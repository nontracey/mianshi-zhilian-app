/// 资料来源、分块与入库任务模型（§6.3、§6.4、§9.2）。
library;

import '../domain/common.dart';

/// 来源类型。
enum SourceType { markdown, txt, pdf, docx, web, paste }

/// 入库/解析状态（§6.4）。
enum IngestionStatus { pending, running, ready, failed }

/// 一条资料来源。保存原文快照、类型、位置、内容哈希与状态（§6.4）。
class Source {
  Source({
    required this.id,
    required this.profileId,
    required this.title,
    required this.type,
    required this.contentHash,
    this.status = IngestionStatus.pending,
    this.url,
    this.revision = 1,
    this.content,
    this.fetchedAt,
    this.createdAt,
  });

  final SourceId id;
  final ProfileId profileId;
  final String title;
  final SourceType type;

  /// 内容哈希，用于去重（同 hash 不重复切块）。
  final String contentHash;
  final IngestionStatus status;
  final String? url;

  /// 正文快照版本；正文哈希变化产生新 revision（§6.6）。
  final int revision;

  /// 原文快照（RAG 可直接检索；向量未就绪也能教学）。
  final String? content;
  final DateTime? fetchedAt;
  final DateTime? createdAt;

  Source copyWith({IngestionStatus? status, int? revision, String? content}) =>
      Source(
        id: id,
        profileId: profileId,
        title: title,
        type: type,
        contentHash: contentHash,
        status: status ?? this.status,
        url: url,
        revision: revision ?? this.revision,
        content: content ?? this.content,
        fetchedAt: fetchedAt,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'title': title,
    'type': type.name,
    'contentHash': contentHash,
    'status': status.name,
    'url': url,
    'revision': revision,
    'content': content,
    'fetchedAt': fetchedAt?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
  };

  factory Source.fromJson(Map<String, dynamic> json) => Source(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    title: json['title'] as String,
    type: SourceType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => SourceType.txt,
    ),
    contentHash: json['contentHash'] as String,
    status: IngestionStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => IngestionStatus.pending,
    ),
    url: json['url'] as String?,
    revision: json['revision'] as int? ?? 1,
    content: json['content'] as String?,
    fetchedAt: json['fetchedAt'] == null
        ? null
        : DateTime.parse(json['fetchedAt'] as String),
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.parse(json['createdAt'] as String),
  );
}

/// 资料分块。每块保存来源、位置、哈希、可选向量 profile（§6.4、§6.5）。
class SourceChunk {
  SourceChunk({
    required this.id,
    required this.sourceId,
    required this.sourceRevision,
    required this.index,
    required this.content,
    this.titlePath,
    this.sourceLocation,
    this.hash,
    this.knowledgeItemId,
    this.embeddingProfileId,
  });

  final ChunkId id;
  final SourceId sourceId;
  final int sourceRevision;
  final int index;
  final String content;

  /// 标题路径（例如 "3. 事务隔离 / 3.1 隔离级别"），用于展示出处。
  final String? titlePath;
  final String? sourceLocation;
  final String? hash;

  /// 关联的知识点（定向检索用；可为空表示通用资料）。
  final KnowledgeItemId? knowledgeItemId;
  final String? embeddingProfileId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'sourceRevision': sourceRevision,
    'index': index,
    'content': content,
    'titlePath': titlePath,
    'sourceLocation': sourceLocation,
    'hash': hash,
    'knowledgeItemId': knowledgeItemId,
    'embeddingProfileId': embeddingProfileId,
  };

  factory SourceChunk.fromJson(Map<String, dynamic> json) => SourceChunk(
    id: json['id'] as String,
    sourceId: json['sourceId'] as String,
    sourceRevision: json['sourceRevision'] as int,
    index: json['chunkIndex'] as int? ?? json['index'] as int,
    content: json['content'] as String,
    titlePath: json['titlePath'] as String?,
    sourceLocation: json['sourceLocation'] as String?,
    hash: json['hash'] as String?,
    knowledgeItemId: json['knowledgeItemId'] as String?,
    embeddingProfileId: json['embeddingProfileId'] as String?,
  );
}

/// 入库任务（§6.4、§9.2）。失败可重试；正文已可检索而向量未完成仍可教学。
class IngestionJob {
  IngestionJob({
    required this.id,
    required this.profileId,
    required this.sourceId,
    this.status = IngestionStatus.pending,
    this.error,
    required this.createdAt,
    this.completedAt,
  });

  final String id;
  final ProfileId profileId;
  final SourceId sourceId;
  final IngestionStatus status;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'sourceId': sourceId,
    'status': status.name,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory IngestionJob.fromJson(Map<String, dynamic> json) => IngestionJob(
    id: json['id'] as String,
    profileId: json['profileId'] as String,
    sourceId: json['sourceId'] as String,
    status: IngestionStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => IngestionStatus.pending,
    ),
    error: json['error'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    completedAt: json['completedAt'] == null
        ? null
        : DateTime.parse(json['completedAt'] as String),
  );
}

/// FNV-1a 32 位内容哈希（纯 Dart，无外部依赖）。用于去重与变更检测。
/// 非加密哈希，碰撞风险可接受；精确去重可辅以原文比对。
String computeContentHash(String content) {
  var hash = 0x811c9dc5;
  for (final codeUnit in content.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
