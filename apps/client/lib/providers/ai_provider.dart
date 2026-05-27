import 'package:flutter/material.dart';
import '../models/ai_config.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';

class AiProvider extends ChangeNotifier {
  final AiService _aiService;
  final StorageService _storage;

  AiProvider(this._aiService, this._storage);

  List<AiConfig> _configs = [];
  AiConfig? _defaultConfig;
  bool _isTesting = false;
  String? _testResult;

  List<AiConfig> get configs => _configs;
  AiConfig? get defaultConfig => _defaultConfig;
  bool get isTesting => _isTesting;
  String? get testResult => _testResult;

  Future<void> loadConfigs() async {
    _configs = await _storage.loadAiConfigs();
    _defaultConfig = _configs.where((c) => c.isDefault).firstOrNull;
    notifyListeners();
  }

  Future<void> addConfig(AiConfig config) async {
    _configs.add(config);
    if (config.isDefault) {
      _configs = _configs
          .map((c) => c.id == config.id ? c : c.copyWith(isDefault: false))
          .toList();
      _defaultConfig = config;
    }
    await _storage.saveAiConfigs(_configs);
    notifyListeners();
  }

  Future<void> updateConfig(AiConfig config) async {
    final index = _configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      if (config.isDefault) {
        _configs = _configs
            .map((c) => c.id == config.id ? config : c.copyWith(isDefault: false))
            .toList();
        _defaultConfig = config;
      } else {
        _configs[index] = config;
        if (_defaultConfig?.id == config.id) {
          _defaultConfig = config;
        }
      }
      await _storage.saveAiConfigs(_configs);
      notifyListeners();
    }
  }

  Future<void> deleteConfig(String id) async {
    _configs.removeWhere((c) => c.id == id);
    if (_defaultConfig?.id == id) {
      _defaultConfig = _configs.where((c) => c.isDefault).firstOrNull;
    }
    await _storage.saveAiConfigs(_configs);
    notifyListeners();
  }

  Future<void> setDefault(String id) async {
    _configs = _configs.map((c) {
      if (c.id == id) {
        _defaultConfig = c.copyWith(isDefault: true);
        return _defaultConfig!;
      }
      return c.copyWith(isDefault: false);
    }).toList();
    await _storage.saveAiConfigs(_configs);
    notifyListeners();
  }

  Future<void> testConnection(String id) async {
    final config = _configs.where((c) => c.id == id).firstOrNull;
    if (config == null) return;

    _isTesting = true;
    _testResult = null;
    notifyListeners();

    try {
      final success = await _aiService.testConnection(config);
      _testResult = success ? '连接成功' : '连接失败';
    } catch (e) {
      _testResult = '连接失败: $e';
    }

    _isTesting = false;
    notifyListeners();
  }
}
