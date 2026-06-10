import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
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

/// A-7：AI 路线缓存层收敛——`custom_routes` 是唯一事实源，
/// 不再维护独立的 `route_cache_*` 24h TTL 缓存层。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAiService mockAi;
  late AiRouteGenerator generator;
  late StorageService storage;
  late ContentProvider content;
  late ProgressProvider progress;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAi = MockAiService();
    when(mockAi.isConfigAvailable(any)).thenReturn(false); // 走本地 fallback

    storage = StorageService();
    final mockContentApi = MockContentApiService();
    when(mockContentApi.fetchManifest()).thenAnswer((_) async => {'domains': []});
    content = ContentProvider(mockContentApi, storage);
    progress = ProgressProvider(storage);

    generator = AiRouteGenerator([_javaDomain(), _agentDomain()]);
  });

  Future<LearningRoute> gen({
    bool forceRegenerate = false,
    List<LearningRoute> existingRoutes = const [],
  }) =>
      generator.generateRoute(
        plan: _javaPlan(),
        allTopics: const [],
        progressProvider: progress,
        aiService: mockAi,
        contentProvider: content,
        forceRegenerate: forceRegenerate,
        existingRoutes: existingRoutes,
      );

  group('single source of truth — no separate route_cache layer', () {
    test('non-force generate reuses existing route with same planSignature',
        () async {
      final first = await gen(forceRegenerate: true);
      // 把生成的路线作为"已有路线"再次非强制生成 → 原样返回，不重新生成
      final second = await gen(existingRoutes: [first]);

      expect(second.id, first.id);
      expect(second.createdAt, first.createdAt);
      expect(identical(second, first), isTrue,
          reason: '应直接返回已有对象，而非重新生成');
    });

    test('non-force generate without matching existing route regenerates',
        () async {
      final route = await gen(existingRoutes: const []);
      expect(route.source, 'ai');
      expect(route.planSignature, _javaPlan().signature);
    });

    test('force regenerate ignores existing route and produces fresh route',
        () async {
      final first = await gen(forceRegenerate: true);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final regenerated =
          await gen(forceRegenerate: true, existingRoutes: [first]);

      expect(regenerated.id, first.id, reason: '同一 plan 路线 id 稳定');
      expect(identical(regenerated, first), isFalse,
          reason: '强制重生应产出新对象');
      expect(
        regenerated.updatedAt.isAfter(first.updatedAt) ||
            regenerated.updatedAt == first.updatedAt,
        isTrue,
      );
    });

    test('generateRoute never writes a route_cache_* key to storage', () async {
      await gen(forceRegenerate: true);
      final prefs = await SharedPreferences.getInstance();
      final cacheKeys =
          prefs.getKeys().where((k) => k.startsWith('route_cache_')).toList();
      expect(cacheKeys, isEmpty,
          reason: '收敛后不应再产生独立的 route_cache_* 缓存键');
    });

    test('route planSignature equals PrepPlan.signature (trim-safe)', () async {
      // 带首尾空格的 plan：route 的签名应与 PrepPlan.signature 完全一致
      final plan = PrepPlan(
        targetRole: '  Java 后端工程师  ',
        techStack: 'Java Spring Boot',
        jobDescription: '',
        interviewDate: null,
        updatedAt: DateTime(2024),
      );
      final route = await generator.generateRoute(
        plan: plan,
        allTopics: const [],
        progressProvider: progress,
        aiService: mockAi,
        contentProvider: content,
        forceRegenerate: true,
      );
      expect(route.planSignature, plan.signature);
    });
  });
}
