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

/// 默认学习路线
const defaultRoutes = [
  LearningRoute(
    id: 'java',
    name: 'Java 后端开发',
    description: 'Java 核心、Spring、数据库、微服务',
    domainIds: ['java', 'database', 'distributed', 'network'],
    isDefault: true,
  ),
  LearningRoute(
    id: 'frontend',
    name: '前端开发',
    description: 'JavaScript、React、Vue、性能优化',
    domainIds: ['javascript', 'react', 'vue', 'frontend'],
    isDefault: true,
  ),
  LearningRoute(
    id: 'agent',
    name: 'Agent 开发',
    description: 'AI Agent、RAG、Prompt Engineering',
    domainIds: ['ai', 'agent', 'algorithm'],
    isDefault: true,
  ),
  LearningRoute(
    id: 'dotnet',
    name: '.NET 开发',
    description: 'C#、ASP.NET、微服务、数据库',
    domainIds: ['dotnet', 'csharp', 'database', 'distributed'],
    isDefault: true,
  ),
];
