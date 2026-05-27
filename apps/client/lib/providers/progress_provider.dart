import 'package:flutter/material.dart';
import '../models/topic.dart';
import '../models/user_progress.dart';
import '../services/storage_service.dart';

class ProgressProvider extends ChangeNotifier {
  final StorageService _storage;

  ProgressProvider(this._storage);

  Map<String, TopicProgress> _progressMap = {};
  List<PracticeSession> _sessions = [];

  Map<String, TopicProgress> get progressMap => _progressMap;
  List<PracticeSession> get sessions => _sessions;

  Future<void> loadProgress() async {
    _progressMap = await _storage.loadProgressMap();
    _sessions = await _storage.loadSessions();
    notifyListeners();
  }

  Future<void> updateProgress(String topicId, int score, String status) async {
    final existing = _progressMap[topicId];
    _progressMap[topicId] = TopicProgress(
      topicId: topicId,
      score: score,
      status: status,
      practiceCount: (existing?.practiceCount ?? 0) + 1,
      lastPracticeAt: DateTime.now(),
      nextReviewAt: _calculateNextReview(score),
    );
    await _storage.saveProgressMap(_progressMap);
    notifyListeners();
  }

  Future<void> updateTopicProgress(String topicId, {required int score}) async {
    final status = score >= 85 ? 'mastered' : (score >= 60 ? 'learning' : 'new');
    await updateProgress(topicId, score, status);
  }

  DateTime _calculateNextReview(int score) {
    final now = DateTime.now();
    // Simple spaced repetition: higher score = longer interval
    if (score >= 85) return now.add(const Duration(days: 7));
    if (score >= 60) return now.add(const Duration(days: 3));
    return now.add(const Duration(days: 1));
  }

  Future<void> addSession(PracticeSession session) async {
    _sessions.add(session);
    await _storage.saveSessions(_sessions);
    notifyListeners();
  }

  TopicProgress? getProgress(String topicId) => _progressMap[topicId];

  /// Alias for getProgress
  TopicProgress? getTopicProgress(String topicId) => getProgress(topicId);

  /// Returns (masteryPercent, topicCount) for a domain
  ({int masteryPercent, int topicCount}) getDomainProgress(String domainId, List<Topic> topics) {
    final domainTopics = topics.where((t) => t.domainId == domainId).toList();
    if (domainTopics.isEmpty) return (masteryPercent: 0, topicCount: 0);

    double totalScore = 0;
    int count = 0;
    for (final topic in domainTopics) {
      final progress = _progressMap[topic.id];
      if (progress != null) {
        totalScore += progress.score;
        count++;
      }
    }

    if (count == 0) return (masteryPercent: 0, topicCount: domainTopics.length);
    return (masteryPercent: (totalScore / domainTopics.length).round(), topicCount: domainTopics.length);
  }

  int getReviewCount(String domainId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _progressMap.values.where((p) {
      if (p.nextReviewAt == null) return false;
      final reviewDate = DateTime(
        p.nextReviewAt!.year,
        p.nextReviewAt!.month,
        p.nextReviewAt!.day,
      );
      return !reviewDate.isAfter(today);
    }).length;
  }

  List<Topic> getRecommendedTopics(
    String domainId,
    List<Topic> topics,
    String strategy,
  ) {
    final domainTopics = topics.where((t) => t.domainId == domainId).toList();
    final result = List<Topic>.from(domainTopics);

    switch (strategy) {
      case 'low-score-first':
        result.sort((a, b) {
          final scoreA = _progressMap[a.id]?.score ?? 0;
          final scoreB = _progressMap[b.id]?.score ?? 0;
          return scoreA.compareTo(scoreB);
        });
        break;
      case 'path-order':
        result.sort((a, b) => a.order.compareTo(b.order));
        break;
      case 'high-frequency':
        result.sort((a, b) {
          if (a.highFrequency && !b.highFrequency) return -1;
          if (!a.highFrequency && b.highFrequency) return 1;
          final scoreA = _progressMap[a.id]?.score ?? 0;
          final scoreB = _progressMap[b.id]?.score ?? 0;
          return scoreA.compareTo(scoreB);
        });
        break;
    }

    return result;
  }

  List<Topic> getTodayReviewTopics(List<Topic> topics) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return topics.where((t) {
      final progress = _progressMap[t.id];
      if (progress == null) return false;
      if (progress.nextReviewAt == null) return false;
      final reviewDate = DateTime(
        progress.nextReviewAt!.year,
        progress.nextReviewAt!.month,
        progress.nextReviewAt!.day,
      );
      return !reviewDate.isAfter(today);
    }).toList();
  }

  /// 导出所有进度数据
  Map<String, dynamic> exportProgress() {
    return _progressMap.map((k, v) => MapEntry(k, v.toJson()));
  }

  /// 从云端合并进度数据
  Future<void> mergeFromCloud(Map<String, dynamic> cloudProgress) async {
    for (final entry in cloudProgress.entries) {
      final topicId = entry.key;
      final cloudData = entry.value as Map<String, dynamic>;
      final localProgress = _progressMap[topicId];

      if (localProgress == null) {
        // 本地没有，直接使用云端数据
        _progressMap[topicId] = TopicProgress.fromJson(cloudData);
      } else {
        // 合并策略：保留分数更高的
        final cloudScore = cloudData['score'] as int? ?? 0;
        if (cloudScore > localProgress.score) {
          _progressMap[topicId] = TopicProgress.fromJson(cloudData);
        }
      }
    }

    await _storage.saveProgressMap(_progressMap);
    notifyListeners();
  }
}
