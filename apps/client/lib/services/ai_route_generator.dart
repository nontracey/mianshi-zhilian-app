import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import '../models/domain.dart';
import '../models/learning_route.dart';
import '../models/topic.dart';
import '../models/user_progress.dart';
import '../providers/content_provider.dart';
import '../providers/progress_provider.dart';
import '../services/ai_service.dart';
import '../services/content_api_service.dart';
import '../services/storage_service.dart';

class AiRouteGenerator {
  final StorageService _storage;
  final List<Domain> _allDomains;

  AiRouteGenerator(this._storage, this._allDomains);

  Future<LearningRoute> generateRoute({
    required PrepPlan plan,
    required List<Topic> allTopics,
    required ProgressProvider progressProvider,
    required AiService aiService,
    required ContentProvider contentProvider,
    bool forceRegenerate = false,
  }) async {
    if (!forceRegenerate) {
      final cached = await _loadCachedRoute(plan);
      if (cached != null) return cached;
    }

    if (await aiService.isAvailable()) {
      try {
        final selectedDomainIds = await _selectDomains(plan, aiService);
        await contentProvider.ensureTopicsLoaded(selectedDomainIds);

        final relevantTopicIds = await _selectTopics(
          plan, selectedDomainIds, contentProvider, progressProvider, aiService,
        );

        final route = _buildStructuredRoute(
          plan, selectedDomainIds, relevantTopicIds, contentProvider, progressProvider,
        );
        await _cacheRoute(plan, route);
        return route;
      } catch (e) {
        debugPrint('AI route generation failed, using fallback: $e');
      }
    }

    final route = _generateFallbackRoute(plan, allTopics, progressProvider, contentProvider);
    await _cacheRoute(plan, route);
    return route;
  }

  Future<List<String>> _selectDomains(PrepPlan plan, AiService aiService) async {
    if (await aiService.isAvailable()) {
      final domainList = _allDomains.map((d) =>
          '${d.id}: ${d.title}（${d.categories.map((c) => c.title).join('、')}）').join('\n');

      final prompt = '''
用户目标：${plan.targetRole} / ${plan.techStack}
${plan.jobDescription.isNotEmpty ? 'JD概要：${plan.jobDescription.substring(0, plan.jobDescription.length.clamp(0, 300))}' : ''}

可选领域：
$domainList

请按以下要求选择领域：
1. 选出与用户目标相关的领域，按相关度从高到低排序
2. 包含用户目标所需的"前置知识"领域（如Agent开发需要Python/Java基础）
3. 不相关的领域不要包含

返回 JSON 数组，每个元素包含领域ID和理由。只输出JSON。
示例格式：["java", "architecture", "agent"]
''';

      try {
        final response = await aiService.sendMessage(prompt);
        final start = response.indexOf('[');
        final end = response.lastIndexOf(']');
        if (start != -1 && end > start) {
          return (json.decode(response.substring(start, end + 1)) as List)
              .cast<String>();
        }
      } catch (_) {}
    }

    // 降级：本地关键词匹配
    return _matchDomainsLocally(plan);
  }

  List<String> _matchDomainsLocally(PrepPlan plan) {
    final searchText =
        '${plan.targetRole} ${plan.techStack} ${plan.jobDescription}'.toLowerCase();
    if (searchText.length < 3) return _allDomains.map((d) => d.id).toList();

    final matched = _allDomains.where((d) {
      final text = '${d.title} ${d.description} ${d.categories.map((c) => '${c.title} ${c.id}').join(' ')}'.toLowerCase();
      return searchText.split(RegExp(r'[\s,，、；;]+')).any((w) => w.length >= 2 && text.contains(w));
    }).toList();

    final matchedIds = matched.map((d) => d.id).toSet();

    // 无AI时：包含匹配领域的前置知识领域（如Agent需要Java）
    for (final domain in matched) {
      for (final cat in domain.categories) {
        // 通过分类信息推断前置领域
        final text = '${cat.title} ${cat.description}'.toLowerCase();
        for (final d in _allDomains) {
          if (!matchedIds.contains(d.id)) {
            final domainText = '${d.title} ${d.description} ${d.categories.map((c) => c.title).join(' ')}'.toLowerCase();
            if (text.contains(d.id) || text.split(' ').any((w) => w.length >= 2 && domainText.contains(w))) {
              matchedIds.add(d.id);
            }
          }
        }
      }
    }

    return matchedIds.toList();
  }

