class AiConfig {
  final String id;
  final String name;
  final String providerType;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool isDefault;
  final bool enabled;
  final bool supportsTextInput;
  final bool supportsImageInput;
  final bool supportsAudioInput;
  final bool supportsMultimodal;
  final bool supportsStreaming;
  final List<String> usageTags;

  const AiConfig({
    required this.id,
    required this.name,
    this.providerType = 'openai_compatible',
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.isDefault = false,
    this.enabled = true,
    this.supportsTextInput = true,
    this.supportsImageInput = false,
    this.supportsAudioInput = false,
    this.supportsMultimodal = false,
    this.supportsStreaming = false,
    this.usageTags = const ['recall'],
  });

  bool get canEvaluate => enabled && supportsTextInput;

  /// 能力标签（返回 l10n key 列表，UI 层使用 l10n.get() 逐个翻译后拼接）
  List<String> get capabilityLabels {
    final labels = <String>[];
    if (supportsTextInput) labels.add('support_text');
    if (supportsImageInput) labels.add('support_image');
    if (supportsAudioInput) labels.add('speech_voice');
    if (supportsStreaming) labels.add('support_streaming');
    return labels.isEmpty ? ['capability_not_declared'] : labels;
  }

  @Deprecated('Use capabilityLabels with l10n.get() instead')
  String get capabilityLabel => capabilityLabels.join(' · ');

  AiConfig copyWith({
    String? id,
    String? name,
    String? providerType,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? isDefault,
    bool? enabled,
    bool? supportsTextInput,
    bool? supportsImageInput,
    bool? supportsAudioInput,
    bool? supportsMultimodal,
    bool? supportsStreaming,
    List<String>? usageTags,
  }) => AiConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    providerType: providerType ?? this.providerType,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    isDefault: isDefault ?? this.isDefault,
    enabled: enabled ?? this.enabled,
    supportsTextInput: supportsTextInput ?? this.supportsTextInput,
    supportsImageInput: supportsImageInput ?? this.supportsImageInput,
    supportsAudioInput: supportsAudioInput ?? this.supportsAudioInput,
    supportsMultimodal: supportsMultimodal ?? this.supportsMultimodal,
    supportsStreaming: supportsStreaming ?? this.supportsStreaming,
    usageTags: usageTags ?? this.usageTags,
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
    supportsTextInput: json['supportsTextInput'] as bool? ?? true,
    supportsImageInput: json['supportsImageInput'] as bool? ?? false,
    supportsAudioInput: json['supportsAudioInput'] as bool? ?? false,
    supportsMultimodal: json['supportsMultimodal'] as bool? ?? false,
    supportsStreaming: json['supportsStreaming'] as bool? ?? false,
    usageTags:
        (json['usageTags'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['recall'],
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
    'supportsTextInput': supportsTextInput,
    'supportsImageInput': supportsImageInput,
    'supportsAudioInput': supportsAudioInput,
    'supportsMultimodal': supportsMultimodal,
    'supportsStreaming': supportsStreaming,
    'usageTags': usageTags,
  };
}
