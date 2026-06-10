import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// 按 `test/fixtures/content_full/` 提供内容的假 HTTP 客户端。
///
/// 用真实的 [ContentApiService] + [ContentProvider] 跑通「manifest → 领域 →
/// 知识点」全链路（不 mock 业务层），数据来自真实 content 仓库的精简快照
/// （java/agent/python 三领域，含真实 learningPaths 与全部 topic 引用）。
class FakeContentClient extends http.BaseClient {
  FakeContentClient() {
    _topics = (json.decode(File('$_root/topics.json').readAsStringSync())
            as Map)
        .cast<String, dynamic>();
  }

  static const _root = 'test/fixtures/content_full';
  late final Map<String, dynamic> _topics;

  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    final raw = request.url.path;
    final p = raw.startsWith('/') ? raw.substring(1) : raw;

    String? body;
    if (p == 'manifest.json') {
      body = File('$_root/manifest.json').readAsStringSync();
    } else if (p.startsWith('domains/')) {
      final f = File('$_root/$p');
      if (f.existsSync()) body = f.readAsStringSync();
    } else if (p.startsWith('topics/')) {
      final t = _topics[p];
      if (t != null) body = json.encode(t);
    }

    final code = body == null ? 404 : 200;
    final bytes = utf8.encode(body ?? '{"error":"not found: $p"}');
    return http.StreamedResponse(Stream.value(bytes), code, request: request);
  }
}
