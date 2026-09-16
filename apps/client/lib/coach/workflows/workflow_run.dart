/// 训练安排运行实例与运行期编辑规则（§9.7）。
///
/// `workflow_run` 只追踪执行到了哪张卡片、暂停在哪里；实际题目、证据、回测与完成
/// 事实仍落在原有 session / plan 表里。**完成一张卡片不等于内容已经掌握。**
///
/// 本文件是纯 Dart，不依赖 Flutter。
library;

import '../domain/common.dart';
import 'workflow_template.dart';

/// 运行期编辑导致暂停时的提示 key。
const String workflowEditPausedKey = 'coach_workflow_edit_paused_current_card';

/// 一次训练安排执行实例。
class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.profileId,
    required this.templateId,
    required this.templateVersion,
    required this.cardIds,
    this.planId,
    this.currentIndex = 0,
    this.status = RuntimeStatus.idle,
    this.pausedCardIds = const {},
    this.skippedCardIds = const {},
    this.completedIds,
  });

  final String id;
  final ProfileId profileId;
  final String templateId;
  final int templateVersion;
  final List<String> cardIds;
  final DailyPlanId? planId;

  /// 当前卡片下标。等于 [cardIds] 长度表示已全部走完。
  final int currentIndex;
  final RuntimeStatus status;
  final Set<String> pausedCardIds;
  final Set<String> skippedCardIds;
  final Set<String>? completedIds;

  /// 已完成的卡片（下标在当前卡片之前）。
  List<String> get completedCardIds => completedIds != null
      ? cardIds.where(completedIds!.contains).toList()
      : cardIds
            .take(currentIndex.clamp(0, cardIds.length))
            .where((id) => !skippedCardIds.contains(id))
            .toList();

  /// 当前卡片。
  String? get currentCardId =>
      currentIndex < cardIds.length ? cardIds[currentIndex] : null;

  /// 尚未开始的卡片。
  List<String> get notStartedCardIds => cardIds
      .where(
        (id) =>
            id != currentCardId &&
            !completedCardIds.contains(id) &&
            !skippedCardIds.contains(id),
      )
      .toList();

  bool get finished => currentIndex >= cardIds.length;

  int _nextIndex(Set<String> completed, Set<String> skipped) {
    for (final index in [
      for (var i = currentIndex + 1; i < cardIds.length; i++) i,
      for (var i = 0; i <= currentIndex && i < cardIds.length; i++) i,
    ]) {
      if (!completed.contains(cardIds[index]) &&
          !skipped.contains(cardIds[index]))
        return index;
    }
    return cardIds.length;
  }

  WorkflowRun advance() {
    if (finished) return this;
    final completed = {
      ...completedCardIds,
      if (currentCardId != null) currentCardId!,
    };
    final next = _nextIndex(completed, skippedCardIds);
    return copyWith(
      completedIds: completed,
      currentIndex: next,
      status: next >= cardIds.length
          ? RuntimeStatus.completed
          : RuntimeStatus.waitingUser,
    );
  }

  WorkflowRun pause() => copyWith(status: RuntimeStatus.paused);
  WorkflowRun resume() => copyWith(status: RuntimeStatus.waitingUser);

  WorkflowRun skipCurrent() {
    final card = currentCardId;
    if (card == null) return this;
    final skipped = {...skippedCardIds, card};
    final completed = completedCardIds.toSet();
    final next = _nextIndex(completed, skipped);
    return copyWith(
      skippedCardIds: skipped,
      completedIds: completed,
      currentIndex: next,
      status: next >= cardIds.length
          ? RuntimeStatus.completed
          : RuntimeStatus.waitingUser,
    );
  }

  WorkflowRun copyWith({
    int? currentIndex,
    RuntimeStatus? status,
    Set<String>? pausedCardIds,
    Set<String>? skippedCardIds,
    Set<String>? completedIds,
    DailyPlanId? planId,
  }) {
    return WorkflowRun(
      id: id,
      profileId: profileId,
      templateId: templateId,
      templateVersion: templateVersion,
      cardIds: cardIds,
      planId: planId ?? this.planId,
      currentIndex: currentIndex ?? this.currentIndex,
      status: status ?? this.status,
      pausedCardIds: pausedCardIds ?? this.pausedCardIds,
      skippedCardIds: skippedCardIds ?? this.skippedCardIds,
      completedIds: completedIds ?? this.completedIds,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'templateId': templateId,
    'templateVersion': templateVersion,
    'cardIds': cardIds,
    'planId': planId,
    'currentIndex': currentIndex,
    'status': status.name,
    'pausedCardIds': pausedCardIds.toList(),
    'skippedCardIds': skippedCardIds.toList(),
    'completedIds': completedIds?.toList(),
  };

  factory WorkflowRun.fromJson(Map<String, Object?> json) => WorkflowRun(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    templateId: json['templateId'] as String,
    templateVersion: json['templateVersion'] as int,
    cardIds: (json['cardIds'] as List? ?? const [])
        .map((item) => item as String)
        .toList(),
    planId: json['planId'] as String?,
    completedIds: (json['completedIds'] as List?)?.cast<String>().toSet(),
    currentIndex: json['currentIndex'] as int? ?? 0,
    status: RuntimeStatus.values.byName(
      json['status'] as String? ?? RuntimeStatus.idle.name,
    ),
    pausedCardIds: ((json['pausedCardIds'] as List? ?? const [])
        .map((item) => item as String)
        .toSet()),
    skippedCardIds: ((json['skippedCardIds'] as List? ?? const [])
        .map((item) => item as String)
        .toSet()),
  );
}

