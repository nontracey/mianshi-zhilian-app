import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

import 'recall_page.dart';

class TodayReviewPage extends StatelessWidget {
  const TodayReviewPage({super.key, required this.currentDomainId});

  final String currentDomainId;

  @override
  Widget build(BuildContext context) {
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

    final queue = <Topic>[
      ...dueTopics,
      ...lowScoreTopics,
      ...highFrequencyTopics,
    ];
    final uniqueQueue = {
      for (final topic in queue) topic.id: topic,
    }.values.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('今日复习工作台')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── 顶部 Hero 统计面板 ──
          _ReviewHeroPanel(
            dueCount: dueTopics.length,
            lowScoreCount: lowScoreTopics.length,
            highFreqCount: highFrequencyTopics.length,
            totalCount: uniqueQueue.length,
            onStartAll: uniqueQueue.isEmpty
                ? null
                : () => _startRecall(context, uniqueQueue),
          ),
          const SizedBox(height: 20),

          // ── 到期与逾期 ──
          _ReviewGroup(
            title: '到期与逾期',
            icon: Icons.schedule_outlined,
            iconColor: AppColors.warning,
            emptyText: '暂无到期复习',
            emptyIcon: Icons.check_circle_outline,
            topics: dueTopics,
            progressProvider: progress,
            reasonBuilder: (topic) => _reviewReason(context, progress, topic),
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: (topic) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已将「${topic.title}」推迟到明天')),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── 低分与错因回流 ──
          _ReviewGroup(
            title: '低分与错因回流',
            icon: Icons.trending_down_outlined,
            iconColor: AppColors.danger,
            emptyText: '暂无低分回流',
            emptyIcon: Icons.sentiment_satisfied_outlined,
            topics: lowScoreTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final attempts = progress.getAttemptsForTopic(topic.id);
              final lastScore = attempts.isNotEmpty
                  ? (attempts.last.score ?? 0)
                  : 0;
              // ignore: unnecessary_null_comparison
              return '最近得分 $lastScore 分，需要重新组织回答';
            },
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: null, // 低分不建议跳过
          ),
          const SizedBox(height: 16),

          // ── 高频未稳 ──
          _ReviewGroup(
            title: '高频未稳',
            icon: Icons.priority_high_outlined,
            iconColor: AppColors.accent,
            emptyText: '高频知识掌握稳定',
            emptyIcon: Icons.verified_outlined,
            topics: highFrequencyTopics,
            progressProvider: progress,
            reasonBuilder: (topic) {
              final score = progress.getTopicProgress(topic.id)?.score ?? 0;
              return '高频知识点，当前 $score 分，未达熟练阈值';
            },
            onStart: (topic) => _startRecall(context, [topic]),
            onSkip: (topic) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已将「${topic.title}」推迟到明天')),
              );
            },
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
                  const Text(
                    '今日复习已完成！',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '没有到期或薄弱内容需要复习，可以进行高频冲刺或模拟面试。',
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
    final p = progress.getTopicProgress(topic.id);
    if (p?.nextReviewAt == null) return '需要复习';
    final now = DateTime.now();
    final days = now.difference(p!.nextReviewAt!).inDays;
    if (days > 0) return '已逾期 $days 天，遗忘风险增加';
    if (days == 0) return '今天到期，按遗忘曲线安排';
    return '提前复习';
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
    required this.totalCount,
    this.onStartAll,
  });

  final int dueCount;
  final int lowScoreCount;
  final int highFreqCount;
  final int totalCount;
  final VoidCallback? onStartAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            const Color(0xFF0F3460),
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
          const Text(
            '复习负载',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            totalCount == 0
                ? '暂无待复习内容'
                : '共 $totalCount 个知识点等待复习',
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
                label: '到期',
                value: dueCount,
                color: AppColors.warning,
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.trending_down_outlined,
                label: '低分',
                value: lowScoreCount,
                color: AppColors.danger,
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.priority_high_outlined,
                label: '高频',
                value: highFreqCount,
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
                label: const Text('一键开始全部复习'),
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
                  '${topic.estimatedMinutes} 分钟',
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
                      '上次遗漏：',
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
                    label: const Text('开始复习'),
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
                    child: const Text('推迟'),
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
