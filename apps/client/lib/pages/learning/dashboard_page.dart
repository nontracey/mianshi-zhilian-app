import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
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
    final reviewCount = progressProvider.getReviewCount(currentDomainId);
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
                      masteryPercent: masteryPercent,
                      readiness: readiness,
                      weakTopics: weakTopics,
                      recentAttempts: recentAttempts,
                      onTopicTap: onTopicTap,
                      progressProvider: progressProvider,
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
                    masteryPercent: masteryPercent,
                    readiness: readiness,
                    weakTopics: weakTopics,
                    recentAttempts: recentAttempts,
                    onTopicTap: onTopicTap,
                    progressProvider: progressProvider,
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  String _strategyLabel(String strategy) => switch (strategy) {
    'smart' => '智能推荐',
    'path-order' => '路径顺序',
    'high-frequency' => '高频优先',
    'review-first' => '复习优先',
    _ => '低分优先',
  };
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
    final scoreColor = score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;
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

// ── 掌握度概览组件 ──────────────────────────────────────────────

class _MasteryOverview extends StatelessWidget {
  const _MasteryOverview({
    required this.masteryPercent,
    required this.readiness,
  });

  final int masteryPercent;
  final int readiness;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        // 顶部：总体下拉选择器
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2332) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? const Color(0xFF263238) : const Color(0xFFE0E0E0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '总体',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : const Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 14,
                    color: isDark ? Colors.white54 : const Color(0xFF999999),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 环形图 + 统计
        Row(
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
                      const Text(
                        '综合掌握度',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // 统计信息
            Expanded(
              child: Column(
                children: [
                  _MasteryStatItem(
                    label: '熟练',
                    value: '23%',
                    color: AppColors.success,
                    dotColor: AppColors.success,
                  ),
                  const SizedBox(height: 6),
                  _MasteryStatItem(
                    label: '掌握',
                    value: '45%',
                    color: AppColors.accent,
                    dotColor: AppColors.accent,
                  ),
                  const SizedBox(height: 6),
                  _MasteryStatItem(
                    label: '薄弱',
                    value: '22%',
                    color: AppColors.warning,
                    dotColor: AppColors.warning,
                  ),
                  const SizedBox(height: 6),
                  _MasteryStatItem(
                    label: '未学',
                    value: '10%',
                    color: Colors.grey,
                    dotColor: Colors.grey,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MasteryStatItem extends StatelessWidget {
  const _MasteryStatItem({
    required this.label,
    required this.value,
    required this.color,
    required this.dotColor,
  });

  final String label;
  final String value;
  final Color color;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
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

  // 根据领域名称返回特定图标
  IconData _getDomainIcon(String domainId) {
    final id = domainId.toLowerCase();
    if (id.contains('java')) return Icons.coffee; // Java 咖啡杯
    if (id.contains('agent') || id.contains('ai')) return Icons.smart_toy; // Agent 机器人
    if (id.contains('algorithm') || id.contains('算法')) return Icons.functions; // 算法 Σ
    if (id.contains('frontend') || id.contains('前端')) return Icons.code; // 前端 代码
    if (id.contains('network') || id.contains('网络')) return Icons.language; // 网络 地球
    if (id.contains('database') || id.contains('数据库')) return Icons.storage; // 数据库
    if (id.contains('system') || id.contains('系统')) return Icons.computer; // 系统
    if (id.contains('security') || id.contains('安全')) return Icons.security; // 安全
    return Icons.book_outlined; // 默认
  }

  @override
  Widget build(BuildContext context) {
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
    
    // 模拟练习题数（实际应从数据中获取）
    final practiceCount = domain.topicCount * 3;
    final domainIcon = _getDomainIcon(domain.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    child: Icon(
                      domainIcon,
                      size: 16,
                      color: domainColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    domain.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 状态标签
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
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '掌握度',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '$masteryPercent%',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: domainColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: masteryPercent / 100,
              backgroundColor: domainColor.withValues(alpha: 0.1),
              color: domainColor,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 12),
            // 考点和练习题数
            Row(
              children: [
                Text(
                  '考点 ${domain.topicCount}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '练习 $practiceCount 题',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 继续学习按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  side: BorderSide(color: domainColor.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  '继续学习',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: domainColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 统计数据块组件 ──────────────────────────────────────────────

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.value,
    required this.label,
    this.color = Colors.white,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 28,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    ),
  );
}

// ── 学习路径项目组件 ──────────────────────────────────────────────

class _LearningPathItem extends StatelessWidget {
  const _LearningPathItem({
    required this.domain,
    required this.index,
    required this.masteryPercent,
    required this.isSelected,
    required this.onTap,
  });

  final Domain domain;
  final int index;
  final int masteryPercent;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = masteryPercent >= 80
        ? '已完成'
        : masteryPercent > 0
        ? '进行中'
        : '未开始';
    final statusColor = masteryPercent >= 80
        ? AppColors.success
        : masteryPercent > 0
        ? AppColors.accent
        : Colors.grey;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        domain.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
                        '进度 $masteryPercent%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '考点 ${domain.topicCount}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 工作台头部组件 ──────────────────────────────────────────────

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({
    required this.domainTitle,
    required this.masteryPercent,
    required this.topicCount,
    required this.readiness,
    required this.streakDays,
    required this.onPractice,
    this.onReview,
    this.onMockInterview,
  });

  final String domainTitle;
  final int masteryPercent;
  final int topicCount;
  final int readiness;
  final int streakDays;
  final VoidCallback onPractice;
  final VoidCallback? onReview;
  final VoidCallback? onMockInterview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            const Color(0xFF0F3460),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标签行
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '当前领域：$domainTitle',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (streakDays > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '连续 $streakDays 天',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '把面试知识练成可以讲出来的答案',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '先充分学习知识解释，再进入复述训练，由 AI 按 rubric 评分、纠错和补充。',
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          // 统计数据行
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              final stats = [
                _StatBlock(
                  value: '$masteryPercent%',
                  label: '掌握度',
                  color: AppColors.success,
                ),
                _StatBlock(
                  value: '$readiness',
                  label: '就绪度',
                  color: AppColors.accent,
                ),
                _StatBlock(
                  value: '$topicCount',
                  label: '知识点',
                  color: Colors.white,
                ),
              ];
              if (isNarrow) {
                return Wrap(spacing: 20, runSpacing: 12, children: stats);
              }
              return Row(children: stats);
            },
          ),
          const SizedBox(height: 16),
          // 操作按钮行
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onPractice,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('开始复述'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bgDark,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
              if (onReview != null)
                OutlinedButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.replay_outlined, size: 18),
                  label: const Text('今日复习'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                ),
              if (onMockInterview != null)
                OutlinedButton.icon(
                  onPressed: onMockInterview,
                  icon: const Icon(Icons.psychology_outlined, size: 18),
                  label: const Text('模拟面试'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 薄弱知识点组件 ──────────────────────────────────────────────

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
    final now = DateTime.now();
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
  });

  final String title;
  final Widget child;
  final String? trailing;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15202E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              if (headerTrailing != null) ...[
                headerTrailing!,
                const SizedBox(width: 8),
              ],
              if (trailing != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3078F0).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    trailing!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3078F0),
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
        // 顶部工作台
        _WorkbenchHeader(
          domainTitle: currentDomain?.title ?? '',
          masteryPercent: masteryPercent,
          topicCount: topicCount,
          readiness: readiness,
          streakDays: streakDays,
          onPractice: onPractice,
          onReview: onReview,
          onMockInterview: onMockInterview,
        ),
        const SizedBox(height: 16),
        // 当前学习路线
        _PanelCard(
          title: '当前学习路线',
          trailing: '切换路线',
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
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 领域知识卡片
        _PanelCard(
          title: '领域知识卡片',
          trailing: '管理领域',
          child: Column(
            children: [
              if (domains.isEmpty)
                const _EmptyState(message: '暂无领域数据')
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: domains.take(6).map((domain) {
                    final dp = progressProvider.getDomainProgress(
                      domain.id,
                      contentProvider.topics.values.toList(),
                    );
                    return _DomainKnowledgeCard(
                      domain: domain,
                      masteryPercent: dp.masteryPercent,
                      onTap: () {
                        onDomainChanged(domain.id);
                        if (contentProvider.getLoadedTopicCount(domain.id) == 0) {
                          contentProvider.loadDomainTopics(domain.id);
                        }
                        onViewDomainCatalog(domain.id);
                      },
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 右侧面板：掌握度概览、下一步最佳行动、最近AI反馈 ──────────────────────────────────────────────

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.masteryPercent,
    required this.readiness,
    required this.weakTopics,
    required this.recentAttempts,
    required this.onTopicTap,
    required this.progressProvider,
  });

  final int masteryPercent;
  final int readiness;
  final List<Topic> weakTopics;
  final List<PracticeAttempt> recentAttempts;
  final ValueChanged<String> onTopicTap;
  final ProgressProvider progressProvider;

  @override
  Widget build(BuildContext context) {
    // 获取掌握度趋势数据
    final trendData = progressProvider.getMasteryTrend();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 掌握度概览
        _PanelCard(
          title: '掌握度概览',
          child: Column(
            children: [
              _MasteryOverview(
                masteryPercent: masteryPercent,
                readiness: readiness,
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
          child: _MasteryTrendChart(trendData: trendData),
        ),
        const SizedBox(height: 16),
        // 下一步最佳行动
        _PanelCard(
          title: '下一步最佳行动',
          child: _NextBestAction(
            weakTopics: weakTopics,
            onTopicTap: onTopicTap,
          ),
        ),
        const SizedBox(height: 16),
        // 备选行动
        _PanelCard(
          title: '备选行动',
          child: _AlternativeActions(
            weakTopics: weakTopics,
            onTopicTap: onTopicTap,
          ),
        ),
        const SizedBox(height: 16),
        // 最近AI反馈
        _PanelCard(
          title: '最近 AI 反馈',
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


