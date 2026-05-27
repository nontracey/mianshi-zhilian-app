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
    final loaded = contentProvider.getLoadedTopicCount(currentDomainId);
    final total = currentDomain.topicCount;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        WorkPanel(
          title: currentDomain.title,
          trailing: SegmentedButton<String>(
            segments: domains
                .map((d) => ButtonSegment(value: d.id, label: Text(d.id)))
                .toList(),
            selected: {currentDomainId},
            onSelectionChanged: (next) {
              onDomainChanged(next.first);
              // 切换领域时自动加载 topics
              if (contentProvider.getLoadedTopicCount(next.first) == 0) {
                contentProvider.loadDomainTopics(next.first);
              }
            },
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
            if (contentProvider.isLoadingTopics && loaded < total) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('正在加载知识点 $loaded/$total ...'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            ...currentDomain.categories.map((category) {
              final categoryTopics = domainTopics
                  .where((t) => t.category == category.id)
                  .toList();
              if (categoryTopics.isEmpty && !contentProvider.isLoadingTopics) {
                // 分类下暂无数据（可能还没加载）
                return _CategorySection(
                  category: category,
                  topics: const [],
                  isLoading: contentProvider.isLoadingTopics,
                  progressProvider: progressProvider,
                  onTopicLearn: onTopicLearn,
                  onTopicPractice: onTopicPractice,
                );
              }
              return _CategorySection(
                category: category,
                topics: categoryTopics,
                isLoading: false,
                progressProvider: progressProvider,
                onTopicLearn: onTopicLearn,
                onTopicPractice: onTopicPractice,
              );
            }),
          ],
        ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.topics,
    required this.isLoading,
    required this.progressProvider,
    required this.onTopicLearn,
    required this.onTopicPractice,
  });

  final Category category;
  final List<Topic> topics;
  final bool isLoading;
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
        if (isLoading && topics.isEmpty)
          // 加载中骨架
          ...List.generate(3, (_) => Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle)),
              title: Container(width: 160, height: 14, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4))),
              subtitle: Container(width: 240, height: 12, decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(4))),
            ),
          ))
        else if (topics.isEmpty)
          // 暂无数据
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '暂无知识点',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          )
        else
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
