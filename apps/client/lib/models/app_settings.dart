import 'package:flutter/material.dart';

/// 知识源环境
enum ContentEnv {
  test('test', '测试版'),
  production('production', '发布版');

  const ContentEnv(this.key, this.label);
  final String key;
  final String label;

  static ContentEnv fromKey(String key) =>
      ContentEnv.values.firstWhere((e) => e.key == key,
          orElse: () => ContentEnv.production);
}

class AppSettings {
  final ThemeMode themeMode;
  final Color primaryColor;
  final Color accentColor;
  final String language;
  final String recommendStrategy;
  final String currentDomain;
  final bool compactLayout;

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
    return customProdContentUrl?.isNotEmpty == true
        ? customProdContentUrl!
        : '$defaultWorkerApiUrl/content/production';
  }

  /// 测试版 URL（显示用）
  String get effectiveTestContentUrl =>
      customTestContentUrl?.isNotEmpty == true
          ? customTestContentUrl!
          : '$defaultWorkerApiUrl/content/test';

  /// 发布版 URL（显示用）
  String get effectiveProdContentUrl =>
      customProdContentUrl?.isNotEmpty == true
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
    ContentEnv? contentEnv,
    String? customTestContentUrl,
    String? customProdContentUrl,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        primaryColor: primaryColor ?? this.primaryColor,
        accentColor: accentColor ?? this.accentColor,
        language: language ?? this.language,
        recommendStrategy: recommendStrategy ?? this.recommendStrategy,
        currentDomain: currentDomain ?? this.currentDomain,
        compactLayout: compactLayout ?? this.compactLayout,
        contentEnv: contentEnv ?? this.contentEnv,
        customTestContentUrl:
            customTestContentUrl ?? this.customTestContentUrl,
        customProdContentUrl:
            customProdContentUrl ?? this.customProdContentUrl,
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
        contentEnv: ContentEnv.fromKey(json['contentEnv'] as String? ?? 'production'),
        customTestContentUrl:
            json['customTestContentUrl'] as String?,
        customProdContentUrl:
            json['customProdContentUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'primaryColor': primaryColor.toARGB32(),
        'accentColor': accentColor.toARGB32(),
        'language': language,
        'recommendStrategy': recommendStrategy,
        'currentDomain': currentDomain,
        'compactLayout': compactLayout,
        'contentEnv': contentEnv.key,
        'customTestContentUrl': customTestContentUrl,
        'customProdContentUrl': customProdContentUrl,
      };
}
