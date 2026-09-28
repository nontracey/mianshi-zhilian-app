/// 教练三入口外壳：知识内容 / 学习 / 掌握度。
///
/// 知识内容浏览与掌握度统计直接复用内容库页面（CDN 内容源），
/// 学习入口承载教练每日计划与聊天会话；不再保留旧版五入口壳层。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/content_provider.dart';
import '../../providers/learning_scope_provider.dart';
import '../../providers/localization_provider.dart';
import '../../providers/settings_provider.dart';
import '../learning/catalog_page.dart';
import '../learning/topic_detail_page.dart';
import '../mastery/mastery_page.dart';
import 'today_page.dart';

class CoachShell extends StatefulWidget {
  const CoachShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<CoachShell> createState() => _CoachShellState();
}

class _CoachShellState extends State<CoachShell> {
  late int _index = widget.initialIndex.clamp(0, 2);

  void _onDomainChanged(String id) {
    final settings = context.read<SettingsProvider>();
    final scope = context.read<LearningScopeProvider>();
    final content = context.read<ContentProvider>();
    settings.updateSettings(settings.settings.copyWith(currentDomain: id));
    scope.setSingleDomain(id, contentProvider: content);
    if (content.getLoadedTopicCount(id) == 0) {
      content.loadDomainTopics(id);
    }
  }

  void _openTopic(String topicId, {int initialTab = 0, bool replace = false}) {
    final topic = context.read<ContentProvider>().findTopic(topicId);
    if (topic == null) return;
    final page = Scaffold(
      body: SafeArea(
        child: TopicDetailPage(
          topic: topic,
          initialTabIndex: initialTab,
          onBack: () => context.pop(),
          // 路线导航点入时替换当前页，避免返回栈无限增长。
          onRouteTopicTap: (nextId) =>
              _openTopic(nextId, initialTab: initialTab, replace: true),
          showRouteNav: true,
        ),
      ),
    );
    if (replace) {
      context.pushReplacement('/topic', extra: page);
    } else {
      context.push('/topic', extra: page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _KnowledgeTab(
            l10n: l10n,
            onDomainChanged: _onDomainChanged,
            onOpenTopic: _openTopic,
          ),
          const TodayPage(),
          _MasteryTab(
            l10n: l10n,
            onDomainChanged: _onDomainChanged,
            onOpenTopic: _openTopic,
            onGoStudy: () => setState(() => _index = 1),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l10n.get('coach_nav_knowledge'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.get('coach_nav_today'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.donut_large_outlined),
            selectedIcon: const Icon(Icons.donut_large),
            label: l10n.get('coach_nav_mastery'),
          ),
        ],
      ),
    );
  }
}

/// 知识内容：内容库目录（CDN 内容源）。
class _KnowledgeTab extends StatelessWidget {
  const _KnowledgeTab({
    required this.l10n,
    required this.onDomainChanged,
    required this.onOpenTopic,
  });

  final LocalizationProvider l10n;
  final ValueChanged<String> onDomainChanged;
  final void Function(String topicId, {int initialTab}) onOpenTopic;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('coach_nav_knowledge'))),
      body: CatalogPage(
        onDomainChanged: onDomainChanged,
        onTopicLearn: (id) => onOpenTopic(id),
        onTopicPractice: (id) => onOpenTopic(id, initialTab: 1),
      ),
    );
  }
}

/// 掌握度统计：内容库掌握度视图。
class _MasteryTab extends StatelessWidget {
  const _MasteryTab({
    required this.l10n,
    required this.onDomainChanged,
    required this.onOpenTopic,
    required this.onGoStudy,
  });

  final LocalizationProvider l10n;
  final ValueChanged<String> onDomainChanged;
  final void Function(String topicId, {int initialTab}) onOpenTopic;
  final VoidCallback onGoStudy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('coach_nav_mastery'))),
      body: MasteryPage(
        onDomainChanged: onDomainChanged,
        onStartTopicPractice: (id) => onOpenTopic(id, initialTab: 1),
        onStartPractice: onGoStudy,
      ),
    );
  }
}
