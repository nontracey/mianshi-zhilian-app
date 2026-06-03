import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mianshi_zhilian/services/endpoint_fallback_client.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueuedClient extends http.BaseClient {
  _QueuedClient(this.responses);

  final List<http.Response> responses;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (responses.isEmpty) {
      throw http.ClientException('no response queued', request.url);
    }
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('GET falls back on 5xx and remembers successful lane', () async {
    final storage = StorageService();
    final client = _QueuedClient([
      http.Response('primary failed', 502),
      http.Response('backup ok', 200),
    ]);
    final fallbackClient = EndpointFallbackClient(
      stateStore: RouteStateStore(storage),
      httpClient: client,
    );

    final response = await fallbackClient.request(
      RouteService.content,
      'GET',
      '/manifest.json',
    );

    expect(response.statusCode, 200);
    expect(client.requests, hasLength(2));
    expect(
      client.requests[0].url.host,
      Uri.parse(RouteResolver.contentPrimary).host,
    );
    expect(
      client.requests[1].url.host,
      Uri.parse(RouteResolver.contentBackup).host,
    );
    expect(
      await RouteStateStore(storage).loadActiveLane(RouteService.content),
      RouteLane.backup,
    );
  });

  test('POST does not replay after receiving an HTTP response', () async {
    final client = _QueuedClient([
      http.Response('server failed', 500),
      http.Response('backup should not be used', 200),
    ]);
    final fallbackClient = EndpointFallbackClient(
      stateStore: RouteStateStore(StorageService()),
      httpClient: client,
    );

    final response = await fallbackClient.request(
      RouteService.appApi,
      'POST',
      '/tickets',
      body: '{"subject":"x"}',
    );

    expect(response.statusCode, 500);
    expect(client.requests, hasLength(1));
  });
}
