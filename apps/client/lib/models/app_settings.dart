import 'package:flutter/material.dart';

/// 知识源环境
enum ContentEnv {
  test('test', '测试版'),
  draft('draft', '草稿版'),
  production('production', '发布版');

  const ContentEnv(this.key, this.label);
  final String key;
  final String label;

  static ContentEnv fromKey(String key) => ContentEnv.values.firstWhere(
    (e) => e.key == key,
    orElse: () => ContentEnv.production,
  );
}

/// 主题类型
enum AppThemeType {
  system('system', '跟随系统'),
  elegantWhite('elegantWhite', '典雅白'),
  qualityBlack('qualityBlack', '气质黑'),
  midnightBlue('midnightBlue', '午夜蓝');

  const AppThemeType(this.key, this.label);
  final String key;
  final String label;

  static AppThemeType fromKey(String key) => AppThemeType.values.firstWhere(
    (e) => e.key == key,
    orElse: () => AppThemeType.system,
  );
  
  /// 获取实际的亮度（用于跟随系统）
  Brightness get resolvedBrightness {
    if (this == AppThemeType.elegantWhite) return Brightness.light;
    if (this == AppThemeType.qualityBlack || this == AppThemeType.midnightBlue) return Brightness.dark;
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

  // 知识源配置
  final ContentEnv contentEnv;
  final String? customTestContentUrl;
  final String? customProdContentUrl;

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
    this.contentEnv = ContentEnv.production,
    this.customTestContentUrl,
    this.customProdContentUrl,
  });

  /// 默认 Worker API 基地址
  static const defaultWorkerApiUrl =
      'https://mianshi-zhilian-api.nontracey.workers.dev';

  /// 获取当前内容源的基础 URL
  String get contentBaseUrl {
    if (contentEnv == ContentEnv.test) {
      return customTestContentUrl?.isNotEmpty == true
          ? customTestContentUrl!
          : '$defaultWorkerApiUrl/content/test';
    }
    if (contentEnv == ContentEnv.draft) {
      return customTestContentUrl?.isNotEmpty == true
          ? customTestContentUrl!
          : '$defaultWorkerApiUrl/content/draft';
    }
    return customProdContentUrl?.isNotEmpty == true
        ? customProdContentUrl!
        : '$defaultWorkerApiUrl/content/production';
  }

  /// 测试版 URL（显示用）
  String get effectiveTestContentUrl => customTestContentUrl?.isNotEmpty == true
      ? customTestContentUrl!
      : '$defaultWorkerApiUrl/content/test';

  /// 发布版 URL（显示用）
  String get effectiveProdContentUrl => customProdContentUrl?.isNotEmpty == true
      ? customProdContentUrl!
      : '$defaultWorkerApiUrl/content/production';

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
    ContentEnv? contentEnv,
    String? customTestContentUrl,
    String? customProdContentUrl,
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
    contentEnv: contentEnv ?? this.contentEnv,
    customTestContentUrl: customTestContentUrl ?? this.customTestContentUrl,
    customProdContentUrl: customProdContentUrl ?? this.customProdContentUrl,
  );

  /// 获取 ThemeMode（兼容旧代码）
  ThemeMode get themeMode {
    if (themeType == AppThemeType.system) return ThemeMode.system;
    if (themeType == AppThemeType.elegantWhite) return ThemeMode.light;
    return ThemeMode.dark;
  }

  /// 从旧的 themeMode 字符串转换为 AppThemeType
  static AppThemeType _parseThemeType(dynamic themeTypeJson, dynamic themeModeJson) {
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
    contentEnv: ContentEnv.fromKey(
      json['contentEnv'] as String? ?? 'production',
    ),
    customTestContentUrl: json['customTestContentUrl'] as String?,
    customProdContentUrl: json['customProdContentUrl'] as String?,
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
    'contentEnv': contentEnv.key,
    'customTestContentUrl': customTestContentUrl,
    'customProdContentUrl': customProdContentUrl,
  };
}
