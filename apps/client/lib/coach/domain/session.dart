/// 会话、消息与教学检查点（§7.3、§5 学习续接）。
library;

import 'common.dart';

/// Frozen interview scope. It records what was actually in scope when a mock
/// starts; later JD or resume edits must not rewrite a historical report.
class SessionCoverageSnapshot {
  const SessionCoverageSnapshot({
    this.requirementIds = const [],
    this.knowledgeItemIds = const [],
    this.reviewPointIds = const [],
    this.projectIds = const [],
    this.claimIds = const [],
    this.requirements = const [],
    this.projects = const [],
    this.claims = const [],
    this.reviewPoints = const [],
    this.knowledgeItems = const [],
    this.knowledgeLinks = const [],
    this.maxQuestions,
    this.planItemId,
    this.parentSessionId,
  });

  final List<RequirementId> requirementIds;
  final List<KnowledgeItemId> knowledgeItemIds;
  final List<ReviewPointId> reviewPointIds;
  final List<ProjectId> projectIds;
  final List<ClaimId> claimIds;
  // Full immutable values keep historical context independent of later edits.
  final List<Map<String, dynamic>> requirements;
  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> claims;
  final List<Map<String, dynamic>> reviewPoints;
  final List<Map<String, dynamic>> knowledgeItems;
  final List<Map<String, dynamic>> knowledgeLinks;
  final int? maxQuestions;
  final String? planItemId;
  final String? parentSessionId;

  Map<String, Object?> toJson() => {
    'requirementIds': requirementIds,
    'knowledgeItemIds': knowledgeItemIds,
    'reviewPointIds': reviewPointIds,
    'projectIds': projectIds,
    'claimIds': claimIds,
    'requirements': requirements,
    'projects': projects,
    'claims': claims,
    'reviewPoints': reviewPoints,
    'knowledgeItems': knowledgeItems,
    'knowledgeLinks': knowledgeLinks,
    'maxQuestions': maxQuestions,
    'planItemId': planItemId,
    'parentSessionId': parentSessionId,
  };

  factory SessionCoverageSnapshot.fromJson(Map<String, Object?> json) =>
      SessionCoverageSnapshot(
        requirementIds: _stringList(json['requirementIds']),
        knowledgeItemIds: _stringList(json['knowledgeItemIds']),
        reviewPointIds: _stringList(json['reviewPointIds']),
        projectIds: _stringList(json['projectIds']),
        claimIds: _stringList(json['claimIds']),
        requirements: _maps(json['requirements']),
        projects: _maps(json['projects']),
        claims: _maps(json['claims']),
        reviewPoints: _maps(json['reviewPoints']),
        knowledgeItems: _maps(json['knowledgeItems']),
        knowledgeLinks: _maps(json['knowledgeLinks']),
        maxQuestions: json['maxQuestions'] as int?,
        planItemId: json['planItemId'] as String?,
        parentSessionId: json['parentSessionId'] as String?,
      );
}

