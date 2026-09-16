import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mianshi_zhilian/coach/application/coach_runtime.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/domain/profile.dart';
import 'package:mianshi_zhilian/coach/domain/plan.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';
import 'package:mianshi_zhilian/coach/mcp/mcp_client.dart';
import 'package:mianshi_zhilian/coach/mcp/request_metadata.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_backup.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_sync.dart';
import 'package:mianshi_zhilian/coach/persistence/sync_conflicts.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store_native.dart';
import 'package:mianshi_zhilian/coach/persistence/extension_records.dart';
import 'package:mianshi_zhilian/coach/persistence/legacy_material_migration.dart';
import 'package:mianshi_zhilian/coach/knowledge/source.dart';
import 'package:mianshi_zhilian/coach/knowledge/index.dart';
import 'package:mianshi_zhilian/coach/workflows/workflow_template.dart';
import 'package:mianshi_zhilian/coach/persistence/workflow_repository.dart';
import 'package:mianshi_zhilian/services/coach_http_client.dart';
import 'implementation_flows_test.dart' show seed, provider, now;

void main() {
  test(
    'redacted fields survive database round trips and newer remote metadata cannot erase private material',
    () async {
      final local = InMemoryCoachStore();
      await seed(local);
      await provider(local).load();
      final original = await exportCoachBackup(local);
      final redacted = redactCoachBackup(
        original,
        fullText: false,
        privateMaterials: false,
      );
      final remote = InMemoryCoachStore();
      await restoreCoachBackup(remote, redacted);
      await remote.putGoal(
        (await remote.getGoal(
          'g',
        ))!.copyWith(updatedAt: now.add(const Duration(days: 1))),
      );
      final reexported = await exportCoachBackup(remote);
      for (final pair in [(original, reexported), (reexported, original)]) {
        final merged = await mergeCoachBackups(pair.$1, pair.$2);
        final restored = InMemoryCoachStore();
        await restoreCoachBackup(restored, merged);
        expect((await restored.getGoal('g'))!.title, 'Synthetic role');
        expect(
          (await restored.getGoal('g'))!.originalText,
          'Understand concurrency',
        );
        expect(
          (await restored.listGoalRequirements('g')).single.title,
          'Original requirement',
        );
        expect(
          (await mergeCoachBackups(merged, reexported))['contentHash'],
          merged['contentHash'],
        );
      }
    },
  );

  test(
    'modern MCP sends per-request metadata and mirrored UTF-8 headers without legacy lifecycle',
    () async {
      final methods = <String>[];
      final httpClient = CoachHttpClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          final method = body['method'] as String;
          methods.add(method);
          expect(request.headers['MCP-Protocol-Version'], '2026-07-28');
          expect(request.headers['Mcp-Method'], method);
          expect(request.headers.containsKey('Mcp-Session-Id'), isFalse);
          expect(
            body['params']['_meta']['io.modelcontextprotocol/protocolVersion'],
            '2026-07-28',
          );
          if (method == 'tools/call') {
            expect(request.headers['Mcp-Name'], 'read_note');
            expect(request.headers['Mcp-Param-query'], encodeMcpHeader('并发'));
          }
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': method == 'tools/list'
                  ? {
                      'tools': [
                        {
                          'name': 'read_note',
                          'inputSchema': {
                            'type': 'object',
                            'properties': {
                              'q': {'type': 'string', 'x-mcp-header': 'query'},
                            },
                          },
                        },
                        {
                          'name': 'invalid',
                          'inputSchema': {
                            'type': 'object',
                            'properties': {
                              'x': {'type': 'number', 'x-mcp-header': 'bad'},
                            },
                          },
                        },
                      ],
                    }
                  : {
                      'content': [
                        {'type': 'text', 'text': 'untrusted note'},
                      ],
                    },
            }),
            200,
            headers: {'mcp-session-id': 'must-be-ignored'},
          );
        }),
      );
      addTearDown(httpClient.close);
      final client = McpRemoteClient(
        config: const McpServerConfig(
          id: 'm',
          name: 'test',
          url: 'https://mcp.example/rpc',
          protocolVersion: '2026-07-28',
          allowedTools: ['read_note'],
        ),
        http: httpClient,
      );
      await client.connect();
      expect((await client.listTools()).single.name, 'read_note');
      expect(await client.callTool('read_note', {'q': '并发'}), 'untrusted note');
      expect(methods, everyElement(isIn(['tools/list', 'tools/call'])));
    },
  );

  test(
    'a recovered second runtime blocks the first runtime commit and cancellation',
    () async {
      final store = InMemoryCoachStore();
      final first = CoachRuntime(store: store),
          second = CoachRuntime(store: store);
      final session = await first.startSession(
        profileId: 'p',
        mode: SessionMode.learning,
      );
      final old = await first.beginModelTurn(session.id);
      await store.putSession(
        (await store.getSession(
          session.id,
        ))!.copyWith(status: RuntimeStatus.paused),
      );
      final replacement = await second.beginModelTurn(session.id);
      await expectLater(
        first.commitModelTurn(handle: old, content: 'late'),
        throwsA(isA<RuntimeConflictException>()),
      );
      expect(await first.cancel(old), isFalse);
      await second.commitModelTurn(handle: replacement, content: 'current');
      expect((await store.messagesOf(session.id)).single.content, 'current');
      expect(
        jsonEncode(await exportCoachBackup(store)),
        isNot(contains('runtimeLease')),
      );
    },
  );

  test(
    'legacy target, projects and whole mock history migrate idempotently without credit',
    () async {
      final store = InMemoryCoachStore();
      final migrator = LegacyMaterialMigrator(store: store, profileId: 'p');
      final snapshot = <String, Object?>{
        'prep_plan': {
          'targetRole': 'Synthetic QA',
          'jobDescription': 'Test concurrency',
        },
        'project_library': [
          {
            'id': 'project1',
            'name': 'Synthetic billing',
            'background': 'B2B billing',
            'task': 'Testing',
            'result': '20% fewer retries',
            'techStack': ['Dart'],
          },
        ],
        'mock_interview_sessions': [
          {
            'id': 'mock1',
            'startedAt': now.toIso8601String(),
            'averageScore': 95,
            'attempts': [
              {
                'id': 'a',
                'question': 'Why retry?',
                'answer': 'Transient errors.',
              },
            ],
          },
        ],
      };
      await migrator.migrate(snapshot);
      await migrator.migrate(snapshot);
      expect(await store.listGoals('p'), hasLength(1));
      expect(await store.listResumes('p'), hasLength(1));
      final session = (await store.listSessions('p')).single;
      expect((await store.messagesOf(session.id)).map((m) => m.content), [
        'Why retry?',
        'Transient errors.',
      ]);
      expect(await store.listAssessmentEvents(session.id), isEmpty);
      expect(await store.listReviewStates('p'), isEmpty);
      expect(
        (await store.getExtension(
          'p',
          CoachExtensionKind.legacyMigration,
          'legacy.upgrade.snapshot.v1',
        ))!.value['snapshotJson'],
        contains('95'),
      );
    },
  );

  test(
    'forged deletion markers cannot delete material from a different profile',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      await provider(store).load();
      final attacker = InMemoryCoachStore();
      await attacker.putProfile(
        Profile(id: 'other', createdAt: now, updatedAt: now),
      );
      await attacker.putTombstone(
        CoachTombstone(
          profileId: 'other',
          entityType: 'goal',
          entityId: 'g',
          generation: 0,
          deletedAt: now,
          operationId: 'forged',
        ),
      );
      final backup = await exportCoachBackup(attacker);
      await expectLater(
        restoreCoachBackup(store, backup),
        throwsFormatException,
      );
      expect(await store.getGoal('g'), isNotNull);
    },
  );

  test(
    'full reset reclaims SQLite file pages while retaining another profile',
    () async {
      final dir = await Directory.systemTemp.createTemp('coach-wipe-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/coach.sqlite');
      final store = openNativeCoachStoreFile(file);
      await seed(store);
      final coach = provider(store);
      await coach.load();
      await coach.startSession();
      const secret = 'SYNTHETIC_PRIVATE_MATERIAL_NEVER_IN_CLEARED_PAGES';
      await coach.sendUserMessage(secret);
      await coach.clearPersonalMaterials();
      await store.close();
      expect(latin1.decode(await file.readAsBytes()), isNot(contains(secret)));
    },
  );

  test(
    'two devices assessing the same point on one day only advance once',
    () async {
      final base = InMemoryCoachStore();
      await seed(base);
      await provider(base).load();
      await base.putReviewState(
        ReviewState(
          profileId: 'p',
          knowledgeItemId: 'k',
          reviewPointId: 'rp',
          status: ReviewStatus.exposed,
          firstDueAt: now.subtract(const Duration(days: 1)),
          nextDueAt: now.subtract(const Duration(days: 1)),
        ),
      );
      final snapshot = await exportCoachBackup(base);
      Future<Map<String, Object?>> device(String id) async {
        final store = InMemoryCoachStore();
        await restoreCoachBackup(store, snapshot);
        await store.putSession(
          CoachSession(
            id: id,
            profileId: 'p',
            mode: SessionMode.review,
            createdAt: now,
          ),
        );
        for (final role in ['assistant', 'user']) {
          await store.putMessage(
            CoachMessage(
              id: '$id.$role',
              sessionId: id,
              profileId: 'p',
              role: role,
              content: 'synthetic $role',
              turnId: '$id.turn',
              sequence: role == 'user' ? 2 : 1,
              createdAt: now,
            ),
          );
        }
        await store.putAssessmentEvent(
          AssessmentEvent(
            id: '$id.event',
            profileId: 'p',
            sessionId: id,
            turnGroupId: '$id.turn',
            knowledgeItemId: 'k',
            reviewPointId: 'rp',
            questionMessageId: '$id.assistant',
            answerMessageIds: ['$id.user'],
            assessmentMode: SessionMode.review,
            result: ReviewOutcome.independentPass,
            independentEligible: true,
            isSpacedEligible: true,
            askedDimensions: ['ordering'],
            sourceRevisionIds: ['synthetic-source:v1'],
            createdAt: now,
          ),
        );
        return exportCoachBackup(store);
      }

      final a = await device('a'), b = await device('b');
      final merged = await mergeCoachBackups(a, b);
      final states = (merged['data'] as Map)['reviewStates'] as List;
      expect(states.single['consecutiveIndependentPasses'], 1);
      expect((merged['data'] as Map)['assessmentEvents'], hasLength(2));
      expect(
        (await mergeCoachBackups(merged, b))['contentHash'],
        merged['contentHash'],
      );
    },
  );

  test(
    'explicit plan conflict choice converges and keeps both revisions',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      await provider(store).load();
      await provider(store).load();
      final coach = provider(store);
      await coach.load();
      await coach.ensureTodayPlan();
      final a = await exportCoachBackup(store);
      final data = Map<String, Object?>.from(jsonDecode(jsonEncode(a['data'])));
      ((data['dailyPlans'] as List).single['planItems'] as List)
              .first['estimatedMinutes'] =
          7;
      final b = coachBackupFromData(data);
      final merged = await mergeCoachBackups(a, b);
      expect(
        (await mergeCoachBackups(b, a))['contentHash'],
        merged['contentHash'],
      );
      final recovered = InMemoryCoachStore();
      await restoreCoachBackup(recovered, merged);
      final service = CoachSyncConflictService(recovered, 'p');
      final conflict = (await service.listOpen()).single;
      final variant = await recovered.getDailyPlan(conflict.variantId);
      expect(variant, isNotNull);
      await service.resolve(
        conflict,
        chooseVariant: true,
        now: now.add(const Duration(days: 1)),
      );
      expect(await service.listOpen(), isEmpty);
      final selected = await recovered.getDailyPlan(conflict.entityId);
      expect(selected!.version, greaterThan(variant!.version));
      expect(
        selected.planItems.first.estimatedMinutes,
        variant.planItems.first.estimatedMinutes,
      );
      expect(await recovered.getDailyPlan(conflict.variantId), isNotNull);
      final repeated = await mergeCoachBackups(
        await exportCoachBackup(recovered),
        b,
      );
      final other = InMemoryCoachStore();
      await restoreCoachBackup(other, repeated);
      expect(await CoachSyncConflictService(other, 'p').listOpen(), isEmpty);
      expect(
        (await other.getDailyPlan(conflict.entityId))!.version,
        selected.version,
      );
    },
  );

  test(
    'same assessment revision is quarantined until explicit choice',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      await provider(store).load();
      await store.putSession(
        CoachSession(
          id: 's',
          profileId: 'p',
          mode: SessionMode.review,
          createdAt: now,
        ),
      );
      for (final (role, sequence) in [('assistant', 1), ('user', 2)]) {
        await store.putMessage(
          CoachMessage(
            id: role,
            sessionId: 's',
            profileId: 'p',
            role: role,
            content: 'Synthetic content',
            turnId: 'turn',
            sequence: sequence,
            createdAt: now,
          ),
        );
      }
      await store.putAssessmentEvent(
        AssessmentEvent(
          id: 'a',
          profileId: 'p',
          sessionId: 's',
          turnGroupId: 'turn',
          knowledgeItemId: 'k',
          reviewPointId: 'rp',
          questionMessageId: 'assistant',
          answerMessageIds: ['user'],
          assessmentMode: SessionMode.review,
          askedDimensions: ['ordering'],
          sourceRevisionIds: ['source:v1'],
          result: ReviewOutcome.independentPass,
          independentEligible: true,
          isSpacedEligible: true,
          rationale: 'PRIVATE_ASSESSMENT_REASON',
          createdAt: now,
        ),
      );
      final a = await exportCoachBackup(store);
      final data = Map<String, Object?>.from(jsonDecode(jsonEncode(a['data'])));
      final event = (data['assessmentEvents'] as List).single;
      event['result'] = 'needsReinforcement';
      event['rationale'] = 'OTHER_PRIVATE_REASON';
      final b = coachBackupFromData(data);
      final merged = await mergeCoachBackups(a, b);
      expect(
        (merged['data'] as Map)['assessmentEvents'].single['validity'],
        'pending',
      );
      final recovered = InMemoryCoachStore();
      await restoreCoachBackup(recovered, merged);
      final service = CoachSyncConflictService(recovered, 'p');
      final conflict = (await service.listOpen()).single;
      expect(conflict.table, 'assessmentEvents');
      final redacted = redactCoachBackup(
        merged,
        fullText: false,
        privateMaterials: false,
      );
      expect(
        jsonEncode(redacted),
        isNot(contains('PRIVATE_ASSESSMENT_REASON')),
      );
      expect(jsonEncode(redacted), isNot(contains('OTHER_PRIVATE_REASON')));
      await service.resolve(
        conflict,
        chooseVariant: true,
        now: now.add(const Duration(days: 1)),
      );
      expect(await service.listOpen(), isEmpty);
      expect(
        (await recovered.listAssessmentEvents('s')).any(
          (e) =>
              e.assessmentRevision == 2 &&
              e.validity == EvidenceValidity.accepted,
        ),
        true,
      );
      final repeated = await mergeCoachBackups(
        await exportCoachBackup(recovered),
        b,
      );
      final again = InMemoryCoachStore();
      await restoreCoachBackup(again, repeated);
      expect(await CoachSyncConflictService(again, 'p').listOpen(), isEmpty);
    },
  );

  test(
    'concurrent source revisions keep chunks separated and require choice',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      await provider(store).load();
      await store.putSource(
        Source(
          id: 'source',
          profileId: 'p',
          title: 'Reference',
          type: SourceType.txt,
          contentHash: computeContentHash('alpha'),
          status: IngestionStatus.ready,
          revision: 2,
          content: 'alpha',
          createdAt: now,
          fetchedAt: now,
        ),
      );
      await store.putSourceChunk(
        SourceChunk(
          id: 'chunk-a',
          sourceId: 'source',
          sourceRevision: 2,
          index: 0,
          content: 'alpha',
        ),
      );
      final a = await exportCoachBackup(store);
      final data = Map<String, Object?>.from(jsonDecode(jsonEncode(a['data'])));
      final source = (data['sources'] as List).single;
      source['contentHash'] = computeContentHash('beta');
      source['content'] = 'beta';
      final chunk = (data['sourceChunks'] as List).single;
      chunk['id'] = 'chunk-b';
      chunk['content'] = 'beta';
      final b = coachBackupFromData(data);
      final merged = await mergeCoachBackups(a, b);
      expect(
        (await mergeCoachBackups(b, a))['contentHash'],
        merged['contentHash'],
      );
      final recovered = InMemoryCoachStore();
      await restoreCoachBackup(recovered, merged);
      final conflict = (await CoachSyncConflictService(
        recovered,
        'p',
      ).listOpen()).single;
      expect(conflict.table, 'sources');
      expect(await recovered.listSources('p'), hasLength(2));
      final allChunks = [
        ...await recovered.listSourceChunks('source'),
        ...await recovered.listSourceChunks(conflict.variantId),
      ];
      expect(allChunks, hasLength(2));
      final index = InMemoryIndex();
      for (final src in await recovered.listSources('p')) {
        index.addSource(src);
      }
      for (final c in allChunks) {
        index.addChunk(IndexedChunk(c, 'p'));
      }
      expect(index.scopedIds(profileId: 'p', sourceIds: ['source']), isEmpty);
      final pendingRetry = await mergeCoachBackups(merged, b);
      final pendingStore = InMemoryCoachStore();
      await restoreCoachBackup(pendingStore, pendingRetry);
      expect(
        await CoachSyncConflictService(pendingStore, 'p').listOpen(),
        hasLength(1),
      );
      expect(
        (await pendingStore.getSource('source'))!.status,
        IngestionStatus.pending,
      );
      await CoachSyncConflictService(recovered, 'p').resolve(
        conflict,
        chooseVariant: true,
        now: now.add(const Duration(days: 1)),
      );
      final chosen = (await recovered.getSource('source'))!;
      expect(chosen.revision, 3);
      final live = (await recovered.listSourceChunks(
        'source',
      )).where((c) => c.sourceRevision == chosen.revision).toList();
      expect(live, hasLength(1));
      expect(live.single.content, chosen.content);
      index.addSource(chosen);
      index.addChunk(IndexedChunk(live.single, 'p'));
      expect(
        index.scopedIds(profileId: 'p', sourceIds: ['source']),
        contains(live.single.id),
      );
      final repeated = await mergeCoachBackups(
        await exportCoachBackup(recovered),
        b,
      );
      final again = InMemoryCoachStore();
      await restoreCoachBackup(again, repeated);
      expect(await CoachSyncConflictService(again, 'p').listOpen(), isEmpty);
    },
  );

  test('same-version workflow template choices converge', () async {
    final store = InMemoryCoachStore();
    await seed(store);
    final coach = provider(store);
    await coach.load();
    final template = await coach.saveWorkflowTemplate(
      name: 'Synthetic',
      cards: const [
        WorkflowCard(
          id: 'card',
          type: PlanItemType.learnKnowledge,
          knowledgeItemId: 'k',
          estimatedMinutes: 8,
        ),
      ],
    );
    final a = await exportCoachBackup(store);
    final data = Map<String, Object?>.from(jsonDecode(jsonEncode(a['data'])));
    final record = (data['extensions'] as List).singleWhere(
      (e) => e['kind'] == 'workflowTemplate',
    );
    (record['value']['cards'] as List).single['estimatedMinutes'] = 11;
    final b = coachBackupFromData(data);
    final merged = await mergeCoachBackups(a, b);
    final recovered = InMemoryCoachStore();
    await restoreCoachBackup(recovered, merged);
    final service = CoachSyncConflictService(recovered, 'p');
    final conflict = (await service.listOpen()).single;
    expect(conflict.table, 'extensions');
    final variant = await WorkflowRepository(
      recovered,
    ).getTemplate('p', conflict.variantId);
    await service.resolve(
      conflict,
      chooseVariant: true,
      now: now.add(const Duration(days: 1)),
    );
    final selected = await WorkflowRepository(
      recovered,
    ).getTemplate('p', template.id);
    expect(selected!.version, greaterThan(template.version));
    expect(
      selected.cards.single.estimatedMinutes,
      variant!.cards.single.estimatedMinutes,
    );
    final repeated = await mergeCoachBackups(
      await exportCoachBackup(recovered),
      b,
    );
    final again = InMemoryCoachStore();
    await restoreCoachBackup(again, repeated);
    expect(await CoachSyncConflictService(again, 'p').listOpen(), isEmpty);
  });

  test(
    'same-version plan conflicts preserve both variants and converge',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      final coach = provider(store);
      await coach.load();
      await coach.ensureTodayPlan();
      final a = await exportCoachBackup(store);
      final data = Map<String, Object?>.from(jsonDecode(jsonEncode(a['data'])));
      ((data['dailyPlans'] as List).single['planItems'] as List)
              .first['estimatedMinutes'] =
          7;
      final b = coachBackupFromData(data);
      final ab = await mergeCoachBackups(a, b),
          ba = await mergeCoachBackups(b, a);
      expect((ab['data'] as Map)['dailyPlans'], hasLength(2));
      expect(ab['contentHash'], ba['contentHash']);
      expect(
        (await mergeCoachBackups(ab, b))['contentHash'],
        ab['contentHash'],
      );
    },
  );
}
