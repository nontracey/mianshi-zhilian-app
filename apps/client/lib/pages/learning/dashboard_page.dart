import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/domain_card.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/status_dot.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.currentDomainId,
    required this.onDomainChanged,
    required this.onPractice,
    required this.onTopicTap,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;
  final VoidCallback onPractice;
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();

    final domains = contentProvider.domains;
    final currentDomain = domains.where((d) => d.id == currentDomainId).firstOrNull;

    if (currentDomain == null && domains.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onDomainChanged(domains.first.id);
      });
    }

    final domainProgress = progressProvider.getDomainProgress(currentDomainId);
    final masteryPercent = domainProgress.$1;
    final topicCount = domainProgress.$2;
    final reviewCount = progressProvider.getReviewCount(currentDomainId);

    final recommendedTopics = progressProvider.getRecommendedTopics(currentDomainId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroPanel(
          domainTitle: currentDomain?.title ?? '',
          masteryPercent: masteryPercent,
          topicCount: topicCount,
          reviewCount: reviewCount,
          onPractice: onPractice,
        ),
        const SizedBox(height: 20),
        Text(
          '领域选择',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: domains.map((domain) {
            final dp = progressProvider.getDomainProgress(domain.id);
            return _DomainCardWrapper(
              domain: domain,
              masteryPercent: dp.$1,
              selected: domain.id == currentDomainId,
              onTap: () => onDomainChanged(domain.id),
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
                children: recommendedTopics.take(3).map((topic) {
                  final progress = progressProvider.getTopicProgress(topic.id);
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
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children
                        .map((c) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: c,
                              ),
                            ))
                        .toList(),
                  )
                : Column(children: children);
          },
        ),
      ],
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
    required this.onTap,
  });

  final Domain domain;
  final int masteryPercent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final domainColor = _parseDomainColor(domain.color);
    return SizedBox(
      width: 330,
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
              Text(
                domain.title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(domain.description),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: masteryPercent / 100,
                color: domainColor,
              ),
              const SizedBox(height: 8),
              Text('$masteryPercent% 熟练 · 点击切换领域'),
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
                  Text(topic.title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _parseDomainColor(String? colorStr) {
  if (colorStr == null) return AppColors.primary;
  if (colorStr.startsWith('#') && colorStr.length == 7) {
    final hex = colorStr.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
  return AppColors.primary;
}
