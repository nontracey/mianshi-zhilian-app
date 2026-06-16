import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/user.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/widgets/offline_banner.dart';
import 'package:mianshi_zhilian/widgets/onboarding_screen.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/l10n/l10n.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/services/analytics_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/ai_route_generator.dart';
import 'package:mianshi_zhilian/pages/learning/dashboard_page.dart';
import 'package:mianshi_zhilian/pages/learning/catalog_page.dart';
import 'package:mianshi_zhilian/pages/learning/topic_detail_page.dart';
import 'package:mianshi_zhilian/pages/practice/practice_page.dart';
import 'package:mianshi_zhilian/pages/practice/recall_page.dart';
import 'package:mianshi_zhilian/pages/practice/mock_interview_page.dart';
import 'package:mianshi_zhilian/pages/practice/today_review_page.dart';
import 'package:mianshi_zhilian/pages/prep/interview_prep_page.dart';
import 'package:mianshi_zhilian/pages/mastery/mastery_page.dart';
import 'package:mianshi_zhilian/pages/profile/profile_page.dart';
import 'package:mianshi_zhilian/widgets/navigation_rail_panel.dart';
import 'package:mianshi_zhilian/widgets/header_bar.dart';

enum AppSection { dashboard, catalog, practice, prep, mastery, profile }

class LearningShell extends StatefulWidget {
  const LearningShell({super.key});

  @override
  State<LearningShell> createState() => _LearningShellState();
}

