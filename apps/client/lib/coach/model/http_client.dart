/// 抽象 HTTP 客户端，避免直接依赖具体实现（dart:io / http 包 / Web 适配）。
///
/// 这样 [OpenAiCompatibleGateway] 在原生和 Web 都可复用同一份解析逻辑，
/// 真正的网络实现由调用方按平台注入（见 services/coach_http_client.dart）。
library;

import 'dart:async';

/// 请求取消令牌。模型调用在取消后应停止发送或忽略迟到响应。
class CancelToken {
  bool _cancelled = false;
  final Completer<void> _cancelledCompleter = Completer<void>();

  /// 是否已请求取消。
  bool get isCancelled => _cancelled;

  /// Completes once cancellation is requested. HTTP adapters can wire this to
  /// an abort signal so cancellation closes an in-flight connection instead
  /// of merely ignoring its eventual response.
  Future<void> get whenCancelled => _cancelledCompleter.future;

  /// 请求取消。
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelledCompleter.complete();
  }
}

/// 一次 HTTP 响应。
class HttpResponse {
  HttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });
  final int statusCode;
  final String body;

  /// 响应头（小写键）。MCP 旧版会话 ID 从这里读取；不可用时为空。
  final Map<String, String> headers;

  bool get isOk => statusCode >= 200 && statusCode < 300;
}

/// 最小 HTTP 客户端契约。网关只依赖它，不关心底层是 dart:io 还是 Web 适配器。
abstract class HttpClient {
  /// 发送 POST 请求。实现应尊重 [cancel]，取消时尽快抛出 [HttpCanceledException]。
  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    required String body,
    CancelToken? cancel,
  });

  /// 流式 POST（用于 SSE）。按原始文本分块返回，网关负责解析 `data:` 行。
  /// 不支持真流的适配器可把完整响应作为单个分块返回，网关的 SSE 解析依然成立。
  Stream<String> postStreaming(
    String url, {
    Map<String, String>? headers,
    required String body,
    CancelToken? cancel,
  });
}

/// 取消时由底层客户端抛出的异常，网关捕获后转成可识别的取消错误。
class HttpCanceledException implements Exception {
  @override
  String toString() => 'HttpCanceledException: 请求已被取消';
}
