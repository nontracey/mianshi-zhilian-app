/// 目标 JD 与能力要求模型（§6.2、§6.7、§6.8）。
library;

import 'common.dart';

/// 目标 JD。用户通过文本、链接、岗位搜索建立目标；可保存多个，首版同时激活一个主目标。
class Goal {
  Goal({
    required this.id,
    required this.profileId,
    required this.title,
    required this.originalText,
    this.originalUrl,
    this.canonicalUrl,
    this.platform,
    this.externalJobId,
    this.company,
    this.location,
    this.salaryText,
    this.description,
    this.postedAt,
    this.expiresAt,
    this.extractionStatus = 'pending',
    required this.contentHash,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
  });

  final GoalId id;
  final ProfileId profileId;
  final String title;
  final String originalText;
  final String? originalUrl;
  final String? canonicalUrl;
  final String? platform;
  final String? externalJobId;
  final String? company;
  final String? location;
  final String? salaryText;
  final String? description;
  final DateTime? postedAt;
  final DateTime? expiresAt;
  final String extractionStatus;
  final String contentHash;
  final bool active;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  Goal copyWith({
    String? title,
    bool? active,
    bool? archived,
    DateTime? updatedAt,
  }) {
    return Goal(
      id: id,
      profileId: profileId,
      title: title ?? this.title,
      originalText: originalText,
      originalUrl: originalUrl,
      canonicalUrl: canonicalUrl,
      platform: platform,
      externalJobId: externalJobId,
      company: company,
      location: location,
      salaryText: salaryText,
      description: description,
      postedAt: postedAt,
      expiresAt: expiresAt,
      extractionStatus: extractionStatus,
      contentHash: contentHash,
      active: active ?? this.active,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'title': title,
    'originalText': originalText,
    'originalUrl': originalUrl,
    'canonicalUrl': canonicalUrl,
    'platform': platform,
    'externalJobId': externalJobId,
    'company': company,
    'location': location,
    'salaryText': salaryText,
    'description': description,
    'postedAt': postedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'extractionStatus': extractionStatus,
    'contentHash': contentHash,
    'active': active,
    'archived': archived,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    title: json['title'] as String,
    originalText: json['originalText'] as String,
    originalUrl: json['originalUrl'] as String?,
    canonicalUrl: json['canonicalUrl'] as String?,
    platform: json['platform'] as String?,
    externalJobId: json['externalJobId'] as String?,
    company: json['company'] as String?,
    location: json['location'] as String?,
    salaryText: json['salaryText'] as String?,
    description: json['description'] as String?,
    postedAt: json['postedAt'] == null
        ? null
        : DateTime.parse(json['postedAt'] as String),
    expiresAt: json['expiresAt'] == null
        ? null
        : DateTime.parse(json['expiresAt'] as String),
    extractionStatus: json['extractionStatus'] as String? ?? 'pending',
    contentHash: json['contentHash'] as String,
    active: json['active'] as bool? ?? false,
    archived: json['archived'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

/// JD 能力要求。模型将 JD 拆成职责/硬要求/加分项/能力点，每项保留原句位置与推断理由。
class GoalRequirement {
  GoalRequirement({
    required this.id,
    required this.goalId,
    required this.profileId,
    required this.type,
    required this.title,
    this.summary,
    this.jdSourceSpan,
    this.importance = Importance.medium,
    this.suggestedDepth,
    this.prerequisiteRequirementIds = const [],
    this.inferred = false,
    this.inferenceRationale,
    this.createdAt,
  });

  final RequirementId id;
  final GoalId goalId;
  final ProfileId profileId;
  final RequirementType type;
  final String title;
  final String? summary;

  /// JD 原句位置（用于保留原句依据）。
  final String? jdSourceSpan;
  final Importance importance;

  /// 建议学习深度：如“基础机制” vs “事务边界、故障与取舍”。
  final String? suggestedDepth;
  final List<RequirementId> prerequisiteRequirementIds;
  final bool inferred;
  final String? inferenceRationale;
  final DateTime? createdAt;

  GoalRequirement copyWith({
    RequirementType? type,
    String? title,
    String? summary,
    String? jdSourceSpan,
    Importance? importance,
    String? suggestedDepth,
    List<RequirementId>? prerequisiteRequirementIds,
    bool? inferred,
    String? inferenceRationale,
  }) => GoalRequirement(
    id: id,
    goalId: goalId,
    profileId: profileId,
    type: type ?? this.type,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    jdSourceSpan: jdSourceSpan ?? this.jdSourceSpan,
    importance: importance ?? this.importance,
    suggestedDepth: suggestedDepth ?? this.suggestedDepth,
    prerequisiteRequirementIds:
        prerequisiteRequirementIds ?? this.prerequisiteRequirementIds,
    inferred: inferred ?? this.inferred,
    inferenceRationale: inferenceRationale ?? this.inferenceRationale,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'goalId': goalId,
    'profileId': profileId,
    'type': type.name,
    'title': title,
    'summary': summary,
    'jdSourceSpan': jdSourceSpan,
    'importance': importance.name,
    'suggestedDepth': suggestedDepth,
    'prerequisiteRequirementIds': prerequisiteRequirementIds,
    'inferred': inferred,
    'inferenceRationale': inferenceRationale,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory GoalRequirement.fromJson(Map<String, dynamic> json) =>
      GoalRequirement(
        id: json['id'] as String,
        goalId: json['goalId'] as String,
        profileId: json['profileId'] as String,
        type: RequirementType.values.firstWhere((e) => e.name == json['type']),
        title: json['title'] as String,
        summary: json['summary'] as String?,
        jdSourceSpan: json['jdSourceSpan'] as String?,
        importance: Importance.values.firstWhere(
          (e) => e.name == json['importance'],
        ),
        suggestedDepth: json['suggestedDepth'] as String?,
        prerequisiteRequirementIds:
            (json['prerequisiteRequirementIds'] as List<dynamic>? ?? [])
                .map((e) => e as String)
                .toList(),
        inferred: json['inferred'] as bool? ?? false,
        inferenceRationale: json['inferenceRationale'] as String?,
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.parse(json['createdAt'] as String),
      );
}

/// JD 版本修订（§6.6）。修改 JD 生成能力差异，只补充或降级相关要求，已有知识与原答保留。
class GoalRevision {
  GoalRevision({
    required this.id,
    required this.goalId,
    required this.profileId,
    required this.revisionNumber,
    required this.contentHash,
    required this.createdAt,
    this.note,
  });

  final String id;
  final GoalId goalId;
  final ProfileId profileId;
  final int revisionNumber;
  final String contentHash;
  final DateTime createdAt;
  final String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'goalId': goalId,
    'profileId': profileId,
    'revisionNumber': revisionNumber,
    'contentHash': contentHash,
    'createdAt': createdAt.toIso8601String(),
    'note': note,
  };

  factory GoalRevision.fromJson(Map<String, dynamic> json) => GoalRevision(
    id: json['id'] as String,
    goalId: json['goalId'] as String,
    profileId: json['profileId'] as String,
    revisionNumber: json['revisionNumber'] as int,
    contentHash: json['contentHash'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    note: json['note'] as String?,
  );
}
