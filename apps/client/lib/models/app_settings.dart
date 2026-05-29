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

class AppSettings {
  final ThemeMode themeMode;
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
    this.themeMode = ThemeMode.system,
    this.primaryColor = const Color(0xFF0A2540),
    this.accentColor = const Color(0xFF00CCF9),
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
    ThemeMode? themeMode,
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
    themeMode: themeMode ?? this.themeMode,
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

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeMode: ThemeMode.values.firstWhere(
      (e) => e.name == json['themeMode'],
      orElse: () => ThemeMode.system,
    ),
    primaryColor: json['primaryColor'] != null
        ? Color(json['primaryColor'] as int)
        : const Color(0xFF0A2540),
    accentColor: json['accentColor'] != null
        ? Color(json['accentColor'] as int)
        : const Color(0xFF00CCF9),
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
    'themeMode': themeMode.name,
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
