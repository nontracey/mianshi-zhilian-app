/// 教练三入口外壳：今天 / 模拟面试 / 目标与资料。
///
/// 与既有「学习（内容库）」入口并列，作为目标化改造的独立入口，
/// 不替换现有学习页，避免改造期间影响存量用户。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/localization_provider.dart';
import 'goals_materials_page.dart';
import 'interview_page.dart';
import 'today_page.dart';

class CoachShell extends StatefulWidget {
  const CoachShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<CoachShell> createState() => _CoachShellState();
}

class _CoachShellState extends State<CoachShell> {
  late int _index = widget.initialIndex.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [TodayPage(), InterviewPage(), GoalsMaterialsPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.get('coach_nav_today'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.record_voice_over_outlined),
            selectedIcon: const Icon(Icons.record_voice_over),
            label: l10n.get('coach_nav_interview'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.flag_outlined),
            selectedIcon: const Icon(Icons.flag),
            label: l10n.get('coach_nav_goals'),
          ),
        ],
      ),
    );
  }
}
