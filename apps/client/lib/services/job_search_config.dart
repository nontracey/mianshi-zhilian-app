/// 岗位搜索通道装配（§6.7）。
///
/// 三种状态必须严格区分，不能混为一谈：
/// - `off`：用户没配任何通道 → UI 如实说“未配置”，给链接导入/粘贴的替代入口；
/// - `custom`：用户自配的搜索服务 → 真实结果，覆盖范围由用户自己的服务决定；
/// - `demo`：本机合成通道 → 让用户能走通流程，但**必须**标注为演示数据，
///   不能冒充真实招聘信息。
///
/// 凭据不进 SharedPreferences：endpoint 存设置，apiKey 只进系统安全存储。
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../coach/domain/common.dart';
import '../coach/jobs/local_demo_search.dart';
import '../coach/jobs/models.dart';
import '../coach/jobs/search_service.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';
import 'coach_http_client.dart';
import 'job_search_transport.dart';
import 'zhaopin_public_search.dart';

export '../coach/jobs/models.dart' show JobSearchMode;

/// 搜索通道状态（UI 直接消费，不猜）。
class JobSearchChannelState {
  const JobSearchChannelState({
    required this.mode,
    required this.configured,
    this.endpoint,
    this.noteKey,
  });

  final String mode;
  final bool configured;
  final String? endpoint;

  /// 需要如实告诉用户的说明（l10n key），可为 null。
  final String? noteKey;

  bool get isDemo => mode == JobSearchMode.demo;
}

/// 根据设置装配搜索通道；设置变化后调用 [sync] 重建。
class JobSearchConfigController extends ChangeNotifier {
  JobSearchConfigController({
    required StorageService storage,
    JobSearchTransport? customTransport,
    JobSearchTransport? demoTransport,
    IdGenerator? idGen,
  }) : _storage = storage,
       _injectedTransport = customTransport,
       _idGen = idGen ?? IdGenerator(),
       _demoTransport = demoTransport ?? const LocalDemoJobSearchTransport();

  final StorageService _storage;
  final JobSearchTransport? _injectedTransport;
  JobSearchTransport? _customTransport;
  final CoachHttpClient _http = CoachHttpClient();
  final JobSearchTransport _demoTransport;
  final IdGenerator _idGen;

  String _mode = JobSearchMode.off;
  String _endpoint = '';
  String? _apiKey;
  int _syncRevision = 0;

  String _secretSlot(String endpoint) =>
      '${StorageService.jobSearchApiKeySlot}_${sha256.convert(utf8.encode(endpoint.trim()))}';

  /// 当前通道状态。
  JobSearchChannelState get state => JobSearchChannelState(
    mode: _mode,
    configured: service != null,
    endpoint: _endpoint.isEmpty ? null : _endpoint,
    noteKey: _mode == JobSearchMode.demo
        ? LocalDemoJobSearchTransport.demoNoteKey
        : null,
  );

  /// 当前可用的岗位发现服务；未配置时为 null（UI 必须照实提示）。
  JobDiscoveryService? get service {
    switch (_mode) {
      case JobSearchMode.zhaopinPublic:
        return WebSearchJobAdapter(
          transport: ZhaopinPublicSearchTransport(),
          idGen: _idGen,
          platform: JobPlatform.zhaopin,
        );
      case JobSearchMode.custom:
        final transport = _customTransport;
        if (_endpoint.trim().isEmpty || transport == null) return null;
        return WebSearchJobAdapter(transport: transport, idGen: _idGen);
      case JobSearchMode.demo:
        return WebSearchJobAdapter(
          transport: _demoTransport,
          idGen: _idGen,
          platform: JobPlatform.demo,
          completeness: 'demo',
        );
      default:
        return null;
    }
  }

  /// 幂等版 [sync]：设置没变就不重建（可在每次 rebuild 时安全调用）。
  Future<void> syncIfChanged(AppSettings settings) async {
    final mode = JobSearchMode.normalize(settings.jobSearchMode);
    final endpoint = settings.jobSearchEndpoint?.trim() ?? '';
    if (mode == _mode && endpoint == _endpoint && _syncedOnce) return;
    await sync(settings);
  }

  bool _syncedOnce = false;

  /// 用当前设置重建通道（apiKey 从安全存储读，不落明文）。
  Future<void> sync(AppSettings settings) async {
    final revision = ++_syncRevision;
    final mode = JobSearchMode.normalize(settings.jobSearchMode);
    final endpoint = settings.jobSearchEndpoint?.trim() ?? '';
    final key = mode == JobSearchMode.custom
        ? await _storage.readSecret(_secretSlot(endpoint))
        : null;
    if (revision != _syncRevision) return;
    _syncedOnce = true;
    _mode = mode;
    _endpoint = endpoint;
    _apiKey = key;
    _rebuild();
  }

  void _rebuild() {
    if (_mode == JobSearchMode.custom && _endpoint.isNotEmpty) {
      _customTransport =
          _injectedTransport ??
          HttpJobSearchTransport(
            http: _http,
            endpoint: _endpoint,
            apiKey: _apiKey,
          );
    } else {
      _customTransport = null;
    }
    notifyListeners();
  }

  /// 保存用户配置；返回是否写成功。
  ///
  /// apiKey 为空表示清除（走安全存储删除），不会被写成空字符串蒙混过关。
  Future<bool> configure({
    required String mode,
    String endpoint = '',
    String? apiKey,
  }) async {
    final normalized = JobSearchMode.normalize(mode);
    if (normalized == JobSearchMode.custom && apiKey != null) {
      final ok = await _storage.writeSecret(_secretSlot(endpoint), apiKey);
      if (!ok) return false;
    } else if (normalized != JobSearchMode.custom) {
      await _storage.deleteSecret(_secretSlot(_endpoint));
    }
    ++_syncRevision;
    _mode = normalized;
    _endpoint = endpoint.trim();
    _apiKey = normalized == JobSearchMode.custom
        ? (apiKey ?? await _storage.readSecret(_secretSlot(endpoint)))
        : null;
    _rebuild();
    return true;
  }

  /// 当前是否已保存过 key（不回传明文，只给 UI 一个“已填/未填”信号）。
  Future<bool> hasStoredApiKey() async =>
      (_apiKey ?? await _storage.readSecret(_secretSlot(_endpoint)))
          ?.isNotEmpty ??
      false;
  Future<String?> storedKeyFor(String endpoint) =>
      _storage.readSecret(_secretSlot(endpoint));

  @override
  void dispose() {
    ++_syncRevision;
    _http.close();
    super.dispose();
  }
}
