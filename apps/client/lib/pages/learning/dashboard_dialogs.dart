import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

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
