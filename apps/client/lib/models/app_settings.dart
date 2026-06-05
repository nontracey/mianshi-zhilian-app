import 'package:flutter/material.dart';

import '../services/route_resolver.dart';

const Object _unset = Object();

/// 本机 STT 引擎类型
enum OnDeviceEngine {
  senseVoice,
  whisper,
  paraformer;

  String get key {
    switch (this) {
      case OnDeviceEngine.senseVoice:
        return 'sense_voice';
      case OnDeviceEngine.whisper:
        return 'whisper';
      case OnDeviceEngine.paraformer:
        return 'paraformer';
    }
  }

  static OnDeviceEngine fromKey(String key) => OnDeviceEngine.values.firstWhere(
    (e) => e.key == key,
    orElse: () => OnDeviceEngine.senseVoice,
  );
}

/// 知识源环境
enum ContentEnv {
  staging,
  draft,
  production;

  String get key {
    switch (this) {
      case ContentEnv.staging:
        return 'staging';
      case ContentEnv.draft:
        return 'draft';
      case ContentEnv.production:
        return 'production';
    }
  }

  /// 返回 l10n key，UI 层使用 l10n.get() 获取显示文本
  String get labelKey {
    switch (this) {
      case ContentEnv.staging:
        return 'test_version';
      case ContentEnv.draft:
        return 'draft_version';
      case ContentEnv.production:
        return 'publish_version';
    }
  }

  String get routeStage => switch (this) {
    ContentEnv.staging => 'test',
    ContentEnv.draft => 'draft',
    ContentEnv.production => 'production',
  };

  bool isAllowedBy(Iterable<String> allowedKeys) {
    if (allowedKeys.contains(key)) return true;
    return this == ContentEnv.staging && allowedKeys.contains('test');
  }

  static ContentEnv fromKey(String key) {
    final normalized = key == 'test' ? 'staging' : key;
    return ContentEnv.values.firstWhere(
      (e) => e.key == normalized,
      orElse: () => ContentEnv.production,
    );
  }
}

/// 主题类型
enum AppThemeType {
  system,
  elegantWhite,
  qualityBlack,
  midnightBlue;

  String get key {
    switch (this) {
      case AppThemeType.system:
        return 'system';
      case AppThemeType.elegantWhite:
        return 'elegantWhite';
      case AppThemeType.qualityBlack:
        return 'qualityBlack';
      case AppThemeType.midnightBlue:
        return 'midnightBlue';
    }
  }

  /// 返回 l10n key，UI 层使用 l10n.get() 获取显示文本
  String get labelKey {
    switch (this) {
      case AppThemeType.system:
        return 'follow_system';
      case AppThemeType.elegantWhite:
        return 'classic_elegant_white';
      case AppThemeType.qualityBlack:
        return 'gas_quality_dark';
      case AppThemeType.midnightBlue:
        return 'noon_night_blue';
    }
  }

  static AppThemeType fromKey(String key) => AppThemeType.values.firstWhere(
    (e) => e.key == key,
    orElse: () => AppThemeType.system,
  );

  /// 获取实际的亮度（用于跟随系统）
  Brightness get resolvedBrightness {
    if (this == AppThemeType.elegantWhite) return Brightness.light;
    if (this == AppThemeType.qualityBlack ||
        this == AppThemeType.midnightBlue) {
      return Brightness.dark;
    }
    return Brightness.light; // system 默认，实际由系统决定
  }
}

class AppSettings {
  final AppThemeType themeType;
  final Color primaryColor;
  final Color accentColor;
  final String language;
  final String recommendStrategy;
  final String currentDomain;
  final bool compactLayout;
  final int dailyNewCount;
  final int dailyReviewCount;
  final int lowScoreWeight;
  final int overdueWeight;
  final int highFrequencyWeight;
  final int pathOrderWeight;
  final int notPracticedWeight;
  final bool prioritizePrerequisites;
  final bool allowSkipLowFrequency;
  final String mockInterviewPreference;
  final double fontScale;
  final String cardDensity;

