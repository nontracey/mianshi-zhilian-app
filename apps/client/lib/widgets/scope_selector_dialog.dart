import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/learning_scope.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

/// 学习范围选择对话框：一个列表展示「全部领域 / 各领域 / 各路线（含 AI 路线）」。
class ScopeSelectorDialog extends StatelessWidget {
  const ScopeSelectorDialog({
    super.key,
    this.onGenerateAiRoute,
  });

  final VoidCallback? onGenerateAiRoute;

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onGenerateAiRoute,
  }) =>
      showDialog(
        context: context,
        builder: (_) => ScopeSelectorDialog(onGenerateAiRoute: onGenerateAiRoute),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final scope = context.watch<LearningScopeProvider>();
    final content = context.watch<ContentProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final domains = content.domains;
    final routes = scope.customRoutes;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.tune_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.get('select_study_scope'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  // ── 全部领域 ──
                  _buildScopeItem(
                    context: context,
                    isDark: isDark,
                    icon: Icons.language_outlined,
                    title: l10n.get('all_domains'),
                    subtitle: '${domains.length} ${l10n.get('domains')}',
                    isSelected: scope.isAllDomains,
                    onTap: () {
                      scope.setAllDomains();
                      Navigator.of(context).pop();
                    },
                  ),

                  // ── 单领域 ──
                  if (domains.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(
                        l10n.get('domains'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ...domains.map((d) => _buildScopeItem(
                      context: context,
                      isDark: isDark,
                      icon: Icons.book_outlined,
                      title: d.title,
                      subtitle: '${d.topicCount} ${l10n.get('knowledge_points_count')}',
                      isSelected: scope.isSingleDomain && scope.scope.domainId == d.id,
                      onTap: () {
                        scope.setSingleDomain(d.id);
                        Navigator.of(context).pop();
                      },
                    )),
                  ],

                  // ── 自定义路线 ──
                  if (routes.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(
                        l10n.get('learning_route'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ...routes.map((r) => _buildRouteItem(
                      context: context,
                      isDark: isDark,
                      route: r,
                      isSelected: scope.isRouteMode && scope.scope.routeId == r.id,
                      onTap: () {
                        scope.setRoute(r.id);
                        Navigator.of(context).pop();
                      },
                    )),
                  ],

                  // ── AI 生成路线 ──
                  if (onGenerateAiRoute != null) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 4),
                    ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.auto_awesome, size: 18, color: AppColors.accent),
                      ),
                      title: Text(l10n.get('generate_ai_route'), style: const TextStyle(fontSize: 13)),
                      subtitle: Text(l10n.get('ai_route_subtitle_hint'), style: const TextStyle(fontSize: 11)),
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      onTap: () {
                        Navigator.of(context).pop();
                        onGenerateAiRoute!();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeItem({
    required BuildContext context,
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        title: Text(title, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: isSelected
            ? Icon(Icons.check_circle, size: 18, color: Theme.of(context).colorScheme.primary)
            : null,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
            : null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildRouteItem({
    required BuildContext context,
    required bool isDark,
    required LearningRoute route,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final l10n = context.watch<LocalizationProvider>();
    final topicCount = route.allTopicIds.length;
    final domainCount = route.domainIds.length;
    final subtitle = domainCount > 1
        ? '$domainCount ${l10n.get("domains")} · $topicCount ${l10n.get("knowledge_points_count")}'
        : '$topicCount ${l10n.get("knowledge_points_count")}';
    final badgeLabel = route.source == 'ai' ? 'AI' : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.route_outlined,
            size: 18,
            color: isSelected ? AppColors.accent : null,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                route.name,
                style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badgeLabel != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(fontSize: 10, color: AppColors.accent, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: isSelected
            ? const Icon(Icons.check_circle, size: 18, color: AppColors.accent)
            : null,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: isSelected ? AppColors.accent.withValues(alpha: 0.06) : null,
        onTap: onTap,
      ),
    );
  }
}

/// 显示当前范围并可点击切换的紧凑芯片。
class ScopeSelectorChip extends StatelessWidget {
  const ScopeSelectorChip({super.key, this.onGenerateAiRoute});

  final VoidCallback? onGenerateAiRoute;

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<LearningScopeProvider>();
    final l10n = context.watch<LocalizationProvider>();
    final content = context.watch<ContentProvider>();

    final domainTitles = {for (final d in content.domains) d.id: d.title};
    final label = switch (scope.scope.kind) {
      ScopeKind.allDomains => l10n.get('all_domains'),
      ScopeKind.singleDomain => domainTitles[scope.scope.domainId] ?? l10n.get('single_domain'),
      ScopeKind.route => scope.activeRoute?.name ?? l10n.get('learning_route'),
    };

    return GestureDetector(
      onTap: () => ScopeSelectorDialog.show(context, onGenerateAiRoute: onGenerateAiRoute),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: scope.isRouteMode
              ? AppColors.accent.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scope.isRouteMode
                ? AppColors.accent.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              scope.isRouteMode ? Icons.route : Icons.tune_outlined,
              size: 14,
              color: scope.isRouteMode ? AppColors.accent : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scope.isRouteMode
                      ? AppColors.accent
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more,
              size: 14,
              color: scope.isRouteMode
                  ? AppColors.accent
                  : Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
