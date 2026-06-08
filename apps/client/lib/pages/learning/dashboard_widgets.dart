import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/utils/mastery_utils.dart';

// ── 下一步最佳行动组件 ──

class NextBestAction extends StatelessWidget {
  const NextBestAction({super.key, required this.weakTopics, required this.onTopicTap});

  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    if (weakTopics.isEmpty) {
      return EmptyState(message: l10n.get('temporary_no_recommend_action'));
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
                    ActionTag(
                      icon: Icons.access_time,
                      text: l10n.get('pre_plan_use_time_25_min'),
                    ),
                    const SizedBox(width: 12),
                    ActionTag(
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

class ActionTag extends StatelessWidget {
  const ActionTag({super.key, required this.icon, required this.text});

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

// ── AI反馈组件 ──

class AIFeedbackItem extends StatelessWidget {
  const AIFeedbackItem({super.key, required this.attempt});

  final PracticeAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final score = attempt.score ?? 0;
    final hasAiScore = attempt.aiEvaluated && attempt.score != null;
    final feedbackType = !hasAiScore
        ? switch (attempt.analysisStatus) {
            'failed' => l10n.get('analysis_failed_saved_local'),
            'pending' => l10n.get('analysis_pending'),
            _ => l10n.get('local_practice_already_save'),
          }
        : score >= 85
        ? l10n.get('surface_current_excellent')
        : score >= 60
        ? l10n.get('understand_question_count_thinking_road_pending_optimize')
        : l10n.get('knowledge_point_mastery_not_enough');
    final feedbackColor = !hasAiScore
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;
    final feedbackIcon = !hasAiScore
        ? switch (attempt.analysisStatus) {
            'failed' => Icons.error_outline,
            'pending' => Icons.schedule_outlined,
            _ => Icons.save_outlined,
          }
        : score >= 85
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
            hasAiScore
                ? '$score · ${_timeAgo(attempt.createdAt, l10n)}'
                : _timeAgo(attempt.createdAt, l10n),
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

// ── 领域切换下拉框 ──

class DomainDropdown extends StatelessWidget {
  const DomainDropdown({
    super.key,
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

// ── 掌握度概览组件 ──

class MasteryOverview extends StatelessWidget {
  const MasteryOverview({
    super.key,
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
              MasteryStatItem(
                label: l10n.get('skilled_training'),
                value: '$masteredPercent%',
                color: AppColors.success,
              ),
              const SizedBox(height: 8),
              MasteryStatItem(
                label: l10n.get('study_in'),
                value: '$learningPercent%',
                color: AppColors.accent,
              ),
              const SizedBox(height: 8),
              MasteryStatItem(
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

class MasteryStatItem extends StatelessWidget {
  const MasteryStatItem({
    super.key,
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

// ── 掌握度统计组件 ──

class MasteryStats extends StatelessWidget {
  const MasteryStats({super.key, required this.categories});

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
              child: MasteryStatCard(
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

class MasteryStatCard extends StatelessWidget {
  const MasteryStatCard({
    super.key,
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

// ── 领域知识卡片组件 ──

class DomainKnowledgeCard extends StatelessWidget {
  const DomainKnowledgeCard({
    super.key,
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

// ── 薄弱知识点项目组件 ──

class WeakTopicItem extends StatelessWidget {
  const WeakTopicItem({
    super.key,
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

// ── 复习项目组件 ──

class ReviewItem extends StatelessWidget {
  const ReviewItem({
    super.key,
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

// ── 通用面板卡片 ──

class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
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

// ── 空状态组件 ──

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

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

// ── 备选行动列表 ──

class AlternativeActions extends StatelessWidget {
  const AlternativeActions({
    super.key,
    required this.weakTopics,
    required this.onTopicTap,
  });

  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    if (weakTopics.isEmpty) {
      return EmptyState(
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

// ── 掌握度趋势图表 ──

class MasteryTrendChart extends StatelessWidget {
  const MasteryTrendChart({super.key, required this.trendData});

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
                  painter: LineChartPainter(data: trendData),
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
class LineChartPainter extends CustomPainter {
  const LineChartPainter({required this.data});

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

// ── 练习记录项目组件 ──

// ── 路线阶段卡片（公用） ──

class PhaseCard extends StatelessWidget {
  const PhaseCard({
    super.key,
    required this.name,
    required this.totalTopics,
    required this.masteredTopics,
    required this.statusText,
    required this.statusColor,
    required this.statusIcon,
    this.isCurrent = false,
    this.topicIds,
    this.topicTitles,
    this.onTopicTap,
    this.onPractice,
  });

  final String name;
  final int totalTopics;
  final int masteredTopics;
  final String statusText;
  final Color statusColor;
  final IconData statusIcon;
  final bool isCurrent;
  final List<String>? topicIds;
  final Map<String, String>? topicTitles;
  final void Function(String?)? onTopicTap;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context) {
    final fraction = totalTopics > 0 ? masteredTopics / totalTopics : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCurrent
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.04)
            : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
              : Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 6),
              Text(statusText,
                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
              if (isCurrent) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('当前', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary)),
                ),
              ],
              const Spacer(),
              Text('$masteredTopics/$totalTopics', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          if (topicIds != null && topicTitles != null && topicIds!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: topicIds!.take(6).map((id) => InkWell(
                onTap: onTopicTap != null ? () => onTopicTap!(id) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    topicTitles![id] ?? id,
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              )).toList(),
            ),
            if (topicIds!.length > 6)
              Text('+${topicIds!.length - 6} 更多', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
          ],
          if (onPractice != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPractice,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('开始练习'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PracticeRecordItem extends StatelessWidget {
  const PracticeRecordItem({
    super.key,
    required this.attempt,
    required this.topic,
    required this.onDelete,
  });

  final PracticeAttempt attempt;
  final Topic? topic;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final score = attempt.score ?? 0;
    final hasAiScore = attempt.aiEvaluated && attempt.score != null;
    final statusText = !hasAiScore
        ? switch (attempt.analysisStatus) {
            'failed' => l10n.get('analysis_failed_saved_local'),
            'pending' => l10n.get('analysis_pending'),
            _ => l10n.get('local_practice_already_save'),
          }
        : score >= 85
        ? l10n.get('surface_current_excellent')
        : score >= 60
        ? l10n.get('understand_question_count_thinking_road_pending_optimize')
        : l10n.get('knowledge_point_mastery_not_enough');
    final statusColor = !hasAiScore
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;
    final statusIcon = switch (attempt.analysisStatus) {
      'failed' => Icons.error_outline,
      'pending' => Icons.schedule_outlined,
      _ => Icons.save_outlined,
    };
    final title =
        topic?.title ??
        (attempt.question.isNotEmpty ? attempt.question : attempt.topicId);
    final detail = attempt.summary?.isNotEmpty == true
        ? attempt.summary!
        : (attempt.answer.isNotEmpty ? attempt.answer : attempt.question);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: hasAiScore
                ? Text(
                    '$score',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  )
                : Icon(statusIcon, size: 18, color: statusColor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _timeAgo(attempt.createdAt, l10n),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.get('delete'),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
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
