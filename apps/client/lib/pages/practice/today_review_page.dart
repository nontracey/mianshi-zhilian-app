import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

import 'recall_page.dart';
import '../../providers/localization_provider.dart';
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
      appBar: AppBar(title: Text(l10n.get('4eca_day_review_5de5_4f5c_53f0'))),
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
            title: l10n.get('5230_671f_4e0e_903e_671f'),
            icon: Icons.schedule_outlined,
            iconColor: AppColors.warning,
            emptyText: l10n.get('6682_no_5230_671f_review'),
            emptyIcon: Icons.check_circle_outline,
            topics: dueTopics,
            progressProvider: progress,
            reasonBuilder: (topic) => _reviewReason(context, progress, topic),
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: (topic) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.getp('already_5c06_{title}_63a8_8fdf_5230_660e_day', {'title': topic.title}))),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── 低分与错因回流 ──
          _ReviewGroup(
            title: l10n.get('4f4e_5206_4e0e_9519_56e0_56de_6d41'),
            icon: Icons.trending_down_outlined,
            iconColor: AppColors.danger,
            emptyText: l10n.get('6682_no_4f4e_5206_56de_6d41'),
            emptyIcon: Icons.sentiment_satisfied_outlined,
            topics: lowScoreTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final attempts = progress.getAttemptsForTopic(topic.id);
              final lastScore = attempts.isNotEmpty
                  ? (attempts.first.score ?? 0)
                  : 0;
              final practiceCount = attempts.length;
              return l10n.getp('recent_5f97_5206_{lastscore}_5206_already_practice_{practice', {'lastScore': lastScore, 'practiceCount': practiceCount});
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
            emptyText: l10n.get('high_freq_knowledge_mastery_7a33_5b9a'),
            emptyIcon: Icons.verified_outlined,
            topics: highFrequencyTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final score = progress.getTopicProgress(topic.id)?.score ?? 0;
              return l10n.getp('high_freq_knowledge_point_current_{score}_5206_un_8fbe_719f', {'score': score});
            },
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: (topic) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.getp('already_5c06_{title}_63a8_8fdf_5230_660e_day', {'title': topic.title}))),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── 长期未复习 ──
          _ReviewGroup(
            title: l10n.get('957f_671f_un_review'),
            icon: Icons.event_busy_outlined,
            iconColor: AppColors.categoryPurple,
            emptyText: l10n.get('6240_has_knowledge_point_8fd1_671f_90fd_has_review'),
            emptyIcon: Icons.event_available_outlined,
            topics: longUnreviewedTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final attempts = progress.getAttemptsForTopic(topic.id);
              if (attempts.isEmpty) return l10n.get('4ece_un_practice_forgetting_98ce_9669_6781_9ad8');
              final lastDate = attempts.first.createdAt;
              final days = DateTime.now().difference(lastDate).inDays;
              return l10n.getp('8ddd_last_practice_already_{days}_day_suggestion_5c3d_5feb_r', {'days': days});
            },
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: (topic) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.getp('already_5c06_{title}_63a8_8fdf', {'title': topic.title}))),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── 最近退步 ──
          _ReviewGroup(
            title: l10n.get('recent_9000_6b65'),
            icon: Icons.trending_down_outlined,
            iconColor: AppColors.danger,
            emptyText: l10n.get('8fd1_671f_no_9000_6b65_knowledge_point'),
            emptyIcon: Icons.trending_up_outlined,
            topics: regressedTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final attempts = progress.getAttemptsForTopic(topic.id);
              if (attempts.length < 2) return l10n.get('score_4e0b_964d_9700_8981_5de9_56fa');
              final latest = attempts[0].score ?? 0;
              final previous = attempts[1].score ?? 0;
              final diff = previous - latest;
              return l10n.getp('4ece_{previous}_5206_964d_81f3_{latest}_5206_4e0b_964d_{diff', {'previous': previous, 'latest': latest, 'diff': diff});
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
                    l10n.get('4eca_day_review_already_complete'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.get('6ca1_has_5230_671f_6216_weak_content_9700_8981_review_53ef_4'),
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
    if (p?.nextReviewAt == null) return l10n.get('9700_8981_review');
    final now = DateTime.now();
    final daysOverdue = now.difference(p!.nextReviewAt!).inDays;
    if (daysOverdue > 3) return l10n.getp('already_903e_671f_{daysoverdue}_day_forgetting_98ce_9669_678', {'daysOverdue': daysOverdue});
    if (daysOverdue > 0) return l10n.getp('already_903e_671f_{daysoverdue}_day_forgetting_98ce_9669_589', {'daysOverdue': daysOverdue});
    if (daysOverdue == 0) {
      final attempts = progress.getAttemptsForTopic(topic.id);
      if (attempts.isNotEmpty) {
        final daysSincePractice = now.difference(attempts.first.createdAt).inDays;
        if (daysSincePractice > 0) return l10n.getp('8ddd_last_practice_{dayssincepractice}_day_6309_forgetting_c', {'daysSincePractice': daysSincePractice});
      }
      return l10n.get('4eca_day_5230_671f_6309_forgetting_curve_5b89_6392');
    }
    return l10n.getp('63d0_524d_review_539f_5b9a_{days}_day_540e', {'days': -daysOverdue});
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
                ? l10n.get('6682_no_5f85_review_content')
                : l10n.getp('total_{totalcount}_4e2a_knowledge_point_pending_review', {'totalCount': totalCount}),
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
                label: l10n.get('5230_671f'),
                value: dueCount,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.trending_down_outlined,
                label: l10n.get('4f4e_5206'),
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
                label: l10n.get('9000_6b65'),
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
                label: Text(l10n.get('4e00_952e_start_all_review')),
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
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
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
                  l10n.getp('{minutes}_min', {'minutes': topic.estimatedMinutes}),
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
                    ...lastMissed.take(2).map(
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
                    child: Text(l10n.get('63a8_8fdf')),
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
