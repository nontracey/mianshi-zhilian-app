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
  String _currentDomain = 'java';
  bool _isLoading = false;
  String? _error;

  List<Domain> get domains => _domains;
  Map<String, Topic> get topics => _topics;
  Map<String, dynamic>? get manifest => _manifest;
  String get currentDomain => _currentDomain;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadContent() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _manifest = await _api.fetchManifest();
      final domainList = _manifest?['domains'] as List<dynamic>? ?? [];
      _domains = domainList
          .map((e) => Domain.fromJson(e as Map<String, dynamic>))
          .toList();

      // Try to load cached topics from storage
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
      final manifestTopics = _manifest?['topics'] as Map<String, dynamic>?;
      final topicIds = (manifestTopics?[domainId] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList();

      for (final topicId in topicIds) {
        if (!_topics.containsKey(topicId)) {
          final topic = await _api.fetchTopic(topicId);
          _topics[topicId] = topic;
        }
      }

      // Cache topics
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

  void setCurrentDomain(String domainId) {
    _currentDomain = domainId;
    notifyListeners();
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
    // 清空缓存，重新加载
    _domains = [];
    _topics = {};
    _manifest = null;
    notifyListeners();
    await loadContent();
  }
}
