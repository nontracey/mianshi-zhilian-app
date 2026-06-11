import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class TopicProgress {
  final String topicId;
  final int score;
  final String status; // 'mastered', 'learning', 'new'
  final int practiceCount;
  final DateTime? lastPracticeAt;
  final DateTime? nextReviewAt;

  /// 当前复习间隔天数（间隔重复用）。0 表示尚未排期/旧数据，
  /// 由 [ProgressProvider] 在每次练习后按遗忘曲线递进。
  final int reviewIntervalDays;

  const TopicProgress({
    required this.topicId,
    required this.score,
    required this.status,
    this.practiceCount = 0,
    this.lastPracticeAt,
    this.nextReviewAt,
    this.reviewIntervalDays = 0,
  });

  TopicProgress copyWith({
    String? topicId,
    int? score,
    String? status,
    int? practiceCount,
    DateTime? lastPracticeAt,
    DateTime? nextReviewAt,
    int? reviewIntervalDays,
  }) => TopicProgress(
    topicId: topicId ?? this.topicId,
    score: score ?? this.score,
    status: status ?? this.status,
    practiceCount: practiceCount ?? this.practiceCount,
    lastPracticeAt: lastPracticeAt ?? this.lastPracticeAt,
    nextReviewAt: nextReviewAt ?? this.nextReviewAt,
    reviewIntervalDays: reviewIntervalDays ?? this.reviewIntervalDays,
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
    reviewIntervalDays: (json['reviewIntervalDays'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'topicId': topicId,
    'score': score,
    'status': status,
    'practiceCount': practiceCount,
    'lastPracticeAt': lastPracticeAt?.toIso8601String(),
    'nextReviewAt': nextReviewAt?.toIso8601String(),
    'reviewIntervalDays': reviewIntervalDays,
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
  final String analysisStatus; // unanalysed, success, failed, pending

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
    this.analysisStatus = 'unanalysed',
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
        analysisStatus:
            json['analysisStatus'] as String? ??
            ((json['aiEvaluated'] as bool? ?? false)
                ? 'success'
                : 'unanalysed'),
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
    'analysisStatus': analysisStatus,
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
  final String? sourceRouteId;

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
    this.sourceRouteId,
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
        sourceRouteId: json['sourceRouteId'] as String?,
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
    if (sourceRouteId != null) 'sourceRouteId': sourceRouteId,
  };

  MockInterviewSession copyWith({
    String? id,
    String? scenario,
    DateTime? startedAt,
    DateTime? completedAt,
    List<String>? topicIds,
    List<PracticeAttempt>? attempts,
    int? averageScore,
    String? reportSummary,
    List<String>? weakTopicIds,
    List<String>? nextActions,
    bool? formalMode,
    String? sourceRouteId,
  }) => MockInterviewSession(
    id: id ?? this.id,
    scenario: scenario ?? this.scenario,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    topicIds: topicIds ?? this.topicIds,
    attempts: attempts ?? this.attempts,
    averageScore: averageScore ?? this.averageScore,
    reportSummary: reportSummary ?? this.reportSummary,
    weakTopicIds: weakTopicIds ?? this.weakTopicIds,
    nextActions: nextActions ?? this.nextActions,
    formalMode: formalMode ?? this.formalMode,
    sourceRouteId: sourceRouteId ?? this.sourceRouteId,
  );
}

class PrepPlan {
  final String targetRole;
  final String techStack;
  final DateTime? interviewDate;
  final int dailyMinutes;
  final String jobDescription;
  final String? company;
  final String? currentLevel;
  final DateTime updatedAt;

  const PrepPlan({
    this.targetRole = '',
    this.techStack = '',
    this.interviewDate,
    this.dailyMinutes = 45,
    this.jobDescription = '',
    this.company,
    this.currentLevel,
    required this.updatedAt,
  });

  bool get hasTarget =>
      targetRole.trim().isNotEmpty ||
      techStack.trim().isNotEmpty ||
      interviewDate != null ||
      jobDescription.trim().isNotEmpty ||
      (company ?? '').trim().isNotEmpty;

  /// 用于检测目标变化的签名（稳定哈希，跨进程一致）
  String get signature {
    final input = '${targetRole.trim()}_${techStack.trim()}_${jobDescription.trim()}_${interviewDate?.toIso8601String() ?? ''}';
    return sha256.convert(utf8.encode(input)).toString().substring(0, 16);
  }

  factory PrepPlan.empty() => PrepPlan(updatedAt: DateTime.now());

  factory PrepPlan.fromJson(Map<String, dynamic> json) => PrepPlan(
    targetRole: json['targetRole'] as String? ?? '',
    techStack: json['techStack'] as String? ?? '',
    interviewDate: json['interviewDate'] != null
        ? DateTime.parse(json['interviewDate'] as String)
        : null,
    dailyMinutes: (json['dailyMinutes'] as num?)?.toInt() ?? 45,
    jobDescription: json['jobDescription'] as String? ?? '',
    company: json['company'] as String?,
    currentLevel: json['currentLevel'] as String?,
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
    if (company != null) 'company': company,
    if (currentLevel != null) 'currentLevel': currentLevel,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class LocalProfile {
  final String nickname;
  final String avatarSeed;
  final String? avatarUrl;
  final String email;
  final bool emailBound;
  final bool wechatBound;

  /// 最近一次修改时间，用于同步时的 last-write-wins 合并（跨设备收敛）。
  /// 旧数据可能为 null，合并时按"最旧"处理（本地优先回退）。
  final DateTime? updatedAt;

  const LocalProfile({
    this.nickname = '本地用户',
    this.avatarSeed = 'local',
    this.avatarUrl,
    this.email = '',
    this.emailBound = false,
    this.wechatBound = false,
    this.updatedAt,
  });

  /// 创建一个随机种子默认头像的本地用户配置。
  /// 新访客每次启动会得到不同的 DiceBear 头像。
  factory LocalProfile.defaultProfile() {
    final random = Random();
    final seed = 'guest_${random.nextInt(1000000)}';
    return LocalProfile(avatarSeed: seed);
  }

  factory LocalProfile.fromJson(Map<String, dynamic> json) => LocalProfile(
    nickname: json['nickname'] as String? ?? '本地用户',
    avatarSeed: json['avatarSeed'] as String? ?? 'guest_${Random().nextInt(1000000)}',
    avatarUrl: json['avatarUrl'] as String?,
    email: json['email'] as String? ?? '',
    emailBound: json['emailBound'] as bool? ?? false,
    wechatBound: json['wechatBound'] as bool? ?? false,
    updatedAt: json['updatedAt'] != null
        ? DateTime.tryParse(json['updatedAt'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'avatarSeed': avatarSeed,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    'email': email,
    'emailBound': emailBound,
    'wechatBound': wechatBound,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  LocalProfile copyWith({
    String? nickname,
    String? avatarSeed,
    String? avatarUrl,
    String? email,
    bool? emailBound,
    bool? wechatBound,
    DateTime? updatedAt,
  }) => LocalProfile(
    nickname: nickname ?? this.nickname,
    avatarSeed: avatarSeed ?? this.avatarSeed,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    email: email ?? this.email,
    emailBound: emailBound ?? this.emailBound,
    wechatBound: wechatBound ?? this.wechatBound,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class SyncSettings {
  final String
  method; // local, file, webdav, github, gitee（旧 cloud 配置会自动转为 local）
  final String webDavUrl;
  final String webDavUsername;
  final String webDavPassword;
  final String githubToken;
  final String githubOwner;
  final String githubRepo;
  final String githubBranch;
  final String githubPath;
  final String giteeToken;
  final String giteeOwner;
  final String giteeRepo;
  final String giteeBranch;
  final String giteePath;
  final bool autoSyncEnabled;
  final int autoSyncIntervalMinutes;
  final bool syncFullPracticeText;
  final bool syncPrivatePrepData;
  final bool syncAiConfigMetadata;
  final DateTime? lastSyncAt;
  final String lastSyncStatus;

  const SyncSettings({
    this.method = 'local',
    this.webDavUrl = '',
    this.webDavUsername = '',
    this.webDavPassword = '',
    this.githubToken = '',
    this.githubOwner = '',
    this.githubRepo = '',
    this.githubBranch = 'main',
    this.githubPath = 'mianshi-zhilian/sync-state.json',
    this.giteeToken = '',
    this.giteeOwner = '',
    this.giteeRepo = '',
    this.giteeBranch = 'master',
    this.giteePath = 'mianshi-zhilian/sync-state.json',
    this.autoSyncEnabled = true,
    this.autoSyncIntervalMinutes = 5,
    this.syncFullPracticeText = false,
    this.syncPrivatePrepData = false,
    this.syncAiConfigMetadata = true,
    this.lastSyncAt,
    this.lastSyncStatus = 'local_mode',
  });

  factory SyncSettings.fromJson(Map<String, dynamic> json) => SyncSettings(
    method: _normalizeMethod(json['method'] as String? ?? 'local'),
    webDavUrl: json['webDavUrl'] as String? ?? '',
    webDavUsername: json['webDavUsername'] as String? ?? '',
    webDavPassword: json['webDavPassword'] as String? ?? '',
    githubToken: json['githubToken'] as String? ?? '',
    githubOwner: json['githubOwner'] as String? ?? '',
    githubRepo: json['githubRepo'] as String? ?? '',
    githubBranch: json['githubBranch'] as String? ?? 'main',
    githubPath:
        json['githubPath'] as String? ?? 'mianshi-zhilian/sync-state.json',
    giteeToken: json['giteeToken'] as String? ?? '',
    giteeOwner: json['giteeOwner'] as String? ?? '',
    giteeRepo: json['giteeRepo'] as String? ?? '',
    giteeBranch: json['giteeBranch'] as String? ?? 'master',
    giteePath:
        json['giteePath'] as String? ?? 'mianshi-zhilian/sync-state.json',
    autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
    autoSyncIntervalMinutes:
        (json['autoSyncIntervalMinutes'] as num?)?.toInt() ?? 5,
    syncFullPracticeText: json['syncFullPracticeText'] as bool? ?? false,
    syncPrivatePrepData: json['syncPrivatePrepData'] as bool? ?? false,
    syncAiConfigMetadata: json['syncAiConfigMetadata'] as bool? ?? true,
    lastSyncAt: json['lastSyncAt'] != null
        ? DateTime.parse(json['lastSyncAt'] as String)
        : null,
    lastSyncStatus: json['lastSyncStatus'] as String? ?? 'local_mode',
  );

  Map<String, dynamic> toJson() => {
    'method': method,
    'webDavUrl': webDavUrl,
    'webDavUsername': webDavUsername,
    'webDavPassword': webDavPassword,
    'githubToken': githubToken,
    'githubOwner': githubOwner,
    'githubRepo': githubRepo,
    'githubBranch': githubBranch,
    'githubPath': githubPath,
    'giteeToken': giteeToken,
    'giteeOwner': giteeOwner,
    'giteeRepo': giteeRepo,
    'giteeBranch': giteeBranch,
    'giteePath': giteePath,
    'autoSyncEnabled': autoSyncEnabled,
    'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
    'syncFullPracticeText': syncFullPracticeText,
    'syncPrivatePrepData': syncPrivatePrepData,
    'syncAiConfigMetadata': syncAiConfigMetadata,
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'lastSyncStatus': lastSyncStatus,
  };

  bool get isAutomaticMethod =>
      method == 'webdav' || method == 'github' || method == 'gitee';

  static String _normalizeMethod(String method) {
    if (method == 'cloud') return 'local';
    return method;
  }

  SyncSettings copyWith({
    String? method,
    String? webDavUrl,
    String? webDavUsername,
    String? webDavPassword,
    String? githubToken,
    String? githubOwner,
    String? githubRepo,
    String? githubBranch,
    String? githubPath,
    String? giteeToken,
    String? giteeOwner,
    String? giteeRepo,
    String? giteeBranch,
    String? giteePath,
    bool? autoSyncEnabled,
    int? autoSyncIntervalMinutes,
    bool? syncFullPracticeText,
    bool? syncPrivatePrepData,
    bool? syncAiConfigMetadata,
    DateTime? lastSyncAt,
    String? lastSyncStatus,
  }) => SyncSettings(
    method: method ?? this.method,
    webDavUrl: webDavUrl ?? this.webDavUrl,
    webDavUsername: webDavUsername ?? this.webDavUsername,
    webDavPassword: webDavPassword ?? this.webDavPassword,
    githubToken: githubToken ?? this.githubToken,
    githubOwner: githubOwner ?? this.githubOwner,
    githubRepo: githubRepo ?? this.githubRepo,
    githubBranch: githubBranch ?? this.githubBranch,
    githubPath: githubPath ?? this.githubPath,
    giteeToken: giteeToken ?? this.giteeToken,
    giteeOwner: giteeOwner ?? this.giteeOwner,
    giteeRepo: giteeRepo ?? this.giteeRepo,
    giteeBranch: giteeBranch ?? this.giteeBranch,
    giteePath: giteePath ?? this.giteePath,
    autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
    autoSyncIntervalMinutes:
        autoSyncIntervalMinutes ?? this.autoSyncIntervalMinutes,
    syncFullPracticeText: syncFullPracticeText ?? this.syncFullPracticeText,
    syncPrivatePrepData: syncPrivatePrepData ?? this.syncPrivatePrepData,
    syncAiConfigMetadata: syncAiConfigMetadata ?? this.syncAiConfigMetadata,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastSyncStatus: lastSyncStatus ?? this.lastSyncStatus,
  );
}
