/// 删除影响预览与保护清理的模型（§6.8）。
///
/// 这些结构是纯数据：装配快照的人负责读存储，规划器只做确定性计算，
/// 因此可以在无模型、无数据库的环境里被单测覆盖。
library;

import '../domain/common.dart';
import '../domain/goal.dart';
import '../domain/plan.dart';
import '../domain/session.dart';

/// 知识项在本次删除中的归类。
enum KnowledgeImpactKind {
  /// 仍被其他未删除 JD（含已保存与归档）引用 → 保留。
  referencedByOtherGoals,

  /// 已无 JD 引用，且尚未学习 → 可作为清理候选（默认仍不勾选）。
  unreferencedUnlearned,

  /// 已无 JD 引用，但已有学习/作答记录 → 必须逐项明确选择。
  unreferencedLearned,

  /// 其他用途保护（用户固定保留 / 独立项目训练 / 执行中）→ 默认不清理。
  otherUseProtected,
}

/// 其他用途保护的类型。
enum OtherUseKind {
  userPinned,
  standaloneProjectTraining,
  inProgressSession,
  other,
}

/// 一条其他用途保护声明。
class OtherUseProtection {
  const OtherUseProtection({required this.knowledgeItemId, required this.kind});

  final KnowledgeItemId knowledgeItemId;
  final OtherUseKind kind;
}

/// 某知识项的学习记录摘要。
///
/// “已学过”不能只按掌握分判断：讲解记录、checkpoint、学习完成、理解检查、
/// 原答、正式评估中的任一项都归入有学习记录组；数据缺失或旧记录无法分类时按
/// 已学保护处理。仅有自动生成但未展示的知识草稿不算用户已学。
class LearningRecordSummary {
  const LearningRecordSummary({
    this.hasLessonCheckpoint = false,
    this.learningCompleted = false,
    this.hasHintAssistedCheck = false,
    this.acceptedAssessmentCount = 0,
    this.answerCount = 0,
    this.lastLearnedAt,
    this.reviewStatus,
    this.uncertain = false,
  });

  final bool hasLessonCheckpoint;
  final bool learningCompleted;
  final bool hasHintAssistedCheck;
  final int acceptedAssessmentCount;
  final int answerCount;
  final DateTime? lastLearnedAt;
  final ReviewStatus? reviewStatus;

  /// 旧记录或数据缺失，无法安全分类 → 按已学保护。
  final bool uncertain;

  static const LearningRecordSummary none = LearningRecordSummary();

  bool get hasAnyRecord =>
      hasLessonCheckpoint ||
      learningCompleted ||
      hasHintAssistedCheck ||
      acceptedAssessmentCount > 0 ||
      answerCount > 0;

  /// 是否必须当作“已学”保护。
  bool get shouldProtectAsLearned => uncertain || hasAnyRecord;

  Map<String, Object?> toJson() => {
    'hasLessonCheckpoint': hasLessonCheckpoint,
    'learningCompleted': learningCompleted,
    'hasHintAssistedCheck': hasHintAssistedCheck,
    'acceptedAssessmentCount': acceptedAssessmentCount,
    'answerCount': answerCount,
    'lastLearnedAt': lastLearnedAt?.toIso8601String(),
    'reviewStatus': reviewStatus?.name,
    'uncertain': uncertain,
    'hasAnyRecord': hasAnyRecord,
  };
}

/// 单个知识项的删除影响。
class KnowledgeImpact {
  const KnowledgeImpact({
    required this.knowledgeItemId,
    required this.title,
    required this.kind,
    this.referencingGoalIds = const [],
    this.records = LearningRecordSummary.none,
    this.otherUse,
    this.isDraftOnly = false,
  });

  final KnowledgeItemId knowledgeItemId;
  final String title;
  final KnowledgeImpactKind kind;

  /// 仍引用该知识的其他（未被删除的）JD。
  final List<GoalId> referencingGoalIds;
  final LearningRecordSummary records;
  final OtherUseProtection? otherUse;

  /// 仅有自动生成且未展示的草稿 → 不计入“已学”。
  final bool isDraftOnly;

  /// 可以进入默认清理候选（未学且无其他引用与用途）。
  bool get selectableForCleanup =>
      kind == KnowledgeImpactKind.unreferencedUnlearned;

  /// 需要用户逐项明确选择处理方式。
  bool get requiresExplicitChoice =>
      kind == KnowledgeImpactKind.unreferencedLearned;

