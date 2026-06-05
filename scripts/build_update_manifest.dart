import 'dart:convert';
import 'dart:io';

/// 从 pubspec.yaml 读取版本号，例如 "0.1.3+103" → version="0.1.3", buildNumber=103
(int, String) _parsePubspecVersion(String pubspecContent) {
  final versionLine = pubspecContent
      .split('\n')
      .firstWhere((line) => line.startsWith('version:'));
  final value = versionLine.substring('version:'.length).trim();
  final parts = value.split('+');
  final version = parts.first;
  final buildNumber = parts.length > 1 ? int.tryParse(parts[1]) ?? 100 : 100;
  return (buildNumber, version);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart scripts/build_update_manifest.dart <tag> [assetsDir]',
    );
    exit(64);
  }

  final version = args.first;
  final assetsDir = args.length > 1 ? Directory(args[1]) : Directory.current;
  final tag = version.startsWith('v') ? version : 'v$version';
  final cleanVersion = version.replaceFirst('v', '');
  final minimumRequiredVersion = Platform
      .environment['MINIMUM_REQUIRED_VERSION']
      ?.trim();
  final notesEnv = Platform.environment['RELEASE_NOTES']?.trim();
  // GitHub 镜像站前缀（用于生成备用下载链接）
  final ghMirrorPrefix = Platform.environment['GH_MIRROR_PREFIX']?.trim();

  // 从 pubspec.yaml 读取 buildNumber
  final pubspecFile = File('apps/client/pubspec.yaml');
  int buildNumber = 100;
  if (pubspecFile.existsSync()) {
    final (bn, pubspecVersion) = _parsePubspecVersion(
      pubspecFile.readAsStringSync(),
    );
    if (pubspecVersion != cleanVersion) {
      stderr.writeln(
        'Release tag $tag does not match apps/client/pubspec.yaml version $pubspecVersion',
      );
      exit(65);
    }
    buildNumber = bn;
  } else {
    stderr.writeln(
      'Warning: apps/client/pubspec.yaml not found, using buildNumber=100',
    );
  }
  final assets =
      assetsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => !file.path.endsWith('update.json'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  /// 为单个文件构建平台条目（url/assetPath/mirrors/sha256/size）
  Map<String, Object?> _buildAssetEntry(File file, String name) {
    final githubUrl =
        'https://github.com/nontracey/mianshi-zhilian-app/releases/download/$tag/$name';
    final assetPath = '/releases/latest/download/$name';
    final mirrors = <String>[];
    mirrors.add('https://ghfast.top/$githubUrl');
    if (ghMirrorPrefix != null && ghMirrorPrefix.isNotEmpty) {
      mirrors.add('$ghMirrorPrefix/$githubUrl');
    }
    return {
      'url': githubUrl,
      'assetPath': assetPath,
      'mirrors': mirrors,
      'sha256': sha256sum(file),
      'size': file.lengthSync(),
    };
  }

  /// 返回 Android ABI 特有平台条目，同时保留一个 fallback `android` 条目。
  ///
  /// 扫描所有匹配 `-android-{abi}.apk` 的文件，如 arm64-v8a/armeabi-v7a/x86_64/x86。
  /// 旧客户端只看 `android` key 仍能拿到 arm64-v8a APK（主要 ABI）。
  Map<String, Map<String, Object?>> _androidAbiAssets() {
    final result = <String, Map<String, Object?>>{};
    File? primaryFile;
    for (final file in assets.whereType<File>()) {
      final name = file.uri.pathSegments.last;
      final match = RegExp(r'-android-(arm64-v8a|armeabi-v7a|x86_64|x86)\.apk$')
          .firstMatch(name);
      if (match == null) continue;
      final abi = match.group(1)!;
      final key = 'android-$abi';
      result[key] = _buildAssetEntry(file, name);
      if (primaryFile == null) primaryFile = file;
    }
    // fallback：arm64-v8a（如果没有找到任何 APK，用 platformAsset 原逻辑兜底）
    if (primaryFile != null) {
      result['android'] = result['android-arm64-v8a'] ?? result.values.first;
    }
    return result;
  }

  /// 非 Android 平台的单一条目生成（windows/macos/web）。
  Map<String, Object?> platformAsset(String platform) {
    final file = assets.cast<File?>().firstWhere(
      (item) => item!.path.toLowerCase().contains(platform),
      orElse: () => null,
    );
    if (file == null) {
      return {
        'url':
            'https://github.com/nontracey/mianshi-zhilian-app/releases/download/$tag/mianshi-zhilian-$tag-$platform.zip',
        'sha256': '待生成',
        'size': 0,
      };
    }
    final name = file.uri.pathSegments.last;
    return _buildAssetEntry(file, name);
  }

  final manifest = <String, Object?>{
    'version': cleanVersion,
    'buildNumber': buildNumber,
    'releaseDate': DateTime.now().toIso8601String().split('T').first,
    'notes': notesEnv != null && notesEnv.isNotEmpty
        ? notesEnv
              .split('|')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : ['版本更新'],
    'platforms': {
      // Android 优先使用 ABI 特化条目，fallback android 兼容旧客户端
      ..._androidAbiAssets(),
      'windows': platformAsset('windows'),
      'macos': platformAsset('macos'),
      'web': platformAsset('web'),
    },
  };
  if (minimumRequiredVersion != null && minimumRequiredVersion.isNotEmpty) {
    manifest['minimumRequiredVersion'] = minimumRequiredVersion;
  }
  File('${assetsDir.path}/update.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}

String sha256sum(File file) {
  final result = Process.runSync('shasum', ['-a', '256', file.path]);
  if (result.exitCode != 0) {
    throw StateError(
      'Failed to calculate sha256 for ${file.path}: ${result.stderr}',
    );
  }
  return result.stdout.toString().split(RegExp(r'\s+')).first;
}
