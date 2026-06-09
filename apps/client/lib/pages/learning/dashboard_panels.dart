import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/utils/mastery_utils.dart';
import 'package:mianshi_zhilian/widgets/route_editor_dialog.dart';
import 'package:mianshi_zhilian/widgets/scope_selector_dialog.dart';
import 'dashboard_widgets.dart';
import 'dashboard_dialogs.dart';

// ── 学习路径项目组件 ──

class LearningPathItem extends StatefulWidget {
  const LearningPathItem({
    super.key,
    required this.domain,
    required this.index,
    required this.masteryPercent,
    required this.isSelected,
    required this.onTap,
    this.onViewCatalog,
  });

  final Domain domain;
  final int index;
  final int masteryPercent;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onViewCatalog;

  @override
  State<LearningPathItem> createState() => LearningPathItemState();
}

class LearningPathItemState extends State<LearningPathItem> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final level = getMasteryLevel(widget.masteryPercent);
    final status = level == MasteryLevel.mastered
        ? l10n.get('already_complete')
        : level == MasteryLevel.learning
        ? l10n.get('progress_action_in')
        : l10n.get('un_start');
    final statusColor = getMasteryColor(widget.masteryPercent);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? AppColors.accent.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isSelected
              ? AppColors.accent.withValues(alpha: 0.3)
              : (isDark ? AppColors.borderMidnight : AppColors.borderLight),
        ),
      ),
      child: Column(
        children: [
          // 主行
          InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 序号
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? AppColors.accent
                          : (isDark
                                ? AppColors.borderMidnightSubtle
                                : const Color(0xFFF0F2F5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: widget.isSelected
                              ? Colors.white
                              : (isDark
                                    ? Colors.white70
                                    : Colors.grey.shade700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 标题和状态
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.domain.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              l10n.getp('progress_percent_2', {
                                'percent': widget.masteryPercent,
                              }),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              l10n.getp('exam_point_count_2', {
                                'count': widget.domain.topicCount,
                              }),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 展开/折叠按钮
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的详情
          if (_isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // 描述
                  if (widget.domain.description.isNotEmpty) ...[
                    Text(
                      widget.domain.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 统计信息
                  Row(
                    children: [
                      _buildStatItem(
                        context,
                        icon: Icons.menu_book_outlined,
                        label: l10n.get('knowledge_point'),
                        value: '${widget.domain.topicCount}',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        context,
                        icon: Icons.trending_up,
                        label: l10n.get('mastery'),
                        value: '${widget.masteryPercent}%',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        context,
                        icon: Icons.category_outlined,
                        label: l10n.get('score_category'),
                        value: '${widget.domain.categories.length}',
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: widget.masteryPercent / 100,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                      color: AppColors.accent,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 查看详情按钮
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onViewCatalog ?? widget.onTap,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(l10n.get('check_view_knowledge_catalog')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: isDark ? Colors.white54 : Colors.grey),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── 左侧面板：今日复习队列、薄弱知识点TOP5 ──

class LeftPanel extends StatelessWidget {
  const LeftPanel({
    super.key,
    required this.dueTopics,
    required this.weakTopics,
    required this.onTopicTap,
    required this.onReview,
    required this.progressProvider,
    this.routeTopicIds,
    this.isRouteMode = false,
    this.routeFirstTopicId,
    this.onStartLearning,
  });

  final List<Topic> dueTopics;
  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;
  final VoidCallback? onReview;
  final ProgressProvider progressProvider;
  final List<String>? routeTopicIds;
  final bool isRouteMode;
  final String? routeFirstTopicId;
  final VoidCallback? onStartLearning;

  List<Topic> get _filteredDueTopics => routeTopicIds != null
      ? dueTopics.where((t) => routeTopicIds!.contains(t.id)).toList()
      : dueTopics;

  List<Topic> get _filteredWeakTopics => routeTopicIds != null
      ? weakTopics.where((t) => routeTopicIds!.contains(t.id)).toList()
      : weakTopics;

  bool get _hasNoProgress {
    final ids = routeTopicIds ?? [];
    if (ids.isEmpty) return dueTopics.isEmpty && weakTopics.isEmpty;
    for (final id in ids) {
      if ((progressProvider.getTopicProgress(id)?.score ?? 0) > 0) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredDueTopics = _filteredDueTopics;
    final filteredWeakTopics = _filteredWeakTopics;

    if (isRouteMode && _hasNoProgress) {
      return _buildStartGuidance(context, l10n, isDark);
    }

    // 非路线模式下，未开始学习时显示引导
    if (!isRouteMode && filteredDueTopics.isEmpty && filteredWeakTopics.isEmpty) {
      return _buildNewUserGuidance(context, l10n, isDark);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelCard(
          title: l10n.get('today_day_review_queue'),
          icon: Icons.replay_outlined,
          trailing: '${filteredDueTopics.length}',
          headerTrailing: Text(
            l10n.get('to_day_time'),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : AppColors.textTertiary,
            ),
          ),
          child: Column(
            children: [
              if (filteredDueTopics.isEmpty)
                EmptyState(message: l10n.get('temporary_no_to_day_content'))
              else
                ...filteredDueTopics.take(5).map((topic) {
                  final progress = progressProvider.getTopicProgress(topic.id);
                  final score = progress?.score ?? 0;
                  final nextReviewAt = progress?.nextReviewAt;
                  return ReviewItem(
                    topic: topic,
                    score: score,
                    nextReviewAt: nextReviewAt,
                    onTap: () => onTopicTap(topic.id),
                  );
                }),
                if (filteredDueTopics.length > 5)
                  TextButton(
                    onPressed: onReview,
                    child: Text(l10n.get('check_view_all_review')),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PanelCard(
          title: l10n.get('weak_knowledge_point_top_5'),
          icon: Icons.trending_down_outlined,
          trailing: '${filteredWeakTopics.length}',
          child: Column(
            children: [
              if (filteredWeakTopics.isEmpty)
                EmptyState(message: l10n.get('temporary_no_weak_item'))
              else
                ...filteredWeakTopics.map((topic) {
                  final progress = progressProvider.getTopicProgress(topic.id);
                  final score = progress?.score ?? 0;
                  return WeakTopicItem(
                    topic: topic,
                    score: score,
                    onTap: () => onTopicTap(topic.id),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStartGuidance(BuildContext context, LocalizationProvider l10n, bool isDark) {
    return PanelCard(
      title: l10n.get('route_start_guidance'),
      icon: Icons.rocket_launch_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.get('route_start_guidance_desc'),
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (routeFirstTopicId != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => onTopicTap(routeFirstTopicId!),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(l10n.get('start_first_topic')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          if (onStartLearning != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onStartLearning,
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: Text(l10n.get('browse_route_catalog')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNewUserGuidance(BuildContext context, LocalizationProvider l10n, bool isDark) {
    return PanelCard(
      title: l10n.get('start_learning_journey'),
      icon: Icons.auto_stories_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.get('new_user_guidance_desc'),
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (onStartLearning != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStartLearning,
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: Text(l10n.get('browse_knowledge_catalog')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CenterPanel extends StatefulWidget {
  const CenterPanel({
    super.key,
    required this.currentDomain,
    required this.allDomains,
    required this.currentDomainId,
    required this.recommendedTopics,
    required this.masteryPercent,
    required this.topicCount,
    required this.readiness,
    required this.streakDays,
    required this.onDomainChanged,
    required this.onTopicTap,
    required this.onViewDomainCatalog,
    required this.onPractice,
    required this.onReview,
    required this.onMockInterview,
    required this.contentProvider,
    required this.progressProvider,
    required this.settingsProvider,
    this.onGenerateAiRoute,
    this.onRegenerateAiRoute,
  });

  final Domain? currentDomain;
  final List<Domain> allDomains;
  final String currentDomainId;
  final List<Topic> recommendedTopics;
  final int masteryPercent;
  final int topicCount;
  final int readiness;
  final int streakDays;
  final ValueChanged<String> onDomainChanged;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onViewDomainCatalog;
  final VoidCallback onPractice;
  final VoidCallback? onReview;
  final VoidCallback? onMockInterview;
  final ContentProvider contentProvider;
  final ProgressProvider progressProvider;
  final SettingsProvider settingsProvider;
  final VoidCallback? onGenerateAiRoute;
  final VoidCallback? onRegenerateAiRoute;

  @override
  State<CenterPanel> createState() => CenterPanelState();
}

class CenterPanelState extends State<CenterPanel> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final _storage = StorageService();
  List<String> _disabledIds = [];
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadDisabled();
  }

  Future<void> _loadDisabled() async {
    final ids = await _storage.loadDisabledDomains();
    if (mounted) setState(() => _disabledIds = ids);
  }

  List<Domain> _domains(LearningScopeProvider scope) {
    var domains = widget.allDomains
        .where((d) => !_disabledIds.contains(d.id))
        .toList();

    // 路线模式 + 有路线领域 → 按路线顺序过滤
    if (scope.isRouteMode && scope.scopeDomainIds.isNotEmpty) {
      final routeDomainIds = scope.scopeDomainIds;
      domains = domains
          .where((d) => routeDomainIds.contains(d.id))
          .toList();
      domains.sort(
        (a, b) => routeDomainIds.indexOf(a.id).compareTo(routeDomainIds.indexOf(b.id)),
      );
    } else if (scope.isSingleDomain && scope.scopeDomainIds.isNotEmpty) {
      // 单领域模式 → 只显示该领域
      final ids = scope.scopeDomainIds;
      domains = domains.where((d) => ids.contains(d.id)).toList();
    }

    return domains;
  }

  List<Domain> _allEnabledDomains() {
    return widget.allDomains.where((d) => !_disabledIds.contains(d.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final scope = context.watch<LearningScopeProvider>();
    final route = scope.activeRoute;
    final domains = _domains(scope);
    final allEnabledDomains = _allEnabledDomains();

    // 路线模式有阶段时，确保路线所涉及的领域 topics 已加载（避免 PhaseCard 显示"知识点"占位）
    // 不仅检查 domain 的 topic 计数，还检查阶段引用的具体 topic ID 是否已加载
    if (scope.isRouteMode && route != null && route.phases != null && route.phases!.isNotEmpty) {
      final allTopics = widget.contentProvider.topics;
      final routeDomainIds = route.domainIds;
      final missingDomainIds = <String>{};
      for (final domainId in routeDomainIds) {
        if (widget.contentProvider.getLoadedTopicCount(domainId) == 0) {
          missingDomainIds.add(domainId);
        }
      }
      // 检查阶段引用的 topic ID 是否具体已在 allTopics 中（可能部分加载）
      if (missingDomainIds.length < routeDomainIds.length) {
        for (final phase in route.phases!) {
          for (final tid in phase.topicIds) {
            if (!allTopics.containsKey(tid) && phase.domainId != null) {
              missingDomainIds.add(phase.domainId!);
            }
          }
        }
      }
      if (missingDomainIds.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            for (final did in missingDomainIds) {
              widget.contentProvider.loadDomainTopics(did);
            }
          }
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前学习范围内容（路线/领域列表）
        PanelCard(
          title: route != null ? route.name : l10n.get('current_study_route'),
          icon: Icons.route_outlined,
          trailing: l10n.get('toggle_switch_route'),
          onTrailingTap: () => _showRouteSelector(context),
          child: Column(
            children: [
              if (domains.isEmpty)
                EmptyState(message: l10n.get('temporary_no_study_route'))
              else if (scope.isRouteMode &&
                  route != null &&
                  route.phases != null &&
                  route.phases!.isNotEmpty)
                _buildPhaseView(route, l10n)
              else
                ...domains.asMap().entries.map((entry) {
                  final index = entry.key;
                  final domain = entry.value;
                  final dp = widget.progressProvider.getDomainProgress(
                    domain.id,
                    widget.contentProvider.topics.values.toList(),
                  );
                  return LearningPathItem(
                    domain: domain,
                    index: index,
                    masteryPercent: dp.masteryPercent,
                    isSelected: domain.id == widget.currentDomainId,
                    onTap: () {
                      widget.onDomainChanged(domain.id);
                      if (widget.contentProvider.getLoadedTopicCount(domain.id) == 0) {
                        widget.contentProvider.loadDomainTopics(domain.id);
                      }
                    },
                    onViewCatalog: () {
                      widget.onDomainChanged(domain.id);
                      if (widget.contentProvider.getLoadedTopicCount(domain.id) == 0) {
                        widget.contentProvider.loadDomainTopics(domain.id);
                      }
                      widget.onViewDomainCatalog(domain.id);
                    },
                  );
                }),
            ],
          ),
        ),
        // AI 路线生成/管理按钮（仅路线模式显示）
        if (scope.isRouteMode && (widget.onGenerateAiRoute != null || widget.onRegenerateAiRoute != null))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                if (_isGenerating)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.get('generating_route'), style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  )
                else if (route?.source == 'ai' && widget.onRegenerateAiRoute != null) ...[
                  OutlinedButton.icon(
                    onPressed: _onGeneratePressed,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(l10n.get('regenerate_ai_route')),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _editSelectedAiRoute(context),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(l10n.get('edit_route')),
                  ),
                ] else if (widget.progressProvider.prepPlan.hasTarget && widget.onGenerateAiRoute != null) ...[                  FilledButton.tonalIcon(
                    onPressed: _onGeneratePressed,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(l10n.get('generate_ai_route')),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        // 领域知识卡片
        PanelCard(
          title: l10n.get('domain_knowledge_card'),
          icon: Icons.school_outlined,
          trailing: l10n.get('management_domain'),
          onTrailingTap: () => _showManageDomains(context),
          child: Column(
            children: [
              if (allEnabledDomains.isEmpty)
                EmptyState(message: l10n.get('temporary_no_domain_data'))
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 根据宽度决定每行几个卡片
                    final cardWidth = constraints.maxWidth > 900
                        ? (constraints.maxWidth - 36) /
                               4 // 一行4个
                        : constraints.maxWidth > 600
                        ? (constraints.maxWidth - 24) /
                               3 // 一行3个
                        : (constraints.maxWidth - 12) / 2; // 一行2个

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: allEnabledDomains.map((domain) {
                        final dp = widget.progressProvider.getDomainProgress(
                          domain.id,
                          widget.contentProvider.topics.values.toList(),
                        );
                        final practiceCount = widget.progressProvider
                            .getDomainPracticeCount(
                              domain.id,
                              widget.contentProvider.topics.values.toList(),
                            );
                        return SizedBox(
                          width: cardWidth,
                          child: DomainKnowledgeCard(
                            domain: domain,
                            masteryPercent: dp.masteryPercent,
                            practiceCount: practiceCount,
                            onTap: () {
                              widget.onDomainChanged(domain.id);
                              if (widget.contentProvider.getLoadedTopicCount(
                                    domain.id,
                                  ) ==
                                  0) {
                                widget.contentProvider.loadDomainTopics(
                                  domain.id,
                                );
                              }
                              widget.onViewDomainCatalog(domain.id);
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseView(LearningRoute route, LocalizationProvider l10n) {
    final allTopics = widget.contentProvider.topics;
    final progress = widget.progressProvider;
    final topicIds = route.allTopicIds;

    int totalMastered = 0;
    for (final tid in topicIds) {
      final t = allTopics[tid];
      if (t != null && (progress.getTopicProgress(tid)?.score ?? 0) >= 85) {
        totalMastered++;
      }
    }

    final phases = route.phases!;
    final phaseWidgets = _buildPhaseCards(route, allTopics, progress, l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 路线总进度
        Row(
          children: [
            Text(
              '$totalMastered/${topicIds.length}',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: topicIds.isNotEmpty
                    ? (totalMastered * 100 ~/ topicIds.length >= 85
                        ? AppColors.success
                        : totalMastered * 100 ~/ topicIds.length >= 50
                            ? AppColors.warning
                            : AppColors.textTertiary)
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: topicIds.isNotEmpty ? totalMastered / topicIds.length : 0,
                      minHeight: 8,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.getp('count_knowledge_point_2', {'count': topicIds.length})} ${l10n.get('route_info_separator')} ${phases.length} ${l10n.get('phases_suffix')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (route.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            route.description,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 12),
        // 阶段卡片列表（最多展示 6 个，其余折叠）
        ...phaseWidgets.take(6),
        if (phases.length > 6)
          Text(
            '${l10n.get('and_more')} ${phases.length - 6} ${l10n.get('phases_suffix')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  List<Widget> _buildPhaseCards(
    LearningRoute route,
    Map<String, Topic> allTopics,
    ProgressProvider progress,
    LocalizationProvider l10n,
  ) {
    final phases = route.phases ?? [];
    final byDomain = <String, List<RoutePhase>>{};
    for (final p in phases) {
      final firstTopic = p.topicIds.isNotEmpty ? allTopics[p.topicIds.first] : null;
      final did = p.domainId ??
          (firstTopic?.domainId ?? route.domainIds.firstOrNull ?? '');
      byDomain.putIfAbsent(did, () => []).add(p);
    }

    final domainOrder = route.domainIds;
    final sortedEntries = byDomain.entries.toList();
    sortedEntries.sort((a, b) {
      final ia = domainOrder.indexOf(a.key);
      final ib = domainOrder.indexOf(b.key);
      final oa = ia == -1 ? domainOrder.length : ia;
      final ob = ib == -1 ? domainOrder.length : ib;
      return oa.compareTo(ob);
    });

    return sortedEntries.expand((e) {
      final domain = widget.allDomains.cast<Domain?>().firstWhere(
        (d) => d?.id == e.key,
        orElse: () => null,
      );
      final domainTitle = domain?.title ?? e.key;
      final domainColor = domain?.color ?? AppColors.accent;
      return [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: domainColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                domainTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(
                        color: domainColor,
                        fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        ...e.value.map((p) {
          final pids = p.topicIds.toSet().toList();
          final ptitles = <String, String>{};
          var mastered = 0;
          var practiced = 0;
          for (final id in pids) {
            final t = allTopics[id];
            if (t != null) ptitles[id] = t.title;
            final s = progress.getTopicProgress(id)?.score ?? 0;
            if (s >= 85) mastered++;
            if (s > 0) practiced++;
          }
          final allDone = mastered == pids.length && pids.isNotEmpty;
          final inProgress = practiced > 0 && !allDone;
          return PhaseCard(
            name: p.focus.isNotEmpty ? p.focus : '$domainTitle ${l10n.get('phases_suffix')} ${e.value.indexOf(p) + 1}',
            totalTopics: pids.length,
            masteredTopics: mastered,
            statusText: allDone
                ? l10n.get('skilled_training')
                : (inProgress ? l10n.get('progress_action_in') : l10n.get('un_start')),
            statusColor: allDone
                ? AppColors.success
                : (inProgress ? AppColors.warning : AppColors.textTertiary),
            statusIcon: allDone
                ? Icons.check_circle
                : (inProgress ? Icons.trending_up : Icons.radio_button_unchecked),
            isCurrent: inProgress,
            topicIds: pids,
            topicTitles: ptitles,
            onTap: pids.isNotEmpty
                ? () => widget.onTopicTap(pids.first)
                : null,
            onTopicTap: (id) {
              if (id != null) widget.onTopicTap(id);
            },
            onPractice: inProgress
                ? () {
                    final firstTopic = pids.isNotEmpty ? allTopics[pids.first] : null;
                    widget.onDomainChanged(
                      firstTopic?.domainId ?? route.domainIds.firstOrNull ?? '',
                    );
                    widget.onPractice();
                  }
                : null,
          );
        }),
      ];
    }).toList();
  }

  Future<void> _showRouteSelector(BuildContext context) async {
    ScopeSelectorDialog.show(context, onGenerateAiRoute: widget.onGenerateAiRoute);
  }

  void _showManageDomains(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => ManageDomainsDialog(
        domains: widget.allDomains,
        disabledDomainIds: _disabledIds.toSet(),
        onToggleDomain: (domainId) async {
          setState(() {
            if (_disabledIds.contains(domainId)) {
              _disabledIds.remove(domainId);
            } else {
              _disabledIds.add(domainId);
            }
          });
          await _storage.saveDisabledDomains(_disabledIds);
        },
      ),
    );
  }

  Future<void> Function()? get _generateRouteAsync {
    // 优先用 regenerate，否则用 generate
    if (widget.onRegenerateAiRoute != null) return () async => widget.onRegenerateAiRoute!.call();
    if (widget.onGenerateAiRoute != null) return () async => widget.onGenerateAiRoute!.call();
    return null;
  }

  void _onGeneratePressed() {
    final generator = _generateRouteAsync;
    if (generator == null || _isGenerating) return;
    setState(() => _isGenerating = true);
    generator().whenComplete(() {
      if (mounted) setState(() => _isGenerating = false);
    });
  }

  void _editSelectedAiRoute(BuildContext context) async {
    final scope = context.read<LearningScopeProvider>();
    final route = scope.activeRoute;
    if (route == null) return;

    final allRouteNames = scope.customRoutes.map((r) => r.name).toList();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => RouteEditorDialog(
        availableDomains: widget.allDomains
            .map((d) => DomainItem(id: d.id, title: d.title))
            .toList(),
        existingRoute: route,
        existingRouteNames: allRouteNames,
        onSave: (updatedRoute) async {
          await scope.upsertRoute(updatedRoute, activate: true, contentProvider: widget.contentProvider);
        },
      ),
    );
  }
}

// ── 右侧面板 ──

class RightPanel extends StatelessWidget {
  const RightPanel({
    super.key,
    required this.currentDomainId,
    required this.domains,
    required this.masteryPercent,
    required this.readiness,
    required this.weakTopics,
    required this.recentAttempts,
    required this.onTopicTap,
    required this.onDomainChanged,
    required this.progressProvider,
    required this.scopedTopics,
    this.isRouteMode = false,
  });

  final String currentDomainId;
  final List<Domain> domains;
  final int masteryPercent;
  final int readiness;
  final List<Topic> weakTopics;
  final List<PracticeAttempt> recentAttempts;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onDomainChanged;
  final ProgressProvider progressProvider;
  final List<Topic> scopedTopics;
  final bool isRouteMode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();

    final categoryMap = <String, List<Topic>>{};
    for (final topic in scopedTopics) {
      categoryMap.putIfAbsent(topic.category, () => []).add(topic);
    }

    final categories = categoryMap.entries.map((entry) {
      final topics = entry.value;
      int totalScore = 0;
      int learnedCount = 0;
      for (final t in topics) {
        final score = progressProvider.getTopicProgress(t.id)?.score ?? 0;
        if (score > 0) {
          totalScore += score;
          learnedCount++;
        }
      }
      final avgScore = learnedCount == 0 ? 0 : (totalScore / learnedCount).round();
      return CategoryMastery(name: entry.key, masteryPercent: avgScore);
    }).toList()..sort((a, b) => b.masteryPercent.compareTo(a.masteryPercent));

    // 计算掌握程度百分比
    int totalTopics = scopedTopics.length;
    int masteredCount = 0;
    int learningCount = 0;
    int newCount = 0;

    for (final topic in scopedTopics) {
      final score = progressProvider.getTopicProgress(topic.id)?.score ?? 0;
      if (score >= 85) {
        masteredCount++;
      } else if (score >= 60) {
        learningCount++;
      } else {
        newCount++;
      }
    }

    final masteredPercent = totalTopics == 0
        ? 0
        : (masteredCount * 100 ~/ totalTopics);
    final learningPercent = totalTopics == 0
        ? 0
        : (learningCount * 100 ~/ totalTopics);
    final newPercent = totalTopics == 0 ? 0 : (newCount * 100 ~/ totalTopics);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelCard(
          title: l10n.get('mastery_overview_browse'),
          icon: Icons.pie_chart_outline,
          headerTrailing: isRouteMode
              ? null
              : DomainDropdown(
                  currentDomainId: currentDomainId,
                  domains: domains,
                  onChanged: onDomainChanged,
                ),
          child: Column(
            children: [
              MasteryOverview(
                masteryPercent: masteryPercent,
                masteredPercent: masteredPercent,
                learningPercent: learningPercent,
                newPercent: newPercent,
              ),
              const SizedBox(height: 16),
              MasteryStats(categories: categories.take(4).toList()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PanelCard(
          title: l10n.get('next_step_best_action'),
          icon: Icons.lightbulb_outline,
          child: NextBestAction(
            weakTopics: weakTopics,
            onTopicTap: onTopicTap,
          ),
        ),
      ],
    );
  }

  }
