import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'route_resolver.dart';
import 'route_state_store.dart';

class EndpointFallbackClient {
  EndpointFallbackClient({
    RouteResolver resolver = const RouteResolver(),
    required RouteStateStore stateStore,
    http.Client? httpClient,
  }) : _resolver = resolver,
       _stateStore = stateStore,
       _httpClient = httpClient ?? http.Client();

  final RouteResolver _resolver;
  final RouteStateStore _stateStore;
  final http.Client _httpClient;

  Future<http.Response> request(
    RouteService service,
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final mode = await _stateStore.loadMode(service);
    final activeLane = await _stateStore.loadActiveLane(service);
    final candidates = _resolver.resolveCandidates(
      service,
      path,
      mode: mode,
      activeLane: activeLane,
    );
    Object? lastError;

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      try {
        final response = await _send(
          method,
          candidate.url,
          headers: headers,
          body: body,
        ).timeout(timeout);
        if (i < candidates.length - 1 &&
            _canReplayOnHttpStatus(method, response.statusCode)) {
          lastError = 'HTTP ${response.statusCode} from ${candidate.url.host}';
          continue;
        }
        await _stateStore.rememberActiveLane(
          service,
          candidate.endpoint.lane,
          ttl: _ttlFor(service),
        );
        return response;
      } on TimeoutException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }

    throw http.ClientException(
      'All endpoints unreachable for ${service.name}: $lastError',
    );
  }

  List<String> resolveUrls(
    RouteService service,
    String path, {
    RouteMode mode = RouteMode.auto,
    RouteLane? activeLane,
  }) {
    return _resolver
        .resolveCandidates(service, path, mode: mode, activeLane: activeLane)
        .map((candidate) => candidate.url.toString())
        .toList();
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final request = http.Request(method.toUpperCase(), url);
    request.headers.addAll(headers ?? {});
    if (body is String) {
      request.body = body;
    } else if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body != null) {
      request.body = json.encode(body);
    }
    return http.Response.fromStream(await _httpClient.send(request));
  }

  bool _canReplayOnHttpStatus(String method, int statusCode) {
    final normalized = method.toUpperCase();
    return (normalized == 'GET' || normalized == 'HEAD') && statusCode >= 500;
  }

  Duration _ttlFor(RouteService service) {
    return service == RouteService.content
        ? const Duration(minutes: 45)
        : const Duration(minutes: 30);
  }
}
