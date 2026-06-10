import 'package:flutter/material.dart';
import '../models/topic.dart';
import '../models/user_progress.dart';
import '../services/storage_service.dart';

enum MasteryStatus { new_, learning, skilled }

class ProgressProvider extends ChangeNotifier {
  final StorageService _storage;

  ProgressProvider(this._storage);

  Map<String, TopicProgress> _progressMap = {};
  List<PracticeSession> _sessions = [];
  List<PracticeAttempt> _attempts = [];
  List<MockInterviewSession> _mockSessions = [];
  PrepPlan _prepPlan = PrepPlan.empty();
  LocalProfile _localProfile = LocalProfile.defaultProfile();
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
    final status = computeMastery(topicId, progressMap: _progressMap, attempts: _attempts);
    await updateProgress(topicId, score, status.name);
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
      if (!_topicBelongsToDomain(p.topicId, domainId)) return false;
      if (p.nextReviewAt == null) return false;
      final reviewDate = DateTime(
        p.nextReviewAt!.year,
        p.nextReviewAt!.month,
        p.nextReviewAt!.day,
      );
      return !reviewDate.isAfter(today);
    }).length;
  }

  bool _topicBelongsToDomain(String topicId, String domainId) {
    return topicId == domainId || topicId.startsWith('$domainId.');
  }

  List<Topic> getRecommendedTopics(
    String? domainId,
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
    // 跨域路线模式：topics 已经是预过滤的跨域列表，不再按 domainId 过滤
    final domainTopics = domainId != null
        ? topics.where((t) => t.domainId == domainId).toList()
        : List<Topic>.from(topics);
    final result = List<Topic>.from(domainTopics);

    switch (strategy) {
      case 'smart':
        final availableTopicIds = domainTopics.map((t) => t.id).toSet();
        final prerequisiteDemand = _prerequisiteDemand(
          domainTopics,
          availableTopicIds,
        );
        // Schwartzian transform: compute score once per topic, sort by cached value.
        final scored = result.map((t) {
          final s = _recommendationScore(
            t,
            availableTopicIds: availableTopicIds,
            prerequisiteDemand: prerequisiteDemand[t.id] ?? 0,
            lowScoreWeight: lowScoreWeight,
            overdueWeight: overdueWeight,
            highFrequencyWeight: highFrequencyWeight,
            pathOrderWeight: pathOrderWeight,
            notPracticedWeight: notPracticedWeight,
            prioritizePrerequisites: prioritizePrerequisites,
            allowSkipLowFrequency: allowSkipLowFrequency,
          );
          return (topic: t, score: s);
        }).toList()
          ..sort((a, b) => b.score.compareTo(a.score));
        result
          ..clear()
          ..addAll(scored.map((e) => e.topic));
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
    required Set<String> availableTopicIds,
    required int prerequisiteDemand,
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
    final unreadyPrerequisitePenalty = prioritizePrerequisites
        ? _unreadyPrerequisiteCount(topic, availableTopicIds) * 2500
        : 0;
    final prerequisiteDemandBoost = prioritizePrerequisites
        ? prerequisiteDemand * 150
        : 0;
    return lowScorePart +
        overduePart +
        highFrequencyPart +
        pathPart +
        notPracticedPart -
        lowFrequencyPenalty -
        unreadyPrerequisitePenalty +
        prerequisiteDemandBoost;
  }

  Map<String, int> _prerequisiteDemand(
    List<Topic> topics,
    Set<String> availableTopicIds,
  ) {
    final result = <String, int>{};
    for (final topic in topics) {
      for (final prerequisiteId in topic.prerequisites) {
        if (!availableTopicIds.contains(prerequisiteId)) continue;
        if (_isPrerequisiteReady(prerequisiteId)) continue;
        result[prerequisiteId] = (result[prerequisiteId] ?? 0) + 1;
      }
    }
    return result;
  }

  int _unreadyPrerequisiteCount(Topic topic, Set<String> availableTopicIds) {
    var count = 0;
    for (final prerequisiteId in topic.prerequisites) {
      if (!availableTopicIds.contains(prerequisiteId)) continue;
      if (!_isPrerequisiteReady(prerequisiteId)) count++;
    }
    return count;
  }

  bool _isPrerequisiteReady(String topicId) =>
      (_progressMap[topicId]?.score ?? 0) >= 60;

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

  /// 今日计划：依据备考目标的每日配额，从学习范围内组装"今日应学清单"。
  /// - 复习项：今日到期（nextReviewAt <= 今天），按到期顺序取前 [reviewCount] 个；
  /// - 新知识点：从未练习过的 topic，按内容侧 `Topic.order`（由浅到难）取前 [newCount] 个，
  ///   不与复习项重复。
  ///
  /// 排序所有权遵循 L-3：新知识点默认顺序使用内容库维护的 order，App 不擅自重排。
  ({List<Topic> reviewTopics, List<Topic> newTopics}) getTodayPlan(
    List<Topic> scopedTopics, {
    required int newCount,
    required int reviewCount,
  }) {
    final reviewTopics =
        getTodayReviewTopics(scopedTopics).take(reviewCount.clamp(0, 999)).toList();
    final reviewIds = reviewTopics.map((t) => t.id).toSet();

    final newCandidates = scopedTopics.where((t) {
      if (reviewIds.contains(t.id)) return false;
      final p = _progressMap[t.id];
      return p == null || p.practiceCount == 0;
    }).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final newTopics = newCandidates.take(newCount.clamp(0, 999)).toList();
    return (reviewTopics: reviewTopics, newTopics: newTopics);
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
    // 连续学习天数：不局限于"练习记录"，模拟面试与各知识点的最近练习时间
    // 同样视为当日有学习行为，避免只做模拟面试/复习时口径过窄。
    final dates = <DateTime>{
      ..._attempts.map(
        (a) => DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day),
      ),
      ..._mockSessions.map(
        (s) => DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day),
      ),
      ..._progressMap.values
          .where((p) => p.lastPracticeAt != null)
          .map((p) => DateTime(
                p.lastPracticeAt!.year,
                p.lastPracticeAt!.month,
                p.lastPracticeAt!.day,
              )),
    };
    var streak = 0;
    var cursor = DateTime.now();
    while (dates.contains(DateTime(cursor.year, cursor.month, cursor.day))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int readinessScore(List<Topic> topics) {
    return routeReadinessScore(
      routeTopicIds: topics.map((t) => t.id).toList(),
      allTopics: topics,
    );
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

  /// 统一掌握度判定：最近 2 次 >= 85 且间隔 > 1 小时为 skilled
  static MasteryStatus computeMastery(
    String topicId, {
    required Map<String, TopicProgress> progressMap,
    required List<PracticeAttempt> attempts,
  }) {
    final progress = progressMap[topicId];
    if (progress == null) return MasteryStatus.new_;
    if (progress.score < 60) return MasteryStatus.new_;

    if (progress.score >= 85) {
      final scoredAttempts = attempts
          .where((a) => a.topicId == topicId && a.score != null)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final highScoreAttempts = scoredAttempts
          .where((a) => a.score! >= 85)
          .toList();

      if (highScoreAttempts.length >= 2) {
        final gap = highScoreAttempts[0].createdAt
            .difference(highScoreAttempts[1].createdAt);
        if (gap.inHours >= 1) return MasteryStatus.skilled;
      }
      return MasteryStatus.learning;
    }
    return MasteryStatus.learning;
  }

  /// 路线限定范围内的准备度
  int routeReadinessScore({
    required List<String> routeTopicIds,
    required List<Topic> allTopics,
  }) {
    final scopedTopics = allTopics.where((t) => routeTopicIds.contains(t.id)).toList();
    if (scopedTopics.isEmpty) return 0;

    final hasScored = scopedTopics.any(
      (t) => (_progressMap[t.id]?.score ?? 0) > 0,
    );
    if (!hasScored && _mockSessions.isEmpty) return 0;

    final avgScore = scopedTopics
        .map((t) => _progressMap[t.id]?.score ?? 0)
        .fold<int>(0, (sum, s) => sum + s) /
        scopedTopics.length;

    final relevantMocks = _mockSessions.where(
      (s) => s.topicIds.any((id) => routeTopicIds.contains(id)),
    ).toList();

    final mockCount = relevantMocks.take(3).length;
    final mockAvg = relevantMocks.isEmpty
        ? avgScore
        : relevantMocks
              .take(3)
              .map((s) => s.averageScore)
              .fold<int>(0, (a, b) => a + b) /
          mockCount;

    final streakBonus = (practiceStreakDays.clamp(0, 14) * 1.5).round();
    final reviewPenalty = (getTodayReviewTopics(scopedTopics).length.clamp(0, 10) * 2);

    return ((avgScore * 0.50 + mockAvg * 0.35 + streakBonus) - reviewPenalty)
        .round().clamp(0, 100);
  }

  /// 导出所有进度数据
  Map<String, dynamic> exportProgress() {
    return _progressMap.map((k, v) => MapEntry(k, v.toJson()));
  }
}
