import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/l10n.dart';

import 'models/app_settings.dart';
import 'models/user.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/content_provider.dart';
import 'providers/ai_provider.dart';
import 'providers/localization_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/settings_provider.dart';
import 'services/content_api_service.dart';
import 'services/ai_service.dart';
import 'services/analytics_service.dart';
import 'services/data_sync_service.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
import 'pages/learning/dashboard_page.dart';
import 'pages/learning/catalog_page.dart';
import 'pages/learning/topic_detail_page.dart';
import 'pages/practice/practice_page.dart';
import 'pages/practice/recall_page.dart';
import 'pages/practice/mock_interview_page.dart';
import 'pages/practice/today_review_page.dart';
import 'pages/prep/interview_prep_page.dart';
import 'pages/mastery/mastery_page.dart';
import 'pages/profile/profile_page.dart';
import 'widgets/navigation_rail_panel.dart';
import 'widgets/header_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  // 先加载已保存的设置，获取正确的 contentBaseUrl
  final savedSettings = await storage.loadSettings();
  final contentApi = ContentApiService(baseUrl: savedSettings.contentBaseUrl);
  final aiService = AiService();
  final updateService = UpdateService();
  final dataSyncService = DataSyncService(storage)..start();
  final analyticsService = AnalyticsService(storage)..start();

  runApp(
    MianshiZhilianApp(
      storage: storage,
      dataSyncService: dataSyncService,
      analyticsService: analyticsService,
      contentApi: contentApi,
      aiService: aiService,
      updateService: updateService,
      initialLanguage: savedSettings.language,
    ),
  );
}

enum AppSection { dashboard, catalog, practice, prep, mastery, profile }

class MianshiZhilianApp extends StatefulWidget {
  final StorageService storage;
  final DataSyncService dataSyncService;
  final AnalyticsService analyticsService;
  final ContentApiService contentApi;
  final AiService aiService;
  final UpdateService updateService;
  final String initialLanguage;

  const MianshiZhilianApp({
    super.key,
    required this.storage,
    required this.dataSyncService,
    required this.analyticsService,
    required this.contentApi,
    required this.aiService,
    required this.updateService,
    required this.initialLanguage,
  });

  @override
  State<MianshiZhilianApp> createState() => _MianshiZhilianAppState();
}

class _MianshiZhilianAppState extends State<MianshiZhilianApp> {
  bool _contentLoaded = false;

  @override
  void dispose() {
    widget.dataSyncService.stop();
    widget.analyticsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              SettingsProvider(widget.storage, widget.dataSyncService)
                ..loadSettings(),
        ),
        ChangeNotifierProvider(
          create: (_) => ContentProvider(widget.contentApi, widget.storage),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AiProvider(widget.aiService, widget.storage)..loadConfigs(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProgressProvider(widget.storage)..loadProgress(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(widget.storage)..loadUser(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              LocalizationProvider(initialLanguage: widget.initialLanguage),
        ),
        Provider<AnalyticsService>.value(value: widget.analyticsService),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final l10n = context.watch<LocalizationProvider>();
          // 设置加载完成后，再加载内容（使用当前领域）
          if (!settings.isLoading && !_contentLoaded) {
            _contentLoaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final progressProvider = context.read<ProgressProvider>();
              final settingsProvider = context.read<SettingsProvider>();
              final aiProvider = context.read<AiProvider>();
              final localizationProvider = context.read<LocalizationProvider>();
              widget.dataSyncService.onDataImported = () async {
                await progressProvider.loadProgress();
                await settingsProvider.loadSettings();
                await aiProvider.loadConfigs();
                localizationProvider.setLanguage(
                  settingsProvider.settings.language,
                );
              };
              // 同步语言设置到 LocalizationProvider
              context.read<LocalizationProvider>().setLanguage(
                settings.settings.language,
              );
              // 加载内容
              final contentProvider = context.read<ContentProvider>();
              contentProvider.loadContent(
                currentDomainId: settings.settings.currentDomain,
              );
            });
          }

          // 获取系统亮度
          final systemBrightness = MediaQuery.platformBrightnessOf(context);
          final systemIsDark = systemBrightness == Brightness.dark;

          // 构建主题
          final theme = buildTheme(
            settings.settings.primaryColor,
            settings.settings.accentColor,
            settings.settings.themeType.key,
            fontScale: settings.settings.fontScale,
            cardDensity: settings.settings.cardDensity,
            systemIsDark: systemIsDark,
          );

          return MaterialApp(
            title: l10n.get('interview_intelligence_training'),
            debugShowCheckedModeBanner: false,
            locale: Locale(l10n.language),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10n.supportedLocales,
            themeMode: settings.settings.themeMode,
            theme: theme,
            home: const LearningShell(),
          );
        },
      ),
    );
  }
}

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

    return Scaffold(
      body: Row(
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
                  onContentStageChanged: (stage) async {
                    // 检查权限
                    final authProvider = context.read<AuthProvider>();
                    final userRole = authProvider.userRole;
                    if (!userRole.allowedContentEnvs.contains(stage)) {
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

                    // 切换内容环境
                    final contentEnv = ContentEnv.fromKey(stage);
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

    // 各页面自行管理滚动和 padding，避免嵌套 ListView
    return _currentPage();
  }

  Widget _currentPage() {
    final content = context.read<ContentProvider>();
    final settings = context.read<SettingsProvider>();

    return switch (_section) {
      AppSection.dashboard => DashboardPage(
        currentDomainId: settings.settings.currentDomain,
        onDomainChanged: (id) => settings.updateSettings(
          settings.settings.copyWith(currentDomain: id),
        ),
        onPractice: () => _setSection(AppSection.practice),
        onTopicTap: (topicId) => setState(() {
          _selectedTopicId = topicId;
          _selectedTopicInitialTab = 0;
        }),
        onViewDomainCatalog: (domainId) {
          settings.updateSettings(
            settings.settings.copyWith(currentDomain: domainId),
          );
          setState(() => _section = AppSection.catalog);
        },
        onReview: () => _setSection(AppSection.practice),
        onMockInterview: () => _setSection(AppSection.practice),
      ),
      AppSection.catalog => CatalogPage(
        currentDomainId: settings.settings.currentDomain,
        onDomainChanged: (id) => settings.updateSettings(
          settings.settings.copyWith(currentDomain: id),
        ),
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
        onDailyReview: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TodayReviewPage(
                currentDomainId: settings.settings.currentDomain,
              ),
            ),
          );
        },
        onRandomQuiz: (domainId) {
          final domainTopics = content.getTopicsByDomain(domainId);
          final topicIds = domainTopics.map((t) => t.id).toList()..shuffle();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecallPage(topicIds: topicIds.take(5).toList()),
            ),
          );
        },
        onMockInterview: () {
          final domainTopics = content.getTopicsByDomain(
            settings.settings.currentDomain,
          );
          final topicIds = domainTopics.map((t) => t.id).toList()..shuffle();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  MockInterviewPage(topicIds: topicIds.take(10).toList()),
            ),
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
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  MockInterviewPage(topicIds: topicIds.take(10).toList()),
            ),
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
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecallPage(topicIds: topicIds.take(5).toList()),
            ),
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
