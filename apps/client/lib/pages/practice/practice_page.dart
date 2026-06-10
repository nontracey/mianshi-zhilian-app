import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/practice/follow_up_training_page.dart';
import 'package:mianshi_zhilian/pages/practice/weakness_training_page.dart';
import 'package:mianshi_zhilian/pages/practice/system_design_page.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/pages/practice/practice_widgets.dart';
import 'package:mianshi_zhilian/pages/practice/high_frequency_sprint_page.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/widgets/skeleton_loader.dart';

class PracticePage extends StatelessWidget {
  const PracticePage({
    super.key,
    required this.onDailyReview,
    required this.onRandomQuiz,
    required this.onMockInterview,
  });

  final VoidCallback onDailyReview;
  final ValueChanged<String> onRandomQuiz;
  final VoidCallback onMockInterview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progressProvider = context.watch<ProgressProvider>();
    final contentProvider = context.watch<ContentProvider>();
    final scope = context.watch<LearningScopeProvider>();
    final settings = context.watch<SettingsProvider>();
    final domains = contentProvider.domains;
    // 使用统一范围解析：路线模式下跨域获取 topic，修复了原先只取当前域的 Bug
    final scopedTopics = scope.resolveScopedTopics(contentProvider);
    // 复习计数按范围内 topics 计算（修复原先仅按单域统计的 Bug）
    final reviewCount = scope.isRouteMode
        ? progressProvider.getTodayReviewTopics(scopedTopics).length
        : progressProvider.getReviewCount(settings.settings.currentDomain);

    // 还没有加载到任何知识点时显示骨架
    if (scopedTopics.isEmpty && contentProvider.isLoadingTopics) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            SkeletonCard(height: 100),
            const SizedBox(height: 16),
            ...List.generate(4, (_) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SkeletonTopicRow(),
            )),
          ],
        ),
      );
    }

    if (scopedTopics.isEmpty) {
      final currentDomainId = settings.settings.currentDomain;
      return EmptyPracticeState(
        onRetry: () => contentProvider.loadDomainTopics(currentDomainId),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (scope.isRouteMode && scopedTopics.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.route, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.getp('knowledge_points_in_route', {'count': scopedTopics.length}),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          l10n.get('select_practice_mode'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
LayoutBuilder(
 builder: (context, constraints) {
            final cardWidth = constraints.maxWidth > 900
                ? (constraints.maxWidth - 32) / 3
                : constraints.maxWidth > 500
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.get('practice_core'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: PracticeModeCard(
                        icon: Icons.today_outlined,
                        title: l10n.get('today_day_review'),
                        subtitle: l10n.getp(
                          'based_on_forgetting_curve_today_day_has_count_knowledg_2',
                          {'count': reviewCount},
                        ),
                        color: AppColors.accent,
                        onTap: onDailyReview,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: PracticeModeCard(
                        icon: Icons.casino_outlined,
                        title: l10n.get('random_machine_question'),
                        subtitle: l10n.get(
                          'select_domain_after_random_machine_fetch_knowledge_point_progress',
                        ),
                        color: AppColors.success,
                        onTap: () => _showDomainPicker(context, domains),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: PracticeModeCard(
                        icon: Icons.groups_outlined,
                        title: l10n.get('mode_mock_interview'),
                        subtitle: l10n.get(
                          'streak_multi_question_count_mode_mock_real_actual_int',
                        ),
                        color: AppColors.categoryRed,
                        onTap: onMockInterview,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // U-6：进阶模式默认折叠，首屏只突出 3 个核心模式，降低新用户决策成本。
                // PageStorageKey 保证展开态在列表重建后不丢失。
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: const PageStorageKey('practice_advanced_section'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 4, bottom: 4),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    initiallyExpanded: false,
                    leading: Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                    title: Text(
                      l10n.get('practice_advanced'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      l10n.get('practice_advanced_hint'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: cardWidth,
                            child: PracticeModeCard(
                              icon: Icons.question_answer_outlined,
                              title: l10n.get('follow_up_training'),
                              subtitle: l10n.get(
                                'mode_mock_interview_official_follow_up_deep_enter_practice_knowle',
                              ),
                              color: AppColors.categoryPurple,
                              onTap: () =>
                                  _startFollowUpTraining(context, scopedTopics),
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: PracticeModeCard(
                              icon: Icons.trending_down_outlined,
                              title: l10n.get('weakness_training_pack'),
                              subtitle: l10n.get(
                                'needle_peer_weak_knowledge_point_progress_action_specialized_item_training',
                              ),
                              color: AppColors.danger,
                              onTap: () => _startWeaknessTraining(context),
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: PracticeModeCard(
                              icon: Icons.local_fire_department_outlined,
                              title: l10n.get('high_freq_sprint'),
                              subtitle: l10n.get(
                                'needle_peer_high_freq_interview_question_count_progress_action_accent',
                              ),
                              color: AppColors.warning,
                              onTap: () => _startHighFrequencyTraining(
                                  context, scopedTopics),
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: PracticeModeCard(
                              icon: Icons.architecture_outlined,
                              title: l10n.get('system_design'),
                              subtitle:
                                  l10n.get('system_design_interview_practice'),
                              color: AppColors.categoryAmber,
                              onTap: () => _startSystemDesign(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showDomainPicker(BuildContext context, List domains) {
    final l10n = context.read<LocalizationProvider>();
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.get('select_domain')),
        children: domains
            .map<SimpleDialogOption>(
              (domain) => SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(ctx, domain.id);
                  onRandomQuiz(domain.id);
                },
                child: Text(domain.title),
              ),
            )
            .toList(),
      ),
    );
  }

  void _startFollowUpTraining(BuildContext context, List domainTopics) {
    // 筛选有追问的知识点（入参已经是 scope 解析后的 topics）
    final topicsWithFollowUps = domainTopics
        .where((topic) => topic.followUps.isNotEmpty)
        .toList();

    if (topicsWithFollowUps.isEmpty) {
      final l10n = context.read<LocalizationProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.get(
              'current_domain_not_has_optional_follow_up_knowledge_point',
            ),
          ),
        ),
      );
      return;
    }

    // 随机选择最多5个知识点
    final shuffled = List.from(topicsWithFollowUps)..shuffle();
    final selectedTopics = shuffled.take(5).toList();
    final topicIds = selectedTopics.map((t) => t.id as String).toList();

    context.push(
      '/practice/follow-up-training',
      extra: FollowUpTrainingPage(topicIds: topicIds),
    );
  }

  void _startWeaknessTraining(BuildContext context) {
    context.push(
      '/practice/weakness-training',
      extra: const WeaknessTrainingPage(),
    );
  }

  void _startHighFrequencyTraining(BuildContext context, List domainTopics) {
    // 筛选高频知识点（入参已经是 scope 解析后的 topics）
    final highFrequencyTopics = domainTopics
        .where((topic) => topic.highFrequency)
        .toList();

    if (highFrequencyTopics.isEmpty) {
      final l10n = context.read<LocalizationProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.get('current_domain_not_has_high_freq_knowledge_point'),
          ),
        ),
      );
      return;
    }

    context.push(
      '/practice/high-frequency',
      extra: HighFrequencySprintPage(topics: highFrequencyTopics.cast<Topic>()),
    );
  }

  void _startSystemDesign(BuildContext context) {
    context.push('/practice/system-design', extra: const SystemDesignPage());
  }
}

