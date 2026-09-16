/// 简历、项目主张与 JD 关联（§6.9）。
library;

import 'common.dart';

/// 简历版本。支持一个档案多份简历，JD 可关联默认简历版本。
class Resume {
  Resume({
    required this.id,
    required this.profileId,
    required this.versionLabel,
    required this.originalText,
    this.fileName,
    this.parsedAt,
    required this.createdAt,
    this.revision = 1,
  });

  final ResumeId id;
  final ProfileId profileId;
  final String versionLabel;
  final String originalText;
  final String? fileName;
  final DateTime? parsedAt;
  final DateTime createdAt;

  /// 整数修订号。会话固定 `resumeId + revision`，之后改简历不会改写历史原答。
  final int revision;

  Resume copyWith({
    String? versionLabel,
    String? originalText,
    String? fileName,
    DateTime? parsedAt,
    int? revision,
  }) => Resume(
    id: id,
    profileId: profileId,
    versionLabel: versionLabel ?? this.versionLabel,
    originalText: originalText ?? this.originalText,
    fileName: fileName ?? this.fileName,
    parsedAt: parsedAt ?? this.parsedAt,
    createdAt: createdAt,
    revision: revision ?? this.revision,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'versionLabel': versionLabel,
    'originalText': originalText,
    'fileName': fileName,
    'parsedAt': parsedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'revision': revision,
  };

  factory Resume.fromJson(Map<String, dynamic> json) => Resume(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    versionLabel: json['versionLabel'] as String,
    originalText: json['originalText'] as String,
    fileName: json['fileName'] as String?,
    parsedAt: json['parsedAt'] == null
        ? null
        : DateTime.parse(json['parsedAt'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    revision: json['revision'] as int? ?? 1,
  );
}

/// 简历项目（本人经历，不是 JD 要求）。
class Project {
  Project({
    required this.id,
    required this.profileId,
    required this.resumeId,
    required this.name,
    this.originalSpan,
    this.goal,
    this.responsibilities,
    this.techStack,
    this.metrics,
    this.timeRange,
  });

  final ProjectId id;
  final ProfileId profileId;
  final ResumeId resumeId;
  final String name;

  /// 原文对照位置（解析时记录，便于用户校对）。
  final String? originalSpan;
  final String? goal;
  final String? responsibilities;
  final String? techStack;
  final String? metrics;
  final String? timeRange;

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'resumeId': resumeId,
    'name': name,
    'originalSpan': originalSpan,
    'goal': goal,
    'responsibilities': responsibilities,
    'techStack': techStack,
    'metrics': metrics,
    'timeRange': timeRange,
  };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    resumeId: json['resumeId'] as String,
    name: json['name'] as String,
    originalSpan: json['originalSpan'] as String?,
    goal: json['goal'] as String?,
    responsibilities: json['responsibilities'] as String?,
    techStack: json['techStack'] as String?,
    metrics: json['metrics'] as String?,
    timeRange: json['timeRange'] as String?,
  );
}

/// 简历主张草稿（§6.9）。提取置信度不等于经历可信度；信息未写明留待确认。
class ResumeClaim {
  ResumeClaim({
    required this.id,
    required this.profileId,
    required this.resumeId,
    this.projectId,
    required this.statement,
    this.originalSpan,
    this.status = ClaimStatus.pending,
    this.confidence,
  });

  final ClaimId id;
  final ProfileId profileId;
  final ResumeId resumeId;
  final ProjectId? projectId;
  final String statement;
  final String? originalSpan;

  /// pending / confirmed / disputed。
  final ClaimStatus status;

  /// 解析置信度（0-1），不表示经历可信度。
  final double? confidence;

  bool get isConfirmed => status == ClaimStatus.confirmed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'resumeId': resumeId,
    'projectId': projectId,
    'statement': statement,
    'originalSpan': originalSpan,
    'status': status.name,
    'confidence': confidence,
  };

  factory ResumeClaim.fromJson(Map<String, dynamic> json) => ResumeClaim(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    resumeId: json['resumeId'] as String,
    projectId: json['projectId'] as String?,
    statement: json['statement'] as String,
    originalSpan: json['originalSpan'] as String?,
    status: ClaimStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => ClaimStatus.pending,
    ),
    confidence: (json['confidence'] as num?)?.toDouble(),
  );
}

/// 用户选定简历与 JD 的关联。
class GoalResumeLink {
  GoalResumeLink({
    required this.goalId,
    required this.resumeId,
    required this.profileId,
    this.isDefault = false,
    required this.createdAt,
  });

  final GoalId goalId;
  final ResumeId resumeId;
  final ProfileId profileId;
  final bool isDefault;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'goalId': goalId,
    'resumeId': resumeId,
    'profileId': profileId,
    'isDefault': isDefault,
    'createdAt': createdAt.toIso8601String(),
  };

  factory GoalResumeLink.fromJson(Map<String, dynamic> json) => GoalResumeLink(
    goalId: json['goalId'] as String,
    resumeId: json['resumeId'] as String,
    profileId: json['profileId'] as String,
    isDefault: json['isDefault'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// 主张对 JD 要求的映射与依据（§6.9 三类出题依据）。
class ClaimRequirementLink {
  ClaimRequirementLink({
    required this.claimId,
    required this.requirementId,
    required this.profileId,
    required this.mappingType,
    this.rationale,
  });

  final ClaimId claimId;
  final RequirementId requirementId;
  final ProfileId profileId;

  /// 'jdAndResume'（JD×简历）/ 'jdOnly'（JD必需但简历无覆盖）/ 'resumeOnly'（简历强主张）。
  final String mappingType;
  final String? rationale;

  Map<String, dynamic> toJson() => {
    'claimId': claimId,
    'requirementId': requirementId,
    'profileId': profileId,
    'mappingType': mappingType,
    'rationale': rationale,
  };

  factory ClaimRequirementLink.fromJson(Map<String, dynamic> json) =>
      ClaimRequirementLink(
        claimId: json['claimId'] as String,
        requirementId: json['requirementId'] as String,
        profileId: json['profileId'] as String,
        mappingType: json['mappingType'] as String,
        rationale: json['rationale'] as String?,
      );
}
