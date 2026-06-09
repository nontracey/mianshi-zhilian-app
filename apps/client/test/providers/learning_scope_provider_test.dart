import 'package:flutter_test/flutter_test.dart';

import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/learning_scope.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

// ── fakes ──────────────────────────────────────────────────────────────────

class _FakeStorage implements StorageService {
  final Map<String, dynamic> _data = {};

  _FakeStorage({Map<String, dynamic>? seed}) {
    if (seed != null) _data.addAll(seed);
  }

  @override
  Future<void> save(String key, dynamic data) async => _data[key] = data;

  @override
  Future<dynamic> load(String key) async => _data[key];

  @override
  Future<void> saveCustomRoutes(List<Map<String, dynamic>> routes) async =>
      _data['custom_routes'] = routes;

  @override
  Future<List<Map<String, dynamic>>> loadCustomRoutes() async {
    final raw = _data['custom_routes'];
    if (raw == null) return [];
    return (raw as List).cast<Map<String, dynamic>>();
  }

  // ignore: avoid_implementing_value_types, override_on_non_overriding_member
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(i.memberName.toString());
}

class _FakeContent implements ContentProvider {
  final Map<String, Topic> _topics;

  _FakeContent(List<Topic> topics) : _topics = {for (final t in topics) t.id: t};

  @override
  Map<String, Topic> get topics => _topics;

  @override
  List<Topic> getTopicsByDomain(String domainId) =>
      _topics.values.where((t) => t.domainId == domainId).toList();

  @override
  Topic? findTopic(String topicId) => _topics[topicId];

  @override
  Future<void> loadDomainTopics(String domainId) async {}

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(i.memberName.toString());
}

// ── helpers ────────────────────────────────────────────────────────────────

Topic _t(String id, String domain) => Topic(
      id: id,
      title: id,
      domain: domain,
      category: '',
      summary: '',
    );

