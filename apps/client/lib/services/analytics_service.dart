import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'api_headers.dart';
import 'storage_service.dart';

class AnalyticsService {
  AnalyticsService(
    this._storage, {
    this.apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://mianshi-zhilian-api.nontracey.workers.dev',
    ),
  });

  final StorageService _storage;
  final String apiBaseUrl;
  Timer? _timer;
  DateTime? _activeStartedAt;
  String? _currentBatchId;

  static const _bufferKey = '_analyticsBuffer';
  static const _lastFlushKey = '_analyticsLastFlushAt';
  static const _flushInterval = Duration(minutes: 30);
  static const _sections = {
    'dashboard',
    'catalog',
    'practice',
    'prep',
    'mastery',
    'profile',
  };
  static const _features = {
    'ai_eval',
    'manual_sync',
    'ticket_submit',
    'login',
  };

  void start() {
    _activeStartedAt ??= DateTime.now();
    recordOpen();
    _timer?.cancel();
    _timer = Timer.periodic(_flushInterval, (_) => flush());
  }

  void stop() {
    flush();
    _timer?.cancel();
    _timer = null;
  }

  Future<void> recordOpen() async {
    await _increment('open_count');
  }

  Future<void> recordSection(String section) async {
    if (!_sections.contains(section)) return;
    await _incrementNested('section_counts', section);
  }

  Future<void> recordFeature(String feature) async {
    if (!_features.contains(feature)) return;
    await _incrementNested('feature_counts', feature);
  }

  Future<void> flush({String? token}) async {
    try {
      await _captureActiveSeconds();
      final buffer = await _loadBuffer();
      final days = buffer['days'];
      if (days is! Map || days.isEmpty) return;
      _currentBatchId ??= const Uuid().v4();
      final deviceId = await _storage.getOrCreateDeviceId();
      final packageInfo = await PackageInfo.fromPlatform();
      final payload = {
        'batch_id': _currentBatchId,
        'device_id': deviceId,
        'platform': defaultTargetPlatform.name,
        'app_version': packageInfo.version,
        'os_version': 'unknown',
        'device_model': 'unknown',
        'days': days.entries.map((entry) {
          final value = Map<String, dynamic>.from(entry.value as Map);
          return {'date': entry.key, ...value};
        }).toList(),
      };
      final headers = await ApiHeaders.build(_storage, token: token);
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/analytics/batch'),
            headers: headers,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _storage.saveJsonObject(_bufferKey, {'days': <String, dynamic>{}});
        await _storage.save(_lastFlushKey, DateTime.now().toIso8601String());
        _currentBatchId = null;
      }
    } catch (e) {
      debugPrint('Analytics flush failed: $e');
    } finally {
      _activeStartedAt = DateTime.now();
    }
  }

  Future<void> bindDevice(String token) async {
    try {
      final deviceId = await _storage.getOrCreateDeviceId();
      await http
          .post(
            Uri.parse('$apiBaseUrl/analytics/bind-device'),
            headers: await ApiHeaders.build(_storage, token: token),
            body: json.encode({'device_id': deviceId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Analytics bind failed: $e');
    }
  }

  Future<Map<String, dynamic>> _loadBuffer() async {
    final buffer = await _storage.loadJsonObject(_bufferKey);
    if (buffer == null) return {'days': <String, dynamic>{}};
    return buffer;
  }

  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _increment(String key, {int by = 1}) async {
    final buffer = await _loadBuffer();
    final days = Map<String, dynamic>.from(buffer['days'] as Map? ?? {});
    final today = _today();
    final day = Map<String, dynamic>.from(days[today] as Map? ?? {});
    day[key] = ((day[key] as num?)?.toInt() ?? 0) + by;
    days[today] = day;
    await _storage.saveJsonObject(_bufferKey, {'days': _trimDays(days)});
  }

  Future<void> _incrementNested(String key, String name) async {
    final buffer = await _loadBuffer();
    final days = Map<String, dynamic>.from(buffer['days'] as Map? ?? {});
    final today = _today();
    final day = Map<String, dynamic>.from(days[today] as Map? ?? {});
    final nested = Map<String, dynamic>.from(day[key] as Map? ?? {});
    nested[name] = ((nested[name] as num?)?.toInt() ?? 0) + 1;
    day[key] = nested;
    days[today] = day;
    await _storage.saveJsonObject(_bufferKey, {'days': _trimDays(days)});
  }

  Map<String, dynamic> _trimDays(Map<String, dynamic> days) {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final result = <String, dynamic>{};
    for (final entry in days.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null || date.isBefore(cutoff)) continue;
      result[entry.key] = entry.value;
    }
    return result;
  }

  Future<void> _captureActiveSeconds() async {
    final started = _activeStartedAt;
    if (started == null) return;
    final seconds = DateTime.now().difference(started).inSeconds;
    if (seconds <= 0) return;
    await _increment('active_seconds', by: seconds.clamp(0, 30 * 60));
  }
}
