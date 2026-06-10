import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/services/route_composer.dart';

/// RouteComposer：路线结构来自内容库 learningPath（单一事实源）。
/// 验证「声称的领域 == 实际有内容的领域」、跨域拼接、领域重排生效。
void main() {
  // 两个领域各一条 learningPath，覆盖各自的两个分类。
  Domain domain(String id, String title, Map<String, List<String>> catTopics) {
    final cats = catTopics.entries
        .map((e) => Category(id: e.key, title: e.key, topics: e.value))
        .toList();
    final steps = catTopics.keys
        .map((catId) => LearningPathStep(
              title: '阶段 $catId',
              description: '',
              categoryIds: [catId],
            ))
        .toList();
    return Domain(
      id: id,
      title: title,
      description: '',
      categories: cats,
      learningPaths: [
        LearningPath(id: '$id-path', title: '$title 路线', description: '', steps: steps),
      ],
    );
  }

  // topicRef -> Topic（content id 形如 domain.category.name）
  final java = domain('java', 'Java', {
    'jvm': ['topics/java/jvm-1.json', 'topics/java/jvm-2.json'],
    'collections': ['topics/java/col-1.json'],
  });
  final agent = domain('agent', 'Agent', {
    'llm': ['topics/agent/llm-1.json'],
    'rag': ['topics/agent/rag-1.json', 'topics/agent/rag-2.json'],
  });

  final topicByRef = <String, Topic>{
    'topics/java/jvm-1.json': const Topic(id: 'java.jvm.jvm-1', domain: 'java', category: 'jvm', title: 'JVM1', summary: ''),
    'topics/java/jvm-2.json': const Topic(id: 'java.jvm.jvm-2', domain: 'java', category: 'jvm', title: 'JVM2', summary: ''),
    'topics/java/col-1.json': const Topic(id: 'java.collections.col-1', domain: 'java', category: 'collections', title: 'Col1', summary: ''),
    'topics/agent/llm-1.json': const Topic(id: 'agent.llm.llm-1', domain: 'agent', category: 'llm', title: 'LLM1', summary: ''),
    'topics/agent/rag-1.json': const Topic(id: 'agent.rag.rag-1', domain: 'agent', category: 'rag', title: 'RAG1', summary: ''),
    'topics/agent/rag-2.json': const Topic(id: 'agent.rag.rag-2', domain: 'agent', category: 'rag', title: 'RAG2', summary: ''),
  };

  // resolveTopic 直接按 ref 命中（绕过 cacheKey 转换，专注组装逻辑）
  Topic? resolve(String ref) => topicByRef[ref];

  group('composePhases — content is the single source of truth', () {
    test('multi-domain route covers every selected domain', () {
      final phases = RouteComposer.composePhases(
        orderedDomainIds: ['java', 'agent'],
        allDomains: [java, agent],
        resolveTopic: resolve,
      );
      // 每个领域的每个分类各一个 phase
      expect(phases.map((p) => p.domainId).toSet(), {'java', 'agent'});
      final allTopics = phases.expand((p) => p.topicIds).toSet();
      expect(allTopics, contains('java.jvm.jvm-1'));
      expect(allTopics, contains('agent.rag.rag-2'));
      expect(allTopics.length, 6);
    });

    test('domainsOf == selected domains that actually have content', () {
      final phases = RouteComposer.composePhases(
        orderedDomainIds: ['java', 'agent'],
        allDomains: [java, agent],
        resolveTopic: resolve,
      );
      expect(RouteComposer.domainsOf(phases), ['java', 'agent']);
    });

    test('reordering domains reorders phases (issue 3)', () {
      final phasesA = RouteComposer.composePhases(
        orderedDomainIds: ['java', 'agent'],
        allDomains: [java, agent],
        resolveTopic: resolve,
      );
      final phasesB = RouteComposer.composePhases(
        orderedDomainIds: ['agent', 'java'],
        allDomains: [java, agent],
        resolveTopic: resolve,
      );
      expect(RouteComposer.domainsOf(phasesA), ['java', 'agent']);
      expect(RouteComposer.domainsOf(phasesB), ['agent', 'java']);
      expect(phasesB.first.domainId, 'agent');
    });

    test('a selected domain with no loaded topics is dropped (no empty tab)', () {
      // agent 的 topic 都解析不到 → agent 不产出 phases
      Topic? javaOnly(String ref) =>
          ref.startsWith('topics/java/') ? topicByRef[ref] : null;
      final phases = RouteComposer.composePhases(
        orderedDomainIds: ['java', 'agent'],
        allDomains: [java, agent],
        resolveTopic: javaOnly,
      );
      expect(RouteComposer.domainsOf(phases), ['java']);
    });
  });

  group('LearningRoute.effectiveDomainIds', () {
    test('derives from phases when present (claimed == has-content)', () {
      final phases = RouteComposer.composePhases(
        orderedDomainIds: ['java', 'agent'],
        allDomains: [java, agent],
        resolveTopic: (ref) => ref.startsWith('topics/java/') ? topicByRef[ref] : null,
      );
      // 声称 3 个领域，但只有 java 有 phases
      final route = LearningRoute(
        id: 'r1',
        name: 'R',
        domainIds: ['java', 'agent', 'python'],
        phases: phases,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(route.effectiveDomainIds, ['java']);
    });

    test('falls back to stored domainIds when no phases', () {
      final route = LearningRoute(
        id: 'r2',
        name: 'R',
        domainIds: ['java', 'agent'],
        phases: null,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(route.effectiveDomainIds, ['java', 'agent']);
    });
  });
}
