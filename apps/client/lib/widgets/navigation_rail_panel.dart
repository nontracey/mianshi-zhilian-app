import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../main.dart';

IconData _sectionIcon(AppSection section) => switch (section) {
      AppSection.dashboard => Icons.dashboard_outlined,
      AppSection.catalog => Icons.menu_book_outlined,
      AppSection.practice => Icons.psychology_alt_outlined,
      AppSection.mastery => Icons.bar_chart_outlined,
      AppSection.profile => Icons.person_outline,
    };

String _sectionTitle(AppSection section) => switch (section) {
      AppSection.dashboard => '学习',
      AppSection.catalog => '知识',
      AppSection.practice => '练习',
      AppSection.mastery => '掌握',
      AppSection.profile => '我的',
    };

class NavigationRailPanel extends StatelessWidget {
  const NavigationRailPanel({
    super.key,
    required this.section,
    required this.onSelect,
    required this.currentDomain,
    required this.topicCount,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;
  final String currentDomain;
  final int topicCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            'assets/logo.svg',
            width: 36,
            height: 36,
          ),
          const SizedBox(height: 12),
          const Text(
            '面试智练',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'AI 主动回忆学习工作台',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 28),
          ...AppSection.values.map(
            (item) => _NavButton(
              section: item,
              active: section == item,
              onTap: () => onSelect(item),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => onSelect(AppSection.practice),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始今日练习'),
          ),
          const SizedBox(height: 16),
          Text(
            '本地优先模式\n已缓存 $topicCount 个知识点\n当前领域: $currentDomain',
            style: const TextStyle(color: Colors.white70, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.section,
    required this.active,
    required this.onTap,
  });

  final AppSection section;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(_sectionIcon(section), color: Colors.white),
        label: Text(
          _sectionTitle(section),
          style: const TextStyle(color: Colors.white),
        ),
        style: TextButton.styleFrom(
          backgroundColor:
              active ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
          minimumSize: const Size.fromHeight(46),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}
