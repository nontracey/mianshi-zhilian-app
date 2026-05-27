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
  bool _isLoadingTopics = false;
  String? _error;

  List<Domain> get domains => _domains;
  Map<String, Topic> get topics => _topics;
  Map<String, dynamic>? get manifest => _manifest;
  bool get isLoading => _isLoading;
  bool get isLoadingTopics => _isLoadingTopics;
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

      // 5. 自动加载默认 domain 的 topics（后台加载，不阻塞 UI）
      final defaultDomainId = _manifest?['defaultDomain'] as String? ?? 'java';
      if (_topics.values.where((t) => t.domainId == defaultDomainId).isEmpty) {
        loadDomainTopics(defaultDomainId);
      }
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDomainTopics(String domainId) async {
    _isLoadingTopics = true;
    notifyListeners();

    try {
      // 找到对应的 domain，从 categories 中获取 topic 路径列表
      final domain = _domains.where((d) => d.id == domainId).firstOrNull;
      if (domain == null) {
        _isLoadingTopics = false;
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
              // 每加载一个 topic 就通知 UI 更新，让用户看到渐进式加载
              notifyListeners();
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

      _isLoadingTopics = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoadingTopics = false;
      notifyListeners();
    }
  }

  /// 获取指定 domain 下已加载的 topic 数量
  int getLoadedTopicCount(String domainId) {
    return _topics.values.where((t) => t.domainId == domainId).length;
  }

  /// 获取指定 domain 的预期 topic 总数（从 manifest 读取）
  int getTotalTopicCount(String domainId) {
    final domain = _domains.where((d) => d.id == domainId).firstOrNull;
    return domain?.topicCount ?? 0;
  }

  List<Topic> getTopicsByDomain(String domainId) {
    return _topics.values
        .where((t) => t.domainId == domainId)
        .toList()
      ..sort((a, b) {
        // 先按难度升序（由易到难），难度相同再按 order
        final diff = a.difficulty.compareTo(b.difficulty);
        if (diff != 0) return diff;
        return a.order.compareTo(b.order);
      });
  }

  List<Topic> getTopicsByCategory(String domainId, String categoryId) {
    return _topics.values
        .where((t) => t.domainId == domainId && t.categoryId == categoryId)
        .toList()
      ..sort((a, b) {
        final diff = a.difficulty.compareTo(b.difficulty);
        if (diff != 0) return diff;
        return a.order.compareTo(b.order);
      });
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
