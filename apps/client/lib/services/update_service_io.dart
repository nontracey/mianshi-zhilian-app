import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log_service.dart';
import 'app_version_service.dart';
import 'download_source_resolver.dart';
import 'endpoint_fallback_client.dart';
import 'on_device_stt/runtime_platform.dart';
import 'route_resolver.dart';
import 'route_state_store.dart';
import 'storage_service.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseDate;
  final String minimumRequiredVersion;
  final List<String> notes;
  final Map<String, PlatformUpdate> platforms;

  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseDate,
    required this.minimumRequiredVersion,
    required this.notes,
    required this.platforms,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final platforms = <String, PlatformUpdate>{};
    final platformsJson = json['platforms'] as Map<String, dynamic>? ?? {};
    for (final entry in platformsJson.entries) {
      platforms[entry.key] = PlatformUpdate.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    return UpdateInfo(
      version: json['version'] as String? ?? '',
      buildNumber: json['buildNumber'] as int? ?? 0,
      releaseDate: json['releaseDate'] as String? ?? '',
      minimumRequiredVersion: json['minimumRequiredVersion'] as String? ?? '',
      notes: (json['notes'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      platforms: platforms,
    );
  }
}

class PlatformUpdate {
  final String url;
  final String? assetPath;
  final List<String> mirrors;
  final String sha256;
  final int size;

  const PlatformUpdate({
    required this.url,
    this.assetPath,
    this.mirrors = const [],
    required this.sha256,
    required this.size,
  });

  factory PlatformUpdate.fromJson(Map<String, dynamic> json) {
    return PlatformUpdate(
      url: json['url'] as String? ?? '',
      assetPath: json['assetPath'] as String?,
      mirrors: (json['mirrors'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      sha256: json['sha256'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

/// 更新检查结果
class CheckUpdateResult {
  final UpdateInfo? updateInfo;
  final bool isError;
  final AppBuildInfo? localVersion;
  final String? remoteVersion;
  final int? remoteBuildNumber;

  const CheckUpdateResult._(
    this.updateInfo,
    this.isError, {
    this.localVersion,
    this.remoteVersion,
    this.remoteBuildNumber,
  });

  /// 发现新版本
  CheckUpdateResult.hasUpdate(UpdateInfo info, {AppBuildInfo? localVersion})
    : this._(
        info,
        false,
        localVersion: localVersion,
        remoteVersion: info.version,
        remoteBuildNumber: info.buildNumber,
      );

  /// 已是最新版本
  const CheckUpdateResult.noUpdate({
    AppBuildInfo? localVersion,
    String? remoteVersion,
    int? remoteBuildNumber,
  }) : this._(
         null,
         false,
         localVersion: localVersion,
         remoteVersion: remoteVersion,
         remoteBuildNumber: remoteBuildNumber,
       );

  /// 检查失败（网络等原因）
  const CheckUpdateResult.error({AppBuildInfo? localVersion})
    : this._(null, true, localVersion: localVersion);

  bool get hasUpdate => updateInfo != null;

  String? get remoteFullVersion {
    final version = remoteVersion;
    final buildNumber = remoteBuildNumber;
    if (version == null || version.isEmpty) return null;
    if (buildNumber == null || buildNumber <= 0) return version;
    return '$version+$buildNumber';
  }
}

/// 下载结果
enum DownloadResult {
  /// 下载成功
  success,

  /// 下载失败 — 网络原因
  networkError,

  /// 下载失败 — 校验不通过
  verificationFailed,

  /// 下载被取消
  cancelled,
}

/// 单次下载源尝试记录
class DownloadAttempt {
  final String url;
  final String sourceLabel;
  final bool reached;
  final int? statusCode;
  final String? errorSummary;

  const DownloadAttempt({
    required this.url,
    required this.sourceLabel,
    required this.reached,
    this.statusCode,
    this.errorSummary,
  });

  /// 用户可读的失败原因
  String get failureReason {
    if (reached) {
      if (statusCode != null && statusCode != 200) {
        return 'HTTP $statusCode';
      }
      return '校验不通过';
    }
    return errorSummary ?? '无法连接';
  }
}

/// 下载进度回调
/// [received] 已下载字节数, [total] 总字节数, [sourceLabel] 当前下载源描述
typedef DownloadProgressCallback =
    void Function(int received, int total, String sourceLabel);

class DownloadCancelToken {
  bool _isCancelled = false;
  http.Client? _client;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
    _client?.close();
  }

  void _bind(http.Client client) {
    if (_isCancelled) {
      client.close();
      return;
    }
    _client = client;
  }

  void _unbind(http.Client client) {
    if (_client == client) {
      _client = null;
    }
  }
}

class UpdateService {
  final String updateManifestUrl;
  final EndpointFallbackClient _routeClient;

  /// 用户自定义的 GitHub 镜像站前缀（如 https://mirror.example.com）
  /// 如果设置了，下载时会优先插入自定义镜像到 mirrors 列表头部
  final String? customMirrorPrefix;

  /// 下载源模式，控制各来源的尝试顺序
  final DownloadSourceMode downloadSourceMode;

  /// 最近一次下载的源尝试记录（供 UI 展示失败详情）
  List<DownloadAttempt> _lastAttempts = [];
  List<DownloadAttempt> get lastAttempts => List.unmodifiable(_lastAttempts);

  UpdateService({
    this.updateManifestUrl = '',
    this.customMirrorPrefix,
    this.downloadSourceMode = DownloadSourceMode.auto,
    EndpointFallbackClient? routeClient,
  }) : _routeClient =
           routeClient ??
           EndpointFallbackClient(
             stateStore: EndpointStateStore(StorageService()),
           );

  /// 检查是否有新版本
  Future<CheckUpdateResult> checkForUpdate(AppBuildInfo currentVersion) async {
    try {
      final response = await _routeClient.request(
        EndpointService.appApi,
        'GET',
        '/update.json',
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        debugPrint('Failed to check update: ${response.statusCode}');
        unawaited(
          AppLog.warning(
            'Check update failed: HTTP ${response.statusCode}',
            source: 'app_update',
          ),
        );
        return CheckUpdateResult.error(localVersion: currentVersion);
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final remoteVersion = data['version'] as String? ?? '';
      final remoteBuildNumber = data['buildNumber'] as int? ?? 0;
      unawaited(
        AppLog.info(
          'Update check local=${currentVersion.fullVersion} '
          'remote=$remoteVersion+$remoteBuildNumber',
          source: 'app_update',
        ),
      );
      if (_isNewerVersion(
        remoteVersion: remoteVersion,
        remoteBuildNumber: remoteBuildNumber,
        localVersion: currentVersion.version,
        localBuildNumber: currentVersion.buildNumber,
      )) {
        return CheckUpdateResult.hasUpdate(
          UpdateInfo.fromJson(data),
          localVersion: currentVersion,
        );
      }

      return CheckUpdateResult.noUpdate(
        localVersion: currentVersion,
        remoteVersion: remoteVersion,
        remoteBuildNumber: remoteBuildNumber,
      );
    } catch (e) {
      debugPrint('Check update error: $e');
      unawaited(
        AppLog.warning('Check update error', source: 'app_update', error: e),
      );
      return CheckUpdateResult.error(localVersion: currentVersion);
    }
  }

  bool isRequiredUpdate(UpdateInfo updateInfo, AppBuildInfo currentVersion) {
    final minimumVersion = updateInfo.minimumRequiredVersion;
    if (minimumVersion.isEmpty) return false;
    return _isVersionGreater(minimumVersion, currentVersion.version);
  }

  /// 获取当前平台的更新信息
  PlatformUpdate? getPlatformUpdate(UpdateInfo updateInfo) {
    if (kIsWeb) {
      return null; // Web 端自动更新，不需要下载
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // 优先按 ABI 特化条目下载（如 android-arm64-v8a），
      // 回退到通用 android 条目兼容旧 update.json
      final abi = currentSherpaOnnxRuntimeArch();
      final abiKey = 'android-$abi';
      return updateInfo.platforms[abiKey] ?? updateInfo.platforms['android'];
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return updateInfo.platforms['macos']; // iOS 暂用 macOS 包
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return updateInfo.platforms['macos'];
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return updateInfo.platforms['windows'];
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return updateInfo.platforms['linux'];
    }

    return null;
  }

  /// 根据 URL 生成用户可读的下载源描述
  String _sourceLabelFromUrl(String url) {
    return DownloadSourceResolver.sourceLabel(
      url,
      customMirrorPrefix: customMirrorPrefix,
    );
  }

  /// 构建下载 URL 列表，按 [downloadSourceMode] 排序
  @visibleForTesting
  List<String> buildDownloadUrlsForTest(PlatformUpdate platformUpdate) {
    return _buildDownloadUrls(platformUpdate);
  }

  List<String> _buildDownloadUrls(PlatformUpdate platformUpdate) {
    final candidates = DownloadSourceResolver.resolve(
      originalUrl: platformUpdate.url.trim(),
      customMirrorPrefix: customMirrorPrefix,
      additionalMirrors: platformUpdate.mirrors
          .where((m) => m.trim().isNotEmpty)
          .toList(),
      mode: downloadSourceMode,
    );
    return candidates.map((c) => c.url).toList();
  }

  /// 下载更新文件
  /// 返回 (文件路径, 下载结果)，失败时路径为 null。
  /// 可通过 [lastAttempts] 获取每个源的尝试详情。
  Future<(String?, DownloadResult)> downloadUpdate({
    required PlatformUpdate platformUpdate,
    required String version,
    DownloadProgressCallback? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    var urls = _buildDownloadUrls(platformUpdate);
    if (downloadSourceMode == DownloadSourceMode.auto) {
      urls = await _orderUrlsByProbeLatency(urls);
    }

    if (urls.isEmpty) {
      _lastAttempts = [];
      return (null, DownloadResult.networkError);
    }

    // 获取临时目录
    final tempDir = await getTemporaryDirectory();
    final fileName = 'mianshi-zhilian-v$version.${_getFileExtension()}';
    final filePath = '${tempDir.path}/$fileName';

    final attempts = <DownloadAttempt>[];
    bool lastVerificationFailed = false;

    for (final url in urls) {
      if (cancelToken?.isCancelled ?? false) {
        _lastAttempts = attempts;
        return (null, DownloadResult.cancelled);
      }
      final sourceLabel = _sourceLabelFromUrl(url);

      // HEAD 预检：快速判断源是否可达，避免等待完整超时
      if (!await _headCheck(url, sourceLabel, attempts, cancelToken)) {
        continue;
      }

      final result = await _downloadFromUrl(
        url: url,
        filePath: filePath,
        platformUpdate: platformUpdate,
        sourceLabel: sourceLabel,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      switch (result) {
        case _DownloadStatus.success:
          // 只记录成功的，前面的失败已在 HEAD 预检中记录
          _lastAttempts = attempts;
          return (filePath, DownloadResult.success);
        case _DownloadStatus.cancelled:
          _lastAttempts = attempts;
          return (null, DownloadResult.cancelled);
        case _DownloadStatus.verificationFailed:
          attempts.add(
            DownloadAttempt(
              url: url,
              sourceLabel: sourceLabel,
              reached: true,
              errorSummary: 'SHA256 校验不通过',
            ),
          );
          lastVerificationFailed = true;
          continue;
        case _DownloadStatus.networkError:
          attempts.add(
            DownloadAttempt(
              url: url,
              sourceLabel: sourceLabel,
              reached: false,
              errorSummary: '下载中断',
            ),
          );
          continue;
      }
    }

    _lastAttempts = attempts;
    // 所有源都失败
    if (lastVerificationFailed) {
      return (null, DownloadResult.verificationFailed);
    }
    return (null, DownloadResult.networkError);
  }

  /// HEAD 预检：快速判断下载源是否可达
  ///
  /// 返回 true 表示可以继续尝试下载，false 表示应跳过该源
  Future<bool> _headCheck(
    String url,
    String sourceLabel,
    List<DownloadAttempt> attempts,
    DownloadCancelToken? cancelToken,
  ) async {
    final client = http.Client();
    cancelToken?._bind(client);
    try {
      final headRequest = http.Request('HEAD', Uri.parse(url));
      final headResponse = await client
          .send(headRequest)
          .timeout(const Duration(seconds: 12));
      cancelToken?._unbind(client);
      client.close();

      if (headResponse.statusCode == 200) {
        return true; // 源可达，继续下载
      }

      // 返回非 200，记录并跳过
      attempts.add(
        DownloadAttempt(
          url: url,
          sourceLabel: sourceLabel,
          reached: true,
          statusCode: headResponse.statusCode,
        ),
      );
      debugPrint('HEAD $sourceLabel → ${headResponse.statusCode}，跳过');
      unawaited(
        AppLog.warning(
          'Update source skipped by HEAD: $sourceLabel '
          'HTTP ${headResponse.statusCode}',
          source: 'app_update',
        ),
      );
      return false;
    } on TimeoutException {
      cancelToken?._unbind(client);
      client.close();
      attempts.add(
        DownloadAttempt(
          url: url,
          sourceLabel: sourceLabel,
          reached: false,
          errorSummary: '连接超时',
        ),
      );
      debugPrint('HEAD $sourceLabel → 超时，跳过');
      unawaited(
        AppLog.warning(
          'Update source HEAD timeout: $sourceLabel',
          source: 'app_update',
        ),
      );
      return false;
    } catch (e) {
      cancelToken?._unbind(client);
      client.close();
      attempts.add(
        DownloadAttempt(
          url: url,
          sourceLabel: sourceLabel,
          reached: false,
          errorSummary: '$e'.length > 60 ? '${'$e'.substring(0, 60)}...' : '$e',
        ),
      );
      debugPrint('HEAD $sourceLabel → $e，跳过');
      unawaited(
        AppLog.warning(
          'Update source HEAD failed: $sourceLabel',
          source: 'app_update',
          error: e,
        ),
      );
      return false;
    }
  }

  Future<List<String>> _orderUrlsByProbeLatency(List<String> urls) async {
    return DownloadSourceResolver.orderByProbeLatency(urls);
  }

  Future<_DownloadStatus> _downloadFromUrl({
    required String url,
    required String filePath,
    required PlatformUpdate platformUpdate,
    String sourceLabel = '',
    DownloadProgressCallback? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final client = http.Client();
    cancelToken?._bind(client);
    final file = File(filePath);
    IOSink? sink;
    try {
      if (await file.exists()) {
        await file.delete();
      }

      // 下载文件（HEAD 预检已确认源可达，缩短连接超时）
      final request = http.Request('GET', Uri.parse(url));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        debugPrint('Download failed from $url: ${response.statusCode}');
        unawaited(
          AppLog.warning(
            'Update download failed: $sourceLabel HTTP ${response.statusCode}',
            source: 'app_update',
          ),
        );
        return _DownloadStatus.networkError;
      }

      sink = file.openWrite();
      int received = 0;
      final total = platformUpdate.size > 0
          ? platformUpdate.size
          : response.contentLength ?? 0;

      await response.stream
          .timeout(
            const Duration(seconds: 45),
            onTimeout: (controller) {
              controller.addError(
                TimeoutException('Download stalled for 45 seconds'),
              );
              controller.close();
            },
          )
          .forEach((chunk) {
            if (cancelToken?.isCancelled ?? false) {
              throw StateError('Download cancelled');
            }
            sink!.add(chunk);
            received += chunk.length;
            onProgress?.call(received, total, sourceLabel);
          })
          .timeout(const Duration(minutes: 20));

      await sink.close();
      sink = null;

      // 校验 sha256
      final isValid = await verifySha256(filePath, platformUpdate.sha256);
      if (!isValid) {
        debugPrint('SHA256 verification failed for $url');
        unawaited(
          AppLog.error(
            'Update SHA256 verification failed: $sourceLabel',
            source: 'app_update',
          ),
        );
        await file.delete();
        return _DownloadStatus.verificationFailed;
      }

      unawaited(
        AppLog.info(
          'Update download completed: $sourceLabel',
          source: 'app_update',
        ),
      );
      return _DownloadStatus.success;
    } on StateError catch (e) {
      debugPrint('Download cancelled: $e');
      unawaited(
        AppLog.info(
          'Update download cancelled: $sourceLabel error=$e',
          source: 'app_update',
        ),
      );
      try {
        await sink?.close();
      } catch (_) {}
      if (await file.exists()) {
        await file.delete();
      }
      return _DownloadStatus.cancelled;
    } catch (e) {
      debugPrint('Download error from $url: $e');
      unawaited(
        AppLog.warning(
          'Update download error: $sourceLabel',
          source: 'app_update',
          error: e,
        ),
      );
      try {
        await sink?.close();
      } catch (_) {}
      if (await file.exists()) {
        await file.delete();
      }
      return _DownloadStatus.networkError;
    } finally {
      cancelToken?._unbind(client);
      client.close();
    }
  }

  /// 启动系统默认安装流程。
  ///
  /// Android 会打开 APK 安装确认，Windows 会启动 EXE 安装器，macOS 会打开 DMG。
  Future<bool> openInstaller(String filePath) async {
    if (kIsWeb) return false;
    final result = await OpenFilex.open(filePath);
    return result.type == ResultType.done;
  }

  /// 校验文件的 SHA256
  Future<bool> verifySha256(String filePath, String expectedSha256) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final digest = await sha256.bind(file.openRead()).first;
      final actualSha256 = digest.toString();

      debugPrint('Expected SHA256: $expectedSha256');
      debugPrint('Actual SHA256: $actualSha256');

      return actualSha256.toLowerCase() == expectedSha256.toLowerCase();
    } catch (e) {
      debugPrint('SHA256 verification error: $e');
      return false;
    }
  }

  /// 获取文件扩展名
  String _getFileExtension() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'apk';
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return 'exe';
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return 'AppImage';
    }
    return 'dmg'; // macOS / iOS
  }

  /// 比较版本号
  bool _isNewerVersion({
    required String remoteVersion,
    required int remoteBuildNumber,
    required String localVersion,
    required int localBuildNumber,
  }) {
    final versionCompare = _compareVersion(remoteVersion, localVersion);
    if (versionCompare > 0) return true;
    if (versionCompare < 0) return false;
    return remoteBuildNumber > localBuildNumber;
  }

  bool _isVersionGreater(String remote, String local) {
    return _compareVersion(remote, local) > 0;
  }

  int _compareVersion(String remote, String local) {
    final remoteParts = remote
        .replaceAll('v', '')
        .split('.')
        .map(int.tryParse)
        .toList();
    final localParts = local
        .replaceAll('v', '')
        .split('.')
        .map(int.tryParse)
        .toList();

    for (var i = 0; i < 3; i++) {
      final r = i < remoteParts.length ? (remoteParts[i] ?? 0) : 0;
      final l = i < localParts.length ? (localParts[i] ?? 0) : 0;
      if (r > l) return 1;
      if (r < l) return -1;
    }

    return 0;
  }

  /// 格式化文件大小
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 下载状态内部枚举
enum _DownloadStatus { success, networkError, verificationFailed, cancelled }
