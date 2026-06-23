import 'package:flutter/material.dart';
import 'colors.dart';

/// 应用打包的中文子集字体族名（见 pubspec.yaml fonts: AppSans）。
/// 含拉丁与中文字形，避免运行时从 Google Fonts 下载 Noto 分片
/// （此前的运行时下载会在滚动时按需拉取字形分片，造成全局卡顿）。
const String kAppFontFamily = 'AppSans';

/// 构建主题
/// 
/// [themeType] 主题类型：system, elegantWhite, qualityBlack, midnightBlue
/// [systemIsDark] 当 themeType 为 system 时，系统是否为深色模式
ThemeData buildTheme(
  Color primary,
  Color accent,
  String themeType, {
  double fontScale = 1.0,
  String cardDensity = 'comfortable',
  bool systemIsDark = false,
}) {
  // 解析主题类型
  final isQualityBlack = themeType == 'qualityBlack';
  final isMidnightBlue = themeType == 'midnightBlue';
  final isSystemDark = themeType == 'system' && systemIsDark;
  
  // 是否为深色主题
  final isDark = isQualityBlack || isMidnightBlue || isSystemDark;
  // 是否为午夜蓝
  final isMidnight = isMidnightBlue || (themeType == 'system' && systemIsDark && false); // 系统深色默认用气质黑

  // 根据主题类型选择颜色
  final bgColor = isDark
      ? (isMidnight ? AppColors.bgMidnight : AppColors.bgDark)
      : AppColors.bgLight;
  final surfaceColor = isDark
      ? (isMidnight ? AppColors.surfaceMidnight : AppColors.surfaceDark)
      : Colors.white;
  final surfaceHighColor = isDark
      ? (isMidnight ? AppColors.surfaceMidnightHigh : AppColors.surfaceDarkHigh)
      : const Color(0xFFF0F2F5);
  final surfaceHighestColor = isDark
      ? (isMidnight ? AppColors.surfaceMidnightHighest : AppColors.surfaceDarkHighest)
      : const Color(0xFFEEF0F2);
  final borderColor = isDark
      ? (isMidnight ? AppColors.borderMidnight : AppColors.borderDark)
      : AppColors.borderLight;
  final borderSubtleColor = isDark
      ? (isMidnight ? AppColors.borderMidnightSubtle : AppColors.borderDarkSubtle)
      : const Color(0xFFE8E8E8);
  final textPrimaryColor = isDark ? const Color(0xFFE6EDF3) : AppColors.textPrimary;
  final textSecondaryColor = isDark ? const Color(0xFF8B949E) : AppColors.textSecondary;
  final shadowColor = isDark ? AppColors.cardShadowDark : AppColors.cardShadow;

  // 配色
  final colorScheme = ColorScheme(
    brightness: isDark ? Brightness.dark : Brightness.light,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: isDark
        ? (isMidnight ? const Color(0xFF1E3A5F) : const Color(0xFF1A2B4A))
        : const Color(0xFFD6E4FF),
    onPrimaryContainer: isDark ? Colors.white : const Color(0xFF0D2240),
    secondary: accent,
    onSecondary: Colors.white,
    secondaryContainer: isDark
        ? (isMidnight ? const Color(0xFF1A3A6E) : const Color(0xFF1A2B4A))
        : const Color(0xFFD6E4FF),
    onSecondaryContainer: isDark ? Colors.white : const Color(0xFF001B3E),
    tertiary: AppColors.success,
    onTertiary: Colors.white,
    error: AppColors.danger,
    onError: Colors.white,
    surface: bgColor,
    onSurface: textPrimaryColor,
    onSurfaceVariant: textSecondaryColor,
    outline: borderColor,
    outlineVariant: borderSubtleColor,
    surfaceContainerHighest: surfaceHighestColor,
    surfaceContainer: surfaceHighColor,
    surfaceBright: surfaceColor,
  );

  final baseTextTheme = isDark
      ? ThemeData.dark().textTheme
      : ThemeData.light().textTheme;
  final textTheme = baseTextTheme.apply(
    fontFamily: kAppFontFamily,
    fontFamilyFallback: const [kAppFontFamily],
  );

  final scaledTextTheme = textTheme.apply(fontSizeFactor: fontScale);

  return ThemeData(
    colorScheme: colorScheme,
    fontFamily: kAppFontFamily,
    fontFamilyFallback: const [kAppFontFamily],
    visualDensity: cardDensity == 'compact'
        ? VisualDensity.compact
        : VisualDensity.standard,
    textTheme: scaledTextTheme.copyWith(
      bodyLarge: scaledTextTheme.bodyLarge?.copyWith(
        color: textPrimaryColor,
        height: 1.5,
      ),
      bodyMedium: scaledTextTheme.bodyMedium?.copyWith(
        color: textSecondaryColor,
        height: 1.5,
      ),
      titleLarge: scaledTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: textPrimaryColor,
      ),
      titleMedium: scaledTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: textPrimaryColor,
      ),
      titleSmall: scaledTextTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: textPrimaryColor,
      ),
      labelLarge: scaledTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodySmall: scaledTextTheme.bodySmall?.copyWith(
        color: textSecondaryColor,
      ),
    ),
    scaffoldBackgroundColor: bgColor,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      color: surfaceHighColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor,
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    shadowColor: shadowColor,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderSubtleColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 2),
      ),
      filled: true,
      fillColor: surfaceHighColor,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(color: borderColor),
        foregroundColor: textPrimaryColor,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceHighColor,
      selectedColor: accent.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: textPrimaryColor,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      secondaryLabelStyle: TextStyle(
        color: textPrimaryColor,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: borderColor,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: textSecondaryColor,
      indicatorColor: accent,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      dividerColor: borderSubtleColor,
    ),
    dividerTheme: DividerThemeData(
      color: borderSubtleColor,
      thickness: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surfaceColor,
      foregroundColor: textPrimaryColor,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 18,
        color: textPrimaryColor,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceColor,
      indicatorColor: accent.withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: accent,
          );
        }
        return TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
          color: textSecondaryColor,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surfaceColor,
      selectedIconTheme: IconThemeData(color: accent),
      unselectedIconTheme: IconThemeData(
        color: textSecondaryColor,
      ),
      selectedLabelTextStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: accent,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 12,
        color: textSecondaryColor,
      ),
    ),
  );
}
