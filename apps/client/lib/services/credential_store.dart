import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'storage_service.dart';

/// 登录凭据存储。
///
/// - 用户名 + "记住我"开关：普通本地存储（非敏感）。
/// - 密码：**仅原生平台**写入系统级安全存储（Keychain / Keystore / DPAPI），
///   通过 [FlutterSecureStorage] 实现，其它 App 读不到、且不进同步包。
/// - **Web 不保存密码**：Web 的 shared_preferences 即 localStorage 明文，
///   任何同源代码都能读取，无法安全保存可还原口令，故仅记住用户名。
class CredentialStore {
  CredentialStore(this._prefs);

  final StorageService _prefs;

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _rememberKey = '_saved_login_remember';
  static const _usernameKey = '_saved_login_username';
  static const _securePasswordKey = 'login_password_secure';
  // 历史版本在 shared_preferences 里混淆存储的密码键（需抹除）。
  static const _legacyPasswordKey = '_saved_login_password';

  Future<bool> get rememberMe async =>
      (await _prefs.load(_rememberKey) as bool?) ?? false;

  Future<String> loadUsername() async =>
      (await _prefs.load(_usernameKey) as String?) ?? '';

  /// 读取记住的密码。Web 恒为空；原生从安全存储读取。
  Future<String> loadPassword() async {
    await _purgeLegacyPassword();
    if (kIsWeb) return '';
    try {
      return await _secure.read(key: _securePasswordKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 保存凭据。用户名进普通存储；密码仅原生写安全存储。
  Future<void> save(String username, String password) async {
    await _prefs.save(_rememberKey, true);
    await _prefs.save(_usernameKey, username);
    if (kIsWeb) return;
    try {
      await _secure.write(key: _securePasswordKey, value: password);
    } catch (_) {
      // 安全存储不可用时静默失败，至少用户名已记住。
    }
  }

  /// 清除全部记住的凭据。
  Future<void> clear() async {
    await _prefs.save(_rememberKey, false);
    await _prefs.save(_usernameKey, '');
    await _purgeLegacyPassword();
    if (kIsWeb) return;
    try {
      await _secure.delete(key: _securePasswordKey);
    } catch (_) {}
  }

  /// 抹除历史明文/混淆密码遗留键（一次性清理，幂等）。
  Future<void> _purgeLegacyPassword() async {
    await _prefs.save(_legacyPasswordKey, null);
  }
}
