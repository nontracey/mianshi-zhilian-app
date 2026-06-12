part of '../dashboard_widgets.dart';


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
