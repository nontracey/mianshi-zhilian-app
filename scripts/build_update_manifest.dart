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
  final version = args.isNotEmpty ? args.first : '0.1.0';
  final assetsDir = args.length > 1 ? Directory(args[1]) : Directory.current;
  final tag = version.startsWith('v') ? version : 'v$version';
  final cleanVersion = version.replaceFirst('v', '');

  // 从 pubspec.yaml 读取 buildNumber
  final pubspecFile = File('apps/client/pubspec.yaml');
  int buildNumber = 100;
  if (pubspecFile.existsSync()) {
    final (bn, _) = _parsePubspecVersion(pubspecFile.readAsStringSync());
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

  final manifest = {
    'version': cleanVersion,
    'buildNumber': buildNumber,
    'releaseDate': DateTime.now().toIso8601String().split('T').first,
    'minimumRequiredVersion': '0.1.0',
    'notes': ['新增领域知识目录', '新增 AI 复述评估', '优化掌握度排序'],
    'platforms': {
      'android': platformAsset('android'),
      'windows': platformAsset('windows'),
      'macos': platformAsset('macos'),
      'web': platformAsset('web'),
    },
  };
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
