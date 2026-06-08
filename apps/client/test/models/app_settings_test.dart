import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';

void main() {
  group('AppSettings default round-trip', () {
    test('default AppSettings toJson then fromJson preserves values', () {
      const original = AppSettings();
      final json = original.toJson();
      final restored = AppSettings.fromJson(json);

      expect(restored.themeType, AppThemeType.system);
      expect(restored.primaryColor, const Color(0xFF1A2B4A));
      expect(restored.accentColor, const Color(0xFF3078F0));
      expect(restored.language, 'zh');
      expect(restored.recommendStrategy, 'low-score-first');
      expect(restored.currentDomain, 'java');
      expect(restored.compactLayout, false);
      expect(restored.dailyNewCount, 3);
      expect(restored.dailyReviewCount, 6);
      expect(restored.lowScoreWeight, 35);
      expect(restored.overdueWeight, 25);
      expect(restored.highFrequencyWeight, 25);
      expect(restored.pathOrderWeight, 10);
      expect(restored.notPracticedWeight, 5);
      expect(restored.prioritizePrerequisites, true);
      expect(restored.allowSkipLowFrequency, false);
      expect(restored.mockInterviewPreference, 'mixed');
      expect(restored.fontScale, 1.0);
      expect(restored.cardDensity, 'comfortable');
      expect(restored.onboardingCompleted, false);
      expect(restored.sttMode, 'auto');
      expect(restored.sttAiConfigId, isNull);
      expect(restored.onDeviceEngine, 'sense_voice');
      expect(restored.whisperModel, 'base');
      expect(restored.contentEnv, ContentEnv.production);
      expect(restored.customTestContentUrl, isNull);
      expect(restored.customDraftContentUrl, isNull);
      expect(restored.customProdContentUrl, isNull);
      expect(restored.customGithubMirror, isNull);
    });
  });

  group('AppSettings custom values round-trip', () {
    test('fully customized AppSettings round-trips correctly', () {
      const custom = AppSettings(
        themeType: AppThemeType.midnightBlue,
        primaryColor: Color(0xFFFF0000),
        accentColor: Color(0xFF00FF00),
        language: 'en',
        recommendStrategy: 'overdue-first',
        currentDomain: 'golang',
        compactLayout: true,
        dailyNewCount: 10,
        dailyReviewCount: 20,
        lowScoreWeight: 50,
        overdueWeight: 30,
        highFrequencyWeight: 10,
        pathOrderWeight: 5,
        notPracticedWeight: 3,
        prioritizePrerequisites: false,
        allowSkipLowFrequency: true,
        mockInterviewPreference: 'domain-only',
        fontScale: 1.25,
        cardDensity: 'compact',
        onboardingCompleted: true,
        sttMode: 'system',
        sttAiConfigId: 'ai-cfg-001',
        onDeviceEngine: 'whisper',
        whisperModel: 'medium',
        contentEnv: ContentEnv.staging,
        customTestContentUrl: 'https://test.example.com/content',
        customDraftContentUrl: 'https://draft.example.com/content',
        customProdContentUrl: 'https://prod.example.com/content',
        customGithubMirror: 'https://mirror.example.com',
      );

      final json = custom.toJson();
      final restored = AppSettings.fromJson(json);

      expect(restored.themeType, AppThemeType.midnightBlue);
      expect(restored.primaryColor, const Color(0xFFFF0000));
      expect(restored.accentColor, const Color(0xFF00FF00));
      expect(restored.language, 'en');
      expect(restored.recommendStrategy, 'overdue-first');
      expect(restored.currentDomain, 'golang');
      expect(restored.compactLayout, true);
      expect(restored.dailyNewCount, 10);
      expect(restored.dailyReviewCount, 20);
      expect(restored.lowScoreWeight, 50);
      expect(restored.overdueWeight, 30);
      expect(restored.highFrequencyWeight, 10);
      expect(restored.pathOrderWeight, 5);
      expect(restored.notPracticedWeight, 3);
      expect(restored.prioritizePrerequisites, false);
      expect(restored.allowSkipLowFrequency, true);
      expect(restored.mockInterviewPreference, 'domain-only');
      expect(restored.fontScale, 1.25);
      expect(restored.cardDensity, 'compact');
      expect(restored.onboardingCompleted, true);
      expect(restored.sttMode, 'system');
      expect(restored.sttAiConfigId, 'ai-cfg-001');
      expect(restored.onDeviceEngine, 'whisper');
      expect(restored.whisperModel, 'medium');
      expect(restored.contentEnv, ContentEnv.staging);
      expect(restored.customTestContentUrl, 'https://test.example.com/content');
      expect(restored.customDraftContentUrl, 'https://draft.example.com/content');
      expect(restored.customProdContentUrl, 'https://prod.example.com/content');
      expect(restored.customGithubMirror, 'https://mirror.example.com');
    });
  });

  group('field-level serialization', () {
    test('themeType serializes to and from key strings', () {
      for (final type in AppThemeType.values) {
        const base = AppSettings();
        final custom = AppSettings(themeType: type);
        final json = custom.toJson();
        expect(json['themeType'], type.key);

        final restored = AppSettings.fromJson(json);
        expect(restored.themeType, type);
      }
    });

    test('Color fields serialize to int and restore correctly', () {
      const testCases = [
        Color(0x00000000),
        Color(0xFFFFFFFF),
        Color(0xFF1A2B4A),
        Color(0xFFFF0000),
        Color(0x8800FF00),
        Color(0x12345678),
      ];

      for (final color in testCases) {
        final settings = AppSettings(primaryColor: color, accentColor: color);
        final json = settings.toJson();

        expect(json['primaryColor'], isA<int>());
        expect(json['accentColor'], isA<int>());
        expect(json['primaryColor'], color.toARGB32());
        expect(json['accentColor'], color.toARGB32());

        final restored = AppSettings.fromJson(json);
        expect(restored.primaryColor, color);
        expect(restored.accentColor, color);
      }
    });

    test('int fields serialize and restore correctly', () {
      const settings = AppSettings(
        dailyNewCount: 99,
        dailyReviewCount: 88,
        lowScoreWeight: 77,
        overdueWeight: 66,
        highFrequencyWeight: 55,
        pathOrderWeight: 44,
        notPracticedWeight: 33,
      );
      final json = settings.toJson();

      expect(json['dailyNewCount'], 99);
      expect(json['dailyReviewCount'], 88);
      expect(json['lowScoreWeight'], 77);
      expect(json['overdueWeight'], 66);
      expect(json['highFrequencyWeight'], 55);
      expect(json['pathOrderWeight'], 44);
      expect(json['notPracticedWeight'], 33);

      final restored = AppSettings.fromJson(json);
      expect(restored.dailyNewCount, 99);
      expect(restored.dailyReviewCount, 88);
      expect(restored.lowScoreWeight, 77);
      expect(restored.overdueWeight, 66);
      expect(restored.highFrequencyWeight, 55);
      expect(restored.pathOrderWeight, 44);
      expect(restored.notPracticedWeight, 33);
    });

    test('bool fields serialize and restore correctly', () {
      const settings = AppSettings(
        compactLayout: true,
        prioritizePrerequisites: false,
        allowSkipLowFrequency: true,
        onboardingCompleted: true,
      );
      final json = settings.toJson();

      expect(json['compactLayout'], true);
      expect(json['prioritizePrerequisites'], false);
      expect(json['allowSkipLowFrequency'], true);
      expect(json['onboardingCompleted'], true);

      final restored = AppSettings.fromJson(json);
      expect(restored.compactLayout, true);
      expect(restored.prioritizePrerequisites, false);
      expect(restored.allowSkipLowFrequency, true);
      expect(restored.onboardingCompleted, true);
    });

    test('double fontScale serializes and restores correctly', () {
      const settings = AppSettings(fontScale: 1.5);
      final json = settings.toJson();

      expect(json['fontScale'], 1.5);

      final restored = AppSettings.fromJson(json);
      expect(restored.fontScale, 1.5);
    });

    test('String fields serialize and restore correctly', () {
      const settings = AppSettings(
        language: 'ja',
        recommendStrategy: 'mixed',
        currentDomain: 'python',
        mockInterviewPreference: 'mixed',
        cardDensity: 'spacious',
        sttMode: 'fixed_ai_config',
        onDeviceEngine: 'paraformer',
        whisperModel: 'tiny',
      );
      final json = settings.toJson();

      expect(json['language'], 'ja');
      expect(json['recommendStrategy'], 'mixed');
      expect(json['currentDomain'], 'python');
      expect(json['mockInterviewPreference'], 'mixed');
      expect(json['cardDensity'], 'spacious');
      expect(json['sttMode'], 'fixed_ai_config');
      expect(json['onDeviceEngine'], 'paraformer');
      expect(json['whisperModel'], 'tiny');

      final restored = AppSettings.fromJson(json);
      expect(restored.language, 'ja');
      expect(restored.recommendStrategy, 'mixed');
      expect(restored.currentDomain, 'python');
      expect(restored.mockInterviewPreference, 'mixed');
      expect(restored.cardDensity, 'spacious');
      expect(restored.sttMode, 'fixed_ai_config');
      expect(restored.onDeviceEngine, 'paraformer');
      expect(restored.whisperModel, 'tiny');
    });

    test('contentEnv serializes to key string and restores from key', () {
      for (final env in ContentEnv.values) {
        final settings = AppSettings(contentEnv: env);
        final json = settings.toJson();
        expect(json['contentEnv'], env.key);

        final restored = AppSettings.fromJson(json);
        expect(restored.contentEnv, env);
      }
    });
  });

  group('nullable fields', () {
    test('nullable fields default to null', () {
      const settings = AppSettings();
      final json = settings.toJson();

      expect(json['sttAiConfigId'], isNull);
      expect(json['customTestContentUrl'], isNull);
      expect(json['customDraftContentUrl'], isNull);
      expect(json['customProdContentUrl'], isNull);
      expect(json['customGithubMirror'], isNull);

      final restored = AppSettings.fromJson(json);
      expect(restored.sttAiConfigId, isNull);
      expect(restored.customTestContentUrl, isNull);
      expect(restored.customDraftContentUrl, isNull);
      expect(restored.customProdContentUrl, isNull);
      expect(restored.customGithubMirror, isNull);
    });

    test('nullable fields round-trip non-null values', () {
      const settings = AppSettings(
        sttAiConfigId: 'cfg-xyz',
        customTestContentUrl: 'https://test.url',
        customDraftContentUrl: 'https://draft.url',
        customProdContentUrl: 'https://prod.url',
        customGithubMirror: 'https://gh-mirror.url',
      );
      final json = settings.toJson();

      expect(json['sttAiConfigId'], 'cfg-xyz');
      expect(json['customTestContentUrl'], 'https://test.url');
      expect(json['customDraftContentUrl'], 'https://draft.url');
      expect(json['customProdContentUrl'], 'https://prod.url');
      expect(json['customGithubMirror'], 'https://gh-mirror.url');

      final restored = AppSettings.fromJson(json);
      expect(restored.sttAiConfigId, 'cfg-xyz');
      expect(restored.customTestContentUrl, 'https://test.url');
      expect(restored.customDraftContentUrl, 'https://draft.url');
      expect(restored.customProdContentUrl, 'https://prod.url');
      expect(restored.customGithubMirror, 'https://gh-mirror.url');
    });

    test('nullable fields can be set to empty string and restore as empty string', () {
      const settings = AppSettings(
        customTestContentUrl: '',
        customGithubMirror: '',
      );
      final json = settings.toJson();

      expect(json['customTestContentUrl'], '');
      expect(json['customGithubMirror'], '');

      final restored = AppSettings.fromJson(json);
      expect(restored.customTestContentUrl, '');
      expect(restored.customGithubMirror, '');
    });

    test('fromJson with missing nullable keys returns null', () {
      final json = <String, dynamic>{};
      final restored = AppSettings.fromJson(json);

      expect(restored.sttAiConfigId, isNull);
      expect(restored.customTestContentUrl, isNull);
      expect(restored.customDraftContentUrl, isNull);
      expect(restored.customProdContentUrl, isNull);
      expect(restored.customGithubMirror, isNull);
    });

    test('fromJson with explicit null for nullable keys returns null', () {
      final json = <String, dynamic>{
        'sttAiConfigId': null,
        'customTestContentUrl': null,
        'customDraftContentUrl': null,
        'customProdContentUrl': null,
        'customGithubMirror': null,
      };
      final restored = AppSettings.fromJson(json);

      expect(restored.sttAiConfigId, isNull);
      expect(restored.customTestContentUrl, isNull);
      expect(restored.customDraftContentUrl, isNull);
      expect(restored.customProdContentUrl, isNull);
      expect(restored.customGithubMirror, isNull);
    });
  });

  group('enum serialization', () {
    test('all AppThemeType values serialize and deserialize correctly', () {
      for (final type in AppThemeType.values) {
        final json = <String, dynamic>{'themeType': type.key};
        final restored = AppSettings.fromJson(json);
        expect(restored.themeType, type);
      }
    });

    test('all ContentEnv values serialize and deserialize correctly', () {
      for (final env in ContentEnv.values) {
        final json = <String, dynamic>{'contentEnv': env.key};
        final restored = AppSettings.fromJson(json);
        expect(restored.contentEnv, env);
      }
    });

    test('fromJson handles legacy themeMode field for compatibility', () {
      final json = <String, dynamic>{'themeMode': 'ThemeMode.dark'};
      final restored = AppSettings.fromJson(json);
      expect(restored.themeType, AppThemeType.qualityBlack);

      final json2 = <String, dynamic>{'themeMode': 'ThemeMode.light'};
      final restored2 = AppSettings.fromJson(json2);
      expect(restored2.themeType, AppThemeType.elegantWhite);

      final json3 = <String, dynamic>{'themeMode': 'ThemeMode.system'};
      final restored3 = AppSettings.fromJson(json3);
      expect(restored3.themeType, AppThemeType.system);

      final json4 = <String, dynamic>{'themeMode': 'dark'};
      final restored4 = AppSettings.fromJson(json4);
      expect(restored4.themeType, AppThemeType.qualityBlack);

      final json5 = <String, dynamic>{'themeMode': 'light'};
      final restored5 = AppSettings.fromJson(json5);
      expect(restored5.themeType, AppThemeType.elegantWhite);

      final json6 = <String, dynamic>{'themeMode': 'system'};
      final restored6 = AppSettings.fromJson(json6);
      expect(restored6.themeType, AppThemeType.system);
    });

    test('fromJson with themeType takes priority over legacy themeMode', () {
      final json = <String, dynamic>{
        'themeType': 'elegantWhite',
        'themeMode': 'dark',
      };
      final restored = AppSettings.fromJson(json);
      expect(restored.themeType, AppThemeType.elegantWhite);
    });

    test('fromJson with unknown key falls back to default', () {
      final json = <String, dynamic>{'themeType': 'unknown_theme'};
      final restored = AppSettings.fromJson(json);
      expect(restored.themeType, AppThemeType.system);

      final json2 = <String, dynamic>{'contentEnv': 'unknown_env'};
      final restored2 = AppSettings.fromJson(json2);
      expect(restored2.contentEnv, ContentEnv.production);
    });

    test('fromJson with test key maps to contentEnv staging', () {
      final json = <String, dynamic>{'contentEnv': 'test'};
      final restored = AppSettings.fromJson(json);
      expect(restored.contentEnv, ContentEnv.staging);
    });
  });

  group('Color serialization', () {
    test('Color with full opacity round-trips', () {
      const settings = AppSettings(
        primaryColor: Color(0xFFFFFFFF),
        accentColor: Color(0xFF000000),
      );
      final json = settings.toJson();
      expect(json['primaryColor'], 0xFFFFFFFF);
      expect(json['accentColor'], 0xFF000000);

      final restored = AppSettings.fromJson(json);
      expect(restored.primaryColor, const Color(0xFFFFFFFF));
      expect(restored.accentColor, const Color(0xFF000000));
    });

    test('Color with transparency round-trips', () {
      const settings = AppSettings(
        primaryColor: Color(0x800000FF),
        accentColor: Color(0x40FF0000),
      );
      final json = settings.toJson();
      expect(json['primaryColor'], 0x800000FF);
      expect(json['accentColor'], 0x40FF0000);

      final restored = AppSettings.fromJson(json);
      expect(restored.primaryColor, const Color(0x800000FF));
      expect(restored.accentColor, const Color(0x40FF0000));
    });

    test('fromJson with null Color falls back to default', () {
      final json = <String, dynamic>{};
      final restored = AppSettings.fromJson(json);
      expect(restored.primaryColor, const Color(0xFF1A2B4A));
      expect(restored.accentColor, const Color(0xFF3078F0));
    });

    test('Color values appear in JSON as int, not as Color object', () {
      const settings = AppSettings(
        primaryColor: Color(0xFF123456),
        accentColor: Color(0xFF789ABC),
      );
      final json = settings.toJson();
      expect(json['primaryColor'], isA<int>());
      expect(json['accentColor'], isA<int>());
    });
  });

  group('copyWith', () {
    test('copyWith creates a modified copy without changing original', () {
      const original = AppSettings(
        themeType: AppThemeType.system,
        dailyNewCount: 3,
        language: 'zh',
      );

      final modified = original.copyWith(
        themeType: AppThemeType.qualityBlack,
        dailyNewCount: 50,
      );

      // Modified has new values
      expect(modified.themeType, AppThemeType.qualityBlack);
      expect(modified.dailyNewCount, 50);

      // Original unchanged
      expect(original.themeType, AppThemeType.system);
      expect(original.dailyNewCount, 3);
      expect(original.language, 'zh');
    });

    test('copyWith preserves unmodified fields', () {
      const original = AppSettings(
        themeType: AppThemeType.elegantWhite,
        language: 'en',
        dailyNewCount: 10,
        fontScale: 1.5,
      );

      final modified = original.copyWith(language: 'ja');

      expect(modified.language, 'ja');
      expect(modified.themeType, AppThemeType.elegantWhite);
      expect(modified.dailyNewCount, 10);
      expect(modified.fontScale, 1.5);
    });

    test('copyWith with non-null sttAiConfigId replaces null', () {
      const original = AppSettings();
      expect(original.sttAiConfigId, isNull);

      final modified = original.copyWith(sttAiConfigId: 'new-cfg');
      expect(modified.sttAiConfigId, 'new-cfg');
    });

    test('copyWith with null sttAiConfigId clears existing value', () {
      const original = AppSettings(sttAiConfigId: 'old-cfg');
      expect(original.sttAiConfigId, 'old-cfg');

      final modified = original.copyWith(sttAiConfigId: null);
      expect(modified.sttAiConfigId, isNull);
    });

    test('copyWith with non-null nullable string replaces null', () {
      const original = AppSettings();
      expect(original.customTestContentUrl, isNull);

      final modified = original.copyWith(customTestContentUrl: 'https://new.url');
      expect(modified.customTestContentUrl, 'https://new.url');
    });

    test('copyWith with null nullable string clears existing value', () {
      const original = AppSettings(customGithubMirror: 'https://old.mirror');
      expect(original.customGithubMirror, 'https://old.mirror');

      final modified = original.copyWith(customGithubMirror: null);
      expect(modified.customGithubMirror, isNull);
    });
  });

  group('toJson key presence', () {
    test('toJson contains all expected keys', () {
      const settings = AppSettings();
      final json = settings.toJson();

      expect(json, containsPair('themeType', 'system'));
      expect(json, containsPair('primaryColor', 0xFF1A2B4A));
      expect(json, containsPair('accentColor', 0xFF3078F0));
      expect(json, containsPair('language', 'zh'));
      expect(json, containsPair('recommendStrategy', 'low-score-first'));
      expect(json, containsPair('currentDomain', 'java'));
      expect(json, containsPair('compactLayout', false));
      expect(json, containsPair('dailyNewCount', 3));
      expect(json, containsPair('dailyReviewCount', 6));
      expect(json, containsPair('lowScoreWeight', 35));
      expect(json, containsPair('overdueWeight', 25));
      expect(json, containsPair('highFrequencyWeight', 25));
      expect(json, containsPair('pathOrderWeight', 10));
      expect(json, containsPair('notPracticedWeight', 5));
      expect(json, containsPair('prioritizePrerequisites', true));
      expect(json, containsPair('allowSkipLowFrequency', false));
      expect(json, containsPair('mockInterviewPreference', 'mixed'));
      expect(json, containsPair('fontScale', 1.0));
      expect(json, containsPair('cardDensity', 'comfortable'));
      expect(json, containsPair('onboardingCompleted', false));
      expect(json, containsPair('sttMode', 'auto'));
      expect(json, containsPair('onDeviceEngine', 'sense_voice'));
      expect(json, containsPair('whisperModel', 'base'));
      expect(json, containsPair('contentEnv', 'production'));
      expect(json.containsKey('sttAiConfigId'), isTrue);
      expect(json.containsKey('customTestContentUrl'), isTrue);
      expect(json.containsKey('customDraftContentUrl'), isTrue);
      expect(json.containsKey('customProdContentUrl'), isTrue);
      expect(json.containsKey('customGithubMirror'), isTrue);
    });

    test('toJson does not include unexpected keys', () {
      const settings = AppSettings();
      final json = settings.toJson();

      const expectedKeys = <String>{
        'themeType', 'primaryColor', 'accentColor', 'language',
        'recommendStrategy', 'currentDomain', 'compactLayout',
        'dailyNewCount', 'dailyReviewCount', 'lowScoreWeight',
        'overdueWeight', 'highFrequencyWeight', 'pathOrderWeight',
        'notPracticedWeight', 'prioritizePrerequisites',
        'allowSkipLowFrequency', 'mockInterviewPreference', 'fontScale',
        'cardDensity', 'onboardingCompleted', 'sttMode', 'sttAiConfigId',
        'onDeviceEngine', 'whisperModel', 'contentEnv',
        'customTestContentUrl', 'customDraftContentUrl',
        'customProdContentUrl', 'customGithubMirror',
      };
      expect(json.keys, unorderedEquals(expectedKeys));
    });
  });
}
