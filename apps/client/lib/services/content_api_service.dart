import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/domain.dart';
import '../models/topic.dart';
import 'api_response.dart';
import 'endpoint_fallback_client.dart';
import 'route_resolver.dart';

class ContentApiService {
  String baseUrl;
  final EndpointFallbackClient? routeClient;
  final http.Client _httpClient;

  ContentApiService({
    this.baseUrl = RouteResolver.contentPrimary,
    this.routeClient,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// 切换内容源 baseUrl，返回 this 以便链式调用
  ContentApiService switchBaseUrl(String newBaseUrl) {
    baseUrl = newBaseUrl;
    return this;
  }

  /// 返回某个内容资源路径的所有候选 URL（primary + backup）。
  /// 用于图片/SVG 等静态资源加载，使它们也能享受 CDN fallback。
  List<String> resolveContentUrls(String path) {
    final uri = Uri.tryParse(path);
    if (uri?.hasScheme == true) return [path];
    final normalized = path.replaceFirst(RegExp(r'^/+'), '');
    final official = _officialRoute('/$normalized');
    if (official != null && routeClient != null) {
      return routeClient!.resolveUrls(official.service, official.path);
    }
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return ['$base/$normalized'];
  }

  Future<Map<String, dynamic>> fetchManifest() async {
    final response = await _get('/manifest.json');
    final apiResp = ApiResponse.fromJson(response);
    if (response.statusCode == 200 && apiResp.data != null) {
      return apiResp.data!;
    }
    throw ApiResponseException(
      'Failed to load manifest: ${response.statusCode}',
      response.statusCode,
    );
  }

  Future<Domain> fetchDomain(String domainId, {String? entry}) async {
    final domainPath = _normalizeDomainPath(domainId, entry: entry);
    final response = await _get(domainPath);
    final apiResp = ApiResponse.fromJson(response);
    if (response.statusCode == 200 && apiResp.data != null) {
      return Domain.fromJson(apiResp.data!);
    }
    throw ApiResponseException(
      'Failed to load domain $domainPath: ${response.statusCode}',
      response.statusCode,
    );
  }

  /// 支持完整相对路径 "topics/java/a.json" / "staging/topics/java/a.json"，
  /// 也兼容旧格式 "java/a" (不带 .json)。
  Future<Topic> fetchTopic(String topicPath) async {
    final response = await _get(_normalizeTopicPath(topicPath));
    final apiResp = ApiResponse.fromJson(response);
    if (response.statusCode == 200 && apiResp.data != null) {
      return Topic.fromJson(apiResp.data!);
    }
    throw ApiResponseException(
      'Failed to load topic $topicPath: ${response.statusCode}',
      response.statusCode,
    );
  }

  /// 单个领域批量拉取 topic 时的并发窗口大小。
  /// 过大容易在弱网/移动端打满连接池，6 在大领域（70+ topic）下
  /// 已能把首次加载从全串行的几十次 RTT 压缩到 ~1/6。
  static const _topicFetchConcurrency = 6;

  /// 批量加载某个领域下的所有 topics。
  ///
  /// 按固定窗口分批并发（替代逐个 await 的全串行），结果顺序仍与
  /// 内容契约中分类/topic 的引用顺序一致；单个 topic 加载失败不阻断整体。
  Future<List<Topic>> fetchDomainTopics(Domain domain) async {
    final paths = <String>[
      for (final category in domain.categories) ...category.topics,
    ];
    final results = List<Topic?>.filled(paths.length, null);
    for (var start = 0; start < paths.length; start += _topicFetchConcurrency) {
      final end = start + _topicFetchConcurrency > paths.length
          ? paths.length
          : start + _topicFetchConcurrency;
      await Future.wait([
        for (var i = start; i < end; i++)
          () async {
            try {
              results[i] = await fetchTopic(paths[i]);
            } catch (e) {
              // 单个 topic 加载失败不阻断整体
              debugPrint('Failed to load topic ${paths[i]}: $e');
            }
          }(),
      ]);
    }
    return [
      for (final topic in results)
        if (topic != null) topic,
    ];
  }

  static String cacheKeyForTopicRef(String topicPath) =>
      _normalizeRelativePath(topicPath).replaceAll(RegExp(r'\.json$'), '');

  static String _normalizeDomainPath(String domainId, {String? entry}) {
    if (entry != null && entry.trim().isNotEmpty) {
      return _normalizeRelativePath(entry);
    }
    return 'domains/$domainId.json';
  }

  static String _normalizeTopicPath(String topicPath) {
    final normalized = _normalizeRelativePath(topicPath);
    if (normalized.endsWith('.json')) return normalized;
    if (normalized.startsWith('topics/') ||
        normalized.startsWith('staging/topics/') ||
        normalized.startsWith('draft/topics/')) {
      return '$normalized.json';
    }
    return 'topics/$normalized.json';
  }

  static String _normalizeRelativePath(String path) =>
      path.trim().replaceFirst(RegExp(r'^/+'), '');

  Future<http.Response> _get(String path) {
    final requestPath = path.startsWith('/') ? path : '/$path';
    final official = _officialRoute(requestPath);
    if (official != null && routeClient != null) {
      return routeClient!.request(
        official.service,
        'GET',
        official.path,
        timeout: const Duration(seconds: 8),
      );
    }
    return _httpClient
        .get(Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$requestPath'))
        .timeout(const Duration(seconds: 8));
  }

  _OfficialContentRoute? _officialRoute(String path) {
    final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (normalized == RouteResolver.contentPrimary ||
        normalized == RouteResolver.contentBackup) {
      return _OfficialContentRoute(EndpointService.content, path);
    }
    if (normalized == '${RouteResolver.appApiPrimary}/content/production' ||
        normalized == '${RouteResolver.appApiBackup}/content/production') {
      return _OfficialContentRoute(
        EndpointService.appApi,
        '/content/production$path',
      );
    }
    if (normalized == '${RouteResolver.appApiPrimary}/content/test' ||
        normalized == '${RouteResolver.appApiBackup}/content/test') {
      return _OfficialContentRoute(EndpointService.appApi, '/content/test$path');
    }
    if (normalized == '${RouteResolver.appApiPrimary}/content/draft' ||
        normalized == '${RouteResolver.appApiBackup}/content/draft') {
      return _OfficialContentRoute(EndpointService.appApi, '/content/draft$path');
    }
    return null;
  }
}

class _OfficialContentRoute {
  const _OfficialContentRoute(this.service, this.path);

  final EndpointService service;
  final String path;
}