  // 语音识别配置
  // 'auto' | 'follow_current_ai' | 'fixed_ai_config' | 'system' | 'sherpa_onnx'
  final String sttMode;
  final String? sttAiConfigId;
  // 本机语音识别（sherpa_onnx）配置
  final String onDeviceEngine; // 'sense_voice' | 'whisper' | 'paraformer'
  // 'tiny' | 'base' | 'small' | 'medium'（仅引擎为 whisper 时生效）
  final String whisperModel;

  // 知识源配置
  final ContentEnv contentEnv;
  final String? customTestContentUrl;
  final String? customDraftContentUrl;
  final String? customProdContentUrl;

  // 更新下载配置
  final String? customGithubMirror;

  const AppSettings({
    this.themeType = AppThemeType.system,
    this.primaryColor = const Color(0xFF1A2B4A),
    this.accentColor = const Color(0xFF3078F0),
    this.language = 'zh',
    this.recommendStrategy = 'low-score-first',
    this.currentDomain = 'java',
    this.compactLayout = false,
    this.dailyNewCount = 3,
    this.dailyReviewCount = 6,
    this.lowScoreWeight = 35,
    this.overdueWeight = 25,
    this.highFrequencyWeight = 25,
    this.pathOrderWeight = 10,
    this.notPracticedWeight = 5,
    this.prioritizePrerequisites = true,
    this.allowSkipLowFrequency = false,
    this.mockInterviewPreference = 'mixed',
    this.fontScale = 1.0,
    this.cardDensity = 'comfortable',
    this.sttMode = 'auto',
    this.sttAiConfigId,
    this.onDeviceEngine = 'sense_voice',
    this.whisperModel = 'base',
    this.contentEnv = ContentEnv.production,
    this.customTestContentUrl,
    this.customDraftContentUrl,
    this.customProdContentUrl,
    this.customGithubMirror,
  });

  /// 官方 App API 主用地址。业务请求会经 RouteResolver 自动纳入主备路由。
  static const defaultWorkerApiUrl = RouteResolver.appApiPrimary;

  /// 官方发布版内容 CDN 主用地址。为空自定义源时会经 RouteResolver 纳入主备路由。
  static const defaultProdContentUrl = RouteResolver.contentPrimary;

  /// 获取当前内容源的基础 URL
  String get contentBaseUrl {
    if (contentEnv == ContentEnv.staging) {
      return customTestContentUrl?.isNotEmpty == true
          ? customTestContentUrl!
          : '$defaultWorkerApiUrl/content/test';
    }
    if (contentEnv == ContentEnv.draft) {
      return customDraftContentUrl?.isNotEmpty == true
          ? customDraftContentUrl!
          : '$defaultWorkerApiUrl/content/draft';
    }
    return customProdContentUrl?.isNotEmpty == true
        ? customProdContentUrl!
        : defaultProdContentUrl;
  }

  /// 测试版 URL（显示用）
  String get effectiveTestContentUrl => customTestContentUrl?.isNotEmpty == true
      ? customTestContentUrl!
      : '$defaultWorkerApiUrl/content/test';

  /// 草稿版 URL（显示用）
  String get effectiveDraftContentUrl =>
      customDraftContentUrl?.isNotEmpty == true
      ? customDraftContentUrl!
      : '$defaultWorkerApiUrl/content/draft';

  /// 发布版 URL（显示用）
  String get effectiveProdContentUrl => customProdContentUrl?.isNotEmpty == true
      ? customProdContentUrl!
      : defaultProdContentUrl;

