class AiConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool isDefault;

  const AiConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.isDefault = false,
  });

  AiConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? isDefault,
  }) =>
      AiConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        isDefault: isDefault ?? this.isDefault,
      );

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String,
        model: json['model'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'isDefault': isDefault,
      };
}
