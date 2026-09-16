/// 知识项与 JD 关联（§6.3、§6.4、§6.8）。
library;

import 'common.dart';

/// 知识项。稳定 UUID 由 App 分配；同名不自动合并（不同深度/版本/项目事实不合并）。
class KnowledgeItem {
  KnowledgeItem({
    required this.id,
    required this.profileId,
    required this.title,
    this.aliases = const [],
    this.version = 1,
    this.contentStatus = 'ai-draft-unverified',
    required this.createdAt,
    required this.updatedAt,
  });

  final KnowledgeItemId id;
  final ProfileId profileId;
  final String title;
  final List<String> aliases;

  /// 来源状态：'ai-draft-unverified'（AI 生成待核验）/ 'verified' / 'stale'。
  final String contentStatus;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'title': title,
    'aliases': aliases,
    'contentStatus': contentStatus,
    'version': version,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory KnowledgeItem.fromJson(Map<String, dynamic> json) => KnowledgeItem(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    title: json['title'] as String,
    aliases: (json['aliases'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList(),
    contentStatus: json['contentStatus'] as String? ?? 'ai-draft-unverified',
    version: json['version'] as int? ?? 1,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  KnowledgeItem copyWith({
    String? contentStatus,
    int? version,
    DateTime? updatedAt,
  }) => KnowledgeItem(
    id: id,
    profileId: profileId,
    title: title,
    aliases: aliases,
    contentStatus: contentStatus ?? this.contentStatus,
    version: version ?? this.version,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 知识项与 JD 的关联（§6.8 删除依赖检查的核心）。
class GoalKnowledgeLink {
  GoalKnowledgeLink({
    required this.goalId,
    required this.knowledgeItemId,
    required this.profileId,
    this.requirementIds = const [],
    required this.createdAt,
  });

  final GoalId goalId;
  final KnowledgeItemId knowledgeItemId;
  final ProfileId profileId;

  /// 该知识项服务的具体 JD 要求 ID（可多个）。
  final List<RequirementId> requirementIds;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'goalId': goalId,
    'knowledgeItemId': knowledgeItemId,
    'profileId': profileId,
    'requirementIds': requirementIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory GoalKnowledgeLink.fromJson(Map<String, dynamic> json) =>
      GoalKnowledgeLink(
        goalId: json['goalId'] as String,
        knowledgeItemId: json['knowledgeItemId'] as String,
        profileId: json['profileId'] as String,
        requirementIds: (json['requirementIds'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
