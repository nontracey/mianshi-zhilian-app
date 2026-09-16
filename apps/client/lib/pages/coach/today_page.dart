/// 「今天」入口：到期回测 + 一个知识点 + 项目训练。
///
/// 计划由确定性 [PlanService] 生成并冻结，模型只建议优先级（§9.6）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/domain/common.dart';
import '../../coach/domain/plan.dart';
import '../../providers/coach_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import 'coach_widgets.dart';
import 'coach_session_page.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final coach = context.read<CoachProvider>();
    if (coach.loaded) {
      // 已有档案：确保今天有计划。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        coach.ensureTodayPlan();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final l10n = context.watch<LocalizationProvider>();
    final plan = coach.todayPlan;
    final goal = coach.activeGoal;
    final hasCompany = goal?.company?.isNotEmpty ?? false;

    return CoachPageScaffold(
      title: l10n.get('coach_today_title'),
      subtitle: goal == null
          ? l10n.get('coach_today_subtitle_no_goal')
          : (hasCompany
                ? l10n.getp('coach_today_subtitle_goal_company', {
                    'title': goal.title,
                    'company': goal.company!,
                  })
                : l10n.getp('coach_today_subtitle_goal', {
                    'title': goal.title,
                  })),
      actions: [
        IconButton(
          tooltip: l10n.get('coach_today_add_knowledge'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _showAddKnowledge(context, coach, l10n),
        ),
      ],
      children: [
        if (goal == null)
          CoachNoticeBanner(
            message: l10n.get('coach_today_no_goal_banner'),
            tone: CoachNoticeTone.warning,
          ),

        coachPanel(
          title: l10n.get('coach_today_overview'),
          icon: Icons.insights_outlined,
          children: [
            Row(
              children: [
                _Stat(
                  label: l10n.get('coach_today_stat_plan'),
                  value: '${coach.completedCount}/${coach.planDenominator}',
                  color: AppColors.accent,
                ),
                _Stat(
                  label: l10n.get('coach_today_stat_due'),
                  value: '${coach.dueCount}',
                  color: coach.dueCount > 0
                      ? AppColors.warning
                      : AppColors.success,
                ),
                _Stat(
                  label: l10n.get('coach_today_stat_items'),
                  value: '${coach.knowledgeItems.length}',
                  color: AppColors.info,
                ),
              ],
            ),
          ],
        ),

        coachPanel(
          title: l10n.get('coach_today_plan'),
          icon: Icons.checklist_rtl,
          trailing: TextButton(
            onPressed: plan != null && plan.completedCount == plan.denominator
                ? () => coach.addExtraPlan()
                : null,
            child: Text(l10n.get('coach_today_add_extra')),
          ),
          children: [
            if (plan == null || plan.planItems.isEmpty)
              CoachEmptyHint(
                icon: Icons.event_available_outlined,
                message: l10n.get('coach_today_plan_empty'),
              )
            else
              ...plan.planItems.map(
                (item) => _PlanItemTile(
                  label: _planItemLabel(l10n, item, isExtraPlan: plan.isExtra),
                  estimatedMinutes: item.estimatedMinutes,
                  completed: item.completed,
                  onToggle: () => coach.togglePlanItem(item.id),
                  onStart: () async {
                    final session = await coach.startPlanItem(item.id);
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CoachSessionPage(mode: session.mode),
                      ),
                    );
                  },
                ),
              ),
            for (final extra in coach.extraPlans)
              ...extra.planItems.map(
                (item) => _PlanItemTile(
                  label: _planItemLabel(l10n, item, isExtraPlan: true),
                  estimatedMinutes: item.estimatedMinutes,
                  completed: item.completed,
                  onToggle: () => coach.togglePlanItem(item.id),
                  onStart: () async {
                    final session = await coach.startPlanItem(item.id);
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CoachSessionPage(mode: session.mode),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),

        coachPanel(
          title: l10n.get('coach_today_start'),
          icon: Icons.play_circle_outline,
          children: [
            _StartButton(
              label: l10n.get('coach_today_start_learn'),
              subtitle: l10n.get('coach_today_start_learn_sub'),
              icon: Icons.menu_book_outlined,
              color: AppColors.accent,
              onTap: () => _start(context, SessionMode.learning),
            ),
            const SizedBox(height: 8),
            _StartButton(
              label: l10n.get('coach_today_start_review'),
              subtitle: coach.dueCount > 0
                  ? l10n.getp('coach_today_start_review_sub_due', {
                      'count': coach.dueCount,
                    })
                  : l10n.get('coach_today_start_review_sub_none'),
              icon: Icons.replay_outlined,
              color: AppColors.success,
              onTap: () => _start(context, SessionMode.review),
            ),
            const SizedBox(height: 8),
            _StartButton(
              label: l10n.get('coach_today_start_interview'),
              subtitle: l10n.get('coach_today_start_interview_sub'),
              icon: Icons.record_voice_over_outlined,
              color: AppColors.warning,
              onTap: () => _start(context, SessionMode.interview),
            ),
          ],
        ),
      ],
    );
  }

  /// 计划项文案由类型决定（模型/服务端的默认标题不直接展示）。
  static String _planItemLabel(
    LocalizationProvider l10n,
    PlanItem item, {
    required bool isExtraPlan,
  }) {
    if (isExtraPlan && item.type == PlanItemType.reviewLearned) {
      return l10n.get('coach_today_extra_title');
    }
    switch (item.type) {
      case PlanItemType.learnKnowledge:
        return l10n.get('coach_learn_item_title');
      case PlanItemType.reviewLearned:
        return l10n.get('coach_review_item_title');
      case PlanItemType.projectTraining:
        return l10n.get('coach_project_item_title');
      case PlanItemType.mockInterview:
        return l10n.get('coach_mock_item_title');
    }
  }

  Future<void> _start(BuildContext context, SessionMode mode) async {
    final coach = context.read<CoachProvider>();
    coach.setMode(mode);
    await coach.startSession(mode: mode);
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CoachSessionPage(mode: mode)));
  }

  Future<void> _showAddKnowledge(
    BuildContext context,
    CoachProvider coach,
    LocalizationProvider l10n,
  ) async {
    final titleController = TextEditingController();
    final pointsController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.get('coach_today_add_knowledge')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.get('coach_today_knowledge_label'),
                hintText: l10n.get('coach_today_knowledge_hint'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pointsController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.get('coach_today_points_label'),
                hintText: l10n.get('coach_today_points_hint'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n.get('add')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final title = titleController.text.trim();
    if (title.isEmpty) return;
    final labels = pointsController.text
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    await coach.addKnowledgeItem(title, reviewPointLabels: labels);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.getp('coach_today_added', {'title': title}))),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanItemTile extends StatelessWidget {
  const _PlanItemTile({
    required this.label,
    required this.estimatedMinutes,
    required this.completed,
    required this.onToggle,
    required this.onStart,
  });

  final String label;
  final int estimatedMinutes;
  final bool completed;
  final VoidCallback onToggle;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onStart,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            IconButton(
              onPressed: onToggle,
              icon: Icon(
                completed ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: completed
                    ? AppColors.success
                    : (isDark ? Colors.white38 : Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  decoration: completed ? TextDecoration.lineThrough : null,
                  color: completed
                      ? (isDark ? Colors.white38 : AppColors.textTertiary)
                      : (isDark ? Colors.white : AppColors.textPrimary),
                ),
              ),
            ),
            Text(
              '$estimatedMinutes min',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}
