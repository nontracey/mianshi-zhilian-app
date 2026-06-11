import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingAttemptStorage extends StorageService {
  @override
  Future<void> savePracticeAttemptsStrict(
    List<PracticeAttempt> attempts,
  ) async {
    throw StorageWriteException('practice_attempts', 'quota exceeded');
  }
}

void main() {
  group('递进复习间隔（P1-7）', () {
    test('连续高分沿 3→7→14→30 阶梯递进', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      await provider.loadProgress();

      final intervals = <int>[];
      for (var i = 0; i < 5; i++) {
        await provider.updateProgress('java.a', 90, 'skilled');
        intervals.add(provider.getProgress('java.a')!.reviewIntervalDays);
      }
      // 首次 3 天，之后 7、14、30，封顶 30。
      expect(intervals, [3, 7, 14, 30, 30]);
    });

    test('中分固定 3 天，低分重置为 1 天', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      await provider.loadProgress();

      await provider.updateProgress('java.a', 90, 'skilled'); // 3
      await provider.updateProgress('java.a', 90, 'skilled'); // 7
      expect(provider.getProgress('java.a')!.reviewIntervalDays, 7);

      await provider.updateProgress('java.a', 50, 'new'); // 低分重置
      expect(provider.getProgress('java.a')!.reviewIntervalDays, 1);

      await provider.updateProgress('java.a', 70, 'learning'); // 中分固定 3
      expect(provider.getProgress('java.a')!.reviewIntervalDays, 3);

      // 重新高分从阶梯起点之后前进（currentInterval=3 → 7）。
      await provider.updateProgress('java.a', 90, 'skilled');
      expect(provider.getProgress('java.a')!.reviewIntervalDays, 7);
    });

    test('nextReviewAt 与间隔天数一致', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      await provider.loadProgress();

      await provider.updateProgress('java.a', 90, 'skilled');
      final p = provider.getProgress('java.a')!;
      final days = p.nextReviewAt!.difference(DateTime.now()).inDays;
      // 间隔 3 天，允许 1 天误差（跨午夜/执行耗时）。
      expect(days, inInclusiveRange(2, 3));
      expect(p.reviewIntervalDays, 3);
    });
  });

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

  test('addAttempt rethrows storage failure and rolls back memory', () async {
    final provider = ProgressProvider(_FailingAttemptStorage());
    final attempt = PracticeAttempt(
      id: 'attempt-1',
      topicId: 'java.a',
      mode: 'recall',
      question: 'q',
      answer: 'a',
      createdAt: DateTime(2026, 1, 1),
    );

    await expectLater(
      provider.addAttempt(attempt),
      throwsA(isA<StorageWriteException>()),
    );
    expect(provider.attempts, isEmpty);
  });

  group('getTodayPlan', () {
    List<Topic> buildTopics() => const [
      Topic(
        id: 'java.a',
        domain: 'java',
        category: 'core',
        title: 'A',
        summary: 'A',
        order: 1,
      ),
      Topic(
        id: 'java.b',
        domain: 'java',
        category: 'core',
        title: 'B',
        summary: 'B',
        order: 2,
      ),
      Topic(
        id: 'java.c',
        domain: 'java',
        category: 'core',
        title: 'C',
        summary: 'C',
        order: 3,
      ),
      Topic(
        id: 'java.d',
        domain: 'java',
        category: 'core',
        title: 'D',
        summary: 'D',
        order: 4,
      ),
    ];

    test(
      'new topics are never-practiced, ordered by Topic.order, capped by newCount',
      () async {
        SharedPreferences.setMockInitialValues({});
        final provider = ProgressProvider(StorageService());
        final topics = buildTopics();

        final plan = provider.getTodayPlan(topics, newCount: 2, reviewCount: 5);
        expect(plan.newTopics.map((t) => t.id), ['java.a', 'java.b']);
        expect(plan.reviewTopics, isEmpty);
      },
    );

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
        'progress_map':
            '''
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
      final plan = provider.getTodayPlan(
        buildTopics(),
        newCount: 0,
        reviewCount: 0,
      );
      expect(plan.newTopics, isEmpty);
      expect(plan.reviewTopics, isEmpty);
    });

    test(
      'preserveScopeOrder keeps incoming (route) order, not Topic.order',
      () async {
        SharedPreferences.setMockInitialValues({});
        final provider = ProgressProvider(StorageService());
        // 模拟路线顺序：传入顺序与 Topic.order 相反（d,c,b,a）
        final routeOrdered = buildTopics().reversed.toList();
        final plan = provider.getTodayPlan(
          routeOrdered,
          newCount: 3,
          reviewCount: 5,
          preserveScopeOrder: true,
        );
        // 路线模式下应保留路线顺序，而非回退到内容全局 order
        expect(plan.newTopics.map((t) => t.id), ['java.d', 'java.c', 'java.b']);
      },
    );
  });

  test(
    'allowSkipLowFrequency penalizes low-frequency only when enabled',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ProgressProvider(StorageService());
      // 两个未练习项，低频项 base 略高（recommendWeight 更大）。
      const lowTopic = Topic(
        id: 'java.low',
        domain: 'java',
        category: 'core',
        title: 'Low',
        summary: 'Low',
        order: 1,
        recommendWeight: 60,
        interviewFrequency: 'low',
      );
      const midTopic = Topic(
        id: 'java.mid',
        domain: 'java',
        category: 'core',
        title: 'Mid',
        summary: 'Mid',
        order: 2,
        recommendWeight: 50,
        interviewFrequency: 'medium',
      );

      // 关闭（默认）：不惩罚低频，base 更高的低频项排前。
      final off = provider.getRecommendedTopics(
        'java',
        [lowTopic, midTopic],
        'smart',
        prioritizePrerequisites: false,
        allowSkipLowFrequency: false,
      );
      expect(off.first.id, 'java.low');

      // 开启「允许跳过低频」：低频被扣分下沉，中频项排前。
      final on = provider.getRecommendedTopics(
        'java',
        [lowTopic, midTopic],
        'smart',
        prioritizePrerequisites: false,
        allowSkipLowFrequency: true,
      );
      expect(on.first.id, 'java.mid');
    },
  );
}
