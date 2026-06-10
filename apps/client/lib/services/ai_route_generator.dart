import 'dart:convert';
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
import '../services/route_composer.dart';

class AiRouteGenerator {
  final List<Domain> _allDomains;

  // A-7：路线生成不再持有独立缓存存储，custom_routes 是唯一事实源。
  AiRouteGenerator(this._allDomains);

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
    // A-7：custom_routes 是唯一事实源——非强制重生时直接复用调用方已持有的
    // 同 planSignature 路线，不再维护独立的 route_cache_* 24h 缓存层。
    List<LearningRoute> existingRoutes = const [],
  }) async {
    if (!forceRegenerate) {
      final sig = plan.signature;
      final existing = existingRoutes.firstWhereOrNull(
        (r) => r.source == 'ai' && r.planSignature == sig,
      );
      if (existing != null) return existing;
    }

    final useAi = aiService.isConfigAvailable(aiConfig);
    if (useAi) {
      try {
        final selectedDomainIds = await _selectDomains(plan, aiService, aiConfig!);
        await contentProvider.ensureTopicsLoaded(selectedDomainIds);
        // 结构完全来自内容库 learningPath：AI 只负责「选哪些领域」，
        // 领域内阶段/topic 不再由 AI 二次裁剪，避免「选了领域却没内容」。
        return _buildStructuredRoute(plan, selectedDomainIds, contentProvider);
      } catch (e) {
        debugPrint('AI route generation failed, using fallback: $e');
      }
    }

    return _generateFallbackRoute(plan, contentProvider);
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

要求（务必精准，宁缺毋滥）：
1. 只选**与用户目标直接相关**的领域，按相关度从高到低排序
2. 仅当确为该目标的**必要前置基础**时才纳入前置领域（如 Agent 开发需 python 或 java 基础）；不确定就不要加
3. **严禁纳入与目标无关的领域**——例如后端/Agent 目标不要纳入「前端八股」，前端目标不要纳入 JVM/中间件等
4. 领域数量通常 1-3 个，最多不超过 4 个；不要为了凑数而扩列
5. 只能使用上面列出的领域 ID，严禁输出上面没有的 ID

只输出一个 JSON 字符串数组，不要任何其他文字。
示例：["python", "agent"]
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

  // 过于通用、无区分度的词，匹配时忽略，避免「X 开发」把所有「Y 开发」领域都拉进来。
  static const _genericWords = {
    '开发', '工程师', '面试', '岗位', '方向', '基础', '进阶', '高级', '初级',
    '中级', '实习', '校招', '社招', '相关', '技术', '知识',
  };

  static final _splitRe = RegExp(r'[\s,，、；;/]+');

  /// 分词：小写、按分隔符切，过滤过短与通用词。用整词集合做交集，避免
  /// 「java」误命中「javascript」这类子串假阳性。
  Set<String> _tokenize(String s) => s
      .toLowerCase()
      .split(_splitRe)
      .where((w) => w.length >= 2 && !_genericWords.contains(w))
      .toSet();

  /// 无 AI 时的本地领域匹配：用「目标词 ∩ 领域(id+标题+描述)词」的整词交集打分，
  /// 不再扫描宽泛分类文本、不做贪婪前置推断——宁缺毋滥，按强度排序、最多取 4 个。
  List<String> _matchDomainsLocally(PrepPlan plan) {
    final goalTokens =
        _tokenize('${plan.targetRole} ${plan.techStack} ${plan.jobDescription}');
    if (goalTokens.isEmpty) {
      return _allDomains.isNotEmpty ? [_allDomains.first.id] : [];
    }

    final scored = <MapEntry<String, int>>[];
    for (final d in _allDomains) {
      final domainTokens = _tokenize('${d.id} ${d.title} ${d.description}');
      final overlap = goalTokens.intersection(domainTokens).length;
      // 领域 id 作为整词出现在目标里 → 强信号加权
      final idBonus = goalTokens.contains(d.id.toLowerCase()) ? 2 : 0;
      final score = overlap + idBonus;
      if (score > 0) scored.add(MapEntry(d.id, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    final result = scored.take(4).map((e) => e.key).toList();
    if (result.isNotEmpty) return result;
    // 兜底：完全无匹配时返回第一个领域，避免空路线。
    return _allDomains.isNotEmpty ? [_allDomains.first.id] : [];
  }

  /// 用内容库 learningPath 确定性地组装路线：领域内结构完全来自内容契约，
  /// `domainIds` 由实际产出 phases 的领域推导，保证「声称领域 == 有内容领域」。
  LearningRoute _buildStructuredRoute(
    PrepPlan plan,
    List<String> domainIds,
    ContentProvider contentProvider,
  ) {
    final phases = RouteComposer.composePhasesFromContent(
      orderedDomainIds: domainIds,
      allDomains: _allDomains,
      getTopicById: contentProvider.getTopicById,
    );
    final effectiveDomains = RouteComposer.domainsOf(phases);

    final sig = plan.signature;
    final now = DateTime.now();
    return LearningRoute(
      id: 'ai_$sig',
      name: plan.targetRole.isNotEmpty ? '${plan.targetRole} 备考路线' : 'AI 个性化路线',
      description: plan.techStack.isNotEmpty ? '目标：${plan.techStack}' : '',
      // 与 phases 保持一致：没有内容的领域不进 domainIds（极端情况下退回原选择）
      domainIds: effectiveDomains.isNotEmpty ? effectiveDomains : domainIds,
      phases: phases,
      source: 'ai',
      createdAt: now,
      updatedAt: now,
      planSignature: sig,
    );
  }

  LearningRoute _generateFallbackRoute(
    PrepPlan plan,
    ContentProvider contentProvider,
  ) {
    final domainIds = _matchDomainsLocally(plan);
    return _buildStructuredRoute(plan, domainIds, contentProvider);
  }
}
