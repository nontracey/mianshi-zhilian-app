import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';

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
}
