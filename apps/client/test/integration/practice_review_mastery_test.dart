import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/route_composer.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

import '../helpers/fake_content_client.dart';

/// 核心练习 / 复习 / 掌握度 / 路线编辑 的业务层端到端，
/// 数据来自贴真的 java/agent/python 三领域 fixture。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentProvider content;
  late ProgressProvider progress;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final api = ContentApiService(
      baseUrl: 'https://fake.test',
      httpClient: FakeContentClient(),
    );
    storage = StorageService();
    content = ContentProvider(api, storage);
    progress = ProgressProvider(storage);
    await content.loadContent();
    await content.loadDomainTopics('java');
    await content.loadDomainTopics('agent');
    await content.loadDomainTopics('python');
  });

  Future<LearningScopeProvider> activateRoute(List<String> domainIds) async {
    final phases = RouteComposer.composePhasesFromContent(
      orderedDomainIds: domainIds,
      allDomains: content.domains,
      getTopicById: content.getTopicById,
    );
    final route = LearningRoute(
      id: 'r',
      name: 'r',
      domainIds: RouteComposer.domainsOf(phases),
      phases: phases,
      source: 'custom',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final scope = LearningScopeProvider(storage);
    await scope.load();
    await scope.upsertRoute(route, activate: true, contentProvider: content);
    return scope;
  }

  group('练习抽题口径', () {
    test('弱项强化：getWeakTopics 取分数最低的已练习项，按升序、限量', () async {
      final java = content.getTopicsByDomain('java');
      await progress.updateTopicProgress(java[0].id, score: 30);
      await progress.updateTopicProgress(java[1].id, score: 90);
      await progress.updateTopicProgress(java[2].id, score: 55);
      await progress.updateTopicProgress(java[3].id, score: 40);

      final weak = progress.getWeakTopics(java, limit: 2);
      expect(weak.map((t) => t.id), [java[0].id, java[3].id]); // 30, 40
      // 未练习的不计入
      expect(progress.getWeakTopics(java, limit: 50).length, 4);
    });

    test('高频冲刺：按 interviewFrequency==high 过滤（内容侧字段）', () {
      final java = content.getTopicsByDomain('java');
      final high = java.where((t) => t.interviewFrequency == 'high').toList();
      expect(high.length, 35);
      expect(high.every((t) => t.interviewFrequency == 'high'), isTrue);
    });

    test('模拟面试/复述抽题池 == resolveScopedTopics（统一口径 A-1/L-2）', () async {
      final scope = await activateRoute(['java', 'agent', 'python']);
      // learning_shell._startMockInterview 用的就是 resolveScopedTopics
      final pool = scope.resolveScopedTopics(content);
      expect(pool.length, 67 + 26 + 22);
      // 跨域抽题覆盖三领域，不会退回单域
      expect(pool.map((t) => t.domain).toSet(), {'java', 'agent', 'python'});
    });
  });

  group('复习队列', () {
    test('复习间隔随分数增大：高分下次复习更晚', () async {
      final java = content.getTopicsByDomain('java');
      await progress.updateTopicProgress(java[0].id, score: 50); // +1d
      await progress.updateTopicProgress(java[1].id, score: 90); // +7d
      final low = progress.getProgress(java[0].id)!.nextReviewAt!;
      final high = progress.getProgress(java[1].id)!.nextReviewAt!;
      expect(high.isAfter(low), isTrue);
    });

    test('今日到期项出现在复习队列', () async {
      final java = content.getTopicsByDomain('java');
      final dueId = java[0].id;
      // seed 一条昨天到期的进度
      await storage.saveProgressMap({
        dueId: TopicProgress(
          topicId: dueId,
          score: 50,
          status: 'learning',
          practiceCount: 1,
          lastPracticeAt: DateTime.now().subtract(const Duration(days: 2)),
          nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      });
      await progress.loadProgress();

      final due = progress.getTodayReviewTopics(java);
      expect(due.map((t) => t.id), contains(dueId));
    });
  });

  group('跨域掌握度概览', () {
    test('按领域分组 scopedTopics → 三组、计数正确', () async {
      final scope = await activateRoute(['java', 'agent', 'python']);
      final scoped = scope.resolveScopedTopics(content);
      final byDomain = <String, int>{};
      for (final t in scoped) {
        byDomain[t.domain] = (byDomain[t.domain] ?? 0) + 1;
      }
      expect(byDomain, {'java': 67, 'agent': 26, 'python': 22});
    });

    test('分领域掌握度独立计算', () async {
      final agent = content.getTopicsByDomain('agent');
      final all = [
        ...content.getTopicsByDomain('java'),
        ...agent,
        ...content.getTopicsByDomain('python'),
      ];
      for (final t in agent.take(10)) {
        await progress.updateTopicProgress(t.id, score: 90);
      }
      // 只有 agent 被练习 → 只有 agent 掌握度 > 0
      expect(progress.getDomainProgress('agent', all).masteryPercent, greaterThan(0));
      expect(progress.getDomainProgress('java', all).masteryPercent, 0);
      expect(progress.getDomainProgress('python', all).masteryPercent, 0);
    });

    test('薄弱 TOP5 跨领域取分数最低', () async {
      final scope = await activateRoute(['java', 'agent', 'python']);
      final scoped = scope.resolveScopedTopics(content);
      // 给不同领域几个不同低分
      await progress.updateTopicProgress(scoped[0].id, score: 20);
      await progress.updateTopicProgress(scoped[70].id, score: 35); // agent 区间
      await progress.updateTopicProgress(scoped[95].id, score: 10); // python 区间
      final weak = progress.getWeakTopics(scoped, limit: 5);
      expect(weak.first.id, scoped[95].id); // 最低 10
      expect(weak.length, 3);
    });
  });

  group('路线编辑重排（issue 3）', () {
    test('调整领域顺序 → 阶段顺序随之变化，topic 集合不变', () {
      List<RoutePhase> compose(List<String> order) =>
          RouteComposer.composePhasesFromContent(
            orderedDomainIds: order,
            allDomains: content.domains,
            getTopicById: content.getTopicById,
          );

      final a = compose(['java', 'agent']);
      final b = compose(['agent', 'java']);

      expect(RouteComposer.domainsOf(a), ['java', 'agent']);
      expect(RouteComposer.domainsOf(b), ['agent', 'java']);
      // 重排后第一个 phase 的领域翻转
      expect(a.first.domainId, 'java');
      expect(b.first.domainId, 'agent');
      // topic 集合一致（只是顺序变了）
      Set<String> ids(List<RoutePhase> p) => p.expand((e) => e.topicIds).toSet();
      expect(ids(a), ids(b));
    });
  });
}