  /// 默认保留，不纳入清理候选。
  bool get isProtected =>
      kind == KnowledgeImpactKind.referencedByOtherGoals ||
      kind == KnowledgeImpactKind.otherUseProtected;

  bool get hasLearningRecords => records.shouldProtectAsLearned;

  Map<String, Object?> toJson() => {
    'knowledgeItemId': knowledgeItemId,
    'title': title,
    'kind': kind.name,
    'referencingGoalIds': referencingGoalIds,
    'records': records.toJson(),
    'otherUse': otherUse?.kind.name,
    'isDraftOnly': isDraftOnly,
  };
}

/// 用户对“已学知识”选择的处理方式。默认第一种。
enum CleanupAction {
  /// 保留知识与记录：留在自主保留，可继续复习；不占定向训练名额。
  keepKnowledgeAndRecords,

  /// 移除知识，保留历史：退出检索与训练，原答与成绩转为只读历史。
  removeKnowledgeKeepHistory,

  /// 连同相关学习记录删除：列明范围后再次确认。
  removeKnowledgeAndRecords,
}

/// 用户在预览里勾选/决定的范围。
///
/// 令牌不能扩大该范围：提交时若出现范围外的知识 ID，直接拒绝。
class DeletionSelection {
  const DeletionSelection({
    this.cleanupKnowledgeIds = const [],
    this.learnedActions = const {},
  });

  /// 明确勾选要清理的“未学且无引用”知识。
  final List<KnowledgeItemId> cleanupKnowledgeIds;

  /// 已学知识的逐项处理方式。
  final Map<KnowledgeItemId, CleanupAction> learnedActions;

  static const DeletionSelection none = DeletionSelection();
}

/// 计算删除影响所需的只读快照。
class DeletionSnapshot {
  const DeletionSnapshot({
    required this.profileId,
    required this.goals,
    required this.linksByGoal,
    required this.knowledgeItems,
    this.recordsByKnowledge = const {},
    this.otherUseProtections = const [],
    this.openPlans = const [],
    this.affectedSessions = const [],
    this.historicalSnapshotNotes = const [],
  });

  final ProfileId profileId;

  /// 该档案的全部 JD，含已保存与归档项（引用检查要覆盖它们）。
  final List<Goal> goals;

  /// goalId → 该 JD 关联的知识项（同一知识多次关联只算一次）。
  final Map<GoalId, List<GoalKnowledgeLinkRef>> linksByGoal;

  final List<KnowledgeItemRef> knowledgeItems;
  final Map<KnowledgeItemId, LearningRecordSummary> recordsByKnowledge;
  final List<OtherUseProtection> otherUseProtections;

  /// 尚未执行完的计划（用于统计受影响的任务）。
  final List<DailyPlan> openPlans;

  /// 受影响且处于暂停中的会话。
  final List<CoachSession> affectedSessions;

  /// 历史快照说明（历史 JD 版本对应的历史问答、引用快照需保留）。
  final List<String> historicalSnapshotNotes;
}

/// `GoalKnowledgeLink` 的最小投影，避免快照与存储层强耦合。
class GoalKnowledgeLinkRef {
  const GoalKnowledgeLinkRef({
    required this.goalId,
    required this.knowledgeItemId,
    this.requirementIds = const [],
  });

  final GoalId goalId;
  final KnowledgeItemId knowledgeItemId;
  final List<RequirementId> requirementIds;
}

/// `KnowledgeItem` 的最小投影。
class KnowledgeItemRef {
  const KnowledgeItemRef({
    required this.id,
    required this.title,
    this.contentStatus = 'ai-draft-unverified',
    this.displayedToUser = false,
  });

  final KnowledgeItemId id;
  final String title;

  /// 'ai-draft-unverified' / 'verified' / 'stale'。
  final String contentStatus;

  /// 是否已经展示给用户。未展示的自动草稿不算“已学”。
  final bool displayedToUser;
}

/// 删除预览。
class DeletionPreview {
  const DeletionPreview({
    required this.operationId,
    required this.profileId,
    required this.goalIds,
    required this.unknownGoalIds,
    required this.expectedRevisions,
    required this.impacts,
    required this.affectedPlanItems,
    required this.affectedSessions,
    required this.historicalSnapshotNotes,
    required this.createdAt,
  });

  final String operationId;
  final ProfileId profileId;

