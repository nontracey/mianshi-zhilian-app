/// JD / 资料删除影响预览与保护清理（§6.8）。
///
/// 计算规则：
/// 1. 对待删除的 JD 集合取关联知识的并集；
/// 2. 排除仍被**其他未删除 JD**（含已保存与归档）引用的知识；
/// 3. 一个 JD 与同一知识关联多次只计一个引用；
/// 4. 已学过的知识必须醒目提示并由用户明确决定，不跟着 JD 自动删除；
/// 5. 历史 JD 版本不作为活动目标引用，但对应历史问答与引用快照是独立的保留依赖。
///
/// `preview` 只读快照，产出 `operationId + expectedRevisions + selectedIds +
/// impactCounts`；`commit` 必须带 UI 确认令牌，并在提交时用**新快照**重新检查
/// 所有引用，预览后出现新增引用或学习则拒绝并刷新预览。
///
/// 本文件是纯 Dart，不依赖 Flutter。
library;

import '../domain/common.dart';
import '../domain/goal.dart';
import '../tools/tool_contract.dart';
import 'deletion_models.dart';

/// 预览/提交中需要如实告知用户的说明（l10n key，由 UI 翻译）。
abstract final class DeletionNotes {
  /// 历史 JD 快照与历史问答保留为独立依赖。
  static const String historySnapshotsRetained =
      'coach_deletion_note_history_snapshots';

  /// 设备外已导出的备份无法从 App 远程抹除。
  static const String offlineBackupNotRemovable =
      'coach_deletion_note_offline_backup';

  /// 进入回收站不等于彻底删除。
  static const String trashRetention = 'coach_deletion_note_trash_retention';

  /// 本次有待执行计划受影响。
  static const String plannedTasksAffected =
      'coach_deletion_note_planned_tasks_affected';

  /// 本次有暂停中的场次受影响。
  static const String pausedSessionsAffected =
      'coach_deletion_note_paused_sessions_affected';
}

/// 幂等清理任务标识（数据，非 UI 文案）。
abstract final class CleanupTaskIds {
  static const String knowledgeCards = 'knowledge_cards:purge';
  static const String embeddings = 'embeddings:prune';
  static const String sourceChunks = 'source_chunks:reconcile';
}

/// 删除规划器。
class DeletionPlanner {
  const DeletionPlanner();

  /// 生成删除影响预览。纯计算，不修改任何状态。
  DeletionPreview preview({
    required DeletionSnapshot snapshot,
    required Iterable<GoalId> goalIds,
    required IdGenerator idGen,
    required Clock clock,
  }) {
    final known = {for (final goal in snapshot.goals) goal.id};
    final toDelete = <GoalId>[];
    final unknown = <GoalId>[];
    for (final id in goalIds) {
      if (known.contains(id)) {
        if (!toDelete.contains(id)) toDelete.add(id);
      } else if (!unknown.contains(id)) {
        unknown.add(id);
      }
    }
    return _build(
      snapshot: snapshot,
      toDelete: toDelete,
      unknown: unknown,
      operationId: idGen.next(),
      createdAt: clock.now(),
    );
  }

