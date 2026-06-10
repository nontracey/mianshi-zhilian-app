import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'readiness remains zero before any scored progress or mock interview',
    () {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      final topics = [
        const Topic(
          id: 'topic-1',
          domain: 'java',
          category: 'concurrency',
          title: 'AQS',
          summary: 'AbstractQueuedSynchronizer',
        ),
      ];

      expect(provider.readinessScore(topics), 0);
    },
  );

  test('smart recommendations prioritize unmet prerequisites', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ProgressProvider(StorageService());
    final prerequisite = const Topic(
      id: 'java.core.base',
      domain: 'java',
      category: 'core',
      title: 'Base',
      summary: 'Base',
      order: 1,
      recommendWeight: 30,
    );
    final advanced = const Topic(
      id: 'java.core.advanced',
      domain: 'java',
      category: 'core',
      title: 'Advanced',
      summary: 'Advanced',
      order: 2,
      recommendWeight: 100,
      prerequisites: ['java.core.base'],
    );

    final before = provider.getRecommendedTopics('java', [
      advanced,
      prerequisite,
    ], 'smart');
    expect(before.first.id, prerequisite.id);

    await provider.updateTopicProgress(prerequisite.id, score: 70);

    final after = provider.getRecommendedTopics('java', [
      advanced,
      prerequisite,
    ], 'smart');
    expect(after.first.id, advanced.id);
  });

  group('getTodayPlan', () {
    List<Topic> buildTopics() => const [
          Topic(id: 'java.a', domain: 'java', category: 'core', title: 'A', summary: 'A', order: 1),
          Topic(id: 'java.b', domain: 'java', category: 'core', title: 'B', summary: 'B', order: 2),
          Topic(id: 'java.c', domain: 'java', category: 'core', title: 'C', summary: 'C', order: 3),
          Topic(id: 'java.d', domain: 'java', category: 'core', title: 'D', summary: 'D', order: 4),
        ];

    test('new topics are never-practiced, ordered by Topic.order, capped by newCount',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      final topics = buildTopics();

      final plan = provider.getTodayPlan(topics, newCount: 2, reviewCount: 5);
      expect(plan.newTopics.map((t) => t.id), ['java.a', 'java.b']);
      expect(plan.reviewTopics, isEmpty);
    });

    test('practiced topics are excluded from new list', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      final topics = buildTopics();
      await provider.updateTopicProgress('java.a', score: 80);

      final plan = provider.getTodayPlan(topics, newCount: 2, reviewCount: 5);
      // java.a 已练习，应跳过，从 b 开始
      expect(plan.newTopics.map((t) => t.id), ['java.b', 'java.c']);
    });

    test('due-for-review topics are not double-counted as new', () async {
      // 直接 seed 一条已到期（nextReviewAt 在昨天）的进度，模拟到期复习项
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({
        'progress_map': '''
{"java.a":{"topicId":"java.a","score":50,"status":"learning","practiceCount":1,"nextReviewAt":"${yesterday.toIso8601String()}"}}
''',
      });
      final provider = ProgressProvider(StorageService());
      await provider.loadProgress();
      final topics = buildTopics();

      final plan = provider.getTodayPlan(topics, newCount: 3, reviewCount: 3);
      expect(plan.reviewTopics.map((t) => t.id), contains('java.a'));
      expect(plan.newTopics.map((t) => t.id), isNot(contains('java.a')));
    });

    test('zero quotas yield empty plan', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      final plan =
          provider.getTodayPlan(buildTopics(), newCount: 0, reviewCount: 0);
      expect(plan.newTopics, isEmpty);
      expect(plan.reviewTopics, isEmpty);
    });
  });
}
