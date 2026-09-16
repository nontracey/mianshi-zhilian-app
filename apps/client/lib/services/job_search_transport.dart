/// 岗位搜索通道的真实接入点（§6.7）。
///
/// 只做一件事：把用户搜索条件发给**用户自己配置的**搜索服务，并把原始结果
/// 原样取回。适配器（[WebSearchJobAdapter]）负责映射成岗位卡片。
///
/// 硬约束：
/// - **未配置 endpoint 时立刻抛出 [JobSearchNotConfiguredException]**，
///   而不是返回空列表冒充「搜到 0 条」——空结果与未配置是两件事；
/// - 不做结果去重/排序/补全，不根据岗位名猜测公司或薪资；
/// - 返回体不符合约定时抛 [JobSearchProtocolException]，不猜字段。
library;

import 'dart:async';
import 'dart:convert';

import '../coach/jobs/models.dart';
import '../coach/jobs/search_service.dart';
import '../coach/model/http_client.dart';

/// 搜索通道未配置。
class JobSearchNotConfiguredException implements Exception {
  const JobSearchNotConfiguredException(this.reason);
  final String reason;
  @override
  String toString() => 'JobSearchNotConfiguredException: $reason';
}

/// 搜索服务返回体与约定不符。
class JobSearchProtocolException implements Exception {
  const JobSearchProtocolException(this.reason);
  final String reason;
  @override
  String toString() => 'JobSearchProtocolException: $reason';
}

/// 走 HTTP 的搜索通道。
///
/// 约定（POST [endpoint]，JSON）：
///   请求：`{"query": {...SearchQuery.toParams()}}`
///   响应：`{"items": [{"title","company","location","salary","url","snippet",
///                     "postedAt","externalId"}], "truncated": false, "note": "..."}`
class HttpJobSearchTransport implements JobSearchTransport {
  HttpJobSearchTransport({
    required this.http,
    required this.endpoint,
    this.apiKey,
    this.timeout = const Duration(seconds: 20),
  });

  final HttpClient http;
  final String endpoint;
  final String? apiKey;
  final Duration timeout;

  /// endpoint 为空即视为未配置。
  bool get isConfigured => endpoint.trim().isNotEmpty;

  @override
  Future<RawSearchResponse> fetch(
    SearchQuery query, {
    CancelToken? cancel,
  }) async {
    if (!isConfigured) {
      throw const JobSearchNotConfiguredException(
        'search endpoint is empty; configure it in settings before searching',
      );
    }

    if (cancel?.isCancelled == true) throw HttpCanceledException();
    final token = CancelToken();
    var finished = false;
    cancel?.whenCancelled.then((_) {
      if (!finished) token.cancel();
    });
    final HttpResponse resp;
    try {
      resp = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              if (apiKey != null && apiKey!.isNotEmpty)
                'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({'query': query.toParams()}),
            cancel: token,
          )
          .timeout(
            timeout,
            onTimeout: () {
              token.cancel();
              throw TimeoutException('Job search timed out', timeout);
            },
          );
      if (token.isCancelled) throw HttpCanceledException();
    } finally {
      finished = true;
    }

    if (!resp.isOk) {
      throw JobSearchProtocolException(
        'search endpoint returned HTTP ${resp.statusCode}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException catch (e) {
      throw JobSearchProtocolException(
        'response is not valid JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const JobSearchProtocolException(
        'response root is not a JSON object',
      );
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const JobSearchProtocolException(
        "response is missing a list field named 'items'",
      );
    }

    return RawSearchResponse(
      items: items
          .whereType<Map<String, dynamic>>()
          .map(RawSearchItem.fromJson)
          .where((e) => e.title.trim().isNotEmpty)
          .toList(),
      truncated: decoded['truncated'] == true,
      note: decoded['note'] as String?,
    );
  }
}
