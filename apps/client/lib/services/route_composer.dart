import '../models/domain.dart';
import '../models/learning_route.dart';
import '../models/topic.dart';
import 'content_api_service.dart';

/// 路线组装器：把内容库里**每个领域已定义的 learningPath**确定性地拼成路线
/// phases。AI 生成与手动编辑都走这里，保证「路线结构 = 内容契约」这一单一事实源：
///
/// - 领域内的阶段顺序、分类、topic 顺序全部由 content 的 learningPath 决定，
///   App 不再二次定义或裁剪；
/// - 多领域路线 = 所选领域 learningPath 的有序拼接（领域顺序由调用方给定）；
/// - 路线 `domainIds` 由实际产出 phases 的领域推导，绝不会「声称某领域但无内容」。
///
/// 注意：topic 需已通过 ContentProvider 加载（[resolveTopic] 命中），否则该 topic
/// 不计入——调用方应先 `ensureTopicsLoaded(domainIds)`。
class RouteComposer {
  /// 按 [orderedDomainIds] 的顺序，从内容库 learningPath 组装 phases。
  ///
  /// [resolveTopic] 把 learningPath 里的 topicRef（如
  /// `topics/java/topic-001.json`）解析为已加载的 Topic；通常传
  /// `(ref) => content.getTopicById(ContentApiService.cacheKeyForTopicRef(ref))`。
  static List<RoutePhase> composePhases({
    required List<String> orderedDomainIds,
    required List<Domain> allDomains,
    required Topic? Function(String topicRef) resolveTopic,
  }) {
    final phases = <RoutePhase>[];
    final domainById = {for (final d in allDomains) d.id: d};

    for (final domainId in orderedDomainIds) {
      final domain = domainById[domainId];
      if (domain == null || domain.learningPaths.isEmpty) continue;

      for (final lp in domain.learningPaths) {
        for (var i = 0; i < lp.steps.length; i++) {
          final step = lp.steps[i];
          final stepTopics = <String>[];
          for (final catId in step.categoryIds) {
            final category = domain.categories
                .where((c) => c.id == catId)
                .firstOrNull;
            if (category == null) continue;
            for (final topicRef in category.topics) {
              final topic = resolveTopic(topicRef);
              if (topic == null) continue; // 未加载则跳过
              stepTopics.add(topic.id);
            }
          }
          if (stepTopics.isEmpty) continue;
          phases.add(
            RoutePhase(
              id: '${domainId}_lp${lp.id}_s$i',
              focus: step.title.isNotEmpty
                  ? step.title
                  : '${domain.title} ${lp.title} 第${i + 1}阶段',
              description: step.description,
              topicIds: stepTopics,
              categoryIds: step.categoryIds,
              prerequisiteSteps: step.prerequisiteSteps,
              estimatedHours: step.estimatedHours,
              type: i == lp.steps.length - 1 ? 'practice' : 'learn',
              domainId: domainId,
            ),
          );
        }
      }
    }
    return phases;
  }

  /// 便捷封装：直接用 content 的 getTopicById 解析。
  static List<RoutePhase> composePhasesFromContent({
    required List<String> orderedDomainIds,
    required List<Domain> allDomains,
    required Topic? Function(String cacheKey) getTopicById,
  }) {
    return composePhases(
      orderedDomainIds: orderedDomainIds,
      allDomains: allDomains,
      resolveTopic: (ref) =>
          getTopicById(ContentApiService.cacheKeyForTopicRef(ref)),
    );
  }

  /// 从 phases 推导有序去重的领域列表（= 真正有内容的领域）。
  static List<String> domainsOf(List<RoutePhase> phases) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final p in phases) {
      final d = p.domainId;
      if (d == null || d.isEmpty) continue;
      if (seen.add(d)) ordered.add(d);
    }
    return ordered;
  }

  /// 将路线阶段投影到指定 topic 集合，保留阶段顺序并丢弃空阶段。
  ///
  /// 用于目录页在路线视图中叠加领域/搜索/难度等筛选：阶段结构仍来自路线，
  /// 但每个阶段只展示当前筛选范围内的 topic。
  static List<RoutePhase> filterPhasesByTopicIds(
    List<RoutePhase> phases,
    Iterable<String> topicIds,
  ) {
    final allowed = topicIds.toSet();
    if (allowed.isEmpty) return const [];

    final filtered = <RoutePhase>[];
    for (final phase in phases) {
      final phaseTopicIds = phase.topicIds
          .where(allowed.contains)
          .toList(growable: false);
      if (phaseTopicIds.isEmpty) continue;
      filtered.add(phase.copyWith(topicIds: phaseTopicIds));
    }
    return filtered;
  }
}
