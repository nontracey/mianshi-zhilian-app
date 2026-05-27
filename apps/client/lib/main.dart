import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/content_provider.dart';
import 'providers/ai_provider.dart';
import 'providers/localization_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/settings_provider.dart';
import 'services/content_api_service.dart';
import 'services/ai_service.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
import 'pages/learning/dashboard_page.dart';
import 'pages/learning/catalog_page.dart';
import 'pages/learning/topic_detail_page.dart';
import 'pages/practice/practice_page.dart';
import 'pages/practice/recall_page.dart';
import 'pages/practice/mock_interview_page.dart';
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

  runApp(
    MianshiZhilianApp(
      storage: storage,
      contentApi: contentApi,
      aiService: aiService,
      updateService: updateService,
    ),
  );
}

enum AppSection { dashboard, catalog, practice, mastery, profile }

class MianshiZhilianApp extends StatelessWidget {
  final StorageService storage;
  final ContentApiService contentApi;
  final AiService aiService;
  final UpdateService updateService;

  const MianshiZhilianApp({
    super.key,
    required this.storage,
    required this.contentApi,
    required this.aiService,
    required this.updateService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(storage)..loadSettings(),
        ),
        ChangeNotifierProvider(
          create: (_) => ContentProvider(contentApi, storage)..loadContent(),
        ),
        ChangeNotifierProvider(
          create: (_) => AiProvider(aiService, storage)..loadConfigs(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProgressProvider(storage)..loadProgress(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(storage)..loadUser(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocalizationProvider(),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final theme = buildTheme(
            settings.settings.primaryColor,
            settings.settings.accentColor,
            settings.settings.themeMode,
          );
          return MaterialApp(
            title: '面试智练',
            debugShowCheckedModeBanner: false,
            themeMode: settings.settings.themeMode,
            theme: theme,
            darkTheme: buildTheme(
              settings.settings.primaryColor,
              settings.settings.accentColor,
              ThemeMode.dark,
            ),
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

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final settings = context.watch<SettingsProvider>();
    final content = context.watch<ContentProvider>();

    return Scaffold(
      body: Row(
        children: [
          if (wide)
            NavigationRailPanel(
              section: _section,
              onSelect: _setSection,
              currentDomain: settings.settings.currentDomain,
              topicCount: content.topics.length,
            ),
          Expanded(
            child: Column(
              children: [
                HeaderBar(
                  title: _sectionTitle(_section),
                  onProfile: () => _setSection(AppSection.profile),
                  onTopicTap: (topicId) => setState(() {
                    _selectedTopicId = topicId;
                    _selectedTopicInitialTab = 0;
                  }),
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
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: '学习',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  label: '知识',
                ),
                NavigationDestination(
                  icon: Icon(Icons.psychology_alt_outlined),
                  label: '练习',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  label: '掌握',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: '我的',
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
    final progress = context.read<ProgressProvider>();
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
              builder: (_) => RecallPage(
                topicIds: progress
                    .getTodayReviewTopics(content.topics.values.toList())
                    .map((t) => t.id)
                    .toList(),
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
              builder: (_) => MockInterviewPage(topicIds: topicIds.take(10).toList()),
            ),
          );
        },
      ),
      AppSection.mastery => MasteryPage(
        currentDomainId: settings.settings.currentDomain,
        onDomainChanged: (id) => settings.updateSettings(
          settings.settings.copyWith(currentDomain: id),
        ),
      ),
      AppSection.profile => const ProfilePage(),
    };
  }

  void _setSection(AppSection value) {
    setState(() {
      _section = value;
      _selectedTopicId = null;
    });
  }

  String _sectionTitle(AppSection section) => switch (section) {
    AppSection.dashboard => '学习中心',
    AppSection.catalog => '领域知识目录',
    AppSection.practice => 'AI 主动复述',
    AppSection.mastery => '掌握度看板',
    AppSection.profile => '个人中心',
  };
}
