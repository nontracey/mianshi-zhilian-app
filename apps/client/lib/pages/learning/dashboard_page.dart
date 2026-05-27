import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/status_dot.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.currentDomainId,
    required this.onDomainChanged,
    required this.onPractice,
    required this.onTopicTap,
    required this.onViewDomainCatalog,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;
  final VoidCallback onPractice;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onViewDomainCatalog;

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();

    // 内容加载中
    if (contentProvider.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载知识库...'),
          ],
        ),
      );
    }

    // 加载出错
    if (contentProvider.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('加载失败', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(contentProvider.error!, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => contentProvider.loadContent(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final domains = contentProvider.domains;
    final currentDomain = domains
        .where((d) => d.id == currentDomainId)
        .firstOrNull;

    if (currentDomain == null && domains.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onDomainChanged(domains.first.id);
      });
    }

    final domainProgress = progressProvider.getDomainProgress(
      currentDomainId,
      contentProvider.topics.values.toList(),
    );
    final masteryPercent = domainProgress.masteryPercent;
    final topicCount = domainProgress.topicCount;
    final reviewCount = progressProvider.getReviewCount(currentDomainId);

    final recommendedTopics = progressProvider.getRecommendedTopics(
      currentDomainId,
      contentProvider.topics.values.toList(),
      'low-score-first',
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _HeroPanel(
          domainTitle: currentDomain?.title ?? '',
          masteryPercent: masteryPercent,
          topicCount: topicCount,
          reviewCount: reviewCount,
          onPractice: onPractice,
        ),
        const SizedBox(height: 20),
        Text('领域选择', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        // 领域卡片：加载中显示骨架屏，加载完显示卡片
        contentProvider.isLoading
            ? const _DomainSkeleton()
            : Wrap(
                spacing: 14,
                runSpacing: 14,
                children: domains.map((domain) {
                  final dp = progressProvider.getDomainProgress(
                    domain.id,
                    contentProvider.topics.values.toList(),
                  );
                  final loaded = contentProvider.getLoadedTopicCount(domain.id);
                  final total = domain.topicCount;
                  return _DomainCardWrapper(
                    domain: domain,
                    masteryPercent: dp.masteryPercent,
                    selected: domain.id == currentDomainId,
                    loadingProgress: total > 0 ? loaded / total : 0,
                    isTopicLoading:
                        contentProvider.isLoadingTopics &&
                        domain.id == currentDomainId,
                    onTap: () {
                      onDomainChanged(domain.id);
                      // 切换领域时自动加载该领域的 topics
                      if (contentProvider.getLoadedTopicCount(domain.id) == 0) {
                        contentProvider.loadDomainTopics(domain.id);
                      }
                    },
                    onViewDetail: () {
                      onDomainChanged(domain.id);
                      if (contentProvider.getLoadedTopicCount(domain.id) == 0) {
                        contentProvider.loadDomainTopics(domain.id);
                      }
                      onViewDomainCatalog(domain.id);
                    },
                  );
                }).toList(),
              ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 900;
            final children = [
              WorkPanel(
                title: '继续学习 ${currentDomain?.title ?? ''}',
                children: recommendedTopics.isEmpty
                    ? [_EmptyContinueLearning(onPractice: onPractice)]
                    : recommendedTopics.take(3).map((topic) {
                        final progress = progressProvider.getTopicProgress(
                          topic.id,
                        );
                        return _TopicTile(
                          topic: topic,
                          progress: progress,
                          onTap: () => onTopicTap(topic.id),
                        );
                      }).toList(),
              ),
              WorkPanel(
                title: '学习节奏',
                children: const [
                  _InfoRow(
                    icon: Icons.today_outlined,
                    title: '每日 3 个新知识 + 6 个复习',
                    subtitle: '本地优先保存，完成练习后批量同步。',
                  ),
                  _InfoRow(
                    icon: Icons.key_outlined,
                    title: '用户自带 AI Key',
                    subtitle: 'App 端优先直连，Web 端可走 Worker 代理。',
                  ),
                ],
              ),
            ];
            return wide
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < children.length; index += 1)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: index == children.length - 1 ? 0 : 12,
                              ),
                              child: children[index],
                            ),
                          ),
                      ],
                    ),
                  )
                : Column(children: children);
          },
        ),
      ],
    );
  }
}

// ── 空状态：暂未学习 ──────────────────────────────────────────────

class _EmptyContinueLearning extends StatelessWidget {
  const _EmptyContinueLearning({required this.onPractice});

  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 36,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 10),
          const Text(
            '暂未学习',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          const Text(
            '还没有学习记录，开始练习来提升掌握度吧',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: onPractice,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始练习'),
          ),
        ],
      ),
    );
  }
}

// ── 领域卡片骨架屏 ──────────────────────────────────────────────

class _DomainSkeleton extends StatelessWidget {
  const _DomainSkeleton();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: List.generate(
        3,
        (_) => SizedBox(
          width: 330,
          height: 180,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 200,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.domainTitle,
    required this.masteryPercent,
    required this.topicCount,
    required this.reviewCount,
    required this.onPractice,
  });

  final String domainTitle;
  final int masteryPercent;
  final int topicCount;
  final int reviewCount;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(label: Text('当前领域：$domainTitle')),
                const SizedBox(height: 8),
                Text(
                  '把面试知识练成可以讲出来的答案',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '先充分学习知识解释，再进入复述训练，由 AI 按 rubric 评分、纠错和补充。',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onPractice,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('进入复述练习'),
                ),
              ],
            ),
          ),
          _StatBlock(value: '$masteryPercent%', label: '领域掌握度'),
          _StatBlock(value: '$topicCount', label: '知识点'),
          _StatBlock(value: '$reviewCount', label: '待复习'),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 18),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 28,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    ),
  );
}

class _DomainCardWrapper extends StatelessWidget {
  const _DomainCardWrapper({
    required this.domain,
    required this.masteryPercent,
    required this.selected,
    required this.loadingProgress,
    required this.isTopicLoading,
    required this.onTap,
    required this.onViewDetail,
  });

  final Domain domain;
  final int masteryPercent;
  final bool selected;
  final double loadingProgress;
  final bool isTopicLoading;
  final VoidCallback onTap;
  final VoidCallback onViewDetail;

  @override
  Widget build(BuildContext context) {
    final domainColor = domain.color;
    return SizedBox(
      width: 330,
      height: 180,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? domainColor : Theme.of(context).dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      domain.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (isTopicLoading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: domainColor,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(domain.description),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: loadingProgress < 1.0 && loadingProgress > 0
                    ? loadingProgress
                    : masteryPercent / 100,
                color: domainColor,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      loadingProgress < 1.0 && loadingProgress > 0
                          ? '加载中 ${domain.topicCount} 个知识点...'
                          : '$masteryPercent% 熟练 · ${domain.topicCount} 个知识点',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onViewDetail,
                    style: FilledButton.styleFrom(
                      backgroundColor: selected
                          ? domainColor
                          : Theme.of(context).colorScheme.secondaryContainer,
                      foregroundColor: selected
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSecondaryContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('查看知识'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.topic,
    required this.progress,
    required this.onTap,
  });

  final Topic topic;
  final TopicProgress? progress;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final score = progress?.score ?? 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusDot(score: score),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(topic.summary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
