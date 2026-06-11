import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

/// 完整备份导出/导入的凭据安全（P0-1 / P0-2）。
/// - 导出：WebDAV 密码、GitHub/Gitee token、apiKey、登录态均脱敏，明文不外泄。
/// - 导入：脱敏占位符不覆盖本地真实凭据（round-trip 不损坏）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('exportAllData 脱敏 WebDAV 密码与 GitHub/Gitee token', () async {
    final storage = StorageService();
    await storage.saveSyncSettings(const SyncSettings(
      method: 'github',
      webDavPassword: 'wd_secret',
      githubToken: 'ghp_secret_token',
      giteeToken: 'gitee_secret_token',
    ));
    await storage.saveAiConfigs([
      const AiConfig(
        id: 'c1',
        name: 'n',
        baseUrl: 'https://api.example.com',
        apiKey: 'sk-secret-key',
        model: 'm',
      ),
    ]);

    final export = await storage.exportAllData();
    final settings =
        (export['data'] as Map)['sync_settings'] as Map<String, dynamic>;
    expect(settings['webDavPassword'], '[redacted]');
    expect(settings['githubToken'], '[redacted]');
    expect(settings['giteeToken'], '[redacted]');

    // 整个导出 JSON 不含任何凭据明文
    final jsonStr = jsonEncode(export);
    expect(jsonStr.contains('wd_secret'), isFalse);
    expect(jsonStr.contains('ghp_secret_token'), isFalse);
    expect(jsonStr.contains('gitee_secret_token'), isFalse);
    expect(jsonStr.contains('sk-secret-key'), isFalse);
  });

  test('importAllData 跳过占位符，保留本地真实凭据（round-trip）', () async {
    final storage = StorageService();
    await storage.saveSyncSettings(const SyncSettings(
      method: 'github',
      webDavPassword: 'real_wd',
      githubToken: 'real_gh',
      giteeToken: 'real_gitee',
    ));
    await storage.saveAiConfigs([
      const AiConfig(
        id: 'c1',
        name: 'n',
        baseUrl: 'https://api.example.com',
        apiKey: 'real_api_key',
        model: 'm',
      ),
    ]);

    // 导出（已脱敏）后再导入回本地，模拟用户用自己的备份文件恢复。
    final export = await storage.exportAllData();
    await storage
        .importAllData((export['data'] as Map).cast<String, dynamic>());

    final settings = await storage.loadSyncSettings();
    expect(settings.githubToken, 'real_gh', reason: '占位符不应覆盖本地 token');
    expect(settings.giteeToken, 'real_gitee');
    expect(settings.webDavPassword, 'real_wd');

    final configs = await storage.loadAiConfigs();
    expect(configs.single.apiKey, 'real_api_key', reason: '占位符不应覆盖本地 apiKey');
  });
}
