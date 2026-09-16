import '../domain/common.dart';
import '../domain/plan.dart';
import '../domain/evidence.dart';
import '../knowledge/source.dart';
import '../policies/evidence_replay.dart';
import 'coach_backup.dart';
import '../workflows/workflow_template.dart';
import 'coach_store.dart';
import 'extension_records.dart';
import 'workflow_repository.dart';

/// A merge keeps both versions. This service records one explicit choice at a
/// newer revision so it wins over either offline copy on subsequent syncs.
class CoachSyncConflict {
  const CoachSyncConflict({
    required this.record,
    required this.table,
    required this.entityId,
    required this.variantId,
  });
  final CoachExtensionRecord record;
  final String table;
  final String entityId;
  final String variantId;
}

class CoachSyncConflictService {
  const CoachSyncConflictService(this.store, this.profileId);
  final CoachStore store;
  final ProfileId profileId;

  Future<List<CoachSyncConflict>> listOpen() async {
    final records = await store.listExtensions(
      profileId,
      CoachExtensionKind.syncMetadata,
    );
    final result = <CoachSyncConflict>[];
    for (final record in records) {
      if (!record.id.startsWith('conflict.') ||
          record.value['status'] == 'resolved')
        continue;
      final table = record.value['table'],
          entity = record.value['entityId'],
          variant = record.value['variantId'];
      if ((table == 'dailyPlans' ||
              table == 'extensions' ||
              table == 'assessmentEvents' ||
              table == 'sources') &&
          entity is String &&
          variant is String) {
        result.add(
          CoachSyncConflict(
            record: record,
            table: table as String,
            entityId: entity,
            variantId: variant,
          ),
        );
      }
    }
    return result..sort((a, b) => a.record.id.compareTo(b.record.id));
  }

