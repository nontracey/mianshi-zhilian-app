import 'package:flutter/material.dart';

class AppSettings {
  final ThemeMode themeMode;
  final Color primaryColor;
  final Color accentColor;
  final String language;
  final String recommendStrategy;
  final String currentDomain;
  final bool compactLayout;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.primaryColor = const Color(0xFF0A2540),
    this.accentColor = const Color(0xFF00CCF9),
    this.language = 'zh',
    this.recommendStrategy = 'low-score-first',
    this.currentDomain = 'java',
    this.compactLayout = false,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    Color? primaryColor,
    Color? accentColor,
    String? language,
    String? recommendStrategy,
    String? currentDomain,
    bool? compactLayout,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        primaryColor: primaryColor ?? this.primaryColor,
        accentColor: accentColor ?? this.accentColor,
        language: language ?? this.language,
        recommendStrategy: recommendStrategy ?? this.recommendStrategy,
        currentDomain: currentDomain ?? this.currentDomain,
        compactLayout: compactLayout ?? this.compactLayout,
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
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'primaryColor': primaryColor.toARGB32(),
        'accentColor': accentColor.toARGB32(),
        'language': language,
        'recommendStrategy': recommendStrategy,
        'currentDomain': currentDomain,
        'compactLayout': compactLayout,
      };
}
