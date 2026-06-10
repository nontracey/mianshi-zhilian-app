/// 学习路线
class LearningRoute {
  final String id;
  final String name;
  final String description;
  final List<String> domainIds;
  final List<RoutePhase>? phases;     // 阶段排期（官方路线可为 null）
  final String source;                 // 'official' | 'custom' | 'ai'
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// AI 路线专用：生成时的面试目标签名（用于去重）
  final String? planSignature;

  const LearningRoute({
    required this.id,
    required this.name,
    this.description = '',
    required this.domainIds,
    this.phases,
    this.source = 'custom',
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.planSignature,
  });

  /// 获取路线中所有 topicId（去重）
  List<String> get allTopicIds {
    if (phases == null) return [];
    return phases!
        .expand((p) => p.topicIds)
        .toSet()
        .toList();
  }

  /// 真正参与的领域：有 phases 时按 phases 里出现的 domainId 推导（去重、保序），
  /// 否则退回声明的 [domainIds]。
  ///
  /// 这样「声称的领域」永远等于「实际有内容的领域」，避免 domainIds 与 phases
  /// 漂移导致目录出现空领域 tab、掌握度统计只显示部分领域等不一致问题。
  List<String> get effectiveDomainIds {
    final p = phases;
    if (p == null || p.isEmpty) return domainIds;
    final seen = <String>{};
    final ordered = <String>[];
    for (final phase in p) {
      final d = phase.domainId;
      if (d == null || d.isEmpty) continue;
      if (seen.add(d)) ordered.add(d);
    }
    return ordered.isEmpty ? domainIds : ordered;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'domainIds': domainIds,
    if (phases != null) 'phases': phases!.map((p) => p.toJson()).toList(),
    'source': source,
    'isDefault': isDefault,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (planSignature != null) 'planSignature': planSignature,
  };

  factory LearningRoute.fromJson(Map<String, dynamic> json) => LearningRoute(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    domainIds: (json['domainIds'] as List<dynamic>).map((e) => e.toString()).toList(),
    phases: (json['phases'] as List<dynamic>?)
        ?.map((e) => RoutePhase.fromJson(e as Map<String, dynamic>))
        .toList(),
    source: json['source'] as String? ?? 'custom',
    isDefault: json['isDefault'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String? ?? DateTime.now().toIso8601String()),
    updatedAt: DateTime.parse(json['updatedAt'] as String? ?? DateTime.now().toIso8601String()),
    planSignature: json['planSignature'] as String?,
  );
}

/// 路线阶段
class RoutePhase {
  final String id;
  final String focus;
  final String? description;
  final List<String> topicIds;
  final List<String> categoryIds;
  final List<String> prerequisiteSteps;
  final int estimatedHours;
  final String type;
  final String? domainId;

  const RoutePhase({
    required this.id,
    required this.focus,
    this.description,
    this.topicIds = const [],
    this.categoryIds = const [],
    this.prerequisiteSteps = const [],
    this.estimatedHours = 0,
    this.type = 'learn',
    this.domainId,
  });

  RoutePhase copyWith({
    String? id,
    String? focus,
    String? description,
    List<String>? topicIds,
    List<String>? categoryIds,
    List<String>? prerequisiteSteps,
    int? estimatedHours,
    String? type,
    String? domainId,
  }) => RoutePhase(
    id: id ?? this.id,
    focus: focus ?? this.focus,
    description: description ?? this.description,
    topicIds: topicIds ?? this.topicIds,
    categoryIds: categoryIds ?? this.categoryIds,
    prerequisiteSteps: prerequisiteSteps ?? this.prerequisiteSteps,
    estimatedHours: estimatedHours ?? this.estimatedHours,
    type: type ?? this.type,
    domainId: domainId ?? this.domainId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'focus': focus,
    if (description != null) 'description': description,
    'topicIds': topicIds,
    'categoryIds': categoryIds,
    'prerequisiteSteps': prerequisiteSteps,
    'estimatedHours': estimatedHours,
    'type': type,
    if (domainId != null) 'domainId': domainId,
  };

  factory RoutePhase.fromJson(Map<String, dynamic> json) => RoutePhase(
    id: json['id'] as String,
    focus: json['focus'] as String,
    description: json['description'] as String?,
    topicIds: (json['topicIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    categoryIds: (json['categoryIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    prerequisiteSteps: (json['prerequisiteSteps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    estimatedHours: (json['estimatedHours'] as num?)?.toInt() ?? 0,
    type: json['type'] as String? ?? 'learn',
    domainId: json['domainId'] as String?,
  );
}
