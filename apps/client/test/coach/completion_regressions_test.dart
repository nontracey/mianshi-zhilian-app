import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/application/coach_agent.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/plan.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';
import 'package:mianshi_zhilian/coach/jobs/jd_import_service.dart';
import 'package:mianshi_zhilian/coach/knowledge/chunker.dart';
import 'package:mianshi_zhilian/coach/knowledge/importer.dart';
import 'package:mianshi_zhilian/coach/knowledge/index.dart';
import 'package:mianshi_zhilian/coach/knowledge/parser.dart';
import 'package:mianshi_zhilian/coach/model/http_client.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_backup.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_sync.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store_native.dart';
import 'package:mianshi_zhilian/coach/persistence/extension_records.dart';
import 'package:mianshi_zhilian/coach/persistence/legacy_migration.dart';
import 'package:mianshi_zhilian/coach/persistence/legacy_material_migration.dart';
import 'package:mianshi_zhilian/coach/resume/claim_mapping.dart';
import 'package:mianshi_zhilian/coach/resume/resume_parse.dart';
import 'package:mianshi_zhilian/coach/workflows/workflow_template.dart';
import 'package:mianshi_zhilian/providers/coach_provider.dart';
import 'package:mianshi_zhilian/providers/goal_provider.dart';
import 'package:mianshi_zhilian/services/coach_legacy_migration.dart';
import 'fakes/mock_gateway.dart';
import 'implementation_flows_test.dart' show seed, now, response;

class _FailPracticeStore extends InMemoryCoachStore {
  bool fail = true;
  @override
  Future<void> putSession(CoachSession session) async {
    if (fail) throw StateError('synthetic practice write failure');
    await super.putSession(session);
  }
}

class _NoFetch implements JdFetcher {
  @override
  Future<String> fetchText(String url, {CancelToken? cancel}) async => '';
}

