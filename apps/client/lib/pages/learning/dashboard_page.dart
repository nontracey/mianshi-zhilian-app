import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/widgets/skeleton_loader.dart';
import 'dashboard_panels.dart';

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
    this.routeTopicIds,
    this.routeDomainIds,
    this.routeModeEnabled = false,
    this.onRouteModeChanged,
    this.onPrepNavigation,
    this.onNavigateToCatalog,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;
  final VoidCallback onPractice;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onViewDomainCatalog;
  final VoidCallback? onReview;
  final VoidCallback? onMockInterview;
  final VoidCallback? onPrepNavigation;
  final VoidCallback? onNavigateToCatalog;
  final List<String>? routeTopicIds;
  final List<String>? routeDomainIds;
  final bool routeModeEnabled;
  final VoidCallback? onRouteModeChanged;

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final l10n = context.watch<LocalizationProvider>();

    if (contentProvider.isLoading || contentProvider.isLoadingTopics) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            SkeletonCard(height: 160),
            const SizedBox(height: 16),
            SkeletonMetricGrid(),
            const SizedBox(height: 16),
            SkeletonCard(height: 120),
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

    final isCrossDomainRoute = routeModeEnabled &&
        routeDomainIds != null &&
        routeDomainIds!.length > 1 &&
        routeTopicIds != null &&
        routeTopicIds!.isNotEmpty;

    List<Topic> scopedTopics;
    if (isCrossDomainRoute) {
      scopedTopics = routeTopicIds!
          .map((id) => contentProvider.findTopic(id))
          .whereType<Topic>()
          .toList();
    } else if (routeTopicIds != null) {
      scopedTopics = domainTopics.where((t) => routeTopicIds!.contains(t.id)).toList();
    } else {
      scopedTopics = domainTopics;
    }

    if (!contentProvider.isLoadingTopics && scopedTopics.isEmpty && domainTopics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              contentProvider.topicLoadFailures.isNotEmpty
                  ? l10n.get('knowledge_point_loading_fail')
                  : l10n.get('temporary_no_knowledge_point'),
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (contentProvider.topicLoadFailures.isNotEmpty) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => contentProvider.loadDomainTopics(currentDomainId),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.get('retry')),
              ),
            ],
          ],
        ),
      );
    }

    final isRouteFocused = routeModeEnabled && routeTopicIds != null && routeTopicIds!.isNotEmpty;

    final domainProgress = isCrossDomainRoute || isRouteFocused
        ? (masteryPercent: _calcMasteryPercent(scopedTopics, progressProvider), topicCount: scopedTopics.length)
        : progressProvider.getDomainProgress(
            currentDomainId,
            contentProvider.topics.values.toList(),
          );
    final masteryPercent = domainProgress.masteryPercent;
    final topicCount = domainProgress.topicCount;
    final readiness = progressProvider.readinessScore(scopedTopics);

    final recommendedTopics = progressProvider.getRecommendedTopics(
      currentDomainId,
      isCrossDomainRoute || isRouteFocused ? scopedTopics : contentProvider.topics.values.toList(),
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

    final plan = progressProvider.prepPlan;

    final weakTopics = progressProvider.getWeakTopics(scopedTopics, limit: 5);
    final recentAttempts = progressProvider.recentAttempts.take(5).toList();
    final dueTopics = progressProvider.getTodayReviewTopics(scopedTopics);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (!isRouteFocused && plan.hasTarget)
            _buildTargetBanner(context, plan),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1200;
          final isMedium =
              constraints.maxWidth >= 800 && constraints.maxWidth < 1200;

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
                       child: LeftPanel(
                         dueTopics: dueTopics,
                         weakTopics: weakTopics,
                         routeTopicIds: routeTopicIds,
                         isRouteMode: routeModeEnabled && routeTopicIds != null && routeTopicIds!.isNotEmpty,
                         routeFirstTopicId: routeTopicIds?.isNotEmpty == true ? routeTopicIds!.first : null,
                         onStartLearning: onNavigateToCatalog,
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
                      child: CenterPanel(
                        currentDomain: currentDomain,
                        allDomains: domains,
                        currentDomainId: currentDomainId,
                        recommendedTopics: recommendedTopics,
                        masteryPercent: masteryPercent,
                        topicCount: topicCount,
                        readiness: readiness,
                        streakDays: progressProvider.streakDays,
                        routeModeEnabled: routeModeEnabled,
                        onRouteModeChanged: onRouteModeChanged,
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
                      child: RightPanel(
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
                         routeTopicIds: isCrossDomainRoute ? routeTopicIds : null,
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
                      child: LeftPanel(
                         dueTopics: dueTopics,
                         weakTopics: weakTopics,
                         routeTopicIds: routeTopicIds,
                         isRouteMode: routeModeEnabled && routeTopicIds != null && routeTopicIds!.isNotEmpty,
                         routeFirstTopicId: routeTopicIds?.isNotEmpty == true ? routeTopicIds!.first : null,
                         onStartLearning: onNavigateToCatalog,
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
                       child: Column(
                        children: [
                          CenterPanel(
                            currentDomain: currentDomain,
                            allDomains: domains,
                            currentDomainId: currentDomainId,
                            recommendedTopics: recommendedTopics,
                            masteryPercent: masteryPercent,
                            topicCount: topicCount,
                            readiness: readiness,
                            streakDays: progressProvider.streakDays,
                            routeModeEnabled: routeModeEnabled,
                            onRouteModeChanged: onRouteModeChanged,
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
                          RightPanel(
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
                             routeTopicIds: isCrossDomainRoute ? routeTopicIds : null,
                           ),
                        ],
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
                  LeftPanel(
                    dueTopics: dueTopics,
                    weakTopics: weakTopics,
                    routeTopicIds: routeTopicIds,
                    isRouteMode: routeModeEnabled && routeTopicIds != null && routeTopicIds!.isNotEmpty,
                         routeFirstTopicId: routeTopicIds?.isNotEmpty == true ? routeTopicIds!.first : null,
                         onStartLearning: onNavigateToCatalog,
                    onTopicTap: onTopicTap,
                    onReview: onReview,
                    progressProvider: progressProvider,
                  ),
                  const SizedBox(height: 16),
                  CenterPanel(
                    currentDomain: currentDomain,
                    allDomains: domains,
                    currentDomainId: currentDomainId,
                    recommendedTopics: recommendedTopics,
                    masteryPercent: masteryPercent,
                    topicCount: topicCount,
                    readiness: readiness,
                    streakDays: progressProvider.streakDays,
                    routeModeEnabled: routeModeEnabled,
                    onRouteModeChanged: onRouteModeChanged,
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
                  RightPanel(
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
                    routeTopicIds: isCrossDomainRoute ? routeTopicIds : null,
                  ),
                ],
              ),
            );
          }
        },
      ),
    ),
  ],
),
);
  }

  Widget _buildTargetBanner(BuildContext context, PrepPlan plan) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final interviewDate = plan.interviewDate;
    final days = interviewDate != null
        ? interviewDate.difference(DateTime.now()).inDays + 1
        : null;

    return GestureDetector(
      onTap: onPrepNavigation,
      child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.08),
            isDark ? const Color(0xFF1A1D23) : const Color(0xFFF8F9FA),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.work_outline, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.targetRole.isNotEmpty
                      ? '${plan.targetRole}${plan.techStack.isNotEmpty ? ' · ${plan.techStack}' : ''}'
                      : l10n.get('interview_target'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  days != null
                      ? (days > 0 ? l10n.getp('days_until_interview', {'days': days}) : l10n.get('interview_day_already_to'))
                      : l10n.get('interview_target_set'),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (days != null && days > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$days',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  static int _calcMasteryPercent(List<Topic> topics, ProgressProvider progress) {
    if (topics.isEmpty) return 0;
    double totalScore = 0;
    int count = 0;
    for (final topic in topics) {
      final score = progress.getTopicProgress(topic.id)?.score ?? 0;
      if (score > 0) {
        totalScore += score;
        count++;
      }
    }
    if (count == 0) return 0;
    final avgScore = totalScore / count;
    final coverage = count / topics.length;
    return (avgScore * coverage).round();
  }
}