  /// 提交删除。
  ///
  /// 必须带 [token]（由 UI 在用户明确确认后签发）。提交前会用 [freshSnapshot]
  /// 重新检查引用与学习记录；预览已过期时抛 [DeletionConflictException]，
  /// 勾选范围越权时抛 [DeletionScopeException]。
  DeletionCommitResult commit({
    required DeletionPreview preview,
    required DeletionSelection selection,
    required ConfirmationToken token,
    required DeletionSnapshot freshSnapshot,
  }) {
    // 令牌必须对应本次操作，不能跨操作复用。
    if (freshSnapshot.profileId != preview.profileId ||
        token.operationId != preview.operationId ||
        token.subject != preview.goalIds.join(',') ||
        token.expectedRevisions.length != preview.expectedRevisions.length ||
        preview.expectedRevisions.entries.any(
          (e) => token.expectedRevisions[e.key] != e.value,
        )) {
      throw DeletionConflictException(
        operationId: preview.operationId,
        reasons: const ['confirmation token does not match this operation'],
        refreshedPreview: _refresh(preview, freshSnapshot),
      );
    }

    final refreshed = _refresh(preview, freshSnapshot);

    // ── 过期检查：预览之后若出现新引用或新学习，拒绝受影响项 ──────────
    final reasons = <String>[];
    for (final entry in preview.expectedRevisions.entries) {
      final fresh = refreshed.expectedRevisions[entry.key];
      if (fresh != entry.value) {
        reasons.add('goal ${entry.key} changed since preview');
      }
    }

    final beforeById = {for (final i in preview.impacts) i.knowledgeItemId: i};
    for (final impact in refreshed.impacts) {
      final before = beforeById[impact.knowledgeItemId];
      if (before == null) {
        reasons.add('knowledge ${impact.knowledgeItemId} became affected');
        continue;
      }
      if (before.kind != KnowledgeImpactKind.referencedByOtherGoals &&
          impact.kind == KnowledgeImpactKind.referencedByOtherGoals) {
        reasons.add(
          'knowledge ${impact.knowledgeItemId} gained a new goal reference',
        );
      }
      if (before.kind == KnowledgeImpactKind.unreferencedUnlearned &&
          impact.kind == KnowledgeImpactKind.unreferencedLearned) {
        reasons.add(
          'knowledge ${impact.knowledgeItemId} gained learning records',
        );
      }
      if (before.kind == KnowledgeImpactKind.unreferencedUnlearned &&
          impact.kind == KnowledgeImpactKind.otherUseProtected) {
        reasons.add('knowledge ${impact.knowledgeItemId} gained another use');
      }
    }
    if (reasons.isNotEmpty) {
      throw DeletionConflictException(
        operationId: preview.operationId,
        reasons: reasons,
        refreshedPreview: refreshed,
      );
    }

    // ── 范围检查：令牌/勾选不能扩大清理范围 ────────────────────────────
    final allowedCleanup = {
      for (final i in refreshed.unreferencedUnlearned) i.knowledgeItemId,
    };
    final allowedLearned = {
      for (final i in refreshed.unreferencedLearned) i.knowledgeItemId,
    };
    final scopeProblems = <String>[];
    for (final id in selection.cleanupKnowledgeIds) {
      if (!allowedCleanup.contains(id)) {
        scopeProblems.add('$id is not a cleanable unreferenced knowledge item');
      }
    }
    for (final id in selection.learnedActions.keys) {
      if (!allowedLearned.contains(id)) {
        scopeProblems.add('$id has no learning records to decide on');
      }
    }
    if (scopeProblems.isNotEmpty) {
      throw DeletionScopeException(
        operationId: preview.operationId,
        reasons: scopeProblems,
      );
    }

    // ── 计算实际移除范围 ──────────────────────────────────────────────
    final removed = <KnowledgeItemId>{...selection.cleanupKnowledgeIds};
    final applied = <KnowledgeItemId, CleanupAction>{};
    for (final entry in selection.learnedActions.entries) {
      applied[entry.key] = entry.value;
      if (entry.value != CleanupAction.keepKnowledgeAndRecords) {
        removed.add(entry.key);
      }
    }

    final allImpactIds = refreshed.impacts.map((i) => i.knowledgeItemId);
    final retained = <KnowledgeItemId>[
      for (final id in allImpactIds)
        if (!removed.contains(id)) id,
    ];

    final cancelledNotes = <String>[
      if (refreshed.affectedPlanItems > 0) DeletionNotes.plannedTasksAffected,
      if (refreshed.affectedSessions > 0) DeletionNotes.pausedSessionsAffected,
    ];

    final tombstones = <String>[
      for (final id in preview.goalIds) 'goal:$id',
      for (final id in removed) 'knowledge:$id',
    ];

    final cleanupTasks = <String>[
      if (removed.isNotEmpty) CleanupTaskIds.knowledgeCards,
      if (removed.isNotEmpty) CleanupTaskIds.embeddings,
      if (removed.isNotEmpty) CleanupTaskIds.sourceChunks,
    ];

    return DeletionCommitResult(
      operationId: preview.operationId,
      deletedGoalIds: List.unmodifiable(preview.goalIds),
      removedKnowledgeIds: removed.toList(),
      retainedKnowledgeIds: retained,
      learnedActionsApplied: applied,
      cancelledPlanNotes: cancelledNotes,
      tombstones: tombstones,
      cleanupTasks: cleanupTasks,
    );
  }

  // ── 内部 ────────────────────────────────────────────────────────────

  /// 用新快照重算同一操作的范围，保留 operationId 与创建时间以便 UI 对比。
  DeletionPreview _refresh(
    DeletionPreview preview,
    DeletionSnapshot snapshot,
  ) => _build(
    snapshot: snapshot,
    toDelete: preview.goalIds
        .where((id) => snapshot.goals.any((g) => g.id == id))
        .toList(),
    unknown: [
      ...preview.unknownGoalIds,
      ...preview.goalIds.where((id) => !snapshot.goals.any((g) => g.id == id)),
    ],
    operationId: preview.operationId,
    createdAt: preview.createdAt,
  );