  Future<void> resolve(
    CoachSyncConflict conflict, {
    required bool chooseVariant,
    required DateTime now,
  }) => store.transaction(() async {
    final saved = await store.getExtension(
      profileId,
      CoachExtensionKind.syncMetadata,
      conflict.record.id,
    );
    if (saved == null ||
        saved.revision != conflict.record.revision ||
        saved.value['status'] == 'resolved') {
      throw StateError('Conflict changed; reload before choosing');
    }
    final selectedId = chooseVariant ? conflict.variantId : conflict.entityId;
    if (conflict.table == 'dailyPlans') {
      final primary = await store.getDailyPlan(conflict.entityId);
      final variant = await store.getDailyPlan(conflict.variantId);
      if (primary == null ||
          variant == null ||
          primary.profileId != profileId ||
          variant.profileId != profileId ||
          primary.date != variant.date ||
          primary.isExtra ||
          variant.isExtra)
        throw StateError('Plan conflict scope changed');
      final selected = chooseVariant ? variant : primary;
      final losing = chooseVariant ? primary : variant;
      final chosenIds = selected.planItems.map((i) => i.id).toSet();
      final ongoing = (await store.listSessions(profileId))
          .where(
            (s) =>
                s.status != RuntimeStatus.completed &&
                s.coverageSnapshot?.planItemId != null,
          )
          .map((s) => s.coverageSnapshot!.planItemId!)
          .toSet();
      final retained = losing.planItems
          .where(
            (item) => ongoing.contains(item.id) && !chosenIds.contains(item.id),
          )
          .toList();
      if (retained.isNotEmpty) {
        await store.putDailyPlan(
          DailyPlan(
            id: '${conflict.variantId}.ongoing',
            profileId: profileId,
            date: selected.date,
            timezone: selected.timezone,
            planItems: retained,
            baseMinutes: 0,
            version: 1,
            isExtra: true,
            frozenAt: now,
            revisionNote: 'retained_ongoing_conflict',
          ),
        );
      }
      await store.putDailyPlan(
        DailyPlan(
          id: primary.id,
          profileId: profileId,
          date: selected.date,
          timezone: selected.timezone,
          planItems: selected.planItems,
          baseMinutes: selected.baseMinutes,
          version:
              (primary.version > variant.version
                  ? primary.version
                  : variant.version) +
              1,
          frozenAt: selected.frozenAt ?? primary.frozenAt ?? now,
          revisionNote: 'sync_resolved:$selectedId',
        ),
      );
    } else if (conflict.table == 'sources') {
      final primary = await store.getSource(conflict.entityId);
      final variant = await store.getSource(conflict.variantId);
      if (primary == null ||
          variant == null ||
          primary.profileId != profileId ||
          variant.profileId != profileId ||
          primary.revision != variant.revision) {
        throw StateError('Source conflict scope changed');
      }
      final selected = chooseVariant ? variant : primary;
      final chunks = (await store.listSourceChunks(
        selected.id,
      )).where((chunk) => chunk.sourceRevision == selected.revision).toList();
      final nextRevision = primary.revision + 1;
      final oldSnapshotId = '${primary.id}@${primary.revision}';
      if (await store.getExtension(
            profileId,
            CoachExtensionKind.sourceRevision,
            oldSnapshotId,
          ) ==
          null) {
        await store.putExtension(
          CoachExtensionRecord(
            profileId: profileId,
            kind: CoachExtensionKind.sourceRevision,
            id: oldSnapshotId,
            revision: 1,
            value: {
              'source': primary.toJson(),
              'chunkIds': (await store.listSourceChunks(primary.id))
                  .where((chunk) => chunk.sourceRevision == primary.revision)
                  .map((chunk) => chunk.id)
                  .toList(),
            },
            updatedAt: now,
          ),
        );
      }
      await store.putSource(
        Source(
          id: primary.id,
          profileId: profileId,
          title: selected.title,
          type: selected.type,
          contentHash: selected.contentHash,
          status: IngestionStatus.ready,
          url: selected.url,
          revision: nextRevision,
          content: selected.content,
          fetchedAt: now,
          createdAt: primary.createdAt,
        ),
      );
      await store.putSourceChunks([
        for (final chunk in chunks)
          SourceChunk(
            id: '${chunk.id}.resolved.$nextRevision',
            sourceId: primary.id,
            sourceRevision: nextRevision,
            index: chunk.index,
            content: chunk.content,
            titlePath: chunk.titlePath,
            sourceLocation: chunk.sourceLocation,
            hash: chunk.hash,
            knowledgeItemId: chunk.knowledgeItemId,
          ),
      ]);
      for (final knowledgeId
          in chunks.map((c) => c.knowledgeItemId).whereType<String>().toSet()) {
        final item = await store.getKnowledgeItem(knowledgeId);
        if (item != null && item.profileId == profileId) {
          await store.putKnowledgeItem(
            item.copyWith(
              contentStatus: 'stale',
              version: item.version + 1,
              updatedAt: now,
            ),
          );
        }
      }
    } else if (conflict.table == 'assessmentEvents') {
      Map<String, Object?> readRow(String key) {
        final raw = saved.value[key];
        if (raw is! Map)
          throw StateError('Assessment conflict snapshot missing');
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }

      final primary = AssessmentEvent.fromJson(readRow('primary'));
      final variant = AssessmentEvent.fromJson(readRow('variant'));
      if (primary.profileId != profileId ||
          variant.profileId != profileId ||
          primary.sessionId != variant.sessionId ||
          primary.turnGroupId != variant.turnGroupId ||
          primary.assessmentRevision != variant.assessmentRevision) {
        throw StateError('Assessment conflict scope changed');
      }
      if ((await store.listAssessmentEvents(primary.sessionId)).any(
        (event) =>
            event.turnGroupId == primary.turnGroupId &&
            event.assessmentRevision > primary.assessmentRevision,
      )) {
        throw StateError('Assessment was revised after this conflict');
      }
      final selected = chooseVariant ? variant : primary;
      await store.putAssessmentEvent(
        AssessmentEvent.fromJson({
          ...selected.toJson(),
          'id':
              '${selected.id}.sync.resolved.${selected.assessmentRevision + 1}',
          'assessmentRevision': selected.assessmentRevision + 1,
        }),
      );
      final backup = await exportCoachBackup(store);
      final data = Map<String, Object?>.from(backup['data'] as Map);
      replayCoachReviewStates(data);
      for (final row in data['reviewStates'] as List) {
        await store.putReviewState(
          ReviewState.fromJson(Map<String, Object?>.from(row as Map)),
        );
      }
    } else if (conflict.table == 'extensions') {
      final repo = WorkflowRepository(store);
      final primary = await repo.getTemplate(profileId, conflict.entityId);
      final variant = await repo.getTemplate(profileId, conflict.variantId);
      if (primary == null ||
          variant == null ||
          primary.isBuiltIn ||
          variant.isBuiltIn)
        throw StateError('Template conflict scope changed');
      final selected = chooseVariant ? variant : primary;
      await repo.putTemplate(
        WorkflowTemplate.fromJson({
          ...selected.toJson(),
          'id': primary.id,
          'version':
              (primary.version > variant.version
                  ? primary.version
                  : variant.version) +
              1,
          'isBuiltIn': false,
        }),
        profileId: profileId,
        updatedAt: now,
      );
    } else {
      throw StateError('Unsupported conflict kind');
    }
    await store.putExtension(
      CoachExtensionRecord(
        profileId: profileId,
        kind: CoachExtensionKind.syncMetadata,
        id: saved.id,
        revision: saved.revision + 1,
        updatedAt: now,
        value: {...saved.value, 'status': 'resolved', 'selectedId': selectedId},
      ),
    );
  });
}
