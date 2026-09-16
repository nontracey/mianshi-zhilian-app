import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/application/coach_agent.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/domain/goal.dart';
import 'package:mianshi_zhilian/coach/domain/knowledge.dart';
import 'package:mianshi_zhilian/coach/domain/plan.dart';
import 'package:mianshi_zhilian/coach/model/gateway.dart';
import 'package:mianshi_zhilian/coach/model/messages.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_backup.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_sync.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store_native.dart';
import 'package:mianshi_zhilian/coach/workflows/workflows.dart';
import 'package:mianshi_zhilian/providers/coach_provider.dart';
import 'fakes/mock_gateway.dart';

final now = DateTime(2026, 9, 12, 9);
Future<void> seed(CoachStore store) async {
  await store.putGoal(
    Goal(
      id: 'g',
      profileId: 'p',
      title: 'Synthetic role',
      originalText: 'Understand concurrency',
      contentHash: 'h',
      active: true,
      createdAt: now,
      updatedAt: now,
    ),
  );
  await store.putGoalRequirement(
    GoalRequirement(
      id: 'req',
      goalId: 'g',
      profileId: 'p',
      type: RequirementType.hardRequirement,
      title: 'Original requirement',
      importance: Importance.high,
    ),
  );
  await store.putKnowledgeItem(
    KnowledgeItem(
      id: 'k',
      profileId: 'p',
      title: 'Concurrency',
      createdAt: now,
      updatedAt: now,
    ),
  );
  await store.putReviewPoint(
    ReviewPoint(
      id: 'rp',
      profileId: 'p',
      knowledgeItemId: 'k',
      label: 'Ordering',
      createdAt: now,
    ),
  );
  await store.putReviewState(
    ReviewState(reviewPointId: 'rp', profileId: 'p', knowledgeItemId: 'k'),
  );
  await store.putGoalKnowledgeLink(
    GoalKnowledgeLink(
      goalId: 'g',
      knowledgeItemId: 'k',
      profileId: 'p',
      requirementIds: ['req'],
      createdAt: now,
    ),
  );
}

CoachProvider provider(CoachStore store, {MockModelGateway? gateway}) =>
    CoachProvider(
      store: store,
      profileId: 'p',
      clock: FixedClock(now),
      modelBindingProvider: gateway == null
          ? null
          : () => CoachModelBinding(gateway: gateway, providerConfigId: 'test'),
    );
ModelGatewayResponse response(Map<String, Object?> json) =>
    ModelGatewayResponse(
      message: ChatMessage.assistant(content: jsonEncode(json)),
    );

