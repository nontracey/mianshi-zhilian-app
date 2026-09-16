/// 作答证据、回测考点与状态投影（§9.3、§9.4、§9.5）。
library;

import 'common.dart';

/// 一次评估事件。模型只提交允许的评价字段，不能直接填入全部权威字段（§9.3）。
class AssessmentEvent {
  AssessmentEvent({
    required this.id,
    required this.profileId,
    required this.sessionId,
    required this.turnGroupId,
    required this.knowledgeItemId,
    required this.reviewPointId,
    required this.questionMessageId,
    required this.answerMessageIds,
    required this.assessmentMode,
    this.askedDimensions = const [],
    this.result = ReviewOutcome.needsReinforcement,
    this.hintLevel = 'none',
    this.independentEligible = false,
    this.isSpacedEligible = false,
    this.validity = EvidenceValidity.accepted,
    this.sourceRevisionIds = const [],
    this.rubricVersion,
    this.rulesVersion,
    this.providerConfigId,
    required this.createdAt,
    this.assessmentRevision = 1,
    this.rationale,
  });

  final AssessmentEventId id;
  final ProfileId profileId;
  final SessionId sessionId;

  /// 一组主问与中性追问共享一个 turn group，只计一次评估（§9.3）。
  final String turnGroupId;
  final KnowledgeItemId knowledgeItemId;
  final ReviewPointId reviewPointId;
  final String questionMessageId;
  final List<MessageId> answerMessageIds;
  final SessionMode assessmentMode;
  final List<String> askedDimensions;
  final ReviewOutcome result;
  final String hintLevel;
  final bool independentEligible;
  final bool isSpacedEligible;
  final EvidenceValidity validity;
  final List<SourceId> sourceRevisionIds;
  final String? rubricVersion;
  final String? rulesVersion;
  final String? providerConfigId;
  final DateTime createdAt;

