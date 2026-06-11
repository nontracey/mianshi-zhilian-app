import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_config.dart';
import '../models/user_progress.dart';
import '../models/app_settings.dart';

class StorageWriteException implements Exception {
  StorageWriteException(this.key, this.cause);

  final String key;
  final Object cause;

  @override
  String toString() => 'StorageWriteException($key): $cause';
}

/// Web + 通用存储服务，使用 SharedPreferences 替代 dart:io File
class StorageService {
  SharedPreferences? _prefs;
  bool _suppressSyncDirty = false;
  Future<void> _analyticsWriteQueue = Future.value();

  /// 全局存储写入失败信号。[StorageService] 在多处被实例化（SharedPreferences
  /// 底层共享），故用 static notifier 广播：写入失败（如 Web localStorage 配额
  /// 超限）时置为失败的 key，根部 UI 监听后提示用户「数据可能未保存」。
  static final ValueNotifier<String?> writeFailure = ValueNotifier<String?>(
    null,
  );

  static const _syncDirtyKey = '_syncDirty';
  static const _syncDirtyAtKey = '_syncDirtyAt';
  static const _deviceIdKey = '_syncDeviceId';
  static const _analyticsBufferKey = '_analyticsBuffer';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 完整导出（[exportAllData]）对敏感字段写入的占位符。导入时遇到此值
  /// 不覆盖本地真实凭据，避免备份恢复把 apiKey/token 损坏为字面量。
  static const _redactedPlaceholder = '[redacted]';
  // 完整导出中需要脱敏的 sync_settings 凭据字段。
  static const _redactedSyncSettingFields = {
    'webDavPassword',
    'githubToken',
    'giteeToken',
  };

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
    'learning_scope',
    'deletions',

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
    await _save(key, data, strict: false);
  }

  /// 与 [save] 相同，但写入失败会抛 [StorageWriteException]。
  /// 用于练习记录等不能让调用方误以为已经持久化成功的关键路径。
  Future<void> saveStrict(String key, dynamic data) async {
    await _save(key, data, strict: true);
  }

  Future<void> _save(String key, dynamic data, {required bool strict}) async {
    try {
      final prefs = await _instance;
      await prefs.setString(key, json.encode(data));
      if (!_suppressSyncDirty && _isSyncRelevantKey(key)) {
        await markSyncDirty();
      }
    } catch (e) {
      debugPrint('StorageService.save($key) failed: $e');
      // 广播写入失败，让根部 UI 提示用户数据可能未保存（静默吞掉会让用户
      // 在配额超限后毫无察觉地持续丢失练习数据）。
      writeFailure.value = key;
      if (strict) {
        throw StorageWriteException(key, e);
      }
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
    final existingIds = _aiConfigIds(await load('ai_configs'));
    final nextIds = configs.map((c) => c.id).toSet();
    final payload = <Map<String, dynamic>>[];

    for (final config in configs) {
      final json = config.toJson();
      if (!kIsWeb && config.apiKey.isNotEmpty) {
        final wroteSecurely = await _writeAiConfigApiKey(
          config.id,
          config.apiKey,
        );
        if (wroteSecurely) json['apiKey'] = '';
      }
      payload.add(json);
    }

    if (!kIsWeb) {
      for (final removedId in existingIds.difference(nextIds)) {
        await _deleteAiConfigApiKey(removedId);
      }
    }

    await save('ai_configs', payload);
  }

  Future<List<AiConfig>> loadAiConfigs() async {
    final data = await load('ai_configs');
    if (data == null) return [];
    final configs = (data as List)
        .map((e) => AiConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    if (kIsWeb) return configs;

    var shouldSanitizePrefs = false;
    final hydrated = <AiConfig>[];
    for (final config in configs) {
      final secureApiKey = await _readAiConfigApiKey(config.id);
      if (secureApiKey != null && secureApiKey.isNotEmpty) {
        hydrated.add(config.copyWith(apiKey: secureApiKey));
        if (config.apiKey.isNotEmpty) shouldSanitizePrefs = true;
        continue;
      }

      if (config.apiKey.isNotEmpty) {
        final migrated = await _writeAiConfigApiKey(config.id, config.apiKey);
        if (migrated) shouldSanitizePrefs = true;
      }
      hydrated.add(config);
    }

    if (shouldSanitizePrefs) {
      await _saveAiConfigMetadataOnly(hydrated);
    }
    return hydrated;
  }

  Set<String> _aiConfigIds(dynamic value) {
    if (value is! List) return {};
    return value
        .whereType<Map<String, dynamic>>()
        .map((item) => item['id'] as String?)
        .whereType<String>()
        .toSet();
  }

  String _aiConfigApiKeySecureKey(String id) => 'ai_config_api_key_$id';

  Future<bool> _writeAiConfigApiKey(String id, String apiKey) async {
    try {
      await _secureStorage.write(
        key: _aiConfigApiKeySecureKey(id),
        value: apiKey,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _readAiConfigApiKey(String id) async {
    try {
      return await _secureStorage.read(key: _aiConfigApiKeySecureKey(id));
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteAiConfigApiKey(String id) async {
    try {
      await _secureStorage.delete(key: _aiConfigApiKeySecureKey(id));
    } catch (_) {}
  }

  Future<void> _saveAiConfigMetadataOnly(List<AiConfig> configs) async {
    await save(
      'ai_configs',
      configs.map((config) {
        final json = config.toJson();
        json['apiKey'] = '';
        return json;
      }).toList(),
    );
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

  Future<void> savePracticeAttemptsStrict(
    List<PracticeAttempt> attempts,
  ) async {
    await saveStrict(
      'practice_attempts',
      attempts.map((a) => a.toJson()).toList(),
    );
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
    if (data == null) {
      final profile = LocalProfile.defaultProfile();
      await saveLocalProfile(profile);
      return profile;
    }
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
      if (key == 'app_logs') continue;
      Object? rawValue;
      try {
        rawValue = prefs.getString(key);
      } catch (_) {
        // 非字符串键（bool/int/double/List<String> 等运行态值）：直接导出原值，
        // 否则 getString 对它们抛 type-cast，使整个导出失败（用过同步即触发）。
        rawValue = prefs.get(key);
      }
      if (rawValue == null) continue;
      if (rawValue is! String) {
        exportData['data'][key] = rawValue;
        continue;
      }
      final value = rawValue;
      {
        try {
          exportData['data'][key] = json.decode(value);
          if (key == 'ai_configs' && exportData['data'][key] is List) {
            exportData['data'][key] = (exportData['data'][key] as List).map((
              item,
            ) {
              if (item is Map<String, dynamic>) {
                return {...item, 'apiKey': _redactedPlaceholder};
              }
              return item;
            }).toList();
          }
          if (key == 'sync_settings' &&
              exportData['data'][key] is Map<String, dynamic>) {
            // 脱敏所有同步通道凭据（WebDAV 密码、GitHub/Gitee token），
            // 避免随备份文件明文导出。
            final settings = {
              ...(exportData['data'][key] as Map<String, dynamic>),
            };
            for (final field in _redactedSyncSettingFields) {
              if (settings.containsKey(field)) {
                settings[field] = _redactedPlaceholder;
              }
            }
            exportData['data'][key] = settings;
          }
          if (key == 'auth_token') {
            exportData['data'][key] = _redactedPlaceholder;
          }
          if (key == 'auth_refresh_token') {
            exportData['data'][key] = _redactedPlaceholder;
          }
          if (key == 'auth_user') {
            exportData['data'][key] = _redactedPlaceholder;
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

  /// 清除内容缓存与 AI 路线缓存（content_cache_* 和 route_cache_*），保留用户数据。
  Future<int> clearCacheData() async {
    final prefs = await _instance;
    final keys = prefs.getKeys();
    final cacheKeys = keys
        .where(
          (k) => k.startsWith('content_cache_') || k.startsWith('route_cache_'),
        )
        .toList();
    for (final k in cacheKeys) {
      await prefs.remove(k);
    }
    return cacheKeys.length;
  }

  /// 清除 AI 路线缓存（route_cache_*），保留内容缓存和其他用户数据。
  ///
  /// 删除 AI 路线后调用，避免独立缓存在用户重新生成时返回已删除的旧路线。
  Future<int> clearRouteCaches() async {
    final prefs = await _instance;
    final keys = prefs.getKeys();
    final routeKeys = keys.where((k) => k.startsWith('route_cache_')).toList();
    for (final k in routeKeys) {
      await prefs.remove(k);
    }
    return routeKeys.length;
  }

  /// 仅清除学习/练习产生的数据，保留 AI 配置、同步配置、内容缓存和个人资料。
  ///
  /// 清空前为每条记录写删除墓碑，确保开启同步时不会从远端并集里复活
  /// （否则「清空练习数据」在多设备下整体无效）。
  Future<void> clearPracticeData() async {
    final prefs = await _instance;

    final attempts = await loadPracticeAttempts();
    final sessions = await loadSessions();
    final mockSessions = await loadMockInterviewSessions();
    final progressMap = await loadProgressMap();
    await recordDeletions([
      for (final a in attempts) ('practice_attempts', a.id),
      for (final s in sessions) ('sessions', s.id),
      for (final m in mockSessions) ('mock_interview_sessions', m.id),
      for (final topicId in progressMap.keys) ('progress_map', topicId),
    ]);

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

  /// 加载删除墓碑表 `{<集合>:<id>: <deletedAt ISO>}`
  Future<Map<String, String>> loadDeletions() async {
    final data = await load('deletions');
    if (data is! Map) return {};
    return data.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 记录一条删除墓碑；同时对超过 60 天的旧墓碑执行 GC。
  Future<void> recordDeletion(String collection, String id) async {
    final deletions = await loadDeletions();
    deletions['$collection:$id'] = DateTime.now().toIso8601String();
    _gcDeletions(deletions);
    await save('deletions', deletions);
  }

  static String answerVersionDeletionCollection(String topicId) =>
      'answer_versions:$topicId';

  static String answerVersionIdFor(Map<dynamic, dynamic> version) {
    final existing = version['id']?.toString();
    if (existing != null && existing.isNotEmpty) return existing;
    final raw =
        '${version['type'] ?? ''}|${version['content'] ?? ''}|${version['createdAt'] ?? ''}';
    return 'legacy_${sha1.convert(utf8.encode(raw)).toString().substring(0, 16)}';
  }

  Future<void> recordAnswerVersionDeletion(
    String topicId,
    Map<dynamic, dynamic> version,
  ) async {
    await recordDeletion(
      answerVersionDeletionCollection(topicId),
      answerVersionIdFor(version),
    );
  }

  /// 批量记录删除墓碑，仅一次读改写。[entries] 为 `(collection, id)` 列表。
  /// 用于「清空练习数据」等一次删多个集合多条记录的场景。
  Future<void> recordDeletions(Iterable<(String, String)> entries) async {
    final deletions = await loadDeletions();
    final now = DateTime.now().toIso8601String();
    for (final (collection, id) in entries) {
      deletions['$collection:$id'] = now;
    }
    _gcDeletions(deletions);
    await save('deletions', deletions);
  }

  static void _gcDeletions(Map<String, String> deletions) {
    final cutoff = DateTime.now().subtract(const Duration(days: 60));
    deletions.removeWhere((_, value) {
      final dt = DateTime.tryParse(value);
      return dt != null && dt.isBefore(cutoff);
    });
  }

  /// 导出白名单同步快照。同步目标凭证、登录态、API Key、缓存和运行态数据不会进入快照。
  Future<Map<String, dynamic>> exportSyncPackage(
    SyncSettings syncSettings,
  ) async {
    final prefs = await _instance;
    final deviceId = await getOrCreateDeviceId();
    final appSettings = await loadSettings();
    final contentVersion = await _loadContentVersionSnapshot(appSettings);
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
      'contentEnv': appSettings.contentEnv.key,
      'contentVersion': ?contentVersion,
      'data': data,
    }, syncSettings);
  }

  Future<String?> _loadContentVersionSnapshot(AppSettings settings) async {
    final version = await load(
      _contentCacheKey(settings.contentBaseUrl, 'content_version'),
    );
    return version is String && version.isNotEmpty ? version : null;
  }

  String _contentCacheKey(String baseUrl, String key) =>
      'content_cache_${_contentCacheScope(baseUrl)}_$key';

  String _contentCacheScope(String baseUrl) => baseUrl
      .replaceAll(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

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

  /// 从 Map 导入数据到本地存储。
  ///
  /// 备份文件中被 [exportAllData] 脱敏的敏感字段（值为 [_redactedPlaceholder]）
  /// 不会覆盖本地真实凭据：顶层占位符整键跳过，sync_settings/ai_configs 内嵌
  /// 占位符回填本地现有值。避免「导出再导入」把 apiKey/token 损坏为字面量。
  Future<void> importAllData(Map<String, dynamic> data) async {
    final prefs = await _instance;
    _suppressSyncDirty = true;
    try {
      for (final entry in data.entries) {
        final key = entry.key;
        var value = entry.value;
        // 顶层敏感键被脱敏 → 保留本地真实值，不写入占位符。
        if (value == _redactedPlaceholder) continue;
        if (key == 'sync_settings' && value is Map) {
          value = await _restoreRedactedSyncSettings(value);
        } else if (key == 'ai_configs' && value is List) {
          value = await _restoreRedactedAiConfigs(value);
        }
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
    } finally {
      _suppressSyncDirty = false;
    }
  }

  /// 将 sync_settings 中被脱敏的凭据字段回填为本地现有值。
  Future<Map<String, dynamic>> _restoreRedactedSyncSettings(
    Map<dynamic, dynamic> incoming,
  ) async {
    final result = incoming.map((k, v) => MapEntry(k.toString(), v));
    final localJson = (await loadSyncSettings()).toJson();
    for (final field in _redactedSyncSettingFields) {
      if (result[field] == _redactedPlaceholder) {
        result[field] = localJson[field];
      }
    }
    return result;
  }

  /// 将 ai_configs 中被脱敏的 apiKey 回填为本地同 id 配置的真实值。
  Future<List<dynamic>> _restoreRedactedAiConfigs(
    List<dynamic> incoming,
  ) async {
    final current = await loadAiConfigs();
    final keysById = {for (final config in current) config.id: config.apiKey};
    return incoming.map((item) {
      if (item is! Map) return item;
      final normalized = item.map((k, v) => MapEntry(k.toString(), v));
      if (normalized['apiKey'] == _redactedPlaceholder) {
        final id = normalized['id'] as String?;
        normalized['apiKey'] = (id == null ? null : keysById[id]) ?? '';
      }
      return normalized;
    }).toList();
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

  /// 最近一次 [markSyncDirty] 的时间戳（ISO）。用于同步窗口期检测：
  /// 导出后若该值变化，说明期间有新本地改动，不应清除 dirty 标记。
  Future<String?> getSyncDirtyAt() async {
    final prefs = await _instance;
    return prefs.getString(_syncDirtyAtKey);
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
    const allowed = {
      'ai_eval',
      'ai_eval_success',
      'ai_eval_failed',
      'content_load_failed',
      'manual_sync',
      'sync_success',
      'sync_failed',
      'ticket_submit',
      'login',
      'update_check',
    };
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
            key == 'project_library' ||
            key == 'project_dig_projects')) {
      return null;
    }
    if (key == 'local_profile' && value is Map<String, dynamic>) {
      final stripped = {...value}
        ..remove('email')
        ..remove('emailBound')
        ..remove('wechatBound');
      if (!syncSettings.syncPrivatePrepData) {
        stripped.remove('avatarUrl');
      }
      return stripped;
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
