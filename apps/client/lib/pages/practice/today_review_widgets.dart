import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

// ── 顶部 Hero 统计面板 ──────────────────────────────────────────────

class ReviewHeroPanel extends StatelessWidget {
  const ReviewHeroPanel({
    required this.dueCount,
    required this.lowScoreCount,
    required this.highFreqCount,
    required this.longUnreviewedCount,
    required this.regressedCount,
    required this.totalCount,
    this.onStartAll,
  });

  final int dueCount;
  final int lowScoreCount;
  final int highFreqCount;
  final int longUnreviewedCount;
  final int regressedCount;
  final int totalCount;
  final VoidCallback? onStartAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            AppColors.categoryDeepBlue,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.get('review_load'),
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            totalCount == 0
                ? l10n.get('temporary_no_pending_review_content')
                : l10n.getp(
                    'total_totalcount_knowledge_point_pending_review_2',
                    {'totalCount': totalCount},
                  ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 20),
          // 统计卡片行
          Row(
            children: [
              StatChip(
                icon: Icons.schedule_outlined,
                label: l10n.get('to_day'),
                value: dueCount,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              StatChip(
                icon: Icons.trending_down_outlined,
                label: l10n.get('low_score'),
                value: lowScoreCount,
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              StatChip(
                icon: Icons.event_busy_outlined,
                label: l10n.get('un_review'),
                value: longUnreviewedCount,
                color: AppColors.categoryPurple,
              ),
              const SizedBox(width: 8),
              StatChip(
                icon: Icons.priority_high_outlined,
                label: l10n.get('regression_step'),
                value: regressedCount,
                color: AppColors.accent,
              ),
            ],
          ),
          if (onStartAll != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStartAll,
                icon: const Icon(Icons.play_arrow, size: 20),
                label: Text(l10n.get('one_key_start_all_review')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bgDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StatChip extends StatelessWidget {
  const StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$value',
              style: TextStyle(
                color: value > 0 ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 复习分组 ──────────────────────────────────────────────

class ReviewGroup extends StatelessWidget {
  const ReviewGroup({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.emptyText,
    required this.emptyIcon,
    required this.topics,
    required this.progressProvider,
    required this.reasonBuilder,
    required this.onStart,
    this.onSkip,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String emptyText;
  final IconData emptyIcon;
  final List<Topic> topics;
  final ProgressProvider progressProvider;
  final String Function(Topic topic) reasonBuilder;
  final ValueChanged<Topic> onStart;
  final ValueChanged<Topic>? onSkip;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: title,
      trailing: topics.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${topics.length}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: iconColor,
                  fontSize: 12,
                ),
              ),
            ),
      children: [
        if (topics.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Icon(emptyIcon, size: 32, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text(
                  emptyText,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          ...topics.map(
            (topic) => ReviewTile(
              topic: topic,
              reason: reasonBuilder(topic),
              progressProvider: progressProvider,
              onStart: () => onStart(topic),
              onSkip: onSkip != null ? () => onSkip!(topic) : null,
            ),
          ),
      ],
    );
  }
}

// ── 复习知识点行 ──────────────────────────────────────────────

class ReviewTile extends StatelessWidget {
  const ReviewTile({
    required this.topic,
    required this.reason,
    required this.progressProvider,
    required this.onStart,
    this.onSkip,
  });

  final Topic topic;
  final String reason;
  final ProgressProvider progressProvider;
  final VoidCallback onStart;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final progress = progressProvider.getTopicProgress(topic.id);
    final score = progress?.score ?? 0;
    final attempts = progressProvider.getAttemptsForTopic(topic.id);
    final lastMissed = attempts.isNotEmpty
        ? attempts.last.missedPoints
        : <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Expanded(
                  child: Text(
                    topic.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (progress != null) ScoreBadge(score: score),
              ],
            ),
            const SizedBox(height: 8),
            // 原因 + 预计耗时
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: iconColor(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  Icons.timer_outlined,
                  size: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.getp('minutes_min_2', {
                    'minutes': topic.estimatedMinutes,
                  }),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            // 上次遗漏点
            if (lastMissed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.get('last_missed'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...lastMissed
                        .take(2)
                        .map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '· $p',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // 操作按钮行
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(l10n.get('start_review')),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (onSkip != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onSkip,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    child: Text(l10n.get('push_postpone')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color iconColor(BuildContext context) {
    final score = progressProvider.getTopicProgress(topic.id)?.score ?? 0;
    if (score < 40) return AppColors.danger;
    if (score < 70) return AppColors.warning;
    return AppColors.success;
  }
}
