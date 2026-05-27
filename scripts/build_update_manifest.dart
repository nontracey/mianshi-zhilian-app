import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final version = args.isNotEmpty ? args.first : '0.1.0';
  final tag = version.startsWith('v') ? version : 'v$version';
  final manifest = {
    'version': version.replaceFirst('v', ''),
    'buildNumber': 100,
    'releaseDate': DateTime.now().toIso8601String().split('T').first,
    'minimumRequiredVersion': '0.1.0',
    'notes': ['新增领域知识目录', '新增 AI 复述评估', '优化掌握度排序'],
    'platforms': {
      'android': {
        'url': 'https://github.com/nontracey/mianshi-zhilian-app/releases/download/$tag/mianshi-zhilian-$tag-android.apk',
        'sha256': '待生成',
        'size': 0,
      },
      'windows': {
        'url': 'https://github.com/nontracey/mianshi-zhilian-app/releases/download/$tag/mianshi-zhilian-$tag-windows.zip',
        'sha256': '待生成',
        'size': 0,
      },
      'macos': {
        'url': 'https://github.com/nontracey/mianshi-zhilian-app/releases/download/$tag/mianshi-zhilian-$tag-macos.zip',
        'sha256': '待生成',
        'size': 0,
      },
    },
  };
  File('update.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
}
