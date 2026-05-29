import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/practice/follow_up_training_page.dart';
import 'package:mianshi_zhilian/pages/practice/weakness_training_page.dart';
import 'package:mianshi_zhilian/pages/practice/recall_page.dart';
import 'package:mianshi_zhilian/pages/practice/project_dig_page.dart';
import 'package:mianshi_zhilian/pages/practice/system_design_page.dart';

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
    final domainTopics = contentProvider.getTopicsByDomain(currentDomainId);

    // 还没有加载到任何知识点时显示空状态
    if (domainTopics.isEmpty && contentProvider.isLoadingTopics) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在加载知识点...', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    if (domainTopics.isEmpty) {
      return _EmptyPracticeState(
        onRetry: () => contentProvider.loadDomainTopics(currentDomainId),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '选择练习模式',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
                    icon: Icons.question_answer_outlined,
                    title: '追问训练',
                    subtitle: '模拟面试官追问，深入练习知识点',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => _startFollowUpTraining(context, domainTopics),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.trending_down_outlined,
                    title: '弱点训练包',
                    subtitle: '针对薄弱知识点进行专项训练',
                    color: AppColors.danger,
                    onTap: () => _startWeaknessTraining(context),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.local_fire_department_outlined,
                    title: '高频冲刺',
                    subtitle: '针对高频面试题进行强化训练',
                    color: AppColors.warning,
                    onTap: () => _startHighFrequencyTraining(context, domainTopics),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.work_outline,
                    title: '项目深挖',
                    subtitle: 'STAR法则练习，深入项目细节',
                    color: const Color(0xFF10B981),
                    onTap: () => _startProjectDig(context),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.architecture_outlined,
                    title: '系统设计',
                    subtitle: '系统设计面试练习',
                    color: const Color(0xFFF59E0B),
                    onTap: () => _startSystemDesign(context),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _PracticeModeCard(
                    icon: Icons.groups_outlined,
                    title: '模拟面试',
                    subtitle: '连续多题模式，模拟真实面试场景',
                    color: const Color(0xFFEF4444),
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
            .map<SimpleDialogOption>(
              (domain) => SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(ctx, domain.id);
                  onRandomQuiz(domain.id);
                },
                child: Text(domain.title),
              ),
            )
            .toList(),
      ),
    );
  }

  void _startFollowUpTraining(BuildContext context, List domainTopics) {
    // 筛选有追问的知识点
    final topicsWithFollowUps = domainTopics
        .where((topic) => topic.followUps.isNotEmpty)
        .toList();
    
    if (topicsWithFollowUps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前领域没有可追问的知识点')),
      );
      return;
    }

    // 随机选择最多5个知识点
    final shuffled = List.from(topicsWithFollowUps)..shuffle();
    final selectedTopics = shuffled.take(5).toList();
    final topicIds = selectedTopics.map((t) => t.id as String).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowUpTrainingPage(topicIds: topicIds),
      ),
    );
  }

  void _startWeaknessTraining(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WeaknessTrainingPage(currentDomainId: currentDomainId),
      ),
    );
  }

  void _startHighFrequencyTraining(BuildContext context, List domainTopics) {
    // 筛选高频知识点
    final highFrequencyTopics = domainTopics
        .where((topic) => topic.highFrequency)
        .toList();
    
    if (highFrequencyTopics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前领域没有高频知识点')),
      );
      return;
    }

    // 随机选择最多10个高频知识点
    final shuffled = List.from(highFrequencyTopics)..shuffle();
    final selectedTopics = shuffled.take(10).toList();
    final topicIds = selectedTopics.map((t) => t.id as String).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecallPage(topicIds: topicIds),
      ),
    );
  }

  void _startProjectDig(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProjectDigPage(),
      ),
    );
  }

  void _startSystemDesign(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SystemDesignPage(),
      ),
    );
  }
}

// ── 美化的空练习状态 ──────────────────────────────────────────────

class _EmptyPracticeState extends StatelessWidget {
  const _EmptyPracticeState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.psychology_alt_outlined,
                size: 48,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '暂无可练习的知识点',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              '知识点正在加载中，请稍等片刻再试',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
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
