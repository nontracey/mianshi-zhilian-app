import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/pages/learning/topic_detail_page.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/pages/practice/project_dig_page.dart';
import 'package:mianshi_zhilian/pages/practice/mock_interview_page.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/ai_route_generator.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/pages/learning/dashboard_widgets.dart';

class InterviewPrepPage extends StatelessWidget {
  const InterviewPrepPage({
    super.key,
    required this.currentDomainId,
    required this.onStartPractice,
    required this.onStartMock,
    this.routeTopicIds,
    this.routeModeEnabled = false,
    this.onRouteModeChanged,
  });

  final String currentDomainId;
  final VoidCallback onStartPractice;
  final VoidCallback onStartMock;
  final List<String>? routeTopicIds;
  final bool routeModeEnabled;
  final VoidCallback? onRouteModeChanged;

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentProvider>();
    final progress = context.watch<ProgressProvider>();
    final topics = content.getTopicsByDomain(currentDomainId);
    final plan = progress.prepPlan;
    final readiness = progress.readinessScore(topics);
    final reviewCount = progress.getTodayReviewTopics(topics).length;
    final lowScoreCount = progress.lowScoreAttempts.length;
    final highFrequencyUnmastered = topics.where((topic) {
      final topicProgress = progress.getTopicProgress(topic.id);
      return topic.highFrequency && (topicProgress?.score ?? 0) < 85;
    }).length;
    final domainProgress = progress.getDomainProgress(currentDomainId, topics);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: '工作台'),
              Tab(text: '路线'),
              Tab(text: '模拟面试'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildDashboardTab(
                  context,
                  plan: plan,
                  readiness: readiness,
                  reviewCount: reviewCount,
                  highFrequencyUnmastered: highFrequencyUnmastered,
                  lowScoreCount: lowScoreCount,
                  topics: topics,
                  progress: progress,
                  content: content,
                  domainProgress: domainProgress,
                ),
                _buildRouteTab(context, progress: progress),
                _buildMockTab(context, progress: progress, topics: topics),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(
    BuildContext context, {
    required PrepPlan plan,
    required int readiness,
    required int reviewCount,
    required int highFrequencyUnmastered,
    required int lowScoreCount,
    required List<Topic> topics,
    required ProgressProvider progress,
    required ContentProvider content,
    required ({int masteryPercent, int topicCount}) domainProgress,
  }) {
    final l10n = context.watch<LocalizationProvider>();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        WorkPanel(
          title: plan.hasTarget
              ? l10n.getp('interview_preparation_role_2', {
                  'role': plan.targetRole,
                })
              : l10n.get('open_use_tech_interview_preparation'),
          trailing: FilledButton.tonalIcon(
            onPressed: () => _showPlanDialog(context, progress, plan, l10n),
            icon: const Icon(Icons.tune_outlined),
            label: Text(
              plan.hasTarget
                  ? l10n.get('schedule_overall_goal')
                  : l10n.get('settings_goal'),
            ),
          ),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final cards = [
                  _PrepMetric(
                    label: l10n.get('interview_readiness'),
                    value: '$readiness',
                    suffix: '/100',
                    color: _scoreColor(readiness),
                  ),
                  _PrepMetric(
                    label: l10n.get('today_day_pending_review'),
                    value: '$reviewCount',
                    suffix: l10n.get('item'),
                    color: AppColors.warning,
                  ),
                  _PrepMetric(
                    label: l10n.get('high_freq_unstable'),
                    value: '$highFrequencyUnmastered',
                    suffix: l10n.get('item'),
                    color: AppColors.accent,
                  ),
                  _PrepMetric(
                    label: l10n.get('low_score_back_flow'),
                    value: '$lowScoreCount',
                    suffix: l10n.get('round'),
                    color: AppColors.danger,
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map(
                        (card) => SizedBox(
                          width: compact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 36) / 4,
                          child: card,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              plan.hasTarget
                  ? _targetDescription(context, plan)
                  : l10n.get(
                      'un_settings_goal_position_also_optional_by_direct_connect_use',
                    ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onStartPractice,
                  icon: const Icon(Icons.today_outlined),
                  label: Text(l10n.get('start_today_day_practice')),
                ),
                OutlinedButton.icon(
                  onPressed: onStartMock,
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: Text(l10n.get('come_one_round_mode_mock_interview')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildCompactProgress(context, domainProgress),
        const SizedBox(height: 16),
        if (plan.jobDescription.trim().isNotEmpty) ...[
          _JdAnalysisSection(
            jobDescription: plan.jobDescription,
            topics: topics,
            progress: progress,
          ),
          const SizedBox(height: 16),
        ],
        _buildProjectDigButton(context, progress, topics),
        const SizedBox(height: 16),
        WorkPanel(
          title: l10n.get('next_step_suggestion'),
          children: _buildActions(
            context,
            readiness: readiness,
            reviewCount: reviewCount,
            highFrequencyUnmastered: highFrequencyUnmastered,
            hasTarget: plan.hasTarget,
          ),
        ),
        const SizedBox(height: 16),
        WorkPanel(
          title: l10n.get('privacy_and_degrade'),
          children: [
            InfoLine(
              icon: Icons.lock_outline,
              text: l10n.get(
                'goal_position_jd_project_element_material_and_answer_draft_def',
              ),
            ),
            InfoLine(
              icon: Icons.person_outline,
              text: l10n.get(
                'not_login_also_enable_complete_overall_practice_only_use_in',
              ),
            ),
            InfoLine(
              icon: Icons.hub_outlined,
              text: l10n.get('ai_not_configured_practice_falls_back_to_local'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactProgress(
    BuildContext context,
    ({int masteryPercent, int topicCount}) domainProgress,
  ) {
    final l10n = context.watch<LocalizationProvider>();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.get('schedule_overall_goal'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: domainProgress.masteryPercent / 100,
                    minHeight: 8,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${domainProgress.masteryPercent}%',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _scoreColor(domainProgress.masteryPercent),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${domainProgress.topicCount} ${l10n.get('item')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteTab(
    BuildContext context, {
    required ProgressProvider progress,
  }) {
    final content = context.watch<ContentProvider>();
    return _RouteTabContent(
      progress: progress,
      content: content,
    );
  }

  Widget _buildMockTab(
    BuildContext context, {
    required ProgressProvider progress,
    required List<Topic> topics,
  }) {
    return _MockTabContent(
      progress: progress,
      topics: topics,
      routeTopicIds: routeTopicIds,
      routeModeEnabled: routeModeEnabled,
    );
  }

  Widget _buildProjectDigButton(
    BuildContext context,
    ProgressProvider progress,
    List<Topic> topics,
  ) {
    final l10n = context.watch<LocalizationProvider>();
    final plan = progress.prepPlan;
    final keywords =
        plan.jobDescription.trim().isNotEmpty
            ? _extractTechKeywords(plan.jobDescription, topics)
            : <String>[];

    return WorkPanel(
      title: '项目深挖',
      children: [
        InfoLine(
          icon: Icons.work_outline,
          text: '使用 STAR 法则梳理项目经验，准备深挖追问',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (_) => ProjectDigPage(
                      initialTechStack: keywords,
                    ),
                  ),
                )
                .then((result) {
                  if (result != null && result is Map<String, dynamic>) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${l10n.get('save_success')}: ${result['name']}',
                        ),
                      ),
                    );
                  }
                });
          },
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(l10n.get('start_project_dig')),
        ),
        if (keywords.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l10n.getp('jd_keywords_prefill', {'count': keywords.length}),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  static List<String> _extractTechKeywords(String jd, List<Topic> topics) {
    final jdLower = jd.toLowerCase();
    final result = <String>{};
    for (final topic in topics) {
      for (final tag in topic.tags) {
        if (tag.isNotEmpty && jdLower.contains(tag.toLowerCase())) {
          result.add(tag);
        }
      }
      if (topic.category.isNotEmpty &&
          jdLower.contains(topic.category.toLowerCase())) {
        result.add(topic.category);
      }
    }
    return result.toList()..sort();
  }

  List<Widget> _buildActions(
    BuildContext context, {
    required int readiness,
    required int reviewCount,
    required int highFrequencyUnmastered,
    required bool hasTarget,
  }) {
    final l10n = context.watch<LocalizationProvider>();
    final actions = <Widget>[];
    if (reviewCount > 0) {
      actions.add(
        InfoLine(
          icon: Icons.replay_outlined,
          text: l10n.get('clear_today_review_first_avoid_overflow'),
        ),
      );
    }
    if (highFrequencyUnmastered > 0) {
      actions.add(
        InfoLine(
          icon: Icons.local_fire_department_outlined,
          text: l10n.get(
            'priority_sprint_high_freq_unstable_knowledge_point_suitable_combine',
          ),
        ),
      );
    }
    if (readiness < 70) {
      actions.add(
        InfoLine(
          icon: Icons.construction_outlined,
          text: l10n.get(
            'readiness_bias_low_suggestion_first_score_back_flow_again',
          ),
        ),
      );
    } else {
      actions.add(
        InfoLine(
          icon: Icons.groups_outlined,
          text: l10n.get(
            'optional_by_progress_enter_correct_mode_mock_end_after_7',
          ),
        ),
      );
    }
    if (!hasTarget) {
      actions.add(
        InfoLine(
          icon: Icons.flag_outlined,
          text: l10n.get(
            'settings_goal_position_or_paste_jd_after_optional_gain_get_66f',
          ),
        ),
      );
    }
    return actions;
  }

  String _targetDescription(BuildContext context, PrepPlan plan) {
    final l10n = context.watch<LocalizationProvider>();
    final parts = <String>[];
    if (plan.techStack.isNotEmpty) {
      parts.add(
        l10n.getp('tech_stack_techstack_2', {'techStack': plan.techStack}),
      );
    }
    if (plan.dailyMinutes > 0) {
      parts.add(
        l10n.getp('daily_minutes_min_2', {'minutes': plan.dailyMinutes}),
      );
    }
    if (plan.interviewDate != null) {
      final days = plan.interviewDate!.difference(DateTime.now()).inDays + 1;
      parts.add(
        days > 0
            ? l10n.getp('distance_offline_interview_still_has_days_day_2', {
                'days': days,
              })
            : l10n.get('interview_day_already_to'),
      );
    }
    return parts.isEmpty
        ? l10n.get(
            'goal_already_settings_app_will_increase_accent_recommend_rights_restart',
          )
        : parts.join(' · ');
  }

  Color _scoreColor(int score) {
    if (score >= 85) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  void _showPlanDialog(
    BuildContext context,
    ProgressProvider progress,
    PrepPlan current,
    LocalizationProvider l10n,
  ) {
    final roleController = TextEditingController(text: current.targetRole);
    final stackController = TextEditingController(text: current.techStack);
    final jdController = TextEditingController(text: current.jobDescription);
    var dailyMinutes = current.dailyMinutes;
    DateTime? interviewDate = current.interviewDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.get('interview_goal')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: roleController,
                    decoration: InputDecoration(
                      labelText: l10n.get('goal_position_optional_select'),
                      hintText: l10n.get(
                        'java_backend_ai_engineering_transform_architect',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stackController,
                    decoration: InputDecoration(
                      labelText: l10n.get('tech_stack_optional_select'),
                      hintText: 'Spring Cloud, Redis, RAG...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.getp('daily_send_enter_minutes_min_2', {
                            'minutes': dailyMinutes,
                          }),
                        ),
                      ),
                      IconButton(
                        onPressed: dailyMinutes > 15
                            ? () => setDialogState(() => dailyMinutes -= 15)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        onPressed: () =>
                            setDialogState(() => dailyMinutes += 15),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate:
                            interviewDate ??
                            DateTime.now().add(const Duration(days: 14)),
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => interviewDate = picked);
                      }
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      interviewDate == null
                          ? l10n.get('select_interview_day_optional')
                          : l10n.getp('interview_day_year_month_day', {
                              'year': interviewDate!.year,
                              'month': interviewDate!.month,
                              'day': interviewDate!.day,
                            }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: jdController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: l10n.get(
                        'position_description_jd_optional_select_local_save',
                      ),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                progress.updatePrepPlan(
                  PrepPlan(
                    targetRole: roleController.text.trim(),
                    techStack: stackController.text.trim(),
                    interviewDate: interviewDate,
                    dailyMinutes: dailyMinutes,
                    jobDescription: jdController.text.trim(),
                    updatedAt: DateTime.now(),
                  ),
                );
                Navigator.pop(ctx);
              },
              child: Text(l10n.get('save')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteTabContent extends StatefulWidget {
  final ProgressProvider progress;
  final ContentProvider content;

  const _RouteTabContent({
    required this.progress,
    required this.content,
  });

  @override
  State<_RouteTabContent> createState() => _RouteTabContentState();
}

class _RouteTabContentState extends State<_RouteTabContent> {
  final _storage = StorageService();
  LearningRoute? _selectedRoute;
  bool _isLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadSelectedRoute();
  }

  Future<void> _loadSelectedRoute() async {
    final routeId = await _storage.load('selected_route_id');
    if (routeId != null) {
      final customData = await _storage.loadJsonList('custom_routes');
      final route = customData
          .map((e) => LearningRoute.fromJson(e))
          .firstWhereOrNull((r) => r.id == routeId);
      if (route != null && mounted) {
        setState(() {
          _selectedRoute = route;
          _isLoading = false;
        });
        return;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _generateAiRoute() async {
    final plan = widget.progress.prepPlan;
    final l10n = context.read<LocalizationProvider>();
    final aiProvider = context.read<AiProvider>();
    final allDomains = widget.content.domains;
    final generator = AiRouteGenerator(_storage, allDomains);
    setState(() => _isGenerating = true);
    try {
      final route = await generator.generateRoute(
        plan: plan,
        allTopics: widget.content.topics.values.toList(),
        progressProvider: widget.progress,
        aiService: aiProvider.aiService,
        contentProvider: widget.content,
        forceRegenerate: true,
      );

      final customData = await _storage.loadJsonList('custom_routes');
      // 移除旧 AI 路线，防止积压
      customData.removeWhere((e) => e['source'] == 'ai');
      customData.add(route.toJson());
      await _storage.saveJsonList('custom_routes', customData);
      await _storage.save('selected_route_id', route.id);

      if (mounted) setState(() => _selectedRoute = route);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.getp('route_gen_fail', {'error': '$e'}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// 根据面试目标筛选相关领域，避免全量加载
  Color _scoreColor(int score) {
    if (score >= 85) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    if (_isLoading || _isGenerating) return const Center(child: CircularProgressIndicator());
    if (_selectedRoute == null) return _buildNoRouteView(context, l10n);
    return _buildRouteView(context, l10n);
  }

  Widget _buildNoRouteView(BuildContext context, LocalizationProvider l10n) {
    final plan = widget.progress.prepPlan;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        WorkPanel(
          title: plan.hasTarget ? '暂无路线' : '请先设置面试目标',
          children: [
            const SizedBox(height: 8),
            Icon(
              plan.hasTarget ? Icons.route : Icons.flag_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              plan.hasTarget
                  ? '暂未生成学习路线，点击下方按钮生成 AI 个性化路线'
                  : '请先在"工作台"中设置面试目标，然后可以生成个性化学习路线',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (plan.hasTarget)
              FilledButton.icon(
                onPressed: _generateAiRoute,
                icon: const Icon(Icons.auto_awesome),
                label: Text(l10n.get('ai_route_gen')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteView(BuildContext context, LocalizationProvider l10n) {
    final route = _selectedRoute!;
    final phases = route.phases ?? [];
    final allTopics = widget.content.topics;

    int totalMastered = 0;
    int totalTopics = 0;
    for (final phase in phases) {
      for (final topicId in phase.topicIds) {
        totalTopics++;
        final topic = allTopics[topicId];
        if (topic != null) {
          final score = widget.progress.getTopicProgress(topic.id)?.score ?? 0;
          if (score >= 85) totalMastered++;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        WorkPanel(
          title: route.name,
          trailing: Text(
            l10n.getp('phases_count', {'count': phases.length}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          children: [
            Row(
              children: [
                Text(
                  '$totalMastered/$totalTopics',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: _scoreColor(
                      totalTopics > 0 ? (totalMastered * 100 ~/ totalTopics) : 0,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: totalTopics > 0 ? totalMastered / totalTopics : 0,
                          minHeight: 10,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$totalTopics ${l10n.get('item')}',
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
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (phases.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                l10n.get('route_no_phases'),
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          )
        else ...[
          Text(
            l10n.get('learning_phase'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          // 按领域分组展示路线阶段
          ..._groupPhasesByDomain(context, route, widget.content, widget.progress, allTopics, l10n),
        ],
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: _generateAiRoute,
            icon: const Icon(Icons.auto_awesome),
            label: Text(l10n.get('regenerate_route')),
          ),
        ),
      ],
    );
  }

  void _navigateToTopic(BuildContext context, String? topicId) {
    if (topicId == null) return;
    final topic = widget.content.topics[topicId];
    if (topic == null) return;
    context.push('/topic', extra: TopicDetailPage(topic: topic, onBack: () => context.pop()));
  }

  List<Widget> _groupPhasesByDomain(BuildContext ctx, LearningRoute route,
      ContentProvider content, ProgressProvider progress,
      Map<String, Topic> topics, LocalizationProvider l10n) {
    final phases = route.phases ?? [];
    final byDomain = <String, List<RoutePhase>>{};
    for (final p in phases) {
      final did = p.topicIds.isNotEmpty
          ? (topics[p.topicIds.first]?.domainId ?? route.domainIds.firstOrNull ?? '')
          : (route.domainIds.firstOrNull ?? '');
      byDomain.putIfAbsent(did, () => []).add(p);
    }
    return byDomain.entries.expand((e) {
      final domain = content.domains.firstWhereOrNull((d) => d.id == e.key);
      final title = domain?.title ?? e.key;
      return [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(title,
              style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w700)),
        ),
        ...e.value.map((p) {
          final pids = p.topicIds.toSet().toList();
          final ptitles = <String, String>{};
          var mastered = 0; var practiced = 0;
          for (final id in pids) {
            final t = topics[id]; if (t != null) ptitles[id] = t.title;
            final s = progress.getTopicProgress(id)?.score ?? 0;
            if (s >= 85) mastered++;
            if (s > 0) practiced++;
          }
          final allDone = mastered == pids.length && pids.isNotEmpty;
          final inProgress = practiced > 0 && !allDone;
          return PhaseCard(
            name: p.focus.isNotEmpty ? p.focus : '$title 阶段 ${e.value.indexOf(p) + 1}',
            totalTopics: pids.length,
            masteredTopics: mastered,
            statusText: allDone ? l10n.get('skilled_training') : (inProgress ? l10n.get('progress_action_in') : l10n.get('un_start')),
            statusColor: allDone ? AppColors.success : (inProgress ? AppColors.warning : AppColors.textTertiary),
            statusIcon: allDone ? Icons.check_circle : (inProgress ? Icons.trending_up : Icons.radio_button_unchecked),
            isCurrent: inProgress,
            topicIds: pids, topicTitles: ptitles,
            onTap: pids.isNotEmpty ? () => _navigateToTopic(ctx, pids.first) : null,
            onTopicTap: (id) => _navigateToTopic(ctx, id),
          );
        }),
      ];
    }).toList();
  }
}

class _PrepMetric extends StatelessWidget {
  const _PrepMetric({
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
  });

  final String label;
  final String value;
  final String suffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(text: ' $suffix'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _MockTabContent extends StatefulWidget {
  const _MockTabContent({
    required this.progress,
    required this.topics,
    required this.routeTopicIds,
    required this.routeModeEnabled,
  });

  final ProgressProvider progress;
  final List<Topic> topics;
  final List<String>? routeTopicIds;
  final bool routeModeEnabled;

  @override
  State<_MockTabContent> createState() => _MockTabContentState();
}

class _MockTabContentState extends State<_MockTabContent> {
  String _scenario = 'tech';
  int _duration = 15;
  String? _scope;

  @override
  void initState() {
    super.initState();
    _scope = widget.routeModeEnabled && widget.routeTopicIds?.isNotEmpty == true
        ? 'route'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final mockCount = widget.progress.mockSessions.length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        WorkPanel(
          title: '模拟面试',
          children: [
            const SizedBox(height: 8),
            Center(
              child: Icon(
                Icons.record_voice_over_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.get('mock_interview_description'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // 面试场景
            Text(l10n.get('mock_scenario'), style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildScenarioChip('tech', l10n.get('tech_interview'), Icons.psychology_outlined),
                _buildScenarioChip('comprehensive', l10n.get('comprehensive_interview'), Icons.groups_outlined),
                _buildScenarioChip('behavioral', l10n.get('behavioral_interview'), Icons.emoji_people_outlined),
              ],
            ),
            const SizedBox(height: 16),

            // 时长选择
            Text(l10n.get('duration'), style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _buildDurationChip(15, '15 min'),
                _buildDurationChip(30, '30 min'),
              ],
            ),
            const SizedBox(height: 16),

            // 题目范围
            if (widget.routeTopicIds != null && widget.routeTopicIds!.isNotEmpty) ...[
              Text(l10n.get('question_scope'), style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildScopeChip('route', l10n.get('by_current_route')),
                  _buildScopeChip('domain', l10n.get('by_current_domain')),
                  _buildScopeChip('all', l10n.get('all_topics')),
                ],
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                final content = context.read<ContentProvider>();
                List<String> topicIds;
                if (_scope == 'route' &&
                    widget.routeTopicIds != null &&
                    widget.routeTopicIds!.isNotEmpty) {
                  topicIds = List<String>.from(widget.routeTopicIds!)..shuffle();
                } else if (_scope == 'domain') {
                  final domainTopics = content.getTopicsByDomain(
                    context.read<SettingsProvider>().settings.currentDomain,
                  );
                  topicIds = domainTopics.map((t) => t.id).toList()..shuffle();
                } else {
                  topicIds = content.topics.keys.toList()..shuffle();
                }
                context.push(
                  '/practice/mock-interview',
                  extra: MockInterviewPage(topicIds: topicIds.take(_duration).toList()),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.get('start_mock_interview')),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            if (mockCount > 0) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.history),
                label: Text(l10n.getp('view_history_count', {'count': mockCount})),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildScenarioChip(String value, String label, IconData icon) {
    final selected = _scenario == value;
    return ChoiceChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _scenario = value),
    );
  }

  Widget _buildDurationChip(int value, String label) {
    final selected = _duration == value;
    return ChoiceChip(
      avatar: const Icon(Icons.timer_outlined, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _duration = value),
    );
  }

  Widget _buildScopeChip(String value, String label) {
    final selected = _scope == value;
    return ChoiceChip(
      avatar: const Icon(Icons.tune, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _scope = value),
    );
  }
}

class _JdAnalysisSection extends StatelessWidget {
  const _JdAnalysisSection({
    required this.jobDescription,
    required this.topics,
    required this.progress,
  });

  final String jobDescription;
  final List<Topic> topics;
  final ProgressProvider progress;

  List<Topic> _matchTopics(List<String> keywords) {
    if (keywords.isEmpty) return [];
    final matched = <String, Topic>{};
    for (final topic in topics) {
      final searchText =
          '${topic.title} ${topic.summary} '
                  '${topic.category} ${topic.tags.join(' ')} '
                  '${topic.rubric?.mustHave.join(' ') ?? ''}'
              .toLowerCase();
      for (final kw in keywords) {
        if (searchText.contains(kw)) {
          matched[topic.id] = topic;
          break;
        }
      }
    }
    return matched.values.toList();
  }

  static List<String> _extractKeywords(String jd, List<Topic> topics) {
    final jdLower = jd.toLowerCase();
    final result = <String>{};
    for (final topic in topics) {
      for (final tag in topic.tags) {
        if (tag.isNotEmpty && jdLower.contains(tag.toLowerCase())) {
          result.add(tag);
        }
      }
      if (topic.category.isNotEmpty &&
          jdLower.contains(topic.category.toLowerCase())) {
        result.add(topic.category);
      }
    }
    return result.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final keywords = _extractKeywords(jobDescription, topics);
    final matchedTopics = _matchTopics(keywords);

    matchedTopics.sort((a, b) {
      final scoreA = progress.getTopicProgress(a.id)?.score ?? 0;
      final scoreB = progress.getTopicProgress(b.id)?.score ?? 0;
      return scoreA.compareTo(scoreB);
    });

    return WorkPanel(
      title: l10n.get('jd_match_assign_analysis'),
      trailing: Text(
        l10n.getp('count_matches_2', {'count': matchedTopics.length}),
        style: TextStyle(
          fontSize: 12,
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        if (keywords.isEmpty)
          Text(
            l10n.get(
              'un_identify_distinct_to_key_tech_term_please_inspect_check_jd_content',
            ),
          )
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: keywords
                .map(
                  (kw) => Chip(
                    label: Text(kw, style: const TextStyle(fontSize: 11)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          if (matchedTopics.isEmpty)
            Text(
              l10n.get(
                'current_content_library_in_un_find_to_and_jd_match_assign_768',
              ),
            )
          else ...[
            Text(
              l10n.get(
                'suggestion_priority_review_press_mastery_from_low_to_high',
              ),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...matchedTopics.take(10).map((topic) {
              final topicProgress = progress.getTopicProgress(topic.id);
              final score = topicProgress?.score ?? 0;
              final color = score >= 85
                  ? AppColors.success
                  : score >= 60
                  ? AppColors.warning
                  : AppColors.danger;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topic.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            topic.category,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        score > 0 ? '$score' : l10n.get('un_practice'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    );
  }
}
