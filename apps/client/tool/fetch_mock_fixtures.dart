// 一次性脚本：从线上 API 拉取 fixtures，落盘到 test/fixtures/content/
// 用法：dart run tool/fetch_mock_fixtures.dart
//
// 会拉取：manifest.json、java 域、agent 域 及其全部 topics
// 输出到：test/fixtures/content/{manifest,java/*,agent/*}

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const _baseUrl = 'https://mianshi-zhilian-api.pages.dev/content/production';
const _outDir = 'test/fixtures/content';
const _fetchDomains = ['java', 'agent'];

Future<void> main() async {
  final client = http.Client();
  try {
    await _fetch(client);
  } finally {
    client.close();
  }
}

Future<void> _fetch(http.Client client) async {
  // 1. manifest
  final manifest = await _getJson(client, '$_baseUrl/manifest.json');
  _write('$_outDir/manifest.json', manifest);
  print('✓ manifest.json');

  // 2. 每个目标域
  final domains = (manifest['domains'] as List? ?? []).cast<Map<String, dynamic>>();
  for (final d in domains) {
    final domainId = d['id'] as String;
    if (!_fetchDomains.contains(domainId)) continue;

    final entry = d['entry'] as String? ?? 'domains/$domainId.json';
    final domainData = await _getJson(client, '$_baseUrl/$entry');
    _write('$_outDir/$domainId/domain.json', domainData);
    print('✓ $domainId/domain.json');

    // 3. 每个 category 的 topics
    final categories = (domainData['categories'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final cat in categories) {
      final topicPaths = (cat['topics'] as List? ?? []).cast<String>();
      for (final topicPath in topicPaths) {
        try {
          final topicData = await _getJson(client, '$_baseUrl/$topicPath');
          final fileName = topicPath.replaceAll('/', '_').replaceAll('.json', '') + '.json';
          _write('$_outDir/$domainId/$fileName', topicData);
          print('✓ $domainId/$fileName');
        } catch (e) {
          print('✗ $topicPath: $e');
        }
      }
    }
  }
  print('\nDone. Fixtures written to $_outDir/');
}

Future<Map<String, dynamic>> _getJson(http.Client client, String url) async {
  final resp = await client.get(Uri.parse(url));
  if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}: $url');
  return json.decode(resp.body) as Map<String, dynamic>;
}

void _write(String path, Map<String, dynamic> data) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}