  DeletionPreview _build({
    required DeletionSnapshot snapshot,
    required List<GoalId> toDelete,
    required List<GoalId> unknown,
    required String operationId,
    required DateTime createdAt,
  }) {
    final deleteSet = toDelete.toSet();

    // 被删除 JD 关联的知识并集（同 JD 重复关联只计一次）。
    final linkedByDeleted = <KnowledgeItemId>{};
    for (final goalId in toDelete) {
      for (final link in snapshot.linksByGoal[goalId] ?? const []) {
        linkedByDeleted.add(link.knowledgeItemId);
      }
    }

    // 仍被其他未删除 JD（含归档）引用。
    final referencedElsewhere = <KnowledgeItemId, Set<GoalId>>{};
    for (final goal in snapshot.goals) {
      if (deleteSet.contains(goal.id)) continue;
      for (final link in snapshot.linksByGoal[goal.id] ?? const []) {
        referencedElsewhere
            .putIfAbsent(link.knowledgeItemId, () => <GoalId>{})
            .add(goal.id);
      }
    }

    final otherUse = {
      for (final p in snapshot.otherUseProtections) p.knowledgeItemId: p,
    };

    final impacts = <KnowledgeImpact>[];
    for (final item in snapshot.knowledgeItems) {
      if (!linkedByDeleted.contains(item.id)) continue;

      final references = referencedElsewhere[item.id];
      final records =
          snapshot.recordsByKnowledge[item.id] ?? LearningRecordSummary.none;
      final draftOnlyNoRecords =
          item.contentStatus == 'ai-draft-unverified' &&
          !item.displayedToUser &&
          !records.hasAnyRecord &&
          !records.uncertain;

      late final KnowledgeImpactKind kind;
      if (references != null && references.isNotEmpty) {
        kind = KnowledgeImpactKind.referencedByOtherGoals;
      } else if (otherUse.containsKey(item.id)) {
        kind = KnowledgeImpactKind.otherUseProtected;
      } else if (records.shouldProtectAsLearned && !draftOnlyNoRecords) {
        kind = KnowledgeImpactKind.unreferencedLearned;
      } else {
        kind = KnowledgeImpactKind.unreferencedUnlearned;
      }

      impacts.add(
        KnowledgeImpact(
          knowledgeItemId: item.id,
          title: item.title,
          kind: kind,
          referencingGoalIds: references == null
              ? const []
              : (references.toList()..sort()),
          records: records,
          otherUse: otherUse[item.id],
          isDraftOnly: draftOnlyNoRecords,
        ),
      );
    }

    // 稳定排序，便于 UI 与测试断言。
    impacts.sort((a, b) {
      final byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) return byKind;
      return a.title.compareTo(b.title);
    });

    // 受影响的待执行计划项：绑定被删 JD，或只由被删 JD 独占的知识。
    var affectedPlanItems = 0;
    for (final plan in snapshot.openPlans) {
      for (final planItem in plan.planItems) {
        if (planItem.completed) continue;
        final byGoal =
            planItem.goalId != null && deleteSet.contains(planItem.goalId);
        final knowledgeId = planItem.knowledgeItemId;
        final byKnowledge =
            knowledgeId != null &&
            linkedByDeleted.contains(knowledgeId) &&
            !(referencedElsewhere[knowledgeId]?.isNotEmpty ?? false);
        if (byGoal || byKnowledge) affectedPlanItems++;
      }
    }

    final notes = <String>{
      DeletionNotes.historySnapshotsRetained,
      DeletionNotes.offlineBackupNotRemovable,
      ...snapshot.historicalSnapshotNotes,
    }.toList();

    return DeletionPreview(
      operationId: operationId,
      profileId: snapshot.profileId,
      goalIds: List.unmodifiable(toDelete),
      unknownGoalIds: List.unmodifiable(unknown),
      expectedRevisions: {
        for (final id in toDelete)
          id: _revisionToken(snapshot.goals.firstWhere((g) => g.id == id)),
      },
      impacts: List.unmodifiable(impacts),
      affectedPlanItems: affectedPlanItems,
      affectedSessions: snapshot.affectedSessions
          .where(
            (s) =>
                deleteSet.contains(s.goalId) ||
                linkedByDeleted.contains(s.knowledgeItemId),
          )
          .length,
      historicalSnapshotNotes: List.unmodifiable(notes),
      createdAt: createdAt,
    );
  }

  /// 内容版本令牌：内容哈希 + 更新时间，任一变化都视为预览过期。
  String _revisionToken(Goal goal) =>
      '${goal.contentHash}#${goal.updatedAt.toIso8601String()}#'
      '${goal.archived}';
}
