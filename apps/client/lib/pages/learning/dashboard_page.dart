import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/widgets/route_editor_dialog.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.currentDomainId,
    required this.onDomainChanged,
    required this.onPractice,
    required this.onTopicTap,
    required this.onViewDomainCatalog,
    this.onReview,
    this.onMockInterview,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;
  final VoidCallback onPractice;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onViewDomainCatalog;
  final VoidCallback? onReview;
  final VoidCallback? onMockInterview;

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final l10n = context.watch<LocalizationProvider>();

    if (contentProvider.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.get('loading')),
          ],
        ),
      );
    }

    if (contentProvider.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              l10n.get('error'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(contentProvider.error!, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => contentProvider.loadContent(),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.get('retry')),
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

    final domainTopics = contentProvider.getTopicsByDomain(currentDomainId);
    final domainProgress = progressProvider.getDomainProgress(
      currentDomainId,
      contentProvider.topics.values.toList(),
    );
    final masteryPercent = domainProgress.masteryPercent;
    final topicCount = domainProgress.topicCount;
    final readiness = progressProvider.readinessScore(domainTopics);

    final recommendedTopics = progressProvider.getRecommendedTopics(
      currentDomainId,
      contentProvider.topics.values.toList(),
      settingsProvider.settings.recommendStrategy,
      lowScoreWeight: settingsProvider.settings.lowScoreWeight,
      overdueWeight: settingsProvider.settings.overdueWeight,
      highFrequencyWeight: settingsProvider.settings.highFrequencyWeight,
      pathOrderWeight: settingsProvider.settings.pathOrderWeight,
      notPracticedWeight: settingsProvider.settings.notPracticedWeight,
      prioritizePrerequisites:
          settingsProvider.settings.prioritizePrerequisites,
      allowSkipLowFrequency: settingsProvider.settings.allowSkipLowFrequency,
    );

    // 薄弱知识点 Top 5
    final weakTopics = progressProvider.getWeakTopics(domainTopics, limit: 5);
    // 最近练习
    final recentAttempts = progressProvider.recentAttempts.take(5).toList();
    // 到期复习
    final dueTopics = progressProvider.getTodayReviewTopics(domainTopics);

    // 三栏工作台布局
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1200;
          final isMedium = constraints.maxWidth >= 800 && constraints.maxWidth < 1200;
          
          if (isWide) {
            // 三栏布局
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧栏：今日复习队列、薄弱知识点TOP5
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _LeftPanel(
                      dueTopics: dueTopics,
                      weakTopics: weakTopics,
                      onTopicTap: onTopicTap,
                      onReview: onReview,
                      progressProvider: progressProvider,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 中间栏：当前学习路线、领域知识卡片
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _CenterPanel(
                      currentDomain: currentDomain,
                      domains: domains,
                      currentDomainId: currentDomainId,
                      recommendedTopics: recommendedTopics,
                      masteryPercent: masteryPercent,
                      topicCount: topicCount,
                      readiness: readiness,
                      streakDays: progressProvider.streakDays,
                      onDomainChanged: onDomainChanged,
                      onTopicTap: onTopicTap,
                      onViewDomainCatalog: onViewDomainCatalog,
                      onPractice: onPractice,
                      onReview: onReview,
                      onMockInterview: onMockInterview,
                      contentProvider: contentProvider,
                      progressProvider: progressProvider,
                      settingsProvider: settingsProvider,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 右侧栏：掌握度概览、下一步最佳行动、最近AI反馈
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _RightPanel(
                      currentDomainId: currentDomainId,
                      domains: domains,
                      masteryPercent: masteryPercent,
                      readiness: readiness,
                      weakTopics: weakTopics,
                      recentAttempts: recentAttempts,
                      onTopicTap: onTopicTap,
                      onDomainChanged: onDomainChanged,
                      progressProvider: progressProvider,
                      contentProvider: contentProvider,
                    ),
                  ),
                ),
              ],
            );
          } else if (isMedium) {
            // 两栏布局
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _LeftPanel(
                      dueTopics: dueTopics,
                      weakTopics: weakTopics,
                      onTopicTap: onTopicTap,
                      onReview: onReview,
                      progressProvider: progressProvider,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _CenterPanel(
                      currentDomain: currentDomain,
                      domains: domains,
                      currentDomainId: currentDomainId,
                      recommendedTopics: recommendedTopics,
                      masteryPercent: masteryPercent,
                      topicCount: topicCount,
                      readiness: readiness,
                      streakDays: progressProvider.streakDays,
                      onDomainChanged: onDomainChanged,
                      onTopicTap: onTopicTap,
                      onViewDomainCatalog: onViewDomainCatalog,
                      onPractice: onPractice,
                      onReview: onReview,
                      onMockInterview: onMockInterview,
                      contentProvider: contentProvider,
                      progressProvider: progressProvider,
                      settingsProvider: settingsProvider,
                    ),
                  ),
                ),
              ],
            );
          } else {
            // 单栏布局（移动端）
            return SingleChildScrollView(
              child: Column(
                children: [
                  _LeftPanel(
                    dueTopics: dueTopics,
                    weakTopics: weakTopics,
                    onTopicTap: onTopicTap,
                    onReview: onReview,
                    progressProvider: progressProvider,
                  ),
                  const SizedBox(height: 16),
                  _CenterPanel(
                    currentDomain: currentDomain,
                    domains: domains,
                    currentDomainId: currentDomainId,
                    recommendedTopics: recommendedTopics,
                    masteryPercent: masteryPercent,
                    topicCount: topicCount,
                    readiness: readiness,
                    streakDays: progressProvider.streakDays,
                    onDomainChanged: onDomainChanged,
                    onTopicTap: onTopicTap,
                    onViewDomainCatalog: onViewDomainCatalog,
                    onPractice: onPractice,
                    onReview: onReview,
                    onMockInterview: onMockInterview,
                    contentProvider: contentProvider,
                    progressProvider: progressProvider,
                    settingsProvider: settingsProvider,
                  ),
                  const SizedBox(height: 16),
                  _RightPanel(
                    currentDomainId: currentDomainId,
                    domains: domains,
                    masteryPercent: masteryPercent,
                    readiness: readiness,
                    weakTopics: weakTopics,
                    recentAttempts: recentAttempts,
                    onTopicTap: onTopicTap,
                    onDomainChanged: onDomainChanged,
                    progressProvider: progressProvider,
                    contentProvider: contentProvider,
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

}

// ── 下一步最佳行动组件 ──────────────────────────────────────────────

class _NextBestAction extends StatelessWidget {
  const _NextBestAction({
    required this.weakTopics,
    required this.onTopicTap,
  });

  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context) {
    if (weakTopics.isEmpty) {
      return const _EmptyState(message: '暂无推荐行动');
    }

    final nextTopic = weakTopics.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 16,
              color: AppColors.accent,
            ),
            const SizedBox(width: 8),
            Text(
              '推荐任务',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => onTopicTap(nextTopic.id),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nextTopic.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nextTopic.domain,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ActionTag(
                      icon: Icons.access_time,
                      text: '预计用时 25 分钟',
                    ),
                    const SizedBox(width: 12),
                    _ActionTag(
                      icon: Icons.quiz_outlined,
                      text: '考点 6 个',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => onTopicTap(nextTopic.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('开始学习'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionTag extends StatelessWidget {
  const _ActionTag({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── AI反馈组件 ──────────────────────────────────────────────

class _AIFeedbackItem extends StatelessWidget {
  const _AIFeedbackItem({
    required this.attempt,
  });

  final PracticeAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final score = attempt.score ?? 0;
    final feedbackType = score >= 85
        ? '表现优秀'
        : score >= 60
        ? '解题思路待优化'
        : '知识点掌握不足';
    final feedbackColor = score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;
    final feedbackIcon = score >= 85
        ? Icons.check_circle_outline
        : score >= 60
        ? Icons.lightbulb_outline
        : Icons.error_outline;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: feedbackColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              feedbackIcon,
              size: 16,
              color: feedbackColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feedbackType,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: feedbackColor,
                  ),
                ),
                Text(
                  attempt.question.isNotEmpty ? attempt.question : attempt.topicId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _timeAgo(attempt.createdAt),
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dateTime.month}/${dateTime.day}';
  }
}

// ── 领域切换下拉框 ──────────────────────────────────────────────

class _DomainDropdown extends StatelessWidget {
  const _DomainDropdown({
    required this.currentDomainId,
    required this.domains,
    required this.onChanged,
  });

  final String currentDomainId;
  final List<Domain> domains;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE0E0E0),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentDomainId,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: isDark ? Colors.white54 : const Color(0xFF999999),
          ),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : const Color(0xFF666666),
          ),
          items: domains.map((d) => DropdownMenuItem(
            value: d.id,
            child: Text(d.title),
          )).toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

// ── 掌握度概览组件 ──────────────────────────────────────────────

class _MasteryOverview extends StatelessWidget {
  const _MasteryOverview({
    required this.masteryPercent,
    required this.categories,
  });

  final int masteryPercent;
  final List<CategoryMastery> categories;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      children: [
        // 环形图
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: masteryPercent / 100,
                  strokeWidth: 8,
                  backgroundColor: AppColors.success.withValues(alpha: 0.1),
                  color: AppColors.success,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$masteryPercent',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    '掌握度',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // 分类掌握度
        Expanded(
          child: Column(
            children: categories.map((cat) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _MasteryStatItem(
                label: cat.name,
                value: '${cat.masteryPercent}%',
                color: cat.masteryPercent >= 80
                    ? AppColors.success
                    : cat.masteryPercent >= 60
                        ? AppColors.accent
                        : cat.masteryPercent > 0
                            ? AppColors.warning
                            : Colors.grey,
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }
}

class CategoryMastery {
  final String name;
  final int masteryPercent;
  
  const CategoryMastery({required this.name, required this.masteryPercent});
}

class _MasteryStatItem extends StatelessWidget {
  const _MasteryStatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── 掌握度统计组件 ──────────────────────────────────────────────

class _MasteryStats extends StatelessWidget {
  const _MasteryStats({
    required this.weakTopics,
  });

  final List<Topic> weakTopics;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _MasteryStatCard(
              title: 'Java',
              value: '72%',
              color: AppColors.success,
            ),
            const SizedBox(width: 12),
            _MasteryStatCard(
              title: 'Agent',
              value: '61%',
              color: AppColors.accent,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _MasteryStatCard(
              title: '算法',
              value: '55%',
              color: AppColors.warning,
            ),
            const SizedBox(width: 12),
            _MasteryStatCard(
              title: '前端',
              value: '66%',
              color: AppColors.accent,
            ),
          ],
        ),
      ],
    );
  }
}

class _MasteryStatCard extends StatelessWidget {
  const _MasteryStatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 领域知识卡片组件 ──────────────────────────────────────────────

class _DomainKnowledgeCard extends StatelessWidget {
  const _DomainKnowledgeCard({
    required this.domain,
    required this.masteryPercent,
    required this.onTap,
  });

  final Domain domain;
  final int masteryPercent;
  final VoidCallback onTap;

  IconData _getDomainIcon(String domainId) {
    final id = domainId.toLowerCase();
    if (id.contains('java')) return Icons.coffee;
    if (id.contains('agent') || id.contains('ai')) return Icons.smart_toy;
    if (id.contains('algorithm') || id.contains('算法')) return Icons.functions;
    if (id.contains('frontend') || id.contains('前端')) return Icons.code;
    if (id.contains('network') || id.contains('网络')) return Icons.language;
    if (id.contains('database') || id.contains('数据库')) return Icons.storage;
    if (id.contains('system') || id.contains('系统')) return Icons.computer;
    if (id.contains('security') || id.contains('安全')) return Icons.security;
    return Icons.book_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final domainColor = domain.color;
    final status = masteryPercent >= 80
        ? '掌握'
        : masteryPercent >= 60
        ? '良好'
        : masteryPercent >= 40
        ? '中等'
        : masteryPercent > 0
        ? '薄弱'
        : '未学';
    final statusColor = masteryPercent >= 80
        ? AppColors.success
        : masteryPercent >= 60
        ? AppColors.accent
        : masteryPercent >= 40
        ? AppColors.warning
        : masteryPercent > 0
        ? AppColors.danger
        : Colors.grey;
    
    final practiceCount = domain.topicCount * 3;
    final domainIcon = _getDomainIcon(domain.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        splashColor: domainColor.withValues(alpha: 0.08),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部：图标 + 标题
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: domainColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(domainIcon, size: 16, color: domainColor),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        domain.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1A1A1A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: isDark ? Colors.white24 : Colors.grey.shade400),
                  ],
                ),
                const SizedBox(height: 12),
                // 掌握度行
                Row(
                  children: [
                    Text(
                      '$masteryPercent%',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: domainColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: masteryPercent / 100,
                          backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
                          color: domainColor,
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 底部统计
                Row(
                  children: [
                    Text(
                      '${domain.topicCount} 考点',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$practiceCount 练习',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 统计数据块组件 ──────────────────────────────────────────────

// ── 学习路径项目组件 ──────────────────────────────────────────────

class _LearningPathItem extends StatefulWidget {
  const _LearningPathItem({
    required this.domain,
    required this.index,
    required this.masteryPercent,
    required this.isSelected,
    required this.onTap,
    this.onViewCatalog,
  });

  final Domain domain;
  final int index;
  final int masteryPercent;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onViewCatalog;

  @override
  State<_LearningPathItem> createState() => _LearningPathItemState();
}

class _LearningPathItemState extends State<_LearningPathItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = widget.masteryPercent >= 80
        ? '已完成'
        : widget.masteryPercent > 0
        ? '进行中'
        : '未开始';
    final statusColor = widget.masteryPercent >= 80
        ? AppColors.success
        : widget.masteryPercent > 0
        ? AppColors.accent
        : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? AppColors.accent.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isSelected
              ? AppColors.accent.withValues(alpha: 0.3)
              : (isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8)),
        ),
      ),
      child: Column(
        children: [
          // 主行
          InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 序号
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? AppColors.accent
                          : (isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: widget.isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 标题和状态
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.domain.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '进度 ${widget.masteryPercent}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '考点 ${widget.domain.topicCount}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 展开/折叠按钮
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 20,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的详情
          if (_isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // 描述
                  if (widget.domain.description.isNotEmpty) ...[
                    Text(
                      widget.domain.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 统计信息
                  Row(
                    children: [
                      _buildStatItem(
                        context,
                        icon: Icons.menu_book_outlined,
                        label: '知识点',
                        value: '${widget.domain.topicCount}',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        context,
                        icon: Icons.trending_up,
                        label: '掌握度',
                        value: '${widget.masteryPercent}%',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 16),
                      _buildStatItem(
                        context,
                        icon: Icons.category_outlined,
                        label: '分类',
                        value: '${widget.domain.categories.length}',
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: widget.masteryPercent / 100,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                      color: AppColors.accent,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 查看详情按钮
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onViewCatalog ?? widget.onTap,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('查看知识目录'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: isDark ? Colors.white54 : Colors.grey),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── 复习项目组件 ──────────────────────────────────────────────

class _WeakTopicItem extends StatelessWidget {
  const _WeakTopicItem({
    required this.topic,
    required this.score,
    required this.onTap,
  });

  final Topic topic;
  final int score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scoreColor = score >= 60 ? AppColors.warning : AppColors.danger;
    final level = score >= 80
        ? '高'
        : score >= 60
        ? '中'
        : '低';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  level,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: scoreColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    topic.domain,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$score%',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: scoreColor,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
              child: const Text('去练习', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 复习项目组件 ──────────────────────────────────────────────

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({
    required this.topic,
    required this.score,
    required this.onTap,
  });

  final Topic topic;
  final int score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scoreColor = score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;
    
    // 模拟复习时间（实际应从数据中获取）
    final reviewHour = 10 + (topic.title.hashCode % 8);
    final isToday = topic.title.hashCode % 2 == 0;
    final timeText = isToday ? '今天 $reviewHour:00' : '明天 ${(reviewHour - 2).clamp(8, 11)}:00';
    final timeColor = isToday ? const Color(0xFFE5484D) : const Color(0xFF666666);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // 分数
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: scoreColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 标题和领域
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${topic.domain} · ${topic.domain}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 时间
            Text(
              timeText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: timeColor,
              ),
            ),
            const SizedBox(width: 8),
            // 复习按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                '复习',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 通用面板卡片 ──────────────────────────────────────────────

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.child,
    this.trailing,
    this.headerTrailing,
    this.icon,
    this.onTrailingTap,
  });

  final String title;
  final Widget child;
  final String? trailing;
  final Widget? headerTrailing;
  final IconData? icon;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final borderColor = Theme.of(context).colorScheme.outline;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? AppColors.cardShadowDark : AppColors.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              if (headerTrailing != null) ...[
                headerTrailing!,
                const SizedBox(width: 8),
              ],
              if (trailing != null)
                GestureDetector(
                  onTap: onTrailingTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trailing!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                        if (onTrailingTap != null) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            size: 14,
                            color: AppColors.accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── 空状态组件 ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ── 左侧面板：今日复习队列、薄弱知识点TOP5 ──────────────────────────────────────────────

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({
    required this.dueTopics,
    required this.weakTopics,
    required this.onTopicTap,
    required this.onReview,
    required this.progressProvider,
  });

  final List<Topic> dueTopics;
  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;
  final VoidCallback? onReview;
  final ProgressProvider progressProvider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 今日复习队列
        _PanelCard(
          title: '今日复习队列',
          icon: Icons.replay_outlined,
          trailing: '${dueTopics.length}',
          headerTrailing: Text(
            '到期时间',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : const Color(0xFF999999),
            ),
          ),
          child: Column(
            children: [
              if (dueTopics.isEmpty)
                const _EmptyState(message: '暂无到期内容')
              else
                ...dueTopics.take(5).map((topic) {
                  final progress = progressProvider.getTopicProgress(topic.id);
                  final score = progress?.score ?? 0;
                  return _ReviewItem(
                    topic: topic,
                    score: score,
                    onTap: () => onTopicTap(topic.id),
                  );
                }),
              if (dueTopics.length > 5)
                TextButton(
                  onPressed: onReview,
                  child: const Text('查看全部复习'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 薄弱知识点TOP5
        _PanelCard(
          title: '薄弱知识点 TOP 5',
          icon: Icons.trending_down_outlined,
          trailing: '${weakTopics.length}',
          child: Column(
            children: [
              if (weakTopics.isEmpty)
                const _EmptyState(message: '暂无薄弱项')
              else
                ...weakTopics.map((topic) {
                  final progress = progressProvider.getTopicProgress(topic.id);
                  final score = progress?.score ?? 0;
                  return _WeakTopicItem(
                    topic: topic,
                    score: score,
                    onTap: () => onTopicTap(topic.id),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 中间面板：当前学习路线、领域知识卡片 ──────────────────────────────────────────────

class _CenterPanel extends StatelessWidget {
  const _CenterPanel({
    required this.currentDomain,
    required this.domains,
    required this.currentDomainId,
    required this.recommendedTopics,
    required this.masteryPercent,
    required this.topicCount,
    required this.readiness,
    required this.streakDays,
    required this.onDomainChanged,
    required this.onTopicTap,
    required this.onViewDomainCatalog,
    required this.onPractice,
    required this.onReview,
    required this.onMockInterview,
    required this.contentProvider,
    required this.progressProvider,
    required this.settingsProvider,
  });

  final Domain? currentDomain;
  final List<Domain> domains;
  final String currentDomainId;
  final List<Topic> recommendedTopics;
  final int masteryPercent;
  final int topicCount;
  final int readiness;
  final int streakDays;
  final ValueChanged<String> onDomainChanged;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onViewDomainCatalog;
  final VoidCallback onPractice;
  final VoidCallback? onReview;
  final VoidCallback? onMockInterview;
  final ContentProvider contentProvider;
  final ProgressProvider progressProvider;
  final SettingsProvider settingsProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前学习路线
        _PanelCard(
          title: '当前学习路线',
          icon: Icons.route_outlined,
          trailing: '切换路线',
          onTrailingTap: () => _showRouteSelector(context),
          child: Column(
            children: [
              if (domains.isEmpty)
                const _EmptyState(message: '暂无学习路线')
              else
                ...domains.take(5).toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final domain = entry.value;
                  final dp = progressProvider.getDomainProgress(
                    domain.id,
                    contentProvider.topics.values.toList(),
                  );
                  return _LearningPathItem(
                    domain: domain,
                    index: index,
                    masteryPercent: dp.masteryPercent,
                    isSelected: domain.id == currentDomainId,
                    onTap: () {
                      onDomainChanged(domain.id);
                      if (contentProvider.getLoadedTopicCount(domain.id) == 0) {
                        contentProvider.loadDomainTopics(domain.id);
                      }
                    },
                    onViewCatalog: () {
                      onDomainChanged(domain.id);
                      if (contentProvider.getLoadedTopicCount(domain.id) == 0) {
                        contentProvider.loadDomainTopics(domain.id);
                      }
                      onViewDomainCatalog(domain.id);
                    },
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 领域知识卡片
        _PanelCard(
          title: '领域知识卡片',
          icon: Icons.school_outlined,
          trailing: '管理领域',
          onTrailingTap: () => _showManageDomains(context),
          child: Column(
            children: [
              if (domains.isEmpty)
                const _EmptyState(message: '暂无领域数据')
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 根据宽度决定每行几个卡片
                    final cardWidth = constraints.maxWidth > 900 
                        ? (constraints.maxWidth - 36) / 4  // 一行4个
                        : constraints.maxWidth > 600 
                            ? (constraints.maxWidth - 24) / 3  // 一行3个
                            : (constraints.maxWidth - 12) / 2;  // 一行2个
                    
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: domains.take(8).map((domain) {
                        final dp = progressProvider.getDomainProgress(
                          domain.id,
                          contentProvider.topics.values.toList(),
                        );
                        return SizedBox(
                          width: cardWidth,
                          child: _DomainKnowledgeCard(
                            domain: domain,
                            masteryPercent: dp.masteryPercent,
                            onTap: () {
                              onDomainChanged(domain.id);
                              if (contentProvider.getLoadedTopicCount(domain.id) == 0) {
                                contentProvider.loadDomainTopics(domain.id);
                              }
                              onViewDomainCatalog(domain.id);
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showRouteSelector(BuildContext context) {
    final routes = [
      LearningRoute(
        id: 'java',
        name: 'Java 后端开发',
        description: 'Java 核心、Spring、数据库、微服务',
        domainIds: domains.take(5).map((d) => d.id).toList(),
        isDefault: true,
      ),
      LearningRoute(
        id: 'frontend',
        name: '前端开发',
        description: 'JavaScript、React、Vue、性能优化',
        domainIds: domains.take(4).map((d) => d.id).toList(),
        isDefault: true,
      ),
      LearningRoute(
        id: 'agent',
        name: 'Agent 开发',
        description: 'AI Agent、RAG、Prompt Engineering',
        domainIds: domains.take(3).map((d) => d.id).toList(),
        isDefault: true,
      ),
    ];

    showDialog(
      context: context,
      builder: (ctx) => _RouteSelectorDialog(
        routes: routes,
        currentRouteId: currentDomainId,
        availableDomains: domains,
        onRouteSelected: (route) {
          if (route.domainIds.isNotEmpty) {
            onDomainChanged(route.domainIds.first);
          }
        },
      ),
    );
  }

  void _showManageDomains(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ManageDomainsDialog(
        domains: domains,
        disabledDomainIds: {},
        onToggleDomain: (domainId) {
          // TODO: 保存禁用的领域到本地存储
        },
      ),
    );
  }
}

// ── 路线选择对话框 ──────────────────────────────────────────────

class _RouteSelectorDialog extends StatefulWidget {
  const _RouteSelectorDialog({
    required this.routes,
    required this.currentRouteId,
    required this.onRouteSelected,
    required this.availableDomains,
  });

  final List<LearningRoute> routes;
  final String? currentRouteId;
  final ValueChanged<LearningRoute> onRouteSelected;
  final List<Domain> availableDomains;

  @override
  State<_RouteSelectorDialog> createState() => _RouteSelectorDialogState();
}

class _RouteSelectorDialogState extends State<_RouteSelectorDialog> {
  late List<LearningRoute> _routes;

  @override
  void initState() {
    super.initState();
    _routes = List.from(widget.routes);
  }

  void _addCustomRoute(LearningRoute route) {
    setState(() => _routes.add(route));
  }

  void _deleteRoute(String routeId) {
    setState(() => _routes.removeWhere((r) => r.id == routeId));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text('选择学习路线', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            
            // 路线列表
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: Column(
                  children: _routes.map((route) {
                    final isSelected = route.id == widget.currentRouteId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          widget.onRouteSelected(route);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.accent.withValues(alpha: 0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.accent
                                  : (isDark ? const Color(0xFF30363D) : const Color(0xFFE0E0E0)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(route.name, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? AppColors.accent : null)),
                                        if (!route.isDefault) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.accent.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: const Text('自定义', style: TextStyle(fontSize: 9, color: AppColors.accent)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (route.description.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(route.description, style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey)),
                                      ),
                                  ],
                                ),
                              ),
                              if (!route.isDefault)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  color: Colors.red.shade300,
                                  onPressed: () => _deleteRoute(route.id),
                                ),
                              if (isSelected) const Icon(Icons.check_circle, color: AppColors.accent),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 创建自定义路线
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => RouteEditorDialog(
                      availableDomains: widget.availableDomains
                          .map((d) => DomainItem(id: d.id, title: d.title))
                          .toList(),
                      onSave: _addCustomRoute,
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('创建自定义路线'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 管理领域对话框 ──────────────────────────────────────────────

class _ManageDomainsDialog extends StatefulWidget {
  const _ManageDomainsDialog({
    required this.domains,
    required this.disabledDomainIds,
    required this.onToggleDomain,
  });

  final List<Domain> domains;
  final Set<String> disabledDomainIds;
  final ValueChanged<String> onToggleDomain;

  @override
  State<_ManageDomainsDialog> createState() => _ManageDomainsDialogState();
}

class _ManageDomainsDialogState extends State<_ManageDomainsDialog> {
  late Set<String> _disabledIds;

  @override
  void initState() {
    super.initState();
    _disabledIds = Set.from(widget.disabledDomainIds);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school_outlined, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text('管理领域', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '切换开关来启用/禁用领域',
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.grey),
            ),
            const SizedBox(height: 16),
            
            // 领域列表
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: Column(
                  children: widget.domains.map((domain) {
                    final isDisabled = _disabledIds.contains(domain.id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDisabled
                            ? (isDark ? const Color(0xFF111111) : Colors.grey.shade100)
                            : (isDark ? const Color(0xFF161B22) : Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDisabled
                              ? (isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200)
                              : (isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  domain.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDisabled
                                        ? Colors.grey
                                        : (isDark ? Colors.white : const Color(0xFF1A1A1A)),
                                  ),
                                ),
                                Text(
                                  '${domain.topicCount} 个知识点',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDisabled ? Colors.grey : (isDark ? Colors.white54 : Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: !isDisabled,
                            onChanged: (value) {
                              setState(() {
                                if (isDisabled) {
                                  _disabledIds.remove(domain.id);
                                } else {
                                  _disabledIds.add(domain.id);
                                }
                                widget.onToggleDomain(domain.id);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 说明
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '禁用的领域不会在首页显示，但内容不会被删除',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 右侧面板 ──────────────────────────────────────────────

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.currentDomainId,
    required this.domains,
    required this.masteryPercent,
    required this.readiness,
    required this.weakTopics,
    required this.recentAttempts,
    required this.onTopicTap,
    required this.onDomainChanged,
    required this.progressProvider,
    required this.contentProvider,
  });

  final String currentDomainId;
  final List<Domain> domains;
  final int masteryPercent;
  final int readiness;
  final List<Topic> weakTopics;
  final List<PracticeAttempt> recentAttempts;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onDomainChanged;
  final ProgressProvider progressProvider;
  final ContentProvider contentProvider;

  @override
  Widget build(BuildContext context) {
    // 获取掌握度趋势数据
    final trendData = progressProvider.getMasteryTrend();
    
    // 计算当前领域的分类掌握度
    final domainTopics = contentProvider.getTopicsByDomain(currentDomainId);
    
    // 按分类计算掌握度
    final categoryMap = <String, List<Topic>>{};
    for (final topic in domainTopics) {
      categoryMap.putIfAbsent(topic.category, () => []).add(topic);
    }
    
    final categories = categoryMap.entries.map((entry) {
      final topics = entry.value;
      final avgScore = topics.isEmpty ? 0 : 
        topics.fold<int>(0, (sum, t) {
          final score = progressProvider.getTopicProgress(t.id)?.score ?? 0;
          return sum + score;
        }) ~/ topics.length;
      return CategoryMastery(name: entry.key, masteryPercent: avgScore);
    }).toList()
      ..sort((a, b) => b.masteryPercent.compareTo(a.masteryPercent));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 掌握度概览
        _PanelCard(
          title: '掌握度概览',
          icon: Icons.pie_chart_outline,
          headerTrailing: _DomainDropdown(
            currentDomainId: currentDomainId,
            domains: domains,
            onChanged: onDomainChanged,
          ),
          child: Column(
            children: [
              _MasteryOverview(
                masteryPercent: masteryPercent,
                categories: categories.take(4).toList(),
              ),
              const SizedBox(height: 16),
              _MasteryStats(
                weakTopics: weakTopics,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 掌握度趋势
        _PanelCard(
          title: '掌握度趋势（近 7 天）',
          icon: Icons.trending_up_outlined,
          child: _MasteryTrendChart(trendData: trendData),
        ),
        const SizedBox(height: 16),
        // 下一步最佳行动
        _PanelCard(
          title: '下一步最佳行动',
          icon: Icons.lightbulb_outline,
          child: _NextBestAction(
            weakTopics: weakTopics,
            onTopicTap: onTopicTap,
          ),
        ),
        const SizedBox(height: 16),
        // 备选行动
        _PanelCard(
          title: '备选行动',
          icon: Icons.list_alt_outlined,
          child: _AlternativeActions(
            weakTopics: weakTopics,
            onTopicTap: onTopicTap,
          ),
        ),
        const SizedBox(height: 16),
        // 最近AI反馈
        _PanelCard(
          title: '最近 AI 反馈',
          icon: Icons.auto_awesome_outlined,
          trailing: '查看全部',
          child: Column(
            children: [
              if (recentAttempts.isEmpty)
                const _EmptyState(message: '暂无反馈记录')
              else
                ...recentAttempts.take(3).map((attempt) {
                  return _AIFeedbackItem(
                    attempt: attempt,
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 掌握度趋势图表 ──────────────────────────────────────────────

class _MasteryTrendChart extends StatelessWidget {
  const _MasteryTrendChart({required this.trendData});

  final List<double> trendData;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dates = List.generate(7, (i) => 
      '${(now.month).toString().padLeft(2, '0')}-${(now.day - 6 + i).toString().padLeft(2, '0')}'
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 图表区域
        SizedBox(
          height: 120,
          child: CustomPaint(
            size: const Size(double.infinity, 120),
            painter: _LineChartPainter(data: trendData),
          ),
        ),
        const SizedBox(height: 8),
        // X轴标签
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: dates.map((date) => Text(
            date,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )).toList(),
        ),
      ],
    );
  }
}

// 简单的折线图绘制器
class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.data});

  final List<double> data;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF3078F0)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final stepX = width / (data.length - 1);

    // 绘制线条
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = height - (data[i] / 100 * height);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // 绘制数据点
    final dotPaint = Paint()
      ..color = const Color(0xFF3078F0)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = height - (data[i] / 100 * height);
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 备选行动列表 ──────────────────────────────────────────────

class _AlternativeActions extends StatelessWidget {
  const _AlternativeActions({
    required this.weakTopics,
    required this.onTopicTap,
  });

  final List<Topic> weakTopics;
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context) {
    if (weakTopics.isEmpty) {
      return const _EmptyState(message: '暂无备选行动');
    }

    // 取第2-4个薄弱知识点作为备选
    final alternatives = weakTopics.skip(1).take(3).toList();

    return Column(
      children: alternatives.map((topic) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onTopicTap(topic.id),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    topic.id.contains('review') 
                        ? Icons.replay_outlined 
                        : Icons.school_outlined,
                    size: 16,
                    color: const Color(0xFF3078F0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${topic.id.contains('review') ? '复习' : '学习'}：${topic.title}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          topic.domain,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}


