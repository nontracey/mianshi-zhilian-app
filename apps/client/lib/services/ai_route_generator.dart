import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/domain.dart';
import '../models/learning_route.dart';
import '../models/topic.dart';
import '../models/user_progress.dart';
import '../providers/content_provider.dart';
import '../providers/progress_provider.dart';
import '../services/ai_service.dart';
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
        final scopedTopics = contentProvider.topics.values
            .where((t) => selectedDomainIds.contains(t.domainId))
            .toList();
        final route = await _aiGenerateRoute(plan, scopedTopics, progressProvider, aiService);
        if (route != null) {
          await _cacheRoute(plan, route);
          return route;
        }
      } catch (e) {
        debugPrint('AI route generation failed, using fallback: $e');
      }
    }

    final route = _generateFallbackRoute(plan, allTopics, progressProvider);
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

  Future<LearningRoute?> _aiGenerateRoute(
    PrepPlan plan,
    List<Topic> allTopics,
    ProgressProvider progressProvider,
    AiService aiService,
  ) async {
    final topicLines = allTopics.map((t) {
      final score = progressProvider.getProgress(t.id)?.score ?? -1;
      return '${t.id} | ${t.title} | ${t.category} | ${t.difficulty} | ${t.interviewFrequency} | ${t.prerequisites.join(',')} | $score';
    }).join('\n');

    final prompt = '''
你是一个面试备考规划师。用户的目标岗位是 ${plan.targetRole}，
技术栈是 ${plan.techStack}，${plan.interviewDate != null ? '距离面试还有 ${plan.interviewDate!.difference(DateTime.now()).inDays} 天' : '暂无面试日期'}，
每天可用 ${plan.dailyMinutes} 分钟。

当前掌握度评分（-1 表示未学习，0-100 表示学习评分）：
$topicLines

${plan.jobDescription.isNotEmpty ? '用户的JD：${plan.jobDescription.substring(0, plan.jobDescription.length.clamp(0, 300))}' : ''}

请生成一个学习路线：
1. 从以下知识点中筛选出与用户目标真正相关的知识点加入路线
2. 对于前置依赖知识点（如JD涉及Agent但需要Java基础），如果用户未掌握也应加入
3. 按 PHASE 划分，每阶段 3-8 个知识点
4. 未掌握(score<60) + 高频 + 面试常考的知识点优先
5. 考虑前置依赖关系
6. 最后阶段为模拟面试(type=mock)
7. 每个 phase 的 topicIds 只包含实际要学的内容，不相关的知识点不要加入

输出 JSON：
{
  "name": "路线名称",
  "description": "路线描述",
  "domainIds": ["涉及的领域ID"],
  "phases": [
    {
      "id": "phase_1",
      "focus": "阶段焦点",
      "description": "阶段描述",
      "topicIds": ["topic-id-1", "topic-id-2"],
      "estimatedHours": 4,
      "type": "learn"
    }
  ]
}
只输出 JSON，不要额外文字。
''';

    final response = await aiService.sendMessage(prompt);
    return _parseRouteResponse(response, allTopics);
  }

  LearningRoute? _parseRouteResponse(String response, List<Topic> allTopics) {
    try {
      final json = _extractJson(response);
      if (json == null) return null;

      final phases = (json['phases'] as List?)?.map((p) {
        final pMap = p as Map<String, dynamic>;
        return RoutePhase(
          id: pMap['id'] as String? ?? 'phase_${DateTime.now().millisecondsSinceEpoch}',
          focus: pMap['focus'] as String? ?? '',
          description: pMap['description'] as String?,
          topicIds: (pMap['topicIds'] as List?)?.cast<String>() ?? [],
          estimatedHours: (pMap['estimatedHours'] as num?)?.toInt() ?? 0,
          type: pMap['type'] as String? ?? 'learn',
        );
      }).toList();

      return LearningRoute(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? 'AI 推荐路线',
        description: json['description'] as String? ?? '',
        domainIds: (json['domainIds'] as List?)?.cast<String>() ?? allTopics.map((t) => t.domainId).toSet().toList(),
        phases: phases,
        source: 'ai',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Parse route response failed: $e');
      return null;
    }
  }

  Map<String, dynamic>? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return json.decode(text.substring(start, end + 1)) as Map<String, dynamic>?;
  }

  LearningRoute _generateFallbackRoute(
    PrepPlan plan,
    List<Topic> allTopics,
    ProgressProvider progressProvider,
  ) {
    final topicScores = <String, int>{};
    for (final topic in allTopics) {
      final score = progressProvider.getProgress(topic.id)?.score ?? -1;
      var priority = 0;
      if (topic.highFrequency || topic.interviewFrequency == 'high') priority += 500;
      if (score < 0 || score < 60) priority += 300;
      if (score >= 85) priority -= 200;
      priority += (100 - score.clamp(0, 100));
      topicScores[topic.id] = priority;
    }

    final sorted = List<Topic>.from(allTopics)
      ..sort((a, b) => (topicScores[b.id] ?? 0).compareTo(topicScores[a.id] ?? 0));

    final placed = <String>{};
    final phases = <RoutePhase>[];
    var phaseIdx = 0;

    final independent = sorted.where((t) {
      return t.prerequisites.every((p) => !allTopics.any((at) => at.id == p));
    }).toList();

    if (independent.isNotEmpty) {
      phases.add(RoutePhase(
        id: 'phase_${++phaseIdx}',
        focus: '基础巩固',
        description: '掌握基础知识，建立核心概念体系',
        topicIds: independent.map((t) => t.id).toList(),
        estimatedHours: (independent.length * 1.5).round(),
        type: 'learn',
      ));
      placed.addAll(independent.map((t) => t.id));
    }

    final remaining = sorted.where((t) => !placed.contains(t.id)).toList();
    final byCategory = <String, List<Topic>>{};
    for (final topic in remaining) {
      byCategory.putIfAbsent(topic.category, () => []);
      byCategory[topic.category]!.add(topic);
    }

    for (final entry in byCategory.entries) {
      final topics = entry.value;
      for (var i = 0; i < topics.length; i += 6) {
        final chunk = topics.sublist(i, (i + 6).clamp(0, topics.length));
        final type = phaseIdx < 3 ? 'learn' : 'practice';
        phases.add(RoutePhase(
          id: 'phase_${++phaseIdx}_${entry.key.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}',
          focus: '${entry.key}进阶',
          description: '深入学习 ${entry.key} 领域的高频面试题',
          topicIds: chunk.map((t) => t.id).toList(),
          estimatedHours: chunk.length * 2,
          type: type,
        ));
        placed.addAll(chunk.map((t) => t.id));
      }
    }

    final mockTopics = allTopics
        .where((t) => t.highFrequency || t.interviewFrequency == 'high')
        .take(5)
        .map((t) => t.id)
        .toList();
    if (mockTopics.isNotEmpty) {
      phases.add(RoutePhase(
        id: 'phase_mock',
        focus: '模拟面试',
        description: '综合模拟面试，检验学习成果',
        topicIds: mockTopics,
        estimatedHours: 2,
        type: 'mock',
      ));
    }

    return LearningRoute(
      id: 'fallback_${DateTime.now().millisecondsSinceEpoch}',
      name: '备选学习路线',
      description: plan.targetRole.isNotEmpty
          ? '针对 ${plan.targetRole} 岗位的备选学习方案'
          : '基于知识点优先级自动生成的备选路线',
      domainIds: allTopics.map((t) => t.domainId).toSet().toList(),
      phases: phases,
      source: 'fallback',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
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