LearningRoute _route({
  required String id,
  List<String> domainIds = const ['java', 'spring'],
  List<RoutePhase>? phases,
}) => LearningRoute(
      id: id,
      name: id,
      domainIds: domainIds,
      phases: phases,
      source: 'custom',
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

RoutePhase _phase(String domainId, List<String> topicIds) => RoutePhase(
      id: 'phase-$domainId',
      focus: domainId,
      topicIds: topicIds,
      domainId: domainId,
    );

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  group('LearningScope model', () {
    test('equality by value', () {
      expect(LearningScope.singleDomain('java'), LearningScope.singleDomain('java'));
      expect(LearningScope.singleDomain('java'), isNot(LearningScope.singleDomain('spring')));
    });

    test('toJson / fromJson round-trip', () {
      for (final scope in [
        const LearningScope.allDomains(),
        LearningScope.singleDomain('java'),
        LearningScope.route('r-1'),
      ]) {
        expect(LearningScope.fromJson(scope.toJson()), scope);
      }
    });

    test('unknown kind falls back to allDomains', () {
      expect(LearningScope.fromJson({'kind': 'bogus'}).kind, ScopeKind.allDomains);
    });
  });

  group('load — fresh install', () {
    test('uses legacyDomainId as singleDomain when no keys', () async {
      final p = LearningScopeProvider(_FakeStorage());
      await p.load(legacyDomainId: 'java');
      expect(p.scope, LearningScope.singleDomain('java'));
      expect(p.loaded, isTrue);
    });

    test('defaults to allDomains without legacyDomainId', () async {
      final p = LearningScopeProvider(_FakeStorage());
      await p.load();
      expect(p.scope.kind, ScopeKind.allDomains);
    });
  });

  group('load — migration from legacy keys', () {
    test('migrates active route', () async {
      final route42 = _route(id: 'route-42');
      final storage = _FakeStorage(seed: {
        'selected_route_id': 'route-42',
        'route_mode_disabled': false,
        'custom_routes': [route42.toJson()],
      });
      final p = LearningScopeProvider(storage);
      await p.load(legacyDomainId: 'java');
      expect(p.scope, LearningScope.route('route-42'));
    });

    test('migrates to singleDomain when route_mode_disabled=true', () async {
      final route42 = _route(id: 'route-42');
      final storage = _FakeStorage(seed: {
        'selected_route_id': 'route-42',
        'route_mode_disabled': true,
        'custom_routes': [route42.toJson()],
      });
      final p = LearningScopeProvider(storage);
      await p.load(legacyDomainId: 'java');
      expect(p.scope, LearningScope.singleDomain('java'));
    });

    test('falls back when routeId not found in custom_routes', () async {
      final storage = _FakeStorage(seed: {
        'selected_route_id': 'missing',
        'route_mode_disabled': false,
      });
      final p = LearningScopeProvider(storage);
      await p.load(legacyDomainId: 'java');
      expect(p.scope, LearningScope.singleDomain('java'));
    });

    test('skips migration when new learning_scope key exists', () async {
      final storage = _FakeStorage(seed: {
        'learning_scope': {'kind': 'singleDomain', 'domainId': 'python'},
        'selected_route_id': 'route-99',
        'route_mode_disabled': false,
      });
      final p = LearningScopeProvider(storage);
      await p.load(legacyDomainId: 'java');
      expect(p.scope, LearningScope.singleDomain('python'));
    });
  });

  group('resolveScopedTopics', () {
    final jt1 = _t('java.t1', 'java');
    final jt2 = _t('java.t2', 'java');
    final st1 = _t('spring.t1', 'spring');
    late _FakeContent content;

    setUp(() {
      content = _FakeContent([jt1, jt2, st1]);
    });

    test('allDomains returns all topics', () async {
      final p = LearningScopeProvider(_FakeStorage());
      await p.load();
      expect(p.resolveScopedTopics(content), containsAll([jt1, jt2, st1]));
    });

    test('singleDomain returns only that domain', () async {
      final storage = _FakeStorage(seed: {
        'learning_scope': {'kind': 'singleDomain', 'domainId': 'java'},
      });
      final p = LearningScopeProvider(storage);
      await p.load();
      expect(p.resolveScopedTopics(content), unorderedEquals([jt1, jt2]));
    });

    test('route resolves cross-domain via findTopic', () async {
      final r = _route(
        id: 'r1',
        phases: [_phase('java', ['java.t1']), _phase('spring', ['spring.t1'])],
      );
      final storage = _FakeStorage(seed: {
        'learning_scope': {'kind': 'route', 'routeId': 'r1'},
        'custom_routes': [r.toJson()],
      });
      final p = LearningScopeProvider(storage);
      await p.load();
      final result = p.resolveScopedTopics(content);
      expect(result, containsAll([jt1, st1]));
      expect(result, isNot(contains(jt2)));
    });

    test('route without phases returns all domain topics', () async {
      final r = _route(id: 'r-no-phases', phases: null);
      final storage = _FakeStorage(seed: {
        'learning_scope': {'kind': 'route', 'routeId': 'r-no-phases'},
        'custom_routes': [r.toJson()],
      });
      final p = LearningScopeProvider(storage);
      await p.load();
      final result = p.resolveScopedTopics(content);
      expect(result, containsAll([jt1, jt2, st1]));
    });
  });

  group('mutations', () {
    test('setScope persists and notifies', () async {
      final storage = _FakeStorage();
      final p = LearningScopeProvider(storage);
      await p.load(legacyDomainId: 'java');

      bool notified = false;
      p.addListener(() => notified = true);
      await p.setSingleDomain('kotlin');

      expect(p.scope, LearningScope.singleDomain('kotlin'));
      expect(notified, isTrue);
      final saved = await storage.load('learning_scope');
      expect(saved['kind'], 'singleDomain');
      expect(saved['domainId'], 'kotlin');
    });

    test('upsertRoute activate=true sets route scope', () async {
      final p = LearningScopeProvider(_FakeStorage());
      await p.load();
      await p.upsertRoute(_route(id: 'r-new'), activate: true);
      expect(p.scope, LearningScope.route('r-new'));
      expect(p.activeRoute?.id, 'r-new');
    });

    test('deleteRoute resets scope when active', () async {
      final r = _route(id: 'to-delete');
      final storage = _FakeStorage(seed: {
        'learning_scope': {'kind': 'route', 'routeId': 'to-delete'},
        'custom_routes': [r.toJson()],
      });
      final p = LearningScopeProvider(storage);
      await p.load();
      await p.deleteRoute('to-delete');
      expect(p.scope.kind, ScopeKind.allDomains);
    });

    test('deleteRoute non-active does not change scope', () async {
      final r1 = _route(id: 'active');
      final r2 = _route(id: 'other');
      final storage = _FakeStorage(seed: {
        'learning_scope': {'kind': 'route', 'routeId': 'active'},
        'custom_routes': [r1.toJson(), r2.toJson()],
      });
      final p = LearningScopeProvider(storage);
      await p.load();
      await p.deleteRoute('other');
      expect(p.scope, LearningScope.route('active'));
      expect(p.customRoutes.length, 1);
    });
  });

  group('derived getters', () {
    test('isCrossDomain true for multi-domain route', () async {
      final r = _route(id: 'cross', domainIds: ['java', 'spring']);
      final storage = _FakeStorage(seed: {
        'learning_scope': {'kind': 'route', 'routeId': 'cross'},
        'custom_routes': [r.toJson()],
      });
      final p = LearningScopeProvider(storage);
      await p.load();
      expect(p.isCrossDomain, isTrue);
    });

    test('isCrossDomain false for single-domain route', () async {
      final r = _route(id: 'single-d', domainIds: ['java']);
      final storage = _FakeStorage(seed: {
        'learning_scope': {'kind': 'route', 'routeId': 'single-d'},
        'custom_routes': [r.toJson()],
      });
      final p = LearningScopeProvider(storage);
      await p.load();
      expect(p.isCrossDomain, isFalse);
    });
  });
}
