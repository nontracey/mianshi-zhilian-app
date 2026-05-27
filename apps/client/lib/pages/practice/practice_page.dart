import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class PracticePage extends StatelessWidget {
  const PracticePage({
    super.key,
    required this.currentDomainId,
    required this.onDailyReview,
    required this.onRandomQuiz,
    required this.onMockInterview,
  });

  final String currentDomainId;
  final VoidCallback onDailyReview;
  final ValueChanged<String> onRandomQuiz;
  final VoidCallback onMockInterview;

  @override
  Widget build(BuildContext context) {
    final progressProvider = context.watch<ProgressProvider>();
    final reviewCount = progressProvider.getReviewCount(currentDomainId);
    final contentProvider = context.watch<ContentProvider>();
    final domains = contentProvider.domains;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择练习模式',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth > 900
                ? (constraints.maxWidth - 32) / 3
                : constraints.maxWidth;

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.today_outlined,
                    title: '今日复习',
                    subtitle: '基于遗忘曲线，今天有 $reviewCount 个知识点待复习',
                    color: AppColors.accent,
                    onTap: onDailyReview,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.casino_outlined,
                    title: '随机抽问',
                    subtitle: '选择领域后随机抽取知识点进行复述练习',
                    color: AppColors.success,
                    onTap: () => _showDomainPicker(context, domains),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.groups_outlined,
                    title: '模拟面试',
                    subtitle: '连续多题模式，模拟真实面试场景',
                    color: AppColors.warning,
                    onTap: onMockInterview,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showDomainPicker(BuildContext context, List domains) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择领域'),
        children: domains
            .map<SimpleDialogOption>((domain) => SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(ctx, domain.id);
                    onRandomQuiz(domain.id);
                  },
                  child: Text(domain.title),
                ))
            .toList(),
      ),
    );
  }
}

class _PracticeModeCard extends StatelessWidget {
  const _PracticeModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(24),
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      ),
    );
  }
}
