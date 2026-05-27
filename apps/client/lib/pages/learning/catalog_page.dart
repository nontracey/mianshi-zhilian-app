import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/status_dot.dart';

class CatalogPage extends StatelessWidget {
  const CatalogPage({
    super.key,
    required this.currentDomainId,
    required this.onDomainChanged,
    required this.onTopicLearn,
    required this.onTopicPractice,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;
  final ValueChanged<String> onTopicLearn;
  final ValueChanged<String> onTopicPractice;

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();

    final domains = contentProvider.domains;
    final currentDomain = domains.where((d) => d.id == currentDomainId).firstOrNull;
    if (currentDomain == null) {
      return const Center(child: Text('请选择一个领域'));
    }

    final domainTopics = contentProvider.getTopicsByDomain(currentDomainId);
    final domainProgress = progressProvider.getDomainProgress(currentDomainId, contentProvider.topics.values.toList());
    final masteryPercent = domainProgress.masteryPercent;

    return WorkPanel(
      title: currentDomain.title,
      trailing: SegmentedButton<String>(
        segments: domains
            .map((d) => ButtonSegment(value: d.id, label: Text(d.id)))
            .toList(),
        selected: {currentDomainId},
        onSelectionChanged: (next) => onDomainChanged(next.first),
      ),
      children: [
        Text(currentDomain.description),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(value: masteryPercent / 100),
            ),
            const SizedBox(width: 12),
            Text('$masteryPercent%'),
          ],
        ),
        const SizedBox(height: 18),
        ...currentDomain.categories.map((category) {
          final categoryTopics = domainTopics
              .where((t) => t.category == category.id)
              .toList();
          if (categoryTopics.isEmpty) return const SizedBox.shrink();
          return _CategorySection(
            category: category,
            topics: categoryTopics,
            progressProvider: progressProvider,
            onTopicLearn: onTopicLearn,
            onTopicPractice: onTopicPractice,
          );
        }),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.topics,
    required this.progressProvider,
    required this.onTopicLearn,
    required this.onTopicPractice,
  });

  final Category category;
  final List<Topic> topics;
  final ProgressProvider progressProvider;
  final ValueChanged<String> onTopicLearn;
  final ValueChanged<String> onTopicPractice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(
          category.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        if (category.description != null && category.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            category.description!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        ...topics.map((topic) {
          final progress = progressProvider.getTopicProgress(topic.id);
          final score = progress?.score ?? 0;
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: StatusDot(score: score),
              title: Text(topic.title),
              subtitle: Text(topic.summary),
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => onTopicLearn(topic.id),
                    child: const Text('知识查阅'),
                  ),
                  FilledButton(
                    onPressed: () => onTopicPractice(topic.id),
                    child: const Text('学习模式'),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
