/// JD 页面正文抓取器（Flutter 侧实现）。
///
/// 用 `package:http`（跨平台，Web 也能用）拉取岗位页 HTML，做最保守的正文净化：
/// 去脚本/样式、去标签、折叠空白。**不做**平台专用 DOM 解析——各平台结构变动频繁，
/// 结构化提取应优先走页面内 `JobPosting` JSON-LD（由解析器负责）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../coach/jobs/jd_import_service.dart';
import '../coach/model/http_client.dart';
import 'safe_endpoint.dart';

/// JD 抓取失败（网络错误、非 2xx、非法链接）。
class JdFetchException implements Exception {
  JdFetchException(this.message, {this.statusCode, this.url});
  final String message;
  final int? statusCode;
  final String? url;

  @override
  String toString() =>
      'JdFetchException(${statusCode ?? '-'}): $message${url == null ? '' : ' @ $url'}';
}

class HttpJdFetcher implements JdFetcher {
  HttpJdFetcher({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// 桌面 UA，避免部分站点返回精简页或反爬页。
  static const String _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// 抓取体积上限（字节）。岗位页正常在几十 KB 量级；无上限时一个超大页面
  /// 会直接撑爆内存，也会带着整页正文进模型上下文。
  static const int maxResponseBytes = 2 * 1024 * 1024;

  @override
  Future<String> fetchText(String url, {CancelToken? cancel}) async {
    final uri = Uri.tryParse(url);
    // 链接来自用户粘贴、目标不可信：排除内网地址，否则一条链接就能探测内网。
    if (uri == null || !isAllowedFetchTarget(uri)) {
      throw JdFetchException('无效的岗位链接', url: url);
    }
    if (cancel?.isCancelled ?? false) {
      throw HttpCanceledException();
    }

    final http.Response resp;
    try {
      // 不跟随重定向：否则一条公网链接可以 302 跳到内网地址绕过上面的校验。
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll({
          'User-Agent': _ua,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        });
      final streamed = await _client.send(request).timeout(timeout);
      final bytes = await _readCapped(
        streamed.stream,
        maxResponseBytes,
        url: url,
      ).timeout(timeout);
      resp = http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
      );
    } on JdFetchException {
      rethrow;
    } catch (e) {
      throw JdFetchException('网络请求失败：$e', url: url);
    }

    if (cancel?.isCancelled ?? false) {
      throw HttpCanceledException();
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw JdFetchException(
        'HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
        url: url,
      );
    }

    final body = _decodeBody(resp);
    return extractJobPosting(body);
  }

  void close() => _client.close();

  /// 边读边计数，超过上限立刻中断，避免先把整份响应读进内存再判断。
  static Future<Uint8List> _readCapped(
    Stream<List<int>> stream,
    int limit, {
    String? url,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
      if (builder.length > limit) {
        throw JdFetchException('岗位页面过大，请粘贴岗位正文', url: url);
      }
    }
    return builder.takeBytes();
  }

  /// Unsupported encodings fail visibly instead of importing garbled requirements.
  static String _decodeBody(http.Response resp) {
    final ct = (resp.headers['content-type'] ?? '').toLowerCase();
    if (ct.contains('gbk') || ct.contains('gb2312')) {
      throw JdFetchException('页面编码暂不支持，请粘贴岗位正文');
    }
    try {
      return utf8.decode(resp.bodyBytes);
    } on FormatException {
      throw JdFetchException('岗位正文解码失败，请粘贴原文');
    }
  }

  /// Generic structured adapter. Unverified HTML, login pages and multi-job lists
  /// require manual paste until a tested platform-specific extractor is available.
  static String extractJobPosting(String html) {
    final jobs = <Map<String, dynamic>>[];
    void visit(dynamic value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
      }
      if (value is Map<String, dynamic>) {
        final type = value['@type'];
        if (type == 'JobPosting' ||
            (type is List && type.contains('JobPosting'))) {
          jobs.add(value);
        }
        if (value.containsKey('@graph')) visit(value['@graph']);
      }
    }

    for (final script in RegExp(
      r'<script\b([^>]*)>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html)) {
      if (!script[1]!.toLowerCase().contains('application/ld+json')) continue;
      try {
        visit(jsonDecode(script[2]!));
      } on FormatException {
        continue;
      }
    }
    if (jobs.length != 1) throw JdFetchException('未找到唯一、可核对的岗位正文，请打开岗位页后粘贴 JD');
    final job = jobs.single;
    final title = job['title'];
    final description = job['description'];
    final expires = DateTime.tryParse(job['validThrough']?.toString() ?? '');
    if (expires != null && expires.isBefore(DateTime.now())) {
      throw JdFetchException('岗位已过期，请核对后粘贴 JD');
    }
    if (title is! String ||
        title.trim().isEmpty ||
        description is! String ||
        stripHtml(description).length < 80) {
      throw JdFetchException('岗位正文不完整，请粘贴完整 JD');
    }
    return '${stripHtml(title)}\n${stripHtml(description)}';
  }

  /// 极简 HTML → 文本。仅用于给解析器提供素材，不追求完整语义。
  static String stripHtml(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    s = s.replaceAll(
      RegExp(
        r'<(script|style|noscript|svg)[\s\S]*?</\1>',
        caseSensitive: false,
      ),
      ' ',
    );
    // 块级标签换成换行，保留段落结构（解析器依赖换行分批）。
    s = s.replaceAll(
      RegExp(
        r'</?(p|div|br|li|tr|h[1-6]|section|article)[^>]*>',
        caseSensitive: false,
      ),
      '\n',
    );
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // 折叠空格但保留换行。
    s = s.replaceAll(RegExp(r'[ \t\u00A0\u3000]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n');
    return s.trim();
  }
}
