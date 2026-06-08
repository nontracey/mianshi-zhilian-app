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
      await _storage.importSyncPackage(
        mergedPackage,
        syncSettings: settings,
        preserveLocalSensitiveData: true,
      );
      await _storage.clearSyncDirty();
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
        await _storage.importSyncPackage(
          _storage.sanitizeSyncPackage(remotePackage, settings),
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
    if (response.statusCode == 404) return null;
    _ensureSuccess(response, 'WebDAV 下载失败');
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
    final response = await _webDavRequest(
      'PUT',
      uri,
      settings,
      body: const JsonEncoder.withIndent('  ').convert(package),
    );
    _ensureSuccess(response, 'WebDAV 上传失败');
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

  Map<String, dynamic> _mergePackages(
    Map<String, dynamic> local,
    Map<String, dynamic>? remote,
  ) {
    if (remote == null) return local;
    final localData = Map<String, dynamic>.from(local['data'] as Map);
    final remoteData = Map<String, dynamic>.from(remote['data'] as Map);
    final merged = <String, dynamic>{...remoteData, ...localData};

    merged['progress_map'] = _mergeProgressMap(
      remoteData['progress_map'],
      localData['progress_map'],
    );
    for (final key in [
      'practice_attempts',
      'sessions',
      'mock_interview_sessions',
      'project_library',
      'project_dig_projects',
      'custom_routes',
    ]) {
      merged[key] = _mergeListById(remoteData[key], localData[key]);
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

  Map<String, dynamic> _mergeProgressMap(dynamic remote, dynamic local) {
    final result = <String, dynamic>{};
    if (remote is Map) {
      result.addAll(remote.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (local is Map) {
      for (final entry in local.entries) {
        final topicId = entry.key.toString();
        final localProgress = entry.value;
        final remoteProgress = result[topicId];
        if (localProgress is! Map) {
          result[topicId] = localProgress;
          continue;
        }
        if (remoteProgress is! Map) {
          result[topicId] = localProgress;
          continue;
        }
        final localScore = (localProgress['score'] as num?)?.toInt() ?? 0;
        final remoteScore = (remoteProgress['score'] as num?)?.toInt() ?? 0;
        if (localScore > remoteScore) {
          result[topicId] = localProgress;
        } else if (localScore == remoteScore) {
          result[topicId] = {
            ...remoteProgress,
            ...localProgress,
            'practiceCount': [
              (remoteProgress['practiceCount'] as num?)?.toInt() ?? 0,
              (localProgress['practiceCount'] as num?)?.toInt() ?? 0,
            ].reduce((a, b) => a > b ? a : b),
            'nextReviewAt': _earlierDateString(
              remoteProgress['nextReviewAt'] as String?,
              localProgress['nextReviewAt'] as String?,
            ),
          };
        }
      }
    }
    return result;
  }

  List<dynamic>? _mergeListById(dynamic remote, dynamic local) {
    if (remote == null && local == null) return null;
    final byId = <String, dynamic>{};
    void addAll(dynamic value) {
      if (value is! List) return;
      for (final item in value) {
        if (item is Map && item['id'] != null) {
          byId[item['id'].toString()] = item;
        } else {
          byId['idx_${byId.length}'] = item;
        }
      }
    }

    addAll(remote);
    addAll(local);
    return byId.values.toList();
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

  String? _earlierDateString(String? a, String? b) {
    if (a == null || a.isEmpty) return b;
    if (b == null || b.isEmpty) return a;
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null) return b;
    if (db == null) return a;
    return da.isBefore(db) ? a : b;
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