  Future<Set<String>> _selectTopics(
    PrepPlan plan,
    List<String> domainIds,
    ContentProvider contentProvider,
    ProgressProvider progressProvider,
    AiService aiService,
  ) async {
    final topics = contentProvider.topics.values
        .where((t) => domainIds.contains(t.domainId))
        .toList();
    if (topics.isEmpty) return {};

    final topicLines = topics.map((t) {
      final score = progressProvider.getProgress(t.id)?.score ?? -1;
      return '${t.id} | ${t.title} | ${t.domainId} | ${t.difficulty} | ${t.interviewFrequency} | $score';
    }).join('\n');

    final prompt = '''
用户目标：${plan.targetRole} / ${plan.techStack}
${plan.jobDescription.isNotEmpty ? 'JD：${plan.jobDescription.substring(0, plan.jobDescription.length.clamp(0, 300))}' : ''}

相关领域的知识点（格式: id | 名称 | 领域 | 难度 | 面试频率 | 掌握度）：
$topicLines

从以上知识点中选出与用户目标直接相关的知识点，只返回被选中的 id 组成的 JSON 数组。
示例：["java-jvm", "java-collections", "agent-intro"]
只输出 JSON 数组，不要额外文字。''';

    try {
      final response = await aiService.sendMessage(prompt);
      final start = response.indexOf('[');
      final end = response.lastIndexOf(']');
      if (start != -1 && end > start) {
        final ids = (json.decode(response.substring(start, end + 1)) as List)
            .cast<String>();
        return ids.toSet();
      }
    } catch (_) {}

    // 降级：返回所有 topic ID
    return topics.map((t) => t.id).toSet();
  }

  LearningRoute _buildStructuredRoute(
    PrepPlan plan,
    List<String> domainIds,
    Set<String> relevantTopicIds,
    ContentProvider contentProvider,
    ProgressProvider progressProvider,
  ) {
    final phases = <RoutePhase>[];
    final now = DateTime.now();

    for (final domainId in domainIds) {
      final domain = _allDomains.firstWhereOrNull((d) => d.id == domainId);
      if (domain == null || domain.learningPaths.isEmpty) continue;

      for (final lp in domain.learningPaths) {
        for (var i = 0; i < lp.steps.length; i++) {
          final step = lp.steps[i];
          final stepTopics = <String>[];
          for (final catId in step.categoryIds) {
            final category = domain.categories.firstWhereOrNull((c) => c.id == catId);
            if (category != null) {
              for (final topicFile in category.topics) {
                // 通过 cache key 查找 topic 对象，使用其 content ID
                final cacheKey = ContentApiService.cacheKeyForTopicRef(topicFile);
                final topic = contentProvider.getTopicById(cacheKey);
                if (topic == null) continue;
                final tid = topic.id; // 使用 "java.jvm.xxx" 格式的 content ID
                // 只包含 AI 选中且已掌握度低于 85 的
                final score = progressProvider.getTopicProgress(tid)?.score ?? 0;
                if (relevantTopicIds.contains(tid) && score < 85) {
                  stepTopics.add(tid);
                }
              }
            }
          }
          if (stepTopics.isNotEmpty) {
            phases.add(RoutePhase(
              id: '${domainId}_lp${lp.id}_s$i',
              focus: step.title.isNotEmpty ? step.title : '${domain.title} ${lp.title} 第${i + 1}阶段',
              description: step.description,
              topicIds: stepTopics,
              categoryIds: step.categoryIds,
              prerequisiteSteps: step.prerequisiteSteps,
              estimatedHours: step.estimatedHours,
              type: i == lp.steps.length - 1 ? 'practice' : 'learn',
              domainId: domainId,
            ));
          }
        }
      }
    }

    return LearningRoute(
      id: 'ai_${now.millisecondsSinceEpoch}',
      name: plan.targetRole.isNotEmpty ? '${plan.targetRole} 备考路线' : 'AI 个性化路线',
      description: plan.techStack.isNotEmpty ? '目标：${plan.techStack}' : '',
      domainIds: domainIds,
      phases: phases,
      source: 'ai',
      createdAt: now,
      updatedAt: now,
    );
  }
  LearningRoute _generateFallbackRoute(
    PrepPlan plan,
    List<Topic> allTopics,
    ProgressProvider progressProvider,
    ContentProvider contentProvider,
  ) {
    final domainIds = _matchDomainsLocally(plan);
    final relevantIds = allTopics.map((t) => t.id).toSet();
    return _buildStructuredRoute(
      plan, domainIds, relevantIds, contentProvider, progressProvider,
    );
  }

  Future<LearningRoute?> _loadCachedRoute(PrepPlan plan) async {
    final cacheKey = _cacheKey(plan);
    final data = await _storage.load(cacheKey);
    if (data is Map<String, dynamic>) {
      final cached = LearningRoute.fromJson(data);
      if (DateTime.now().difference(cached.createdAt).inHours < 24) {
        return cached;
      }
    }
    return null;
  }

  Future<void> _cacheRoute(PrepPlan plan, LearningRoute route) async {
    await _storage.save(_cacheKey(plan), route.toJson());
  }

  String _cacheKey(PrepPlan plan) =>
    'route_cache_${_hashString('${plan.jobDescription}_${plan.targetRole}_${plan.interviewDate?.toIso8601String()}')}';

  String _hashString(String input) =>
    input.hashCode.toString();
}
