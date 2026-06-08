import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/models/app_settings.dart';
import '../../lib/providers/theme_provider.dart';

void main() {
  group('ThemeProvider', () {
    late ThemeProvider provider;

    setUp(() {
      provider = ThemeProvider();
    });

    test('initial values match defaults', () {
      expect(provider.themeType, AppThemeType.system);
      expect(provider.primaryColor, const Color(0xFF1A2B4A));
      expect(provider.accentColor, const Color(0xFF3078F0));
      expect(provider.fontScale, 1.0);
      expect(provider.cardDensity, 'comfortable');
      expect(provider.language, 'zh');
    });

    test('updateFromSettings changes all fields', () {
      final settings = const AppSettings(
        themeType: AppThemeType.midnightBlue,
        primaryColor: Color(0xFF112233),
        accentColor: Color(0xFF445566),
        fontScale: 1.25,
        cardDensity: 'compact',
        language: 'en',
      );

      provider.updateFromSettings(settings);

      expect(provider.themeType, AppThemeType.midnightBlue);
      expect(provider.primaryColor, const Color(0xFF112233));
      expect(provider.accentColor, const Color(0xFF445566));
      expect(provider.fontScale, 1.25);
      expect(provider.cardDensity, 'compact');
      expect(provider.language, 'en');
    });

    test('updateFromSettings does NOT notify when only language changes', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      final settings = const AppSettings().copyWith(language: 'en');
      provider.updateFromSettings(settings);

      expect(provider.language, 'en');
      expect(notifyCount, 0,
          reason: 'should not notify when no theme-relevant field changed');
    });

    test('updateFromSettings DOES notify when a theme field changes', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      final settings = const AppSettings().copyWith(primaryColor: Color(0xFF112233));
      provider.updateFromSettings(settings);

      expect(notifyCount, 1,
          reason: 'should notify when primaryColor changed');
    });

    test('updateLanguage changes language and notifies', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.updateLanguage('en');

      expect(provider.language, 'en');
      expect(notifyCount, 1);
    });

    test('updateLanguage with same value does NOT notify', () {
      expect(provider.language, 'zh');

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.updateLanguage('zh');

      expect(notifyCount, 0,
          reason: 'should not notify when language is unchanged');
    });
  });
}
