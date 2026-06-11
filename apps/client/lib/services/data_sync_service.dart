import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/user_progress.dart';
import 'app_log_service.dart';
import 'storage_service.dart';

class DataSyncService {
  DataSyncService(this._storage);

  final StorageService _storage;
  Timer? _timer;
  bool _running = false;
  Future<void> Function()? onDataImported;

  static const _fileName = 'sync-state.json';
  static const _timeout = Duration(seconds: 30);
  static const _uploadTimeout = Duration(seconds: 120);

  // ETag from last WebDAV GET; sent as If-Match on next PUT to detect concurrent writes.
  String? _webDavEtag;
  // True when the last GET returned 404 (remote file absent): the next PUT sends
  // If-None-Match:* so two devices creating the file simultaneously don't overwrite.
  bool _webDavRemoteAbsent = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncIfNeeded();
    });
    Future.microtask(syncIfNeeded);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<SyncResult> syncIfNeeded({bool force = false}) async {
    final settings = await _storage.loadSyncSettings();
    if (!_shouldAutoSync(settings, force: force)) {
      return SyncResult.success('local_mode');
    }
    final hasDirty = await _storage.hasSyncDirty();
    final lastSyncAt = settings.lastSyncAt;
    final minInterval = Duration(
      minutes: settings.autoSyncIntervalMinutes.clamp(1, 1440),
    );
    final intervalDue =
        lastSyncAt == null ||
        DateTime.now().difference(lastSyncAt) >= minInterval;
    if (!force && !hasDirty && !intervalDue) {
      return SyncResult.success('sync_waiting_interval');
    }
    if (!force && !hasDirty && intervalDue) {
      return pullRemote(settings);
    }
    return syncNow(settings);
  }

  Future<SyncResult> syncNow([SyncSettings? explicitSettings]) async {
    if (_running) return SyncResult.failure('sync_already_running');
    final settings = explicitSettings ?? await _storage.loadSyncSettings();
    final channel = _channelFor(settings);
    if (!_shouldAutoSync(settings, force: true) || channel == null) {
      return SyncResult.success('local_mode');
    }

    _running = true;
    try {
      // 记录导出前的 dirty 时间戳，用于检测上传/下载窗口期是否有新本地改动。
      final dirtyAtBefore = await _storage.getSyncDirtyAt();
      final localPackage = await _storage.exportSyncPackage(settings);
      final remotePackage = await channel.download();
      final mergedPackage = _storage.sanitizeSyncPackage(
        _mergePackages(localPackage, remotePackage),
        settings,
      );
      await _uploadWithConflictRetry(
        channel,
        settings,
        localPackage,
        mergedPackage,
      );
      // 上传期间（最长 120s）用户可能新增了练习记录。导入前把合并包与「当前
      // 最新本地状态」再合并一次（本地优先），避免窗口期新数据被旧快照覆盖丢失。
      final latestLocalPackage = await _storage.exportSyncPackage(settings);
      final importPackage = _storage.sanitizeSyncPackage(
        _mergePackages(latestLocalPackage, mergedPackage),
        settings,
      );
      await _storage.importSyncPackage(
        importPackage,
        syncSettings: settings,
        preserveLocalSensitiveData: true,
      );
      // 仅当窗口期没有新的本地改动时才清 dirty；否则保留，下次同步上传新数据。
      final dirtyAtAfter = await _storage.getSyncDirtyAt();
      if (dirtyAtAfter == dirtyAtBefore) {
        await _storage.clearSyncDirty();
      }
      await _storage.setLastSyncTime(DateTime.now());
      await _storage.saveSyncSettings(
        settings.copyWith(
          lastSyncAt: DateTime.now(),
          lastSyncStatus: 'sync_success',
        ),
      );
      await onDataImported?.call();
      return SyncResult.success('sync_success');
    } catch (e) {
      debugPrint('Data sync failed: $e');
      unawaited(
        AppLog.warning(
          'Data sync failed: ${settings.method}',
          source: 'data_sync',
          error: e,
        ),
      );
      await _storage.saveSyncSettings(
        settings.copyWith(lastSyncStatus: 'sync_failed'),
      );
      return SyncResult.failure('sync_failed', {'error': '$e'});
    } finally {
      _running = false;
    }
  }

  Future<SyncResult> pullRemote([SyncSettings? explicitSettings]) async {
    if (_running) return SyncResult.failure('sync_already_running');
    final settings = explicitSettings ?? await _storage.loadSyncSettings();
    final channel = _channelFor(settings);
    if (!_shouldAutoSync(settings, force: true) || channel == null) {
      return SyncResult.success('local_mode');
    }
    _running = true;
    try {
      final remotePackage = await channel.download();
      if (remotePackage != null) {
        // 拉取也必须走合并而非直接覆盖：否则定时 pull 会用远端整盘覆盖本地，
        // 把拉取等待期间用户新增的练习删掉，并反向冲掉本设备偏好（违反 local-first）。
        final localPackage = await _storage.exportSyncPackage(settings);
        final importPackage = _storage.sanitizeSyncPackage(
          _mergePackages(localPackage, remotePackage),
          settings,
        );
        await _storage.importSyncPackage(
          importPackage,
          syncSettings: settings,
          preserveLocalSensitiveData: true,
        );
        await onDataImported?.call();
      }
      await _storage.saveSyncSettings(
        settings.copyWith(
          lastSyncAt: DateTime.now(),
          lastSyncStatus: remotePackage == null
              ? 'sync_no_changes'
              : 'sync_pull_success',
        ),
      );
      return SyncResult.success(
        remotePackage == null ? 'sync_no_changes' : 'sync_pull_success',
      );
    } catch (e) {
      debugPrint('Data sync pull failed: $e');
      unawaited(
        AppLog.warning(
          'Data sync pull failed: ${settings.method}',
          source: 'data_sync',
          error: e,
        ),
      );
      await _storage.saveSyncSettings(
        settings.copyWith(lastSyncStatus: 'sync_failed'),
      );
      return SyncResult.failure('sync_failed', {'error': '$e'});
    } finally {
      _running = false;
    }
  }

  Future<SyncResult> restoreFromRemote([SyncSettings? explicitSettings]) async {
    final settings = explicitSettings ?? await _storage.loadSyncSettings();
    final channel = _channelFor(settings);
    if (!_shouldAutoSync(settings, force: true) || channel == null) {
      return SyncResult.failure('sync_method_not_restorable');
    }
    try {
      final remotePackage = await channel.download();
      if (remotePackage == null) {
        return SyncResult.failure('remote_sync_file_missing');
      }
      await _storage.importSyncPackage(
        _storage.sanitizeSyncPackage(remotePackage, settings),
        syncSettings: settings,
        preserveLocalSensitiveData: false,
      );
      await _storage.clearSyncDirty();
      await _storage.saveSyncSettings(
        settings.copyWith(
          lastSyncAt: DateTime.now(),
          lastSyncStatus: 'sync_restore_complete',
        ),
      );
      await onDataImported?.call();
      return SyncResult.success('sync_restore_complete');
    } catch (e) {
      unawaited(
        AppLog.error(
          'Data sync restore failed: ${settings.method}',
          source: 'data_sync',
          error: e,
        ),
      );
      return SyncResult.failure('restore_error', {'error': '$e'});
    }
  }

  Future<SyncResult> testConnection([SyncSettings? explicitSettings]) async {
    final settings = explicitSettings ?? await _storage.loadSyncSettings();
    final channel = _channelFor(settings);
    if (!_shouldAutoSync(settings, force: true) || channel == null) {
      return SyncResult.success('local_mode');
    }
    try {
      await channel.testConnection();
      return SyncResult.success('connection_success');
    } catch (e) {
      unawaited(
        AppLog.warning(
          'Data sync connection test failed: ${settings.method}',
          source: 'data_sync',
          error: e,
        ),
      );
      return SyncResult.failure('connection_failed_with_error', {
        'error': '$e',
      });
    }
  }

  bool _shouldAutoSync(SyncSettings settings, {required bool force}) {
    if (!settings.isAutomaticMethod) return false;
    if (!force && !settings.autoSyncEnabled) return false;
    return true;
  }

  _SyncChannel? _channelFor(SyncSettings settings) {
    switch (settings.method) {
      case 'webdav':
        return _SyncChannel(
          download: () => _downloadWebDav(settings),
          upload: (package) => _uploadWebDav(settings, package),
          testConnection: () => _testWebDavConnection(settings),
        );
      case 'github':
        return _SyncChannel(
          download: () => _downloadGitHub(settings),
          upload: (package) => _uploadGitHub(settings, package),
          testConnection: () => _testGitHubConnection(settings),
        );
      case 'gitee':
        return _SyncChannel(
          download: () => _downloadGitee(settings),
          upload: (package) => _uploadGitee(settings, package),
          testConnection: () => _testGiteeConnection(settings),
        );
      default:
        return null;
    }
  }

  Future<void> _uploadWithConflictRetry(
    _SyncChannel channel,
    SyncSettings settings,
    Map<String, dynamic> localPackage,
    Map<String, dynamic> mergedPackage,
  ) async {
    try {
      await channel.upload(mergedPackage);
    } on SyncConflictException {
      final latestRemotePackage = await channel.download();
      final retryPackage = _storage.sanitizeSyncPackage(
        _mergePackages(localPackage, latestRemotePackage),
        settings,
      );
      await channel.upload(retryPackage);
      mergedPackage
        ..clear()
        ..addAll(retryPackage);
    }
  }

  Future<Map<String, dynamic>?> _downloadWebDav(SyncSettings settings) async {
    _require(settings.webDavUrl.isNotEmpty, '缺少 WebDAV 地址');
    final base = _normalizeUrl(settings.webDavUrl);
    final uri = Uri.parse('$base/$_fileName');
    final response = await _webDavRequest('GET', uri, settings);
    if (response.statusCode == 404) {
      _webDavEtag = null;
      _webDavRemoteAbsent = true;
      return null;
    }
    _ensureSuccess(response, 'WebDAV 下载失败');
    _webDavEtag = response.headers['etag'];
    _webDavRemoteAbsent = false;
    return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> _uploadWebDav(
    SyncSettings settings,
    Map<String, dynamic> package,
  ) async {
    _require(settings.webDavUrl.isNotEmpty, '缺少 WebDAV 地址');
    _require(settings.webDavUsername.isNotEmpty, '缺少 WebDAV 用户名');
    _require(settings.webDavPassword.isNotEmpty, '缺少 WebDAV 应用密码');
    final base = _normalizeUrl(settings.webDavUrl);
    final uri = Uri.parse('$base/$_fileName');
    final etag = _webDavEtag;
    // 优先 If-Match（已知 ETag）；远端确认不存在时用 If-None-Match:* 防止
    // 两设备首次同步互相覆盖；状态未知时不带前置条件（保持兼容）。
    final Map<String, String>? preconditionHeaders = etag != null
        ? {'If-Match': etag}
        : _webDavRemoteAbsent
            ? {'If-None-Match': '*'}
            : null;
    final response = await _webDavRequest(
      'PUT',
      uri,
      settings,
      body: const JsonEncoder.withIndent('  ').convert(package),
      headers: preconditionHeaders,
    );
    if (response.statusCode == 412) {
      // 前置条件失败：另一设备已写入（If-Match 时被改、If-None-Match 时被创建）。
      // 重置状态并抛出冲突，由 _uploadWithConflictRetry 重新下载合并后重试。
      _webDavEtag = null;
      _webDavRemoteAbsent = false;
      throw const SyncConflictException();
    }
    _ensureSuccess(response, 'WebDAV 上传失败');
    // 上传成功后远端文件必然存在；按服务器返回更新 ETag。
    _webDavRemoteAbsent = false;
    final newEtag = response.headers['etag'];
    if (newEtag != null) _webDavEtag = newEtag;
  }

  Future<void> _testWebDavConnection(SyncSettings settings) async {
    _require(settings.webDavUrl.isNotEmpty, '缺少 WebDAV 地址');
    _require(settings.webDavUsername.isNotEmpty, '缺少 WebDAV 用户名');
    _require(settings.webDavPassword.isNotEmpty, '缺少 WebDAV 应用密码');
    final base = _normalizeUrl(settings.webDavUrl);
    final response = await _webDavRequest(
      'PROPFIND',
      Uri.parse(base),
      settings,
      headers: {'Depth': '0'},
    );
    _ensureSuccess(response, 'WebDAV 连接测试失败');
  }

  Future<http.Response> _webDavRequest(
    String method,
    Uri uri,
    SyncSettings settings, {
    String? body,
    Map<String, String>? headers,
  }) async {
    final request = http.Request(method, uri)
      ..headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${settings.webDavUsername}:${settings.webDavPassword}'))}';
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = body;
    }
    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(_timeout);
      return http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>?> _downloadGitHub(SyncSettings settings) async {
    _validateRepoSettings(
      token: settings.githubToken,
      owner: settings.githubOwner,
      repo: settings.githubRepo,
      path: settings.githubPath,
      label: 'GitHub',
    );
    final uri = Uri.https(
      'api.github.com',
      '/repos/${settings.githubOwner}/${settings.githubRepo}/contents/${settings.githubPath}',
      {'ref': settings.githubBranch},
    );
    final response = await http
        .get(uri, headers: _githubHeaders(settings))
        .timeout(_timeout);
    if (response.statusCode == 404) return null;
    _ensureSuccess(response, 'GitHub 下载失败');
    final body = json.decode(response.body) as Map<String, dynamic>;
    final content = (body['content'] as String).replaceAll('\n', '');
    return json.decode(utf8.decode(base64Decode(content)))
        as Map<String, dynamic>;
  }

  Future<void> _uploadGitHub(
    SyncSettings settings,
    Map<String, dynamic> package,
  ) async {
    _validateRepoSettings(
      token: settings.githubToken,
      owner: settings.githubOwner,
      repo: settings.githubRepo,
      path: settings.githubPath,
      label: 'GitHub',
    );
    final uri = Uri.https(
      'api.github.com',
      '/repos/${settings.githubOwner}/${settings.githubRepo}/contents/${settings.githubPath}',
    );
    final existing = await http
        .get(
          uri.replace(queryParameters: {'ref': settings.githubBranch}),
          headers: _githubHeaders(settings),
        )
        .timeout(_timeout);
    String? sha;
    if (existing.statusCode >= 200 && existing.statusCode < 300) {
      sha =
          (json.decode(existing.body) as Map<String, dynamic>)['sha']
              as String?;
    } else if (existing.statusCode != 404) {
      _ensureSuccess(existing, 'GitHub 读取远端版本失败');
    }
    final payload = <String, dynamic>{
      'message': 'chore: sync mianshi zhilian data',
      'content': base64Encode(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(package)),
      ),
      'branch': settings.githubBranch,
    };
    if (sha != null) payload['sha'] = sha;
    final response = await http
        .put(uri, headers: _githubHeaders(settings), body: json.encode(payload))
        .timeout(_timeout);
    if (response.statusCode == 409) throw const SyncConflictException();
    _ensureSuccess(response, 'GitHub 上传失败');
  }

  Future<void> _testGitHubConnection(SyncSettings settings) async {
    _validateRepoSettings(
      token: settings.githubToken,
      owner: settings.githubOwner,
      repo: settings.githubRepo,
      path: settings.githubPath,
      label: 'GitHub',
    );
    final repoUri = Uri.https(
      'api.github.com',
      '/repos/${settings.githubOwner}/${settings.githubRepo}',
    );
    final repoResponse = await http
        .get(repoUri, headers: _githubHeaders(settings))
        .timeout(_timeout);
    _ensureSuccess(repoResponse, 'GitHub 仓库连接测试失败');

    final branchUri = Uri.https(
      'api.github.com',
      '/repos/${settings.githubOwner}/${settings.githubRepo}/branches/${settings.githubBranch}',
    );
    final branchResponse = await http
        .get(branchUri, headers: _githubHeaders(settings))
        .timeout(_timeout);
    _ensureSuccess(branchResponse, 'GitHub 分支连接测试失败');
  }

  Map<String, String> _githubHeaders(SyncSettings settings) => {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer ${settings.githubToken}',
    'X-GitHub-Api-Version': '2022-11-28',
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>?> _downloadGitee(SyncSettings settings) async {
    _validateRepoSettings(
      token: settings.giteeToken,
      owner: settings.giteeOwner,
      repo: settings.giteeRepo,
      path: settings.giteePath,
      label: 'Gitee',
    );
    final uri = Uri.https(
      'gitee.com',
      '/api/v5/repos/${settings.giteeOwner}/${settings.giteeRepo}/contents/${settings.giteePath}',
      {'access_token': settings.giteeToken, 'ref': settings.giteeBranch},
    );
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode == 404) return null;
    _ensureSuccess(response, 'Gitee 下载失败');
    final raw = json.decode(response.body);
    if (raw is! Map<String, dynamic>) return null;
    final content = (raw['content'] as String).replaceAll('\n', '');
    return json.decode(utf8.decode(base64Decode(content)))
        as Map<String, dynamic>;
  }

  Future<void> _uploadGitee(
    SyncSettings settings,
    Map<String, dynamic> package,
  ) async {
    _validateRepoSettings(
      token: settings.giteeToken,
      owner: settings.giteeOwner,
      repo: settings.giteeRepo,
      path: settings.giteePath,
      label: 'Gitee',
    );
    final uri = Uri.https(
      'gitee.com',
      '/api/v5/repos/${settings.giteeOwner}/${settings.giteeRepo}/contents/${settings.giteePath}',
    );
    final existing = await http
        .get(
          uri.replace(
            queryParameters: {
              'access_token': settings.giteeToken,
              'ref': settings.giteeBranch,
            },
          ),
        )
        .timeout(_timeout);
    String? sha;
    if (existing.statusCode >= 200 && existing.statusCode < 300) {
      final body = json.decode(existing.body);
      if (body is Map<String, dynamic>) {
        sha = body['sha'] as String?;
      }
    } else if (existing.statusCode != 404) {
      _ensureSuccess(existing, 'Gitee 读取远端版本失败');
    }
    final body = <String, dynamic>{
      'access_token': settings.giteeToken,
      'message': 'chore: sync mianshi zhilian data',
      'content': base64Encode(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(package)),
      ),
      'branch': settings.giteeBranch,
    };
    if (sha != null) body['sha'] = sha;
    final response = sha == null
        ? await http
            .post(
              uri.replace(queryParameters: {'access_token': settings.giteeToken}),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(body),
            )
            .timeout(_uploadTimeout)
        : await http
            .put(
              uri.replace(queryParameters: {'access_token': settings.giteeToken}),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(body),
            )
            .timeout(_uploadTimeout);
    if (response.statusCode == 409) throw const SyncConflictException();
    _ensureSuccess(response, 'Gitee 上传失败');
  }

  Future<void> _testGiteeConnection(SyncSettings settings) async {
    _validateRepoSettings(
      token: settings.giteeToken,
      owner: settings.giteeOwner,
      repo: settings.giteeRepo,
      path: settings.giteePath,
      label: 'Gitee',
    );
    final repoUri = Uri.https(
      'gitee.com',
      '/api/v5/repos/${settings.giteeOwner}/${settings.giteeRepo}',
      {'access_token': settings.giteeToken},
    );
    final repoResponse = await http.get(repoUri).timeout(_timeout);
    _ensureSuccess(repoResponse, 'Gitee 仓库连接测试失败');

    final branchUri = Uri.https(
      'gitee.com',
      '/api/v5/repos/${settings.giteeOwner}/${settings.giteeRepo}/branches/${settings.giteeBranch}',
      {'access_token': settings.giteeToken},
    );
    final branchResponse = await http.get(branchUri).timeout(_timeout);
    _ensureSuccess(branchResponse, 'Gitee 分支连接测试失败');
  }

  /// 测试入口：暴露合并逻辑以验证 LWW + 删除墓碑的端到端行为。
  @visibleForTesting
  Map<String, dynamic> mergePackagesForTest(
    Map<String, dynamic> local,
    Map<String, dynamic>? remote,
  ) =>
      _mergePackages(local, remote);

  Map<String, dynamic> _mergePackages(
    Map<String, dynamic> local,
    Map<String, dynamic>? remote,
  ) {
    if (remote == null) return local;
    final localData = Map<String, dynamic>.from(local['data'] as Map);
    final remoteData = Map<String, dynamic>.from(remote['data'] as Map);
    // learning_scope, selected_route_id, disabled_domains, settings 等
    // 通过 {...remoteData, ...localData} 得到 local-wins，
    // 每个设备保持自己的偏好，不跨设备同步。
    final merged = <String, dynamic>{...remoteData, ...localData};

    // prep_plan / local_profile 是应跨设备收敛的单例：按 updatedAt 取较新者，
    // 否则 local-wins 会让一台设备的修改永远传不到另一台。
    for (final key in ['prep_plan', 'local_profile']) {
      final picked = _pickByUpdatedAt(remoteData[key], localData[key]);
      if (picked != null) {
        merged[key] = picked;
      } else {
        merged.remove(key);
      }
    }

    // 合并删除墓碑：取两侧各 id 的较晚时间戳，并 GC 60 天以上的旧墓碑。
    final mergedDeletions = _mergeDeletions(
      remoteData['deletions'],
      localData['deletions'],
    );
    if (mergedDeletions.isNotEmpty) {
      merged['deletions'] = mergedDeletions;
    } else {
      merged.remove('deletions');
    }

    merged['progress_map'] = mergeProgressMaps(
      remoteData['progress_map'],
      localData['progress_map'],
      mergedDeletions,
    );
    for (final key in [
      'practice_attempts',
      'sessions',
      'mock_interview_sessions',
      'project_library',
      'project_dig_projects',
      'custom_routes',
    ]) {
      merged[key] = _mergeListById(remoteData[key], localData[key], mergedDeletions, key);
    }
    merged['answer_versions'] = _mergeAnswerVersions(
      remoteData['answer_versions'],
      localData['answer_versions'],
    );

    return {
      'schemaVersion': 1,
      'app': 'mianshi-zhilian',
      'updatedAt': DateTime.now().toIso8601String(),
      'deviceId': local['deviceId'],
      if ((local['contentEnv'] ?? remote['contentEnv']) != null)
        'contentEnv': local['contentEnv'] ?? remote['contentEnv'],
      if ((local['contentVersion'] ?? remote['contentVersion']) != null)
        'contentVersion': local['contentVersion'] ?? remote['contentVersion'],
      'data': merged..removeWhere((_, value) => value == null),
    };
  }

  /// 单例对象按 `updatedAt` 取较新者；任一侧缺失时返回另一侧；时间戳缺失或
  /// 并列时本地优先。
  dynamic _pickByUpdatedAt(dynamic remote, dynamic local) {
    if (remote == null) return local;
    if (local == null) return remote;
    final remoteTs =
        remote is Map ? DateTime.tryParse('${remote['updatedAt'] ?? ''}') : null;
    final localTs =
        local is Map ? DateTime.tryParse('${local['updatedAt'] ?? ''}') : null;
    if (remoteTs == null) return local;
    if (localTs == null) return remote;
    return !localTs.isBefore(remoteTs) ? local : remote;
  }

  /// 合并两侧 progress_map：按 `lastPracticeAt` 做 last-write-wins（取最近一次
  /// 练习的版本），与其它集合的 LWW 口径一致——诚实反映"最近一次练习"，而非
  /// 保留历史最高分。`practiceCount` 取两侧较大值（单调计数不回退）；时间戳缺失
  /// 或并列时遵循本地优先。
  ///
  /// [deletions] 为已合并的墓碑表。`progress_map:<topicId>` 墓碑表示该知识点进度
  /// 被主动清空（如「清空练习数据」）；若该 topic 的 `lastPracticeAt <= deletedAt`
  /// （或缺失）则剔除，避免清空后从远端并集复活。删除后重新练习（更晚的
  /// lastPracticeAt）会正常保留。
  @visibleForTesting
  static Map<String, dynamic> mergeProgressMaps(
    dynamic remote,
    dynamic local, [
    Map<String, String> deletions = const {},
  ]) {
    final result = <String, dynamic>{};
    if (remote is Map) {
      result.addAll(remote.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (local is Map) {
      for (final entry in local.entries) {
        final topicId = entry.key.toString();
        final localProgress = entry.value;
        final remoteProgress = result[topicId];
        if (localProgress is! Map || remoteProgress is! Map) {
          // 任一侧缺失或非 Map：本地优先。
          result[topicId] = localProgress;
          continue;
        }

        final localTs =
            DateTime.tryParse('${localProgress['lastPracticeAt'] ?? ''}');
        final remoteTs =
            DateTime.tryParse('${remoteProgress['lastPracticeAt'] ?? ''}');
        final Map winner;
        if (remoteTs == null) {
          winner = localProgress; // 远端无时间戳 → 本地胜
        } else if (localTs == null) {
          winner = remoteProgress; // 本地无时间戳但远端有 → 远端胜
        } else {
          // 相同时间本地优先（!isBefore 即 local >= remote）。
          winner = !localTs.isBefore(remoteTs) ? localProgress : remoteProgress;
        }

        final maxPractice = [
          (remoteProgress['practiceCount'] as num?)?.toInt() ?? 0,
          (localProgress['practiceCount'] as num?)?.toInt() ?? 0,
        ].reduce((a, b) => a > b ? a : b);

        result[topicId] = {...winner, 'practiceCount': maxPractice};
      }
    }

    if (deletions.isNotEmpty) {
      result.removeWhere((topicId, progress) {
        final deletedAt = deletions['progress_map:$topicId'];
        if (deletedAt == null) return false;
        if (progress is! Map) return true;
        final ts = progress['lastPracticeAt'] as String?;
        if (ts == null) return true;
        return deletedAt.compareTo(ts) >= 0;
      });
    }
    return result;
  }

  /// 通用列表合并：LWW（按 updatedAt 取较新者，本地同 updatedAt 时优先）+ 墓碑过滤。
  ///
  /// [deletions] 是已合并的墓碑表 `{<collection>:<id>: <deletedAt ISO>}`。
  /// 若某条目的 `updatedAt <= deletedAt`（或无 `updatedAt`），则视为已删除而剔除。
  /// 删除后若有意重新创建（`updatedAt > deletedAt`），该条目正常保留。
  List<dynamic>? _mergeListById(
    dynamic remote,
    dynamic local,
    Map<String, String> deletions,
    String collectionKey,
  ) {
    if (remote == null && local == null) return null;
    final byId = <String, dynamic>{};

    // remote 先写，local 后写（local 同 updatedAt 时覆盖 remote，即本地优先）
    void addAll(dynamic value) {
      if (value is! List) return;
      for (final item in value) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        if (id == null) {
          byId['_anon_${byId.length}'] = item;
          continue;
        }
        final existing = byId[id];
        if (existing == null) {
          byId[id] = item;
        } else {
          // LWW: 保留 updatedAt 较晚的；相同时 local 覆盖（remote 先写则 local 会覆盖）
          final existingAt = (existing as Map)['updatedAt'] as String?;
          final itemAt = item['updatedAt'] as String?;
          if (existingAt == null ||
              (itemAt != null && itemAt.compareTo(existingAt) >= 0)) {
            byId[id] = item;
          }
        }
      }
    }

    addAll(remote);
    addAll(local);

    // 应用墓碑：deletedAt >= item.updatedAt 时判定已删除
    if (deletions.isNotEmpty) {
      byId.removeWhere((id, item) {
        if (id.startsWith('_anon_')) return false;
        final deletedAt = deletions['$collectionKey:$id'];
        if (deletedAt == null) return false;
        final itemUpdatedAt = (item as Map)['updatedAt'] as String?;
        if (itemUpdatedAt == null) return true;
        return deletedAt.compareTo(itemUpdatedAt) >= 0;
      });
    }

    return byId.values.toList();
  }

  /// 合并两侧墓碑表：每个 id 取较晚的 deletedAt；同时 GC 60 天以上的旧条目。
  Map<String, String> _mergeDeletions(dynamic remote, dynamic local) {
    final result = <String, String>{};

    void addAll(dynamic value) {
      if (value is! Map) return;
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final ts = entry.value.toString();
        final existing = result[key];
        if (existing == null || ts.compareTo(existing) > 0) {
          result[key] = ts;
        }
      }
    }

    addAll(remote);
    addAll(local);

    // GC: 移除超过 60 天的旧墓碑（所有设备理应已同步过）
    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    result.removeWhere((_, value) {
      final dt = DateTime.tryParse(value);
      return dt != null && dt.isBefore(cutoff);
    });

    return result;
  }

  Map<String, dynamic>? _mergeAnswerVersions(dynamic remote, dynamic local) {
    if (remote == null && local == null) return null;
    final result = <String, dynamic>{};
    if (remote is Map) {
      result.addAll(remote.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (local is Map) {
      for (final entry in local.entries) {
        result[entry.key.toString()] = _mergeVersionList(
          result[entry.key.toString()],
          entry.value,
        );
      }
    }
    return result;
  }

  List<dynamic> _mergeVersionList(dynamic remote, dynamic local) {
    final seen = <String>{};
    final result = <dynamic>[];
    void addAll(dynamic value) {
      if (value is! List) return;
      for (final item in value) {
        final key = item is Map
            ? '${item['type']}|${item['content']}|${item['createdAt']}'
            : item.toString();
        if (seen.add(key)) result.add(item);
      }
    }

    addAll(remote);
    addAll(local);
    return result;
  }

  void _validateRepoSettings({
    required String token,
    required String owner,
    required String repo,
    required String path,
    required String label,
  }) {
    _require(token.isNotEmpty, '缺少 $label token');
    _require(owner.isNotEmpty, '缺少 $label owner');
    _require(repo.isNotEmpty, '缺少 $label repo');
    _require(path.isNotEmpty, '缺少 $label 同步文件路径');
  }

  String _normalizeUrl(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

  void _require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  void _ensureSuccess(http.Response response, String message) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw StateError('$message: HTTP ${response.statusCode}');
  }
}

class SyncResult {
  final bool success;
  final String l10nKey;
  final Map<String, String> params;

  const SyncResult._(this.success, this.l10nKey, this.params);

  factory SyncResult.success(String key, [Map<String, String>? params]) =>
      SyncResult._(true, key, params ?? const {});

  factory SyncResult.failure(String key, [Map<String, String>? params]) =>
      SyncResult._(false, key, params ?? const {});
}

class SyncConflictException implements Exception {
  const SyncConflictException();
}

class _SyncChannel {
  const _SyncChannel({
    required this.download,
    required this.upload,
    required this.testConnection,
  });

  final Future<Map<String, dynamic>?> Function() download;
  final Future<void> Function(Map<String, dynamic> package) upload;
  final Future<void> Function() testConnection;
}
