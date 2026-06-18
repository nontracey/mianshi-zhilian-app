import 'dart:async';

import 'package:flutter/material.dart';
import '../models/domain.dart';
import '../models/topic.dart';
import '../services/app_log_service.dart';
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
  int _loadingDomainCount = 0; // 并发加载中的领域数；>0 即 isLoadingTopics
  bool _isCheckingUpdate = false;
  String? _error;
  List<String> _topicLoadFailures = [];
  String? _cachedContentVersion;
  int _loadEpoch = 0;

  /// 当前正在进行的同域加载 Future，避免 ensureTopicsLoaded 并发触发重复网络请求。
  final Map<String, Future<void>> _pendingDomainLoads = {};

  List<Domain> get domains => _domains;

  /// 返回按 topic.id 去重后的 topic 映射（key = topic.id）。
  /// `_topics` 内部可能以 cacheKey（斜杠）和 topic.id（点号）双键存储同一对象；
  /// 通过此 getter 暴露给外部的视图始终去重，确保 values / length / keys 不翻倍。
  Map<String, Topic> get topics {
    final seen = <String, Topic>{};
    for (final t in _topics.values) {
      seen[t.id] = t;
    }
    return seen;
  }

  Map<String, dynamic>? get manifest => _manifest;
  bool get isLoading => _isLoading;
  bool get isLoadingTopics => _loadingDomainCount > 0;
  bool get isCheckingUpdate => _isCheckingUpdate;
  String? get error => _error;
  List<String> get topicLoadFailures => List.unmodifiable(_topicLoadFailures);
  String? get contentVersion => _cachedContentVersion;
  String get contentBaseUrl => _api.baseUrl;

  String get _cacheScope => _api.baseUrl
      .replaceAll(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  String _cacheKey(String key) => 'content_cache_${_cacheScope}_$key';

  String _domainCacheKey(String domainId) =>
      _cacheKey('domain_cache_$domainId');

  String _domainVersionKey(String domainId) =>
      _cacheKey('domain_version_$domainId');

  Future<void> loadContent({String? currentDomainId}) async {
    final epoch = ++_loadEpoch;
    _isLoading = true;
    _error = null;
    _topicLoadFailures = [];
    notifyListeners();

    try {
      // 1. 加载 manifest 获取 domain 列表
      _manifest = await _api.fetchManifest();
      if (epoch != _loadEpoch) return;
      final domainList = _manifest?['domains'] as List<dynamic>? ?? [];

      // 2. 从 manifest 创建基础 Domain 对象
      final baseDomains = domainList
          .map((e) => Domain.fromJson(e as Map<String, dynamic>))
          .toList();

      // 3. 并发加载 domain 详情（含 categories），保持 manifest 顺序输出。
      final fullDomains = await Future.wait(
        baseDomains.map((domain) async {
          try {
            final fullDomain = await _api.fetchDomain(
              domain.id,
              entry: domain.entry,
            );
            return Domain(
              id: fullDomain.id,
              title: fullDomain.title,
              description: fullDomain.description,
              icon: fullDomain.icon,
              themeColor: fullDomain.themeColor,
              accentColor: fullDomain.accentColor,
              entry: domain.entry,
              categories: fullDomain.categories,
              learningPaths: fullDomain.learningPaths,
              topicCount: domain.topicCount,
              updatedAt: domain.updatedAt,
              color: fullDomain.color,
            );
          } catch (e) {
            debugPrint('Failed to load domain detail ${domain.id}: $e');
            return domain;
          }
        }),
      );
      if (epoch != _loadEpoch) return;
      _domains = fullDomains;

      // 4. 检查内容版本是否有更新
      final remoteVersion = _manifest?['contentVersion'] as String?;
      _cachedContentVersion =
          await _storage.load(_cacheKey('content_version')) as String?;

      if (remoteVersion != null && remoteVersion != _cachedContentVersion) {
        // 内容有更新，标记需要刷新（不清除缓存，切换领域时按需刷新）
        debugPrint(
          'Content version changed: $_cachedContentVersion -> $remoteVersion',
        );
        await _storage.save(_cacheKey('content_version'), remoteVersion);
        _cachedContentVersion = remoteVersion;
        // 记录需要刷新的版本，切换领域时会检查
        await _storage.save(
          _cacheKey('content_version_pending'),
          remoteVersion,
        );

        // 清理已删除领域的缓存
        await _cleanupDeletedDomains();
      } else {
        // 5. 从缓存加载 topics
        final cached = await _storage.load(_cacheKey('topics_cache'));
        if (cached != null && cached is Map<String, dynamic>) {
          final loaded = cached.map(
            (k, v) => MapEntry(k, Topic.fromJson(v as Map<String, dynamic>)),
          );
          _topics = <String, Topic>{};
          for (final entry in loaded.entries) {
            _topics[entry.key] = entry.value;
            if (entry.value.id.isNotEmpty && entry.value.id != entry.key) {
              _topics[entry.value.id] ??= entry.value;
            }
          }
          await _pruneCachedTopics();
        }
      }

      _isLoading = false;
      notifyListeners();

      // 6. 自动加载指定领域或默认领域的 topics（后台加载，不阻塞 UI）
      final domainToLoad =
          currentDomainId ?? _manifest?['defaultDomain'] as String? ?? 'java';
      if (_topics.values.where((t) => t.domainId == domainToLoad).isEmpty) {
        loadDomainTopics(domainToLoad);
      }
    } catch (e) {
      if (epoch != _loadEpoch) return;
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 检查并更新内容（可手动触发或定时触发）
  Future<bool> checkForUpdates() async {
    if (_isCheckingUpdate) return false;

    _isCheckingUpdate = true;
    unawaited(_storage.recordAnalyticsFeature('update_check'));
    notifyListeners();

    try {
      final remoteManifest = await _api.fetchManifest();
      final remoteVersion = remoteManifest['contentVersion'] as String?;
      final localVersion =
          _cachedContentVersion ??
          await _storage.load(_cacheKey('content_version')) as String?;

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
      await _storage.save(_cacheKey('topics_cache'), {});

      // 重新加载内容
      await loadContent();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDomainTopics(String domainId) {
    // 同域并发去重：若该领域已在加载中，直接复用同一 Future，避免重复网络请求。
    return _pendingDomainLoads[domainId] ??= _loadDomainTopicsInternal(domainId)
        .whenComplete(() {
          _pendingDomainLoads.remove(domainId);
        });
  }

  Future<void> _loadDomainTopicsInternal(String domainId) async {
    final epoch = _loadEpoch;
    _loadingDomainCount++;
    // 不在此重置 _topicLoadFailures：并发加载多个领域时各自的失败都应累积保留。
    // loadContent() 和手动刷新操作负责整体重置。
    notifyListeners();

    try {
      // 找到对应的 domain，从 categories 中获取 topic 路径列表
      final domain = _domains.where((d) => d.id == domainId).firstOrNull;
      if (domain == null) {
        return; // finally 负责递减计数并 notify
      }

      // 检查是否有待刷新的版本
      final pendingVersion =
          await _storage.load(_cacheKey('content_version_pending')) as String?;
      final cachedDomainVersion =
          await _storage.load(_domainVersionKey(domainId)) as String?;
      final needsRefresh =
          pendingVersion != null && pendingVersion != cachedDomainVersion;

      // 检查该领域是否已缓存且不需要刷新
      final cachedDomain = await _storage.load(_domainCacheKey(domainId));
      if (epoch != _loadEpoch) return;
      if (cachedDomain != null &&
          cachedDomain is Map<String, dynamic> &&
          !needsRefresh) {
        // 从缓存加载该领域的 topics
        final cachedTopics = cachedDomain.map(
          (k, v) => MapEntry(k, Topic.fromJson(v as Map<String, dynamic>)),
        );
        for (final entry in cachedTopics.entries) {
          _topics[entry.key] = entry.value;
          if (entry.value.id.isNotEmpty && entry.value.id != entry.key) {
            _topics[entry.value.id] ??= entry.value;
          }
        }
        return; // finally 负责递减计数并 notify
      }

      // 缓存中没有或需要刷新，从网络并发加载
      debugPrint(
        'Loading domain $domainId from network (needsRefresh: $needsRefresh)',
      );
      // 收集所有需要加载的 topic 路径
      final pathsToLoad = <String>[];
      for (final category in domain.categories) {
        for (final topicPath in category.topics) {
          final cacheKey = ContentApiService.cacheKeyForTopicRef(topicPath);
          if (!_topics.containsKey(cacheKey) || needsRefresh) {
            pathsToLoad.add(topicPath);
          }
        }
      }
      // 分批并发加载，每个 topic 独立容错，避免一个坏 JSON/404 拖垮整批。
      const batchSize = 8;
      for (var i = 0; i < pathsToLoad.length; i += batchSize) {
        final batch = pathsToLoad.sublist(
          i,
          (i + batchSize < pathsToLoad.length) ? i + batchSize : null,
        );
        final results = await Future.wait(
          batch.map((path) async {
            try {
              return _TopicLoadResult.success(
                path,
                await _api.fetchTopic(path),
              );
            } catch (e) {
              return _TopicLoadResult.failure(path, e);
            }
          }),
        );
        if (epoch != _loadEpoch) return;
        for (final result in results) {
          final topic = result.topic;
          if (topic != null) {
            final cacheKey = ContentApiService.cacheKeyForTopicRef(result.path);
            _topics[cacheKey] = topic;
            if (topic.id.isNotEmpty && topic.id != cacheKey) {
              _topics[topic.id] ??= topic;
            }
            continue;
          }
          _topicLoadFailures.add(result.path);
          unawaited(_storage.recordAnalyticsFeature('content_load_failed'));
          unawaited(
            AppLog.warning(
              'Content topic load failed: ${result.path}',
              source: 'content',
              error: result.error,
            ),
          );
        }
        // 每批加载完后一次性通知 UI 更新
        notifyListeners();
      }

      // 只缓存当前领域的 topics
      final domainTopics = Map.fromEntries(
        _topics.entries.where((e) => e.value.domainId == domainId),
      );
      await _storage.save(
        _domainCacheKey(domainId),
        domainTopics.map((k, v) => MapEntry(k, v.toJson())),
      );
      if (epoch != _loadEpoch) return;

      // 记录该领域的版本
      if (pendingVersion != null) {
        await _storage.save(_domainVersionKey(domainId), pendingVersion);
      }
    } catch (e) {
      if (epoch != _loadEpoch) return;
      _error = e.toString();
    } finally {
      // 无论成功/失败/提前返回，计数递减且只通知一次，避免并发时提前关闭 loading 态。
      _loadingDomainCount = (_loadingDomainCount - 1).clamp(0, 9999);
      notifyListeners();
    }
  }

  /// 确保指定领域列表的 topics 都已加载。始终调 loadDomainTopics，
  /// 由其内部按缓存和 pendingVersion 判断是否需要网络刷新。
  Future<void> ensureTopicsLoaded(List<String> domainIds) =>
      Future.wait(domainIds.map(loadDomainTopics));

  /// 清除指定领域的缓存
  Future<void> clearDomainCache(String domainId) async {
    await _storage.save(_domainCacheKey(domainId), null);
    _topics.removeWhere((key, topic) => topic.domainId == domainId);
    notifyListeners();
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    for (final domain in _domains) {
      await _storage.save(_domainCacheKey(domain.id), null);
    }
    _topics = {};
    notifyListeners();
  }

  /// 获取指定 domain 下已加载的 topic 数量（去重后计数）
  int getLoadedTopicCount(String domainId) {
    return topics.values.where((t) => t.domainId == domainId).length;
  }

  /// 获取指定 domain 的预期 topic 总数（从 manifest 读取）
  int getTotalTopicCount(String domainId) {
    final domain = _domains.where((d) => d.id == domainId).firstOrNull;
    return domain?.topicCount ?? 0;
  }

  List<Topic> getTopicsByDomain(String domainId) {
    return topics.values.where((t) => t.domainId == domainId).toList()
      ..sort((a, b) {
        // Default learning order is content-driven; difficulty is only used
        // when a page explicitly asks for difficulty sorting.
        return a.order.compareTo(b.order);
      });
  }

  List<Topic> getTopicsByCategories(List<String> categoryIds) {
    return topics.values
        .where((t) => categoryIds.contains(t.categoryId))
        .toList();
  }

  List<Topic> getTopicsByCategory(String domainId, String categoryId) {
    return topics.values
        .where((t) => t.domainId == domainId && t.categoryId == categoryId)
        .toList()
      ..sort((a, b) {
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

  /// 解析前置知识：尝试在当前已加载 topics 中查找，
  /// 若找不到则自动加载对应领域的 topics 并重试。
  ///
  /// topicId 格式为 `{domain}.{category}.{name}`（如 `java.jvm.runtime-data-area`），
  /// 第一段即为 domain ID。
  Future<Topic?> resolvePrerequisiteTopic(String topicId) async {
    // 1. 先尝试当前已加载的 topics
    var topic = findTopic(topicId);
    if (topic != null) return topic;

    // 2. 从 topicId 提取 domain（第一段）
    final dotIndex = topicId.indexOf('.');
    if (dotIndex == -1) return null;
    final domainId = topicId.substring(0, dotIndex);

    // 3. 确认 domain 是否存在于当前 manifest
    final domainExists = _domains.any((d) => d.id == domainId);
    if (!domainExists) return null;

    // 4. 检查该 domain 的 topics 是否已加载
    final alreadyLoaded = _topics.values.any((t) => t.domainId == domainId);
    if (alreadyLoaded) return null; // 已加载但仍未找到，说明该 topic 不存在

    // 5. 加载该领域的 topics
    await loadDomainTopics(domainId);

    // 6. 重试查找
    return findTopic(topicId);
  }

  /// 切换知识源环境：更新 baseUrl 并重载内容
  Future<void> switchContentEnv(
    String newBaseUrl, {
    String? currentDomainId,
  }) async {
    _api.switchBaseUrl(newBaseUrl);
    _loadEpoch++;
    _domains = [];
    _topics = {};
    _topicLoadFailures = [];
    _manifest = null;
    _cachedContentVersion = null;
    _error = null;
    notifyListeners();
    await loadContent(currentDomainId: currentDomainId);
  }

  /// 清理已删除领域的缓存
  Future<void> _cleanupDeletedDomains() async {
    try {
      // 获取当前所有领域 ID
      final currentDomainIds = _domains.map((d) => d.id).toSet();

      // 获取本地缓存的所有 key
      final prefs = await _storage.getInstance();
      final keys = prefs.getKeys();

      // 找出 domain_cache_ 开头的 key
      final domainCachePrefix = _cacheKey('domain_cache_');
      final domainCacheKeys = keys
          .where((k) => k.startsWith(domainCachePrefix))
          .toList();

      for (final key in domainCacheKeys) {
        final domainId = key.replaceFirst(domainCachePrefix, '');
        if (!currentDomainIds.contains(domainId)) {
          // 领域已删除，清除缓存
          debugPrint('Cleaning up deleted domain cache: $domainId');
          await _storage.save(key, null);
          await _storage.save(_domainVersionKey(domainId), null);

          // 从内存中移除该领域的 topics
          _topics.removeWhere((_, topic) => topic.domainId == domainId);
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup deleted domains: $e');
    }
  }

  /// 清空所有领域缓存（用于手动刷新）
  Future<void> clearAllDomainCache() async {
    try {
      _topics = {};

      // 清除所有领域的缓存
      for (final domain in _domains) {
        await _storage.save(_domainCacheKey(domain.id), null);
        await _storage.save(_domainVersionKey(domain.id), null);
      }

      // 清除 topics_cache
      await _storage.save(_cacheKey('topics_cache'), {});

      // 清除 pending version
      await _storage.save(_cacheKey('content_version_pending'), null);

      notifyListeners();
      debugPrint('All domain caches cleared');
    } catch (e) {
      debugPrint('Failed to clear all domain cache: $e');
    }
  }

  Set<String> _referencedTopicPaths() {
    final refs = <String>{};
    for (final domain in _domains) {
      for (final category in domain.categories) {
        for (final topicPath in category.topics) {
          refs.add(ContentApiService.cacheKeyForTopicRef(topicPath));
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
        _cacheKey('topics_cache'),
        _topics.map((k, v) => MapEntry(k, v.toJson())),
      );
    }
  }
}

class _TopicLoadResult {
  const _TopicLoadResult._(this.path, this.topic, this.error);

  factory _TopicLoadResult.success(String path, Topic topic) =>
      _TopicLoadResult._(path, topic, null);

  factory _TopicLoadResult.failure(String path, Object error) =>
      _TopicLoadResult._(path, null, error);

  final String path;
  final Topic? topic;
  final Object? error;
}
