import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/widgets/route_editor_dialog.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/utils/mastery_utils.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.currentDomainId,
    required this.onDomainChanged,
    required this.onPractice,
    required this.onTopicTap,
    required this.onViewDomainCatalog,
    this.onReview,
    this.onMockInterview,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;
  final VoidCallback onPractice;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onViewDomainCatalog;
  final VoidCallback? onReview;
  final VoidCallback? onMockInterview;

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final l10n = context.watch<LocalizationProvider>();

    if (contentProvider.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.get('loading')),
          ],
        ),
      );
    }

    if (contentProvider.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              l10n.get('error'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(contentProvider.error!, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => contentProvider.loadContent(),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.get('retry')),
            ),
          ],
        ),
      );
    }

    final domains = contentProvider.domains;
    final currentDomain = domains
        .where((d) => d.id == currentDomainId)
        .firstOrNull;

    if (currentDomain == null && domains.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onDomainChanged(domains.first.id);
      });
    }

    final domainTopics = contentProvider.getTopicsByDomain(currentDomainId);
    final domainProgress = progressProvider.getDomainProgress(
      currentDomainId,
      contentProvider.topics.values.toList(),
    );
    final masteryPercent = domainProgress.masteryPercent;
    final topicCount = domainProgress.topicCount;
    final readiness = progressProvider.readinessScore(domainTopics);

    final recommendedTopics = progressProvider.getRecommendedTopics(
      currentDomainId,
      contentProvider.topics.values.toList(),
      settingsProvider.settings.recommendStrategy,
      lowScoreWeight: settingsProvider.settings.lowScoreWeight,
      overdueWeight: settingsProvider.settings.overdueWeight,
      highFrequencyWeight: settingsProvider.settings.highFrequencyWeight,
      pathOrderWeight: settingsProvider.settings.pathOrderWeight,
      notPracticedWeight: settingsProvider.settings.notPracticedWeight,
      prioritizePrerequisites:
          settingsProvider.settings.prioritizePrerequisites,
      allowSkipLowFrequency: settingsProvider.settings.allowSkipLowFrequency,
    );

    // 薄弱知识点 Top 5
    final weakTopics = progressProvider.getWeakTopics(domainTopics, limit: 5);
    // 最近练习
    final recentAttempts = progressProvider.recentAttempts.take(5).toList();
    // 到期复习
    final dueTopics = progressProvider.getTodayReviewTopics(domainTopics);

    // 三栏工作台布局
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1200;
          final isMedium =
              constraints.maxWidth >= 800 && constraints.maxWidth < 1200;

          if (isWide) {
            // 三栏布局
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧栏：今日复习队列、薄弱知识点TOP5
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _LeftPanel(
                      dueTopics: dueTopics,
                      weakTopics: weakTopics,
                      onTopicTap: onTopicTap,
                      onReview: onReview,
                      progressProvider: progressProvider,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 中间栏：当前学习路线、领域知识卡片
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _CenterPanel(
                      currentDomain: currentDomain,
                      allDomains: domains,
                      currentDomainId: currentDomainId,
                      recommendedTopics: recommendedTopics,
                      masteryPercent: masteryPercent,
                      topicCount: topicCount,
                      readiness: readiness,
                      streakDays: progressProvider.streakDays,
                      onDomainChanged: onDomainChanged,
                      onTopicTap: onTopicTap,
                      onViewDomainCatalog: onViewDomainCatalog,
                      onPractice: onPractice,
                      onReview: onReview,
                      onMockInterview: onMockInterview,
                      contentProvider: contentProvider,
                      progressProvider: progressProvider,
                      settingsProvider: settingsProvider,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 右侧栏：掌握度概览、下一步最佳行动、最近AI反馈
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _RightPanel(
                      currentDomainId: currentDomainId,
                      domains: domains,
                      masteryPercent: masteryPercent,
                      readiness: readiness,
                      weakTopics: weakTopics,
                      recentAttempts: recentAttempts,
                      onTopicTap: onTopicTap,
                      onDomainChanged: onDomainChanged,
                      progressProvider: progressProvider,
                      contentProvider: contentProvider,
                    ),
                  ),
                ),
              ],
            );
          } else if (isMedium) {
            // 两栏布局
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _LeftPanel(
                      dueTopics: dueTopics,
                      weakTopics: weakTopics,
                      onTopicTap: onTopicTap,
                      onReview: onReview,
                      progressProvider: progressProvider,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _CenterPanel(
                      currentDomain: currentDomain,
                      allDomains: domains,
                      currentDomainId: currentDomainId,
                      recommendedTopics: recommendedTopics,
                      masteryPercent: masteryPercent,
                      topicCount: topicCount,
                      readiness: readiness,
                      streakDays: progressProvider.streakDays,
                      onDomainChanged: onDomainChanged,
                      onTopicTap: onTopicTap,
                      onViewDomainCatalog: onViewDomainCatalog,
                      onPractice: onPractice,
                      onReview: onReview,
                      onMockInterview: onMockInterview,
                      contentProvider: contentProvider,
                      progressProvider: progressProvider,
                      settingsProvider: settingsProvider,
                    ),
                  ),
                ),
              ],
            );
          } else {
            // 单栏布局（移动端）
            return SingleChildScrollView(
              child: Column(
                children: [
                  _LeftPanel(
                    dueTopics: dueTopics,
                    weakTopics: weakTopics,
                    onTopicTap: onTopicTap,
                    onReview: onReview,
                    progressProvider: progressProvider,
                  ),
                  const SizedBox(height: 16),
                  _CenterPanel(
                    currentDomain: currentDomain,
                    allDomains: domains,
                    currentDomainId: currentDomainId,
                    recommendedTopics: recommendedTopics,
                    masteryPercent: masteryPercent,
                    topicCount: topicCount,
                    readiness: readiness,
                    streakDays: progressProvider.streakDays,
                    onDomainChanged: onDomainChanged,
                    onTopicTap: onTopicTap,
                    onViewDomainCatalog: onViewDomainCatalog,
                    onPractice: onPractice,
                    onReview: onReview,
                    onMockInterview: onMockInterview,
                    contentProvider: contentProvider,
                    progressProvider: progressProvider,
                    settingsProvider: settingsProvider,
                  ),
                  const SizedBox(height: 16),
                  _RightPanel(
                    currentDomainId: currentDomainId,
                    domains: domains,
                    masteryPercent: masteryPercent,
                    readiness: readiness,
                    weakTopics: weakTopics,
                    recentAttempts: recentAttempts,
                    onTopicTap: onTopicTap,
                    onDomainChanged: onDomainChanged,
                    progressProvider: progressProvider,
                    contentProvider: contentProvider,
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}

// ── 下一步最佳行动组件 ──────────────────────────────────────────────

class _NextBestAction extends StatelessWidget {
  const _NextBestAction({required this.weakTopics, required this.onTopicTap});

  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    if (weakTopics.isEmpty) {
      return _EmptyState(message: l10n.get('temporary_no_recommend_action'));
    }

    final nextTopic = weakTopics.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              l10n.get('recommend_task'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => onTopicTap(nextTopic.id),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nextTopic.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nextTopic.domain,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ActionTag(
                      icon: Icons.access_time,
                      text: l10n.get('pre_plan_use_time_25_min'),
                    ),
                    const SizedBox(width: 12),
                    _ActionTag(
                      icon: Icons.quiz_outlined,
                      text: l10n.get('exam_point_6'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => onTopicTap(nextTopic.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(l10n.get('start_study')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionTag extends StatelessWidget {
  const _ActionTag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── AI反馈组件 ──────────────────────────────────────────────

class _AIFeedbackItem extends StatelessWidget {
  const _AIFeedbackItem({required this.attempt});

  final PracticeAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final score = attempt.score ?? 0;
    final feedbackType = score >= 85
        ? l10n.get('surface_current_excellent')
        : score >= 60
        ? l10n.get('understand_question_count_thinking_road_pending_optimize')
        : l10n.get('knowledge_point_mastery_not_enough');
    final feedbackColor = score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;
    final feedbackIcon = score >= 85
        ? Icons.check_circle_outline
        : score >= 60
        ? Icons.lightbulb_outline
        : Icons.error_outline;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: feedbackColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(feedbackIcon, size: 16, color: feedbackColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feedbackType,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: feedbackColor,
                  ),
                ),
                Text(
                  attempt.question.isNotEmpty
                      ? attempt.question
                      : attempt.topicId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _timeAgo(attempt.createdAt, l10n),
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dateTime, LocalizationProvider l10n) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return l10n.get('just');
    if (diff.inMinutes < 60) {
      return l10n.getp('minutes_min_ago_2', {'minutes': diff.inMinutes});
    }
    if (diff.inHours < 24) {
      return l10n.getp('hours_hour_ago_2', {'hours': diff.inHours});
    }
    if (diff.inDays < 7) {
      return l10n.getp('days_day_ago_2', {'days': diff.inDays});
    }
    return '${dateTime.month}/${dateTime.day}';
  }
}

// ── 领域切换下拉框 ──────────────────────────────────────────────

class _DomainDropdown extends StatelessWidget {
  const _DomainDropdown({
    required this.currentDomainId,
    required this.domains,
    required this.onChanged,
  });

  final String currentDomainId;
  final List<Domain> domains;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.borderMidnightSubtle
            : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? AppColors.borderMidnight : const Color(0xFFE0E0E0),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentDomainId,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: isDark ? Colors.white54 : AppColors.textTertiary,
          ),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : AppColors.textSecondary,
          ),
          items: domains
              .map((d) => DropdownMenuItem(value: d.id, child: Text(d.title)))
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

// ── 掌握度概览组件 ──────────────────────────────────────────────

class _MasteryOverview extends StatelessWidget {
  const _MasteryOverview({
    required this.masteryPercent,
    required this.masteredPercent,
    required this.learningPercent,
    required this.newPercent,
  });

  final int masteryPercent;
  final int masteredPercent;
  final int learningPercent;
  final int newPercent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // 环形图
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: masteryPercent / 100,
                  strokeWidth: 8,
                  backgroundColor: AppColors.success.withValues(alpha: 0.1),
                  color: AppColors.success,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$masteryPercent',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    l10n.get('mastery'),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // 掌握程度百分比
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MasteryStatItem(
                label: l10n.get('skilled_training'),
                value: '$masteredPercent%',
                color: AppColors.success,
              ),
              const SizedBox(height: 8),
              _MasteryStatItem(
                label: l10n.get('study_in'),
                value: '$learningPercent%',
                color: AppColors.accent,
              ),
              const SizedBox(height: 8),
              _MasteryStatItem(
                label: l10n.get('un_mastery'),
                value: '$newPercent%',
                color: AppColors.warning,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CategoryMastery {
  final String name;
  final int masteryPercent;

  const CategoryMastery({required this.name, required this.masteryPercent});
}

class _MasteryStatItem extends StatelessWidget {
  const _MasteryStatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── 掌握度统计组件 ──────────────────────────────────────────────

class _MasteryStats extends StatelessWidget {
  const _MasteryStats({required this.categories});

  final List<CategoryMastery> categories;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    if (categories.isEmpty) {
      return Center(
        child: Text(
          l10n.get('temporary_no_score_category_data'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: categories.take(4).map((cat) {
            final color = cat.masteryPercent >= 85
                ? AppColors.success
                : cat.masteryPercent >= 60
                ? AppColors.accent
                : cat.masteryPercent > 0
                ? AppColors.warning
                : Colors.grey;
            return SizedBox(
              width: cardWidth,
              child: _MasteryStatCard(
                title: cat.name,
                value: '${cat.masteryPercent}%',
                color: color,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _MasteryStatCard extends StatelessWidget {
  const _MasteryStatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 领域知识卡片组件 ──────────────────────────────────────────────

class _DomainKnowledgeCard extends StatelessWidget {
  const _DomainKnowledgeCard({
    required this.domain,
    required this.masteryPercent,
    required this.practiceCount,
    required this.onTap,
  });

  final Domain domain;
  final int masteryPercent;
  final int practiceCount;
  final VoidCallback onTap;

  IconData _getDomainIcon(String domainId) {
    final id = domainId.toLowerCase();
    if (id.contains('java')) return Icons.coffee;
    if (id.contains('agent') || id.contains('ai')) return Icons.smart_toy;
    if (id.contains('algorithm') || id.contains('算法')) return Icons.functions;
    if (id.contains('frontend') || id.contains('前端')) return Icons.code;
    if (id.contains('network') || id.contains('网络')) return Icons.language;
    if (id.contains('database') || id.contains('数据库')) return Icons.storage;
    if (id.contains('system') || id.contains('系统')) return Icons.computer;
    if (id.contains('security') || id.contains('安全')) return Icons.security;
    return Icons.book_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final domainColor = domain.color;
    final status = l10n.get(getMasteryLabelKey(masteryPercent));
    final statusColor = getMasteryColor(masteryPercent);

    final domainIcon = _getDomainIcon(domain.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        splashColor: domainColor.withValues(alpha: 0.08),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部：图标 + 标题
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: domainColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(domainIcon, size: 16, color: domainColor),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        domain.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : const Color(0xFF1A1A1A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: isDark ? Colors.white24 : Colors.grey.shade400,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 掌握度行
                Row(
                  children: [
                    Text(
                      '$masteryPercent%',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: domainColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: masteryPercent / 100,
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.grey.shade200,
                          color: domainColor,
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(
                          alpha: isDark ? 0.15 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(3),
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
                const SizedBox(height: 10),
                // 底部统计
                Row(
                  children: [
                    Text(
                      l10n.getp('count_exam_point_2', {
                        'count': domain.topicCount,
                      }),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.getp('count_practice_2', {'count': practiceCount}),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 统计数据块组件 ──────────────────────────────────────────────

// ── 学习路径项目组件 ──────────────────────────────────────────────

class _LearningPathItem extends StatefulWidget {
  const _LearningPathItem({
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
  State<_LearningPathItem> createState() => _LearningPathItemState();
}

class _LearningPathItemState extends State<_LearningPathItem> {
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

// ── 复习项目组件 ──────────────────────────────────────────────

class _WeakTopicItem extends StatelessWidget {
  const _WeakTopicItem({
    required this.topic,
    required this.score,
    required this.onTap,
  });

  final Topic topic;
  final int score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final scoreColor = getMasteryColor(score);
    final level = score >= 85
        ? l10n.get('high')
        : score >= 60
        ? l10n.get('medium')
        : l10n.get('low');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  level,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: scoreColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    topic.domain,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$score%',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: scoreColor,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
              child: Text(
                l10n.get('go_practice'),
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 复习项目组件 ──────────────────────────────────────────────

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({
    required this.topic,
    required this.score,
    required this.nextReviewAt,
    required this.onTap,
  });

  final Topic topic;
  final int score;
  final DateTime? nextReviewAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final scoreColor = score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;

    // 使用真实的复习时间
    String timeText;
    Color timeColor;
    if (nextReviewAt != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final reviewDate = DateTime(
        nextReviewAt!.year,
        nextReviewAt!.month,
        nextReviewAt!.day,
      );
      final isToday = reviewDate.isAtSameMomentAs(today);
      final isTomorrow = reviewDate.isAtSameMomentAs(
        today.add(const Duration(days: 1)),
      );

      if (isToday) {
        timeText = l10n.getp('today_day_hour_minute_2', {
          'hour': nextReviewAt!.hour,
          'minute': nextReviewAt!.minute.toString().padLeft(2, '0'),
        });
        timeColor = AppColors.danger;
      } else if (isTomorrow) {
        timeText = l10n.getp('clear_day_hour_minute_2', {
          'hour': nextReviewAt!.hour,
          'minute': nextReviewAt!.minute.toString().padLeft(2, '0'),
        });
        timeColor = AppColors.textSecondary;
      } else {
        timeText = '${nextReviewAt!.month}/${nextReviewAt!.day}';
        timeColor = AppColors.textSecondary;
      }
    } else {
      timeText = l10n.get('pending_arrange_rank');
      timeColor = AppColors.textTertiary;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // 分数
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: scoreColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 标题和领域
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${topic.domain} · ${topic.category}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 时间
            Text(
              timeText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: timeColor,
              ),
            ),
            const SizedBox(width: 8),
            // 复习按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                l10n.get('review'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 通用面板卡片 ──────────────────────────────────────────────

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.child,
    this.trailing,
    this.headerTrailing,
    this.icon,
    this.onTrailingTap,
  });

  final String title;
  final Widget child;
  final String? trailing;
  final Widget? headerTrailing;
  final IconData? icon;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final borderColor = Theme.of(context).colorScheme.outline;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              if (headerTrailing != null) ...[
                headerTrailing!,
                const SizedBox(width: 8),
              ],
              if (trailing != null)
                GestureDetector(
                  onTap: onTrailingTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trailing!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                        if (onTrailingTap != null) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            size: 14,
                            color: AppColors.accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── 空状态组件 ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ── 左侧面板：今日复习队列、薄弱知识点TOP5 ──────────────────────────────────────────────

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({
    required this.dueTopics,
    required this.weakTopics,
    required this.onTopicTap,
    required this.onReview,
    required this.progressProvider,
  });

  final List<Topic> dueTopics;
  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;
  final VoidCallback? onReview;
  final ProgressProvider progressProvider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 今日复习队列
        _PanelCard(
          title: l10n.get('today_day_review_queue'),
          icon: Icons.replay_outlined,
          trailing: '${dueTopics.length}',
          headerTrailing: Text(
            l10n.get('to_day_time'),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : AppColors.textTertiary,
            ),
          ),
          child: Column(
            children: [
              if (dueTopics.isEmpty)
                _EmptyState(message: l10n.get('temporary_no_to_day_content'))
              else
                ...dueTopics.take(5).map((topic) {
                  final progress = progressProvider.getTopicProgress(topic.id);
                  final score = progress?.score ?? 0;
                  final nextReviewAt = progress?.nextReviewAt;
                  return _ReviewItem(
                    topic: topic,
                    score: score,
                    nextReviewAt: nextReviewAt,
                    onTap: () => onTopicTap(topic.id),
                  );
                }),
              if (dueTopics.length > 5)
                TextButton(
                  onPressed: onReview,
                  child: Text(l10n.get('check_view_all_review')),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 薄弱知识点TOP5
        _PanelCard(
          title: l10n.get('weak_knowledge_point_top_5'),
          icon: Icons.trending_down_outlined,
          trailing: '${weakTopics.length}',
          child: Column(
            children: [
              if (weakTopics.isEmpty)
                _EmptyState(message: l10n.get('temporary_no_weak_item'))
              else
                ...weakTopics.map((topic) {
                  final progress = progressProvider.getTopicProgress(topic.id);
                  final score = progress?.score ?? 0;
                  return _WeakTopicItem(
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
}

// ── 中间面板：当前学习路线、领域知识卡片 ──────────────────────────────────────────────

class _CenterPanel extends StatefulWidget {
  const _CenterPanel({
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

  @override
  State<_CenterPanel> createState() => _CenterPanelState();
}

class _CenterPanelState extends State<_CenterPanel> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final _storage = StorageService();
  List<String> _disabledIds = [];
  LearningRoute? _selectedRoute;

  @override
  void initState() {
    super.initState();
    _loadDisabled();
    _loadSelectedRoute();
  }

  Future<void> _loadDisabled() async {
    final ids = await _storage.loadDisabledDomains();
    if (mounted) setState(() => _disabledIds = ids);
  }

  Future<void> _loadSelectedRoute() async {
    final routeId = await _storage.load('selected_route_id');
    if (routeId != null && mounted) {
      // 加载自定义路线
      final customData = await _storage.loadJsonList('custom_routes');
      final customRoutes = customData
          .map((e) => LearningRoute.fromJson(e))
          .toList();

      // 默认路线
      final defaultRoutes = [
        LearningRoute(
          id: 'java',
          name: l10n.get('java_backend_dev'),
          description: l10n.get(
            'java_core_jvm_concurrent_spring_database_in_between_condition_syst',
          ),
          domainIds: [
            'java',
            'architecture',
            'design-pattern',
            'network',
            'os',
          ],
          isDefault: true,
        ),
        LearningRoute(
          id: 'frontend',
          name: l10n.get('frontend_dev'),
          description: l10n.get(
            'javascript_typescript_react_vue_frontend_engineering_transform',
          ),
          domainIds: ['frontend', 'algorithm', 'design-pattern', 'network'],
          isDefault: true,
        ),
        LearningRoute(
          id: 'agent',
          name: l10n.get('agent_dev'),
          description: l10n.get('ai_tech_stack_description'),
          domainIds: ['agent', 'algorithm', 'architecture', 'network'],
          isDefault: true,
        ),
      ];

      // 从内容仓库生成的学习路线
      final contentRoutes = _generateRoutesFromContent();

      final allRoutes = [...defaultRoutes, ...contentRoutes, ...customRoutes];
      final route = allRoutes.where((r) => r.id == routeId).firstOrNull;
      if (route != null && mounted) {
        setState(() => _selectedRoute = route);
      }
    }
  }

  Future<void> _saveSelectedRoute(LearningRoute? route) async {
    if (route != null) {
      await _storage.save('selected_route_id', route.id);
    } else {
      await _storage.save('selected_route_id', null);
    }
    if (mounted) setState(() => _selectedRoute = route);
  }

  List<Domain> get _domains {
    var domains = widget.allDomains
        .where((d) => !_disabledIds.contains(d.id))
        .toList();

    // 如果选中了路线，按路线顺序过滤
    if (_selectedRoute != null && _selectedRoute!.domainIds.isNotEmpty) {
      domains = domains
          .where((d) => _selectedRoute!.domainIds.contains(d.id))
          .toList();
      domains.sort(
        (a, b) => _selectedRoute!.domainIds
            .indexOf(a.id)
            .compareTo(_selectedRoute!.domainIds.indexOf(b.id)),
      );
    }

    return domains;
  }

  // 所有未禁用的领域（不受路线选择影响）
  List<Domain> get _allEnabledDomains {
    return widget.allDomains
        .where((d) => !_disabledIds.contains(d.id))
        .toList();
  }

  // 从内容仓库的 learningPaths 生成学习路线
  List<LearningRoute> _generateRoutesFromContent() {
    final routes = <LearningRoute>[];
    for (final domain in widget.allDomains) {
      for (final path in domain.learningPaths) {
        routes.add(
          LearningRoute(
            id: '${domain.id}_${path.id}',
            name: path.title,
            description: path.description,
            domainIds: [domain.id],
            isDefault: false,
          ),
        );
      }
    }
    return routes;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final domains = _domains;
    final allEnabledDomains = _allEnabledDomains;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前学习路线
        _PanelCard(
          title: l10n.get('current_study_route'),
          icon: Icons.route_outlined,
          trailing: l10n.get('toggle_switch_route'),
          onTrailingTap: () => _showRouteSelector(context),
          child: Column(
            children: [
              if (domains.isEmpty)
                _EmptyState(message: l10n.get('temporary_no_study_route'))
              else
                ...domains.take(5).toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final domain = entry.value;
                  final dp = widget.progressProvider.getDomainProgress(
                    domain.id,
                    widget.contentProvider.topics.values.toList(),
                  );
                  return _LearningPathItem(
                    domain: domain,
                    index: index,
                    masteryPercent: dp.masteryPercent,
                    isSelected: domain.id == widget.currentDomainId,
                    onTap: () {
                      widget.onDomainChanged(domain.id);
                      if (widget.contentProvider.getLoadedTopicCount(
                            domain.id,
                          ) ==
                          0) {
                        widget.contentProvider.loadDomainTopics(domain.id);
                      }
                    },
                    onViewCatalog: () {
                      widget.onDomainChanged(domain.id);
                      if (widget.contentProvider.getLoadedTopicCount(
                            domain.id,
                          ) ==
                          0) {
                        widget.contentProvider.loadDomainTopics(domain.id);
                      }
                      widget.onViewDomainCatalog(domain.id);
                    },
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 领域知识卡片
        _PanelCard(
          title: l10n.get('domain_knowledge_card'),
          icon: Icons.school_outlined,
          trailing: l10n.get('management_domain'),
          onTrailingTap: () => _showManageDomains(context),
          child: Column(
            children: [
              if (allEnabledDomains.isEmpty)
                _EmptyState(message: l10n.get('temporary_no_domain_data'))
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
                          child: _DomainKnowledgeCard(
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

  void _showRouteSelector(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final defaultRoutes = [
      LearningRoute(
        id: 'java',
        name: l10n.get('java_backend_dev'),
        description: l10n.get(
          'java_core_jvm_concurrent_spring_database_in_between_condition_syst',
        ),
        domainIds: ['java', 'architecture', 'design-pattern', 'network', 'os'],
        isDefault: true,
      ),
      LearningRoute(
        id: 'frontend',
        name: l10n.get('frontend_dev'),
        description: l10n.get(
          'javascript_typescript_react_vue_frontend_engineering_transform',
        ),
        domainIds: ['frontend', 'algorithm', 'design-pattern', 'network'],
        isDefault: true,
      ),
      LearningRoute(
        id: 'agent',
        name: l10n.get('agent_dev'),
        description: l10n.get('ai_tech_stack_description'),
        domainIds: ['agent', 'algorithm', 'architecture', 'network'],
        isDefault: true,
      ),
    ];

    // 从内容仓库生成的学习路线
    final contentRoutes = _generateRoutesFromContent();

    final routes = [...defaultRoutes, ...contentRoutes];

    showDialog(
      context: context,
      builder: (ctx) => _RouteSelectorDialog(
        routes: routes,
        currentRouteId: _selectedRoute?.id,
        availableDomains: widget.allDomains,
        disabledDomainIds: _disabledIds,
        onRouteSelected: (route) {
          _saveSelectedRoute(route);
          if (route.domainIds.isNotEmpty) {
            widget.onDomainChanged(route.domainIds.first);
          }
        },
      ),
    );
  }

  void _showManageDomains(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ManageDomainsDialog(
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
}

// ── 路线选择对话框 ──────────────────────────────────────────────

class _RouteSelectorDialog extends StatefulWidget {
  const _RouteSelectorDialog({
    required this.routes,
    required this.currentRouteId,
    required this.onRouteSelected,
    required this.availableDomains,
    this.disabledDomainIds = const [],
  });

  final List<LearningRoute> routes;
  final String? currentRouteId;
  final ValueChanged<LearningRoute> onRouteSelected;
  final List<Domain> availableDomains;
  final List<String> disabledDomainIds;

  @override
  State<_RouteSelectorDialog> createState() => _RouteSelectorDialogState();
}

class _RouteSelectorDialogState extends State<_RouteSelectorDialog> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  late List<LearningRoute> _routes;
  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    // 加载自定义路线
    final customData = await _storage.loadJsonList('custom_routes');
    final customRoutes = customData
        .map((e) => LearningRoute.fromJson(e))
        .toList();

    setState(() {
      _routes = [...widget.routes, ...customRoutes];
    });
  }

  Future<void> _saveCustomRoutes() async {
    final customRoutes = _routes.where((r) => !r.isDefault).toList();
    await _storage.saveJsonList(
      'custom_routes',
      customRoutes.map((r) => r.toJson()).toList(),
    );
  }

  void _addCustomRoute(LearningRoute route) {
    setState(() => _routes.add(route));
    _saveCustomRoutes();
  }

  void _updateRoute(int index, LearningRoute route) {
    setState(() => _routes[index] = route);
    _saveCustomRoutes();
  }

  void _deleteRoute(String routeId) {
    setState(() => _routes.removeWhere((r) => r.id == routeId));
    _saveCustomRoutes();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  l10n.get('select_study_route'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 路线列表
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: Column(
                  children: _routes.asMap().entries.map((entry) {
                    final l10n = context.watch<LocalizationProvider>();
                    final index = entry.key;
                    final route = entry.value;
                    final isSelected = route.id == widget.currentRouteId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          widget.onRouteSelected(route);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accent.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.accent
                                  : (isDark
                                        ? AppColors.borderMidnight
                                        : const Color(0xFFE0E0E0)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          route.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? AppColors.accent
                                                : null,
                                          ),
                                        ),
                                        if (!route.isDefault) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.accent
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              l10n.get('custom'),
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: AppColors.accent,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (route.description.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          route.description,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.grey,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // 编辑按钮
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                color: isDark ? Colors.white54 : Colors.grey,
                                onPressed: () {
                                  Navigator.pop(context);
                                  final enabledDomains = widget.availableDomains
                                      .where(
                                        (d) => !widget.disabledDomainIds
                                            .contains(d.id),
                                      )
                                      .toList();
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => RouteEditorDialog(
                                      availableDomains: enabledDomains
                                          .map(
                                            (d) => DomainItem(
                                              id: d.id,
                                              title: d.title,
                                            ),
                                          )
                                          .toList(),
                                      existingRoute: route,
                                      onSave: (updatedRoute) {
                                        _updateRoute(index, updatedRoute);
                                        if (route.id == widget.currentRouteId) {
                                          widget.onRouteSelected(updatedRoute);
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                              // 删除按钮（仅自定义路线）
                              if (!route.isDefault)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  color: Colors.red.shade300,
                                  onPressed: () => _deleteRoute(route.id),
                                ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.accent,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 创建自定义路线
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final enabledDomains = widget.availableDomains
                      .where((d) => !widget.disabledDomainIds.contains(d.id))
                      .toList();
                  showDialog(
                    context: context,
                    builder: (ctx) => RouteEditorDialog(
                      availableDomains: enabledDomains
                          .map((d) => DomainItem(id: d.id, title: d.title))
                          .toList(),
                      onSave: _addCustomRoute,
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: Text(l10n.get('create_build_custom_route')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 管理领域对话框 ──────────────────────────────────────────────

class _ManageDomainsDialog extends StatefulWidget {
  const _ManageDomainsDialog({
    required this.domains,
    required this.disabledDomainIds,
    required this.onToggleDomain,
  });

  final List<Domain> domains;
  final Set<String> disabledDomainIds;
  final ValueChanged<String> onToggleDomain;

  @override
  State<_ManageDomainsDialog> createState() => _ManageDomainsDialogState();
}

class _ManageDomainsDialogState extends State<_ManageDomainsDialog> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  late Set<String> _disabledIds;

  @override
  void initState() {
    super.initState();
    _disabledIds = Set.from(widget.disabledDomainIds);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school_outlined, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  l10n.get('management_domain'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('toggle_switch_open_close_come_enable_disable_domain'),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ),
            const SizedBox(height: 16),

            // 领域列表
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: Column(
                  children: widget.domains.map((domain) {
                    final isDisabled = _disabledIds.contains(domain.id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDisabled
                            ? (isDark
                                  ? AppColors.surfaceDark
                                  : Colors.grey.shade100)
                            : (isDark
                                  ? AppColors.surfaceMidnight
                                  : Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDisabled
                              ? (isDark
                                    ? AppColors.borderDarkSubtle
                                    : Colors.grey.shade200)
                              : (isDark
                                    ? AppColors.borderMidnight
                                    : AppColors.borderLight),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  domain.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDisabled
                                        ? Colors.grey
                                        : (isDark
                                              ? Colors.white
                                              : AppColors.textPrimary),
                                  ),
                                ),
                                Text(
                                  l10n.getp('count_knowledge_point_2', {
                                    'count': domain.topicCount,
                                  }),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDisabled
                                        ? Colors.grey
                                        : (isDark
                                              ? Colors.white54
                                              : Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: !isDisabled,
                            onChanged: (value) {
                              setState(() {
                                if (isDisabled) {
                                  _disabledIds.remove(domain.id);
                                } else {
                                  _disabledIds.add(domain.id);
                                }
                                widget.onToggleDomain(domain.id);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 说明
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.get(
                        'disable_domain_not_will_at_first_page_show_but_conten',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 右侧面板 ──────────────────────────────────────────────

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.currentDomainId,
    required this.domains,
    required this.masteryPercent,
    required this.readiness,
    required this.weakTopics,
    required this.recentAttempts,
    required this.onTopicTap,
    required this.onDomainChanged,
    required this.progressProvider,
    required this.contentProvider,
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
  final ContentProvider contentProvider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    // 获取掌握度趋势数据
    final trendData = progressProvider.getMasteryTrend();

    // 计算当前领域的分类掌握度
    final domainTopics = contentProvider.getTopicsByDomain(currentDomainId);

    // 按分类计算掌握度
    final categoryMap = <String, List<Topic>>{};
    for (final topic in domainTopics) {
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
      // 没有学习过的分类，掌握度为0
      final avgScore = learnedCount == 0 ? 0 : totalScore ~/ learnedCount;
      return CategoryMastery(name: entry.key, masteryPercent: avgScore);
    }).toList()..sort((a, b) => b.masteryPercent.compareTo(a.masteryPercent));

    // 计算掌握程度百分比
    int totalTopics = domainTopics.length;
    int masteredCount = 0;
    int learningCount = 0;
    int newCount = 0;

    for (final topic in domainTopics) {
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
        // 掌握度概览
        _PanelCard(
          title: l10n.get('mastery_overview_browse'),
          icon: Icons.pie_chart_outline,
          headerTrailing: _DomainDropdown(
            currentDomainId: currentDomainId,
            domains: domains,
            onChanged: onDomainChanged,
          ),
          child: Column(
            children: [
              _MasteryOverview(
                masteryPercent: masteryPercent,
                masteredPercent: masteredPercent,
                learningPercent: learningPercent,
                newPercent: newPercent,
              ),
              const SizedBox(height: 16),
              _MasteryStats(categories: categories.take(4).toList()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 掌握度趋势
        _PanelCard(
          title: l10n.get('mastery_trend_recent_7_day'),
          icon: Icons.trending_up_outlined,
          child: _MasteryTrendChart(trendData: trendData),
        ),
        const SizedBox(height: 16),
        // 下一步最佳行动
        _PanelCard(
          title: l10n.get('next_step_best_action'),
          icon: Icons.lightbulb_outline,
          child: _NextBestAction(
            weakTopics: weakTopics,
            onTopicTap: onTopicTap,
          ),
        ),
        const SizedBox(height: 16),
        // 备选行动
        _PanelCard(
          title: l10n.get('alternate_select_action'),
          icon: Icons.list_alt_outlined,
          child: _AlternativeActions(
            weakTopics: weakTopics,
            onTopicTap: onTopicTap,
          ),
        ),
        const SizedBox(height: 16),
        // 最近AI反馈
        _PanelCard(
          title: l10n.get('recent_ai_feedback'),
          icon: Icons.auto_awesome_outlined,
          trailing: l10n.get('check_view_all'),
          child: Column(
            children: [
              if (recentAttempts.isEmpty)
                _EmptyState(message: l10n.get('temporary_no_feedback_record'))
              else
                ...recentAttempts.take(3).map((attempt) {
                  return _AIFeedbackItem(attempt: attempt);
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 掌握度趋势图表 ──────────────────────────────────────────────

class _MasteryTrendChart extends StatelessWidget {
  const _MasteryTrendChart({required this.trendData});

  final List<double?> trendData;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final now = DateTime.now();
    final dates = List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    });

    // 检查是否所有数据都是 null
    final hasData = trendData.any((d) => d != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 图表区域
        SizedBox(
          height: 120,
          child: hasData
              ? CustomPaint(
                  size: const Size(double.infinity, 120),
                  painter: _LineChartPainter(data: trendData),
                )
              : Center(
                  child: Text(
                    l10n.get('start_study_after_will_expand_show_trend'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        // X轴标签
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: dates
              .map(
                (date) => Text(
                  date,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

// 简单的折线图绘制器
class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.data});

  final List<double?> data;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final stepX = width / (data.length - 1);

    // 绘制线条（跳过 null 值）
    bool lastWasNull = true;
    for (int i = 0; i < data.length; i++) {
      if (data[i] == null) {
        lastWasNull = true;
        continue;
      }

      final x = i * stepX;
      final y = height - (data[i]! / 100 * height);

      if (lastWasNull) {
        path.moveTo(x, y);
        lastWasNull = false;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // 绘制数据点（跳过 null 值）
    final dotPaint = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      if (data[i] == null) continue;

      final x = i * stepX;
      final y = height - (data[i]! / 100 * height);
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 备选行动列表 ──────────────────────────────────────────────

class _AlternativeActions extends StatelessWidget {
  const _AlternativeActions({
    required this.weakTopics,
    required this.onTopicTap,
  });

  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    if (weakTopics.isEmpty) {
      return _EmptyState(
        message: l10n.get('temporary_no_alternate_select_action'),
      );
    }

    // 取第2-4个薄弱知识点作为备选
    final alternatives = weakTopics.skip(1).take(3).toList();

    return Column(
      children: alternatives.map((topic) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onTopicTap(topic.id),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    topic.id.contains('review')
                        ? Icons.replay_outlined
                        : Icons.school_outlined,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.getp('type_title', {
                            'type': topic.id.contains('review')
                                ? l10n.get('review')
                                : l10n.get('study'),
                            'title': topic.title,
                          }),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          topic.domain,
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
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
