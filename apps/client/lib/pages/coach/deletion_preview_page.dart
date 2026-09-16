/// 删除影响预览（§6.8、§11）。
///
/// 当前只执行 JD 删除；展示关联影响并保留所有知识及历史。
/// 物理知识清理尚未接入，不展示无法执行的删除选项。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/domain/common.dart';
import '../../coach/lifecycle/lifecycle.dart';
import '../../coach/lifecycle/deletion_executor.dart';
import '../../coach/tools/tool_contract.dart';
import '../../providers/coach_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import 'coach_widgets.dart';

/// 打开删除预览页。返回提交结果（用户取消则为 null）。
Future<DeletionCommitResult?> openDeletionPreview(
  BuildContext context, {
  required List<GoalId> goalIds,
}) {
  return Navigator.of(context).push<DeletionCommitResult>(
    MaterialPageRoute(builder: (_) => DeletionPreviewPage(goalIds: goalIds)),
  );
}

class DeletionPreviewPage extends StatefulWidget {
  const DeletionPreviewPage({super.key, required this.goalIds});

  final List<GoalId> goalIds;

  @override
  State<DeletionPreviewPage> createState() => _DeletionPreviewPageState();
}

class _DeletionPreviewPageState extends State<DeletionPreviewPage> {
  static const _planner = DeletionPlanner();
  static const _snapshotSource = StoreDeletionSnapshotSource();

  final Set<String> _cleanupIds = {};
  final Map<String, CleanupAction> _learnedActions = {};
  DeletionPreview? _preview;
  bool _loading = true;

  /// 明确勾选要清理的「未学且无引用」知识（默认空）。

  /// 已学知识的逐项处理方式（默认全部保留）。

