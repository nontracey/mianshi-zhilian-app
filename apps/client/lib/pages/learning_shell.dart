import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/user.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/widgets/offline_banner.dart';
import 'package:mianshi_zhilian/widgets/onboarding_screen.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/analytics_service.dart';
import 'package:mianshi_zhilian/pages/learning/dashboard_page.dart';
import 'package:mianshi_zhilian/pages/learning/catalog_page.dart';
import 'package:mianshi_zhilian/pages/learning/topic_detail_page.dart';
import 'package:mianshi_zhilian/pages/practice/practice_page.dart';
import 'package:mianshi_zhilian/pages/practice/recall_page.dart';
import 'package:mianshi_zhilian/pages/practice/mock_interview_page.dart';
import 'package:mianshi_zhilian/pages/practice/today_review_page.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
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
  bool _isSidebarCollapsed = false;
  late AuthProvider _auth;
  List<String>? _routeTopicIds;
  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadRouteTopicIds();
  }

  Future<void> _loadRouteTopicIds() async {
    final routeId = await _storage.load('selected_route_id');
    if (routeId == null || routeId == 'all') {
      if (mounted) setState(() => _routeTopicIds = null);
      return;
    }
    final customData = await _storage.loadJsonList('custom_routes');
    for (final data in customData) {
      final route = LearningRoute.fromJson(data);
      if (route.id == routeId) {
        final ids = route.allTopicIds;
        if (mounted) setState(() => _routeTopicIds = ids.isEmpty ? null : ids);
        return;
      }
    }
    if (mounted) setState(() => _routeTopicIds = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth = context.read<AuthProvider>();
    _auth.autoLogoutReason.removeListener(_onAutoLogout);
    _auth.autoLogoutReason.addListener(_onAutoLogout);
  }

  @override
  void dispose() {
    _auth.autoLogoutReason.removeListener(_onAutoLogout);
    super.dispose();
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

    return Scaffold(
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
                    onToggleCollapse: () =>
                        setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
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
                          if (!userRole.allowedContentEnvs.contains(contentEnv.key)) {
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
                          final contentProvider = context.read<ContentProvider>();
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
        );
      }
    }

    return _currentPage();
  }

  Widget _currentPage() {
    final content = context.read<ContentProvider>();
    final settings = context.read<SettingsProvider>();

    return switch (_section) {
      AppSection.dashboard => DashboardPage(
        currentDomainId: settings.settings.currentDomain,
        routeTopicIds: _routeTopicIds,
        onDomainChanged: (id) {
          settings.updateSettings(settings.settings.copyWith(currentDomain: id));
          if (content.getLoadedTopicCount(id) == 0) {
            content.loadDomainTopics(id);
          }
        },
        onPractice: () => _setSection(AppSection.practice),
        onTopicTap: (topicId) => setState(() {
          _selectedTopicId = topicId;
          _selectedTopicInitialTab = 0;
        }),
        onViewDomainCatalog: (domainId) {
          settings.updateSettings(
            settings.settings.copyWith(currentDomain: domainId),
          );
          if (content.getLoadedTopicCount(domainId) == 0) {
            content.loadDomainTopics(domainId);
          }
          setState(() => _section = AppSection.catalog);
        },
        onReview: () => _setSection(AppSection.practice),
        onMockInterview: () => _setSection(AppSection.practice),
      ),
      AppSection.catalog => CatalogPage(
        currentDomainId: settings.settings.currentDomain,
        onDomainChanged: (id) {
          settings.updateSettings(settings.settings.copyWith(currentDomain: id));
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
        currentDomainId: settings.settings.currentDomain,
        routeTopicIds: _routeTopicIds,
        onDailyReview: () {
          context.push(
            '/practice/today-review',
            extra: TodayReviewPage(
              currentDomainId: settings.settings.currentDomain,
              routeTopicIds: _routeTopicIds,
            ),
          );
        },
        onRandomQuiz: (domainId) {
          final domainTopics = content.getTopicsByDomain(domainId);
          final topicIds = domainTopics.map((t) => t.id).toList()..shuffle();
          context.push(
            '/practice/recall',
            extra: RecallPage(topicIds: topicIds.take(5).toList()),
          );
        },
        onMockInterview: () {
          final routeIds = _routeTopicIds;
          List<String> topicIds;
          if (routeIds != null && routeIds.isNotEmpty) {
            topicIds = List.from(routeIds)..shuffle();
          } else {
            final domainTopics = content.getTopicsByDomain(
              settings.settings.currentDomain,
            );
            topicIds = domainTopics.map((t) => t.id).toList()..shuffle();
          }
          context.push(
            '/practice/mock-interview',
            extra: MockInterviewPage(topicIds: topicIds.take(10).toList()),
          );
        },
      ),
      AppSection.prep => InterviewPrepPage(
        currentDomainId: settings.settings.currentDomain,
        onStartPractice: () => _setSection(AppSection.practice),
        onStartMock: () {
          final domainTopics = content.getTopicsByDomain(
            settings.settings.currentDomain,
          );
          final topicIds = domainTopics.map((t) => t.id).toList()..shuffle();
          context.push(
            '/practice/mock-interview',
            extra: MockInterviewPage(topicIds: topicIds.take(10).toList()),
          );
        },
      ),
      AppSection.mastery => MasteryPage(
        currentDomainId: settings.settings.currentDomain,
        onDomainChanged: (id) => settings.updateSettings(
          settings.settings.copyWith(currentDomain: id),
        ),
        onStartPractice: () {
          final domainTopics = content.getTopicsByDomain(
            settings.settings.currentDomain,
          );
          final topicIds = domainTopics.map((t) => t.id).toList()..shuffle();
          context.push(
            '/practice/recall',
            extra: RecallPage(topicIds: topicIds.take(5).toList()),
          );
        },
      ),
      AppSection.profile => const ProfilePage(),
    };
  }

  void _setSection(AppSection value) {
    context.read<AnalyticsService>().recordSection(value.name);
    setState(() {
      _section = value;
      _selectedTopicId = null;
    });
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
