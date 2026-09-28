import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../coach/persistence/sync_conflicts.dart';
import '../../coach/persistence/workflow_repository.dart';
import '../../coach/domain/plan.dart';
import '../../coach/knowledge/source.dart';
import '../../providers/coach_provider.dart';
import '../../providers/localization_provider.dart';
import 'coach_widgets.dart';

class CoachSyncConflictsPage extends StatefulWidget {
  const CoachSyncConflictsPage({super.key});
  @override
  State<CoachSyncConflictsPage> createState() => _CoachSyncConflictsPageState();
}

class _CoachSyncConflictsPageState extends State<CoachSyncConflictsPage> {
  late Future<List<CoachSyncConflict>> _future;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final coach = context.read<CoachProvider>();
    _future = CoachSyncConflictService(coach.store, coach.profileId).listOpen();
  }

  Future<void> _resolve(CoachSyncConflict conflict, bool variant) async {
    final coach = context.read<CoachProvider>();
    final l10n = context.read<LocalizationProvider>();
    if (coach.isGenerating) return;
    setState(() => _busy = true);
    try {
      await CoachSyncConflictService(
        coach.store,
        coach.profileId,
      ).resolve(conflict, chooseVariant: variant, now: coach.clock.now());
      await coach.reload();
      if (mounted) setState(_reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('coach_sync_conflict_changed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final coach = context.watch<CoachProvider>();
    return CoachPageScaffold(
      title: l10n.get('coach_sync_conflicts'),
      subtitle: l10n.get('coach_sync_conflicts_note'),
      children: [
        FutureBuilder<List<CoachSyncConflict>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return CoachNoticeBanner(
                message: l10n.get('coach_sync_conflict_changed'),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            if (snapshot.data!.isEmpty) {
              return CoachEmptyHint(
                icon: Icons.check_circle_outline,
                message: l10n.get('coach_sync_no_conflicts'),
              );
            }
            return Column(
              children: [
                for (final conflict in snapshot.data!)
                  FutureBuilder<(String, String)>(
                    future: () async {
                      if (conflict.table == 'dailyPlans') {
                        final a = await coach.store.getDailyPlan(
                              conflict.entityId,
                            ),
                            b = await coach.store.getDailyPlan(
                              conflict.variantId,
                            );
                        return (
                          a?.planItems
                                  .map(
                                    (i) =>
                                        '${_typeName(l10n, i.type)} · ${i.knowledgeItemId ?? i.projectId ?? i.goalId ?? ''} · ${i.estimatedMinutes} min',
                                  )
                                  .join('\n') ??
                              '',
                          b?.planItems
                                  .map(
                                    (i) =>
                                        '${_typeName(l10n, i.type)} · ${i.knowledgeItemId ?? i.projectId ?? i.goalId ?? ''} · ${i.estimatedMinutes} min',
                                  )
                                  .join('\n') ??
                              '',
                        );
                      }
                      if (conflict.table == 'assessmentEvents') {
                        final a = conflict.record.value['primary'] as Map?;
                        final b = conflict.record.value['variant'] as Map?;
                        return (
                          _assessmentSummary(l10n, a),
                          _assessmentSummary(l10n, b),
                        );
                      }
                      if (conflict.table == 'sources') {
                        final a = await coach.store.getSource(
                          conflict.entityId,
                        );
                        final b = await coach.store.getSource(
                          conflict.variantId,
                        );
                        return (_sourceSummary(a), _sourceSummary(b));
                      }
                      final repo = WorkflowRepository(coach.store);
                      final a = await repo.getTemplate(
                            coach.profileId,
                            conflict.entityId,
                          ),
                          b = await repo.getTemplate(
                            coach.profileId,
                            conflict.variantId,
                          );
                      return (
                        a?.cards
                                .map(
                                  (c) =>
                                      '${_typeName(l10n, c.type)} · ${c.knowledgeItemId ?? c.projectId ?? c.goalId ?? ''} · ${c.estimatedMinutes ?? 0} min',
                                )
                                .join('\n') ??
                            '',
                        b?.cards
                                .map(
                                  (c) =>
                                      '${_typeName(l10n, c.type)} · ${c.knowledgeItemId ?? c.projectId ?? c.goalId ?? ''} · ${c.estimatedMinutes ?? 0} min',
                                )
                                .join('\n') ??
                            '',
                      );
                    }(),
                    builder: (context, versions) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conflict.table == 'dailyPlans'
                                  ? l10n.get('coach_sync_plan_conflict')
                                  : conflict.table == 'assessmentEvents'
                                  ? l10n.get('coach_sync_assessment_conflict')
                                  : conflict.table == 'sources'
                                  ? l10n.get('coach_sync_source_conflict')
                                  : l10n.get('coach_sync_template_conflict'),
                            ),
                            Text(l10n.get('coach_sync_primary_version')),
                            Text(
                              versions.data?.$1 ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(l10n.get('coach_sync_variant_version')),
                            Text(
                              versions.data?.$2 ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: _busy || coach.isGenerating
                                      ? null
                                      : () => _resolve(conflict, false),
                                  child: Text(
                                    l10n.get('coach_sync_choose_primary'),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: _busy || coach.isGenerating
                                      ? null
                                      : () => _resolve(conflict, true),
                                  child: Text(
                                    l10n.get('coach_sync_choose_variant'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _typeName(LocalizationProvider l10n, PlanItemType type) =>
    l10n.get(switch (type) {
      PlanItemType.learnKnowledge => 'coach_learn_item_title',
      PlanItemType.reviewLearned => 'coach_review_item_title',
      PlanItemType.projectTraining => 'coach_project_item_title',
      PlanItemType.mockInterview => 'coach_mock_item_title',
    });

String _assessmentSummary(LocalizationProvider l10n, Map? event) {
  final key = switch (event?['result']) {
    'independentPass' => 'coach_result_independent_pass',
    'needsReinforcement' => 'coach_result_needs_reinforcement',
    'hintCompleted' => 'coach_result_hint_completed',
    _ => 'coach_validity_pending',
  };
  final rationale = event?['rationale']?.toString() ?? '';
  return rationale.isEmpty ? l10n.get(key) : '${l10n.get(key)} · $rationale';
}

String _sourceSummary(Source? source) {
  if (source == null) return '';
  final content = source.content?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  final preview = content.isEmpty
      ? source.contentHash
      : content.substring(0, content.length < 120 ? content.length : 120);
  return '${source.title} · v${source.revision}\n$preview';
}
