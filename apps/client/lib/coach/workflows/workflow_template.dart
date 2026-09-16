/// 训练安排（轻量工作流）模板（§9.7）。
///
/// 产品名是“训练安排”：默认由教练自动安排，需要灵活度的人可以选模板、增删排序
/// 训练卡片、调整每张卡的范围与时间。它是**计划的生成方式**，与每日计划、会话和
/// 成绩共用数据，不另造一套任务看板。
///
/// 首版只有四种可编辑卡片（对应 [PlanItemType]），三类受限条件；模板是版本化
/// JSON，只含数据，**不含可执行脚本**，不写死岗位、公司、技能栈、日历日期或个人
/// 完成度。
///
/// 本文件是纯 Dart，不依赖 Flutter。
library;

import '../domain/common.dart';
import '../domain/plan.dart';

/// 扩展记录里的深不可变 Map 不是 `Map<String, dynamic>`，统一在此归一化。
Map<String, dynamic> _jsonMap(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return value.map((k, v) => MapEntry(k.toString(), v));
}

List<Map<String, dynamic>> _jsonMapList(Object? value) =>
    ((value as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

/// 单个训练安排最多 6 张卡片，避免无限任务链。
const int maxWorkflowCards = 6;

/// 卡片模板版本。结构变化时递增。
const int workflowTemplateSchemaVersion = 1;

/// 项目卡片的两种明确动作（“梳理”与“评估”必须分开）。
enum ProjectTrainingMode {
  /// 梳理这个项目：教学模式，说明已知调用与数据流，缺事实时只问一个必要问题。
  explain,

  /// 针对这个项目提问：评估/项目模拟，一次一问。
  assess,
}

/// 三类受限条件。分支不能循环，也不能递归加新流程。
enum WorkflowCondition {
  /// 无到期项则跳过回测。
  skipReviewWhenNothingDue,

  /// 同一考点连续薄弱则补讲一次（不无限追问）。
  reteachOnceWhenWeak,

  /// 时间不足则询问延长或顺延未开始卡片。
  askExtendWhenTimeShort,
}

/// 一张可编辑的训练卡片。
class WorkflowCard {
  const WorkflowCard({
    required this.id,
    required this.type,
    this.estimatedMinutes,
    this.maxQuestions,
    this.knowledgeItemId,
    this.projectId,
    this.goalId,
    this.resumeId,
    this.projectMode,
    this.condition,
  });

  final String id;
  final PlanItemType type;
  final int? estimatedMinutes;
  final int? maxQuestions;

  /// null 表示按当前目标自动选择。“下一到期项”不是永远锁定一个知识 ID。
  final KnowledgeItemId? knowledgeItemId;
  final ProjectId? projectId;
  final GoalId? goalId;
  final ResumeId? resumeId;

  /// 仅 [PlanItemType.projectTraining] 使用。
  final ProjectTrainingMode? projectMode;

  final WorkflowCondition? condition;

  WorkflowCard copyWith({
    String? id,
    PlanItemType? type,
    int? estimatedMinutes,
    int? maxQuestions,
    KnowledgeItemId? knowledgeItemId,
    ProjectId? projectId,
    GoalId? goalId,
    ResumeId? resumeId,
    ProjectTrainingMode? projectMode,
    WorkflowCondition? condition,
    bool clearKnowledgeItemId = false,
  }) {
    return WorkflowCard(
      id: id ?? this.id,
      type: type ?? this.type,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      maxQuestions: maxQuestions ?? this.maxQuestions,
      knowledgeItemId: clearKnowledgeItemId
          ? null
          : (knowledgeItemId ?? this.knowledgeItemId),
      projectId: projectId ?? this.projectId,
      goalId: goalId ?? this.goalId,
      resumeId: resumeId ?? this.resumeId,
      projectMode: projectMode ?? this.projectMode,
      condition: condition ?? this.condition,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    if (estimatedMinutes != null) 'estimatedMinutes': estimatedMinutes,
    if (maxQuestions != null) 'maxQuestions': maxQuestions,
    if (knowledgeItemId != null) 'knowledgeItemId': knowledgeItemId,
    if (projectId != null) 'projectId': projectId,
    if (goalId != null) 'goalId': goalId,
    if (resumeId != null) 'resumeId': resumeId,
    if (projectMode != null) 'projectMode': projectMode!.name,
    if (condition != null) 'condition': condition!.name,
  };

  factory WorkflowCard.fromJson(Map<String, dynamic> json) => WorkflowCard(
    id: json['id'] as String,
    type: PlanItemType.values.firstWhere((e) => e.name == json['type']),
    estimatedMinutes: json['estimatedMinutes'] as int?,
    maxQuestions: json['maxQuestions'] as int?,
    knowledgeItemId: json['knowledgeItemId'] as String?,
    projectId: json['projectId'] as String?,
    goalId: json['goalId'] as String?,
    resumeId: json['resumeId'] as String?,
    projectMode: json['projectMode'] == null
        ? null
        : ProjectTrainingMode.values.firstWhere(
            (e) => e.name == json['projectMode'],
          ),
    condition: json['condition'] == null
        ? null
        : WorkflowCondition.values.firstWhere(
            (e) => e.name == json['condition'],
          ),
  );
}

/// 模板作用范围：某个 JD + 某份简历 + 若干项目。
class WorkflowScope {
  const WorkflowScope({this.goalId, this.resumeId, this.projectIds = const []});

  final GoalId? goalId;
  final ResumeId? resumeId;
  final List<ProjectId> projectIds;

  bool get isEmpty => goalId == null && resumeId == null && projectIds.isEmpty;

  Map<String, dynamic> toJson() => {
    if (goalId != null) 'goalId': goalId,
    if (resumeId != null) 'resumeId': resumeId,
    if (projectIds.isNotEmpty) 'projectIds': projectIds,
  };

  factory WorkflowScope.fromJson(Map<String, dynamic> json) => WorkflowScope(
    goalId: json['goalId'] as String?,
    resumeId: json['resumeId'] as String?,
    projectIds: ((json['projectIds'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
  );
}

/// 版本化训练安排模板。
class WorkflowTemplate {
  const WorkflowTemplate({
    required this.id,
    this.nameKey,
    this.name,
    required this.cards,
    this.schemaVersion = workflowTemplateSchemaVersion,
    this.version = 1,
    this.scope = const WorkflowScope(),
    this.isBuiltIn = false,
    this.descriptionKey,
  });

  final String id;

  /// 名称 l10n key（内置模板）。模板自身不持有内置文案。
  final String? nameKey;

  /// 用户命名（另存的模板）。这是用户数据，不是 UI 文案；与 [nameKey] 互斥使用：
  /// UI 显示优先取 [nameKey] 翻译，没有则直接显示 [name]。
  final String? name;

  final String? descriptionKey;

  /// 结构版本（数据格式），与 [version]（用户复制/改名后的修订号）不同。
  final int schemaVersion;
  final int version;
  final List<WorkflowCard> cards;
  final WorkflowScope scope;

  /// 内置模板不可原地修改，用户复制后另存。
  final bool isBuiltIn;

  bool get exceedsCardLimit => cards.length > maxWorkflowCards;

  int get estimatedMinutes =>
      cards.fold(0, (sum, card) => sum + (card.estimatedMinutes ?? 0));

  WorkflowTemplate copyWith({
    String? id,
    String? nameKey,
    String? name,
    String? descriptionKey,
    int? version,
    List<WorkflowCard>? cards,
    WorkflowScope? scope,
    bool clearName = false,
  }) {
    return WorkflowTemplate(
      id: id ?? this.id,
      nameKey: nameKey ?? this.nameKey,
      name: clearName ? null : (name ?? this.name),
      descriptionKey: descriptionKey ?? this.descriptionKey,
      schemaVersion: schemaVersion,
      version: version ?? this.version,
      cards: cards ?? this.cards,
      scope: scope ?? this.scope,
      isBuiltIn: isBuiltIn,
    );
  }

  /// 复制成用户自己的模板（内置模板不原地修改）。
  WorkflowTemplate fork({
    required String newId,
    String? newNameKey,
    String? newName,
    String? newDescriptionKey,
  }) {
    return WorkflowTemplate(
      id: newId,
      nameKey: newNameKey,
      name: newName,
      descriptionKey: newDescriptionKey,
      version: version,
      cards: cards,
      scope: scope,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    if (nameKey != null) 'nameKey': nameKey,
    if (name != null) 'name': name,
    if (descriptionKey != null) 'descriptionKey': descriptionKey,
    'version': version,
    'isBuiltIn': isBuiltIn,
    'scope': scope.toJson(),
    'cards': cards.map((c) => c.toJson()).toList(),
  };

  factory WorkflowTemplate.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 0;
    if (schemaVersion > workflowTemplateSchemaVersion) {
      throw FormatException(
        'unsupported workflow template schema: $schemaVersion',
      );
    }
    return WorkflowTemplate(
      id: json['id'] as String,
      nameKey: json['nameKey'] as String?,
      name: json['name'] as String?,
      descriptionKey: json['descriptionKey'] as String?,
      schemaVersion: schemaVersion,
      version: json['version'] as int? ?? 1,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      scope: WorkflowScope.fromJson(_jsonMap(json['scope'])),
      cards: _jsonMapList(json['cards']).map(WorkflowCard.fromJson).toList(),
    );
  }
}

/// 三份中性内置模板。不写死岗位、公司、技能栈、日历日期或个人完成度。
abstract final class BuiltInWorkflows {
  static const String dailyProgressId = 'builtin.daily_progress';
  static const String projectDeepDiveId = 'builtin.project_deep_dive';
  static const String beforeInterviewId = 'builtin.before_interview';

  static const String dailyProgressNameKey = 'coach_workflow_tpl_daily';
  static const String dailyProgressDescKey = 'coach_workflow_tpl_daily_desc';
  static const String projectDeepDiveNameKey = 'coach_workflow_tpl_project';
  static const String projectDeepDiveDescKey =
      'coach_workflow_tpl_project_desc';
  static const String beforeInterviewNameKey = 'coach_workflow_tpl_interview';
  static const String beforeInterviewDescKey =
      'coach_workflow_tpl_interview_desc';

  /// 日常推进：到期回测 → 学一个相关知识点。
  ///
  /// 收尾与计划对账由系统执行，不是用户可删除的卡片。
  static const WorkflowTemplate dailyProgress = WorkflowTemplate(
    id: dailyProgressId,
    nameKey: dailyProgressNameKey,
    descriptionKey: dailyProgressDescKey,
    isBuiltIn: true,
    cards: [
      WorkflowCard(
        id: 'daily.review',
        type: PlanItemType.reviewLearned,
        maxQuestions: 2,
        estimatedMinutes: 6,
        condition: WorkflowCondition.skipReviewWhenNothingDue,
      ),
      WorkflowCard(
        id: 'daily.learn',
        type: PlanItemType.learnKnowledge,
        estimatedMinutes: 8,
      ),
    ],
  );

  /// 项目深挖：梳理本人项目 → 针对一条主张提问 → 必要时补讲关联机制。
  static const WorkflowTemplate projectDeepDive = WorkflowTemplate(
    id: projectDeepDiveId,
    nameKey: projectDeepDiveNameKey,
    descriptionKey: projectDeepDiveDescKey,
    isBuiltIn: true,
    cards: [
      WorkflowCard(
        id: 'project.explain',
        type: PlanItemType.projectTraining,
        projectMode: ProjectTrainingMode.explain,
        estimatedMinutes: 8,
      ),
      WorkflowCard(
        id: 'project.assess',
        type: PlanItemType.projectTraining,
        projectMode: ProjectTrainingMode.assess,
        estimatedMinutes: 10,
      ),
      WorkflowCard(
        id: 'project.reteach',
        type: PlanItemType.learnKnowledge,
        estimatedMinutes: 8,
        condition: WorkflowCondition.reteachOnceWhenWeak,
      ),
    ],
  );

  /// 面试前准备：目标 JD 的关键到期项 → 一场定向模拟 → 少量后续补强。
  static const WorkflowTemplate beforeInterview = WorkflowTemplate(
    id: beforeInterviewId,
    nameKey: beforeInterviewNameKey,
    descriptionKey: beforeInterviewDescKey,
    isBuiltIn: true,
    cards: [
      WorkflowCard(
        id: 'pre.review',
        type: PlanItemType.reviewLearned,
        maxQuestions: 2,
        estimatedMinutes: 6,
        condition: WorkflowCondition.skipReviewWhenNothingDue,
      ),
      WorkflowCard(
        id: 'pre.mock',
        type: PlanItemType.mockInterview,
        estimatedMinutes: 15,
        condition: WorkflowCondition.askExtendWhenTimeShort,
      ),
      WorkflowCard(
        id: 'pre.followup',
        type: PlanItemType.learnKnowledge,
        estimatedMinutes: 8,
      ),
    ],
  );

  static const List<WorkflowTemplate> all = [
    dailyProgress,
    projectDeepDive,
    beforeInterview,
  ];
}