class _LearningShellState extends State<LearningShell> {
  AppSection _section = AppSection.dashboard;
  String? _selectedTopicId;
  int _selectedTopicInitialTab = 0;
  // 「领域知识卡片」点入时的临时目录领域：仅供 CatalogPage 临时浏览该领域目录，
  // 不改变学习范围（路线保持不变）。切换 section / 返回时清空。
  String? _catalogDomainOverride;
  bool _isSidebarCollapsed = false;
  late AuthProvider _auth;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth = context.read<AuthProvider>();
    _auth.autoLogoutReason.removeListener(_onAutoLogout);
    _auth.autoLogoutReason.addListener(_onAutoLogout);
    StorageService.writeFailure.removeListener(_onStorageWriteFailure);
    StorageService.writeFailure.addListener(_onStorageWriteFailure);
  }

  @override
  void dispose() {
    _auth.autoLogoutReason.removeListener(_onAutoLogout);
    StorageService.writeFailure.removeListener(_onStorageWriteFailure);
    super.dispose();
  }

  void _onStorageWriteFailure() {
    if (StorageService.writeFailure.value == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.get('storage_write_failed', L10n.currentLanguage)),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
    StorageService.writeFailure.value = null;
  }

  void _onAutoLogout() {
    final reason = _auth.autoLogoutReason.value;
    if (reason != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _auth.autoLogoutReason.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final settings = context.watch<SettingsProvider>();
    final content = context.watch<ContentProvider>();
    final progress = context.watch<ProgressProvider>();

    if (!settings.settings.onboardingCompleted) {
      return const OnboardingScreen();
    }

    // Shell 内部用 _section / _selectedTopicId 切页（非 go_router 路由栈），
    // 所以系统返回键/侧滑返回没有可 pop 的路由，会直接最小化 App。
    // 用 PopScope 拦截：先关闭知识点详情，再回到学习首页，最后才允许退出。
    final canPop = _selectedTopicId == null && _section == AppSection.dashboard;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedTopicId != null) {
          setState(() => _selectedTopicId = null);
        } else if (_section != AppSection.dashboard) {
          _setSection(AppSection.dashboard);
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: Row(
                children: [
                  if (wide)
                    NavigationRailPanel(
                      section: _section,
                      onSelect: _setSection,
                      currentDomain: settings.settings.currentDomain,
                      topicCount: content.topics.length,
                      streakDays: progress.streakDays,
                      totalHours: progress.totalHours,
                      todayHoursGrowth: progress.todayHoursGrowth,
                      isCollapsed: _isSidebarCollapsed,
                      onToggleCollapse: () => setState(
                        () => _isSidebarCollapsed = !_isSidebarCollapsed,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        HeaderBar(
                          title: _sectionTitle(_section, l10n),
                          sectionIndex: _section.index,
                          onProfile: () => _setSection(AppSection.profile),
                          onTopicTap: (topicId) => setState(() {
                            _selectedTopicId = topicId;
                            _selectedTopicInitialTab = 0;
                          }),
                          onContentStageChanged: (contentEnv) async {
                            final authProvider = context.read<AuthProvider>();
                            final userRole = authProvider.userRole;
                            if (!userRole.allowedContentEnvs.contains(
                              contentEnv.key,
                            )) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    userRole == UserRole.guest
                                        ? l10n.get(
                                            'login_after_optional_check_view_test_version_content',
                                          )
                                        : l10n.get(
                                            'demand_key_management_member_permission_check_view_draft_con',
                                          ),
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              return;
                            }

                            await settings.setContentEnv(contentEnv);
                            if (!context.mounted) return;
                            final contentProvider = context
                                .read<ContentProvider>();
                            await contentProvider.switchContentEnv(
                              settings.settings.contentBaseUrl,
                              currentDomainId: settings.settings.currentDomain,
                            );
                          },
                        ),
                        Expanded(child: _buildCurrentPage(wide)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _section.index,
                onDestinationSelected: (i) => _setSection(AppSection.values[i]),
                destinations: [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    label: l10n.get('study'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    label: l10n.get('catalog'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.psychology_alt_outlined),
                    label: l10n.get('practice'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.flag_outlined),
                    label: l10n.get('interview'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bar_chart_outlined),
                    label: l10n.get('mastery'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    label: l10n.get('settings'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCurrentPage(bool wide) {
    if (_selectedTopicId != null) {
      final content = context.read<ContentProvider>();
      final topic = content.findTopic(_selectedTopicId!);
      if (topic != null) {
        return TopicDetailPage(
          topic: topic,
          initialTabIndex: _selectedTopicInitialTab,
          onBack: () => setState(() => _selectedTopicId = null),
          onRouteTopicTap: (topicId) => setState(() {
            _selectedTopicId = topicId;
            _selectedTopicInitialTab = 0;
          }),
          // 临时浏览某领域目录时进入的知识点：不属于当前路线语境，
          // 隐藏路线上一个/下一个导航。
          showRouteNav: _catalogDomainOverride == null,
        );
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(_section), child: _currentPage()),
    );
  }

  Widget _currentPage() {
    final content = context.read<ContentProvider>();
    final settings = context.read<SettingsProvider>();
    final scope = context.read<LearningScopeProvider>();

    return switch (_section) {
      AppSection.dashboard => DashboardPage(
        onDomainChanged: (id) {
          settings.updateSettings(
            settings.settings.copyWith(currentDomain: id),
          );
          scope.setSingleDomain(id, contentProvider: content);
          if (content.getLoadedTopicCount(id) == 0) {
            content.loadDomainTopics(id);
          }
        },
        onPractice: () => _setSection(AppSection.practice),
        onTopicTap: (topicId) => setState(() {
          _selectedTopicId = topicId;
          _selectedTopicInitialTab = 0;
        }),
        // 路线/领域列表项的「查看目录」：切到单领域范围（退出路线裁剪）再跳目录。
        // 「领域知识卡片」走 onBrowseDomainCatalog（临时浏览，不切换范围）。
        onViewDomainCatalog: (domainId) {
          settings.updateSettings(
            settings.settings.copyWith(currentDomain: domainId),
          );
          if (content.getLoadedTopicCount(domainId) == 0) {
            content.loadDomainTopics(domainId);
          }
          scope.setSingleDomain(domainId, contentProvider: content);
          setState(() => _section = AppSection.catalog);
        },
        // 点「领域知识卡片」= 临时进入该领域目录浏览，不切换学习范围（路线保持）。
        onBrowseDomainCatalog: (domainId) {
          if (content.getLoadedTopicCount(domainId) == 0) {
            content.loadDomainTopics(domainId);
          }
          setState(() {
            _catalogDomainOverride = domainId;
            _section = AppSection.catalog;
            _selectedTopicId = null;
          });
        },
        onReview: () => _setSection(AppSection.practice),
        onMockInterview: () => _startMockInterview(content, settings, scope),
        onPrepNavigation: () => _setSection(AppSection.prep),
        onNavigateToCatalog: () => _setSection(AppSection.catalog),
        onGenerateAiRoute: () => _generateAiRoute(),
        onRegenerateAiRoute: () => _generateAiRoute(forceRegenerate: true),
      ),
      AppSection.catalog => CatalogPage(
        domainOverride: _catalogDomainOverride,
        onExitDomainOverride: () => setState(() {
          _catalogDomainOverride = null;
          _section = AppSection.dashboard;
        }),
        onDomainChanged: (id) {
          settings.updateSettings(
            settings.settings.copyWith(currentDomain: id),
          );
          scope.setSingleDomain(id, contentProvider: content);
          if (content.getLoadedTopicCount(id) == 0) {
            content.loadDomainTopics(id);
          }
        },
        onTopicLearn: (topicId) => setState(() {
          _selectedTopicId = topicId;
          _selectedTopicInitialTab = 0;
        }),
        onTopicPractice: (topicId) => setState(() {
          _selectedTopicId = topicId;
          _selectedTopicInitialTab = 1;
        }),
      ),
      AppSection.practice => PracticePage(
        onDailyReview: () {
          context.push(
            '/practice/today-review',
            extra: const TodayReviewPage(),
          );
        },
        onRandomQuiz: (domainId) {
          final List<String> topicIds;
          if (scope.isRouteMode && scope.scopeTopicIds.isNotEmpty) {
            final routeInDomain = scope.scopeTopicIds.where((id) {
              final t = content.findTopic(id);
              return t != null && t.domainId == domainId;
            }).toList()..shuffle();
            topicIds = routeInDomain.isNotEmpty
                ? routeInDomain
                : (content.getTopicsByDomain(domainId).map((t) => t.id).toList()
                    ..shuffle());
          } else {
            topicIds =
                content.getTopicsByDomain(domainId).map((t) => t.id).toList()
                  ..shuffle();
          }
          context.push(
            '/practice/recall',
            extra: RecallPage(topicIds: topicIds.take(5).toList()),
          );
        },
        onMockInterview: () => _startMockInterview(content, settings, scope),
      ),
      AppSection.prep => InterviewPrepPage(
        onStartPractice: () => _setSection(AppSection.practice),
        onStartMock: () => _startMockInterview(content, settings, scope),
        onGenerateAiRoute: () => _generateAiRoute(),
        onNavigateToDashboard: () => _setSection(AppSection.dashboard),
      ),
      AppSection.mastery => MasteryPage(
        onDomainChanged: (id) {
          settings.updateSettings(
            settings.settings.copyWith(currentDomain: id),
          );
          scope.setSingleDomain(id, contentProvider: content);
        },
        onStartTopicPractice: (topicId) => setState(() {
          _selectedTopicId = topicId;
          _selectedTopicInitialTab = 1;
        }),
        onStartPractice: () {
          final topicIds =
              scope.resolveScopedTopics(content).map((t) => t.id).toList()
                ..shuffle();
          context.push(
            '/practice/recall',
            extra: RecallPage(topicIds: topicIds.take(5).toList()),
          );
        },
      ),
      AppSection.profile => const ProfilePage(),
    };
  }

  void _startMockInterview(
    ContentProvider content,
    SettingsProvider settings,
    LearningScopeProvider scope,
  ) {
    final topicIds =
        scope.resolveScopedTopics(content).map((t) => t.id).toList()..shuffle();
    context.push(
      '/practice/mock-interview',
      extra: MockInterviewPage(
        topicIds: topicIds.take(10).toList(),
        interviewScenario: settings.settings.mockInterviewPreference,
      ),
    );
  }

  void _setSection(AppSection value) {
    context.read<AnalyticsService>().recordSection(value.name);
    setState(() {
      _section = value;
      _selectedTopicId = null;
      // 经导航切换目录时退出临时浏览，回到按学习范围裁剪的目录视图。
      _catalogDomainOverride = null;
    });
  }

  /// AI 路线生成/重新生成
  Future<void> _generateAiRoute({bool forceRegenerate = false}) async {
    final scopeProvider = context.read<LearningScopeProvider>();
    // 全局并发锁：防止重复生成
    if (scopeProvider.isGeneratingRoute) return;
    scopeProvider.setGeneratingRoute(true);
    try {
      final progress = context.read<ProgressProvider>();
      final content = context.read<ContentProvider>();
      final aiProvider = context.read<AiProvider>();
      final plan = progress.prepPlan;

      if (!plan.hasTarget) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.read<LocalizationProvider>().get('set_target_first'),
              ),
            ),
          );
        }
        return;
      }

      // 只加载匹配领域的 topics（不再全量预加载）
      final domainIds = content.domains.map((d) => d.id).toList();

      final generator = AiRouteGenerator(content.domains);
      final aiConfig = aiProvider.defaultConfig;
      final useAi = aiProvider.aiService.isConfigAvailable(aiConfig);

      // 无可用 AI 配置时提前告知用户
      if (!useAi && forceRegenerate) {
        if (mounted) {
          final l10n = context.read<LocalizationProvider>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.get('no_ai_config_available'))),
          );
        }
        return;
      }

      if (useAi) {
        // AI 选领域后再加载对应 topics，避免全量预加载
        try {
          final selectedDomainIds = await generator.selectDomainIds(
            plan: plan,
            aiService: aiProvider.aiService,
            aiConfig: aiConfig!,
          );
          await content.ensureTopicsLoaded(selectedDomainIds);
        } catch (_) {
          // AI 选领域失败，加载全部领域作为兜底
          try {
            await content.ensureTopicsLoaded(domainIds);
          } catch (_) {}
        }
      } else {
        // 无 AI 时加载全部领域
        try {
          await content.ensureTopicsLoaded(domainIds);
        } catch (_) {}
      }

      try {
        final route = await generator.generateRoute(
          plan: plan,
          allTopics: content.topics.values.toList(),
          progressProvider: progress,
          aiService: aiProvider.aiService,
          contentProvider: content,
          aiConfig: aiConfig,
          forceRegenerate: forceRegenerate,
          // custom_routes 作为唯一事实源：非强制重生时复用已有同目标路线
          existingRoutes: scopeProvider.customRoutes,
        );

        // 通过 LearningScopeProvider 保存并去重（同 planSignature 的旧 AI 路线会被替换）
        if (mounted) {
          final scopeProvider = context.read<LearningScopeProvider>();
          await scopeProvider.upsertRoute(
            route,
            activate: true,
            contentProvider: content,
          );
          // 记录生成时的 plan 签名，以便后续检测目标是否变更
          scopeProvider.notifyPlanChanged(plan.signature);
          scopeProvider.clearRouteStale();
          final l10n = context.read<LocalizationProvider>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.get('route_generated_success')),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          final l10n = context.read<LocalizationProvider>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.get('route_generate_failed'))),
          );
        }
      }
    } finally {
      scopeProvider.setGeneratingRoute(false);
    }
  }

  String _sectionTitle(AppSection section, LocalizationProvider l10n) =>
      switch (section) {
        AppSection.dashboard => l10n.get('dashboard_title'),
        AppSection.catalog => l10n.get('catalog_title'),
        AppSection.practice => l10n.get('practice_title'),
        AppSection.prep => l10n.get('interview_preparation'),
        AppSection.mastery => l10n.get('mastery_title'),
        AppSection.profile => l10n.get('profile_title'),
      };
}
