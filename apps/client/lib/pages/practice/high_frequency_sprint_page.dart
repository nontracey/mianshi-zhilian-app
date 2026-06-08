import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/practice/recall_page.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/pages/practice/practice_widgets.dart';

class HighFrequencySprintPage extends StatelessWidget {
  const HighFrequencySprintPage({super.key, required this.topics});

  final List<Topic> topics;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final progress = context.watch<ProgressProvider>();
    final sorted = List<Topic>.from(topics)
      ..sort((a, b) {
        final scoreA = progress.getTopicProgress(a.id)?.score ?? 0;
        final scoreB = progress.getTopicProgress(b.id)?.score ?? 0;
        if (scoreA != scoreB) return scoreA.compareTo(scoreB);
        return b.difficulty.compareTo(a.difficulty);
      });
    final sprintTopics = sorted.take(10).toList();
    final unstableCount = topics
        .where(
          (topic) => (progress.getTopicProgress(topic.id)?.score ?? 0) < 85,
        )
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('high_freq_sprint'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.local_fire_department_outlined,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.get('high_freq_sprint'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.get(
                              'priority_sprint_high_freq_unstable_knowledge_point_suitable_combine',
                            ),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SprintStatChip(
                      icon: Icons.flag_outlined,
                      label: l10n.getp('count_knowledge_point_2', {
                        'count': topics.length,
                      }),
                    ),
                    SprintStatChip(
                      icon: Icons.trending_down_outlined,
                      label: l10n.getp('count_question_count_2', {
                        'count': unstableCount,
                      }),
                    ),
                    SprintStatChip(
                      icon: Icons.quiz_outlined,
                      label: l10n.getp('count_question_count_2', {
                        'count': sprintTopics.length,
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: sprintTopics.isEmpty
                        ? null
                        : () => context.push(
                            '/practice/recall',
                            extra: RecallPage(
                              topicIds: sprintTopics
                                  .map((t) => t.id)
                                  .toList(),
                            ),
                          ),
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: Text(l10n.get('start_practice')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.get('sprint_question_list'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...sprintTopics.map((topic) {
            final topicProgress = progress.getTopicProgress(topic.id);
            final score = topicProgress?.score ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 18,
                    color: score >= 85 ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${topic.category} · ${l10n.getp('score_score_2', {'score': score})}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
