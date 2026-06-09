import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import '../models/ai_config.dart';
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

  /// 仅执行领域选择步骤（供调用方预加载 topics）
  Future<List<String>> selectDomainIds({
    required PrepPlan plan,
    required AiService aiService,
    required AiConfig aiConfig,
  }) async {
    return _selectDomains(plan, aiService, aiConfig);
  }

  Future<LearningRoute> generateRoute({
    required PrepPlan plan,
    required List<Topic> allTopics,
    required ProgressProvider progressProvider,
    required AiService aiService,
    required ContentProvider contentProvider,
    AiConfig? aiConfig,
    bool forceRegenerate = false,
    String? contentVersion,
  }) async {
    if (!forceRegenerate) {
      final cached = await _loadCachedRoute(plan, contentVersion: contentVersion);
      if (cached != null) return cached;
    }

    final useAi = aiService.isConfigAvailable(aiConfig);
    if (useAi) {
      try {
        final selectedDomainIds = await _selectDomains(plan, aiService, aiConfig!);
        await contentProvider.ensureTopicsLoaded(selectedDomainIds);

        final relevantTopicIds = await _selectTopics(
          plan, selectedDomainIds, contentProvider, progressProvider, aiService, aiConfig,
        );

        final route = _buildStructuredRoute(
          plan, selectedDomainIds, relevantTopicIds, contentProvider, progressProvider,
        );
        await _cacheRoute(plan, route, contentVersion: contentVersion);
        return route;
      } catch (e) {
        debugPrint('AI route generation failed, using fallback: $e');
      }
    }

    final route = _generateFallbackRoute(plan, allTopics, progressProvider, contentProvider);
    await _cacheRoute(plan, route, contentVersion: contentVersion);
    return route;
  }

  Future<List<String>> _selectDomains(PrepPlan plan, AiService aiService, AiConfig aiConfig) async {
    final validIds = _allDomains.map((d) => d.id).toSet();
    final domainList = _allDomains.map((d) =>
        '"${d.id}": ${d.title}（${d.categories.map((c) => c.title).join('、')}）').join('\n');

    final prompt = '''
用户目标：${plan.targetRole} / ${plan.techStack}
${plan.jobDescription.isNotEmpty ? 'JD概要：${plan.jobDescription.substring(0, plan.jobDescription.length.clamp(0, 300))}' : ''}

可选领域（只能从下列 ID 中选择，不要发明新 ID）：
$domainList

要求：
1. 选出与用户目标相关的领域，按相关度从高到低排序
2. 包含用户目标所需的前置知识领域（如 Agent 开发需要 java 或 python 基础）
3. 不相关的领域不要包含
4. 只能使用上面列出的领域 ID，严禁输出上面没有的 ID

只输出一个 JSON 字符串数组，不要任何其他文字。
示例：["java", "architecture", "agent"]
''';

    try {
      final response = await aiService.sendMessage(prompt, config: aiConfig);
      final start = response.indexOf('[');
      final end = response.lastIndexOf(']');
      if (start != -1 && end > start) {
        final raw = (json.decode(response.substring(start, end + 1)) as List)
            .cast<String>();
        // 白名单过滤，确保返回的 ID 都合法
        final filtered = raw.where(validIds.contains).toList();
        if (filtered.isNotEmpty) return filtered;
      }
    } catch (e) {
      debugPrint('AI domain selection failed: $e');
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
    AiConfig aiConfig,
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
      final response = await aiService.sendMessage(prompt, config: aiConfig);
      final start = response.indexOf('[');
      final end = response.lastIndexOf(']');
      if (start != -1 && end > start) {
        final ids = (json.decode(response.substring(start, end + 1)) as List)
            .cast<String>();
        return ids.toSet();
      }
    } catch (e) {
      debugPrint('AI topic selection failed: $e');
    }

    // 降级：返回面试频率为 high 或 medium 的 topic ID
    return topics
        .where((t) => t.interviewFrequency == 'high' || t.interviewFrequency == 'medium')
        .map((t) => t.id)
        .toSet();
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
                // 全量纳入 AI 选中的 topic（含已掌握），掌握状态交展示层着色，
                // 避免重新生成后掌握度分母缩减、进度被人为推高。
                if (relevantTopicIds.contains(tid)) {
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

    final sig = _stableHash('${plan.targetRole}_${plan.techStack}_${plan.jobDescription}_${plan.interviewDate?.toIso8601String() ?? ''}');
    return LearningRoute(
      id: 'ai_$sig',
      name: plan.targetRole.isNotEmpty ? '${plan.targetRole} 备考路线' : 'AI 个性化路线',
      description: plan.techStack.isNotEmpty ? '目标：${plan.techStack}' : '',
      domainIds: domainIds,
      phases: phases,
      source: 'ai',
      createdAt: now,
      updatedAt: now,
      planSignature: sig,
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

  Future<LearningRoute?> _loadCachedRoute(PrepPlan plan, {String? contentVersion}) async {
    final cacheKey = _cacheKey(plan, contentVersion: contentVersion);
    final data = await _storage.load(cacheKey);
    if (data is Map<String, dynamic>) {
      final cached = LearningRoute.fromJson(data);
      if (DateTime.now().difference(cached.createdAt).inHours < 24) {
        return cached;
      }
    }
    return null;
  }

  Future<void> _cacheRoute(PrepPlan plan, LearningRoute route, {String? contentVersion}) async {
    await _storage.save(_cacheKey(plan, contentVersion: contentVersion), route.toJson());
  }

  String _cacheKey(PrepPlan plan, {String? contentVersion}) =>
    'route_cache_${_stableHash('${plan.jobDescription}_${plan.targetRole}_${plan.techStack}_${plan.interviewDate?.toIso8601String() ?? ''}_${contentVersion ?? ''}')}';

  static String _stableHash(String input) =>
    sha256.convert(utf8.encode(input)).toString().substring(0, 16);
}
