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

  /// 获取 SharedPreferences 实例（用于遍历 key 等操作）
  Future<SharedPreferences> getInstance() async {
    return await _instance;
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

  Future<void> savePracticeAttempts(List<PracticeAttempt> attempts) async {
    await save('practice_attempts', attempts.map((a) => a.toJson()).toList());
  }

  Future<List<PracticeAttempt>> loadPracticeAttempts() async {
    final data = await load('practice_attempts');
    if (data == null) return [];
    return (data as List)
        .map((e) => PracticeAttempt.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMockInterviewSessions(
    List<MockInterviewSession> sessions,
  ) async {
    await save(
      'mock_interview_sessions',
      sessions.map((s) => s.toJson()).toList(),
    );
  }

  Future<List<MockInterviewSession>> loadMockInterviewSessions() async {
    final data = await load('mock_interview_sessions');
    if (data == null) return [];
    return (data as List)
        .map((e) => MockInterviewSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePrepPlan(PrepPlan plan) async {
    await save('prep_plan', plan.toJson());
  }

  Future<PrepPlan> loadPrepPlan() async {
    final data = await load('prep_plan');
    if (data == null) return PrepPlan.empty();
    return PrepPlan.fromJson(data as Map<String, dynamic>);
  }

  Future<void> saveLocalProfile(LocalProfile profile) async {
    await save('local_profile', profile.toJson());
  }

  Future<LocalProfile> loadLocalProfile() async {
    final data = await load('local_profile');
    if (data == null) return const LocalProfile();
    return LocalProfile.fromJson(data as Map<String, dynamic>);
  }

  Future<void> saveSyncSettings(SyncSettings settings) async {
    await save('sync_settings', settings.toJson());
  }

  Future<SyncSettings> loadSyncSettings() async {
    final data = await load('sync_settings');
    if (data == null) return const SyncSettings();
    return SyncSettings.fromJson(data as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings settings) async {
    await save('settings', settings.toJson());
  }

  Future<AppSettings> loadSettings() async {
    final data = await load('settings');
    if (data == null) return const AppSettings();
    return AppSettings.fromJson(data as Map<String, dynamic>);
  }

  /// 导出所有本地数据为 JSON
  Future<Map<String, dynamic>> exportAllData() async {
    final prefs = await _instance;
    final keys = prefs.getKeys();

    final exportData = <String, dynamic>{
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'data': <String, dynamic>{},
    };

    for (final key in keys) {
      final value = prefs.getString(key);
      if (value != null) {
        try {
          exportData['data'][key] = json.decode(value);
          if (key == 'ai_configs' && exportData['data'][key] is List) {
            exportData['data'][key] = (exportData['data'][key] as List).map((
              item,
            ) {
              if (item is Map<String, dynamic>) {
                return {...item, 'apiKey': '[redacted]'};
              }
              return item;
            }).toList();
          }
          if (key == 'sync_settings' &&
              exportData['data'][key] is Map<String, dynamic>) {
            exportData['data'][key] = {
              ...(exportData['data'][key] as Map<String, dynamic>),
              'webDavPassword': '[redacted]',
            };
          }
        } catch (_) {
          exportData['data'][key] = value;
        }
      }
    }

    return exportData;
  }
}
