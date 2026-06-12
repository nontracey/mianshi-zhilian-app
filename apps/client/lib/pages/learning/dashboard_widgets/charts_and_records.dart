part of '../dashboard_widgets.dart';


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
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    if (data.length != oldDelegate.data.length) return true;
    for (int i = 0; i < data.length; i++) {
      if (data[i] != oldDelegate.data[i]) return true;
    }
    return false;
  }
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
    this.onTap,
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final fraction = totalTopics > 0 ? masteredTopics / totalTopics : 0.0;
    final card = Container(
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
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.get('current_phase'),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '$masteredTopics/$totalTopics',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
          if (topicIds != null &&
              topicTitles != null &&
              topicIds!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: topicIds!
                  .take(6)
                  .map(
                    (id) => InkWell(
                      onTap: onTopicTap != null ? () => onTopicTap!(id) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (topicTitles![id]?.isNotEmpty == true)
                              ? topicTitles![id]!
                              : l10n.get('knowledge_point'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (topicIds!.length > 6)
              Text(
                l10n.getp('more_count', {'count': topicIds!.length - 6}),
                style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
              ),
          ],
          if (onPractice != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPractice,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(l10n.get('start_phase_practice')),
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
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: card,
      );
    }
    return card;
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
