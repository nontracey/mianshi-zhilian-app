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
  bool _isCheckingUpdate = false;
  String? _error;
  String? _cachedContentVersion;

  List<Domain> get domains => _domains;
  Map<String, Topic> get topics => _topics;
  Map<String, dynamic>? get manifest => _manifest;
  bool get isLoading => _isLoading;
  bool get isLoadingTopics => _isLoadingTopics;
  bool get isCheckingUpdate => _isCheckingUpdate;
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
          fullDomains.add(
            Domain(
              id: fullDomain.id,
              title: fullDomain.title,
              description: fullDomain.description,
              categories: fullDomain.categories,
              topicCount: domain.topicCount,
              updatedAt: domain.updatedAt,
              color: fullDomain.color,
            ),
          );
        } catch (e) {
          debugPrint('Failed to load domain detail ${domain.id}: $e');
          fullDomains.add(domain);
        }
      }
      _domains = fullDomains;

      // 4. 检查内容版本是否有更新
      final remoteVersion = _manifest?['contentVersion'] as String?;
      _cachedContentVersion = await _storage.load('content_version') as String?;

      if (remoteVersion != null && remoteVersion != _cachedContentVersion) {
        // 内容有更新，清除所有缓存并重新加载
        debugPrint('Content version changed: $_cachedContentVersion -> $remoteVersion');
        _topics = {};
        await _storage.save('topics_cache', {});
        
        // 清除所有领域的缓存
        for (final domain in _domains) {
          await _storage.save('domain_cache_${domain.id}', null);
        }
        
        await _storage.save('content_version', remoteVersion);
        _cachedContentVersion = remoteVersion;
      } else {
        // 5. 从缓存加载 topics
        final cached = await _storage.load('topics_cache');
        if (cached != null && cached is Map<String, dynamic>) {
          _topics = cached.map(
            (k, v) => MapEntry(k, Topic.fromJson(v as Map<String, dynamic>)),
          );
          await _pruneCachedTopics();
        }
      }

      _isLoading = false;
      notifyListeners();

      // 6. 自动加载默认 domain 的 topics（后台加载，不阻塞 UI）
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

  /// 检查并更新内容（可手动触发或定时触发）
  Future<bool> checkForUpdates() async {
    if (_isCheckingUpdate) return false;

    _isCheckingUpdate = true;
    notifyListeners();

    try {
      final remoteManifest = await _api.fetchManifest();
      final remoteVersion = remoteManifest['contentVersion'] as String?;
      final localVersion = _cachedContentVersion ?? await _storage.load('content_version') as String?;

      if (remoteVersion != null && remoteVersion != localVersion) {
        debugPrint('Content update available: $localVersion -> $remoteVersion');
        _isCheckingUpdate = false;
        notifyListeners();
        return true; // 有更新
      }

      _isCheckingUpdate = false;
      notifyListeners();
      return false; // 无更新
    } catch (e) {
      debugPrint('Failed to check for updates: $e');
      _isCheckingUpdate = false;
      notifyListeners();
      return false;
    }
  }

  /// 执行内容更新
  Future<void> performUpdate() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 清除缓存
      _topics = {};
      await _storage.save('topics_cache', {});

      // 重新加载内容
      await loadContent();
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

      // 检查该领域是否已缓存
      final cachedDomain = await _storage.load('domain_cache_$domainId');
      if (cachedDomain != null && cachedDomain is Map<String, dynamic>) {
        // 从缓存加载该领域的 topics
        final cachedTopics = cachedDomain.map(
          (k, v) => MapEntry(k, Topic.fromJson(v as Map<String, dynamic>)),
        );
        _topics.addAll(cachedTopics);
        _isLoadingTopics = false;
        notifyListeners();
        return;
      }

      // 缓存中没有，从网络加载
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

      // 只缓存当前领域的 topics
      final domainTopics = Map.fromEntries(
        _topics.entries.where((e) => e.value.domainId == domainId),
      );
      await _storage.save(
        'domain_cache_$domainId',
        domainTopics.map((k, v) => MapEntry(k, v.toJson())),
      );

      _isLoadingTopics = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoadingTopics = false;
      notifyListeners();
    }
  }

  /// 清除指定领域的缓存
  Future<void> clearDomainCache(String domainId) async {
    await _storage.save('domain_cache_$domainId', null);
    _topics.removeWhere((key, topic) => topic.domainId == domainId);
    notifyListeners();
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    for (final domain in _domains) {
      await _storage.save('domain_cache_${domain.id}', null);
    }
    _topics = {};
    notifyListeners();
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
    return _topics.values.where((t) => t.domainId == domainId).toList()
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

  Topic? findTopic(String topicId) {
    final direct = _topics[topicId];
    if (direct != null) return direct;
    for (final topic in _topics.values) {
      if (topic.id == topicId) return topic;
    }
    return null;
  }

  /// 切换知识源环境：更新 baseUrl 并重载内容
  Future<void> switchContentEnv(String newBaseUrl) async {
    _api.switchBaseUrl(newBaseUrl);
    _domains = [];
    _topics = {};
    _manifest = null;
    notifyListeners();
    await loadContent();
  }

  Set<String> _referencedTopicPaths() {
    final refs = <String>{};
    for (final domain in _domains) {
      for (final category in domain.categories) {
        for (final topicPath in category.topics) {
          refs.add(topicPath.replaceAll('topics/', '').replaceAll('.json', ''));
        }
      }
    }
    return refs;
  }

  Future<void> _pruneCachedTopics() async {
    final refs = _referencedTopicPaths();
    if (refs.isEmpty || _topics.isEmpty) return;

    final before = _topics.length;
    _topics.removeWhere(
      (cacheKey, topic) =>
          !refs.contains(cacheKey) &&
          !refs.contains('${topic.domain}/${topic.id.split('.').last}'),
    );

    if (_topics.length != before) {
      await _storage.save(
        'topics_cache',
        _topics.map((k, v) => MapEntry(k, v.toJson())),
      );
    }
  }
}
