import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/http_jd_fetcher.dart';
import 'package:mianshi_zhilian/coach/jobs/link_parser.dart';
import 'package:mianshi_zhilian/coach/jobs/models.dart';
import 'package:mianshi_zhilian/coach/application/coach_runtime.dart';
import 'package:mianshi_zhilian/coach/application/plan_service.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/domain/knowledge.dart';
import 'package:mianshi_zhilian/coach/knowledge/index.dart';
import 'package:mianshi_zhilian/coach/knowledge/retriever.dart';
import 'package:mianshi_zhilian/coach/knowledge/source.dart';
import 'package:mianshi_zhilian/coach/lifecycle/lifecycle.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store_native.dart';
import 'package:mianshi_zhilian/coach/policies/evidence_reducer.dart';
import 'package:mianshi_zhilian/coach/policies/review_scheduler.dart';
import 'package:mianshi_zhilian/coach/tools/tool_contract.dart';
import 'package:mianshi_zhilian/providers/coach_provider.dart';
import 'package:mianshi_zhilian/services/coach_store_handle.dart';
import 'fixtures/synthetic.dart';

class MutableClock implements Clock {
  MutableClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

void main() {
  final now = DateTime(2026, 9, 11);
  for (final sqlite in [false, true]) {
    group(sqlite ? 'SQLite' : 'Memory', () {
      late CoachStore store;
      setUp(
        () => store = sqlite
            ? openNativeCoachStoreMemory()
            : InMemoryCoachStore(),
      );
      tearDown(() async {
        if (store is DriftCoachStore) await (store as DriftCoachStore).close();
      });

      test('failed unit of work rolls back all writes', () async {
        await expectLater(
          store.transaction(() async {
            await store.putGoal(buildDemoGoal(now: now));
            await store.putKnowledgeItem(buildDemoKnowledge(now: now));
            throw StateError('synthetic write failure');
          }),
          throwsStateError,
        );
        expect(await store.getGoal(demoGoalId), isNull);
        expect(await store.listKnowledgeItems(demoProfileId), isEmpty);
      });

      test(
        'concurrent answers get distinct monotonically ordered sequences',
        () async {
          final runtime = CoachRuntime(store: store);
          final session = await runtime.startSession(
            profileId: demoProfileId,
            mode: SessionMode.review,
          );
          await Future.wait(
            List.generate(
              5,
              (i) => runtime.appendUserMessage(
                sessionId: session.id,
                content: 'answer $i',
              ),
            ),
          );
          final messages = await store.messagesOf(session.id);
          expect(messages.map((m) => m.sequence), [1, 2, 3, 4, 5]);
          await store.putMessage(messages.first);
          expect((await store.messagesOf(session.id)).length, 5);
        },
      );

      test('only one simultaneous generation can start', () async {
        final a = CoachRuntime(store: store);
        final b = CoachRuntime(store: store);
        final session = await a.startSession(
          profileId: demoProfileId,
          mode: SessionMode.review,
        );
        final outcomes = await Future.wait(
          [a, b].map((r) async {
            try {
              await r.beginModelTurn(session.id);
              return true;
            } on RuntimeConflictException {
              return false;
            }
          }),
        );
        expect(outcomes.where((x) => x).length, 1);
      });

      test(
        'completed sessions reject answers and expired run handles',
        () async {
          final runtime = CoachRuntime(store: store);
          final session = await runtime.startSession(
            profileId: demoProfileId,
            mode: SessionMode.review,
          );
          final handle = await runtime.beginModelTurn(session.id);
          await runtime.finishModelTurn(
            session.id,
            completed: true,
            handle: handle,
          );
          expect(
            () => runtime.assertRunValid(handle),
            throwsA(isA<RuntimeConflictException>()),
          );
          expect(await runtime.cancel(handle), isFalse);
          await expectLater(
            runtime.appendUserMessage(sessionId: session.id, content: 'late'),
            throwsA(isA<RuntimeConflictException>()),
          );
        },
      );
    });
  }

  test(
    'extra batches do not change base counters or disappear on reload',
    () async {
      final store = InMemoryCoachStore();
      final clock = MutableClock(now);
      await store.putGoal(buildDemoGoal(now: now));
      await store.putKnowledgeItem(buildDemoKnowledge(now: now));
      await store.putGoalKnowledgeLink(
        GoalKnowledgeLink(
          goalId: demoGoalId,
          knowledgeItemId: demoKnowledgeId,
          profileId: demoProfileId,
          createdAt: now,
        ),
      );
      for (var i = 0; i < 5; i++) {
        await store.putReviewState(
          ReviewState(
            reviewPointId: 'rp$i',
            profileId: demoProfileId,
            knowledgeItemId: demoKnowledgeId,
            status: ReviewStatus.recall,
            nextDueAt: now,
          ),
        );
      }
      final coach = CoachProvider(
        store: store,
        clock: clock,
        profileId: demoProfileId,
      );
      addTearDown(coach.dispose);
      await coach.load();
      final plan = await coach.ensureTodayPlan();
      for (final item in plan.planItems) {
        await coach.togglePlanItem(item.id);
      }
      await coach.addExtraPlan();
      expect(coach.planDenominator, plan.denominator);
      expect(coach.completedCount, plan.denominator);
      expect(coach.extraPlans.single.planItems.length, 2);
      await coach.togglePlanItem(coach.extraPlans.single.planItems.first.id);
      await coach.reload();
      expect(coach.extraPlans.single.completedCount, 1);
      expect(coach.extraPlans.single.planItems.length, 2);
      expect(coach.completedCount, plan.denominator);
      clock.value = now.add(const Duration(days: 1));
      final tomorrow = await coach.ensureTodayPlan();
      expect(tomorrow.date, '2026-09-12');
      expect(coach.extraPlans, isEmpty);
    },
  );

  test(
    'review eligibility excludes future, taught, tested, stale and disputed items',
    () {
      ReviewState state(String id) => ReviewState(
        reviewPointId: id,
        profileId: 'p',
        knowledgeItemId: 'k',
        status: ReviewStatus.recall,
        nextDueAt: now,
      );
      final selected = const ReviewSelector().select(
        [
          state('ok'),
          state('future').copyWith(nextDueAt: now.add(const Duration(days: 1))),
          state('taught').copyWith(lastTaughtAt: now),
          state('tested').copyWith(lastAssessedAt: now),
          state('stale').copyWith(status: ReviewStatus.stale),
          state('disputed').copyWith(pendingDispute: true),
        ],
        count: 10,
        now: now,
      );
      expect(selected.map((s) => s.reviewPointId), ['ok']);
    },
  );

  test(
    'hint after mastery resets status and interval; premature passes cannot advance',
    () {
      final state = ReviewState(
        reviewPointId: 'rp',
        profileId: 'p',
        knowledgeItemId: 'k',
        status: ReviewStatus.mastered,
        intervalStep: 5,
        consecutiveIndependentPasses: 6,
        nextDueAt: now.add(const Duration(days: 90)),
      );
      final clock = FixedClock(now);
      const scheduler = ReviewScheduler();
      final premature = scheduler.apply(
        current: state,
        clock: clock,
        conclusion: const EvidenceConclusion(
          trigger: SchedulerTrigger.independentPass,
          spaced: true,
          hintUsed: false,
          validity: EvidenceValidity.accepted,
          advanceAllowed: true,
        ),
      );
      expect(premature.consecutiveIndependentPasses, 6);
      final hint = scheduler.apply(
        current: state,
        clock: clock,
        conclusion: const EvidenceConclusion(
          trigger: SchedulerTrigger.coreGapOrHint,
          spaced: false,
          hintUsed: true,
          validity: EvidenceValidity.accepted,
          advanceAllowed: true,
        ),
      );
      expect(hint.status, ReviewStatus.exposed);
      expect(hint.intervalStep, 0);
      expect(hint.consecutiveIndependentPasses, 0);
    },
  );

  test(
    'raw answer without evaluation protects knowledge; removed goals invalidate preview',
    () async {
      final store = InMemoryCoachStore();
      await store.putGoal(buildDemoGoal(now: now));
      await store.putKnowledgeItem(buildDemoKnowledge(now: now));
      await store.putGoalKnowledgeLink(
        GoalKnowledgeLink(
          goalId: demoGoalId,
          knowledgeItemId: demoKnowledgeId,
          profileId: demoProfileId,
          createdAt: now,
        ),
      );
      final runtime = CoachRuntime(store: store);
      final session = await runtime.startSession(
        profileId: demoProfileId,
        mode: SessionMode.review,
        knowledgeItemId: demoKnowledgeId,
        goalId: demoGoalId,
      );
      await runtime.appendUserMessage(
        sessionId: session.id,
        content: 'original answer',
      );
      const source = StoreDeletionSnapshotSource();
      final snapshot = await source.load(store, profileId: demoProfileId);
      const planner = DeletionPlanner();
      final preview = planner.preview(
        snapshot: snapshot,
        goalIds: [demoGoalId],
        idGen: IdGenerator(),
        clock: FixedClock(now),
      );
      expect(preview.unreferencedLearned.length, 1);
      await store.deleteGoal(demoGoalId);
      final fresh = await source.load(store, profileId: demoProfileId);
      expect(
        () => planner.commit(
          preview: preview,
          selection: DeletionSelection(),
          token: ConfirmationToken(
            operationId: preview.operationId,
            issuedAt: now,
            subject: demoGoalId,
            expectedRevisions: preview.expectedRevisions,
          ),
          freshSnapshot: fresh,
          now: now,
        ),
        throwsA(isA<DeletionConflictException>()),
      );
    },
  );

  test(
    'retrieval requires exact profile, knowledge and source revision; replacement removes old tokens',
    () async {
      final index = InMemoryIndex();
      final source = Source(
        id: 's',
        profileId: 'p',
        title: 'Synthetic source',
        type: SourceType.txt,
        contentHash: 'hash',
        status: IngestionStatus.ready,
      );
      index.addSource(source);
      SourceChunk chunk(String content) => SourceChunk(
        id: 'c',
        sourceId: 's',
        sourceRevision: 1,
        index: 0,
        content: content,
      );
      index.addChunk(IndexedChunk(chunk('alpha'), 'p'));
      final retriever = KnowledgeRetriever(index: index);
      expect(await retriever.retrieve('alpha', profileId: 'other'), isEmpty);
      expect(
        await retriever.retrieve('alpha', profileId: 'p', knowledgeItemId: 'k'),
        isEmpty,
      );
      expect(await retriever.retrieve('alpha', profileId: 'p'), hasLength(1));
      index.addChunk(IndexedChunk(chunk('beta'), 'p'));
      expect(await retriever.retrieve('alpha', profileId: 'p'), isEmpty);
      index.addSource(source.copyWith(revision: 2));
      expect(await retriever.retrieve('beta', profileId: 'p'), isEmpty);
    },
  );

  test(
    'JD importer rejects login, ambiguous jobs and lookalike platform domains',
    () {
      expect(
        () => HttpJdFetcher.extractJobPosting('<html>Please log in</html>'),
        throwsA(isA<JdFetchException>()),
      );
      final job = {
        '@type': 'JobPosting',
        'title': 'Synthetic role',
        'description': List.filled(10, 'Build reliable systems.').join(' '),
      };
      String html(Object value) =>
          '<script type="application/ld+json">${jsonEncode(value)}</script>';
      expect(
        HttpJdFetcher.extractJobPosting(html(job)),
        contains('Synthetic role'),
      );
      expect(
        () => HttpJdFetcher.extractJobPosting(html([job, job])),
        throwsA(isA<JdFetchException>()),
      );
      expect(
        detectPlatform(Uri.parse('https://zhipin.com.example.org')),
        JobPlatform.unknown,
      );
      expect(
        detectPlatform(Uri.parse('https://www.zhipin.com')),
        JobPlatform.boss,
      );
    },
  );

  test(
    'unsupported web storage rejects writes instead of silently losing them',
    () async {
      final handle = CoachStoreHandle.unavailable(
        'coach_storage_web_unavailable',
      );
      expect(handle.available, isFalse);
      expect(
        () => handle.store.putGoal(buildDemoGoal(now: now)),
        throwsStateError,
      );
    },
  );
}
