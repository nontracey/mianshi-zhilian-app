/// 学习路线
class LearningRoute {
  final String id;
  final String name;
  final String description;
  final List<String> domainIds;
  final bool isDefault;

  const LearningRoute({
    required this.id,
    required this.name,
    required this.description,
    required this.domainIds,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'domainIds': domainIds,
    'isDefault': isDefault,
  };

  factory LearningRoute.fromJson(Map<String, dynamic> json) => LearningRoute(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    domainIds: (json['domainIds'] as List<dynamic>).map((e) => e.toString()).toList(),
    isDefault: json['isDefault'] as bool? ?? false,
  );
}
