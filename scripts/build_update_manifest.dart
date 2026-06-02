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
    return {
      'url':
          'https://github.com/nontracey/mianshi-zhilian-app/releases/download/$tag/$name',
      'sha256': sha256sum(file),
      'size': file.lengthSync(),
    };
  }

  final manifest = <String, Object?>{
    'version': cleanVersion,
    'buildNumber': buildNumber,
    'releaseDate': DateTime.now().toIso8601String().split('T').first,
    'notes': notesEnv != null && notesEnv.isNotEmpty
        ? notesEnv.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : ['版本更新'],
    'platforms': {
      'android': platformAsset('android'),
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
