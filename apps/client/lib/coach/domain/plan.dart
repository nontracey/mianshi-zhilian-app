/// 每日计划与计划项（§9.6）。
library;

import 'common.dart';

/// 计划项类型（对应轻量工作流的四种卡片，§9.7）。
enum PlanItemType {
  learnKnowledge,
  reviewLearned,
  projectTraining,
  mockInterview,
}

/// 卡片类型的默认时长（分钟）。
///
/// 编译器、今日计划生成与训练安排 UI 必须共用这一份；此前 (8, 6, 10, 15)
/// 在四处各写了一遍，改一处忘三处是必然。
extension PlanItemTypeDefaults on PlanItemType {
  int get defaultMinutes {
    switch (this) {
      case PlanItemType.learnKnowledge:
        return 8;
      case PlanItemType.reviewLearned:
        return 6;
      case PlanItemType.projectTraining:
        return 10;
      case PlanItemType.mockInterview:
        return 15;
    }
  }
}

/// 计划项。每个卡片的执行事实（证据、回测、完成）仍落在 session/plan 表中。
class PlanItem {
  PlanItem({
    required this.id,
    required this.type,
    required this.title,
    this.knowledgeItemId,
    this.reviewPointIds = const [],
    this.projectId,
    this.goalId,
    this.resumeId,
    this.estimatedMinutes = 8,
    this.manualOverride = false,
    this.completed = false,
    this.maxQuestions,
    this.projectMode = 'assess',
    this.workflowCardId,
  });

  final String id;
  final int? maxQuestions;
  final String projectMode;
  final String? workflowCardId;
  final PlanItemType type;
  final String title;
  final KnowledgeItemId? knowledgeItemId;
  final List<ReviewPointId> reviewPointIds;
  final ProjectId? projectId;
  final GoalId? goalId;
  final ResumeId? resumeId;
  final int estimatedMinutes;
  final bool manualOverride;

  /// 完成一张卡片不等于内容已经掌握（§9.7）。
  final bool completed;

  PlanItem copyWith({
    PlanItemType? type,
    String? title,
    KnowledgeItemId? knowledgeItemId,
    List<ReviewPointId>? reviewPointIds,
    ProjectId? projectId,
    GoalId? goalId,
    ResumeId? resumeId,
    int? estimatedMinutes,
    bool? manualOverride,
    bool? completed,
    int? maxQuestions,
    String? projectMode,
    String? workflowCardId,
  }) {
    return PlanItem(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      knowledgeItemId: knowledgeItemId ?? this.knowledgeItemId,
      reviewPointIds: reviewPointIds ?? this.reviewPointIds,
      projectId: projectId ?? this.projectId,
      goalId: goalId ?? this.goalId,
      resumeId: resumeId ?? this.resumeId,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      manualOverride: manualOverride ?? this.manualOverride,
      completed: completed ?? this.completed,
      maxQuestions: maxQuestions ?? this.maxQuestions,
      projectMode: projectMode ?? this.projectMode,
      workflowCardId: workflowCardId ?? this.workflowCardId,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'knowledgeItemId': knowledgeItemId,
    'reviewPointIds': reviewPointIds,
    'projectId': projectId,
    'goalId': goalId,
    'resumeId': resumeId,
    'estimatedMinutes': estimatedMinutes,
    'manualOverride': manualOverride,
    'completed': completed,
    'maxQuestions': maxQuestions,
    'projectMode': projectMode,
    'workflowCardId': workflowCardId,
  };

  factory PlanItem.fromJson(Map<String, Object?> json) => PlanItem(
    id: json['id'] as String,
    type: PlanItemType.values.byName(json['type'] as String),
    title: json['title'] as String,
    knowledgeItemId: json['knowledgeItemId'] as String?,
    reviewPointIds: (json['reviewPointIds'] as List? ?? const [])
        .map((item) => item as String)
        .toList(),
    projectId: json['projectId'] as String?,
    goalId: json['goalId'] as String?,
    resumeId: json['resumeId'] as String?,
    estimatedMinutes: json['estimatedMinutes'] as int? ?? 8,
    manualOverride: json['manualOverride'] as bool? ?? false,
    completed: json['completed'] as bool? ?? false,
    maxQuestions: json['maxQuestions'] as int?,
    projectMode: json['projectMode'] as String? ?? 'assess',
    workflowCardId: json['workflowCardId'] as String?,
  );
}

/// 每日基础计划。首次开始训练时冻结：保存 ID、考点范围、预计时长和分母（§9.6）。
class DailyPlan {
  DailyPlan({
    required this.id,
    required this.profileId,
    required this.date,
    required this.timezone,
    required this.planItems,
    required this.baseMinutes,
    required this.version,
    this.frozenAt,
    this.revisionNote,
    this.isExtra = false,
  });

  final DailyPlanId id;
  final ProfileId profileId;

  /// 本地自然日（YYYY-MM-DD）。
  final String date;
  final String timezone;
  final List<PlanItem> planItems;

  /// 基础时长预算（冻结值，分母）。
  final int baseMinutes;
  final int version;

  /// 冻结时间戳；一旦设置，基础计划不可被静默改写。
  final DateTime? frozenAt;
  final String? revisionNote;

  /// 是否为基础结束后追加的额外计划（不影响原基础分母，§9.6）。
  final bool isExtra;

  int get completedCount => planItems.where((e) => e.completed).length;

  /// 完成的分母：基础计划用冻结时的人数；额外项不计入（§9.6）。
  int get denominator => planItems.length;

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'date': date,
    'timezone': timezone,
    'planItems': planItems.map((item) => item.toJson()).toList(),
    'baseMinutes': baseMinutes,
    'version': version,
    'frozenAt': frozenAt?.toIso8601String(),
    'revisionNote': revisionNote,
    'isExtra': isExtra,
  };

  factory DailyPlan.fromJson(Map<String, Object?> json) => DailyPlan(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    date: json['date'] as String,
    timezone: json['timezone'] as String,
    planItems: (json['planItems'] as List? ?? const [])
        .map(
          (item) => PlanItem.fromJson(
            (item as Map).map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(),
    baseMinutes: json['baseMinutes'] as int,
    version: json['version'] as int,
    frozenAt: json['frozenAt'] == null
        ? null
        : DateTime.parse(json['frozenAt'] as String),
    revisionNote: json['revisionNote'] as String?,
    isExtra: json['isExtra'] as bool? ?? false,
  );
}