void main() {
  test(
    'default template controls frozen plan and card resumes across reload',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      final coach = provider(store);
      await coach.load();
      final template = await coach.saveWorkflowTemplate(
        name: 'Custom',
        cards: [
          const WorkflowCard(
            id: 'mock',
            type: PlanItemType.mockInterview,
            estimatedMinutes: 10,
            maxQuestions: 2,
          ),
        ],
      );
      await coach.setDefaultWorkflowTemplate(template.id);
      final plan = await coach.ensureTodayPlan();
      expect(plan.planItems.single.maxQuestions, 2);
      expect(plan.planItems.single.goalId, 'g');
      final session = await coach.startPlanItem(plan.planItems.single.id);
      await coach.sendUserMessage('saved answer');
      final restored = provider(store);
      await restored.load();
      final resumed = await restored.startPlanItem(plan.planItems.single.id);
      expect(resumed.id, session.id);
      expect(restored.messages.single.content, 'saved answer');
      expect(resumed.coverageSnapshot!.maxQuestions, 2);
    },
  );

  test('session context remains frozen after requirements change', () async {
    final store = InMemoryCoachStore();
    await seed(store);
    final gateway = MockModelGateway(
      responder: (_) => response({
        'assistantText': 'Question',
        'questionReviewPointId': 'rp',
      }),
    );
    final coach = provider(store, gateway: gateway);
    await coach.load();
    final session = await coach.startSession(mode: SessionMode.interview);
    final requirement = (await store.listGoalRequirements('g')).single;
    await store.putGoalRequirement(
      requirement.copyWith(title: 'Unrelated new requirement'),
    );
    await coach.generateCurrentReply();
    final prompt = gateway.requests.last.messages.first.content;
    expect(prompt, contains('Original requirement'));
    expect(prompt, isNot(contains('Unrelated new requirement')));
    expect((await store.getSession(session.id))!.askedQuestionCount, 1);
    expect(coach.messages.single.references, contains('reviewPoint:rp'));
  });

  test(
    'natural learning switch preserves interview cursor and does not assess command',
    () async {
      final store = InMemoryCoachStore();
      await seed(store);
      final coach = provider(store);
      await coach.load();
      final before = await coach.startSession(mode: SessionMode.interview);
      await coach.sendUserMessage('继续学习');
      expect(coach.activeSession!.mode, SessionMode.learning);
      expect(coach.activeSession!.coverageSnapshot!.parentSessionId, before.id);
      final prior = (await store.getSession(before.id))!;
      expect(prior.status, RuntimeStatus.paused);
      expect(prior.turnSequence, 1);
      expect(await store.listAssessmentEvents(before.id), isEmpty);
    },
  );

  test('question limit ends after accepting the last answer', () async {
    final store = InMemoryCoachStore();
    await seed(store);
    final gateway = MockModelGateway(
      responder: (_) => response({
        'assistantText': 'Response',
        'questionReviewPointId': 'rp',
      }),
    );
    final coach = provider(store, gateway: gateway);
    await coach.load();
    await coach.startSession(mode: SessionMode.interview, maxQuestions: 1);
    await coach.generateCurrentReply();
    expect(coach.activeSession!.status, RuntimeStatus.waitingUser);
    await coach.sendUserMessage('Final answer');
    expect(coach.activeSession!.status, RuntimeStatus.completed);
    expect(coach.activeSession!.askedQuestionCount, 1);
    expect(coach.activeSession!.endedAt, now);
    expect(
      gateway.requests.last.messages.first.content,
      contains('must_finish_after_assessing_latest_answer'),
    );
  });

  for (final native in [false, true]) {
    test(
      'reset is profile scoped and rejects old backups (native=$native)',
      () async {
        final db = native ? openNativeCoachStoreMemory() : null;
        final CoachStore store = db ?? InMemoryCoachStore();
        addTearDown(() => db?.close());
        await seed(store);
        final coach = provider(store);
        await coach.load();
        await coach.startSession();
        await coach.sendUserMessage('Sensitive answer');
        final backup = await exportCoachBackup(store);
        final other = CoachProvider(store: store, profileId: 'other');
        await other.load();
        await other.startSession();
        await coach.clearPersonalMaterials();
        expect(await store.listGoals('p'), isEmpty);
        expect(await store.listSessions('p'), isEmpty);
        expect(await store.listSessions('other'), hasLength(1));
        await expectLater(
          restoreCoachBackup(store, backup),
          throwsFormatException,
        );
        expect(
          jsonEncode(await exportCoachBackup(store)),
          isNot(contains('Sensitive answer')),
        );
      },
    );
  }

  test(
    'sync union preserves originals, reset generation wins, redaction removes text',
    () async {
      final a = InMemoryCoachStore();
      await seed(a);
      final coach = provider(a);
      await coach.load();
      await coach.startSession();
      await coach.sendUserMessage('Private original');
      final before = await exportCoachBackup(a);
      final redacted = redactCoachBackup(
        before,
        fullText: false,
        privateMaterials: false,
      );
      expect(jsonEncode(redacted), isNot(contains('Private original')));
      final merged = await mergeCoachBackups(before, redacted);
      expect(jsonEncode(merged), contains('Private original'));
      await coach.clearPersonalMaterials();
      final cleared = await mergeCoachBackups(
        await exportCoachBackup(a),
        before,
      );
      expect((cleared['data'] as Map)['messages'], isEmpty);
      expect((cleared['data'] as Map)['goals'], isEmpty);
    },
  );

  test(
    'sync identical original id with different text is a conflict',
    () async {
      final a = InMemoryCoachStore();
      await seed(a);
      final coach = provider(a);
      await coach.load();
      await coach.startSession();
      await coach.sendUserMessage('one');
      final backup = await exportCoachBackup(a);
      final data = Map<String, Object?>.from(
        jsonDecode(jsonEncode(backup['data'])),
      );
      (data['messages'] as List).single['content'] = 'different';
      await expectLater(
        mergeCoachBackups(backup, coachBackupFromData(data)),
        throwsFormatException,
      );
    },
  );
}