/// 运行期编辑决定。
class RuntimeEditDecision {
  const RuntimeEditDecision({
    required this.applyToCardIds,
    required this.mustPauseFirst,
    required this.ignoredCompletedCardIds,
    this.pauseReasonKey,
  });

  /// 本次编辑实际会生效的卡片（只含未开始卡片）。
  final List<String> applyToCardIds;

  /// 是否必须先保存问答并暂停（编辑命中了当前正在进行的卡片）。
  final bool mustPauseFirst;

  /// 已产生证据、不能再改的卡片。
  final List<String> ignoredCompletedCardIds;

  final String? pauseReasonKey;
}

/// 运行中编辑默认只影响未开始卡片。
///
/// 改变当前卡片时先保存问答并暂停，在问答边界切换；已完成卡片已经产生证据，
/// 不因编辑被重写。改模板不热更新已开始的执行实例。
RuntimeEditDecision planRuntimeEdit(
  WorkflowRun run,
  Set<String> editedCardIds,
) {
  final current = run.currentCardId;
  final editable = run.notStartedCardIds.toSet();
  final completed = run.completedCardIds.toSet();

  final apply = <String>[
    for (final id in run.cardIds)
      if (editedCardIds.contains(id) && editable.contains(id)) id,
  ];

  final ignored = <String>[
    for (final id in run.cardIds)
      if (editedCardIds.contains(id) && completed.contains(id)) id,
  ];

  final hitsCurrent = current != null && editedCardIds.contains(current);
  return RuntimeEditDecision(
    applyToCardIds: apply,
    mustPauseFirst: hitsCurrent,
    ignoredCompletedCardIds: ignored,
    pauseReasonKey: hitsCurrent ? workflowEditPausedKey : null,
  );
}

/// JD / 简历 / 项目被删除后，相关卡片标为“来源已删除，待选择”。
///
/// **不**自动绑定到名字相似的新实体；返回受影响的卡片 ID。
List<String> markCardsWithDeletedSource(
  WorkflowTemplate template, {
  required Set<String> deletedEntityIds,
}) {
  final affected = <String>[];
  for (final card in template.cards) {
    final ids = <String?>[
      card.goalId,
      card.resumeId,
      card.projectId,
      card.knowledgeItemId,
    ];
    if (ids.any((id) => id != null && deletedEntityIds.contains(id))) {
      affected.add(card.id);
    }
  }
  return affected;
}
