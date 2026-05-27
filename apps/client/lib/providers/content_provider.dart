import 'package:flutter/material.dart';
import '../models/domain.dart';
import '../models/topic.dart';
import '../services/content_api_service.dart';
import '../services/storage_service.dart';

class ContentProvider extends ChangeNotifier {
  final ContentApiService _api;
  final StorageService _storage;

  ContentProvider(this._api, this._storage);

  List<Domain> _domains = [];
  Map<String, Topic> _topics = {};
  Map<String, dynamic>? _manifest;
  bool _isLoading = false;
  String? _error;

  List<Domain> get domains => _domains;
  Map<String, Topic> get topics => _topics;
  Map<String, dynamic>? get manifest => _manifest;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadContent() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. 加载 manifest 获取 domain 列表
      _manifest = await _api.fetchManifest();
      final domainList = _manifest?['domains'] as List<dynamic>? ?? [];

      // 2. 从 manifest 创建基础 Domain 对象
      final baseDomains = domainList
          .map((e) => Domain.fromJson(e as Map<String, dynamic>))
          .toList();

      // 3. 逐个加载 domain 详情（含 categories）
      final List<Domain> fullDomains = [];
      for (final domain in baseDomains) {
        try {
          final fullDomain = await _api.fetchDomain(domain.id);
          fullDomains.add(fullDomain);
        } catch (e) {
          // 单个 domain 加载失败不阻断，用 manifest 里的基础信息
          debugPrint('Failed to load domain detail ${domain.id}: $e');
          fullDomains.add(domain);
        }
      }
      _domains = fullDomains;

      // 4. 尝试从缓存加载 topics
      final cached = await _storage.load('topics_cache');
      if (cached != null && cached is Map<String, dynamic>) {
        _topics = cached.map(
          (k, v) => MapEntry(k, Topic.fromJson(v as Map<String, dynamic>)),
        );
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDomainTopics(String domainId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 找到对应的 domain，从 categories 中获取 topic 路径列表
      final domain = _domains.where((d) => d.id == domainId).firstOrNull;
      if (domain == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      for (final category in domain.categories) {
        for (final topicPath in category.topics) {
          // topicPath 格式: "topics/java/topic-001-xxx.json"
          final cleanPath = topicPath
              .replaceAll('topics/', '')
              .replaceAll('.json', '');
          if (!_topics.containsKey(cleanPath)) {
            try {
              final topic = await _api.fetchTopic(cleanPath);
              _topics[cleanPath] = topic;
            } catch (e) {
              debugPrint('Failed to load topic $cleanPath: $e');
            }
          }
        }
      }

      // 缓存 topics
      await _storage.save(
        'topics_cache',
        _topics.map((k, v) => MapEntry(k, v.toJson())),
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  List<Topic> getTopicsByDomain(String domainId) {
    return _topics.values
        .where((t) => t.domainId == domainId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<Topic> getTopicsByCategory(String domainId, String categoryId) {
    return _topics.values
        .where((t) => t.domainId == domainId && t.categoryId == categoryId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  Topic? getTopicById(String topicId) => _topics[topicId];

  /// 切换知识源环境：更新 baseUrl 并重载内容
  Future<void> switchContentEnv(String newBaseUrl) async {
    _api.switchBaseUrl(newBaseUrl);
    _domains = [];
    _topics = {};
    _manifest = null;
    notifyListeners();
    await loadContent();
  }
}