  AppSettings copyWith({
    AppThemeType? themeType,
    Color? primaryColor,
    Color? accentColor,
    String? language,
    String? recommendStrategy,
    String? currentDomain,
    bool? compactLayout,
    int? dailyNewCount,
    int? dailyReviewCount,
    int? lowScoreWeight,
    int? overdueWeight,
    int? highFrequencyWeight,
    int? pathOrderWeight,
    int? notPracticedWeight,
    bool? prioritizePrerequisites,
    bool? allowSkipLowFrequency,
    String? mockInterviewPreference,
    double? fontScale,
    String? cardDensity,
    String? sttMode,
    Object? sttAiConfigId = _unset,
    String? onDeviceEngine,
    String? whisperModel,
    ContentEnv? contentEnv,
    Object? customTestContentUrl = _unset,
    Object? customDraftContentUrl = _unset,
    Object? customProdContentUrl = _unset,
    Object? customGithubMirror = _unset,
  }) => AppSettings(
    themeType: themeType ?? this.themeType,
    primaryColor: primaryColor ?? this.primaryColor,
    accentColor: accentColor ?? this.accentColor,
    language: language ?? this.language,
    recommendStrategy: recommendStrategy ?? this.recommendStrategy,
    currentDomain: currentDomain ?? this.currentDomain,
    compactLayout: compactLayout ?? this.compactLayout,
    dailyNewCount: dailyNewCount ?? this.dailyNewCount,
    dailyReviewCount: dailyReviewCount ?? this.dailyReviewCount,
    lowScoreWeight: lowScoreWeight ?? this.lowScoreWeight,
    overdueWeight: overdueWeight ?? this.overdueWeight,
    highFrequencyWeight: highFrequencyWeight ?? this.highFrequencyWeight,
    pathOrderWeight: pathOrderWeight ?? this.pathOrderWeight,
    notPracticedWeight: notPracticedWeight ?? this.notPracticedWeight,
    prioritizePrerequisites:
        prioritizePrerequisites ?? this.prioritizePrerequisites,
    allowSkipLowFrequency: allowSkipLowFrequency ?? this.allowSkipLowFrequency,
    mockInterviewPreference:
        mockInterviewPreference ?? this.mockInterviewPreference,
    fontScale: fontScale ?? this.fontScale,
    cardDensity: cardDensity ?? this.cardDensity,
    sttMode: sttMode ?? this.sttMode,
    sttAiConfigId: sttAiConfigId == _unset
        ? this.sttAiConfigId
        : sttAiConfigId as String?,
    onDeviceEngine: onDeviceEngine ?? this.onDeviceEngine,
    whisperModel: whisperModel ?? this.whisperModel,
    contentEnv: contentEnv ?? this.contentEnv,
    customTestContentUrl: customTestContentUrl == _unset
        ? this.customTestContentUrl
        : customTestContentUrl as String?,
    customDraftContentUrl: customDraftContentUrl == _unset
        ? this.customDraftContentUrl
        : customDraftContentUrl as String?,
    customProdContentUrl: customProdContentUrl == _unset
        ? this.customProdContentUrl
        : customProdContentUrl as String?,
    customGithubMirror: customGithubMirror == _unset
        ? this.customGithubMirror
        : customGithubMirror as String?,
  );

  /// 获取 ThemeMode（兼容旧代码）
  ThemeMode get themeMode {
    if (themeType == AppThemeType.system) return ThemeMode.system;
    if (themeType == AppThemeType.elegantWhite) return ThemeMode.light;
    return ThemeMode.dark;
  }