class _MutableClock implements Clock {
  _MutableClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

void main() {
  test(
    'material and practice migration roll back and retry as one upgrade',
    () async {
      final store = _FailPracticeStore();
      final snapshot = <String, Object?>{
        'prep_plan': {
          'targetRole': 'Synthetic role',
          'jobDescription': 'Concurrency',
        },
      };
      final input = LegacyPracticeInput(
        attempts: [
          {
            'id': 'a',
            'answer': 'Synthetic answer',
            'question': 'Question?',
            'createdAt': now.toIso8601String(),
          },
        ],
      );
      await expectLater(
        migrateLegacyUpgradeAtomic(
          store: store,
          profileId: 'p',
          snapshot: snapshot,
          practice: input,
        ),
        throwsStateError,
      );
      expect(await store.getProfile('p'), isNull);
      expect(await store.listGoals('p'), isEmpty);
      expect(
        await store.getExtension(
          'p',
          CoachExtensionKind.legacyMigration,
          'legacy.upgrade.snapshot.v1',
        ),
        isNull,
      );
      store.fail = false;
      final result = await migrateLegacyUpgradeAtomic(
        store: store,
        profileId: 'p',
        snapshot: snapshot,
        practice: input,
      );
      expect(result.importedSessions, 1);
      expect(await store.listGoals('p'), hasLength(1));
      expect(await store.listSessions('p'), hasLength(1));
    },
  );

  test('native nested migration joins outer transaction rollback', () async {
    final store = openNativeCoachStoreMemory();
    addTearDown(store.close);
    await expectLater(
      store.transaction(() async {
        await LegacyMaterialMigrator(store: store, profileId: 'p').migrate({
          'prep_plan': {'targetRole': 'Synthetic role'},
        });
        throw StateError('abort upgrade');
      }),
      throwsStateError,
    );
    expect(await store.getProfile('p'), isNull);
    expect(await store.listGoals('p'), isEmpty);
  });

  test(
    'source update keeps history, invalidates current chunks and linked knowledge',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      final clock = FixedClock(now);
      final ids = IdGenerator.deterministic();
      final goals = GoalProvider(
        store: store,
        profileId: 'p',
        documents: DocumentImporter(
          parser: const BuiltInDocumentParser(),
          chunker: Chunker(),
          idGen: ids,
          clock: clock,
        ),
        resumeImport: ResumeImportService(
          parser: const RuleBasedResumeParser(),
          idGen: ids,
          clock: clock,
          matcher: KeywordClaimMatcher(),
        ),
        jdImport: JdImportService(
          fetcher: _NoFetch(),
          parser: const HeuristicJdParser(),
          idGen: ids,
          clock: clock,
        ),
      );
      final imported = await goals.importDocument(
        text: 'Original concurrency note',
        title: 'Reference',
        knowledgeItemId: 'k',
      );
      final original = (await store.getSource(imported.createdSourceId!))!;
      final oldChunk = (await store.listSourceChunks(original.id)).single;
      final updated = await goals.updateDocumentSource(
        original,
        'Revised isolation note',
      );
      expect(updated.ok, true);
      final current = (await store.getSource(original.id))!;
      expect(current.revision, 2);
      expect((await store.listSourceChunks(original.id)), hasLength(2));
      expect((await store.getKnowledgeItem('k'))!.contentStatus, 'stale');
      expect(
        (await store.getExtension(
          'p',
          CoachExtensionKind.sourceRevision,
          '${original.id}@1',
        ))!.value['source'],
        containsPair('content', original.content),
      );
      final index = InMemoryIndex()..addSource(current);
      for (final chunk in await store.listSourceChunks(original.id)) {
        index.addChunk(IndexedChunk(chunk, 'p'));
      }
      final live = index.scopedIds(profileId: 'p');
      expect(live, hasLength(1));
      expect(live, isNot(contains(oldChunk.id)));
      expect(
        (await goals.updateDocumentSource(original, 'stale write')).ok,
        false,
      );
      expect(
        (await goals.updateDocumentSource(
          current,
          current.content!,
        )).messageKey,
        'coach_source_unchanged',
      );
      final redacted = redactCoachBackup(
        await exportCoachBackup(store),
        fullText: false,
        privateMaterials: false,
      );
      expect(redacted.toString(), isNot(contains('Original concurrency note')));
      expect(redacted.toString(), isNot(contains('Revised isolation note')));
    },
  );

