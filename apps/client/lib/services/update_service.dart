import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'app_version_service.dart';
import 'endpoint_fallback_client.dart';
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

  const CheckUpdateResult._(this.updateInfo, this.isError);

  /// 发现新版本
  const CheckUpdateResult.hasUpdate(UpdateInfo info) : this._(info, false);

  /// 已是最新版本
  const CheckUpdateResult.noUpdate() : this._(null, false);

  /// 检查失败（网络等原因）
  const CheckUpdateResult.error() : this._(null, true);

  bool get hasUpdate => updateInfo != null;
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

  UpdateService({
    this.updateManifestUrl = '',
    this.customMirrorPrefix,
    EndpointFallbackClient? routeClient,
  }) : _routeClient =
           routeClient ??
           EndpointFallbackClient(
             stateStore: RouteStateStore(StorageService()),
           );

  /// 默认备用镜像站
  static const defaultMirrorPrefix = 'https://ghproxy.com';

  /// 检查是否有新版本
  Future<CheckUpdateResult> checkForUpdate(AppBuildInfo currentVersion) async {
    try {
      final response = await _routeClient.request(
        RouteService.appApi,
        'GET',
        '/update.json',
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        debugPrint('Failed to check update: ${response.statusCode}');
        return const CheckUpdateResult.error();
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final remoteVersion = data['version'] as String? ?? '';

      final remoteBuildNumber = data['buildNumber'] as int? ?? 0;
      if (_isNewerVersion(
        remoteVersion: remoteVersion,
        remoteBuildNumber: remoteBuildNumber,
        localVersion: currentVersion.version,
        localBuildNumber: currentVersion.buildNumber,
      )) {
        return CheckUpdateResult.hasUpdate(UpdateInfo.fromJson(data));
      }

      return const CheckUpdateResult.noUpdate();
    } catch (e) {
      debugPrint('Check update error: $e');
      return const CheckUpdateResult.error();
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
      return updateInfo.platforms['android'];
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
    if (url.contains('github.com')) return 'GitHub';
    if (url.contains('ghproxy.com')) return 'ghproxy.com';
    if (customMirrorPrefix != null && url.startsWith(customMirrorPrefix!)) {
      // 从自定义镜像 URL 中提取域名
      try {
        final uri = Uri.parse(url);
        return uri.host;
      } catch (_) {
        return customMirrorPrefix!;
      }
    }
    // 其他镜像：提取域名
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return url.substring(0, url.length.clamp(0, 30));
    }
  }

  /// 构建下载 URL 列表：官方 Pages/de5 镜像 → GitHub 官方 → 用户自定义镜像 → ghproxy.com → manifest 中的其他镜像
  @visibleForTesting
  List<String> buildDownloadUrlsForTest(PlatformUpdate platformUpdate) {
    return _buildDownloadUrls(platformUpdate);
  }

  List<String> _buildDownloadUrls(PlatformUpdate platformUpdate) {
    final urls = <String>[];

    final officialAssetPath = _officialAssetPath(platformUpdate);
    if (officialAssetPath != null) {
      urls.addAll(
        _routeClient.resolveUrls(RouteService.appWeb, officialAssetPath),
      );
    }

    // GitHub 官方下载
    if (platformUpdate.url.trim().isNotEmpty) {
      urls.add(platformUpdate.url);
    }

    // 2. 用户自定义镜像站（设置中配置的）
    if (customMirrorPrefix != null && customMirrorPrefix!.isNotEmpty) {
      final mirrorUrl =
          '${customMirrorPrefix!.replaceAll(RegExp(r'/+$'), '')}/${platformUpdate.url}';
      if (!urls.contains(mirrorUrl)) {
        urls.add(mirrorUrl);
      }
    }

    // 3. ghproxy.com 默认备用镜像
    final ghproxyUrl = '$defaultMirrorPrefix/${platformUpdate.url}';
    if (!urls.contains(ghproxyUrl)) {
      urls.add(ghproxyUrl);
    }

    // 4. manifest 中的其他镜像
    for (final mirror in platformUpdate.mirrors) {
      if (mirror.trim().isNotEmpty && !urls.contains(mirror)) {
        urls.add(mirror);
      }
    }

    return urls;
  }

  String? _officialAssetPath(PlatformUpdate platformUpdate) {
    final assetPath = platformUpdate.assetPath?.trim();
    if (assetPath != null && assetPath.isNotEmpty) {
      return assetPath.startsWith('/') ? assetPath : '/$assetPath';
    }

    final uri = Uri.tryParse(platformUpdate.url);
    if (uri == null) return null;
    if (uri.host == Uri.parse(RouteResolver.appWebPrimary).host ||
        uri.host == Uri.parse(RouteResolver.appWebBackup).host) {
      return uri.path;
    }
    return null;
  }

  /// 下载更新文件
  /// 返回 (文件路径, 下载结果)，失败时路径为 null
  Future<(String?, DownloadResult)> downloadUpdate({
    required PlatformUpdate platformUpdate,
    required String version,
    DownloadProgressCallback? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final urls = _buildDownloadUrls(platformUpdate);

    if (urls.isEmpty) {
      return (null, DownloadResult.networkError);
    }

    // 获取临时目录
    final tempDir = await getTemporaryDirectory();
    final fileName = 'mianshi-zhilian-v$version.${_getFileExtension()}';
    final filePath = '${tempDir.path}/$fileName';

    for (final url in urls) {
      if (cancelToken?.isCancelled ?? false) {
        return (null, DownloadResult.cancelled);
      }
      final sourceLabel = _sourceLabelFromUrl(url);
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
          return (filePath, DownloadResult.success);
        case _DownloadStatus.cancelled:
          return (null, DownloadResult.cancelled);
        case _DownloadStatus.verificationFailed:
          // 校验失败不重试其他镜像（文件内容可能不同）
          return (null, DownloadResult.verificationFailed);
        case _DownloadStatus.networkError:
          continue;
      }
    }

    // 所有源都失败
    return (null, DownloadResult.networkError);
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

      // 下载文件
      final request = http.Request('GET', Uri.parse(url));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('Download failed from $url: ${response.statusCode}');
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
        await file.delete();
        return _DownloadStatus.verificationFailed;
      }

      return _DownloadStatus.success;
    } on StateError catch (e) {
      debugPrint('Download cancelled: $e');
      try {
        await sink?.close();
      } catch (_) {}
      if (await file.exists()) {
        await file.delete();
      }
      return _DownloadStatus.cancelled;
    } catch (e) {
      debugPrint('Download error from $url: $e');
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
