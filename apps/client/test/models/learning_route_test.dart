import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';

void main() {
  group('RoutePhase', () {
    test('toJson/fromJson round-trip', () {
      final phase = RoutePhase(
        id: 'phase_1',
        focus: 'JVM',
        topicIds: ['java.jvm.1', 'java.jvm.2'],
        estimatedHours: 3,
        type: 'learn',
      );
      final json = phase.toJson();
      final restored = RoutePhase.fromJson(json);
      expect(restored.id, phase.id);
      expect(restored.focus, phase.focus);
      expect(restored.topicIds, phase.topicIds);
      expect(restored.estimatedHours, phase.estimatedHours);
      expect(restored.type, phase.type);
    });

    test('copyWith modifies only specified fields', () {
      final phase = RoutePhase(id: 'p1', focus: 'JVM');
      final modified = phase.copyWith(focus: 'Concurrency');
      expect(modified.id, 'p1');
      expect(modified.focus, 'Concurrency');
      expect(modified.topicIds, isEmpty);
    });

    test('default values are correct', () {
      final phase = RoutePhase(id: 'p1', focus: 'Test');
      expect(phase.topicIds, isEmpty);
      expect(phase.categoryIds, isEmpty);
      expect(phase.prerequisiteSteps, isEmpty);
      expect(phase.estimatedHours, 0);
      expect(phase.type, 'learn');
    });
  });

  group('LearningRoute', () {
    test('toJson/fromJson round-trip with phases', () {
      final now = DateTime.now();
      final route = LearningRoute(
        id: 'test_route',
        name: 'Test Route',
        domainIds: ['java'],
        phases: [
          RoutePhase(id: 'p1', focus: 'JVM', topicIds: ['t1', 't2']),
        ],
        source: 'ai',
        createdAt: now,
        updatedAt: now,
      );
      final json = route.toJson();
      final restored = LearningRoute.fromJson(json);
      expect(restored.id, route.id);
      expect(restored.source, 'ai');
      expect(restored.phases!.length, 1);
      expect(restored.phases![0].topicIds, ['t1', 't2']);
    });

    test('allTopicIds returns all unique topicIds from phases', () {
      final route = LearningRoute(
        id: 'r1',
        name: 'R',
        domainIds: ['java'],
        phases: [
          RoutePhase(id: 'p1', focus: 'A', topicIds: ['t1', 't2']),
          RoutePhase(id: 'p2', focus: 'B', topicIds: ['t2', 't3']),
        ],
        source: 'ai',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(route.allTopicIds, ['t1', 't2', 't3']);
    });

    test('allTopicIds returns empty when phases is null', () {
      final route = LearningRoute(
        id: 'r1', name: 'R', domainIds: ['java'],
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      );
      expect(route.allTopicIds, isEmpty);
    });

    test('toJson omits phases when null', () {
      final route = LearningRoute(
        id: 'r1', name: 'R', domainIds: ['java'],
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      );
      final json = route.toJson();
      expect(json.containsKey('phases'), false);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'r1', 'name': 'R', 'domainIds': ['java'],
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      final route = LearningRoute.fromJson(json);
      expect(route.phases, isNull);
      expect(route.source, 'custom');
    });
  });
}
