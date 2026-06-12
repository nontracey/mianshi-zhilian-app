part of '../dashboard_widgets.dart';

// ── 下一步最佳行动组件 ──

class NextBestAction extends StatelessWidget {
  const NextBestAction({
    super.key,
    required this.reviewTopics,
    required this.weakTopics,
    required this.newTopics,
    required this.onTopicTap,
    this.onReview,
  });

  final List<Topic> reviewTopics;
  final List<Topic> weakTopics;
  final List<Topic> newTopics;
  final ValueChanged<String> onTopicTap;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final action = _selectAction(l10n);
    if (action == null) {
      return EmptyState(message: l10n.get('temporary_no_recommend_action'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(action.icon, size: 16, color: action.color),
            const SizedBox(width: 8),
            Text(
              action.heading,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: action.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: action.onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: action.color.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.topic.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.topic.domain,
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
                      text: l10n.getp('minutes_min_2', {
                        'minutes': action.topic.estimatedMinutes,
                      }),
                    ),
                    const SizedBox(width: 12),
                    ActionTag(icon: action.tagIcon, text: action.tagText),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: action.onPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: action.color,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(action.buttonText),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  _NextAction? _selectAction(LocalizationProvider l10n) {
    if (reviewTopics.isNotEmpty) {
      return _NextAction(
        topic: reviewTopics.first,
        heading: l10n.get('recommend_task'),
        buttonText: l10n.get('start_review'),
        tagText: l10n.get('pending_review'),
        icon: Icons.rate_review_outlined,
        tagIcon: Icons.event_available_outlined,
        color: AppColors.warning,
        onPressed: onReview ?? () => onTopicTap(reviewTopics.first.id),
      );
    }
    if (weakTopics.isNotEmpty) {
      return _NextAction(
        topic: weakTopics.first,
        heading: l10n.get('recommend_task'),
        buttonText: l10n.get('start_study'),
        tagText: l10n.get('demand_review'),
        icon: Icons.lightbulb_outline,
        tagIcon: Icons.report_problem_outlined,
        color: AppColors.accent,
        onPressed: () => onTopicTap(weakTopics.first.id),
      );
    }
    if (newTopics.isNotEmpty) {
      return _NextAction(
        topic: newTopics.first,
        heading: l10n.get('recommend_task'),
        buttonText: l10n.get('start_study'),
        tagText: l10n.get('daily_new_learn'),
        icon: Icons.auto_stories_outlined,
        tagIcon: Icons.fiber_new_outlined,
        color: AppColors.accent,
        onPressed: () => onTopicTap(newTopics.first.id),
      );
    }
    return null;
  }
}

class _NextAction {
  const _NextAction({
    required this.topic,
    required this.heading,
    required this.buttonText,
    required this.tagText,
    required this.icon,
    required this.tagIcon,
    required this.color,
    required this.onPressed,
  });

  final Topic topic;
  final String heading;
  final String buttonText;
  final String tagText;
  final IconData icon;
  final IconData tagIcon;
  final Color color;
  final VoidCallback onPressed;
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
