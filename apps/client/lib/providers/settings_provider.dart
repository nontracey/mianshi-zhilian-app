import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../models/user_progress.dart';
import '../services/data_sync_service.dart';
import '../services/storage_service.dart';
import '../services/whisper_migration_helper.dart';
import 'theme_provider.dart';

// Web 端下载（条件导入）
import 'web_download/web_download_stub.dart'
    if (dart.library.html) 'web_download/web_download_web.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  final DataSyncService _dataSync;
  final ThemeProvider _themeProvider;

  SettingsProvider(this._storage, this._dataSync, this._themeProvider);

  AppSettings _settings = const AppSettings();
  bool _isLoading = false;

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    _settings = await _storage.loadSettings();
    _settings = _applyPlatformDefaults(_settings);

    await WhisperMigrationHelper.migrateIfNeeded(_storage, source: 'SettingsProvider');

    _isLoading = false;
    notifyListeners();
  }

  AppSettings _applyPlatformDefaults(AppSettings s) {
    if (s.sttMode == 'whisper') return s.copyWith(sttMode: 'auto');
    return s;
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await _storage.saveSettings(_settings);
    _themeProvider.updateFromSettings(_settings);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _settings = _settings.copyWith(onboardingCompleted: true);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> resetOnboarding() async {
    _settings = _settings.copyWith(onboardingCompleted: false);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    // 兼容旧代码，转换为 AppThemeType
    AppThemeType themeType;
    switch (mode) {
      case ThemeMode.light:
        themeType = AppThemeType.elegantWhite;
        break;
      case ThemeMode.dark:
        themeType = AppThemeType.qualityBlack;
        break;
      case ThemeMode.system:
        themeType = AppThemeType.system;
        break;
    }
    _settings = _settings.copyWith(themeType: themeType);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  /// 设置主题类型
  Future<void> setThemeType(AppThemeType themeType) async {
    _settings = _settings.copyWith(themeType: themeType);
    await _storage.saveSettings(_settings);
    _themeProvider.updateFromSettings(_settings);
    notifyListeners();
  }

  Future<void> setPrimaryColor(Color color) async {
    _settings = _settings.copyWith(primaryColor: color);
    await _storage.saveSettings(_settings);
    _themeProvider.updateFromSettings(_settings);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    _settings = _settings.copyWith(accentColor: color);
    await _storage.saveSettings(_settings);
    _themeProvider.updateFromSettings(_settings);
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    _settings = _settings.copyWith(language: language);
    await _storage.saveSettings(_settings);
    _themeProvider.updateLanguage(language);
    notifyListeners();
  }

  Future<void> setRecommendStrategy(String strategy) async {
    _settings = _settings.copyWith(recommendStrategy: strategy);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setCurrentDomain(String domainId) async {
    _settings = _settings.copyWith(currentDomain: domainId);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  /// 切换知识源环境（测试版 / 发布版）
  Future<void> setContentEnv(ContentEnv env) async {
    _settings = _settings.copyWith(contentEnv: env);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  /// 设置自定义测试版内容 URL（传空字符串恢复默认）
  Future<void> setCustomTestContentUrl(String? url) async {
    _settings = _settings.copyWith(
      customTestContentUrl: (url != null && url.isEmpty) ? null : url,
    );
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  /// 设置自定义草稿版内容 URL（传空字符串恢复默认）
  Future<void> setCustomDraftContentUrl(String? url) async {
    _settings = _settings.copyWith(
      customDraftContentUrl: (url != null && url.isEmpty) ? null : url,
    );
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  /// 设置自定义发布版内容 URL（传空字符串恢复默认）
  Future<void> setCustomProdContentUrl(String? url) async {
    _settings = _settings.copyWith(
      customProdContentUrl: (url != null && url.isEmpty) ? null : url,
    );
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  /// 设置自定义 GitHub 镜像站前缀（传空字符串恢复默认）
  Future<void> setCustomGithubMirror(String? url) async {
    _settings = _settings.copyWith(
      customGithubMirror: (url != null && url.isEmpty) ? null : url,
    );
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  // Convenience aliases used by profile page
  Future<void> updateThemeMode(ThemeMode mode) async => setThemeMode(mode);
  Future<void> updatePrimaryColor(Color color) async => setPrimaryColor(color);
  Future<void> updateAccentColor(Color color) async => setAccentColor(color);
  Future<void> updateLanguage(String lang) async => setLanguage(lang);
  Future<void> updateRecommendStrategy(String strategy) async =>
      setRecommendStrategy(strategy);

  Future<void> updateFontScale(double scale) async {
    _settings = _settings.copyWith(fontScale: scale);
    await _storage.saveSettings(_settings);
    _themeProvider.updateFromSettings(_settings);
    notifyListeners();
  }

  Future<void> updateDensity(String density) async {
    _settings = _settings.copyWith(cardDensity: density);
    await _storage.saveSettings(_settings);
    _themeProvider.updateFromSettings(_settings);
    notifyListeners();
  }

  Future<String> syncData([SyncSettings? syncSettings]) async {
    await _storage.recordAnalyticsFeature('manual_sync');
    try {
      final settings = syncSettings ?? const SyncSettings();
      late final String resultKey;
      if (settings.method == 'local') {
        resultKey = 'local_mode_data_saved';
      } else if (settings.method == 'file') {
        await exportData();
        resultKey = 'local_export_generated';
      } else if (settings.isAutomaticMethod) {
        final result = await _dataSync.syncNow(settings);
        resultKey = result.l10nKey;
      } else if ([
        'baidu',
        'quark',
        'aliyun',
        'onedrive',
      ].contains(settings.method)) {
        resultKey = 'third_party_sync_coming_soon';
      } else {
        resultKey = 'cloud_sync_unavailable';
      }

      await _storage.recordAnalyticsFeature(
        _isSuccessfulSyncResult(resultKey) ? 'sync_success' : 'sync_failed',
      );
      return resultKey;
    } catch (_) {
      await _storage.recordAnalyticsFeature('sync_failed');
      rethrow;
    }
  }

  bool _isSuccessfulSyncResult(String resultKey) {
    return {
      'local_mode_data_saved',
      'local_export_generated',
      'sync_success',
      'sync_upload_success',
      'sync_download_success',
      'sync_merged_success',
      'sync_no_changes',
    }.contains(resultKey);
  }

  Future<void> exportData() async {
    try {
      final syncSettings = await _storage.loadSyncSettings();
      final data = await _storage.exportSyncPackage(syncSettings);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final fileName =
          'mianshi-zhilian-export-${DateTime.now().millisecondsSinceEpoch}.json';

      if (kIsWeb) {
        downloadFile(fileName, jsonStr);
      } else {
        await FilePicker.platform.saveFile(
          dialogTitle: L10n.get('data_export', _settings.language),
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(jsonStr)),
        );
      }

      debugPrint('Data exported: $fileName');
    } catch (e) {
      debugPrint('Export failed: $e');
    }
  }

  Future<SyncResult> importData(String content) async {
    try {
      final decoded = json.decode(content);
      if (decoded is! Map<String, dynamic> ||
          decoded['app'] != 'mianshi-zhilian' ||
          decoded['data'] is! Map<String, dynamic>) {
        return SyncResult.failure('import_invalid_file');
      }
      await _storage.importSyncPackage(decoded);
      await _storage.clearSyncDirty();
      await loadSettings();
      return SyncResult.success('import_success');
    } catch (e) {
      return SyncResult.failure('import_failed', {'error': '$e'});
    }
  }

  /// 从当前远端同步渠道恢复数据
  Future<SyncResult> restoreFromRemote([SyncSettings? syncSettings]) async {
    final settings = syncSettings ?? const SyncSettings();
    return _dataSync.restoreFromRemote(settings);
  }

  /// 测试当前同步渠道连接
  Future<SyncResult> testSyncConnection([SyncSettings? syncSettings]) async {
    final settings = syncSettings ?? const SyncSettings();
    return _dataSync.testConnection(settings);
  }

  /// 获取上次同步时间
  Future<DateTime?> getLastSyncTime() => _storage.getLastSyncTime();
}
