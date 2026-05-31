import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../theme/colors.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

IconData _sectionIcon(AppSection section) => switch (section) {
  AppSection.dashboard => Icons.dashboard_outlined,
  AppSection.catalog => Icons.menu_book_outlined,
  AppSection.practice => Icons.psychology_alt_outlined,
  AppSection.prep => Icons.flag_outlined,
  AppSection.mastery => Icons.bar_chart_outlined,
  AppSection.profile => Icons.person_outline,
};

String _sectionTitle(AppSection section, LocalizationProvider l10n) =>
    switch (section) {
      AppSection.dashboard => l10n.get('study'),
      AppSection.catalog => l10n.get('catalog'),
      AppSection.practice => l10n.get('practice'),
      AppSection.prep => l10n.get('interview'),
      AppSection.mastery => l10n.get('mastery'),
      AppSection.profile => l10n.get('settings'),
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
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSelect;
  final String currentDomain;
  final int topicCount;
  final int streakDays;
  final double totalHours;
  final double todayHoursGrowth;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final borderColor = Theme.of(context).colorScheme.outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isCollapsed ? 72 : 220,
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(right: BorderSide(color: borderColor, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + 产品名 + 收缩按钮
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCollapsed ? 12 : 20,
              24,
              isCollapsed ? 12 : 20,
              8,
            ),
            child: isCollapsed
                ? Center(
                    child: SvgPicture.asset(
                      'assets/logo.svg',
                      width: 32,
                      height: 32,
                    ),
                  )
                : Row(
                    children: [
                      SvgPicture.asset(
                        'assets/logo.svg',
                        width: 32,
                        height: 32,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.get('interview_intelligence_training'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 收缩按钮
                      IconButton(
                        icon: Icon(
                          Icons.chevron_left,
                          size: 20,
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                        onPressed: onToggleCollapse,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: l10n.get('collapse_sidebar'),
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
              isCollapsed: isCollapsed,
              onTap: () => onSelect(item),
            ),
          ),

          const Spacer(),

          // 展开按钮（收缩状态时显示）
          if (isCollapsed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: IconButton(
                  icon: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                  onPressed: onToggleCollapse,
                  tooltip: l10n.get('expand_sidebar'),
                ),
              ),
            ),

          // 底部统计信息
          if (!isCollapsed)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _StatItem(
                    icon: Icons.access_time,
                    label: l10n.get('study_total_time_long'),
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
                    label: l10n.get('streak_study'),
                    value: l10n.getp('days_day_2', {'days': streakDays}),
                    isDark: isDark,
                  ),
                ],
              ),
            ),

          // 收缩状态显示简化统计
          if (isCollapsed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Tooltip(
                    message: l10n.getp('streak_study_days_day_2', {
                      'days': streakDays,
                    }),
                    child: Icon(
                      Icons.local_fire_department_outlined,
                      size: 20,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
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
    required this.isCollapsed,
    required this.onTap,
  });

  final AppSection section;
  final bool active;
  final bool isDark;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final accentColor = const Color(0xFF3078F0);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 8 : 12,
        vertical: 4,
      ),
      child: Tooltip(
        message: isCollapsed ? _sectionTitle(section, l10n) : '',
        child: Material(
          color: active
              ? (isDark
                    ? accentColor.withValues(alpha: 0.15)
                    : accentColor.withValues(alpha: 0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCollapsed ? 0 : 12,
                vertical: 12,
              ),
              child: isCollapsed
                  ? Center(
                      child: Icon(
                        _sectionIcon(section),
                        size: 22,
                        color: active
                            ? accentColor
                            : (isDark
                                  ? Colors.white54
                                  : AppColors.textSecondary),
                      ),
                    )
                  : Row(
                      children: [
                        Icon(
                          _sectionIcon(section),
                          size: 20,
                          color: active
                              ? accentColor
                              : (isDark
                                    ? Colors.white54
                                    : AppColors.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _sectionTitle(section, l10n),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: active
                                ? accentColor
                                : (isDark
                                      ? Colors.white70
                                      : AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
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
