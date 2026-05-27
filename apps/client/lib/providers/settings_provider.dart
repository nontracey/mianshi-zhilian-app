import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';

// Web 端下载（条件导入）
import 'web_download/web_download_stub.dart'
    if (dart.library.html) 'web_download/web_download_web.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;

  SettingsProvider(this._storage);

  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  Future<void> loadSettings() async {
    _settings = await _storage.loadSettings();
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
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

  // Convenience aliases used by profile page
  Future<void> updateThemeMode(ThemeMode mode) async => setThemeMode(mode);
  Future<void> updatePrimaryColor(Color color) async => setPrimaryColor(color);
  Future<void> updateAccentColor(Color color) async => setAccentColor(color);
  Future<void> updateLanguage(String lang) async => setLanguage(lang);
  Future<void> updateRecommendStrategy(String strategy) async => setRecommendStrategy(strategy);

  Future<void> updateFontScale(double scale) async {
    // Font scale not yet in AppSettings model; no-op for now
  }

  Future<void> updateDensity(String density) async {
    // Density not yet in AppSettings model; no-op for now
  }

  Future<void> syncData() async {
    // Sync not yet implemented
  }

  Future<void> exportData() async {
    try {
      final data = await _storage.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final fileName = 'mianshi-zhilian-export-${DateTime.now().millisecondsSinceEpoch}.json';

      if (kIsWeb) {
        downloadFile(fileName, jsonStr);
      }

      debugPrint('Data exported: $fileName');
    } catch (e) {
      debugPrint('Export failed: $e');
    }
  }
}
