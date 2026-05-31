import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

import 'recall_page.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

class TodayReviewPage extends StatelessWidget {
  const TodayReviewPage({super.key, required this.currentDomainId});

  final String currentDomainId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final content = context.watch<ContentProvider>();
    final progress = context.watch<ProgressProvider>();
    final topics = content.getTopicsByDomain(currentDomainId);
    final dueTopics = progress.getTodayReviewTopics(topics);
    final lowScoreTopicIds = progress.lowScoreAttempts
        .map((a) => a.topicId)
        .toSet();
    final lowScoreTopics = topics
        .where((topic) => lowScoreTopicIds.contains(topic.id))
        .toList();
    final highFrequencyTopics = topics.where((topic) {
      final score = progress.getTopicProgress(topic.id)?.score ?? 0;
      return topic.highFrequency && score < 85;
    }).toList();
    final longUnreviewedIds = progress.getLongUnreviewedTopicIds(topics);
    final longUnreviewedTopics = topics
        .where((t) => longUnreviewedIds.contains(t.id))
        .toList();
    final regressedIds = progress.getRegressedTopicIds(topics);
    final regressedTopics = topics
        .where((t) => regressedIds.contains(t.id))
        .toList();

    final queue = <Topic>[
      ...dueTopics,
      ...lowScoreTopics,
      ...highFrequencyTopics,
      ...longUnreviewedTopics,
      ...regressedTopics,
    ];
    final uniqueQueue = {
      for (final topic in queue) topic.id: topic,
    }.values.toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('today_day_review_work_platform'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── 顶部 Hero 统计面板 ──
          _ReviewHeroPanel(
            dueCount: dueTopics.length,
            lowScoreCount: lowScoreTopics.length,
            highFreqCount: highFrequencyTopics.length,
            longUnreviewedCount: longUnreviewedTopics.length,
            regressedCount: regressedTopics.length,
            totalCount: uniqueQueue.length,
            onStartAll: uniqueQueue.isEmpty
                ? null
                : () => _startRecall(context, uniqueQueue),
          ),
          const SizedBox(height: 20),

          // ── 到期与逾期 ──
          _ReviewGroup(
            title: l10n.get('to_day_and_overdue'),
            icon: Icons.schedule_outlined,
            iconColor: AppColors.warning,
            emptyText: l10n.get('temporary_no_to_day_review'),
            emptyIcon: Icons.check_circle_outline,
            topics: dueTopics,
            progressProvider: progress,
            reasonBuilder: (topic) => _reviewReason(context, progress, topic),
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: (topic) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.getp(
                      'already_will_title_push_postpone_to_clear_day_2',
                      {'title': topic.title},
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── 低分与错因回流 ──
          _ReviewGroup(
            title: l10n.get('low_score_and_error_because_back_flow'),
            icon: Icons.trending_down_outlined,
            iconColor: AppColors.danger,
            emptyText: l10n.get('temporary_no_low_score_back_flow'),
            emptyIcon: Icons.sentiment_satisfied_outlined,
            topics: lowScoreTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final attempts = progress.getAttemptsForTopic(topic.id);
              final lastScore = attempts.isNotEmpty
                  ? (attempts.first.score ?? 0)
                  : 0;
              final practiceCount = attempts.length;
              return l10n.getp(
                'recent_get_score_lastscore_already_practice_practice_2',
                {'lastScore': lastScore, 'practiceCount': practiceCount},
              );
            },
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: null, // 低分不建议跳过
          ),
          const SizedBox(height: 16),

          // ── 高频未稳 ──
          _ReviewGroup(
            title: l10n.get('high_freq_unstable'),
            icon: Icons.priority_high_outlined,
            iconColor: AppColors.accent,
            emptyText: l10n.get('high_freq_knowledge_mastery_stable_fixed'),
            emptyIcon: Icons.verified_outlined,
            topics: highFrequencyTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final score = progress.getTopicProgress(topic.id)?.score ?? 0;
              return l10n.getp(
                'high_freq_knowledge_point_current_score_score_un_reach_skilled_2',
                {'score': score},
              );
            },
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: (topic) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.getp(
                      'already_will_title_push_postpone_to_clear_day_2',
                      {'title': topic.title},
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── 长期未复习 ──
          _ReviewGroup(
            title: l10n.get('long_day_un_review'),
            icon: Icons.event_busy_outlined,
            iconColor: AppColors.categoryPurple,
            emptyText: l10n.get('all_has_knowledge_point_recent_day_review'),
            emptyIcon: Icons.event_available_outlined,
            topics: longUnreviewedTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final attempts = progress.getAttemptsForTopic(topic.id);
              if (attempts.isEmpty)
                return l10n.get('never_practiced_high_forgetting_risk');
              final lastDate = attempts.first.createdAt;
              final days = DateTime.now().difference(lastDate).inDays;
              return l10n.getp(
                'distance_last_practice_already_days_day_suggestion_exhaust_fast_r_2',
                {'days': days},
              );
            },
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: (topic) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.getp('already_will_title_push_postpone_2', {
                      'title': topic.title,
                    }),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── 最近退步 ──
          _ReviewGroup(
            title: l10n.get('recent_regression_step'),
            icon: Icons.trending_down_outlined,
            iconColor: AppColors.danger,
            emptyText: l10n.get(
              'recent_day_no_regression_step_knowledge_point',
            ),
            emptyIcon: Icons.trending_up_outlined,
            topics: regressedTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final attempts = progress.getAttemptsForTopic(topic.id);
              if (attempts.length < 2)
                return l10n.get(
                  'score_lower_drop_demand_key_reinforce_consolidate',
                );
              final latest = attempts[0].score ?? 0;
              final previous = attempts[1].score ?? 0;
              final diff = previous - latest;
              return l10n.getp(
                'from_previous_score_drop_to_latest_lower_diff_2',
                {'previous': previous, 'latest': latest, 'diff': diff},
              );
            },
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: null,
          ),

          // ── 空状态提示 ──
          if (uniqueQueue.isEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: AppColors.success.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.get('today_day_review_already_complete'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.get(
                      'not_has_to_day_or_weak_content_demand_key_review_optional_4',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _reviewReason(
    BuildContext context,
    ProgressProvider progress,
    Topic topic,
  ) {
    final l10n = context.watch<LocalizationProvider>();
    final p = progress.getTopicProgress(topic.id);
    if (p?.nextReviewAt == null) return l10n.get('demand_key_review');
    final now = DateTime.now();
    final daysOverdue = now.difference(p!.nextReviewAt!).inDays;
    if (daysOverdue > 3)
      return l10n.getp(
        'already_overdue_day_daysoverdue_forgetting_wind_risk_678_2',
        {'daysOverdue': daysOverdue},
      );
    if (daysOverdue > 0)
      return l10n.getp(
        'already_overdue_day_daysoverdue_forgetting_wind_risk_589_2',
        {'daysOverdue': daysOverdue},
      );
    if (daysOverdue == 0) {
      final attempts = progress.getAttemptsForTopic(topic.id);
      if (attempts.isNotEmpty) {
        final daysSincePractice = now
            .difference(attempts.first.createdAt)
            .inDays;
        if (daysSincePractice > 0)
          return l10n.getp(
            'distance_last_practice_dayssincepractice_day_press_forgetting_c_2',
            {'daysSincePractice': daysSincePractice},
          );
      }
      return l10n.get('today_due_by_forgetting_curve');
    }
    return l10n.getp('advance_ago_review_original_fixed_days_day_after_2', {
      'days': -daysOverdue,
    });
  }

  void _startRecall(BuildContext context, List<Topic> topics) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecallPage(topicIds: topics.map((t) => t.id).toList()),
      ),
    );
  }
}

// ── 顶部 Hero 统计面板 ──────────────────────────────────────────────

class _ReviewHeroPanel extends StatelessWidget {
  const _ReviewHeroPanel({
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
              _StatChip(
                icon: Icons.schedule_outlined,
                label: l10n.get('to_day'),
                value: dueCount,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.trending_down_outlined,
                label: l10n.get('low_score'),
                value: lowScoreCount,
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.event_busy_outlined,
                label: l10n.get('un_review'),
                value: longUnreviewedCount,
                color: AppColors.categoryPurple,
              ),
              const SizedBox(width: 8),
              _StatChip(
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

class _StatChip extends StatelessWidget {
  const _StatChip({
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

class _ReviewGroup extends StatelessWidget {
  const _ReviewGroup({
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
            (topic) => _ReviewTile(
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

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
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
