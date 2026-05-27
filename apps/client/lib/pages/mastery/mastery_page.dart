import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

enum MasterySort { scoreAsc, scoreDesc }

enum MasteryFilter { all, skilled, familiar, unfamiliar }

class MasteryPage extends StatefulWidget {
  const MasteryPage({
    super.key,
    required this.currentDomainId,
    required this.onDomainChanged,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;

  @override
  State<MasteryPage> createState() => _MasteryPageState();
}

class _MasteryPageState extends State<MasteryPage> {
  MasterySort _sort = MasterySort.scoreAsc;
  MasteryFilter _filter = MasteryFilter.all;

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();

    final domains = contentProvider.domains;
    final currentDomain = domains.where((d) => d.id == widget.currentDomainId).firstOrNull;
    if (currentDomain == null) {
      return const Center(child: Text('请选择一个领域'));
    }

    final domainTopics = contentProvider.getTopicsByDomain(widget.currentDomainId);
    final domainProgress = progressProvider.getDomainProgress(widget.currentDomainId);
    final masteryPercent = domainProgress.$1;

    final filteredTopics = _applyFilter(domainTopics, progressProvider);
    final sortedTopics = _applySort(filteredTopics, progressProvider);

    return WorkPanel(
      title: '${currentDomain.title} · $masteryPercent%',
      trailing: SegmentedButton<String>(
        segments: domains
            .map((d) => ButtonSegment(value: d.id, label: Text(d.id)))
            .toList(),
        selected: {widget.currentDomainId},
        onSelectionChanged: (next) => widget.onDomainChanged(next.first),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(value: masteryPercent / 100),
            ),
            const SizedBox(width: 12),
            Text('$masteryPercent%'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<MasterySort>(
                value: _sort,
                decoration: const InputDecoration(
                  labelText: '排序',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: MasterySort.scoreAsc, child: Text('熟练度 低→高')),
                  DropdownMenuItem(value: MasterySort.scoreDesc, child: Text('熟练度 高→低')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _sort = value);
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<MasteryFilter>(
                value: _filter,
                decoration: const InputDecoration(
                  labelText: '筛选',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: MasteryFilter.all, child: Text('全部')),
                  DropdownMenuItem(value: MasteryFilter.skilled, child: Text('熟练')),
                  DropdownMenuItem(value: MasteryFilter.familiar, child: Text('不熟练')),
                  DropdownMenuItem(value: MasteryFilter.unfamiliar, child: Text('未掌握')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _filter = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: sortedTopics.map((topic) {
            final progress = progressProvider.getTopicProgress(topic.id);
            final score = progress?.score ?? 0;
            final status = progress?.status ?? TopicStatus.unfamiliar;
            return _MasteryCard(
              title: topic.title,
              status: status,
              score: score,
            );
          }).toList(),
        ),
      ],
    );
  }

  List<Topic> _applyFilter(List<Topic> topics, ProgressProvider provider) {
    return switch (_filter) {
      MasteryFilter.all => topics,
      MasteryFilter.skilled => topics.where((t) {
          final p = provider.getTopicProgress(t.id);
          return p?.status == TopicStatus.skilled;
        }).toList(),
      MasteryFilter.familiar => topics.where((t) {
          final p = provider.getTopicProgress(t.id);
          return p?.status == TopicStatus.familiar;
        }).toList(),
      MasteryFilter.unfamiliar => topics.where((t) {
          final p = provider.getTopicProgress(t.id);
          return p?.status == TopicStatus.unfamiliar || p == null;
        }).toList(),
    };
  }

  List<Topic> _applySort(List<Topic> topics, ProgressProvider provider) {
    final sorted = List<Topic>.from(topics);
    sorted.sort((a, b) {
      final scoreA = provider.getTopicProgress(a.id)?.score ?? 0;
      final scoreB = provider.getTopicProgress(b.id)?.score ?? 0;
      return switch (_sort) {
        MasterySort.scoreAsc => scoreA.compareTo(scoreB),
        MasterySort.scoreDesc => scoreB.compareTo(scoreA),
      };
    });
    return sorted;
  }
}

class _MasteryCard extends StatelessWidget {
  const _MasteryCard({
    required this.title,
    required this.status,
    required this.score,
  });

  final String title;
  final TopicStatus status;
  final int score;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (status) {
      TopicStatus.skilled => '熟练',
      TopicStatus.familiar => '不熟练',
      TopicStatus.unfamiliar => '未掌握',
    };

    final statusColor = switch (status) {
      TopicStatus.skilled => AppColors.success,
      TopicStatus.familiar => AppColors.warning,
      TopicStatus.unfamiliar => Colors.grey,
    };

    return SizedBox(
      width: 260,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '$score 分',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _scoreColor(score),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: score / 100,
              color: _scoreColor(score),
            ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 85) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return Colors.grey;
  }
}