  test(
    'deferred workflow cards materialize tomorrow once outside base denominator',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      final clock = _MutableClock(now);
      final coach = CoachProvider(
        store: store,
        profileId: 'p',
        clock: clock,
        idGen: IdGenerator.deterministic(),
      );
      await coach.load();
      final template = WorkflowTemplate(
        id: 'custom',
        cards: const [
          WorkflowCard(
            id: 'mock',
            type: PlanItemType.mockInterview,
            estimatedMinutes: 12,
          ),
        ],
      );
      final plan = DailyPlan(
        id: 'today',
        profileId: 'p',
        date: coach.todayKey,
        timezone: 'CST',
        planItems: [],
        baseMinutes: 5,
        version: 1,
        frozenAt: now,
        revisionNote: 'workflow:custom@v1',
      );
      await coach.applyPlan(
        plan,
        workflowTemplate: template,
        deferredCardIds: const ['mock'],
      );
      clock.value = now.add(const Duration(days: 1));
      await coach.reload();
      final base = await coach.ensureTodayPlan();
      final denominator = base.denominator;
      expect(
        coach.extraPlans.where((p) => p.revisionNote == 'deferred_from:today'),
        hasLength(1),
      );
      expect(coach.extraPlans.single.planItems.single.workflowCardId, 'mock');
      await coach.ensureTodayPlan();
      expect(coach.extraPlans, hasLength(1));
      expect(coach.todayPlan!.denominator, denominator);
    },
  );

  test('undoing an applied workflow cancels its deferred cards', () async {
    final store = InMemoryCoachStore();
    await seed(store);
    final clock = _MutableClock(now);
    final coach = CoachProvider(
      store: store,
      profileId: 'p',
      clock: clock,
      idGen: IdGenerator.deterministic(),
    );
    await coach.load();
    DailyPlan plan(String id, {String? revisionNote}) => DailyPlan(
      id: id,
      profileId: 'p',
      date: coach.todayKey,
      timezone: 'CST',
      planItems: [],
      baseMinutes: 5,
      version: 1,
      frozenAt: now,
      revisionNote: revisionNote,
    );

    await coach.applyPlan(plan('before'));
    await coach.applyPlan(
      plan('applied', revisionNote: 'workflow:custom@v1'),
      workflowTemplate: WorkflowTemplate(
        id: 'custom',
        cards: const [
          WorkflowCard(
            id: 'mock',
            type: PlanItemType.mockInterview,
            estimatedMinutes: 12,
          ),
        ],
      ),
      deferredCardIds: const ['mock'],
    );
    expect(await coach.undoPlanApply(), true);
    expect(
      (await store.getExtension(
        'p',
        CoachExtensionKind.workflowPlanSnapshot,
        'applied',
      ))!.value['cancelledByUndo'],
      true,
    );

    clock.value = now.add(const Duration(days: 1));
    await coach.reload();
    await coach.ensureTodayPlan();
    expect(
      coach.extraPlans.where((p) => p.revisionNote == 'deferred_from:applied'),
      isEmpty,
    );
  });

  test('weakness arising during a workflow adds one reteach extra', () async {
    final store = InMemoryCoachStore();
    await seed(store);
    final gateway = MockModelGateway(
      responder: (_) => response({
        'assistantText': 'Synthetic question',
        'questionReviewPointId': 'rp',
      }),
    );
    final coach = CoachProvider(
      store: store,
      profileId: 'p',
      clock: FixedClock(now),
      idGen: IdGenerator.deterministic(),
      modelBindingProvider: () =>
          CoachModelBinding(gateway: gateway, providerConfigId: 'test'),
    );
    await coach.load();
    final plan = DailyPlan(
      id: 'workflow-plan',
      profileId: 'p',
      date: coach.todayKey,
      timezone: 'CST',
      version: 1,
      baseMinutes: 10,
      frozenAt: now,
      revisionNote: 'workflow:custom@v1',
      planItems: [
        PlanItem(
          id: 'mock-item',
          type: PlanItemType.mockInterview,
          title: '',
          goalId: 'g',
          maxQuestions: 1,
          estimatedMinutes: 10,
          workflowCardId: 'mock',
        ),
      ],
    );
    final template = WorkflowTemplate(
      id: 'custom',
      cards: const [
        WorkflowCard(
          id: 'mock',
          type: PlanItemType.mockInterview,
          estimatedMinutes: 10,
        ),
        WorkflowCard(
          id: 'reteach',
          type: PlanItemType.learnKnowledge,
          knowledgeItemId: 'k',
          condition: WorkflowCondition.reteachOnceWhenWeak,
          estimatedMinutes: 8,
        ),
      ],
    );
    await coach.applyPlan(plan, workflowTemplate: template);
    await store.putReviewState(
      (await store.getReviewState('rp'))!.copyWith(consecutiveWeaknesses: 2),
    );
    await coach.reload();
    await coach.startPlanItem('mock-item');
    await coach.generateCurrentReply();
    await coach.sendUserMessage('Synthetic original answer');
    expect(coach.activeSession!.status, RuntimeStatus.completed);
    final extra = coach.extraPlans
        .where((p) => p.revisionNote == 'workflow_weak_branch:workflow-plan')
        .toList();
    expect(extra, hasLength(1));
    expect(extra.single.planItems.single.knowledgeItemId, 'k');
    expect(coach.todayPlan!.denominator, 1);
    await coach.reload();
    expect(
      coach.extraPlans.where(
        (p) => p.revisionNote == 'workflow_weak_branch:workflow-plan',
      ),
      hasLength(1),
    );
  });
}
