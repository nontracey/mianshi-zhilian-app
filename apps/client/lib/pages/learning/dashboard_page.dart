import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/widgets/skeleton_loader.dart';
import 'dashboard_panels.dart';
import 'dashboard_dialogs.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.onDomainChanged,
    required this.onPractice,
    required this.onTopicTap,
    required this.onViewDomainCatalog,
    this.onReview,
    this.onMockInterview,
    this.onPrepNavigation,
    this.onNavigateToCatalog,
    this.onGenerateAiRoute,
    this.onRegenerateAiRoute,
    this.onRouteChanged,
  });

  final ValueChanged<String> onDomainChanged;
  final VoidCallback onPractice;
  final ValueChanged<String> onTopicTap;
  final ValueChanged<String> onViewDomainCatalog;
  final VoidCallback? onReview;
  final VoidCallback? onMockInterview;
  final VoidCallback? onPrepNavigation;
  final VoidCallback? onNavigateToCatalog;
  final VoidCallback? onGenerateAiRoute;
  final VoidCallback? onRegenerateAiRoute;
  final VoidCallback? onRouteChanged;

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final scope = context.watch<LearningScopeProvider>();
    final l10n = context.watch<LocalizationProvider>();
    final currentDomainId = settingsProvider.settings.currentDomain;

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
      // 当前域不在列表中，切换到第一个可用域
      // 使用 ValueKey 确保只在域 ID 变化时触发切换，避免 build 中的无限回调
      return _DomainAutoSwitch(
        key: ValueKey(domains.first.id),
        domainId: domains.first.id,
        onDomainChanged: onDomainChanged,
      );
    }

    final domainTopics = contentProvider.getTopicsByDomain(currentDomainId);
    final isCrossDomainRoute = scope.isCrossDomain;
    final isRouteFocused = scope.isRouteMode;

    // 通过 LearningScopeProvider 统一解析 scopedTopics
    var scopedTopics = scope.resolveScopedTopics(contentProvider);

    if (!contentProvider.isLoadingTopics && scopedTopics.isEmpty) {
      // 路线模式下 scopedTopics 为空（topic 尚未加载），回退当前域
      if (isRouteFocused && domainTopics.isNotEmpty) {
        scopedTopics = domainTopics;
      } else if (domainTopics.isEmpty) {
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
    }

    final domainProgress = isRouteFocused
        ? (masteryPercent: _calcMasteryPercent(scopedTopics, progressProvider), topicCount: scopedTopics.length)
        : progressProvider.getDomainProgress(
            currentDomainId,
            contentProvider.topics.values.toList(),
          );
    final masteryPercent = domainProgress.masteryPercent;
    final topicCount = domainProgress.topicCount;
    final readiness = progressProvider.readinessScore(scopedTopics);

    final recommendedTopics = progressProvider.getRecommendedTopics(
      isCrossDomainRoute ? null : currentDomainId,
      isRouteFocused ? scopedTopics : contentProvider.topics.values.toList(),
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
    // 目标改变时通知 scope，检测路线陈旧
    if (plan.hasTarget) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scope.notifyPlanChanged(plan.signature),
      );
    }

    final weakTopics = progressProvider.getWeakTopics(scopedTopics, limit: 5);
    final recentAttempts = progressProvider.recentAttempts.take(5).toList();
    final dueTopics = progressProvider.getTodayReviewTopics(scopedTopics);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (scope.routeStale)
            _buildRouteStaleBanner(context),
          if (!scope.isRouteMode && plan.hasTarget)
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
                         routeTopicIds: scope.isRouteMode ? scope.scopeTopicIds : null,
                         isRouteMode: scope.isRouteMode,
                         routeFirstTopicId: scope.isRouteMode && scope.scopeTopicIds.isNotEmpty ? scope.scopeTopicIds.first : null,
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
                        routeModeEnabled: scope.isRouteMode,
                        onRouteModeChanged: () { final s = context.read<LearningScopeProvider>(); if (s.isRouteMode) { s.setAllDomains(); } else if (s.customRoutes.isNotEmpty) { s.setRoute(s.customRoutes.last.id); } },
                        onDomainChanged: onDomainChanged,
                        onTopicTap: onTopicTap,
                        onViewDomainCatalog: onViewDomainCatalog,
                        onPractice: onPractice,
                        onReview: onReview,
                        onMockInterview: onMockInterview,
                        contentProvider: contentProvider,
                        progressProvider: progressProvider,
                        settingsProvider: settingsProvider,
                        onGenerateAiRoute: onGenerateAiRoute,
                        onRegenerateAiRoute: onRegenerateAiRoute,
                        onRouteChanged: onRouteChanged,
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
                         routeTopicIds: scope.isRouteMode ? scope.scopeTopicIds : null,
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
                         routeTopicIds: scope.isRouteMode ? scope.scopeTopicIds : null,
                         isRouteMode: scope.isRouteMode,
                         routeFirstTopicId: scope.isRouteMode && scope.scopeTopicIds.isNotEmpty ? scope.scopeTopicIds.first : null,
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
                            routeModeEnabled: scope.isRouteMode,
                            onRouteModeChanged: () {
                              final s = context.read<LearningScopeProvider>();
                              if (s.isRouteMode) {
                                s.setAllDomains();
                              } else if (s.customRoutes.isNotEmpty) {
                                s.setRoute(s.customRoutes.last.id);
                              }
                            },
                            onDomainChanged: onDomainChanged,
                            onTopicTap: onTopicTap,
                            onViewDomainCatalog: onViewDomainCatalog,
                            onPractice: onPractice,
                            onReview: onReview,
                            onMockInterview: onMockInterview,
                            contentProvider: contentProvider,
                            progressProvider: progressProvider,
                            settingsProvider: settingsProvider,
                            onGenerateAiRoute: onGenerateAiRoute,
                            onRegenerateAiRoute: onRegenerateAiRoute,
                            onRouteChanged: onRouteChanged,
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
                             routeTopicIds: scope.isRouteMode ? scope.scopeTopicIds : null,
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
                    routeTopicIds: scope.isRouteMode ? scope.scopeTopicIds : null,
                    isRouteMode: scope.isRouteMode,
                    routeFirstTopicId: scope.isRouteMode && scope.scopeTopicIds.isNotEmpty ? scope.scopeTopicIds.first : null,
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
                    routeModeEnabled: scope.isRouteMode,
                    onRouteModeChanged: () { final s = context.read<LearningScopeProvider>(); if (s.isRouteMode) { s.setAllDomains(); } else if (s.customRoutes.isNotEmpty) { s.setRoute(s.customRoutes.last.id); } },
                    onDomainChanged: onDomainChanged,
                    onTopicTap: onTopicTap,
                    onViewDomainCatalog: onViewDomainCatalog,
                    onPractice: onPractice,
                    onReview: onReview,
                    onMockInterview: onMockInterview,
                    contentProvider: contentProvider,
                    progressProvider: progressProvider,
                    settingsProvider: settingsProvider,
                    onGenerateAiRoute: onGenerateAiRoute,
                    onRegenerateAiRoute: onRegenerateAiRoute,
                    onRouteChanged: onRouteChanged,
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
                    routeTopicIds: scope.isRouteMode ? scope.scopeTopicIds : null,
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

  Widget _buildRouteStaleBanner(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.get('route_stale_hint'),
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              context.read<LearningScopeProvider>().clearRouteStale();
              onRegenerateAiRoute?.call();
            },
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
            child: Text(l10n.get('update_route'), style: TextStyle(color: AppColors.warning, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.warning,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => context.read<LearningScopeProvider>().clearRouteStale(),
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
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: isDark ? Colors.white54 : Colors.grey,
            ),
            onPressed: () {
              final progress = context.read<ProgressProvider>();
              showPlanEditDialog(context, progress, plan, l10n);
            },
            tooltip: l10n.get('edit'),
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

/// 当 currentDomainId 不在 domains 列表中时，自动切换到第一个可用域
class _DomainAutoSwitch extends StatefulWidget {
  const _DomainAutoSwitch({
    super.key,
    required this.domainId,
    required this.onDomainChanged,
  });

  final String domainId;
  final ValueChanged<String> onDomainChanged;

  @override
  State<_DomainAutoSwitch> createState() => _DomainAutoSwitchState();
}

class _DomainAutoSwitchState extends State<_DomainAutoSwitch> {
  bool _switched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_switched) {
      _switched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDomainChanged(widget.domainId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
