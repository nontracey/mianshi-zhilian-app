import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_config.dart';
import '../models/user_progress.dart';
import '../models/app_settings.dart';

/// Web + 通用存储服务，使用 SharedPreferences 替代 dart:io File
class StorageService {
  SharedPreferences? _prefs;
  bool _suppressSyncDirty = false;
  Future<void> _analyticsWriteQueue = Future.value();

  static const _syncDirtyKey = '_syncDirty';
  static const _syncDirtyAtKey = '_syncDirtyAt';
  static const _deviceIdKey = '_syncDeviceId';
  static const _analyticsBufferKey = '_analyticsBuffer';

  static const Set<String> _syncKeys = {
    'progress_map',
    'sessions',
    'practice_attempts',
    'mock_interview_sessions',
    'prep_plan',
    'local_profile',
    'settings',
    'disabled_domains',
    'custom_routes',
    'selected_route_id',
    'prep_goal',
    'training_plan',
    'project_library',
    'project_dig_projects',
    'ai_configs',
  };

  static const Set<String> _syncPrefixes = {'answer_versions_'};

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
      if (!_suppressSyncDirty && _isSyncRelevantKey(key)) {
        await markSyncDirty();
      }
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
          if (key == 'auth_token') {
            exportData['data'][key] = '[redacted]';
          }
          if (key == 'auth_refresh_token') {
            exportData['data'][key] = '[redacted]';
          }
          if (key == 'auth_user') {
            exportData['data'][key] = '[redacted]';
          }
        } catch (_) {
          exportData['data'][key] = value;
        }
      }
    }

    return exportData;
  }

  /// 清除所有本地数据
  Future<void> clearAllData() async {
    final prefs = await _instance;
    await prefs.clear();
  }

  /// 仅清除学习/练习产生的数据，保留 AI 配置、同步配置、内容缓存和个人资料。
  Future<void> clearPracticeData() async {
    final prefs = await _instance;
    for (final key in [
      'progress_map',
      'sessions',
      'practice_attempts',
      'mock_interview_sessions',
    ]) {
      await prefs.remove(key);
    }
    await markSyncDirty();
  }

  /// 保存 JSON 列表
  Future<void> saveJsonList(String key, List<Map<String, dynamic>> data) async {
    await save(key, data);
  }

  /// 加载 JSON 列表
  Future<List<Map<String, dynamic>>> loadJsonList(String key) async {
    final data = await load(key);
    if (data == null) return [];
    return (data as List).map((e) => e as Map<String, dynamic>).toList();
  }

  /// 保存 JSON 对象
  Future<void> saveJsonObject(String key, Map<String, dynamic> data) async {
    await save(key, data);
  }

  /// 加载 JSON 对象
  Future<Map<String, dynamic>?> loadJsonObject(String key) async {
    final data = await load(key);
    if (data == null) return null;
    return data as Map<String, dynamic>;
  }

  /// 保存禁用的领域列表
  Future<void> saveDisabledDomains(List<String> domainIds) async {
    await save('disabled_domains', domainIds);
  }

  /// 加载禁用的领域列表
  Future<List<String>> loadDisabledDomains() async {
    final data = await load('disabled_domains');
    if (data == null) return [];
    return (data as List).map((e) => e.toString()).toList();
  }

  /// 保存自定义路线
  Future<void> saveCustomRoutes(List<Map<String, dynamic>> routes) async {
    await save('custom_routes', routes);
  }

  /// 加载自定义路线
  Future<List<Map<String, dynamic>>> loadCustomRoutes() async {
    return await loadJsonList('custom_routes');
  }

  /// 导出白名单同步快照。同步目标凭证、登录态、API Key、缓存和运行态数据不会进入快照。
  Future<Map<String, dynamic>> exportSyncPackage(
    SyncSettings syncSettings,
  ) async {
    final prefs = await _instance;
    final deviceId = await getOrCreateDeviceId();
    final data = <String, dynamic>{};

    for (final key in _syncKeys) {
      final value = prefs.getString(key);
      if (value == null) continue;
      final decoded = _decodeStoredValue(value);
      final sanitized = _sanitizeSyncValue(key, decoded, syncSettings);
      if (sanitized != null) {
        data[key] = sanitized;
      }
    }

    final answerVersions = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('answer_versions_')) continue;
      final value = prefs.getString(key);
      if (value == null) continue;
      answerVersions[key.substring('answer_versions_'.length)] =
          _decodeStoredValue(value);
    }
    if (answerVersions.isNotEmpty) {
      data['answer_versions'] = answerVersions;
    }

    return sanitizeSyncPackage({
      'schemaVersion': 1,
      'app': 'mianshi-zhilian',
      'updatedAt': DateTime.now().toIso8601String(),
      'deviceId': deviceId,
      'data': data,
    }, syncSettings);
  }

  /// 对同步快照应用当前隐私策略。远端已有历史数据参与合并后也要再过一遍，
  /// 避免旧快照中的完整回答被当前设备继续上传。
  Map<String, dynamic> sanitizeSyncPackage(
    Map<String, dynamic> package,
    SyncSettings syncSettings,
  ) {
    final data = package['data'];
    if (data is! Map) return package;

    final sanitizedData = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (key == 'answer_versions') {
        if (syncSettings.syncFullPracticeText && value is Map) {
          sanitizedData[key] = value.map((k, v) => MapEntry(k.toString(), v));
        }
        continue;
      }
      final sanitized = _sanitizeSyncValue(key, value, syncSettings);
      if (sanitized != null) {
        sanitizedData[key] = sanitized;
      }
    }

    return {
      ...package,
      'data': sanitizedData..removeWhere((_, value) => value == null),
    };
  }

  /// 导入白名单同步快照。只写入允许同步的业务数据。
  Future<void> importSyncPackage(
    Map<String, dynamic> package, {
    SyncSettings? syncSettings,
    bool preserveLocalSensitiveData = true,
  }) async {
    final data = package['data'];
    if (data is! Map<String, dynamic>) return;
    final prefs = await _instance;
    _suppressSyncDirty = true;
    try {
      for (final entry in data.entries) {
        if (entry.key == 'answer_versions' && entry.value is Map) {
          if (syncSettings != null && !syncSettings.syncFullPracticeText) {
            continue;
          }
          for (final versionEntry in (entry.value as Map).entries) {
            await prefs.setString(
              'answer_versions_${versionEntry.key}',
              json.encode(versionEntry.value),
            );
          }
          continue;
        }
        if (!_syncKeys.contains(entry.key)) continue;
        if (entry.key == 'practice_attempts') {
          final merged = await _mergePracticeAttemptsForImport(
            entry.value,
            syncSettings: syncSettings,
            preserveLocalSensitiveData: preserveLocalSensitiveData,
          );
          await prefs.setString(entry.key, json.encode(merged));
          continue;
        }
        if (entry.key == 'mock_interview_sessions') {
          final merged = await _mergeMockSessionsForImport(
            entry.value,
            syncSettings: syncSettings,
            preserveLocalSensitiveData: preserveLocalSensitiveData,
          );
          await prefs.setString(entry.key, json.encode(merged));
          continue;
        }
        if (entry.key == 'settings') {
          final merged = await _mergeSettingsForImport(entry.value);
          await prefs.setString(entry.key, json.encode(merged));
          continue;
        }
        if (entry.key == 'ai_configs') {
          final merged = await _mergeAiConfigsForImport(entry.value);
          await prefs.setString(entry.key, json.encode(merged));
          continue;
        }
        await prefs.setString(entry.key, json.encode(entry.value));
      }
    } finally {
      _suppressSyncDirty = false;
    }
  }

  /// 从 Map 导入数据到本地存储
  Future<void> importAllData(Map<String, dynamic> data) async {
    final prefs = await _instance;
    _suppressSyncDirty = true;
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      try {
        if (value is String) {
          await prefs.setString(key, value);
        } else {
          await prefs.setString(key, json.encode(value));
        }
      } catch (e) {
        debugPrint('importAllData: skip key=$key, error=$e');
      }
    }
    _suppressSyncDirty = false;
  }

  /// 记录上次同步时间
  Future<void> setLastSyncTime(DateTime time) async {
    await save('_lastSyncTime', time.toIso8601String());
  }

  /// 获取上次同步时间
  Future<DateTime?> getLastSyncTime() async {
    final data = await load('_lastSyncTime');
    if (data == null) return null;
    return DateTime.tryParse(data.toString());
  }

  Future<void> markSyncDirty() async {
    final prefs = await _instance;
    await prefs.setBool(_syncDirtyKey, true);
    await prefs.setString(_syncDirtyAtKey, DateTime.now().toIso8601String());
  }

  Future<bool> hasSyncDirty() async {
    final prefs = await _instance;
    return prefs.getBool(_syncDirtyKey) ?? false;
  }

  Future<void> clearSyncDirty() async {
    final prefs = await _instance;
    await prefs.setBool(_syncDirtyKey, false);
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await _instance;
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  Future<void> recordAnalyticsFeature(String feature) async {
    const allowed = {'ai_eval', 'manual_sync', 'ticket_submit', 'login'};
    if (!allowed.contains(feature)) return;
    await incrementAnalyticsNestedCounter('feature_counts', feature);
  }

  Future<void> incrementAnalyticsCounter(String key, {int by = 1}) async {
    if (by <= 0) return;
    await _mutateAnalyticsBuffer((buffer) {
      final days = _analyticsDays(buffer);
      final today = _todayKey();
      final day = Map<String, dynamic>.from(days[today] as Map? ?? {});
      day[key] = ((day[key] as num?)?.toInt() ?? 0) + by;
      days[today] = day;
      buffer['days'] = _trimAnalyticsDays(days);
    });
  }

  Future<void> incrementAnalyticsNestedCounter(String key, String name) async {
    await _mutateAnalyticsBuffer((buffer) {
      final days = _analyticsDays(buffer);
      final today = _todayKey();
      final day = Map<String, dynamic>.from(days[today] as Map? ?? {});
      final nested = Map<String, dynamic>.from(day[key] as Map? ?? {});
      nested[name] = ((nested[name] as num?)?.toInt() ?? 0) + 1;
      day[key] = nested;
      days[today] = day;
      buffer['days'] = _trimAnalyticsDays(days);
    });
  }

  Future<Map<String, dynamic>?> snapshotAnalyticsBufferForFlush() async {
    return _mutateAnalyticsBuffer((buffer) {
      final days = _analyticsDays(buffer);
      if (days.isEmpty) return null;
      final batchId = _analyticsBatchId(buffer) ?? const Uuid().v4();
      buffer['batch_id'] = batchId;
      return {'batch_id': batchId, 'days': _deepCopyMap(days)};
    });
  }

  Future<void> markAnalyticsFlushSuccess(
    String batchId,
    Map<String, dynamic> sentDays,
  ) async {
    await _mutateAnalyticsBuffer((buffer) {
      final currentBatchId = _analyticsBatchId(buffer);
      if (currentBatchId != null && currentBatchId != batchId) {
        return;
      }
      final currentDays = _analyticsDays(buffer);
      final remainingDays = _subtractAnalyticsDays(currentDays, sentDays);
      buffer['days'] = remainingDays;
      if (remainingDays.isEmpty) {
        buffer.remove('batch_id');
      } else {
        buffer['batch_id'] = const Uuid().v4();
      }
    });
  }

  Future<Map<String, dynamic>> loadAnalyticsBuffer() async {
    final buffer = await loadJsonObject(_analyticsBufferKey);
    if (buffer == null) return {'days': <String, dynamic>{}};
    return _normalizeAnalyticsBuffer(buffer);
  }

  Future<T> _mutateAnalyticsBuffer<T>(
    FutureOr<T> Function(Map<String, dynamic> buffer) mutate,
  ) async {
    final previous = _analyticsWriteQueue;
    final completer = Completer<void>();
    _analyticsWriteQueue = previous.then((_) => completer.future);
    await previous;
    try {
      final buffer = await loadAnalyticsBuffer();
      final result = await mutate(buffer);
      final normalized = _normalizeAnalyticsBuffer(buffer);
      await saveJsonObject(_analyticsBufferKey, normalized);
      return result;
    } finally {
      completer.complete();
    }
  }

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  String? _analyticsBatchId(Map<String, dynamic> buffer) {
    final value = buffer['batch_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  Map<String, dynamic> _analyticsDays(Map<String, dynamic> buffer) {
    return Map<String, dynamic>.from(buffer['days'] as Map? ?? {});
  }

  Map<String, dynamic> _normalizeAnalyticsBuffer(Map<String, dynamic> buffer) {
    final days = _trimAnalyticsDays(_analyticsDays(buffer));
    final normalized = <String, dynamic>{'days': days};
    final batchId = _analyticsBatchId(buffer);
    if (days.isNotEmpty && batchId != null) {
      normalized['batch_id'] = batchId;
    }
    return normalized;
  }

  Map<String, dynamic> _trimAnalyticsDays(Map<String, dynamic> days) {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final result = <String, dynamic>{};
    for (final entry in days.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null || date.isBefore(cutoff)) continue;
      result[entry.key] = entry.value;
    }
    return result;
  }

  Map<String, dynamic> _subtractAnalyticsDays(
    Map<String, dynamic> currentDays,
    Map<String, dynamic> sentDays,
  ) {
    final remaining = _deepCopyMap(currentDays);
    for (final sentEntry in sentDays.entries) {
      final currentDay = remaining[sentEntry.key];
      final sentDay = sentEntry.value;
      if (currentDay is! Map || sentDay is! Map) continue;
      final day = Map<String, dynamic>.from(currentDay);
      _subtractNumberField(day, sentDay, 'open_count');
      _subtractNumberField(day, sentDay, 'active_seconds');
      _subtractNestedCounts(day, sentDay, 'section_counts');
      _subtractNestedCounts(day, sentDay, 'feature_counts');
      if (day.isEmpty) {
        remaining.remove(sentEntry.key);
      } else {
        remaining[sentEntry.key] = day;
      }
    }
    return remaining;
  }

  void _subtractNumberField(
    Map<String, dynamic> target,
    Map<dynamic, dynamic> sent,
    String key,
  ) {
    final currentValue = (target[key] as num?)?.toInt() ?? 0;
    final sentValue = (sent[key] as num?)?.toInt() ?? 0;
    final remaining = currentValue - sentValue;
    if (remaining > 0) {
      target[key] = remaining;
    } else {
      target.remove(key);
    }
  }

  void _subtractNestedCounts(
    Map<String, dynamic> target,
    Map<dynamic, dynamic> sent,
    String key,
  ) {
    final currentNested = target[key];
    final sentNested = sent[key];
    if (currentNested is! Map || sentNested is! Map) return;
    final remaining = Map<String, dynamic>.from(currentNested);
    for (final entry in sentNested.entries) {
      final name = entry.key.toString();
      final currentValue = (remaining[name] as num?)?.toInt() ?? 0;
      final sentValue = (entry.value as num?)?.toInt() ?? 0;
      final count = currentValue - sentValue;
      if (count > 0) {
        remaining[name] = count;
      } else {
        remaining.remove(name);
      }
    }
    if (remaining.isEmpty) {
      target.remove(key);
    } else {
      target[key] = remaining;
    }
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
    return json.decode(json.encode(value)) as Map<String, dynamic>;
  }

  bool _isSyncRelevantKey(String key) {
    if (_syncKeys.contains(key)) return true;
    return _syncPrefixes.any(key.startsWith);
  }

  dynamic _decodeStoredValue(String value) {
    try {
      return json.decode(value);
    } catch (_) {
      return value;
    }
  }

  dynamic _sanitizeSyncValue(
    String key,
    dynamic value,
    SyncSettings syncSettings,
  ) {
    if (key == 'sync_settings') return null;
    if (key == 'ai_configs') {
      if (!syncSettings.syncAiConfigMetadata || value is! List) return null;
      return value.map((item) {
        if (item is! Map<String, dynamic>) return item;
        return {...item, 'apiKey': ''};
      }).toList();
    }
    if (key == 'practice_attempts' && !syncSettings.syncFullPracticeText) {
      return _sanitizePracticeAttempts(value);
    }
    if (key == 'mock_interview_sessions' &&
        !syncSettings.syncFullPracticeText &&
        value is List) {
      return value.map((item) {
        if (item is! Map<String, dynamic>) return item;
        return {
          ...item,
          'attempts': _sanitizePracticeAttempts(item['attempts']),
        };
      }).toList();
    }
    if (!syncSettings.syncPrivatePrepData &&
        (key == 'prep_plan' ||
            key == 'prep_goal' ||
            key == 'training_plan' ||
            key == 'project_library' ||
            key == 'project_dig_projects')) {
      return null;
    }
    return value;
  }

  dynamic _sanitizePracticeAttempts(dynamic value) {
    if (value is! List) return value;
    return value.map((item) {
      if (item is! Map<String, dynamic>) return item;
      return {...item, 'answer': '', 'improvedAnswer': null};
    }).toList();
  }

  Future<dynamic> _mergePracticeAttemptsForImport(
    dynamic incoming, {
    required SyncSettings? syncSettings,
    required bool preserveLocalSensitiveData,
  }) async {
    if (incoming is! List) return incoming;
    if (!_shouldPreserveSensitiveData(
      syncSettings,
      preserveLocalSensitiveData,
    )) {
      return incoming;
    }

    final current = await loadPracticeAttempts();
    final currentById = {
      for (final attempt in current) attempt.id: attempt.toJson(),
    };

    return incoming.map((item) {
      if (item is! Map) return item;
      final imported = item.map((k, v) => MapEntry(k.toString(), v));
      final id = imported['id'] as String?;
      final local = id == null ? null : currentById[id];
      return _preserveAttemptSensitiveFields(imported, local);
    }).toList();
  }

  Future<dynamic> _mergeMockSessionsForImport(
    dynamic incoming, {
    required SyncSettings? syncSettings,
    required bool preserveLocalSensitiveData,
  }) async {
    if (incoming is! List) return incoming;
    if (!_shouldPreserveSensitiveData(
      syncSettings,
      preserveLocalSensitiveData,
    )) {
      return incoming;
    }

    final current = await loadMockInterviewSessions();
    final currentById = {
      for (final session in current) session.id: session.toJson(),
    };

    return incoming.map((item) {
      if (item is! Map) return item;
      final imported = item.map((k, v) => MapEntry(k.toString(), v));
      final id = imported['id'] as String?;
      final local = id == null ? null : currentById[id];
      final localAttempts = <String, Map<String, dynamic>>{};
      final localAttemptList = local?['attempts'];
      if (localAttemptList is List) {
        for (final attempt in localAttemptList) {
          if (attempt is Map) {
            final normalized = attempt.map((k, v) => MapEntry(k.toString(), v));
            final attemptId = normalized['id'] as String?;
            if (attemptId != null) localAttempts[attemptId] = normalized;
          }
        }
      }

      final importedAttempts = imported['attempts'];
      if (importedAttempts is List) {
        imported['attempts'] = importedAttempts.map((attempt) {
          if (attempt is! Map) return attempt;
          final normalized = attempt.map((k, v) => MapEntry(k.toString(), v));
          final attemptId = normalized['id'] as String?;
          return _preserveAttemptSensitiveFields(
            normalized,
            attemptId == null ? null : localAttempts[attemptId],
          );
        }).toList();
      }
      return imported;
    }).toList();
  }

  bool _shouldPreserveSensitiveData(
    SyncSettings? syncSettings,
    bool preserveLocalSensitiveData,
  ) {
    return preserveLocalSensitiveData &&
        syncSettings != null &&
        !syncSettings.syncFullPracticeText;
  }

  Map<String, dynamic> _preserveAttemptSensitiveFields(
    Map<String, dynamic> imported,
    Map<String, dynamic>? local,
  ) {
    if (local == null) return imported;
    final localAnswer = local['answer'] as String?;
    if ((imported['answer'] as String? ?? '').isEmpty &&
        localAnswer != null &&
        localAnswer.isNotEmpty) {
      imported['answer'] = localAnswer;
    }
    final localImprovedAnswer = local['improvedAnswer'] as String?;
    if (imported['improvedAnswer'] == null &&
        localImprovedAnswer != null &&
        localImprovedAnswer.isNotEmpty) {
      imported['improvedAnswer'] = localImprovedAnswer;
    }
    return imported;
  }

  Future<dynamic> _mergeSettingsForImport(dynamic incoming) async {
    if (incoming is! Map<String, dynamic>) return incoming;
    return incoming;
  }

  Future<dynamic> _mergeAiConfigsForImport(dynamic incoming) async {
    if (incoming is! List) return incoming;
    final current = await loadAiConfigs();
    final keysById = {for (final config in current) config.id: config.apiKey};
    return incoming.map((item) {
      if (item is! Map<String, dynamic>) return item;
      final id = item['id'] as String?;
      final localKey = id == null ? null : keysById[id];
      return {
        ...item,
        'apiKey': (localKey != null && localKey.isNotEmpty)
            ? localKey
            : (item['apiKey'] ?? ''),
      };
    }).toList();
  }
}