  /// 同一 session + turnGroup + assessmentRevision 唯一（§9.3）。
  final int assessmentRevision;
  final String? rationale;

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'sessionId': sessionId,
    'turnGroupId': turnGroupId,
    'knowledgeItemId': knowledgeItemId,
    'reviewPointId': reviewPointId,
    'questionMessageId': questionMessageId,
    'answerMessageIds': answerMessageIds,
    'assessmentMode': assessmentMode.name,
    'askedDimensions': askedDimensions,
    'result': result.name,
    'hintLevel': hintLevel,
    'independentEligible': independentEligible,
    'isSpacedEligible': isSpacedEligible,
    'validity': validity.name,
    'sourceRevisionIds': sourceRevisionIds,
    'rubricVersion': rubricVersion,
    'rulesVersion': rulesVersion,
    'providerConfigId': providerConfigId,
    'createdAt': createdAt.toIso8601String(),
    'assessmentRevision': assessmentRevision,
    'rationale': rationale,
  };

  factory AssessmentEvent.fromJson(Map<String, Object?> json) =>
      AssessmentEvent(
        id: json['id'] as String,
        profileId: json['profileId'] as String,
        sessionId: json['sessionId'] as String,
        turnGroupId: json['turnGroupId'] as String,
        knowledgeItemId: json['knowledgeItemId'] as String,
        reviewPointId: json['reviewPointId'] as String,
        questionMessageId: json['questionMessageId'] as String,
        answerMessageIds: (json['answerMessageIds'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        assessmentMode: SessionMode.values.firstWhere(
          (e) => e.name == json['assessmentMode'],
          orElse: () => SessionMode.learning,
        ),
        askedDimensions: (json['askedDimensions'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        result: ReviewOutcome.values.firstWhere(
          (e) => e.name == json['result'],
          orElse: () => ReviewOutcome.needsReinforcement,
        ),
        hintLevel: json['hintLevel'] as String? ?? 'none',
        independentEligible: json['independentEligible'] as bool? ?? false,
        isSpacedEligible: json['isSpacedEligible'] as bool? ?? false,
        validity: EvidenceValidity.values.firstWhere(
          (e) => e.name == json['validity'],
          orElse: () => EvidenceValidity.accepted,
        ),
        sourceRevisionIds: (json['sourceRevisionIds'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        rubricVersion: json['rubricVersion'] as String?,
        rulesVersion: json['rulesVersion'] as String?,
        providerConfigId: json['providerConfigId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        assessmentRevision: json['assessmentRevision'] as int? ?? 1,
        rationale: json['rationale'] as String?,
      );
}

/// 回测考点。每个知识点最多 8 个（§9.4）。
class ReviewPoint {
  ReviewPoint({
    required this.id,
    required this.profileId,
    required this.knowledgeItemId,
    required this.label,
    this.aliases = const [],
    this.createdAt,
  });

  final ReviewPointId id;
  final ProfileId profileId;
  final KnowledgeItemId knowledgeItemId;
  final String label;
  final List<String> aliases;
  final DateTime? createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'knowledgeItemId': knowledgeItemId,
    'label': label,
    'aliases': aliases,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory ReviewPoint.fromJson(Map<String, Object?> json) => ReviewPoint(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    knowledgeItemId: json['knowledgeItemId'] as String,
    label: json['label'] as String,
    aliases: (json['aliases'] as List? ?? const [])
        .map((e) => e as String)
        .toList(),
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.parse(json['createdAt'] as String),
  );
}

/// 回测状态投影。保存每个考点的状态、首次待测、到期日、阶梯、连续薄弱次数。
class ReviewState {
  ReviewState({
    required this.reviewPointId,
    required this.profileId,
    required this.knowledgeItemId,
    this.status = ReviewStatus.unseen,
    this.firstDueAt,
    this.nextDueAt,
    this.lastAssessedAt,
    this.lastTaughtAt,
    this.consecutiveIndependentPasses = 0,
    this.consecutiveWeaknesses = 0,
    this.intervalStep = 0,
    this.pendingDispute = false,
  });

  final ReviewPointId reviewPointId;
  final ProfileId profileId;
  final KnowledgeItemId knowledgeItemId;
  final ReviewStatus status;
  final DateTime? firstDueAt;
  final DateTime? nextDueAt;
  final DateTime? lastAssessedAt;
  final DateTime? lastTaughtAt;
  final int consecutiveIndependentPasses;
  final int consecutiveWeaknesses;
  final int intervalStep;
  final bool pendingDispute;

  Map<String, Object?> toJson() => {
    'reviewPointId': reviewPointId,
    'profileId': profileId,
    'knowledgeItemId': knowledgeItemId,
    'status': status.name,
    'firstDueAt': firstDueAt?.toIso8601String(),
    'nextDueAt': nextDueAt?.toIso8601String(),
    'lastAssessedAt': lastAssessedAt?.toIso8601String(),
    'lastTaughtAt': lastTaughtAt?.toIso8601String(),
    'consecutiveIndependentPasses': consecutiveIndependentPasses,
    'consecutiveWeaknesses': consecutiveWeaknesses,
    'intervalStep': intervalStep,
    'pendingDispute': pendingDispute,
  };

  factory ReviewState.fromJson(Map<String, Object?> json) => ReviewState(
    reviewPointId: json['reviewPointId'] as String,
    profileId: json['profileId'] as String,
    knowledgeItemId: json['knowledgeItemId'] as String,
    status: ReviewStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => ReviewStatus.unseen,
    ),
    firstDueAt: json['firstDueAt'] == null
        ? null
        : DateTime.parse(json['firstDueAt'] as String),
    nextDueAt: json['nextDueAt'] == null
        ? null
        : DateTime.parse(json['nextDueAt'] as String),
    lastAssessedAt: json['lastAssessedAt'] == null
        ? null
        : DateTime.parse(json['lastAssessedAt'] as String),
    lastTaughtAt: json['lastTaughtAt'] == null
        ? null
        : DateTime.parse(json['lastTaughtAt'] as String),
    consecutiveIndependentPasses:
        json['consecutiveIndependentPasses'] as int? ?? 0,
    consecutiveWeaknesses: json['consecutiveWeaknesses'] as int? ?? 0,
    intervalStep: json['intervalStep'] as int? ?? 0,
    pendingDispute: json['pendingDispute'] as bool? ?? false,
  );

  ReviewState copyWith({
    ReviewStatus? status,
    DateTime? firstDueAt,
    DateTime? nextDueAt,
    DateTime? lastAssessedAt,
    DateTime? lastTaughtAt,
    int? consecutiveIndependentPasses,
    int? consecutiveWeaknesses,
    int? intervalStep,
    bool? pendingDispute,
  }) {
    return ReviewState(
      reviewPointId: reviewPointId,
      profileId: profileId,
      knowledgeItemId: knowledgeItemId,
      status: status ?? this.status,
      firstDueAt: firstDueAt ?? this.firstDueAt,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      lastAssessedAt: lastAssessedAt ?? this.lastAssessedAt,
      lastTaughtAt: lastTaughtAt ?? this.lastTaughtAt,
      consecutiveIndependentPasses:
          consecutiveIndependentPasses ?? this.consecutiveIndependentPasses,
      consecutiveWeaknesses:
          consecutiveWeaknesses ?? this.consecutiveWeaknesses,
      intervalStep: intervalStep ?? this.intervalStep,
      pendingDispute: pendingDispute ?? this.pendingDispute,
    );
  }

  bool canReview(DateTime now) =>
      status != ReviewStatus.unseen &&
      status != ReviewStatus.stale &&
      !pendingDispute &&
      isDue(now) &&
      !sameLocalDay(lastTaughtAt, now) &&
      !sameLocalDay(lastAssessedAt, now);

  /// 是否到期（用于计划选题）。
  bool isDue(DateTime now) {
    if (nextDueAt == null) return false;
    return !nextDueAt!.isAfter(now);
  }
}
