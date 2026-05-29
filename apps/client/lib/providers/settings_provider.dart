import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/app_settings.dart';
import '../models/user_progress.dart';
import '../services/storage_service.dart';

// Web 端下载（条件导入）
import 'web_download/web_download_stub.dart'
    if (dart.library.html) 'web_download/web_download_web.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;

  SettingsProvider(this._storage);

  AppSettings _settings = const AppSettings();
  bool _isLoading = false;

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    _settings = await _storage.loadSettings();
    _isLoading = false;
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
    final settings = syncSettings ?? const SyncSettings();
    if (settings.method == 'local') {
      return '当前为本地模式，数据已保存在本机。';
    }
    if (settings.method == 'file') {
      await exportData();
      return '已生成本地导出文件。';
    }
    if (settings.method == 'webdav') {
      if (settings.webDavUrl.isEmpty ||
          settings.webDavUsername.isEmpty ||
          settings.webDavPassword.isEmpty) {
        return '请先填写 WebDAV 地址、用户名和应用密码。';
      }
      final data = await _storage.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final base = settings.webDavUrl.replaceAll(RegExp(r'/+$'), '');
      final fileName = 'mianshi-zhilian-backup.json';
      final uri = Uri.parse('$base/$fileName');
      final basic = base64Encode(
        utf8.encode('${settings.webDavUsername}:${settings.webDavPassword}'),
      );
      final response = await http.put(
        uri,
        headers: {
          'Authorization': 'Basic $basic',
          'Content-Type': 'application/json',
        },
        body: jsonStr,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return 'WebDAV 备份完成。';
      }
      return 'WebDAV 备份失败：${response.statusCode}';
    }
    if (['baidu', 'quark', 'aliyun', 'onedrive'].contains(settings.method)) {
      return '该第三方同步方式待开通，可先使用文件导出或 WebDAV。';
    }
    return '云同步暂不可用，本地数据不受影响。';
  }

  Future<void> exportData() async {
    try {
      final data = await _storage.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final fileName =
          'mianshi-zhilian-export-${DateTime.now().millisecondsSinceEpoch}.json';

      if (kIsWeb) {
        downloadFile(fileName, jsonStr);
      }

      debugPrint('Data exported: $fileName');
    } catch (e) {
      debugPrint('Export failed: $e');
    }
  }
}
