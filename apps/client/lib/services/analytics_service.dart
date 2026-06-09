import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_headers.dart';
import 'app_log_service.dart';
import 'device_info_helper.dart';
import 'endpoint_fallback_client.dart';
import 'route_resolver.dart';
import 'route_state_store.dart';
import 'storage_service.dart';

class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService(this._storage, {EndpointFallbackClient? routeClient})
    : _routeClient =
          routeClient ??
          EndpointFallbackClient(stateStore: EndpointStateStore(_storage));

  final StorageService _storage;
  final EndpointFallbackClient _routeClient;
  Timer? _timer;
  DateTime? _activeStartedAt;
  bool _flushing = false;
  bool _isActive = false;
  bool _observingLifecycle = false;

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

  void start() {
    _isActive = true;
    _activeStartedAt ??= DateTime.now();
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    recordOpen();
    _timer?.cancel();
    _timer = Timer.periodic(_flushInterval, (_) => flush());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    // 同步部分：先取消定时器；异步 flush 交给事件循环收尾
    // 如果进程立即退出，本批数据下次启动时会随 buffer 重试
    flush(restartActiveTimer: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isActive = true;
        _activeStartedAt ??= DateTime.now();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (!_isActive) return;
        _isActive = false;
        flush(restartActiveTimer: false);
        break;
    }
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
    await _storage.recordAnalyticsFeature(feature);
  }

  Future<void> flush({String? token, bool restartActiveTimer = true}) async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _captureActiveSeconds();
      final snapshot = await _storage.snapshotAnalyticsBufferForFlush();
      if (snapshot == null) return;
      final batchId = snapshot['batch_id'] as String;
      final days = snapshot['days'] as Map<String, dynamic>;
      final deviceId = await _storage.getOrCreateDeviceId();
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = await DeviceInfoHelper.instance;
      final payload = {
        'batch_id': batchId,
        'device_id': deviceId,
        'platform': defaultTargetPlatform.name,
        'app_version': packageInfo.version,
        'os_version': deviceInfo.osVersion,
        'device_model': deviceInfo.deviceModel,
        'days': days.entries.map((entry) {
          final value = Map<String, dynamic>.from(entry.value as Map);
          return {'date': entry.key, ...value};
        }).toList(),
      };
      final headers = await ApiHeaders.build(_storage, token: token);
      final response = await _routeClient.request(
        EndpointService.appApi,
        'POST',
        '/analytics/batch',
        headers: headers,
        body: json.encode(payload),
        timeout: const Duration(seconds: 10),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _storage.markAnalyticsFlushSuccess(batchId, days);
        await _storage.save(_lastFlushKey, DateTime.now().toIso8601String());
      }
      // 失败时保留 buffer 和 batch_id，下次 flush 以同一批次重试
    } catch (e) {
      debugPrint('Analytics flush failed: $e');
      unawaited(
        AppLog.debug('Analytics flush failed: $e', source: 'analytics'),
      );
    } finally {
      _flushing = false;
      _activeStartedAt = (restartActiveTimer || _isActive)
          ? DateTime.now()
          : null;
    }
  }

  Future<void> bindDevice(String token) async {
    try {
      final deviceId = await _storage.getOrCreateDeviceId();
      await _routeClient.request(
        EndpointService.appApi,
        'POST',
        '/analytics/bind-device',
        headers: await ApiHeaders.build(_storage, token: token),
        body: json.encode({'device_id': deviceId}),
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Analytics bind failed: $e');
      unawaited(AppLog.debug('Analytics bind failed: $e', source: 'analytics'));
    }
  }

  Future<void> _increment(String key, {int by = 1}) async {
    await _storage.incrementAnalyticsCounter(key, by: by);
  }

  Future<void> _incrementNested(String key, String name) async {
    await _storage.incrementAnalyticsNestedCounter(key, name);
  }

  Future<void> _captureActiveSeconds() async {
    final started = _activeStartedAt;
    if (started == null) return;
    final seconds = DateTime.now().difference(started).inSeconds;
    if (seconds <= 0) return;
    await _increment('active_seconds', by: seconds.clamp(0, 30 * 60));
  }
}
