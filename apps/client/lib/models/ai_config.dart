enum AiAudioMode {
  none,
  transcriptionEndpoint,
  chatAudioInput;

  String get key => switch (this) {
    AiAudioMode.none => 'none',
    AiAudioMode.transcriptionEndpoint => 'transcription_endpoint',
    AiAudioMode.chatAudioInput => 'chat_audio_input',
  };

  String get labelKey => switch (this) {
    AiAudioMode.none => 'audio_mode_none',
    AiAudioMode.transcriptionEndpoint => 'audio_mode_transcription_endpoint',
    AiAudioMode.chatAudioInput => 'audio_mode_chat_audio_input',
  };

  static AiAudioMode fromKey(String? key) => AiAudioMode.values.firstWhere(
    (mode) => mode.key == key,
    orElse: () => AiAudioMode.none,
  );
}

enum AiCapability {
  text,
  audio,
  image;

  String get key => switch (this) {
    AiCapability.text => 'text',
    AiCapability.audio => 'audio',
    AiCapability.image => 'image',
  };

  String get labelKey => switch (this) {
    AiCapability.text => 'support_text',
    AiCapability.audio => 'speech_voice',
    AiCapability.image => 'support_image',
  };
}

enum CapabilityTestState {
  untested,
  passed,
  failed;

  String get key => switch (this) {
    CapabilityTestState.untested => 'untested',
    CapabilityTestState.passed => 'passed',
    CapabilityTestState.failed => 'failed',
  };

  String get labelKey => switch (this) {
    CapabilityTestState.untested => 'capability_test_untested',
    CapabilityTestState.passed => 'capability_test_passed',
    CapabilityTestState.failed => 'capability_test_failed',
  };

  static CapabilityTestState fromKey(String? key) =>
      CapabilityTestState.values.firstWhere(
        (state) => state.key == key,
        orElse: () => CapabilityTestState.untested,
      );
}

class CapabilityTestRecord {
  final CapabilityTestState state;
  final DateTime? testedAt;
  final String message;

  const CapabilityTestRecord({
    this.state = CapabilityTestState.untested,
    this.testedAt,
    this.message = '',
  });

  CapabilityTestRecord copyWith({
    CapabilityTestState? state,
    DateTime? testedAt,
    String? message,
  }) => CapabilityTestRecord(
    state: state ?? this.state,
    testedAt: testedAt ?? this.testedAt,
    message: message ?? this.message,
  );

  factory CapabilityTestRecord.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CapabilityTestRecord();
    return CapabilityTestRecord(
      state: CapabilityTestState.fromKey(json['state'] as String?),
      testedAt: json['testedAt'] != null
          ? DateTime.tryParse(json['testedAt'] as String)
          : null,
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state.key,
    'testedAt': testedAt?.toIso8601String(),
    'message': message,
  };
}

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
  final AiAudioMode audioMode;
  final List<String> usageTags;
  final Map<String, CapabilityTestRecord> capabilityTests;

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
    this.audioMode = AiAudioMode.none,
    this.usageTags = const ['recall'],
    this.capabilityTests = const {},
  });

  bool get canEvaluate =>
      enabled &&
      supportsTextInput &&
      testRecord(AiCapability.text).state == CapabilityTestState.passed;

  bool get canTranscribe =>
      enabled &&
      audioMode != AiAudioMode.none &&
      testRecord(AiCapability.audio).state == CapabilityTestState.passed;

  CapabilityTestRecord testRecord(AiCapability capability) =>
      capabilityTests[capability.key] ?? const CapabilityTestRecord();

  /// 能力标签（返回 l10n key 列表，UI 层使用 l10n.get() 逐个翻译后拼接）
  List<String> get capabilityLabels {
    final labels = <String>[];
    if (supportsTextInput) labels.add('support_text');
    if (supportsImageInput) labels.add('support_image');
    if (audioMode != AiAudioMode.none || supportsAudioInput) {
      labels.add('speech_voice');
    }
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
    AiAudioMode? audioMode,
    List<String>? usageTags,
    Map<String, CapabilityTestRecord>? capabilityTests,
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
    audioMode: audioMode ?? this.audioMode,
    usageTags: usageTags ?? this.usageTags,
    capabilityTests: capabilityTests ?? this.capabilityTests,
  );

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    providerType: json['providerType'] as String? ?? 'openai_compatible',
    baseUrl: json['baseUrl'] as String,
    apiKey: json['apiKey'] as String? ?? '',
    model: json['model'] as String,
    isDefault: json['isDefault'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? true,
    supportsTextInput: json['supportsTextInput'] as bool? ?? true,
    supportsImageInput: json['supportsImageInput'] as bool? ?? false,
    supportsAudioInput:
        json['supportsAudioInput'] as bool? ??
        (json['audioMode'] != null &&
            json['audioMode'] != AiAudioMode.none.key),
    supportsMultimodal: json['supportsMultimodal'] as bool? ?? false,
    supportsStreaming: json['supportsStreaming'] as bool? ?? false,
    audioMode: AiAudioMode.fromKey(
      json['audioMode'] as String? ??
          ((json['supportsAudioInput'] as bool? ?? false)
              ? AiAudioMode.transcriptionEndpoint.key
              : null),
    ),
    usageTags:
        (json['usageTags'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['recall'],
    capabilityTests: ((json['capabilityTests'] as Map<String, dynamic>?) ?? {})
        .map(
          (key, value) => MapEntry(
            key,
            CapabilityTestRecord.fromJson(
              value is Map<String, dynamic> ? value : null,
            ),
          ),
        ),
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
    'audioMode': audioMode.key,
    'usageTags': usageTags,
    'capabilityTests': capabilityTests.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };
}
