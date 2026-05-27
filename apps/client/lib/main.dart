import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme/app_theme.dart';
import 'theme/colors.dart';
import 'providers/content_provider.dart';
import 'providers/ai_provider.dart';
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
import 'pages/mastery/mastery_page.dart';
import 'pages/profile/profile_page.dart';
import 'pages/profile/ai_config_page.dart';
import 'widgets/navigation_rail_panel.dart';
import 'widgets/header_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final contentApi = ContentApiService(
    baseUrl: 'https://mianshi-zhilian-content.pages.dev',
  );
  final aiService = AiService();
  final updateService = UpdateService();

  runApp(MianshiZhilianApp(
    storage: storage,
    contentApi: contentApi,
    aiService: aiService,
    updateService: updateService,
  ));
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
          create: (_) => AiProvider(storage, aiService)..loadConfigs(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProgressProvider(storage)..loadProgress(),
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

  @override
  Widget build(BuildContext context) {
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
            ),
          Expanded(
            child: Column(
              children: [
                HeaderBar(
                  title: _sectionTitle(_section),
                  onProfile: () => _setSection(AppSection.profile),
                ),
                Expanded(
                  child: _buildCurrentPage(wide),
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
              onDestinationSelected: (i) =>
                  _setSection(AppSection.values[i]),
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
    final padding = wide ? 24.0 : 16.0;
    if (_selectedTopicId != null) {
      final content = context.read<ContentProvider>();
      final topic = content.topics[_selectedTopicId!];
      if (topic != null) {
        return TopicDetailPage(
          topic: topic,
          onBack: () => setState(() => _selectedTopicId = null),
        );
      }
    }

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [_currentPage()],
    );
  }

  Widget _currentPage() {
    final content = context.read<ContentProvider>();
    final progress = context.read<ProgressProvider>();
    final settings = context.read<SettingsProvider>();

    return switch (_section) {
      AppSection.dashboard => DashboardPage(
          onPractice: () => _setSection(AppSection.practice),
          onTopicDetail: (topicId) => setState(() => _selectedTopicId = topicId),
        ),
      AppSection.catalog => CatalogPage(
          onTopicDetail: (topicId) => setState(() => _selectedTopicId = topicId),
        ),
      AppSection.practice => PracticePage(
          onStartRecall: (topicId) {
            // Navigate to recall page with topic
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RecallPage(initialTopicId: topicId),
              ),
            );
          },
        ),
      AppSection.mastery => const MasteryPage(),
      AppSection.profile => ProfilePage(
          onAiConfig: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiConfigPage()),
            );
          },
        ),
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