  /// 本次待删除的 JD。
  final List<GoalId> goalIds;

  /// 未在该档案中找到的 JD（不参与删除，需如实告知）。
  final List<GoalId> unknownGoalIds;

  /// goalId → 内容版本（提交时用于判断预览是否已过期）。
  final Map<String, String> expectedRevisions;

  final List<KnowledgeImpact> impacts;

  /// 受影响的待执行计划项数量。
  final int affectedPlanItems;

  /// 受影响且暂停中的场次数量。
  final int affectedSessions;

  final List<String> historicalSnapshotNotes;
  final DateTime createdAt;

  List<KnowledgeImpact> get stillReferenced => impacts
      .where((i) => i.kind == KnowledgeImpactKind.referencedByOtherGoals)
      .toList();

  List<KnowledgeImpact> get unreferencedUnlearned => impacts
      .where((i) => i.kind == KnowledgeImpactKind.unreferencedUnlearned)
      .toList();

  List<KnowledgeImpact> get unreferencedLearned => impacts
      .where((i) => i.kind == KnowledgeImpactKind.unreferencedLearned)
      .toList();

  List<KnowledgeImpact> get protectedByOtherUse => impacts
      .where((i) => i.kind == KnowledgeImpactKind.otherUseProtected)
      .toList();

  int get totalLinkedKnowledge => impacts.length;

  /// 该预览是否涉及任何“已学且无引用”的知识（决定 UI 是否必须展开选择）。
  bool get requiresLearnedDecision => unreferencedLearned.isNotEmpty;

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'profileId': profileId,
    'goalIds': goalIds,
    'unknownGoalIds': unknownGoalIds,
    'expectedRevisions': expectedRevisions,
    'impacts': impacts.map((i) => i.toJson()).toList(),
    'affectedPlanItems': affectedPlanItems,
    'affectedSessions': affectedSessions,
    'historicalSnapshotNotes': historicalSnapshotNotes,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// 提交结果。
class DeletionCommitResult {
  const DeletionCommitResult({
    required this.operationId,
    required this.deletedGoalIds,
    required this.removedKnowledgeIds,
    required this.retainedKnowledgeIds,
    required this.learnedActionsApplied,
    required this.cancelledPlanNotes,
    required this.tombstones,
    required this.cleanupTasks,
  });

  final String operationId;
  final List<GoalId> deletedGoalIds;

  /// 被移除（退出检索与训练）的知识。
  final List<KnowledgeItemId> removedKnowledgeIds;

  /// 仍然保留的知识（含被其他 JD 引用、其他用途保护、以及用户选择保留的）。
  final List<KnowledgeItemId> retainedKnowledgeIds;

  final Map<KnowledgeItemId, CleanupAction> learnedActionsApplied;

  /// 因目标删除而取消/顺延的计划项说明。
  final List<String> cancelledPlanNotes;

  /// 需要写入的同步墓碑，阻止旧设备复活已删目标。
  final List<String> tombstones;

  /// 附件/向量等幂等清理任务（失败可重试，不让已删数据继续参与检索）。
  final List<String> cleanupTasks;

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'deletedGoalIds': deletedGoalIds,
    'removedKnowledgeIds': removedKnowledgeIds,
    'retainedKnowledgeIds': retainedKnowledgeIds,
    'learnedActionsApplied': learnedActionsApplied.map(
      (k, v) => MapEntry(k, v.name),
    ),
    'cancelledPlanNotes': cancelledPlanNotes,
    'tombstones': tombstones,
    'cleanupTasks': cleanupTasks,
  };
}

/// 预览已过期：预览之后出现了新的引用或学习记录。
class DeletionConflictException implements Exception {
  DeletionConflictException({
    required this.operationId,
    required this.reasons,
    required this.refreshedPreview,
  });

  final String operationId;
  final List<String> reasons;

  /// 刷新后的预览，供 UI 直接展示新范围。
  final DeletionPreview refreshedPreview;

  @override
  String toString() =>
      'DeletionConflictException($operationId): ${reasons.join("; ")}';
}

/// 提交范围越权：selectedIds 超出了预览允许清理的范围。
class DeletionScopeException implements Exception {
  DeletionScopeException({required this.operationId, required this.reasons});

  final String operationId;
  final List<String> reasons;

  @override
  String toString() =>
      'DeletionScopeException($operationId): ${reasons.join("; ")}';
}
