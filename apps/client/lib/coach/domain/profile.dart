/// 本地档案（§9.2 profiles）。单用户首版也保留档案边界，避免切换档案时混淆经历或成绩。
library;

import 'common.dart';

/// 本地档案。每个用户/设备档案相互独立，个人事实与作答不跨档案复用。
class Profile {
  Profile({
    required this.id,
    this.displayName,
    this.dailyMinutesBudget = 25,
    this.baseLevel,
    this.teachingPreference,
    this.defaultWorkflowTemplateId,
    required this.createdAt,
    required this.updatedAt,
  });

  final ProfileId id;
  final String? displayName;

  /// 每天可用时间预算（分钟），作为计划生成依据（§9.6）。
  final int dailyMinutesBudget;

  /// 基础水平（如“初级/中级/高级”），仅作产品默认，不硬编码个人薪资/城市。
  final String? baseLevel;

  /// 教学风格/例子偏好（用户可改，不能覆盖数据真实性规则）。
  final String? teachingPreference;

  /// 今后默认使用的训练安排模板 id（§9.7「今后默认」）。`null` 表示未设置。
  final String? defaultWorkflowTemplateId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile copyWith({
    String? displayName,
    int? dailyMinutesBudget,
    String? baseLevel,
    String? teachingPreference,
    String? defaultWorkflowTemplateId,
    bool clearDefaultWorkflowTemplateId = false,
    DateTime? updatedAt,
  }) => Profile(
    id: id,
    displayName: displayName ?? this.displayName,
    dailyMinutesBudget: dailyMinutesBudget ?? this.dailyMinutesBudget,
    baseLevel: baseLevel ?? this.baseLevel,
    teachingPreference: teachingPreference ?? this.teachingPreference,
    defaultWorkflowTemplateId: clearDefaultWorkflowTemplateId
        ? null
        : (defaultWorkflowTemplateId ?? this.defaultWorkflowTemplateId),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'dailyMinutesBudget': dailyMinutesBudget,
    'baseLevel': baseLevel,
    'teachingPreference': teachingPreference,
    'defaultWorkflowTemplateId': defaultWorkflowTemplateId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    displayName: json['displayName'] as String?,
    dailyMinutesBudget: json['dailyMinutesBudget'] as int? ?? 25,
    baseLevel: json['baseLevel'] as String?,
    teachingPreference: json['teachingPreference'] as String?,
    defaultWorkflowTemplateId: json['defaultWorkflowTemplateId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
