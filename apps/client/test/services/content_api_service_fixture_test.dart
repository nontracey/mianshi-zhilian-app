// fixture JSON 直接测试 Domain/Topic 解析，无需网络请求
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';

String _fixture(String path) =>
    File('test/fixtures/content/$path').readAsStringSync();

void main() {
  group('manifest fixture', () {
    test('has java and agent domains', () {
      final raw = json.decode(_fixture('manifest.json')) as Map<String, dynamic>;
      final domains = (raw['domains'] as List).cast<Map<String, dynamic>>();
      expect(domains.map((d) => d['id']), containsAll(['java', 'agent']));
    });
  });

  group('Domain.fromJson — java fixture', () {
    late Domain domain;
    setUp(() {
      domain = Domain.fromJson(
        json.decode(_fixture('java/domain.json')) as Map<String, dynamic>,
      );
    });

    test('basic fields', () {
      expect(domain.id, 'java');
      expect(domain.title, 'Java');
    });

    test('has expected categories', () {
      expect(domain.categories.map((c) => c.id),
          containsAll(['java-jvm', 'java-collections']));
    });

    test('learning path steps have prerequisite chain', () {
      final steps = domain.learningPaths.first.steps;
      expect(steps, hasLength(2));
      expect(steps[1].prerequisiteSteps, contains('java-jvm'));
    });

    test('categories contain topic paths', () {
      final jvmCat = domain.categories.firstWhere((c) => c.id == 'java-jvm');
      expect(jvmCat.topics, isNotEmpty);
    });
  });

  group('Domain.fromJson — agent fixture', () {
    late Domain domain;
    setUp(() {
      domain = Domain.fromJson(
        json.decode(_fixture('agent/domain.json')) as Map<String, dynamic>,
      );
    });

    test('basic fields', () {
      expect(domain.id, 'agent');
      expect(domain.categories.first.id, 'agent-core');
    });
  });

  group('Topic.fromJson — java hashmap fixture', () {
    late Topic topic;
    setUp(() {
      topic = Topic.fromJson(
        json.decode(_fixture('java/hashmap.json')) as Map<String, dynamic>,
      );
    });

    test('basic fields', () {
      expect(topic.id, 'java.collections.hashmap');
      expect(topic.domainId, 'java');
      expect(topic.title, 'HashMap 原理');
    });

    test('interview metadata', () {
      expect(topic.interviewFrequency, 'high');
      expect(topic.difficulty, 2);
    });

    test('has recall prompts', () {
      expect(topic.recallPrompts, isNotEmpty);
    });
  });

  group('Topic.fromJson — agent intro fixture', () {
    late Topic topic;
    setUp(() {
      topic = Topic.fromJson(
        json.decode(_fixture('agent/intro.json')) as Map<String, dynamic>,
      );
    });

    test('basic fields', () {
      expect(topic.id, 'agent.core.intro');
      expect(topic.domainId, 'agent');
      expect(topic.interviewFrequency, 'medium');
    });
  });

  group('Topic.fromJson — jvm memory model fixture', () {
    late Topic topic;
    setUp(() {
      topic = Topic.fromJson(
        json.decode(_fixture('java/jvm_memory_model.json')) as Map<String, dynamic>,
      );
    });

    test('basic fields', () {
      expect(topic.id, 'java.jvm.memory-model');
      expect(topic.domainId, 'java');
      expect(topic.title, isNotEmpty);
    });
  });
}
