import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mianshi_zhilian/services/content_api_service.dart';
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

  test('official production content uses the route client', () async {
    final storage = StorageService();
    final client = _QueuedClient([http.Response('{"domains":[]}', 200)]);
    final routeClient = EndpointFallbackClient(
      stateStore: RouteStateStore(storage),
      httpClient: client,
    );
    final service = ContentApiService(
      baseUrl: RouteResolver.contentPrimary,
      routeClient: routeClient,
      httpClient: _QueuedClient([]),
    );

    final manifest = await service.fetchManifest();

    expect(manifest['domains'], isEmpty);
    expect(client.requests, hasLength(1));
    expect(
      client.requests.single.url.toString(),
      '${RouteResolver.contentPrimary}/manifest.json',
    );
  });

  test('custom production content bypasses official fallback', () async {
    final customClient = _QueuedClient([http.Response('{"domains":[]}', 200)]);
    final routeClient = EndpointFallbackClient(
      stateStore: RouteStateStore(StorageService()),
      httpClient: _QueuedClient([
        http.Response('route client should not be used', 500),
      ]),
    );
    final service = ContentApiService(
      baseUrl: 'https://content.example.test/custom',
      routeClient: routeClient,
      httpClient: customClient,
    );

    await service.fetchManifest();

    expect(customClient.requests, hasLength(1));
    expect(
      customClient.requests.single.url.toString(),
      'https://content.example.test/custom/manifest.json',
    );
  });

  test('official test content maps through appApi proxy paths', () async {
    final client = _QueuedClient([http.Response('{"domains":[]}', 200)]);
    final routeClient = EndpointFallbackClient(
      stateStore: RouteStateStore(StorageService()),
      httpClient: client,
    );
    final service = ContentApiService(
      baseUrl: '${RouteResolver.appApiPrimary}/content/test',
      routeClient: routeClient,
    );

    await service.fetchManifest();

    expect(client.requests, hasLength(1));
    expect(
      client.requests.single.url.toString(),
      '${RouteResolver.appApiPrimary}/content/test/manifest.json',
    );
  });
}
