class TopicProgress {
  final String topicId;
  final int score;
  final String status; // 'mastered', 'learning', 'new'
  final int practiceCount;
  final DateTime? lastPracticeAt;
  final DateTime? nextReviewAt;

  const TopicProgress({
    required this.topicId,
    required this.score,
    required this.status,
    this.practiceCount = 0,
    this.lastPracticeAt,
    this.nextReviewAt,
  });

  TopicProgress copyWith({
    String? topicId,
    int? score,
    String? status,
    int? practiceCount,
    DateTime? lastPracticeAt,
    DateTime? nextReviewAt,
  }) => TopicProgress(
    topicId: topicId ?? this.topicId,
    score: score ?? this.score,
    status: status ?? this.status,
    practiceCount: practiceCount ?? this.practiceCount,
    lastPracticeAt: lastPracticeAt ?? this.lastPracticeAt,
    nextReviewAt: nextReviewAt ?? this.nextReviewAt,
  );

  factory TopicProgress.fromJson(Map<String, dynamic> json) => TopicProgress(
    topicId: json['topicId'] as String,
    score: (json['score'] as num).toInt(),
    status: json['status'] as String,
    practiceCount: (json['practiceCount'] as num?)?.toInt() ?? 0,
    lastPracticeAt: json['lastPracticeAt'] != null
        ? DateTime.parse(json['lastPracticeAt'] as String)
        : null,
    nextReviewAt: json['nextReviewAt'] != null
        ? DateTime.parse(json['nextReviewAt'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'topicId': topicId,
    'score': score,
    'status': status,
    'practiceCount': practiceCount,
    'lastPracticeAt': lastPracticeAt?.toIso8601String(),
    'nextReviewAt': nextReviewAt?.toIso8601String(),
  };
}

class PracticeSession {
  final String id;
  final String topicId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int score;
  final String? feedback;

  const PracticeSession({
    required this.id,
    required this.topicId,
    required this.startedAt,
    this.completedAt,
    required this.score,
    this.feedback,
  });

  factory PracticeSession.fromJson(Map<String, dynamic> json) =>
      PracticeSession(
        id: json['id'] as String,
        topicId: json['topicId'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        score: (json['score'] as num).toInt(),
        feedback: json['feedback'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'topicId': topicId,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'score': score,
    'feedback': feedback,
  };
}

class PracticeAttempt {
  final String id;
  final String topicId;
  final String promptId;
  final String mode; // recall, review, mockInterview, code, project
  final String question;
  final String answer;
  final DateTime createdAt;
  final int? score;
  final String? level;
  final String? summary;
  final List<String> missedPoints;
  final List<String> wrongPoints;
  final List<String> errorTags;
  final String? improvedAnswer;
  final String? nextAction;
  final String? aiConfigId;
  final bool aiEvaluated;
  final bool localOnly;

  const PracticeAttempt({
    required this.id,
    required this.topicId,
    this.promptId = '',
    required this.mode,
    required this.question,
    required this.answer,
    required this.createdAt,
    this.score,
    this.level,
    this.summary,
    this.missedPoints = const [],
    this.wrongPoints = const [],
    this.errorTags = const [],
    this.improvedAnswer,
    this.nextAction,
    this.aiConfigId,
    this.aiEvaluated = false,
    this.localOnly = true,
  });

  factory PracticeAttempt.fromJson(Map<String, dynamic> json) =>
      PracticeAttempt(
        id: json['id'] as String,
        topicId: json['topicId'] as String,
        promptId: json['promptId'] as String? ?? '',
        mode: json['mode'] as String? ?? 'recall',
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        score: (json['score'] as num?)?.toInt(),
        level: json['level'] as String?,
        summary: json['summary'] as String?,
        missedPoints:
            (json['missedPoints'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        wrongPoints:
            (json['wrongPoints'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        errorTags:
            (json['errorTags'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        improvedAnswer: json['improvedAnswer'] as String?,
        nextAction: json['nextAction'] as String?,
        aiConfigId: json['aiConfigId'] as String?,
        aiEvaluated: json['aiEvaluated'] as bool? ?? false,
        localOnly: json['localOnly'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'topicId': topicId,
    'promptId': promptId,
    'mode': mode,
    'question': question,
    'answer': answer,
    'createdAt': createdAt.toIso8601String(),
    'score': score,
    'level': level,
    'summary': summary,
    'missedPoints': missedPoints,
    'wrongPoints': wrongPoints,
    'errorTags': errorTags,
    'improvedAnswer': improvedAnswer,
    'nextAction': nextAction,
    'aiConfigId': aiConfigId,
    'aiEvaluated': aiEvaluated,
    'localOnly': localOnly,
  };
}

class MockInterviewSession {
  final String id;
  final String scenario;
  final DateTime startedAt;
  final DateTime? completedAt;
  final List<String> topicIds;
  final List<PracticeAttempt> attempts;
  final int averageScore;
  final String reportSummary;
  final List<String> weakTopicIds;
  final List<String> nextActions;
  final bool formalMode;

  const MockInterviewSession({
    required this.id,
    required this.scenario,
    required this.startedAt,
    this.completedAt,
    this.topicIds = const [],
    this.attempts = const [],
    this.averageScore = 0,
    this.reportSummary = '',
    this.weakTopicIds = const [],
    this.nextActions = const [],
    this.formalMode = false,
  });

  factory MockInterviewSession.fromJson(Map<String, dynamic> json) =>
      MockInterviewSession(
        id: json['id'] as String,
        scenario: json['scenario'] as String? ?? 'mixed',
        startedAt: DateTime.parse(json['startedAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        topicIds:
            (json['topicIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        attempts:
            (json['attempts'] as List<dynamic>?)
                ?.map(
                  (e) => PracticeAttempt.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        averageScore: (json['averageScore'] as num?)?.toInt() ?? 0,
        reportSummary: json['reportSummary'] as String? ?? '',
        weakTopicIds:
            (json['weakTopicIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        nextActions:
            (json['nextActions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        formalMode: json['formalMode'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'scenario': scenario,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'topicIds': topicIds,
    'attempts': attempts.map((e) => e.toJson()).toList(),
    'averageScore': averageScore,
    'reportSummary': reportSummary,
    'weakTopicIds': weakTopicIds,
    'nextActions': nextActions,
    'formalMode': formalMode,
  };
}

class PrepPlan {
  final String targetRole;
  final String techStack;
  final DateTime? interviewDate;
  final int dailyMinutes;
  final String jobDescription;
  final DateTime updatedAt;

  const PrepPlan({
    this.targetRole = '',
    this.techStack = '',
    this.interviewDate,
    this.dailyMinutes = 45,
    this.jobDescription = '',
    required this.updatedAt,
  });

  bool get hasTarget =>
      targetRole.trim().isNotEmpty ||
      techStack.trim().isNotEmpty ||
      interviewDate != null ||
      jobDescription.trim().isNotEmpty;

  factory PrepPlan.empty() => PrepPlan(updatedAt: DateTime.now());

  factory PrepPlan.fromJson(Map<String, dynamic> json) => PrepPlan(
    targetRole: json['targetRole'] as String? ?? '',
    techStack: json['techStack'] as String? ?? '',
    interviewDate: json['interviewDate'] != null
        ? DateTime.parse(json['interviewDate'] as String)
        : null,
    dailyMinutes: (json['dailyMinutes'] as num?)?.toInt() ?? 45,
    jobDescription: json['jobDescription'] as String? ?? '',
    updatedAt: DateTime.parse(
      json['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
    ),
  );

  Map<String, dynamic> toJson() => {
    'targetRole': targetRole,
    'techStack': techStack,
    'interviewDate': interviewDate?.toIso8601String(),
    'dailyMinutes': dailyMinutes,
    'jobDescription': jobDescription,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class LocalProfile {
  final String nickname;
  final String avatarSeed;
  final String email;
  final bool emailBound;
  final bool wechatBound;

  const LocalProfile({
    this.nickname = '本地用户',
    this.avatarSeed = 'local',
    this.email = '',
    this.emailBound = false,
    this.wechatBound = false,
  });

  factory LocalProfile.fromJson(Map<String, dynamic> json) => LocalProfile(
    nickname: json['nickname'] as String? ?? '本地用户',
    avatarSeed: json['avatarSeed'] as String? ?? 'local',
    email: json['email'] as String? ?? '',
    emailBound: json['emailBound'] as bool? ?? false,
    wechatBound: json['wechatBound'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'avatarSeed': avatarSeed,
    'email': email,
    'emailBound': emailBound,
    'wechatBound': wechatBound,
  };
}

class SyncSettings {
  final String method; // local, file, webdav, cloud, baidu, quark...
  final String webDavUrl;
  final String webDavUsername;
  final String webDavPassword;
  final DateTime? lastSyncAt;
  final String lastSyncStatus;

  const SyncSettings({
    this.method = 'local',
    this.webDavUrl = '',
    this.webDavUsername = '',
    this.webDavPassword = '',
    this.lastSyncAt,
    this.lastSyncStatus = '本地模式',
  });

  factory SyncSettings.fromJson(Map<String, dynamic> json) => SyncSettings(
    method: json['method'] as String? ?? 'local',
    webDavUrl: json['webDavUrl'] as String? ?? '',
    webDavUsername: json['webDavUsername'] as String? ?? '',
    webDavPassword: json['webDavPassword'] as String? ?? '',
    lastSyncAt: json['lastSyncAt'] != null
        ? DateTime.parse(json['lastSyncAt'] as String)
        : null,
    lastSyncStatus: json['lastSyncStatus'] as String? ?? '本地模式',
  );

  Map<String, dynamic> toJson() => {
    'method': method,
    'webDavUrl': webDavUrl,
    'webDavUsername': webDavUsername,
    'webDavPassword': webDavPassword,
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'lastSyncStatus': lastSyncStatus,
  };
}
