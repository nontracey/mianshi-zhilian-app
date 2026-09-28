import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/learning_scope.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/route_composer.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

import '../helpers/fake_content_client.dart';

/// 核心业务流程端到端（数据/业务层）：用真实 ContentApiService + ContentProvider
/// 加载贴真的 java/agent/python 三领域内容，跑通 内容加载 → 路线生成 → 范围解析
/// → 目录 → 掌握度/今日计划，防止核心功能偏离预期。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentProvider content;
  late ProgressProvider progress;
  late StorageService storage;

  // 真实领域 topic 数（与 manifest/domain.json 引用一致）
  const javaCount = 67;
  const agentCount = 26;
  const pythonCount = 22;
  const totalCount = javaCount + agentCount + pythonCount;

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
      id: 'test-route',
      name: '测试路线',
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

  group('内容加载', () {
    test('manifest 含三领域', () {
      expect(content.domains.map((d) => d.id),
          containsAll(['java', 'agent', 'python']));
    });

    test('每个领域 topic 数与内容契约一致，且全局无重复 (R-1)', () {
      expect(content.getTopicsByDomain('java').length, javaCount);
      expect(content.getTopicsByDomain('agent').length, agentCount);
      expect(content.getTopicsByDomain('python').length, pythonCount);

      final all = content.topics.values.toList();
      expect(all.length, totalCount);
      final ids = all.map((t) => t.id).toSet();
      expect(ids.length, all.length, reason: 'topics.values 不应出现重复 id');
    });

    test('topic 默认顺序由内容侧 order 维护（升序）', () {
      final orders = content.getTopicsByDomain('java').map((t) => t.order).toList();
      final sorted = [...orders]..sort();
      expect(orders, sorted);
    });
  });

  group('范围解析（resolveScopedTopics）', () {
    test('路线模式跨域：解析出全部领域 topic（修复 issue 4/5）', () async {
      final scope = await activateRoute(['java', 'agent', 'python']);
      final scoped = scope.resolveScopedTopics(content);
      expect(scoped.length, totalCount);
      for (final d in ['java', 'agent', 'python']) {
        expect(scoped.where((t) => t.domain == d), isNotEmpty,
            reason: '$d 切换后不应「无知识点」');
      }
    });

    test('单领域范围：只返回该领域 topic', () async {
      final scope = LearningScopeProvider(storage);
      await scope.load();
      await scope.setScope(LearningScope.singleDomain('agent'),
          contentProvider: content);
      final scoped = scope.resolveScopedTopics(content);
      expect(scoped.length, agentCount);
      expect(scoped.every((t) => t.domain == 'agent'), isTrue);
    });

    test('全部领域范围：返回所有已加载 topic（无重复）', () async {
      final scope = LearningScopeProvider(storage);
      await scope.load();
      await scope.setScope(const LearningScope.allDomains(),
          contentProvider: content);
      expect(scope.resolveScopedTopics(content).length, totalCount);
    });
  });

  group('掌握度 / 今日计划', () {
    test('今日计划取范围内新知识点（按 order），排除已练习项', () async {
      final java = content.getTopicsByDomain('java');
      await progress.updateTopicProgress(java[0].id, score: 80);
      await progress.updateTopicProgress(java[1].id, score: 80);

      final plan = progress.getTodayPlan(java, newCount: 3, reviewCount: 5);
      final newIds = plan.newTopics.map((t) => t.id).toSet();
      expect(newIds, isNot(contains(java[0].id)));
      expect(newIds, isNot(contains(java[1].id)));
      expect(plan.newTopics.length, 3);
    });

    test('领域掌握度随练习上升', () async {
      final agent = content.getTopicsByDomain('agent');
      final before = progress.getDomainProgress('agent', agent).masteryPercent;
      for (final t in agent.take(5)) {
        await progress.updateTopicProgress(t.id, score: 90);
      }
      final after = progress.getDomainProgress('agent', agent).masteryPercent;
      expect(after, greaterThan(before));
    });
  });
}
