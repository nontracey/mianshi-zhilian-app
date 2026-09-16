/// Profile-scoped, versioned JSON records for coach features.
///
/// This is deliberately a small allow-list instead of a generic preferences
/// bucket. It gives workflow, migration and metadata features one durable
/// contract while keeping credentials out of the coach database and exports.
library;

import '../domain/common.dart';

enum CoachExtensionKind {
  runtimeLease,
  modelTurn,
  workflowTemplate,
  workflowRun,
  planAdjustment,
  deletionOperation,
  legacyMigration,
  syncMetadata,
  mcpConfigMetadata,
  embeddingConfigMetadata,
  providerConfigMetadata,
  sourceRevision,
  workflowPlanSnapshot,
}

class CoachExtensionRecord {
  CoachExtensionRecord({
    required this.profileId,
    required this.kind,
    required this.id,
    required this.revision,
    required Map<String, Object?> value,
    required this.updatedAt,
  }) : value = Map.unmodifiable(_copyAndValidate(value));

  final ProfileId profileId;
  final CoachExtensionKind kind;
  final String id;
  final int revision;
  final Map<String, Object?> value;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'kind': kind.name,
    'id': id,
    'revision': revision,
    'value': value,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CoachExtensionRecord.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'];
    if (kindName is! String)
      throw const FormatException('extension kind missing');
    final value = json['value'];
    if (value is! Map)
      throw const FormatException('extension value must be object');
    return CoachExtensionRecord(
      profileId: json['profileId'] as String,
      kind: CoachExtensionKind.values.byName(kindName),
      id: json['id'] as String,
      revision: json['revision'] as int,
      value: value.map((key, value) => MapEntry(key.toString(), value)),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// Durable deletion marker. [generation] changes after a full reset so a
/// long-offline device cannot revive content from an older dataset.
class CoachTombstone {
  const CoachTombstone({
    required this.profileId,
    required this.entityType,
    required this.entityId,
    required this.generation,
    required this.deletedAt,
    required this.operationId,
  });

  final ProfileId profileId;
  final String entityType;
  final String entityId;
  final int generation;
  final DateTime deletedAt;
  final String operationId;

  String get key => '$entityType:$entityId';

  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'entityType': entityType,
    'entityId': entityId,
    'generation': generation,
    'deletedAt': deletedAt.toIso8601String(),
    'operationId': operationId,
  };

  factory CoachTombstone.fromJson(Map<String, Object?> json) => CoachTombstone(
    profileId: json['profileId'] as String,
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    generation: json['generation'] as int,
    deletedAt: DateTime.parse(json['deletedAt'] as String),
    operationId: json['operationId'] as String,
  );
}

enum CleanupTaskStatus { pending, running, failed, completed }

class CoachCleanupTask {
  const CoachCleanupTask({
    required this.id,
    required this.profileId,
    required this.type,
    required this.operationId,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.error,
  });

  final String id;
  final ProfileId profileId;
  final String type;
  final String operationId;
  final CleanupTaskStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? error;

  Map<String, Object?> toJson() => {
    'id': id,
    'profileId': profileId,
    'type': type,
    'operationId': operationId,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'error': error,
  };

  factory CoachCleanupTask.fromJson(Map<String, Object?> json) =>
      CoachCleanupTask(
        id: json['id'] as String,
        profileId: json['profileId'] as String,
        type: json['type'] as String,
        operationId: json['operationId'] as String,
        status: CleanupTaskStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
        error: json['error'] as String?,
      );

  CoachCleanupTask copyWith({
    CleanupTaskStatus? status,
    DateTime? updatedAt,
    String? error,
  }) => CoachCleanupTask(
    id: id,
    profileId: profileId,
    type: type,
    operationId: operationId,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    error: error ?? this.error,
  );
}

const _forbiddenKeyFragments = <String>[
  'apikey',
  'api_key',
  'secret',
  'password',
  'credential',
  'authorization',
  'access_token',
  'refresh_token',
];

Map<String, Object?> _copyAndValidate(Map<String, Object?> value) {
  Object? visit(Object? node, String? key) {
    if (key != null && _forbiddenKeyFragments.any(key.toLowerCase().contains)) {
      throw ArgumentError.value(
        key,
        'value',
        'coach extension must not contain credentials',
      );
    }
    if (node == null || node is String || node is num || node is bool)
      return node;
    if (node is List)
      return List.unmodifiable(node.map((item) => visit(item, null)));
    if (node is Map) {
      return Map.unmodifiable({
        for (final entry in node.entries)
          entry.key.toString(): visit(entry.value, entry.key.toString()),
      });
    }
    throw ArgumentError.value(
      node,
      'value',
      'extension values must be JSON data',
    );
  }

  return (visit(value, null) as Map).cast<String, Object?>();
}
