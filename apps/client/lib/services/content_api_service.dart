import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/domain.dart';
import '../models/topic.dart';
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

  Future<Map<String, dynamic>> fetchManifest() async {
    final response = await _get('/manifest.json');
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load manifest: ${response.statusCode}');
  }

  Future<Domain> fetchDomain(String domainId, {String? entry}) async {
    final domainPath = _normalizeDomainPath(domainId, entry: entry);
    final response = await _get(domainPath);
    if (response.statusCode == 200) {
      return Domain.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception(
      'Failed to load domain $domainPath: ${response.statusCode}',
    );
  }

  /// 支持完整相对路径 "topics/java/a.json" / "staging/topics/java/a.json"，
  /// 也兼容旧格式 "java/a" (不带 .json)。
  Future<Topic> fetchTopic(String topicPath) async {
    final response = await _get(_normalizeTopicPath(topicPath));
    if (response.statusCode == 200) {
      return Topic.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Failed to load topic $topicPath: ${response.statusCode}');
  }

  /// 批量加载某个领域下的所有 topics
  Future<List<Topic>> fetchDomainTopics(Domain domain) async {
    final topics = <Topic>[];
    for (final category in domain.categories) {
      for (final topicPath in category.topics) {
        try {
          final topic = await fetchTopic(topicPath);
          topics.add(topic);
        } catch (e) {
          // 单个 topic 加载失败不阻断整体
          debugPrint('Failed to load topic $topicPath: $e');
        }
      }
    }
    return topics;
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
      return _OfficialContentRoute(RouteService.content, path);
    }
    if (normalized == '${RouteResolver.appApiPrimary}/content/production' ||
        normalized == '${RouteResolver.appApiBackup}/content/production') {
      return _OfficialContentRoute(
        RouteService.appApi,
        '/content/production$path',
      );
    }
    if (normalized == '${RouteResolver.appApiPrimary}/content/test' ||
        normalized == '${RouteResolver.appApiBackup}/content/test') {
      return _OfficialContentRoute(RouteService.appApi, '/content/test$path');
    }
    if (normalized == '${RouteResolver.appApiPrimary}/content/draft' ||
        normalized == '${RouteResolver.appApiBackup}/content/draft') {
      return _OfficialContentRoute(RouteService.appApi, '/content/draft$path');
    }
    return null;
  }
}

class _OfficialContentRoute {
  const _OfficialContentRoute(this.service, this.path);

  final RouteService service;
  final String path;
}
