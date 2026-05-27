class AiConfig {
  final String id;
  final String name;
  final String providerType;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool isDefault;
  final bool enabled;

  const AiConfig({
    required this.id,
    required this.name,
    this.providerType = 'openai_compatible',
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.isDefault = false,
    this.enabled = true,
  });

  AiConfig copyWith({
    String? id,
    String? name,
    String? providerType,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? isDefault,
    bool? enabled,
  }) =>
      AiConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        providerType: providerType ?? this.providerType,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        isDefault: isDefault ?? this.isDefault,
        enabled: enabled ?? this.enabled,
      );

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        providerType: json['providerType'] as String? ?? 'openai_compatible',
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String,
        model: json['model'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'providerType': providerType,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'isDefault': isDefault,
        'enabled': enabled,
      };
}
