import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseDate;
  final List<String> notes;
  final Map<String, PlatformUpdate> platforms;

  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseDate,
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
      notes: (json['notes'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      platforms: platforms,
    );
  }
}

class PlatformUpdate {
  final String url;
  final String sha256;
  final int size;

  const PlatformUpdate({
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory PlatformUpdate.fromJson(Map<String, dynamic> json) {
    return PlatformUpdate(
      url: json['url'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

/// 下载进度回调
typedef DownloadProgressCallback = void Function(int received, int total);

class UpdateService {
  final String updateManifestUrl;

  UpdateService({
    this.updateManifestUrl =
        'https://mianshi-zhilian-api.nontracey.workers.dev/update.json',
  });

  /// 检查是否有新版本
  Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    try {
      final response = await http.get(Uri.parse(updateManifestUrl));
      if (response.statusCode != 200) {
        debugPrint('Failed to check update: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final remoteVersion = data['version'] as String? ?? '';

      if (_isNewerVersion(remoteVersion, currentVersion)) {
        return UpdateInfo.fromJson(data);
      }

      return null;
    } catch (e) {
      debugPrint('Check update error: $e');
      return null;
    }
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
  }) async {
    try {
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final fileName = 'mianshi-zhilian-v$version.${_getFileExtension()}';
      final filePath = '${tempDir.path}/$fileName';

      // 下载文件
      final request = http.Request('GET', Uri.parse(platformUpdate.url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        debugPrint('Download failed: ${response.statusCode}');
        return null;
      }

      final file = File(filePath);
      final sink = file.openWrite();
      int received = 0;
      final total = platformUpdate.size;

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      });

      await sink.close();

      // 校验 sha256
      final isValid = await verifySha256(filePath, platformUpdate.sha256);
      if (!isValid) {
        debugPrint('SHA256 verification failed');
        await file.delete();
        return null;
      }

      return filePath;
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
    }
  }

  /// 校验文件的 SHA256
  Future<bool> verifySha256(String filePath, String expectedSha256) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
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
  bool _isNewerVersion(String remote, String local) {
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
      if (r > l) return true;
      if (r < l) return false;
    }

    return false;
  }

  /// 格式化文件大小
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
