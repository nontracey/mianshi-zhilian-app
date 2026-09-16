import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/goal.dart';
import 'package:mianshi_zhilian/coach/domain/profile.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';
import 'package:mianshi_zhilian/coach/knowledge/source.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_backup.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store_native.dart';
import 'package:mianshi_zhilian/coach/persistence/extension_records.dart';
import 'package:mianshi_zhilian/coach/persistence/legacy_migration.dart';

final now = DateTime(2026, 9, 12);
Future<void> seed(
  CoachStore store, {
  String profile = 'p',
  String answer = 'original',
}) async {
  await store.putProfile(Profile(id: profile, createdAt: now, updatedAt: now));
  await store.putSession(
    CoachSession(
      id: 's',
      profileId: profile,
      mode: SessionMode.review,
      status: RuntimeStatus.paused,
      turnSequence: 1,
      createdAt: now,
    ),
  );
  await store.putMessage(
    CoachMessage(
      id: 'm',
      profileId: profile,
      sessionId: 's',
      role: 'user',
      content: answer,
      turnId: 't',
      sequence: 1,
      createdAt: now,
    ),
  );
}

void main() {
  test(
    'reads a precomputed schema 1 backup from the signed VM hash format',
    () async {
      final backup =
          jsonDecode(
                await File(
                  'test/coach/fixtures/coach_backup_v1.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final store = InMemoryCoachStore();
      await restoreCoachBackup(store, backup);
      expect((await store.listProfiles()).single.id, 'legacy-profile');
    },
  );

  test(
    'SQLite backup preserves deleted goal revisions, chunks and cleanup tasks',
    () async {
      final source = openNativeCoachStoreMemory();
      final target = openNativeCoachStoreMemory();
      addTearDown(source.close);
      addTearDown(target.close);
      await seed(source);
      await source.putGoalRevision(
        GoalRevision(
          id: 'rev',
          goalId: 'deleted-goal',
          profileId: 'p',
          revisionNumber: 1,
          contentHash: 'hash',
          createdAt: now,
        ),
      );
      await source.putSource(
        Source(
          id: 'src',
          profileId: 'p',
          title: 'notes',
          type: SourceType.txt,
          contentHash: 'hash',
          createdAt: now,
        ),
      );
      await source.putSourceChunk(
        SourceChunk(
          id: 'chunk',
          sourceId: 'src',
          sourceRevision: 1,
          index: 0,
          content: 'source text',
        ),
      );
      await source.putCleanupTask(
        CoachCleanupTask(
          id: 'cleanup',
          profileId: 'p',
          type: 'index',
          operationId: 'operation',
          status: CleanupTaskStatus.pending,
          createdAt: now,
        ),
      );
      final backup =
          jsonDecode(jsonEncode(await exportCoachBackup(source)))
              as Map<String, dynamic>;
      await restoreCoachBackup(target, backup);
      expect((await target.listGoalRevisions('deleted-goal')).single.id, 'rev');
      expect(
        (await target.listSourceChunks('src')).single.content,
        'source text',
      );
      expect(
        (await target.listCleanupTasks('p')).single.status,
        CleanupTaskStatus.pending,
      );
      expect((await target.messagesOf('s')).single.content, 'original');
    },
  );
  test(
    'a backup cannot overwrite another profile via a colliding global ID',
    () async {
      final source = InMemoryCoachStore();
      final target = InMemoryCoachStore();
      await seed(source, profile: 'p2');
      await seed(target);
      await expectLater(
        restoreCoachBackup(target, await exportCoachBackup(source)),
        throwsA(isA<FormatException>()),
      );
      expect(
        await target.getProfile('p2'),
        isNull,
        reason: 'restore rolls back entirely',
      );
      expect((await target.getSession('s'))!.profileId, 'p');
    },
  );
  test('a backup cannot replace an existing original answer', () async {
    final source = InMemoryCoachStore();
    final target = InMemoryCoachStore();
    await seed(source, answer: 'different');
    await seed(target);
    await expectLater(
      restoreCoachBackup(target, await exportCoachBackup(source)),
      throwsA(isA<FormatException>()),
    );
    expect((await target.messagesOf('s')).single.content, 'original');
  });
  test(
    'cross-profile parent references are rejected even with a valid hash',
    () async {
      final source = InMemoryCoachStore();
      final target = InMemoryCoachStore();
      await seed(source);
      await source.putProfile(
        Profile(id: 'other', createdAt: now, updatedAt: now),
      );
      await source.putMessage(
        CoachMessage(
          id: 'foreign',
          profileId: 'other',
          sessionId: 's',
          role: 'user',
          content: 'other answer',
          turnId: 't2',
          sequence: 2,
          createdAt: now,
        ),
      );
      await expectLater(
        restoreCoachBackup(target, await exportCoachBackup(source)),
        throwsA(isA<FormatException>()),
      );
      expect(await target.listProfiles(), isEmpty);
    },
  );
  test(
    'wrong manifest counts are rejected and JSON map order is irrelevant',
    () async {
      final source = InMemoryCoachStore();
      await seed(source);
      final backup = await exportCoachBackup(source);
      final data = backup['data'] as Map;
      backup['data'] = Map.fromEntries(data.entries.toList().reversed);
      await restoreCoachBackup(InMemoryCoachStore(), backup);
      (backup['counts'] as Map)['messages'] = 0;
      await expectLater(
        restoreCoachBackup(InMemoryCoachStore(), backup),
        throwsA(isA<FormatException>()),
      );
    },
  );
  test(
    'older backup preserves a newer local session cursor and answers',
    () async {
      final source = InMemoryCoachStore();
      final target = InMemoryCoachStore();
      await seed(source);
      await seed(target);
      await target.putSession(
        (await target.getSession('s'))!.copyWith(turnSequence: 2),
      );
      await target.putMessage(
        CoachMessage(
          id: 'new',
          profileId: 'p',
          sessionId: 's',
          role: 'user',
          content: 'new answer',
          turnId: 'new-turn',
          sequence: 2,
          createdAt: now,
        ),
      );
      await restoreCoachBackup(target, await exportCoachBackup(source));
      expect((await target.getSession('s'))!.turnSequence, 2);
      expect(await target.messagesOf('s'), hasLength(2));
    },
  );
  test(
    'legacy IDs are deterministic across fresh databases and retain metadata',
    () async {
      final a = InMemoryCoachStore();
      final b = InMemoryCoachStore();
      final input = LegacyPracticeInput(
        attempts: [
          {
            'id': 'legacy-1',
            'answer': 'old answer',
            'question': 'old question',
            'mode': 'recall',
            'topicId': 'legacy-topic',
            'score': 80,
            'createdAt': now.toIso8601String(),
          },
        ],
      );
      for (final store in [a, b]) {
        await LegacyPracticeMigrator(
          store: store,
          profileId: 'p',
        ).migrate(input);
      }
      expect(
        (await a.listSessions('p')).single.id,
        (await b.listSessions('p')).single.id,
      );
      final backup = await exportCoachBackup(a);
      await restoreCoachBackup(b, backup);
      await LegacyPracticeMigrator(store: b, profileId: 'p').migrate(input);
      expect(await b.listSessions('p'), hasLength(1));
      expect(jsonEncode(backup), contains('legacy-topic'));
      expect(await b.listReviewStates('p'), isEmpty);
    },
  );
}
