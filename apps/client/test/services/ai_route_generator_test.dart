import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/ai_config.dart';
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

AiConfig _dummyConfig() => const AiConfig(
  id: 'test',
  name: 'Test',
  baseUrl: 'https://example.com',
  apiKey: 'sk-test',
  model: 'gpt-test',
);

PrepPlan _javaPlan() => PrepPlan(
  targetRole: 'Java 后端工程师',
  techStack: 'Java Spring Boot',
  jobDescription: '',
  interviewDate: null,
  updatedAt: DateTime(2024),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAiService mockAi;
  late MockStorageService mockStorage;
  late AiRouteGenerator generator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAi = MockAiService();
    mockStorage = MockStorageService();
    final domains = [_javaDomain(), _agentDomain()];
    generator = AiRouteGenerator(domains);

    // storage: cache miss by default
    when(mockStorage.load(any)).thenAnswer((_) async => null);
    when(mockStorage.save(any, any)).thenAnswer((_) async {});
  });

  group('domain selection — whitelist filtering', () {
    test('AI returns valid IDs → all kept', () async {
      when(mockAi.isConfigAvailable(any)).thenReturn(true);
      when(mockAi.sendMessage(any, config: anyNamed('config')))
          .thenAnswer((_) async => '["java", "agent"]');

      final ids = await generator.selectDomainIds(
        plan: _javaPlan(),
        aiService: mockAi,
        aiConfig: _dummyConfig(),
      );

      expect(ids, containsAll(['java', 'agent']));
    });

    test('AI returns hallucinated IDs → filtered out', () async {
      when(mockAi.isConfigAvailable(any)).thenReturn(true);
      when(mockAi.sendMessage(any, config: anyNamed('config')))
          .thenAnswer((_) async => '["java", "python", "rust", "nonexistent"]');

      final ids = await generator.selectDomainIds(
        plan: _javaPlan(),
        aiService: mockAi,
        aiConfig: _dummyConfig(),
      );

      expect(ids, contains('java'));
      expect(ids, isNot(contains('python')));
      expect(ids, isNot(contains('rust')));
      expect(ids, isNot(contains('nonexistent')));
    });

    test('AI returns only hallucinated IDs → falls back to local matching', () async {
      when(mockAi.isConfigAvailable(any)).thenReturn(true);
      when(mockAi.sendMessage(any, config: anyNamed('config')))
          .thenAnswer((_) async => '["nonexistent_domain"]');

      final ids = await generator.selectDomainIds(
        plan: _javaPlan(),
        aiService: mockAi,
        aiConfig: _dummyConfig(),
      );

      // fallback should return at least one valid domain
      final validIds = {'java', 'agent'};
      expect(ids.any(validIds.contains), isTrue);
    });

    test('AI throws → falls back to local matching', () async {
      when(mockAi.isConfigAvailable(any)).thenReturn(true);
      when(mockAi.sendMessage(any, config: anyNamed('config')))
          .thenThrow(Exception('network error'));

      final ids = await generator.selectDomainIds(
        plan: _javaPlan(),
        aiService: mockAi,
        aiConfig: _dummyConfig(),
      );

      expect(ids, isNotEmpty);
    });
  });

  group('plan signature dedup', () {
    test('same plan produces same route ID', () async {
      when(mockAi.isConfigAvailable(any)).thenReturn(false);

      final storage = StorageService();
      final mockContentApi = MockContentApiService();
      when(mockContentApi.fetchManifest()).thenAnswer((_) async => {'domains': []});
      final mockContent = ContentProvider(mockContentApi, storage);
      final mockProgress = ProgressProvider(storage);

      final plan = _javaPlan();
      final r1 = await generator.generateRoute(
        plan: plan, allTopics: [], progressProvider: mockProgress,
        aiService: mockAi, contentProvider: mockContent, forceRegenerate: true,
      );
      final r2 = await generator.generateRoute(
        plan: plan, allTopics: [], progressProvider: mockProgress,
        aiService: mockAi, contentProvider: mockContent, forceRegenerate: true,
      );

      expect(r1.id, r2.id);
      expect(r1.planSignature, isNotNull);
      expect(r1.planSignature, r2.planSignature);
    });

    test('different plans produce different route IDs', () async {
      when(mockAi.isConfigAvailable(any)).thenReturn(false);

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

      final r1 = await generator.generateRoute(
        plan: plan1, allTopics: [], progressProvider: mockProgress,
        aiService: mockAi, contentProvider: mockContent, forceRegenerate: true,
      );
      final r2 = await generator.generateRoute(
        plan: plan2, allTopics: [], progressProvider: mockProgress,
        aiService: mockAi, contentProvider: mockContent, forceRegenerate: true,
      );

      expect(r1.id, isNot(r2.id));
      expect(r1.planSignature, isNot(r2.planSignature));
    });
  });

  group('LearningScopeProvider route dedup', () {
    test('upsertRoute replaces AI route with same planSignature', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final scope = LearningScopeProvider(storage);
      await scope.load();

      const sig = 'sig123';
      final old = LearningRoute(
        id: 'ai_old',
        name: 'Old Route',
        domainIds: ['java'],
        phases: [],
        source: 'ai',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        planSignature: sig,
      );
      final newer = LearningRoute(
        id: 'ai_new',
        name: 'New Route',
        domainIds: ['java'],
        phases: [],
        source: 'ai',
        createdAt: DateTime(2024, 6, 1),
        updatedAt: DateTime(2024, 6, 1),
        planSignature: sig,
      );

      await scope.upsertRoute(old);
      await scope.upsertRoute(newer);

      final routes = scope.customRoutes;
      final aiRoutes = routes.where((r) => r.planSignature == sig).toList();
      expect(aiRoutes, hasLength(1));
      expect(aiRoutes.single.id, 'ai_new');
    });

    test('manual routes are not deduplicated by planSignature', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final scope = LearningScopeProvider(storage);
      await scope.load();

      final r1 = LearningRoute(
        id: 'manual_1',
        name: 'My Route',
        domainIds: ['java'],
        phases: [],
        source: 'manual',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );
      final r2 = LearningRoute(
        id: 'manual_2',
        name: 'My Route 2',
        domainIds: ['java'],
        phases: [],
        source: 'manual',
        createdAt: DateTime(2024, 6, 1),
        updatedAt: DateTime(2024, 6, 1),
      );

      await scope.upsertRoute(r1);
      await scope.upsertRoute(r2);

      expect(scope.customRoutes, hasLength(2));
    });
  });
}
