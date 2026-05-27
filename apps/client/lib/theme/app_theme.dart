import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

ThemeData buildTheme(Color primary, Color accent, ThemeMode mode) {
  final isDark = mode == ThemeMode.dark;
  final seed = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: isDark ? Brightness.dark : Brightness.light,
  );

  final colorScheme = seed.copyWith(
    primary: primary,
    onPrimary: Colors.white,
    secondary: accent,
    onSecondary: AppColors.bgDark,
    secondaryContainer: isDark
        ? const Color(0xFF073A4A)
        : const Color(0xFFD7F7FF),
    onSecondaryContainer: isDark ? Colors.white : const Color(0xFF003443),
    surface: isDark ? AppColors.bgDark : AppColors.bgLight,
  );

  final textTheme = GoogleFonts.interTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  );

  return ThemeData(
    colorScheme: colorScheme,
    textTheme: textTheme.copyWith(
      bodyLarge: textTheme.bodyLarge,
      bodyMedium: textTheme.bodyMedium,
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    scaffoldBackgroundColor: colorScheme.surface,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: colorScheme.secondary, width: 1.2),
        foregroundColor: colorScheme.secondary,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: isDark ? Colors.white : colorScheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark
          ? const Color(0xFF10243A)
          : const Color(0xFFEAF2FA),
      selectedColor: colorScheme.secondaryContainer,
      labelStyle: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF102033),
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF102033),
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: isDark ? const Color(0xFF4D6075) : const Color(0xFFC3CEDA),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: isDark ? Colors.white : colorScheme.primary,
      unselectedLabelColor: isDark
          ? const Color(0xFFB9C6D8)
          : const Color(0xFF526173),
      indicatorColor: colorScheme.secondary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w900),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
    ),
  );
}
