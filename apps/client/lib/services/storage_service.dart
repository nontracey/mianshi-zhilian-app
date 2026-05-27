import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/ai_config.dart';
import '../models/user_progress.dart';
import '../models/app_settings.dart';

class StorageService {
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> _localFile(String name) async {
    final path = await _localPath;
    return File('$path/$name');
  }

  Future<void> save(String key, dynamic data) async {
    final file = await _localFile('$key.json');
    await file.writeAsString(json.encode(data));
  }

  Future<dynamic> load(String key) async {
    try {
      final file = await _localFile('$key.json');
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      return json.decode(contents);
    } catch (_) {
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
