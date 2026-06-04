import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../models/ai_config.dart';
import '../models/app_settings.dart';
import '../models/user_progress.dart';
import '../services/data_sync_service.dart';
import '../services/storage_service.dart';

// Web 端下载（条件导入）
import 'web_download/web_download_stub.dart'
    if (dart.library.html) 'web_download/web_download_web.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  final DataSyncService _dataSync;

  SettingsProvider(this._storage, this._dataSync);

  AppSettings _settings = const AppSettings();
  bool _isLoading = false;

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    _settings = await _storage.loadSettings();
    _settings = _applyPlatformDefaults(_settings);

    // 迁移旧版 Whisper API 配置 → AiConfig
    await _migrateOldWhisperConfig();

    _isLoading = false;
    notifyListeners();
  }

  /// 检测并迁移旧版 AppSettings 中的 whisperBaseUrl/whisperApiKey/whisperModel
  /// 到新的 AiConfig 体系，避免旧用户升级后配置静默丢失
  Future<void> _migrateOldWhisperConfig() async {
    try {
      final rawData = await _storage.load('settings');
      if (rawData == null) return;
      final rawJson = rawData as Map<String, dynamic>;
      final oldBaseUrl = rawJson['whisperBaseUrl'] as String?;
      final oldApiKey = rawJson['whisperApiKey'] as String?;
      final oldModel = rawJson['whisperModel'] as String?;
      if (oldBaseUrl == null || oldBaseUrl.isEmpty) return;

      // 检查是否已迁移过（通过标记或已有同名配置）
      final existingConfigs = await _storage.loadAiConfigs();
      final alreadyMigrated = existingConfigs.any(
        (c) =>
            c.baseUrl == oldBaseUrl &&
            c.name.contains(L10n.get('whisper_default_name', 'zh')),
      );
      if (alreadyMigrated) return;

      // 创建一个新 AiConfig
      final migratedConfig = AiConfig(
        id: 'whisper_migrated_${DateTime.now().millisecondsSinceEpoch}',
        name: oldModel != null && oldModel.isNotEmpty
            ? 'Whisper ($oldModel)'
            : L10n.get('whisper_default_name', 'zh'),
        baseUrl: oldBaseUrl,
        apiKey: oldApiKey ?? '',
        model: oldModel ?? 'whisper-1',
        isDefault: existingConfigs.isEmpty,
        enabled: true,
        supportsTextInput: false,
        supportsImageInput: false,
        supportsAudioInput: true,
        supportsMultimodal: false,
        supportsStreaming: true,
        audioMode: AiAudioMode.transcriptionEndpoint,
        usageTags: ['stt'],
        capabilityTests: {
          AiCapability.audio.key: CapabilityTestRecord(
            state: CapabilityTestState.untested,
            testedAt: DateTime.now(),
            message: 'migrated_from_old_settings',
          ),
        },
      );
      final updatedConfigs = [...existingConfigs, migratedConfig];
      await _storage.saveAiConfigs(updatedConfigs);

      // 清除旧 whisper 字段（可选 — 不破坏其他设置）
      // 但不对 settings 本身做写回，因为 fromJson 已忽略这些字段
      debugPrint('SettingsProvider: migrated old whisper config to AiConfig');
    } catch (e) {
      debugPrint('SettingsProvider: whisper migration failed: $e');
    }
  }

  AppSettings _applyPlatformDefaults(AppSettings s) {
    if (s.sttMode == 'whisper') return s.copyWith(sttMode: 'auto');
    if (s.sttMode == 'whisper_kit' &&
        (kIsWeb || defaultTargetPlatform == TargetPlatform.macOS)) {
      return s.copyWith(sttMode: 'auto');
    }
    // Android 保持 whisper_kit 默认
    return s;
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
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
    notifyListeners();
  }

  Future<void> setPrimaryColor(Color color) async {
    _settings = _settings.copyWith(primaryColor: color);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    _settings = _settings.copyWith(accentColor: color);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    _settings = _settings.copyWith(language: language);
    await _storage.saveSettings(_settings);
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
    notifyListeners();
  }

  Future<void> updateDensity(String density) async {
    _settings = _settings.copyWith(cardDensity: density);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<String> syncData([SyncSettings? syncSettings]) async {
    await _storage.recordAnalyticsFeature('manual_sync');
    final settings = syncSettings ?? const SyncSettings();
    if (settings.method == 'local') {
      return 'local_mode_data_saved';
    }
    if (settings.method == 'file') {
      await exportData();
      return 'local_export_generated';
    }
    if (settings.isAutomaticMethod) {
      final result = await _dataSync.syncNow(settings);
      return result.l10nKey;
    }
    if (['baidu', 'quark', 'aliyun', 'onedrive'].contains(settings.method)) {
      return 'third_party_sync_coming_soon';
    }
    return 'cloud_sync_unavailable';
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

  /// 从 WebDAV 恢复数据
  Future<SyncResult> restoreFromWebDav([SyncSettings? syncSettings]) async {
    final settings = syncSettings ?? const SyncSettings();
    return _dataSync.restoreFromRemote(settings);
  }

  /// 测试 WebDAV 连接
  Future<SyncResult> testWebDavConnection([SyncSettings? syncSettings]) async {
    final settings = syncSettings ?? const SyncSettings();
    return _dataSync.testConnection(settings);
  }

  /// 获取上次同步时间
  Future<DateTime?> getLastSyncTime() => _storage.getLastSyncTime();
}
