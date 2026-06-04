import 'package:flutter/material.dart';
import '../models/topic.dart';
import '../models/user_progress.dart';
import '../services/storage_service.dart';

class ProgressProvider extends ChangeNotifier {
  final StorageService _storage;

  ProgressProvider(this._storage);

  Map<String, TopicProgress> _progressMap = {};
  List<PracticeSession> _sessions = [];
  List<PracticeAttempt> _attempts = [];
  List<MockInterviewSession> _mockSessions = [];
  PrepPlan _prepPlan = PrepPlan.empty();
  LocalProfile _localProfile = const LocalProfile();
  SyncSettings _syncSettings = const SyncSettings();

  Map<String, TopicProgress> get progressMap => _progressMap;
  List<PracticeSession> get sessions => _sessions;
  List<PracticeAttempt> get attempts => _attempts;
  List<MockInterviewSession> get mockSessions => _mockSessions;
  PrepPlan get prepPlan => _prepPlan;
  LocalProfile get localProfile => _localProfile;
  SyncSettings get syncSettings => _syncSettings;

  Future<void> loadProgress() async {
    _progressMap = await _storage.loadProgressMap();
    _sessions = await _storage.loadSessions();
    _attempts = await _storage.loadPracticeAttempts();
    _mockSessions = await _storage.loadMockInterviewSessions();
    _prepPlan = await _storage.loadPrepPlan();
    _localProfile = await _storage.loadLocalProfile();
    _syncSettings = await _storage.loadSyncSettings();
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
    final status = score >= 85
        ? 'mastered'
        : (score >= 60 ? 'learning' : 'new');
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

  Future<void> addAttempt(PracticeAttempt attempt) async {
    _attempts.insert(0, attempt);
    await _storage.savePracticeAttempts(_attempts);
    notifyListeners();
  }

  Future<void> deleteAttempt(String attemptId) async {
    _attempts.removeWhere((attempt) => attempt.id == attemptId);
    await _storage.savePracticeAttempts(_attempts);
    notifyListeners();
  }

  Future<void> clearPracticeData() async {
    _progressMap = {};
    _sessions = [];
    _attempts = [];
    _mockSessions = [];
    await _storage.clearPracticeData();
    notifyListeners();
  }

  Future<void> addMockSession(MockInterviewSession session) async {
    _mockSessions.insert(0, session);
    await _storage.saveMockInterviewSessions(_mockSessions);
    notifyListeners();
  }

  Future<void> updatePrepPlan(PrepPlan plan) async {
    _prepPlan = plan;
    await _storage.savePrepPlan(plan);
    notifyListeners();
  }

  Future<void> updateLocalProfile(LocalProfile profile) async {
    _localProfile = profile;
    await _storage.saveLocalProfile(profile);
    notifyListeners();
  }

  Future<void> updateSyncSettings(SyncSettings settings) async {
    _syncSettings = settings;
    await _storage.saveSyncSettings(settings);
    notifyListeners();
  }

  TopicProgress? getProgress(String topicId) => _progressMap[topicId];

  /// Alias for getProgress
  TopicProgress? getTopicProgress(String topicId) => getProgress(topicId);

  /// Returns (masteryPercent, topicCount) for a domain
  ({int masteryPercent, int topicCount}) getDomainProgress(
    String domainId,
    List<Topic> topics,
  ) {
    final domainTopics = topics.where((t) => t.domainId == domainId).toList();
    if (domainTopics.isEmpty) return (masteryPercent: 0, topicCount: 0);

    double totalScore = 0;
    int count = 0;
    for (final topic in domainTopics) {
      final progress = _progressMap[topic.id];
      if (progress != null && progress.score > 0) {
        totalScore += progress.score;
        count++;
      }
    }

    // 没有学习过的知识点，掌握度为0
    if (count == 0) return (masteryPercent: 0, topicCount: domainTopics.length);

    // 计算综合掌握度：平均分 × 覆盖率
    final avgScore = totalScore / count;
    final coverage = count / domainTopics.length;
    final masteryPercent = (avgScore * coverage).round();

    return (masteryPercent: masteryPercent, topicCount: domainTopics.length);
  }

  /// 获取指定领域的练习总次数
  int getDomainPracticeCount(String domainId, List<Topic> topics) {
    final domainTopicIds = topics
        .where((t) => t.domainId == domainId)
        .map((t) => t.id)
        .toSet();
    return _progressMap.entries
        .where((e) => domainTopicIds.contains(e.key))
        .fold<int>(0, (sum, e) => sum + e.value.practiceCount);
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
    String strategy, {
    int lowScoreWeight = 35,
    int overdueWeight = 25,
    int highFrequencyWeight = 25,
    int pathOrderWeight = 10,
    int notPracticedWeight = 5,
    bool prioritizePrerequisites = true,
    bool allowSkipLowFrequency = false,
  }) {
    final domainTopics = topics.where((t) => t.domainId == domainId).toList();
    final result = List<Topic>.from(domainTopics);

    switch (strategy) {
      case 'smart':
        result.sort((a, b) {
          final scoreA = _recommendationScore(
            a,
            lowScoreWeight: lowScoreWeight,
            overdueWeight: overdueWeight,
            highFrequencyWeight: highFrequencyWeight,
            pathOrderWeight: pathOrderWeight,
            notPracticedWeight: notPracticedWeight,
            prioritizePrerequisites: prioritizePrerequisites,
            allowSkipLowFrequency: allowSkipLowFrequency,
          );
          final scoreB = _recommendationScore(
            b,
            lowScoreWeight: lowScoreWeight,
            overdueWeight: overdueWeight,
            highFrequencyWeight: highFrequencyWeight,
            pathOrderWeight: pathOrderWeight,
            notPracticedWeight: notPracticedWeight,
            prioritizePrerequisites: prioritizePrerequisites,
            allowSkipLowFrequency: allowSkipLowFrequency,
          );
          return scoreB.compareTo(scoreA);
        });
        break;
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
      case 'review-first':
        result.sort((a, b) {
          final dueA = _isReviewDue(_progressMap[a.id]) ? 1 : 0;
          final dueB = _isReviewDue(_progressMap[b.id]) ? 1 : 0;
          if (dueA != dueB) return dueB.compareTo(dueA);
          final scoreA = _progressMap[a.id]?.score ?? 0;
          final scoreB = _progressMap[b.id]?.score ?? 0;
          return scoreA.compareTo(scoreB);
        });
        break;
    }

    return result;
  }

  int _recommendationScore(
    Topic topic, {
    required int lowScoreWeight,
    required int overdueWeight,
    required int highFrequencyWeight,
    required int pathOrderWeight,
    required int notPracticedWeight,
    required bool prioritizePrerequisites,
    required bool allowSkipLowFrequency,
  }) {
    final progress = _progressMap[topic.id];
    final score = progress?.score ?? 0;
    final lowScorePart = (100 - score).clamp(0, 100) * lowScoreWeight;
    final overduePart = _isReviewDue(progress) ? 100 * overdueWeight : 0;
    final highFrequencyPart =
        (topic.highFrequency ? 100 : topic.recommendWeight) *
        highFrequencyWeight;
    final pathPart =
        (10000 - topic.order).clamp(0, 10000) * pathOrderWeight ~/ 100;
    final notPracticedPart = progress == null ? 100 * notPracticedWeight : 0;
    final lowFrequencyPenalty =
        !allowSkipLowFrequency && topic.interviewFrequency == 'low' ? 500 : 0;
    return lowScorePart +
        overduePart +
        highFrequencyPart +
        pathPart +
        notPracticedPart -
        lowFrequencyPenalty;
  }

  bool _isReviewDue(TopicProgress? progress) {
    if (progress?.nextReviewAt == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final review = progress!.nextReviewAt!;
    final reviewDate = DateTime(review.year, review.month, review.day);
    return !reviewDate.isAfter(today);
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

  List<PracticeAttempt> getAttemptsForTopic(String topicId) =>
      _attempts.where((a) => a.topicId == topicId).toList();

  List<PracticeAttempt> get lowScoreAttempts =>
      _attempts.where((a) => (a.score ?? 100) < 60).toList();

  /// 超过 N 天未复习的知识点 ID 列表
  List<String> getLongUnreviewedTopicIds(List<Topic> topics, {int days = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final result = <String>[];
    for (final topic in topics) {
      final attempts = getAttemptsForTopic(topic.id);
      if (attempts.isEmpty) {
        result.add(topic.id);
        continue;
      }
      final lastAttempt = attempts.first.createdAt;
      if (lastAttempt.isBefore(cutoff)) {
        result.add(topic.id);
      }
    }
    return result;
  }

  /// 最近退步的知识点 ID 列表（最近一次分数低于上一次）
  List<String> getRegressedTopicIds(List<Topic> topics) {
    final result = <String>[];
    for (final topic in topics) {
      final attempts = getAttemptsForTopic(topic.id);
      if (attempts.length < 2) continue;
      // attempts 按时间倒序，第一个是最新的
      final latest = attempts[0].score ?? 0;
      final previous = attempts[1].score ?? 0;
      if (latest < previous) {
        result.add(topic.id);
      }
    }
    return result;
  }

  int get practiceStreakDays {
    final dates = _attempts
        .map(
          (a) => DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day),
        )
        .toSet();
    var streak = 0;
    var cursor = DateTime.now();
    while (dates.contains(DateTime(cursor.year, cursor.month, cursor.day))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int readinessScore(List<Topic> topics) {
    if (topics.isEmpty) return 0;
    final hasScoredProgress = topics.any(
      (topic) => (_progressMap[topic.id]?.score ?? 0) > 0,
    );
    if (!hasScoredProgress && _mockSessions.isEmpty) return 0;

    final domainAverage =
        topics
            .map((t) => _progressMap[t.id]?.score ?? 0)
            .fold<int>(0, (sum, score) => sum + score) ~/
        topics.length;
    final reviewPenalty = getTodayReviewTopics(topics).length.clamp(0, 10) * 2;
    final mockAverage = _mockSessions.isEmpty
        ? domainAverage
        : _mockSessions
                  .take(3)
                  .map((s) => s.averageScore)
                  .fold<int>(0, (a, b) => a + b) ~/
              _mockSessions.take(3).length;
    return ((domainAverage * 0.55 +
                mockAverage * 0.35 +
                practiceStreakDays * 2) -
            reviewPenalty)
        .round()
        .clamp(0, 100);
  }

  /// 连续学习天数（别名）
  int get streakDays => practiceStreakDays;

  /// 获取薄弱知识点 Top N（按分数升序）
  List<Topic> getWeakTopics(List<Topic> topics, {int limit = 5}) {
    final scored = topics
        .where((t) => (_progressMap[t.id]?.score ?? 0) > 0)
        .toList();
    scored.sort(
      (a, b) => (_progressMap[a.id]?.score ?? 0).compareTo(
        _progressMap[b.id]?.score ?? 0,
      ),
    );
    return scored.take(limit).toList();
  }

  /// 最近练习记录（按时间降序）
  List<PracticeAttempt> get recentAttempts {
    final sorted = List<PracticeAttempt>.from(_attempts)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  /// 总练习次数
  int get totalPracticeCount {
    return _progressMap.values.fold<int>(0, (sum, p) => sum + p.practiceCount);
  }

  /// 总学习时长（小时），基于练习次数估算（每次约10分钟）
  double get totalHours {
    return totalPracticeCount * 10 / 60;
  }

  /// 今日学习时长增长（小时）
  double get todayHoursGrowth {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayAttempts = _attempts
        .where((a) => a.createdAt.isAfter(todayStart))
        .length;
    return todayAttempts * 10 / 60;
  }

  /// 获取掌握度趋势数据（最近7天的平均分）
  List<double?> getMasteryTrend() {
    final now = DateTime.now();
    final trend = <double?>[];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final dayAttempts = _attempts
          .where(
            (a) =>
                a.createdAt.isAfter(dayStart) &&
                a.createdAt.isBefore(dayEnd) &&
                a.score != null,
          )
          .toList();

      if (dayAttempts.isNotEmpty) {
        final avgScore =
            dayAttempts.fold<double>(0, (sum, a) => sum + (a.score ?? 0)) /
            dayAttempts.length;
        trend.add(avgScore);
      } else {
        // 如果当天没有数据，返回 null
        trend.add(null);
      }
    }

    return trend;
  }

  /// 导出所有进度数据
  Map<String, dynamic> exportProgress() {
    return _progressMap.map((k, v) => MapEntry(k, v.toJson()));
  }

  /// 从云端合并进度数据。
  /// 合并策略：保留每 topic 的最高分；同分时保留更高的练习次数和更早的下次复习时间。
  Future<void> mergeFromCloud(Map<String, dynamic> cloudProgress) async {
    for (final entry in cloudProgress.entries) {
      final topicId = entry.key;
      final cloudData = entry.value as Map<String, dynamic>;
      final localProgress = _progressMap[topicId];

      if (localProgress == null) {
        _progressMap[topicId] = TopicProgress.fromJson(cloudData);
      } else {
        final cloudScore = cloudData['score'] as int? ?? 0;
        final cloudPracticeCount = cloudData['practiceCount'] as int? ?? 0;

        if (cloudScore > localProgress.score ||
            (cloudScore == localProgress.score &&
                cloudPracticeCount > localProgress.practiceCount)) {
          var merged = TopicProgress.fromJson(cloudData);
          // 保留更早的下次复习时间
          if (localProgress.nextReviewAt != null &&
              merged.nextReviewAt != null &&
              localProgress.nextReviewAt!.isBefore(merged.nextReviewAt!)) {
            merged = merged.copyWith(nextReviewAt: localProgress.nextReviewAt);
          }
          _progressMap[topicId] = merged;
        }
      }
    }

    await _storage.saveProgressMap(_progressMap);
    notifyListeners();
  }
}
