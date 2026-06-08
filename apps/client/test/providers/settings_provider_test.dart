import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/theme_provider.dart';
import 'package:mianshi_zhilian/services/data_sync_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDataSync extends DataSyncService {
  _MockDataSync() : super(StorageService());
  SyncResult? lastResult;
  @override
  Future<SyncResult> syncNow([SyncSettings? s]) async {
    return lastResult ?? SyncResult.success('sync_success');
  }
}

void main() {
  group('SettingsProvider', () {
    late StorageService storage;
    late _MockDataSync dataSync;
    late ThemeProvider themeProvider;
    late SettingsProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      dataSync = _MockDataSync();
      themeProvider = ThemeProvider();
      provider = SettingsProvider(storage, dataSync, themeProvider);
    });

    test('initial state uses defaults and isLoading is false', () {
      expect(provider.settings.themeType, AppThemeType.system);
      expect(provider.settings.language, 'zh');
      expect(provider.settings.recommendStrategy, 'low-score-first');
      expect(provider.settings.currentDomain, 'java');
      expect(provider.settings.fontScale, 1.0);
      expect(provider.settings.cardDensity, 'comfortable');
      expect(provider.settings.onboardingCompleted, false);
      expect(provider.isLoading, false);
    });

    test('loadSettings with empty storage loads defaults and notifies', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.loadSettings();

      expect(provider.settings.themeType, AppThemeType.system);
      expect(provider.isLoading, false);
      expect(notifyCount, 2);
    });

    test('loadSettings triggers whisper migration when old data exists',
        () async {
      SharedPreferences.setMockInitialValues({
        'settings': '''
{"sttMode":"auto","whisperBaseUrl":"https://old-whisper.example.com","whisperApiKey":"old-key","whisperModel":"whisper-1"}
''',
      });
      storage = StorageService();
      provider = SettingsProvider(storage, dataSync, themeProvider);

      await provider.loadSettings();

      final aiConfigs = await storage.loadAiConfigs();
      expect(aiConfigs, hasLength(1));
      expect(aiConfigs[0].baseUrl, 'https://old-whisper.example.com');
      expect(aiConfigs[0].audioMode, AiAudioMode.transcriptionEndpoint);
    });

    test('loadSettings converts whisper sttMode to auto', () async {
      SharedPreferences.setMockInitialValues({
        'settings': '''
{"sttMode":"whisper"}
''',
      });
      storage = StorageService();
      provider = SettingsProvider(storage, dataSync, themeProvider);

      await provider.loadSettings();

      expect(provider.settings.sttMode, 'auto');
    });

    test('updateSettings saves and notifies themeProvider', () async {
      final newSettings = const AppSettings(
        themeType: AppThemeType.midnightBlue,
        primaryColor: Color(0xFF112233),
        language: 'en',
      );
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      int themeNotifyCount = 0;
      themeProvider.addListener(() => themeNotifyCount++);

      await provider.updateSettings(newSettings);

      expect(provider.settings.themeType, AppThemeType.midnightBlue);
      expect(provider.settings.primaryColor, const Color(0xFF112233));
      expect(provider.settings.language, 'en');
      expect(notifyCount, 1);
      expect(themeNotifyCount, 1);
    });

    test('setThemeType updates settings and calls themeProvider', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      int themeNotifyCount = 0;
      themeProvider.addListener(() => themeNotifyCount++);

      await provider.setThemeType(AppThemeType.qualityBlack);

      expect(provider.settings.themeType, AppThemeType.qualityBlack);
      expect(themeProvider.themeType, AppThemeType.qualityBlack);
      expect(notifyCount, 1);
      expect(themeNotifyCount, 1);
    });

    test('setPrimaryColor updates settings and calls themeProvider', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      int themeNotifyCount = 0;
      themeProvider.addListener(() => themeNotifyCount++);

      await provider.setPrimaryColor(const Color(0xFFAABBCC));

      expect(provider.settings.primaryColor, const Color(0xFFAABBCC));
      expect(themeProvider.primaryColor, const Color(0xFFAABBCC));
      expect(notifyCount, 1);
      expect(themeNotifyCount, 1);
    });

    test('setAccentColor updates settings and calls themeProvider', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.setAccentColor(const Color(0xFFDDEEFF));

      expect(provider.settings.accentColor, const Color(0xFFDDEEFF));
      expect(themeProvider.accentColor, const Color(0xFFDDEEFF));
      expect(notifyCount, 1);
    });

    test('setLanguage updates settings and calls themeProvider.updateLanguage',
        () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      int themeNotifyCount = 0;
      themeProvider.addListener(() => themeNotifyCount++);

      await provider.setLanguage('en');

      expect(provider.settings.language, 'en');
      expect(themeProvider.language, 'en');
      expect(notifyCount, 1);
      expect(themeNotifyCount, 1);
    });

    test('setRecommendStrategy updates settings without themeProvider call',
        () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      int themeNotifyCount = 0;
      themeProvider.addListener(() => themeNotifyCount++);

      await provider.setRecommendStrategy('smart');

      expect(provider.settings.recommendStrategy, 'smart');
      expect(notifyCount, 1);
      expect(themeNotifyCount, 0);
    });

    test('setCurrentDomain updates settings and notifies', () async {
      await provider.setCurrentDomain('go');

      expect(provider.settings.currentDomain, 'go');
    });

    test('setContentEnv updates settings and notifies', () async {
      await provider.setContentEnv(ContentEnv.staging);

      expect(provider.settings.contentEnv, ContentEnv.staging);
    });

    test('setCustomGithubMirror sets and clears value', () async {
      await provider.setCustomGithubMirror('https://mirror.example.com');
      expect(provider.settings.customGithubMirror,
          'https://mirror.example.com');

      await provider.setCustomGithubMirror('');
      expect(provider.settings.customGithubMirror, null);
    });

    test('completeOnboarding sets onboardingCompleted to true', () async {
      expect(provider.settings.onboardingCompleted, false);

      await provider.completeOnboarding();

      expect(provider.settings.onboardingCompleted, true);
    });

    test('resetOnboarding sets onboardingCompleted to false', () async {
      await provider.completeOnboarding();
      expect(provider.settings.onboardingCompleted, true);

      await provider.resetOnboarding();

      expect(provider.settings.onboardingCompleted, false);
    });

    test('updateFontScale updates settings and calls themeProvider', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      int themeNotifyCount = 0;
      themeProvider.addListener(() => themeNotifyCount++);

      await provider.updateFontScale(1.25);

      expect(provider.settings.fontScale, 1.25);
      expect(themeProvider.fontScale, 1.25);
      expect(notifyCount, 1);
      expect(themeNotifyCount, 1);
    });

    test('updateDensity updates settings and calls themeProvider', () async {
      await provider.updateDensity('compact');

      expect(provider.settings.cardDensity, 'compact');
      expect(themeProvider.cardDensity, 'compact');
    });

    test('syncData delegates to DataSyncService.syncNow for automatic methods',
        () async {
      dataSync.lastResult = SyncResult.success('sync_merged_success');

      final result = await provider.syncData(const SyncSettings(
        method: 'webdav',
        webDavUrl: 'https://dav.example.com',
        webDavUsername: 'user',
        webDavPassword: 'pass',
      ));

      expect(result, 'sync_merged_success');
    });

    test('syncData returns local_mode_data_saved for local method', () async {
      final result = await provider.syncData(const SyncSettings(
        method: 'local',
      ));

      expect(result, 'local_mode_data_saved');
    });

    test('syncData returns third_party_sync_coming_soon for baidu method',
        () async {
      final result = await provider.syncData(const SyncSettings(
        method: 'baidu',
      ));

      expect(result, 'third_party_sync_coming_soon');
    });

    test('syncData returns cloud_sync_unavailable for unknown method',
        () async {
      final result = await provider.syncData(const SyncSettings(
        method: 'unknown',
      ));

      expect(result, 'cloud_sync_unavailable');
    });
  });
}
