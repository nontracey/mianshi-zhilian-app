import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/application/assessment_review.dart';
import 'package:mianshi_zhilian/coach/application/coach_agent.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';
import 'package:mianshi_zhilian/coach/knowledge/source.dart';
import 'package:mianshi_zhilian/coach/model/proposals.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'implementation_flows_test.dart' show seed, provider, now, response;
import 'fakes/mock_gateway.dart';

Future<AssessmentEvent> prepare(CoachStore store) async {
  await seed(store);
  await provider(store).load();
  await store.putSession(
    CoachSession(
      id: 's',
      profileId: 'p',
      mode: SessionMode.review,
      status: RuntimeStatus.completed,
      createdAt: now,
    ),
  );
  for (final entry in [
    ('q', 'assistant', 1, 'What guarantees ordering?'),
    ('a', 'user', 2, 'Per-key serialization.'),
  ]) {
    await store.putMessage(
      CoachMessage(
        id: entry.$1,
        sessionId: 's',
        profileId: 'p',
        role: entry.$2,
        sequence: entry.$3,
        content: entry.$4,
        createdAt: now,
        turnId: 'turn',
      ),
    );
  }
  await store.putSource(
    Source(
      id: 'source',
      profileId: 'p',
      title: 'Synthetic reference',
      type: SourceType.txt,
      contentHash: 'h',
    ),
  );
  await store.putSourceChunks([
    SourceChunk(
      id: 'citation',
      sourceId: 'source',
      sourceRevision: 1,
      index: 0,
      content: 'Per-key serialization preserves ordering.',
    ),
  ]);
  final event = AssessmentEvent(
    id: 'e',
    profileId: 'p',
    sessionId: 's',
    turnGroupId: 'turn',
    knowledgeItemId: 'k',
    reviewPointId: 'rp',
    questionMessageId: 'q',
    answerMessageIds: ['a'],
    assessmentMode: SessionMode.review,
    askedDimensions: ['mechanism'],
    result: ReviewOutcome.independentPass,
    independentEligible: true,
    isSpacedEligible: true,
    sourceRevisionIds: ['citation'],
    createdAt: now,
  );
  await store.putAssessmentEvent(event);
  await store.putReviewState(
    ReviewState(
      profileId: 'p',
      knowledgeItemId: 'k',
      reviewPointId: 'rp',
      intervalStep: 1,
      consecutiveIndependentPasses: 1,
      firstDueAt: now.subtract(const Duration(days: 1)),
    ),
  );
  return event;
}

void main() {
  test(
    'dispute retracts contribution; reassessment appends a revision without changing raw answers',
    () async {
      final store = InMemoryCoachStore();
      final event = await prepare(store);
      final originals = jsonEncode(
        (await store.messagesOf('s')).map((m) => m.toJson()).toList(),
      );
      final gateway = MockModelGateway(
        responder: (request) {
          expect(
            request.messages.last.content,
            contains('Per-key serialization.'),
          );
          return response({
            'reviewPointId': 'rp',
            'questionMessageId': 'q',
            'answerMessageIds': ['a'],
            'askedDimensions': ['mechanism'],
            'result': 'needsReinforcement',
            'hintLevel': 'none',
            'sourceRevisionIds': ['citation'],
            'rationale': 'Explain the serialization boundary.',
          });
        },
      );
      final service = AssessmentReviewService(
        store: store,
        profileId: 'p',
        binding: () =>
            CoachModelBinding(gateway: gateway, providerConfigId: 'test'),
      );
      await service.dispute(event);
      var events = await store.listAssessmentEvents('s');
      expect(events, hasLength(2));
      expect((await store.getReviewState('rp'))!.intervalStep, 0);
      expect((await store.getReviewState('rp'))!.pendingDispute, true);
      final disputed = events.firstWhere((e) => e.assessmentRevision == 2);
      await service.dispute(disputed); // idempotent
      await service.reassess(disputed);
      events = await store.listAssessmentEvents('s');
      expect(events, hasLength(3));
      expect(
        events.firstWhere((e) => e.assessmentRevision == 3).result,
        ReviewOutcome.needsReinforcement,
      );
      expect((await store.getReviewState('rp'))!.pendingDispute, false);
      expect(
        jsonEncode(
          (await store.messagesOf('s')).map((m) => m.toJson()).toList(),
        ),
        originals,
      );
      expect(
        events.firstWhere((e) => e.id == 'e').result,
        ReviewOutcome.independentPass,
      );
    },
  );
  test(
    'invented evidence leaves the dispute and original evaluation intact',
    () async {
      final store = InMemoryCoachStore();
      final event = await prepare(store);
      final gateway = MockModelGateway(
        responder: (_) => response({
          'reviewPointId': 'rp',
          'questionMessageId': 'q',
          'answerMessageIds': ['a'],
          'askedDimensions': ['mechanism'],
          'result': 'independentPass',
          'sourceRevisionIds': ['invented'],
        }),
      );
      final service = AssessmentReviewService(
        store: store,
        profileId: 'p',
        binding: () =>
            CoachModelBinding(gateway: gateway, providerConfigId: 'test'),
      );
      await service.dispute(event);
      final disputed = (await store.listAssessmentEvents(
        's',
      )).firstWhere((e) => e.assessmentRevision == 2);
      await expectLater(service.reassess(disputed), throwsFormatException);
      expect(await store.listAssessmentEvents('s'), hasLength(2));
      expect((await store.getReviewState('rp'))!.pendingDispute, true);
    },
  );
  test(
    'proposals embedded in unrelated prose are not executable assessments',
    () {
      final json = jsonEncode({
        'assistantText': 'Synthetic response',
        'shouldCompleteSession': true,
      });
      expect(CoachTurnProposal.tryParse(json), isNotNull);
      expect(CoachTurnProposal.tryParse('Example only: $json'), isNull);
      expect(CoachTurnProposal.tryParse('```json\n$json\n```'), isNotNull);
    },
  );
}
