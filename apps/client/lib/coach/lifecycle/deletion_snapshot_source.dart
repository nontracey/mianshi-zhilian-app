/// 从 [CoachStore] 装配删除影响快照（§6.8）。
///
/// 读取与计算分离：[DeletionPlanner] 只做确定性计算，本文件只负责把存储里的
/// 事实读成一个不可变快照，便于单测直接构造快照而不碰数据库。
///
/// 本文件是纯 Dart，不依赖 Flutter。
library;

import '../domain/common.dart';
import '../domain/evidence.dart';
import '../domain/session.dart';
import '../persistence/coach_store.dart';
import 'deletion_models.dart';

/// 从存储装配快照。
class StoreDeletionSnapshotSource {
  const StoreDeletionSnapshotSource();

  /// 装配 [profileId] 的删除影响快照。
  ///
  /// [otherUseProtections]（用户固定保留 / 独立项目训练 / 执行中）与
  /// [historicalSnapshotNotes] 由调用方提供，属于 App 才知道的用途事实。
  Future<DeletionSnapshot> load(
    CoachStore store, {
    required ProfileId profileId,
    List<OtherUseProtection> otherUseProtections = const [],
    List<String> historicalSnapshotNotes = const [],
  }) async {
    final goals = await store.listGoals(profileId);

    final linksByGoal = <GoalId, List<GoalKnowledgeLinkRef>>{};
    for (final goal in goals) {
      final links = await store.listGoalKnowledgeLinks(goal.id);
      // 一个 JD 与同一知识关联多次只计一个引用。
      final seen = <KnowledgeItemId>{};
      final refs = <GoalKnowledgeLinkRef>[];
      for (final link in links) {
        if (!seen.add(link.knowledgeItemId)) continue;
        refs.add(
          GoalKnowledgeLinkRef(
            goalId: link.goalId,
            knowledgeItemId: link.knowledgeItemId,
            requirementIds: link.requirementIds,
          ),
        );
      }
      linksByGoal[goal.id] = refs;
    }

    final knowledgeItems = await store.listKnowledgeItems(profileId);
    final sessions = await store.listSessions(profileId);

    final checkpointsByKnowledge = <KnowledgeItemId, List<LessonCheckpoint>>{};
    final assessmentsByKnowledge = <KnowledgeItemId, List<AssessmentEvent>>{};
    final pausedSessions = <CoachSession>[];
    final rawAnswerKnowledge = <KnowledgeItemId>{};

    for (final session in sessions) {
      if (session.status != RuntimeStatus.completed) {
        pausedSessions.add(session);
      }
      if ((await store.messagesOf(
        session.id,
      )).any((m) => m.role == 'user' && m.content.trim().isNotEmpty)) {
        if (session.knowledgeItemId != null)
          rawAnswerKnowledge.add(session.knowledgeItemId!);
        rawAnswerKnowledge.addAll(
          session.coverageSnapshot?.knowledgeItemIds ?? const [],
        );
      }
      for (final checkpoint in await store.listCheckpoints(session.id)) {
        checkpointsByKnowledge
            .putIfAbsent(checkpoint.knowledgeItemId, () => <LessonCheckpoint>[])
            .add(checkpoint);
      }
      for (final event in await store.listAssessmentEvents(session.id)) {
        assessmentsByKnowledge
            .putIfAbsent(event.knowledgeItemId, () => <AssessmentEvent>[])
            .add(event);
      }
    }

    final records = <KnowledgeItemId, LearningRecordSummary>{};
    for (final item in knowledgeItems) {
      records[item.id] = summarizeLearningRecords(
        hasRawAnswer: rawAnswerKnowledge.contains(item.id),
        checkpoints:
            checkpointsByKnowledge[item.id] ?? const <LessonCheckpoint>[],
        events: assessmentsByKnowledge[item.id] ?? const <AssessmentEvent>[],
        states: await store.listReviewStatesForKnowledge(item.id),
      );
    }

    final plans = await store.listDailyPlans(profileId);
    final openPlans = plans
        .where((plan) => plan.planItems.any((item) => !item.completed))
        .toList();

    return DeletionSnapshot(
      profileId: profileId,
      goals: goals,
      linksByGoal: linksByGoal,
      knowledgeItems: [
        for (final item in knowledgeItems)
          KnowledgeItemRef(
            id: item.id,
            title: item.title,
            contentStatus: item.contentStatus,
            // 只有未核验的 AI 草稿视为“尚未展示给用户”。
            displayedToUser: item.contentStatus != 'ai-draft-unverified',
          ),
      ],
      recordsByKnowledge: records,
      otherUseProtections: otherUseProtections,
      openPlans: openPlans,
      affectedSessions: pausedSessions,
      historicalSnapshotNotes: historicalSnapshotNotes,
    );
  }
}

/// 汇总某知识项的“是否已学过”证据。
///
/// 讲解记录、checkpoint、学习完成、理解检查、原答、正式评估中的任一项都算已学。
LearningRecordSummary summarizeLearningRecords({
  bool hasRawAnswer = false,
  List<LessonCheckpoint> checkpoints = const [],
  List<AssessmentEvent> events = const [],
  List<ReviewState> states = const [],
}) {
  var learningCompleted = false;
  DateTime? lastLearnedAt;
  var maxStatusIndex = -1;

  for (final state in states) {
    if (state.status != ReviewStatus.unseen) learningCompleted = true;
    final index = ReviewStatus.values.indexOf(state.status);
    if (index > maxStatusIndex) maxStatusIndex = index;
    lastLearnedAt = _latest(lastLearnedAt, state.lastAssessedAt);
    lastLearnedAt = _latest(lastLearnedAt, state.lastTaughtAt);
  }

  for (final checkpoint in checkpoints) {
    lastLearnedAt = _latest(lastLearnedAt, checkpoint.updatedAt);
  }

  var acceptedCount = 0;
  var answerCount = hasRawAnswer ? 1 : 0;
  var hasHintAssistedCheck = false;
  for (final event in events) {
    if (event.validity == EvidenceValidity.accepted) acceptedCount++;
    answerCount += event.answerMessageIds.length;
    if (event.hintLevel != 'none') hasHintAssistedCheck = true;
    lastLearnedAt = _latest(lastLearnedAt, event.createdAt);
  }

  return LearningRecordSummary(
    hasLessonCheckpoint: checkpoints.isNotEmpty,
    learningCompleted: learningCompleted,
    hasHintAssistedCheck: hasHintAssistedCheck,
    acceptedAssessmentCount: acceptedCount,
    answerCount: answerCount,
    lastLearnedAt: lastLearnedAt,
    reviewStatus: maxStatusIndex < 0
        ? null
        : ReviewStatus.values[maxStatusIndex],
  );
}

DateTime? _latest(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}
