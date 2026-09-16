/// Persistence adapter for templates, runs and auditable plan adjustments.
library;

import '../domain/common.dart';
import '../domain/plan.dart';
import '../workflows/workflow_run.dart';
import '../workflows/workflow_template.dart';
import 'coach_store.dart';
import 'extension_records.dart';

class PlanAdjustment {
  const PlanAdjustment({
    required this.id,
    required this.profileId,
    required this.planId,
    required this.before,
    required this.after,
    required this.diff,
    required this.createdAt,
    this.undoAllowed = true,
    this.undoReason,
  });

  final String id;
  final ProfileId profileId;
  final DailyPlanId planId;
  final DailyPlan before;
  final DailyPlan after;
  final List<String> diff;
  final DateTime createdAt;
  final bool undoAllowed;
  final String? undoReason;

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'planId': planId,
    'before': before.toJson(),
    'after': after.toJson(),
    'diff': diff,
    'createdAt': createdAt.toIso8601String(),
    'undoAllowed': undoAllowed,
    'undoReason': undoReason,
  };

  factory PlanAdjustment.fromJson(Map<String, Object?> json) => PlanAdjustment(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    planId: json['planId'] as String,
    before: DailyPlan.fromJson(_map(json['before'])),
    after: DailyPlan.fromJson(_map(json['after'])),
    diff: (json['diff'] as List? ?? const [])
        .map((item) => item as String)
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    undoAllowed: json['undoAllowed'] as bool? ?? true,
    undoReason: json['undoReason'] as String?,
  );
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('expected JSON object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

class WorkflowRepository {
  const WorkflowRepository(this.store);

  final CoachStore store;

  Future<void> putTemplate(
    WorkflowTemplate template, {
    required ProfileId profileId,
    required DateTime updatedAt,
  }) => store.putExtension(
    CoachExtensionRecord(
      profileId: profileId,
      kind: CoachExtensionKind.workflowTemplate,
      id: template.id,
      revision: template.version,
      value: template.toJson(),
      updatedAt: updatedAt,
    ),
  );

  Future<WorkflowTemplate?> getTemplate(ProfileId profileId, String id) async {
    final record = await store.getExtension(
      profileId,
      CoachExtensionKind.workflowTemplate,
      id,
    );
    return record == null
        ? null
        : WorkflowTemplate.fromJson(_map(record.value));
  }

  Future<List<WorkflowTemplate>> listTemplates(ProfileId profileId) async =>
      (await store.listExtensions(
            profileId,
            CoachExtensionKind.workflowTemplate,
          ))
          .map((record) => WorkflowTemplate.fromJson(_map(record.value)))
          .toList();

  Future<void> deleteTemplate(ProfileId profileId, String id) =>
      store.deleteExtension(profileId, CoachExtensionKind.workflowTemplate, id);

  Future<void> putRun(WorkflowRun run, {required DateTime updatedAt}) =>
      store.putExtension(
        CoachExtensionRecord(
          profileId: run.profileId,
          kind: CoachExtensionKind.workflowRun,
          id: run.id,
          revision: run.currentIndex,
          value: run.toJson(),
          updatedAt: updatedAt,
        ),
      );

  Future<WorkflowRun?> getRun(ProfileId profileId, String id) async {
    final record = await store.getExtension(
      profileId,
      CoachExtensionKind.workflowRun,
      id,
    );
    return record == null ? null : WorkflowRun.fromJson(_map(record.value));
  }

  Future<List<WorkflowRun>> listRuns(ProfileId profileId) async =>
      (await store.listExtensions(
        profileId,
        CoachExtensionKind.workflowRun,
      )).map((record) => WorkflowRun.fromJson(_map(record.value))).toList();

  Future<void> putAdjustment(PlanAdjustment adjustment) => store.putExtension(
    CoachExtensionRecord(
      profileId: adjustment.profileId,
      kind: CoachExtensionKind.planAdjustment,
      id: adjustment.id,
      revision: adjustment.after.version,
      value: adjustment.toJson(),
      updatedAt: adjustment.createdAt,
    ),
  );

  Future<List<PlanAdjustment>> listAdjustments(ProfileId profileId) async =>
      (await store.listExtensions(
        profileId,
        CoachExtensionKind.planAdjustment,
      )).map((record) => PlanAdjustment.fromJson(_map(record.value))).toList();
}
