import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/practice/follow_up_training_page.dart';
import 'package:mianshi_zhilian/pages/practice/weakness_training_page.dart';
import 'package:mianshi_zhilian/pages/practice/recall_page.dart';
import 'package:mianshi_zhilian/pages/practice/project_dig_page.dart';
import 'package:mianshi_zhilian/pages/practice/system_design_page.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

class PracticePage extends StatelessWidget {
  const PracticePage({
    super.key,
    required this.currentDomainId,
    required this.onDailyReview,
    required this.onRandomQuiz,
    required this.onMockInterview,
  });

  final String currentDomainId;
  final VoidCallback onDailyReview;
  final ValueChanged<String> onRandomQuiz;
  final VoidCallback onMockInterview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final reviewCount = progressProvider.getReviewCount(currentDomainId);
    final contentProvider = context.watch<ContentProvider>();
    final domains = contentProvider.domains;
    final domainTopics = contentProvider.getTopicsByDomain(currentDomainId);

    // 还没有加载到任何知识点时显示空状态
    if (domainTopics.isEmpty && contentProvider.isLoadingTopics) {
      final l10n = context.watch<LocalizationProvider>();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              l10n.get('loading_knowledge_point'),
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (domainTopics.isEmpty) {
      return _EmptyPracticeState(
        onRetry: () => contentProvider.loadDomainTopics(currentDomainId),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
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
                : constraints.maxWidth;

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
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
                  child: _PracticeModeCard(
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
                  child: _PracticeModeCard(
                    icon: Icons.question_answer_outlined,
                    title: l10n.get('follow_up_training'),
                    subtitle: l10n.get(
                      'mode_mock_interview_official_follow_up_deep_enter_practice_knowle',
                    ),
                    color: AppColors.categoryPurple,
                    onTap: () => _startFollowUpTraining(context, domainTopics),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
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
                  child: _PracticeModeCard(
                    icon: Icons.local_fire_department_outlined,
                    title: l10n.get('high_freq_sprint'),
                    subtitle: l10n.get(
                      'needle_peer_high_freq_interview_question_count_progress_action_accent',
                    ),
                    color: AppColors.warning,
                    onTap: () =>
                        _startHighFrequencyTraining(context, domainTopics),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.work_outline,
                    title: l10n.get('project_deep_dig'),
                    subtitle: l10n.get(
                      'star_rule_practice_deep_enter_project_detail_festival',
                    ),
                    color: AppColors.categoryGreen,
                    onTap: () => _startProjectDig(context),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.architecture_outlined,
                    title: l10n.get('system_design'),
                    subtitle: l10n.get('system_design_interview_practice'),
                    color: AppColors.categoryAmber,
                    onTap: () => _startSystemDesign(context),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
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
            );
          },
        ),
      ],
    );
  }

  void _showDomainPicker(BuildContext context, List domains) {
    final l10n = context.watch<LocalizationProvider>();
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
    // 筛选有追问的知识点
    final topicsWithFollowUps = domainTopics
        .where((topic) => topic.followUps.isNotEmpty)
        .toList();

    if (topicsWithFollowUps.isEmpty) {
      final l10n = context.watch<LocalizationProvider>();
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowUpTrainingPage(topicIds: topicIds),
      ),
    );
  }

  void _startWeaknessTraining(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WeaknessTrainingPage(currentDomainId: currentDomainId),
      ),
    );
  }

  void _startHighFrequencyTraining(BuildContext context, List domainTopics) {
    // 筛选高频知识点
    final highFrequencyTopics = domainTopics
        .where((topic) => topic.highFrequency)
        .toList();

    if (highFrequencyTopics.isEmpty) {
      final l10n = context.watch<LocalizationProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.get('current_domain_not_has_high_freq_knowledge_point'),
          ),
        ),
      );
      return;
    }

    // 随机选择最多10个高频知识点
    final shuffled = List.from(highFrequencyTopics)..shuffle();
    final selectedTopics = shuffled.take(10).toList();
    final topicIds = selectedTopics.map((t) => t.id as String).toList();

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RecallPage(topicIds: topicIds)));
  }

  void _startProjectDig(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProjectDigPage()));
  }

  void _startSystemDesign(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SystemDesignPage()));
  }
}

// ── 美化的空练习状态 ──────────────────────────────────────────────

class _EmptyPracticeState extends StatelessWidget {
  const _EmptyPracticeState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.psychology_alt_outlined,
                size: 48,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.get('temporary_no_optional_practice_knowledge_point'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get(
                'knowledge_point_correct_at_loading_in_please_slightly_wait_picture_5',
              ),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.get('restart_new_loading')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeModeCard extends StatelessWidget {
  const _PracticeModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}
