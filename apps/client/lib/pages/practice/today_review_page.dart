import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'recall_page.dart';
import 'today_review_widgets.dart';

class TodayReviewPage extends StatelessWidget {
  const TodayReviewPage({
    super.key,
    required this.currentDomainId,
    this.routeTopicIds,
  });

  final String currentDomainId;
  final List<String>? routeTopicIds;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final content = context.watch<ContentProvider>();
    final progress = context.watch<ProgressProvider>();
    var topics = content.getTopicsByDomain(currentDomainId);
    if (routeTopicIds != null) {
      topics = topics.where((t) => routeTopicIds!.contains(t.id)).toList();
    }
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
          ReviewHeroPanel(
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

          // ── 路线范围提示 ──
          if (routeTopicIds != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.route_outlined, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    '${l10n.get('route_scope')}: ${uniqueQueue.length} ${l10n.get('knowledge_points_count')}',
                    style: TextStyle(fontSize: 12, color: AppColors.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 到期与逾期 ──
          ReviewGroup(
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
          ReviewGroup(
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
          ReviewGroup(
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
          ReviewGroup(
            title: l10n.get('long_day_un_review'),
            icon: Icons.event_busy_outlined,
            iconColor: AppColors.categoryPurple,
            emptyText: l10n.get('all_has_knowledge_point_recent_day_review'),
            emptyIcon: Icons.event_available_outlined,
            topics: longUnreviewedTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final attempts = progress.getAttemptsForTopic(topic.id);
              if (attempts.isEmpty) {
                return l10n.get('never_practiced_high_forgetting_risk');
              }
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
          ReviewGroup(
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
              if (attempts.length < 2) {
                return l10n.get(
                  'score_lower_drop_demand_key_reinforce_consolidate',
                );
              }
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
    if (daysOverdue > 3) {
      return l10n.getp(
        'already_overdue_day_daysoverdue_forgetting_wind_risk_678_2',
        {'daysOverdue': daysOverdue},
      );
    }
    if (daysOverdue > 0) {
      return l10n.getp(
        'already_overdue_day_daysoverdue_forgetting_wind_risk_589_2',
        {'daysOverdue': daysOverdue},
      );
    }
    if (daysOverdue == 0) {
      final attempts = progress.getAttemptsForTopic(topic.id);
      if (attempts.isNotEmpty) {
        final daysSincePractice = now
            .difference(attempts.first.createdAt)
            .inDays;
        if (daysSincePractice > 0) {
          return l10n.getp(
            'distance_last_practice_dayssincepractice_day_press_forgetting_c_2',
            {'daysSincePractice': daysSincePractice},
          );
        }
      }
      return l10n.get('today_due_by_forgetting_curve');
    }
    return l10n.getp('advance_ago_review_original_fixed_days_day_after_2', {
      'days': -daysOverdue,
    });
  }

  void _startRecall(BuildContext context, List<Topic> topics) {
    var topicIds = topics.map((t) => t.id).toList();
    if (routeTopicIds != null) {
      topicIds = topicIds.where((id) => routeTopicIds!.contains(id)).toList();
    }
    if (topicIds.isEmpty) return;
    context.push(
      '/practice/recall',
      extra: RecallPage(topicIds: topicIds),
    );
  }
}
