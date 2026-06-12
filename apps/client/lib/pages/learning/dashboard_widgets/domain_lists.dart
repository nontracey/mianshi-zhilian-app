part of '../dashboard_widgets.dart';


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
            const SizedBox(width: 4),
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
            Flexible(
              child: Text(
                timeText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: timeColor,
                ),
                overflow: TextOverflow.ellipsis,
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
