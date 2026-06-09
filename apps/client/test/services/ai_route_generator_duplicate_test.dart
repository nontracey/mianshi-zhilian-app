import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/ai_route_generator.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

import '../helpers/mocks.mocks.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Domain _javaDomain() {
  final raw = json.decode(
    File('test/fixtures/content/java/domain.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return Domain.fromJson(raw);
}

Domain _agentDomain() {
  final raw = json.decode(
    File('test/fixtures/content/agent/domain.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return Domain.fromJson(raw);
}

PrepPlan _javaPlan() => PrepPlan(
  targetRole: 'Java 后端工程师',
  techStack: 'Java Spring Boot',
  jobDescription: '',
  interviewDate: null,
  updatedAt: DateTime(2024),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAiService mockAi;
  late MockStorageService mockStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAi = MockAiService();
    mockStorage = MockStorageService();
    when(mockStorage.load(any)).thenAnswer((_) async => null);
    when(mockStorage.save(any, any)).thenAnswer((_) async {});
    when(mockStorage.saveCustomRoutes(any)).thenAnswer((_) async {});
    when(mockStorage.loadCustomRoutes()).thenAnswer((_) async => []);
  });

  // ── 场景 1：同一 plan 并发生成两次 → 路线 ID 相同，upsertRoute 覆盖 ─────
  group('concurrent generateRoute calls with same plan', () {
    test('results in only one unique route after both upserts', () async {
      when(mockAi.isConfigAvailable(any)).thenReturn(false);

      final domains = [_javaDomain(), _agentDomain()];
      final generator = AiRouteGenerator(mockStorage, domains);
      final storage = StorageService();
      final mockContentApi = MockContentApiService();
      when(mockContentApi.fetchManifest()).thenAnswer((_) async => {'domains': []});
      final mockContent = ContentProvider(mockContentApi, storage);
      final mockProgress = ProgressProvider(storage);

      final plan = _javaPlan();

      // 模拟"用户同时点好多次"：Future.wait 并发两次 generateRoute
      final routes = await Future.wait([
        generator.generateRoute(
          plan: plan,
          allTopics: [],
          progressProvider: mockProgress,
          aiService: mockAi,
          contentProvider: mockContent,
          forceRegenerate: true,
        ),
        generator.generateRoute(
          plan: plan,
          allTopics: [],
          progressProvider: mockProgress,
          aiService: mockAi,
          contentProvider: mockContent,
          forceRegenerate: true,
        ),
      ]);

      // 关键字段一致（createdAt/updatedAt 有毫秒级差异，不判全等）
      expect(routes[0].id, routes[1].id);
      expect(routes[0].planSignature, routes[1].planSignature);
      expect(routes[0].name, routes[1].name);
      expect(routes[0].domainIds, routes[1].domainIds);

      // 连续 upsert 后最终列表只有一条
      final scope = LearningScopeProvider(storage);
      await scope.load();
      await scope.upsertRoute(routes[0]);
      await scope.upsertRoute(routes[1]);

      final aiRoutes =
          scope.customRoutes.where((r) => r.planSignature == routes[0].planSignature).toList();
      expect(aiRoutes, hasLength(1));
    });
  });

  // ── 场景 2：不同 plan 并发生成 → 各自保留 ───────────────────────────
  group('concurrent generateRoute calls with different plans', () {
    test('both routes are kept after upsert', () async {
      when(mockAi.isConfigAvailable(any)).thenReturn(false);

      final domains = [_javaDomain(), _agentDomain()];
      final generator = AiRouteGenerator(mockStorage, domains);
      final storage = StorageService();
      final mockContentApi = MockContentApiService();
      when(mockContentApi.fetchManifest()).thenAnswer((_) async => {'domains': []});
      final mockContent = ContentProvider(mockContentApi, storage);
      final mockProgress = ProgressProvider(storage);

      final plan1 = _javaPlan();
      final plan2 = PrepPlan(
        targetRole: 'AI Agent 工程师',
        techStack: 'Python LangChain',
        jobDescription: '',
        interviewDate: null,
        updatedAt: DateTime(2024),
      );

      final routes = await Future.wait([
        generator.generateRoute(
          plan: plan1,
          allTopics: [],
          progressProvider: mockProgress,
          aiService: mockAi,
          contentProvider: mockContent,
          forceRegenerate: true,
        ),
        generator.generateRoute(
          plan: plan2,
          allTopics: [],
          progressProvider: mockProgress,
          aiService: mockAi,
          contentProvider: mockContent,
          forceRegenerate: true,
        ),
      ]);

      // 两条路线不同的签名
      expect(routes[0].planSignature, isNot(routes[1].planSignature));

      // 连续 upsert 后仍保留两条
      final scope = LearningScopeProvider(storage);
      await scope.load();
      await scope.upsertRoute(routes[0]);
      await scope.upsertRoute(routes[1]);

      final sigs = scope.customRoutes
          .where((r) => r.source == 'ai')
          .map((r) => r.planSignature)
          .toSet();
      expect(sigs, hasLength(2));
    });
  });

  // ── 场景 3：旧路线与新路线同 planSignature → 自动替换 ────────────────
  group('new route replaces old route with same planSignature', () {
    test('only the latest route survives after upsert', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final scope = LearningScopeProvider(storage);
      await scope.load();

      const sig = 'sig_old_new';
      final oldRoute = LearningRoute(
        id: 'ai_old',
        name: 'Old Route',
        domainIds: ['java'],
        phases: [],
        source: 'ai',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        planSignature: sig,
      );
      final newRoute = LearningRoute(
        id: 'ai_new',
        name: 'New Route',
        domainIds: ['java'],
        phases: [],
        source: 'ai',
        createdAt: DateTime(2024, 6, 1),
        updatedAt: DateTime(2024, 6, 1),
        planSignature: sig,
      );

      await scope.upsertRoute(oldRoute);
      await scope.upsertRoute(newRoute);

      final routes = scope.customRoutes.where((r) => r.planSignature == sig).toList();
      expect(routes, hasLength(1));
      expect(routes.single.id, 'ai_new');
    });

    test('same route upserted multiple times is idempotent', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final scope = LearningScopeProvider(storage);
      await scope.load();

      final route = LearningRoute(
        id: 'ai_duplicate',
        name: 'Route',
        domainIds: ['java'],
        phases: [],
        source: 'ai',
        createdAt: DateTime(2024, 6, 1),
        updatedAt: DateTime(2024, 6, 1),
        planSignature: 'sig_idempotent',
      );

      // 同一个 route 对象 upsert 多次
      await scope.upsertRoute(route);
      await scope.upsertRoute(route);
      await scope.upsertRoute(route);

      expect(scope.customRoutes, hasLength(1));
      expect(scope.customRoutes.single.id, 'ai_duplicate');
    });
  });

  // ── 场景 4：Provider 级并发生成锁 ────────────────────────────────────
  group('generation guard', () {
    test('setGeneratingRoute blocks concurrent generation attempts', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final scope = LearningScopeProvider(storage);
      await scope.load();

      expect(scope.isGeneratingRoute, isFalse);

      scope.setGeneratingRoute(true);
      expect(scope.isGeneratingRoute, isTrue);

      // 并发时：第二次调用直接返回（模拟 LearningShell._generateAiRoute 的行为）
      scope.setGeneratingRoute(true); // no-op because value already true
      expect(scope.isGeneratingRoute, isTrue);

      scope.setGeneratingRoute(false);
      expect(scope.isGeneratingRoute, isFalse);
    });
  });

  // ── 场景 5：load 时自动清理历史重复 AI 路线 ──────────────────────────
  group('load deduplicates stale AI routes', () {
    test('keeps only latest route per planSignature', () async {
      // 模拟持久化中有 3 条 AI 路线: 2 条同 sig, 1 条不同
      final staleRoute = LearningRoute(
        id: 'ai_stale',
        name: 'Stale Route',
        domainIds: ['java'],
        phases: [],
        source: 'ai',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        planSignature: 'sig_a',
      );
      final latestRoute = LearningRoute(
        id: 'ai_latest',
        name: 'Latest Route',
        domainIds: ['java'],
        phases: [],
        source: 'ai',
        createdAt: DateTime(2024, 6, 1),
        updatedAt: DateTime(2024, 6, 1),
        planSignature: 'sig_a',
      );
      final otherRoute = LearningRoute(
        id: 'ai_other',
        name: 'Other Route',
        domainIds: ['agent'],
        phases: [],
        source: 'ai',
        createdAt: DateTime(2024, 3, 1),
        updatedAt: DateTime(2024, 3, 1),
        planSignature: 'sig_b',
      );

      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      // 把 3 条路线写入持久化
      final routesJson = [staleRoute, latestRoute, otherRoute]
          .map((r) => r.toJson())
          .toList();
      // 用 SharedPreferences 模拟持久化
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_routes',
        json.encode(routesJson),
      );

      final scope = LearningScopeProvider(storage);
      await scope.load();

      // sig_a 只保留 latest（最新的那条）
      final sigARoutes =
          scope.customRoutes.where((r) => r.planSignature == 'sig_a').toList();
      expect(sigARoutes, hasLength(1));
      expect(sigARoutes.single.id, 'ai_latest');

      // sig_b 那条还在
      expect(
        scope.customRoutes.any((r) => r.planSignature == 'sig_b'),
        isTrue,
      );

      // 总共 2 条
      expect(scope.customRoutes.length, 2);
    });
  });
}