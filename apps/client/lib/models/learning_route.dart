/// 学习路线
class LearningRoute {
  final String id;
  final String name;
  final String description;
  final List<String> domainIds;
  final List<RoutePhase>? phases;     // 新增：阶段排期（官方路线可为 null）
  final String source;                 // 'official' | 'custom' | 'ai'
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

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
  });

  /// 获取路线中所有 topicId（去重）
  List<String> get allTopicIds {
    if (phases == null) return [];
    return phases!
        .expand((p) => p.topicIds)
        .toSet()
        .toList();
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
  final String type; // 'learn' | 'practice' | 'mock'

  const RoutePhase({
    required this.id,
    required this.focus,
    this.description,
    this.topicIds = const [],
    this.categoryIds = const [],
    this.prerequisiteSteps = const [],
    this.estimatedHours = 0,
    this.type = 'learn',
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
  }) => RoutePhase(
    id: id ?? this.id,
    focus: focus ?? this.focus,
    description: description ?? this.description,
    topicIds: topicIds ?? this.topicIds,
    categoryIds: categoryIds ?? this.categoryIds,
    prerequisiteSteps: prerequisiteSteps ?? this.prerequisiteSteps,
    estimatedHours: estimatedHours ?? this.estimatedHours,
    type: type ?? this.type,
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
  );
}
