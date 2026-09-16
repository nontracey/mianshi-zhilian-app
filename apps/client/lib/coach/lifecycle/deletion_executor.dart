/// Transactional execution and retryable physical cleanup for a confirmed plan.
library;

import '../domain/common.dart';
import '../persistence/coach_store.dart';
import '../persistence/extension_records.dart';
import '../tools/tool_contract.dart';
import 'deletion_models.dart';
import 'deletion_planner.dart';
import 'deletion_snapshot_source.dart';

class DeletionExecutor {
  DeletionExecutor({
    required this.store,
    this.snapshotSource = const StoreDeletionSnapshotSource(),
    this.planner = const DeletionPlanner(),
    Clock? clock,
    this.generation = 0,
  }) : clock = clock ?? const SystemClock();

  final CoachStore store;
  final StoreDeletionSnapshotSource snapshotSource;
  final DeletionPlanner planner;
  final Clock clock;
  final int generation;

  /// Re-checks the confirmation inside the store transaction, records its
  /// immutable outcome and writes durable tombstones before returning success.
  Future<DeletionCommitResult> commit({
    required DeletionPreview preview,
    required DeletionSelection selection,
    required ConfirmationToken token,
  }) => store.transaction(() async {
    final fresh = await snapshotSource.load(
      store,
      profileId: preview.profileId,
    );
    final result = planner.commit(
      preview: preview,
      selection: selection,
      token: token,
      freshSnapshot: fresh,
    );
    final now = clock.now();
    for (final goalId in result.deletedGoalIds) {
      await store.deleteGoal(goalId);
      await store.putTombstone(
        CoachTombstone(
          profileId: preview.profileId,
          entityType: 'goal',
          entityId: goalId,
          generation: generation,
          deletedAt: now,
          operationId: result.operationId,
        ),
      );
    }
    for (final session in await store.listSessions(preview.profileId)) {
      if (session.status != RuntimeStatus.completed &&
          result.deletedGoalIds.contains(session.goalId)) {
        await store.putSession(
          session.copyWith(
            status: RuntimeStatus.paused,
            stopReason: 'source_removed',
            partial: true,
          ),
        );
      }
    }
    for (final knowledgeId in result.removedKnowledgeIds) {
      final action = result.learnedActionsApplied[knowledgeId];
      if (action == null || action == CleanupAction.removeKnowledgeAndRecords) {
        await store.deleteLearningRecordsForKnowledge(knowledgeId);
        await store.deleteKnowledgeItem(knowledgeId);
      } else {
        final item = await store.getKnowledgeItem(knowledgeId);
        if (item != null) {
          await store.putKnowledgeItem(
            item.copyWith(
              contentStatus: 'removed',
              version: item.version + 1,
              updatedAt: now,
            ),
          );
        }
      }
      await store.putTombstone(
        CoachTombstone(
          profileId: preview.profileId,
          entityType: 'knowledge',
          entityId: knowledgeId,
          generation: generation,
          deletedAt: now,
          operationId: result.operationId,
        ),
      );
    }
    await store.putExtension(
      CoachExtensionRecord(
        profileId: preview.profileId,
        kind: CoachExtensionKind.deletionOperation,
        id: result.operationId,
        revision: 1,
        value: {
          'preview': preview.toJson(),
          'selection': {
            'cleanupKnowledgeIds': selection.cleanupKnowledgeIds,
            'learnedActions': selection.learnedActions.map(
              (id, action) => MapEntry(id, action.name),
            ),
          },
          'result': result.toJson(),
          'physicalCleanupComplete': result.cleanupTasks.isEmpty,
        },
        updatedAt: now,
      ),
    );
    for (final type in result.cleanupTasks) {
      await store.putCleanupTask(
        CoachCleanupTask(
          id: '${result.operationId}:$type',
          profileId: preview.profileId,
          type: type,
          operationId: result.operationId,
          status: CleanupTaskStatus.pending,
          createdAt: now,
        ),
      );
    }
    return result;
  });

  Future<void> runPendingCleanupForProfile(
    ProfileId profileId, {
    Future<void> Function(CoachCleanupTask task, List<String> knowledgeIds)?
    externalCleaner,
  }) async {
    for (final task in (await store.listCleanupTasks(
      profileId,
    )).where((t) => t.status != CleanupTaskStatus.completed)) {
      await _runTask(task, externalCleaner);
    }
    final tasks = await store.listCleanupTasks(profileId);
    for (final operation in await store.listExtensions(
      profileId,
      CoachExtensionKind.deletionOperation,
    )) {
      if (operation.value['physicalCleanupComplete'] == true) continue;
      final related = tasks.where((task) => task.operationId == operation.id);
      if (related.isNotEmpty &&
          related.every((task) => task.status == CleanupTaskStatus.completed)) {
        await store.putExtension(
          CoachExtensionRecord(
            profileId: profileId,
            kind: operation.kind,
            id: operation.id,
            revision: operation.revision + 1,
            value: {...operation.value, 'physicalCleanupComplete': true},
            updatedAt: clock.now(),
          ),
        );
      }
    }
  }

  Future<void> _runTask(
    CoachCleanupTask task,
    Future<void> Function(CoachCleanupTask task, List<String> knowledgeIds)?
    externalCleaner,
  ) async {
    final now = clock.now();
    await store.putCleanupTask(
      task.copyWith(status: CleanupTaskStatus.running, updatedAt: now),
    );
    try {
      final operation = await store.getExtension(
        task.profileId,
        CoachExtensionKind.deletionOperation,
        task.operationId,
      );
      final result = operation?.value['result'];
      final ids = result is Map
          ? ((result['removedKnowledgeIds'] as List? ?? const [])
                .map((item) => item as String)
                .toList())
          : const <String>[];
      if (task.type == CleanupTaskIds.sourceChunks) {
        for (final id in ids) {
          await store.deleteSourceChunksForKnowledge(id);
        }
      }
      if (task.type != CleanupTaskIds.sourceChunks && externalCleaner == null) {
        throw StateError('Cleanup handler is unavailable');
      }
      await externalCleaner?.call(task, ids);
      await store.putCleanupTask(
        task.copyWith(
          status: CleanupTaskStatus.completed,
          updatedAt: clock.now(),
        ),
      );
    } catch (error) {
      await store.putCleanupTask(
        task.copyWith(
          status: CleanupTaskStatus.failed,
          updatedAt: clock.now(),
          error: error.toString(),
        ),
      );
    }
  }
}