List<Map<String, dynamic>> _maps(Object? value) => (value as List? ?? const [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

List<String> _stringList(Object? value) =>
    (value as List? ?? const []).map((item) => item as String).toList();

/// 教练会话。模式、目标快照、实际题目与原答、状态、顺序号。
class CoachSession {
  CoachSession({
    required this.id,
    required this.profileId,
    required this.mode,
    required this.createdAt,
    this.status = RuntimeStatus.idle,
    this.goalId,
    this.goalRevision,
    this.resumeId,
    this.resumeRevision,
    this.projectIds = const [],
    this.knowledgeItemId,
    this.reviewPointId,
    this.turnSequence = 0,
    this.expectedRevision = 1,
    this.interviewDurationMinutes,
    this.startedAt,
    this.endedAt,
    this.coverageSnapshot,
    this.askedQuestionCount = 0,
    this.stopReason,
    this.partial = false,
    this.interviewStyle,
  });

  final SessionId id;
  final ProfileId profileId;
  final SessionMode mode;
  final DateTime createdAt;
  final RuntimeStatus status;

  /// 场次开始时固定目标版本；切换目标不会把前一 JD 的问答改成新目标成绩（§6.2）。
  final GoalId? goalId;
  final int? goalRevision;
  final ResumeId? resumeId;
  final int? resumeRevision;
  final List<ProjectId> projectIds;

  /// 当前题目范围（学习/回测用）。
  final KnowledgeItemId? knowledgeItemId;
  final ReviewPointId? reviewPointId;

  final int turnSequence;
  final int expectedRevision;

  /// Interview-only lifecycle facts. They stay optional for existing learning
  /// and review sessions and make partial mock reports auditable.
  final int? interviewDurationMinutes;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final SessionCoverageSnapshot? coverageSnapshot;
  final int askedQuestionCount;
  final String? stopReason;
  final bool partial;
  final String? interviewStyle;

  CoachSession copyWith({
    RuntimeStatus? status,
    int? turnSequence,
    int? expectedRevision,
    KnowledgeItemId? knowledgeItemId,
    ReviewPointId? reviewPointId,
    int? interviewDurationMinutes,
    DateTime? startedAt,
    DateTime? endedAt,
    SessionCoverageSnapshot? coverageSnapshot,
    int? askedQuestionCount,
    String? stopReason,
    bool? partial,
    String? interviewStyle,
    bool clearEndedAt = false,
    bool clearCoverageSnapshot = false,
    bool clearStopReason = false,
    bool clearInterviewStyle = false,
  }) {
    return CoachSession(
      id: id,
      profileId: profileId,
      mode: mode,
      createdAt: createdAt,
      status: status ?? this.status,
      goalId: goalId,
      goalRevision: goalRevision,
      resumeId: resumeId,
      resumeRevision: resumeRevision,
      projectIds: projectIds,
      knowledgeItemId: knowledgeItemId ?? this.knowledgeItemId,
      reviewPointId: reviewPointId ?? this.reviewPointId,
      turnSequence: turnSequence ?? this.turnSequence,
      expectedRevision: expectedRevision ?? this.expectedRevision,
      interviewDurationMinutes:
          interviewDurationMinutes ?? this.interviewDurationMinutes,
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      coverageSnapshot: clearCoverageSnapshot
          ? null
          : (coverageSnapshot ?? this.coverageSnapshot),
      askedQuestionCount: askedQuestionCount ?? this.askedQuestionCount,
      stopReason: clearStopReason ? null : (stopReason ?? this.stopReason),
      partial: partial ?? this.partial,
      interviewStyle: clearInterviewStyle
          ? null
          : (interviewStyle ?? this.interviewStyle),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'mode': mode.name,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'goalId': goalId,
    'goalRevision': goalRevision,
    'resumeId': resumeId,
    'resumeRevision': resumeRevision,
    'projectIds': projectIds,
    'knowledgeItemId': knowledgeItemId,
    'reviewPointId': reviewPointId,
    'turnSequence': turnSequence,
    'expectedRevision': expectedRevision,
    'interviewDurationMinutes': interviewDurationMinutes,
    'startedAt': startedAt?.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'coverageSnapshot': coverageSnapshot?.toJson(),
    'askedQuestionCount': askedQuestionCount,
    'stopReason': stopReason,
    'partial': partial,
    'interviewStyle': interviewStyle,
  };

  factory CoachSession.fromJson(Map<String, Object?> json) => CoachSession(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    mode: SessionMode.values.firstWhere(
      (e) => e.name == json['mode'],
      orElse: () => SessionMode.learning,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: RuntimeStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => RuntimeStatus.idle,
    ),
    goalId: json['goalId'] as String?,
    goalRevision: json['goalRevision'] as int?,
    resumeId: json['resumeId'] as String?,
    resumeRevision: json['resumeRevision'] as int?,
    projectIds: _stringList(json['projectIds']),
    knowledgeItemId: json['knowledgeItemId'] as String?,
    reviewPointId: json['reviewPointId'] as String?,
    turnSequence: json['turnSequence'] as int? ?? 0,
    expectedRevision: json['expectedRevision'] as int? ?? 1,
    interviewDurationMinutes: json['interviewDurationMinutes'] as int?,
    startedAt: json['startedAt'] == null
        ? null
        : DateTime.parse(json['startedAt'] as String),
    endedAt: json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt'] as String),
    coverageSnapshot: json['coverageSnapshot'] is Map
        ? SessionCoverageSnapshot.fromJson(
            (json['coverageSnapshot'] as Map).map(
              (k, v) => MapEntry(k.toString(), v),
            ),
          )
        : null,
    askedQuestionCount: json['askedQuestionCount'] as int? ?? 0,
    stopReason: json['stopReason'] as String?,
    partial: json['partial'] as bool? ?? false,
    interviewStyle: json['interviewStyle'] as String?,
  );
}

/// 会话消息。用户原答、模型回答、工具结果都作为消息保存，带 turnId（§7.3）。
class CoachMessage {
  CoachMessage({
    required this.id,
    required this.sessionId,
    required this.profileId,
    required this.role,
    required this.content,
    required this.turnId,
    required this.sequence,
    required this.createdAt,
    this.references = const [],
    this.isAnswerShown = false,
  });

  final MessageId id;
  final SessionId sessionId;
  final ProfileId profileId;

  /// 'user' / 'assistant' / 'tool' / 'system'。
  final String role;
  final String content;
  final String turnId;
  final int sequence;
  final DateTime createdAt;

  /// 引用的资料 ID（RAG 用，检索增强后续接入）。
  final List<String> references;

  /// App 知道标准答案是否展示，不信任模型自报（§9.4）。
  final bool isAnswerShown;

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'profileId': profileId,
    'role': role,
    'content': content,
    'turnId': turnId,
    'sequence': sequence,
    'createdAt': createdAt.toIso8601String(),
    'references': references,
    'isAnswerShown': isAnswerShown,
  };

  factory CoachMessage.fromJson(Map<String, Object?> json) => CoachMessage(
    id: json['id'] as String,
    sessionId: json['sessionId'] as String,
    profileId: json['profileId'] as String,
    role: json['role'] as String,
    content: json['content'] as String,
    turnId: json['turnId'] as String,
    sequence: json['sequence'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    references: _stringList(json['references']),
    isAnswerShown: json['isAnswerShown'] as bool? ?? false,
  );
}

/// 教学检查点。保存已讲范围与疑问，不依赖模型保留旧聊天（§5）。
class LessonCheckpoint {
  LessonCheckpoint({
    required this.id,
    required this.sessionId,
    required this.profileId,
    required this.knowledgeItemId,
    required this.taughtScope,
    this.openQuestions = const [],
    this.nextPosition,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final SessionId sessionId;
  final ProfileId profileId;
  final KnowledgeItemId knowledgeItemId;

  /// 实际已讲解的范围描述。
  final String taughtScope;
  final List<String> openQuestions;

  /// 下一教学位置（用于“下一题”续接）。
  final String? nextPosition;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'profileId': profileId,
    'knowledgeItemId': knowledgeItemId,
    'taughtScope': taughtScope,
    'openQuestions': openQuestions,
    'nextPosition': nextPosition,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory LessonCheckpoint.fromJson(Map<String, Object?> json) =>
      LessonCheckpoint(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        profileId: json['profileId'] as String,
        knowledgeItemId: json['knowledgeItemId'] as String,
        taughtScope: json['taughtScope'] as String,
        openQuestions: _stringList(json['openQuestions']),
        nextPosition: json['nextPosition'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
