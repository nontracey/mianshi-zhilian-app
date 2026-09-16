import 'dart:convert';

import 'package:http/http.dart' as http;

import '../coach/model/errors.dart';
import '../coach/model/http_client.dart' as coach;

/// One HTTP transport for native and browser model connections. Credentials only
/// go to the requested endpoint; redirects are disabled to prevent forwarding.
class CoachHttpClient implements coach.HttpClient {
  CoachHttpClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  http.AbortableRequest _request(
    String url,
    Map<String, String>? headers,
    String body,
    coach.CancelToken? cancel,
  ) {
    if (cancel?.isCancelled ?? false) throw coach.HttpCanceledException();
    final uri = Uri.parse(url);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ModelGatewayException('Invalid model endpoint');
    }
    return http.AbortableRequest(
        'POST',
        uri,
        abortTrigger: cancel?.whenCancelled,
      )
      ..followRedirects = false
      ..headers.addAll(headers ?? const {})
      ..body = body;
  }

  @override
  Future<coach.HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    required String body,
    coach.CancelToken? cancel,
  }) async {
    try {
      final response = await _client.send(_request(url, headers, body, cancel));
      final text = await response.stream.transform(utf8.decoder).join();
      if (cancel?.isCancelled ?? false) throw coach.HttpCanceledException();
      return coach.HttpResponse(
        statusCode: response.statusCode,
        body: text,
        headers: response.headers.map(
          (key, value) => MapEntry(key.toLowerCase(), value),
        ),
      );
    } on http.RequestAbortedException {
      throw coach.HttpCanceledException();
    }
  }

  @override
  Stream<String> postStreaming(
    String url, {
    Map<String, String>? headers,
    required String body,
    coach.CancelToken? cancel,
  }) async* {
    try {
      final response = await _client.send(_request(url, headers, body, cancel));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Do not include a remote error body, which may echo credentials.
        await response.stream.drain<void>();
        if (response.statusCode == 401) throw ModelAuthException();
        if (response.statusCode == 429) throw ModelRateLimitException();
        throw ModelGatewayException(
          'Model request failed',
          statusCode: response.statusCode,
        );
      }
      yield* response.stream.transform(utf8.decoder);
    } on http.RequestAbortedException {
      throw coach.HttpCanceledException();
    }
  }

  void close() => _client.close();
}