  String? _conflictNote;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final coach = context.read<CoachProvider>();
    final snapshot = await _snapshotSource.load(
      coach.store,
      profileId: coach.profileId,
    );
    final preview = _planner.preview(
      snapshot: snapshot,
      goalIds: widget.goalIds,
      idGen: coach.idGen,
      clock: coach.clock,
    );
    if (!mounted) return;
    setState(() {
      _preview = preview;

      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading || _preview == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        appBar: AppBar(
          title: Text(l10n.get('coach_deletion_title')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final preview = _preview!;

    return CoachPageScaffold(
      title: l10n.get('coach_deletion_title'),
      subtitle: l10n.get('coach_deletion_subtitle'),
      children: [
        if (_conflictNote != null)
          CoachNoticeBanner(
            message: _conflictNote!,
            tone: CoachNoticeTone.warning,
          ),

        coachPanel(
          title: l10n.getp('coach_deletion_goals', {
            'count': preview.goalIds.length,
          }),
          icon: Icons.delete_outline,
          children: [
            if (preview.goalIds.isEmpty)
              CoachEmptyHint(
                icon: Icons.delete_outline,
                message: l10n.get('coach_deletion_nothing'),
              ),
            ...preview.historicalSnapshotNotes.map(
              (key) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  l10n.get(key),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: isDark ? Colors.white54 : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),

        if (preview.unknownGoalIds.isNotEmpty)
          coachPanel(
            title: l10n.get('coach_deletion_unknown'),
            icon: Icons.help_outline,
            children: [
              Text(
                preview.unknownGoalIds.join(', '),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: isDark ? Colors.white60 : AppColors.textSecondary,
                ),
              ),
            ],
          ),

        if (preview.affectedPlanItems > 0 || preview.affectedSessions > 0)
          coachPanel(
            title: l10n.get('coach_deletion_impact'),
            icon: Icons.event_busy_outlined,
            children: [
              if (preview.affectedPlanItems > 0)
                Text(
                  l10n.getp('coach_deletion_affected_plan', {
                    'count': preview.affectedPlanItems,
                  }),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: isDark ? Colors.white70 : AppColors.textPrimary,
                  ),
                ),
              if (preview.affectedSessions > 0)
                Text(
                  l10n.getp('coach_deletion_affected_sessions', {
                    'count': preview.affectedSessions,
                  }),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: isDark ? Colors.white70 : AppColors.textPrimary,
                  ),
                ),
            ],
          ),

        if (preview.stillReferenced.isNotEmpty)
          coachPanel(
            title: l10n.getp('coach_deletion_kept_referenced', {
              'count': preview.stillReferenced.length,
            }),
            icon: Icons.link_outlined,
            children: [
              Text(
                l10n.get('coach_deletion_kept_referenced_hint'),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: isDark ? Colors.white54 : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              ...preview.stillReferenced.map((i) => _ImpactRow(impact: i)),
            ],
          ),

        if (preview.protectedByOtherUse.isNotEmpty)
          coachPanel(
            title: l10n.getp('coach_deletion_protected', {
              'count': preview.protectedByOtherUse.length,
            }),
            icon: Icons.shield_outlined,
            children: [
              ...preview.protectedByOtherUse.map((i) => _ImpactRow(impact: i)),
            ],
          ),

        coachPanel(
          title: l10n.get('coach_deletion_retained_title'),
          icon: Icons.shield_outlined,
          children: [
            Text(l10n.get('coach_deletion_retained_hint')),
            ...preview.unreferencedUnlearned.map(
              (i) => CheckboxListTile(
                value: _cleanupIds.contains(i.knowledgeItemId),
                title: Text(i.title),
                subtitle: Text(l10n.get('coach_cleanup_unlearned')),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _cleanupIds.add(i.knowledgeItemId);
                  } else {
                    _cleanupIds.remove(i.knowledgeItemId);
                  }
                }),
              ),
            ),
            ...preview.unreferencedLearned.map(
              (i) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ImpactRow(impact: i),
                  Text(
                    l10n.getp('coach_cleanup_records', {
                      'answers': i.records.answerCount,
                      'assessments': i.records.acceptedAssessmentCount,
                    }),
                  ),
                  DropdownButton<CleanupAction>(
                    isExpanded: true,
                    value:
                        _learnedActions[i.knowledgeItemId] ??
                        CleanupAction.keepKnowledgeAndRecords,
                    items: CleanupAction.values
                        .map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text(l10n.get(_cleanupKey(a))),
                          ),
                        )
                        .toList(),
                    onChanged: (a) =>
                        setState(() => _learnedActions[i.knowledgeItemId] = a!),
                  ),
                ],
              ),
            ),
          ],
        ),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _committing
                    ? null
                    : () => Navigator.of(context).pop(),
                child: Text(l10n.get('coach_deletion_cancel')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: (_committing || preview.goalIds.isEmpty)
                    ? null
                    : _commit,
                child: Text(
                  l10n.get(
                    _committing
                        ? 'coach_deletion_committing'
                        : 'coach_deletion_confirm',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _commit() async {
    final coach = context.read<CoachProvider>();
    final l10n = context.read<LocalizationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final preview = _preview;
    if (preview == null) return;

    setState(() => _committing = true);
    try {
      // 令牌由 UI 在用户明确确认后签发，模型文本不能代替它。
      final token = ConfirmationToken(
        operationId: preview.operationId,
        issuedAt: coach.clock.now(),
        subject: preview.goalIds.join(','),
        expectedRevisions: preview.expectedRevisions,
      );

      // 提交时用**新快照**重新校验引用与学习记录。
      final removingRecords = _learnedActions.entries
          .where((e) => e.value == CleanupAction.removeKnowledgeAndRecords)
          .map((e) => e.key)
          .toSet();
      if (removingRecords.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.get('coach_cleanup_confirm_records')),
            content: Text(
              preview.unreferencedLearned
                  .where((i) => removingRecords.contains(i.knowledgeItemId))
                  .map((i) => i.title)
                  .join('\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.get('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.get('confirm')),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          if (mounted) setState(() => _committing = false);
          return;
        }
      }
      final result =
          await DeletionExecutor(store: coach.store, clock: coach.clock).commit(
            preview: preview,
            selection: DeletionSelection(
              cleanupKnowledgeIds: _cleanupIds.toList(),
              learnedActions: _learnedActions,
            ),
            token: token,
          );
      await coach.reload();

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.getp('coach_deletion_done', {
              'goals': result.deletedGoalIds.length,
              'removed': result.removedKnowledgeIds.length,
              'kept': result.retainedKnowledgeIds.length,
            }),
          ),
        ),
      );
      Navigator.of(context).pop(result);
    } on DeletionConflictException catch (e) {
      // 预览过期：刷新预览，让用户在新范围上重新确认。
      if (!mounted) return;
      setState(() {
        _committing = false;
        _preview = e.refreshedPreview;
        _cleanupIds.clear();
        _learnedActions.clear();
        _conflictNote = l10n.get('coach_deletion_conflict');
      });
    } on DeletionScopeException {
      if (!mounted) return;
      setState(() {
        _committing = false;
        _conflictNote = l10n.get('coach_deletion_scope_error');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _committing = false;
        _conflictNote = l10n.get('coach_deletion_failed');
      });
    }
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({required this.impact});

  final KnowledgeImpact impact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.circle,
            size: 7,
            color: isDark ? Colors.white38 : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              impact.title,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? Colors.white70 : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            l10n.get('coach_deletion_kept_badge'),
            style: TextStyle(
              fontSize: 10.5,
              color: isDark ? Colors.white38 : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

String _cleanupKey(CleanupAction action) => switch (action) {
  CleanupAction.keepKnowledgeAndRecords =>
    'coach_cleanup_keep_knowledge_and_records',
  CleanupAction.removeKnowledgeKeepHistory =>
    'coach_cleanup_remove_knowledge_keep_history',
  CleanupAction.removeKnowledgeAndRecords =>
    'coach_cleanup_remove_knowledge_and_records',
};
