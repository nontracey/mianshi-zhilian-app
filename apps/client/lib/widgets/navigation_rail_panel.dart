import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../main.dart';

IconData _sectionIcon(AppSection section) => switch (section) {
  AppSection.dashboard => Icons.dashboard_outlined,
  AppSection.catalog => Icons.menu_book_outlined,
  AppSection.practice => Icons.psychology_alt_outlined,
  AppSection.prep => Icons.flag_outlined,
  AppSection.mastery => Icons.bar_chart_outlined,
  AppSection.profile => Icons.person_outline,
};

String _sectionTitle(AppSection section) => switch (section) {
  AppSection.dashboard => '学习',
  AppSection.catalog => '目录',
  AppSection.practice => '练习',
  AppSection.prep => '面试',
  AppSection.mastery => '掌握度',
  AppSection.profile => '设置',
};

class NavigationRailPanel extends StatelessWidget {
  const NavigationRailPanel({
    super.key,
    required this.section,
    required this.onSelect,
    required this.currentDomain,
    required this.topicCount,
    required this.streakDays,
    required this.totalHours,
    required this.todayHoursGrowth,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;
  final String currentDomain;
  final int topicCount;
  final int streakDays;
  final double totalHours;
  final double todayHoursGrowth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15202E) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark 
                ? const Color(0xFF263238) 
                : const Color(0xFFE8E8E8),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + 产品名
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                SvgPicture.asset('assets/logo.svg', width: 32, height: 32),
                const SizedBox(width: 10),
                Text(
                  '面试智练',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A2B4A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // 导航项
          ...AppSection.values.map(
            (item) => _NavButton(
              section: item,
              active: section == item,
              isDark: isDark,
              onTap: () => onSelect(item),
            ),
          ),
          
          const Spacer(),
          
          // 底部统计信息
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _StatItem(
                  icon: Icons.access_time,
                  label: '学习总时长',
                  value: '${totalHours.toStringAsFixed(1)} h',
                  trailing: todayHoursGrowth > 0
                      ? '+${todayHoursGrowth.toStringAsFixed(1)}h'
                      : null,
                  trailingColor: const Color(0xFF10B981),
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _StatItem(
                  icon: Icons.local_fire_department_outlined,
                  label: '连续学习',
                  value: '$streakDays 天',
                  isDark: isDark,
                ),
              ],
            ),
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
    required this.isDark,
    required this.onTap,
  });

  final AppSection section;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF3078F0);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: active
            ? (isDark ? accentColor.withValues(alpha: 0.15) : accentColor.withValues(alpha: 0.08))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _sectionIcon(section),
                  size: 20,
                  color: active
                      ? accentColor
                      : (isDark ? Colors.white54 : const Color(0xFF666666)),
                ),
                const SizedBox(width: 12),
                Text(
                  _sectionTitle(section),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? accentColor
                        : (isDark ? Colors.white70 : const Color(0xFF333333)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.trailing,
    this.trailingColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final String? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white38 : const Color(0xFF999999),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : const Color(0xFF999999),
                ),
              ),
              Row(
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      trailing!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: trailingColor ?? const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
