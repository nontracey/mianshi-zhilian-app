import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_config.dart';
import '../models/user_progress.dart';
import '../models/app_settings.dart';

/// Web + 通用存储服务，使用 SharedPreferences 替代 dart:io File
class StorageService {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> save(String key, dynamic data) async {
    try {
      final prefs = await _instance;
      await prefs.setString(key, json.encode(data));
    } catch (e) {
      debugPrint('StorageService.save($key) failed: $e');
    }
  }

  Future<dynamic> load(String key) async {
    try {
      final prefs = await _instance;
      final raw = prefs.getString(key);
      if (raw == null) return null;
      return json.decode(raw);
    } catch (e) {
      debugPrint('StorageService.load($key) failed: $e');
      return null;
    }
  }

  Future<void> saveAiConfigs(List<AiConfig> configs) async {
    await save('ai_configs', configs.map((c) => c.toJson()).toList());
  }

  Future<List<AiConfig>> loadAiConfigs() async {
    final data = await load('ai_configs');
    if (data == null) return [];
    return (data as List)
        .map((e) => AiConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProgressMap(Map<String, TopicProgress> map) async {
    await save('progress_map', map.map((k, v) => MapEntry(k, v.toJson())));
  }

  Future<Map<String, TopicProgress>> loadProgressMap() async {
    final data = await load('progress_map');
    if (data == null) return {};
    return (data as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, TopicProgress.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<void> saveSessions(List<PracticeSession> sessions) async {
    await save('sessions', sessions.map((s) => s.toJson()).toList());
  }

  Future<List<PracticeSession>> loadSessions() async {
    final data = await load('sessions');
    if (data == null) return [];
    return (data as List)
        .map((e) => PracticeSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSettings(AppSettings settings) async {
    await save('settings', settings.toJson());
  }

  Future<AppSettings> loadSettings() async {
    final data = await load('settings');
    if (data == null) return const AppSettings();
    return AppSettings.fromJson(data as Map<String, dynamic>);
  }
}
