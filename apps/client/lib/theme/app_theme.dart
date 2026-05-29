import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

ThemeData buildTheme(
  Color primary,
  Color accent,
  ThemeMode mode, {
  double fontScale = 1.0,
  String cardDensity = 'comfortable',
}) {
  final isDark = mode == ThemeMode.dark;

  // 改进稿配色：浅色背景 + 明亮蓝色强调
  final colorScheme = ColorScheme(
    brightness: isDark ? Brightness.dark : Brightness.light,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: isDark
        ? const Color(0xFF1E3A5F)
        : const Color(0xFFD6E4FF),
    onPrimaryContainer: isDark ? Colors.white : const Color(0xFF0D2240),
    secondary: accent,
    onSecondary: Colors.white,
    secondaryContainer: isDark
        ? const Color(0xFF1A3A6E)
        : const Color(0xFFD6E4FF),
    onSecondaryContainer: isDark ? Colors.white : const Color(0xFF001B3E),
    tertiary: AppColors.success,
    onTertiary: Colors.white,
    error: AppColors.danger,
    onError: Colors.white,
    surface: isDark ? AppColors.bgDark : AppColors.bgLight,
    onSurface: isDark ? Colors.white : AppColors.textPrimary,
    onSurfaceVariant: isDark
        ? const Color(0xFFB0BEC5)
        : AppColors.textSecondary,
    outline: isDark
        ? const Color(0xFF37474F)
        : AppColors.borderLight,
    outlineVariant: isDark
        ? const Color(0xFF263238)
        : const Color(0xFFE8E8E8),
    surfaceContainerHighest: isDark
        ? const Color(0xFF1A2332)
        : const Color(0xFFEEF0F2),
    surfaceContainer: isDark
        ? const Color(0xFF15202E)
        : Colors.white,
    surfaceBright: isDark
        ? const Color(0xFF1E2D3D)
        : Colors.white,
  );

  final textTheme = GoogleFonts.interTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  );

  final scaledTextTheme = textTheme.apply(fontSizeFactor: fontScale);

  return ThemeData(
    colorScheme: colorScheme,
    visualDensity: cardDensity == 'compact'
        ? VisualDensity.compact
        : VisualDensity.standard,
    textTheme: scaledTextTheme.copyWith(
      bodyLarge: scaledTextTheme.bodyLarge?.copyWith(
        color: isDark ? Colors.white : AppColors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: scaledTextTheme.bodyMedium?.copyWith(
        color: isDark ? Colors.white70 : AppColors.textSecondary,
        height: 1.5,
      ),
      titleLarge: scaledTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white : AppColors.textPrimary,
      ),
      titleMedium: scaledTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : AppColors.textPrimary,
      ),
      titleSmall: scaledTextTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : AppColors.textPrimary,
      ),
      labelLarge: scaledTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodySmall: scaledTextTheme.bodySmall?.copyWith(
        color: isDark ? Colors.white54 : const Color(0xFF999999),
      ),
    ),
    scaffoldBackgroundColor: colorScheme.surface,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF15202E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 2),
      ),
      filled: true,
      fillColor: isDark
          ? const Color(0xFF1A2332)
          : Colors.white,
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
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(color: colorScheme.outline),
        foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
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
      backgroundColor: isDark
          ? const Color(0xFF1A2332)
          : const Color(0xFFF0F2F5),
      selectedColor: accent.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isDark ? Colors.white : AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      secondaryLabelStyle: TextStyle(
        color: isDark ? Colors.white : AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: isDark
            ? const Color(0xFF37474F)
            : AppColors.borderLight,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: isDark
          ? Colors.white54
          : AppColors.textSecondary,
      indicatorColor: accent,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      dividerColor: colorScheme.outlineVariant,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 18,
        color: isDark ? Colors.white : AppColors.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      indicatorColor: accent.withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: accent,
          );
        }
        return TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
          color: isDark ? Colors.white54 : AppColors.textSecondary,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: isDark
          ? const Color(0xFF0D1117)
          : Colors.white,
      selectedIconTheme: IconThemeData(color: accent),
      unselectedIconTheme: IconThemeData(
        color: isDark ? Colors.white54 : AppColors.textSecondary,
      ),
      selectedLabelTextStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: accent,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 12,
        color: isDark ? Colors.white54 : AppColors.textSecondary,
      ),
    ),
  );
}
