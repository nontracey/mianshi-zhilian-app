import '../domain/common.dart';
import '../domain/evidence.dart';
import 'evidence_reducer.dart';
import 'review_scheduler.dart';

/// Rebuild projections from the latest revision of each question group.
void replayCoachReviewStates(Map<String, Object?> data) {
  final states = data['reviewStates'] as List;
  final events =
      (data['assessmentEvents'] as List)
          .map((e) => AssessmentEvent.fromJson(Map<String, Object?>.from(e)))
          .toList()
        ..sort((a, b) {
          final c = a.createdAt.compareTo(b.createdAt);
          return c == 0 ? a.id.compareTo(b.id) : c;
        });
  final messages = {for (final m in data['messages'] as List) m['id']: m};
  for (var i = 0; i < states.length; i++) {
    final original = ReviewState.fromJson(Map<String, Object?>.from(states[i]));
    final latest = <String, AssessmentEvent>{};
    for (final event in events.where(
      (e) =>
          e.profileId == original.profileId &&
          e.reviewPointId == original.reviewPointId,
    )) {
      final key = '${event.sessionId}:${event.turnGroupId}';
      final old = latest[key];
      if (old == null || event.assessmentRevision > old.assessmentRevision)
        latest[key] = event;
    }
    final related = latest.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (related.isEmpty) continue;
    var state = ReviewState(
      reviewPointId: original.reviewPointId,
      profileId: original.profileId,
      knowledgeItemId: original.knowledgeItemId,
      status: original.firstDueAt == null
          ? ReviewStatus.unseen
          : ReviewStatus.exposed,
      firstDueAt: original.firstDueAt,
      nextDueAt: original.firstDueAt,
      pendingDispute: related.any(
        (e) => e.validity == EvidenceValidity.disputed,
      ),
    );
    final taught = (data['checkpoints'] as List)
        .where(
          (c) =>
              c['profileId'] == original.profileId &&
              c['knowledgeItemId'] == original.knowledgeItemId,
        )
        .map((c) => DateTime.parse(c['updatedAt'] as String))
        .toList();
    if (original.lastTaughtAt != null) taught.add(original.lastTaughtAt!);
    for (final event in related) {
      final question = messages[event.questionMessageId];
      final validQuestion =
          question != null &&
          question['role'] == 'assistant' &&
          question['sessionId'] == event.sessionId &&
          question['profileId'] == event.profileId;
      final validAnswers =
          validQuestion &&
          event.answerMessageIds.isNotEmpty &&
          event.answerMessageIds.every((id) {
            final answer = messages[id];
            return answer != null &&
                answer['role'] == 'user' &&
                answer['profileId'] == event.profileId &&
                answer['sessionId'] == event.sessionId &&
                (answer['sequence'] as int) > (question['sequence'] as int);
          });
      final conclusion = const EvidenceReducer().reduce(
        event,
        AssessmentContext(
          hasValidAnswer: validAnswers,
          hasValidReference: event.sourceRevisionIds.isNotEmpty,
          rubricValid: event.askedDimensions.isNotEmpty,
          wasAnswerShown: event.answerMessageIds.any(
            (id) => messages[id]?['isAnswerShown'] == true,
          ),
          justTaughtSamePoint: taught.any(
            (t) => sameLocalDay(t, event.createdAt),
          ),
          sameDay: sameLocalDay(state.lastAssessedAt, event.createdAt),
        ),
      );
      state = const ReviewScheduler().apply(
        current: state,
        conclusion: conclusion,
        clock: FixedClock(event.createdAt),
      );
    }
    states[i] = state.copyWith(lastTaughtAt: original.lastTaughtAt).toJson();
  }
}
