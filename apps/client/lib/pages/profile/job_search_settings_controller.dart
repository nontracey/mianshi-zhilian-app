/// 岗位搜索通道设置的表单状态与副作用（保存 / 测试连接）。
///
/// 单独拆出来是为了让页面只管渲染：密钥处理、保存失败语义、连接测试都在这里，
/// 也便于单测而不必 pump 整个页面。
library;

import 'package:flutter/widgets.dart';

import '../../coach/jobs/local_demo_search.dart';
import '../../coach/jobs/models.dart';
import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';
import '../../services/coach_http_client.dart';
import '../../services/job_search_config.dart';
import '../../services/job_search_transport.dart';
import '../../services/zhaopin_public_search.dart';

class JobSearchSettingsController extends ChangeNotifier {
  JobSearchSettingsController();

  final endpoint = TextEditingController();
  final apiKey = TextEditingController();

  String _mode = JobSearchMode.off;
  bool _hasStoredKey = false;
  bool _saving = false;
  bool _testing = false;
  String? _testResultKey;
  bool _testOk = false;

  String get mode => _mode;
  bool get hasStoredKey => _hasStoredKey;
  bool get saving => _saving;
  bool get testing => _testing;
  String? get testResultKey => _testResultKey;
  bool get testOk => _testOk;

  void loadFrom(AppSettings settings) {
    _mode = JobSearchMode.normalize(settings.jobSearchMode);
    endpoint.text = settings.jobSearchEndpoint ?? '';
    notifyListeners();
  }

  void setMode(String mode) {
    _mode = JobSearchMode.normalize(mode);
    _testResultKey = null;
    notifyListeners();
  }

  /// 读取已保存 key 的存在性（不回显明文）。
  Future<void> refreshStoredKey(JobSearchConfigController config) async {
    _hasStoredKey = await config.hasStoredApiKey();
    notifyListeners();
  }

  /// 保存：先写凭据（失败即停，不留半套配置），再改设置。
  Future<bool> save({
    required SettingsProvider settings,
    required JobSearchConfigController config,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      final ok = await config.configure(
        mode: _mode,
        endpoint: endpoint.text,
        // 留空表示“不改动已保存的 key”；要清除就切到「关闭」。
        apiKey: _mode == JobSearchMode.custom && apiKey.text.isNotEmpty
            ? apiKey.text
            : null,
      );
      if (!ok) return false;
      await settings.setJobSearchConfig(
        mode: _mode,
        endpoint: _mode == JobSearchMode.custom ? endpoint.text : null,
      );
      apiKey.clear();
      _hasStoredKey = await config.hasStoredApiKey();
      return true;
    } catch (_) {
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// 用一次最小查询验证通道是否真的可用。
  Future<void> testConnection({JobSearchConfigController? config}) async {
    _testing = true;
    _testResultKey = null;
    notifyListeners();
    var ok = false;
    try {
      if (_mode == JobSearchMode.off) {
        ok = false;
      } else if (_mode == JobSearchMode.zhaopinPublic) {
        await ZhaopinPublicSearchTransport().fetch(
          SearchQuery(keywords: 'Java'),
        );
        ok = true;
      } else if (_mode == JobSearchMode.demo) {
        // 演示通道不需要联网，能构造出结果即视为可用。
        ok = const LocalDemoJobSearchTransport()
            .buildDemoJobs(SearchQuery(keywords: 'test', region: ''))
            .isNotEmpty;
      } else {
        final text = endpoint.text.trim();
        if (text.isEmpty) {
          ok = false;
        } else {
          final http = CoachHttpClient();
          try {
            final transport = HttpJobSearchTransport(
              http: http,
              endpoint: text,
              apiKey: apiKey.text.isEmpty
                  ? await config?.storedKeyFor(text)
                  : apiKey.text,
            );
            final resp = await transport.fetch(
              SearchQuery(keywords: '__probe__', pageSize: 1),
            );
            // 返回 0 条也算连通；抛异常（未配置/协议错/HTTP 错）才算失败。
            ok = resp.items.isNotEmpty || !resp.truncated;
          } finally {
            http.close();
          }
        }
      }
    } catch (_) {
      ok = false;
    } finally {
      _testOk = ok;
      _testResultKey = ok
          ? 'coach_job_search_test_ok'
          : 'coach_job_search_test_failed';
      _testing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    endpoint.dispose();
    apiKey.dispose();
    super.dispose();
  }
}