  /// 从旧的 themeMode 字符串转换为 AppThemeType
  static AppThemeType _parseThemeType(
    dynamic themeTypeJson,
    dynamic themeModeJson,
  ) {
    // 优先使用新的 themeType 字段
    if (themeTypeJson != null) {
      return AppThemeType.fromKey(themeTypeJson as String);
    }

    // 兼容旧的 themeMode 字段
    if (themeModeJson != null) {
      final themeModeStr = themeModeJson as String;
      // 处理 'ThemeMode.xxx' 格式
      if (themeModeStr.contains('dark')) return AppThemeType.qualityBlack;
      if (themeModeStr.contains('light')) return AppThemeType.elegantWhite;
      if (themeModeStr.contains('system')) return AppThemeType.system;
      // 处理 'xxx' 格式
      if (themeModeStr == 'dark') return AppThemeType.qualityBlack;
      if (themeModeStr == 'light') return AppThemeType.elegantWhite;
      if (themeModeStr == 'system') return AppThemeType.system;
    }

    return AppThemeType.system;
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeType: _parseThemeType(json['themeType'], json['themeMode']),
    primaryColor: json['primaryColor'] != null
        ? Color(json['primaryColor'] as int)
        : const Color(0xFF1A2B4A),
    accentColor: json['accentColor'] != null
        ? Color(json['accentColor'] as int)
        : const Color(0xFF3078F0),
    language: json['language'] as String? ?? 'zh',
    recommendStrategy:
        json['recommendStrategy'] as String? ?? 'low-score-first',
    currentDomain: json['currentDomain'] as String? ?? 'java',
    compactLayout: json['compactLayout'] as bool? ?? false,
    dailyNewCount: (json['dailyNewCount'] as num?)?.toInt() ?? 3,
    dailyReviewCount: (json['dailyReviewCount'] as num?)?.toInt() ?? 6,
    lowScoreWeight: (json['lowScoreWeight'] as num?)?.toInt() ?? 35,
    overdueWeight: (json['overdueWeight'] as num?)?.toInt() ?? 25,
    highFrequencyWeight: (json['highFrequencyWeight'] as num?)?.toInt() ?? 25,
    pathOrderWeight: (json['pathOrderWeight'] as num?)?.toInt() ?? 10,
    notPracticedWeight: (json['notPracticedWeight'] as num?)?.toInt() ?? 5,
    prioritizePrerequisites: json['prioritizePrerequisites'] as bool? ?? true,
    allowSkipLowFrequency: json['allowSkipLowFrequency'] as bool? ?? false,
    mockInterviewPreference:
        json['mockInterviewPreference'] as String? ?? 'mixed',
    fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
    cardDensity: json['cardDensity'] as String? ?? 'comfortable',
    sttMode: json['sttMode'] as String? ?? 'auto',
    sttAiConfigId: json['sttAiConfigId'] as String?,
    onDeviceEngine: json['onDeviceEngine'] as String? ?? 'sense_voice',
    whisperModel: json['whisperModel'] as String? ?? 'base',
    contentEnv: ContentEnv.fromKey(
      json['contentEnv'] as String? ?? 'production',
    ),
    customTestContentUrl: json['customTestContentUrl'] as String?,
    customDraftContentUrl: json['customDraftContentUrl'] as String?,
    customProdContentUrl: json['customProdContentUrl'] as String?,
    customGithubMirror: json['customGithubMirror'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'themeType': themeType.key,
    'primaryColor': primaryColor.toARGB32(),
    'accentColor': accentColor.toARGB32(),
    'language': language,
    'recommendStrategy': recommendStrategy,
    'currentDomain': currentDomain,
    'compactLayout': compactLayout,
    'dailyNewCount': dailyNewCount,
    'dailyReviewCount': dailyReviewCount,
    'lowScoreWeight': lowScoreWeight,
    'overdueWeight': overdueWeight,
    'highFrequencyWeight': highFrequencyWeight,
    'pathOrderWeight': pathOrderWeight,
    'notPracticedWeight': notPracticedWeight,
    'prioritizePrerequisites': prioritizePrerequisites,
    'allowSkipLowFrequency': allowSkipLowFrequency,
    'mockInterviewPreference': mockInterviewPreference,
    'fontScale': fontScale,
    'cardDensity': cardDensity,
    'sttMode': sttMode,
    'sttAiConfigId': sttAiConfigId,
    'onDeviceEngine': onDeviceEngine,
    'whisperModel': whisperModel,
    'contentEnv': contentEnv.key,
    'customTestContentUrl': customTestContentUrl,
    'customDraftContentUrl': customDraftContentUrl,
    'customProdContentUrl': customProdContentUrl,
    'customGithubMirror': customGithubMirror,
  };
}
