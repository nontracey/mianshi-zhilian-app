import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'app_version_service.dart';

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
  final List<String> mirrors;
  final String sha256;
  final int size;

  const PlatformUpdate({
    required this.url,
    this.mirrors = const [],
    required this.sha256,
    required this.size,
  });

  factory PlatformUpdate.fromJson(Map<String, dynamic> json) {
    return PlatformUpdate(
      url: json['url'] as String? ?? '',
      mirrors: (json['mirrors'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      sha256: json['sha256'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

/// 下载进度回调
typedef DownloadProgressCallback = void Function(int received, int total);

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

  UpdateService({
    this.updateManifestUrl = const String.fromEnvironment(
      'UPDATE_MANIFEST_URL',
      defaultValue:
          'https://mianshi-zhilian-api.nontracey.workers.dev/update.json',
    ),
  });

  /// 检查是否有新版本
  Future<UpdateInfo?> checkForUpdate(AppBuildInfo currentVersion) async {
    try {
      final response = await http
          .get(Uri.parse(updateManifestUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('Failed to check update: ${response.statusCode}');
        return null;
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
        return UpdateInfo.fromJson(data);
      }

      return null;
    } catch (e) {
      debugPrint('Check update error: $e');
      return null;
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

  /// 下载更新文件
  /// 返回下载文件的路径，失败返回 null
  Future<String?> downloadUpdate({
    required PlatformUpdate platformUpdate,
    required String version,
    DownloadProgressCallback? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final urls = [
      platformUpdate.url,
      ...platformUpdate.mirrors,
    ].where((url) => url.trim().isNotEmpty).toList();

    if (urls.isEmpty) return null;

    // 获取临时目录
    final tempDir = await getTemporaryDirectory();
    final fileName = 'mianshi-zhilian-v$version.${_getFileExtension()}';
    final filePath = '${tempDir.path}/$fileName';

    for (final url in urls) {
      if (cancelToken?.isCancelled ?? false) return null;
      final downloaded = await _downloadFromUrl(
        url: url,
        filePath: filePath,
        platformUpdate: platformUpdate,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (downloaded) return filePath;
    }

    return null;
  }

  Future<bool> _downloadFromUrl({
    required String url,
    required String filePath,
    required PlatformUpdate platformUpdate,
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
        debugPrint('Download failed: ${response.statusCode}');
        return false;
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
            onProgress?.call(received, total);
          })
          .timeout(const Duration(minutes: 20));

      await sink.close();
      sink = null;

      // 校验 sha256
      final isValid = await verifySha256(filePath, platformUpdate.sha256);
      if (!isValid) {
        debugPrint('SHA256 verification failed');
        await file.delete();
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Download error: $e');
      try {
        await sink?.close();
      } catch (_) {}
      if (await file.exists()) {
        await file.delete();
      }
      return false;
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
