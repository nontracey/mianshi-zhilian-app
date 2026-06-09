import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log_service.dart';
import 'route_resolver.dart';
import 'route_state_store.dart';

class EndpointFallbackClient {
  EndpointFallbackClient({
    RouteResolver resolver = const RouteResolver(),
    required EndpointStateStore stateStore,
    http.Client? httpClient,
  }) : _resolver = resolver,
       _stateStore = stateStore,
       _httpClient = httpClient ?? http.Client();

  final RouteResolver _resolver;
  final EndpointStateStore _stateStore;
  final http.Client _httpClient;

  Future<http.Response> request(
    EndpointService service,
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 5),
    bool fallbackOnAllHttpErrors = false,
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
            _canReplayOnHttpStatus(method, response.statusCode, fallbackOnAllHttpErrors)) {
          lastError = 'HTTP ${response.statusCode} from ${candidate.url.host}';
          unawaited(
            AppLog.debug(
              'Route fallback after HTTP ${response.statusCode}: '
              '${service.name} ${method.toUpperCase()} ${candidate.url.host}',
              source: 'route',
            ),
          );
          continue;
        }
        if (_isHealthyRouteResponse(response.statusCode)) {
          await _stateStore.rememberActiveLane(
            service,
            candidate.endpoint.lane,
            ttl: _ttlFor(service),
          );
          if (candidate.endpoint.lane != activeLane) {
            unawaited(
              AppLog.info(
                'Active route selected: ${service.name} '
                '${candidate.endpoint.lane.name} ${candidate.url.host}',
                source: 'route',
              ),
            );
          }
        }
        return response;
      }       on TimeoutException catch (e) {
        lastError = e;
        if (i < candidates.length - 1) {
          unawaited(
            AppLog.debug(
              'Route timeout, try next: ${service.name} ${method.toUpperCase()} '
              '${candidate.url.host}',
              source: 'route',
            ),
          );
        } else {
          unawaited(
            AppLog.warning(
              'Route timeout (last candidate): ${service.name} '
              '${method.toUpperCase()} ${candidate.url.host}',
              source: 'route',
              error: e,
            ),
          );
        }
      } on http.ClientException catch (e) {
        lastError = e;
        if (i < candidates.length - 1) {
          unawaited(
            AppLog.debug(
              'Route client error, try next: ${service.name} '
              '${method.toUpperCase()} ${candidate.url.host}',
              source: 'route',
            ),
          );
        } else {
          unawaited(
            AppLog.warning(
              'Route client error (last candidate): ${service.name} '
              '${method.toUpperCase()} ${candidate.url.host}',
              source: 'route',
              error: e,
            ),
          );
        }
      } catch (e) {
        lastError = e;
        if (i < candidates.length - 1) {
          unawaited(
            AppLog.debug(
              'Route request failed, try next: ${service.name} '
              '${method.toUpperCase()} ${candidate.url.host}',
              source: 'route',
            ),
          );
        } else {
          unawaited(
            AppLog.warning(
              'Route request failed (last candidate): ${service.name} '
              '${method.toUpperCase()} ${candidate.url.host}',
              source: 'route',
              error: e,
            ),
          );
        }
      }
    }

    unawaited(
      AppLog.error(
        'All endpoints unreachable: ${service.name} ${method.toUpperCase()} '
        '$path',
        source: 'route',
        error: lastError,
      ),
    );
    throw http.ClientException(
      'All endpoints unreachable for ${service.name}: $lastError',
    );
  }

  List<String> resolveUrls(
    EndpointService service,
    String path, {
    EndpointMode mode = EndpointMode.auto,
    EndpointLane? activeLane,
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

  bool _canReplayOnHttpStatus(String method, int statusCode, [bool fallbackAll = false]) {
    if (fallbackAll) return statusCode >= 400;
    final normalized = method.toUpperCase();
    return (normalized == 'GET' || normalized == 'HEAD') && statusCode >= 500;
  }

  bool _isHealthyRouteResponse(int statusCode) {
    return statusCode < 500;
  }

  Duration _ttlFor(EndpointService service) {
    return service == EndpointService.content
        ? const Duration(minutes: 45)
        : const Duration(minutes: 30);
  }
}
