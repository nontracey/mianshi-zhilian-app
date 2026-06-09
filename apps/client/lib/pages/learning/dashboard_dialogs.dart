import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/widgets/route_editor_dialog.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

// ── 路线选择对话框 ──

class RouteSelectorDialog extends StatefulWidget {
  const RouteSelectorDialog({
    super.key,
    required this.routes,
    required this.currentRouteId,
    required this.onRouteSelected,
    required this.availableDomains,
    this.disabledDomainIds = const [],
    this.onRoutesChanged,
  });

  final List<LearningRoute> routes;
  final String? currentRouteId;
  final ValueChanged<LearningRoute> onRouteSelected;
  final List<Domain> availableDomains;
  final List<String> disabledDomainIds;
  final VoidCallback? onRoutesChanged;

  @override
  State<RouteSelectorDialog> createState() => RouteSelectorDialogState();
}

class RouteSelectorDialogState extends State<RouteSelectorDialog> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  List<LearningRoute> _aiRoutes = [];
  List<LearningRoute> _customRoutes = [];
  LearningRoute? _interviewRoute;
  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  List<LearningRoute> get _officialRoutes =>
      widget.routes.where((r) => r.source == 'official').toList();

  Future<void> _loadRoutes() async {
    final progress = context.read<ProgressProvider>();
    final plan = progress.prepPlan;
    final customData = await _storage.loadJsonList('custom_routes');
    final allCustom = customData
        .map((e) => LearningRoute.fromJson(e))
        .toList();

    LearningRoute? interviewRoute;
    if (plan.hasTarget) {
      final interviewDate = plan.interviewDate;
      final days = interviewDate != null
          ? interviewDate.difference(DateTime.now()).inDays + 1
          : null;
      interviewRoute = LearningRoute(
        id: '__interview_target__',
        name: plan.targetRole.isNotEmpty
            ? '${plan.targetRole}${plan.techStack.isNotEmpty ? ' (${plan.techStack})' : ''}'
            : l10n.get('interview_target'),
        domainIds: [],
        description: days != null
            ? (days > 0 ? l10n.getp('days_until_interview', {'days': days}) : l10n.get('interview_day_already_to'))
            : l10n.get('interview_target_set'),
        source: 'custom',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    setState(() {
      _aiRoutes = allCustom.where((r) => r.source == 'ai').toList();
      _customRoutes = allCustom.where((r) => r.source != 'ai').toList();
      _interviewRoute = interviewRoute;
    });
  }

  Future<void> _saveCustomRoutes() async {
    final all = [..._aiRoutes, ..._customRoutes];
    await _storage.saveJsonList(
      'custom_routes',
      all.map((r) => r.toJson()).toList(),
    );
  }

  void _addCustomRoute(LearningRoute route) {
    setState(() {
      _customRoutes.add(route);
    });
    _saveCustomRoutes();
  }

  void _updateRoute(String routeId, LearningRoute route) {
    final aiIndex = _aiRoutes.indexWhere((r) => r.id == routeId);
    if (aiIndex >= 0) {
      setState(() {
        _aiRoutes[aiIndex] = route;
      });
      _saveCustomRoutes();
      return;
    }
    final customIndex = _customRoutes.indexWhere((r) => r.id == routeId);
    if (customIndex >= 0) {
      setState(() {
        _customRoutes[customIndex] = route;
      });
      _saveCustomRoutes();
    }
  }

  void _deleteRoute(String routeId) {
    setState(() {
      _aiRoutes.removeWhere((r) => r.id == routeId);
      _customRoutes.removeWhere((r) => r.id == routeId);
    });
    _saveCustomRoutes();
    widget.onRoutesChanged?.call();
  }

  List<String> get _allRouteNames => [
    ..._officialRoutes.map((r) => r.name),
    ..._aiRoutes.map((r) => r.name),
    ..._customRoutes.map((r) => r.name),
  ];

  (int mastered, int total) _getPhaseProgress(LearningRoute route) {
    if (route.phases == null || route.phases!.isEmpty) {
      final progress = context.read<ProgressProvider>();
      final topics = context.read<ContentProvider>().topics;
      var mastered = 0;
      var total = 0;
      for (final id in route.domainIds) {
        for (final t in topics.values) {
          if (t.domainId == id) {
            total++;
            if ((progress.getTopicProgress(t.id)?.score ?? 0) >= 85) mastered++;
          }
        }
      }
      return total > 0 ? (mastered, total) : (0, 0);
    }
    final progress = context.read<ProgressProvider>();
    var mastered = 0;
    final total = route.phases!.length;
    for (final phase in route.phases!) {
      if (phase.topicIds.isEmpty) { mastered++; continue; }
      var pm = 0;
      for (final tid in phase.topicIds) {
        if ((progress.getTopicProgress(tid)?.score ?? 0) >= 85) pm++;
      }
      if (pm == phase.topicIds.length) mastered++;
    }
    return (mastered, total);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  l10n.get('select_study_route'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 路线列表
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 官方路线
                    if (_officialRoutes.isNotEmpty) ...[
                      _SectionHeader(label: '官方路线'),
                      ..._officialRoutes.map((route) {
                        final (m, t) = _getPhaseProgress(route);
                        return _RouteTile(
                          route: route,
                          isSelected: route.id == widget.currentRouteId,
                          isDark: isDark,
                          phaseProgress: t > 0 ? m : null,
                          phaseTotal: t > 0 ? t : null,
                          onTap: () {
                            widget.onRouteSelected(route);
                            Navigator.pop(context);
                          },
                        );
                      }),
                      const SizedBox(height: 8),
                    ],

                    // AI 个性化路线
                    if (_aiRoutes.isNotEmpty) ...[
                      _SectionHeader(label: 'AI 个性化'),
                      ..._aiRoutes.asMap().entries.map((entry) {
                        final route = entry.value;
                        final (m, t) = _getPhaseProgress(route);
                        return _RouteTile(
                          route: route,
                          isSelected: route.id == widget.currentRouteId,
                          isDark: isDark,
                          phaseProgress: t > 0 ? m : null,
                          phaseTotal: t > 0 ? t : null,
                          badge: const Text('AI', style: TextStyle(fontSize: 9, color: AppColors.accent)),
                          onTap: () {
                            widget.onRouteSelected(route);
                            Navigator.pop(context);
                          },
                          onEdit: () {
                            final enabledDomains = widget.availableDomains
                                .where((d) => !widget.disabledDomainIds.contains(d.id))
                                .toList();
                            showDialog(
                              context: context,
                              builder: (ctx) => RouteEditorDialog(
                                availableDomains: enabledDomains
                                    .map((d) => DomainItem(id: d.id, title: d.title))
                                    .toList(),
                                existingRoute: route,
                                existingRouteNames: _allRouteNames,
                                onSave: (updatedRoute) {
                                  _updateRoute(route.id, updatedRoute);
                                  if (route.id == widget.currentRouteId) {
                                    widget.onRouteSelected(updatedRoute);
                                  }
                                },
                              ),
                            );
                          },
                          onDelete: () => _deleteRoute(route.id),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],

                    // 自定义路线
                    if (_customRoutes.isNotEmpty) ...[
                      _SectionHeader(label: l10n.get('custom')),
                      ..._customRoutes.asMap().entries.map((entry) {
                        final route = entry.value;
                        final (m, t) = _getPhaseProgress(route);
                        return _RouteTile(
                          route: route,
                          isSelected: route.id == widget.currentRouteId,
                          isDark: isDark,
                          phaseProgress: t > 0 ? m : null,
                          phaseTotal: t > 0 ? t : null,
                          badge: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              l10n.get('custom'),
                              style: const TextStyle(fontSize: 9, color: AppColors.accent),
                            ),
                          ),
                          onTap: () {
                            widget.onRouteSelected(route);
                            Navigator.pop(context);
                          },
                          onEdit: () {
                            final enabledDomains = widget.availableDomains
                                .where((d) => !widget.disabledDomainIds.contains(d.id))
                                .toList();
                            showDialog(
                              context: context,
                              builder: (ctx) => RouteEditorDialog(
                                availableDomains: enabledDomains
                                    .map((d) => DomainItem(id: d.id, title: d.title))
                                    .toList(),
                                existingRoute: route,
                                existingRouteNames: _allRouteNames,
                                onSave: (updatedRoute) {
                                  _updateRoute(route.id, updatedRoute);
                                  if (route.id == widget.currentRouteId) {
                                    widget.onRouteSelected(updatedRoute);
                                  }
                                },
                              ),
                            );
                          },
                          onDelete: () => _deleteRoute(route.id),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],

                    // 面试目标路线
                    if (_interviewRoute != null) ...[
                      _SectionHeader(label: l10n.get('interview_target')),
                      _buildInterviewRouteTile(_interviewRoute!, isDark),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 创建自定义路线
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final enabledDomains = widget.availableDomains
                      .where((d) => !widget.disabledDomainIds.contains(d.id))
                      .toList();
                  showDialog(
                    context: context,
                    builder: (ctx) => RouteEditorDialog(
                      availableDomains: enabledDomains
                          .map((d) => DomainItem(id: d.id, title: d.title))
                          .toList(),
                      existingRouteNames: _allRouteNames,
                      onSave: _addCustomRoute,
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: Text(l10n.get('create_build_custom_route')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterviewRouteTile(LearningRoute route, bool isDark) {
    final plan = context.watch<ProgressProvider>().prepPlan;
    final interviewDate = plan.interviewDate;
    final days = interviewDate != null
        ? interviewDate.difference(DateTime.now()).inDays + 1
        : null;

    return _RouteTile(
      route: route,
      isSelected: route.id == widget.currentRouteId,
      isDark: isDark,
      badge: days != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: (days > 0 ? AppColors.warning : AppColors.danger).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                days > 0 ? l10n.getp('countdown_days', {'days': days}) : l10n.get('expired_already'),
                style: TextStyle(
                  fontSize: 9,
                  color: days > 0 ? AppColors.warning : AppColors.danger,
                ),
              ),
            )
          : null,
      onTap: () {
        widget.onRouteSelected(route);
        Navigator.pop(context);
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.route,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
    this.badge,
    this.onEdit,
    this.onDelete,
    this.phaseProgress,
    this.phaseTotal,
  });

  final LearningRoute route;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final Widget? badge;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final int? phaseProgress;
  final int? phaseTotal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.accent
                  : (isDark
                        ? AppColors.borderMidnight
                        : const Color(0xFFE0E0E0)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          route.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? AppColors.accent : null,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          badge!,
                        ],
                      ],
                    ),
                    if (route.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          route.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.grey,
                          ),
                        ),
                      ),
                    if (phaseProgress != null &&
                        phaseTotal != null &&
                        phaseTotal! > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: phaseProgress! / phaseTotal!,
                                minHeight: 4,
                                backgroundColor: isDark
                                    ? AppColors.borderMidnight
                                    : const Color(0xFFE8E8E8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$phaseProgress/$phaseTotal',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white54
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: isDark ? Colors.white54 : Colors.grey,
                  onPressed: onEdit,
                ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.shade300,
                  onPressed: onDelete,
                ),
              if (isSelected)
                const Icon(Icons.check_circle, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 管理领域对话框 ──

class ManageDomainsDialog extends StatefulWidget {
  const ManageDomainsDialog({
    super.key,
    required this.domains,
    required this.disabledDomainIds,
    required this.onToggleDomain,
  });

  final List<Domain> domains;
  final Set<String> disabledDomainIds;
  final ValueChanged<String> onToggleDomain;

  @override
  State<ManageDomainsDialog> createState() => ManageDomainsDialogState();
}

class ManageDomainsDialogState extends State<ManageDomainsDialog> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  late Set<String> _disabledIds;

  @override
  void initState() {
    super.initState();
    _disabledIds = Set.from(widget.disabledDomainIds);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school_outlined, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  l10n.get('management_domain'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('toggle_switch_open_close_come_enable_disable_domain'),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ),
            const SizedBox(height: 16),

            // 领域列表
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                child: Column(
                  children: widget.domains.map((domain) {
                    final isDisabled = _disabledIds.contains(domain.id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDisabled
                            ? (isDark
                                  ? AppColors.surfaceDark
                                  : Colors.grey.shade100)
                            : (isDark
                                  ? AppColors.surfaceMidnight
                                  : Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDisabled
                              ? (isDark
                                    ? AppColors.borderDarkSubtle
                                    : Colors.grey.shade200)
                              : (isDark
                                    ? AppColors.borderMidnight
                                    : AppColors.borderLight),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  domain.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDisabled
                                        ? Colors.grey
                                        : (isDark
                                              ? Colors.white
                                              : AppColors.textPrimary),
                                  ),
                                ),
                                Text(
                                  l10n.getp('count_knowledge_point_2', {
                                    'count': domain.topicCount,
                                  }),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDisabled
                                        ? Colors.grey
                                        : (isDark
                                              ? Colors.white54
                                              : Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: !isDisabled,
                            onChanged: (value) {
                              setState(() {
                                if (isDisabled) {
                                  _disabledIds.remove(domain.id);
                                } else {
                                  _disabledIds.add(domain.id);
                                }
                                widget.onToggleDomain(domain.id);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 说明
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.get(
                        'disable_domain_not_will_at_first_page_show_but_conten',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 面试目标编辑对话框 ──

void showPlanEditDialog(
  BuildContext context,
  ProgressProvider progress,
  PrepPlan current,
  LocalizationProvider l10n,
) {
  final roleController = TextEditingController(text: current.targetRole);
  final stackController = TextEditingController(text: current.techStack);
  final jdController = TextEditingController(text: current.jobDescription);
  var dailyMinutes = current.dailyMinutes;
  DateTime? interviewDate = current.interviewDate;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(l10n.get('interview_goal')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: roleController,
                  decoration: InputDecoration(
                    labelText: l10n.get('goal_position_optional_select'),
                    hintText: l10n.get(
                      'java_backend_ai_engineering_transform_architect',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stackController,
                  decoration: InputDecoration(
                    labelText: l10n.get('tech_stack_optional_select'),
                    hintText: 'Spring Cloud, Redis, RAG...',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.getp('daily_send_enter_minutes_min_2', {
                          'minutes': dailyMinutes,
                        }),
                      ),
                    ),
                    IconButton(
                      onPressed: dailyMinutes > 15
                          ? () => setDialogState(() => dailyMinutes -= 15)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      onPressed: () =>
                          setDialogState(() => dailyMinutes += 15),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate:
                          interviewDate ??
                          DateTime.now().add(const Duration(days: 14)),
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => interviewDate = picked);
                    }
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    interviewDate == null
                        ? l10n.get('select_interview_day_optional')
                        : l10n.getp('interview_day_year_month_day', {
                            'year': interviewDate!.year,
                            'month': interviewDate!.month,
                            'day': interviewDate!.day,
                          }),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: jdController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: l10n.get(
                      'position_description_jd_optional_select_local_save',
                    ),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              progress.updatePrepPlan(
                PrepPlan(
                  targetRole: roleController.text.trim(),
                  techStack: stackController.text.trim(),
                  interviewDate: interviewDate,
                  dailyMinutes: dailyMinutes,
                  jobDescription: jdController.text.trim(),
                  updatedAt: DateTime.now(),
                ),
              );
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    ),
  );
}
