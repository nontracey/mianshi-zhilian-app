part of '../dashboard_widgets.dart';


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
