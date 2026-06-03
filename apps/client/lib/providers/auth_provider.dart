import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../l10n/l10n.dart';
import '../models/user.dart';
import '../services/api_headers.dart';
import '../services/endpoint_fallback_client.dart';
import '../services/route_resolver.dart';
import '../services/route_state_store.dart';
import '../services/storage_service.dart';

/// Access token 有效期为 24h，按一半间隔 12h 主动刷新，确保 token 不过期。
/// 定时器只在登录后启动，登出/刷新失败时自动取消。
const _refreshInterval = Duration(hours: 12);

class AuthProvider extends ChangeNotifier {
  final StorageService _storage;
  final EndpointFallbackClient _routeClient;

  AuthProvider(this._storage, {EndpointFallbackClient? routeClient})
    : _routeClient =
          routeClient ??
          EndpointFallbackClient(stateStore: RouteStateStore(_storage));

  User? _user;
  String? _token;
  String? _refreshToken;
  Future<bool>? _refreshFuture;
  Timer? _refreshTimer;
  bool _isLoading = false;
  String? _error;

  /// 当 token 过期且刷新失败、用户被静默登出时，发出原因通知。
  /// UI 可以监听此 notifier 以弹出非侵入式提示。
  final autoLogoutReason = ValueNotifier<String?>(null);

  User? get user => _user;
  String? get token => _token;
  String get apiBaseUrl => RouteResolver.appApiPrimary;
  bool get isLoggedIn => _user != null && _token != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 获取用户角色，未登录返回 guest
  UserRole get userRole => _user?.role ?? UserRole.guest;

  /// 公开的刷新方法，供外部（如其他 Provider）在收到 401 时调用。
  Future<bool> refreshLogin() => _refreshLogin();

  /// 启动定时刷新周期。每次刷新成功后重置计时器。
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      // 后台静默刷新，不阻塞 UI
      if (_refreshToken != null) {
        _refreshLogin();
      }
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    autoLogoutReason.dispose();
    super.dispose();
  }

  /// 加载已保存的用户信息
  Future<void> loadUser() async {
    try {
      final userData = await _storage.load('auth_user');
      if (userData != null && userData is Map<String, dynamic>) {
        _user = User.fromJson(userData);
        _token = await _storage.load('auth_token') as String?;
        _refreshToken = await _storage.load('auth_refresh_token') as String?;

        // 先尝试 refresh 再通知 UI，避免闪一下「已登录」又被清空
        if (_refreshToken != null) {
          final refreshed = await _refreshLogin();
          if (refreshed) {
            _startRefreshTimer();
          }
          if (!refreshed && _user == null) {
            // 401/403 → _clearSavedUser 已清空状态，无需再 notify
            return;
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load user: $e');
    }
  }

  /// 注册
  Future<bool> register(
    String username,
    String password, {
    String? nickname,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final passwordHash = _hashPassword(password);
      final response = await _routeClient.request(
        RouteService.appApi,
        'POST',
        '/auth/register',
        headers: await ApiHeaders.build(_storage),
        body: json.encode({
          'username': username,
          'password_hash': passwordHash,
          'nickname': nickname,
        }),
      );

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        _user = User.fromJson(data['user'] as Map<String, dynamic>);
        _token = data['token'] as String;
        _refreshToken = data['refreshToken'] as String?;
        await _saveUser();
        await _storage.recordAnalyticsFeature('login');
        _bindDevice();
        _startRefreshTimer();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = data['error'] as String? ?? L10n.get('register_failed', 'zh');
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = L10n.getp('network_error', 'zh', {'error': '$e'});
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // PBKDF2 参数（与服务端 CLIENT_PBKDF2_SALT 保持一致）
  static const String _pbkdf2Salt = 'mianshi-zhilian-v1';
  static const int _pbkdf2Iterations = 10000;
  static const int _pbkdf2KeyLength = 32;

  /// PBKDF2-HMAC-SHA256 客户端哈希（双层方案第一层）
  String _hashPassword(String password) {
    return _pbkdf2(password, _pbkdf2Salt, _pbkdf2Iterations, _pbkdf2KeyLength);
  }

  /// PBKDF2-HMAC-SHA256 手动实现（crypto 3.0.7 不含内置 Pbkdf2）
  static String _pbkdf2(
    String password,
    String salt,
    int iterations,
    int keyLength,
  ) {
    const hLen = 32; // SHA-256 输出字节数
    final passwordBytes = utf8.encode(password);
    final saltBytes = utf8.encode(salt);
    final blockCount = (keyLength / hLen).ceil();
    final result = <int>[];

    for (int block = 1; block <= blockCount; block++) {
      // U₁ = HMAC-SHA256(Password, Salt || INT_32_BE(block))
      final blockBytes = ByteData(4)..setUint32(0, block, Endian.big);
      final input = Uint8List(saltBytes.length + 4)
        ..setRange(0, saltBytes.length, saltBytes)
        ..setRange(
          saltBytes.length,
          saltBytes.length + 4,
          blockBytes.buffer.asUint8List(),
        );

      var u = Hmac(sha256, passwordBytes).convert(input).bytes;
      var t = Uint8List.fromList(u);

      // T = U₁ ⊕ U₂ ⊕ ... ⊕ U_iterations
      for (int i = 2; i <= iterations; i++) {
        u = Hmac(sha256, passwordBytes).convert(u).bytes;
        for (int j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      result.addAll(t);
    }

    return base64.encode(result.sublist(0, keyLength));
  }

  /// 登录
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final passwordHash = _hashPassword(password);
      final headers = await ApiHeaders.build(_storage);
      final response = await _routeClient.request(
        RouteService.appApi,
        'POST',
        '/auth/login',
        headers: headers,
        body: json.encode({
          'username': username,
          'password_hash': passwordHash,
        }),
        timeout: const Duration(seconds: 15),
      );

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        _user = User.fromJson(data['user'] as Map<String, dynamic>);
        _token = data['token'] as String;
        _refreshToken = data['refreshToken'] as String?;
        await _saveUser();
        await _storage.recordAnalyticsFeature('login');
        // 设备绑定不阻塞登录返回
        _bindDevice();
        _startRefreshTimer();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = data['error'] as String? ?? L10n.get('login_failed', 'zh');
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on TimeoutException {
      debugPrint('Login: timeout');
      _error = L10n.get('network_timeout', 'zh');
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Login error: $e');
      _error = L10n.getp('network_error', 'zh', {'error': '$e'});
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 退出登录
  Future<void> logout() async {
    final refreshToken = _refreshToken;
    if (refreshToken != null) {
      try {
        await _routeClient.request(
          RouteService.appApi,
          'POST',
          '/auth/logout',
          headers: await ApiHeaders.build(_storage),
          body: json.encode({'refreshToken': refreshToken}),
        );
      } catch (e) {
        debugPrint('Logout revoke failed: $e');
      }
    }

    _user = null;
    _token = null;
    _refreshToken = null;
    _stopRefreshTimer();
    autoLogoutReason.value = null;
    await _storage.save('auth_user', null);
    await _storage.save('auth_token', null);
    await _storage.save('auth_refresh_token', null);
    notifyListeners();
  }

  /// 保存用户信息到本地
  Future<void> _saveUser() async {
    await _storage.save('auth_user', _user?.toJson());
    await _storage.save('auth_token', _token);
    await _storage.save('auth_refresh_token', _refreshToken);
  }

  Future<void> _clearSavedUser() async {
    _user = null;
    _token = null;
    _refreshToken = null;
    _stopRefreshTimer();
    autoLogoutReason.value = '登录已过期，可继续学习，但云端同步等账号功能将不可用';
    await _storage.save('auth_user', null);
    await _storage.save('auth_token', null);
    await _storage.save('auth_refresh_token', null);
    notifyListeners();
  }

  Future<bool> _refreshLogin() async {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;

    final refreshFuture = _doRefreshLogin();
    _refreshFuture = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<bool> _doRefreshLogin() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;

    try {
      final response = await _routeClient.request(
        RouteService.appApi,
        'POST',
        '/auth/refresh',
        headers: await ApiHeaders.build(_storage),
        body: json.encode({'refreshToken': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          _user = User.fromJson(data['user'] as Map<String, dynamic>);
          _token = data['token'] as String;
          _refreshToken = data['refreshToken'] as String?;
          await _saveUser();
          _bindDevice();
          _startRefreshTimer(); // 刷新成功后重置计时器
          notifyListeners();
          return true;
        }
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        await _clearSavedUser();
      }
      return false;
    } catch (e) {
      debugPrint('Refresh login failed: $e');
      return false;
    }
  }

  Future<void> _bindDevice() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      final deviceId = await _storage.getOrCreateDeviceId();
      await _routeClient.request(
        RouteService.appApi,
        'POST',
        '/analytics/bind-device',
        headers: await ApiHeaders.build(_storage, token: token),
        body: json.encode({'device_id': deviceId}),
        timeout: const Duration(seconds: 8),
      );
    } catch (e) {
      debugPrint('Bind device failed: $e');
    }
  }

  Future<http.Response> _authorizedPost(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    Future<http.Response> send() async {
      return _routeClient.request(
        RouteService.appApi,
        'POST',
        path,
        headers: await ApiHeaders.build(_storage, token: _token),
        body: json.encode(body ?? {}),
      );
    }

    var response = await send();
    if (response.statusCode == 401 && await _refreshLogin()) {
      response = await send();
    }
    return response;
  }

  Future<http.Response> _authorizedGet(String path) async {
    Future<http.Response> send() async {
      return _routeClient.request(
        RouteService.appApi,
        'GET',
        path,
        headers: await ApiHeaders.build(_storage, token: _token, json: false),
      );
    }

    var response = await send();
    if (response.statusCode == 401 && await _refreshLogin()) {
      response = await send();
    }
    return response;
  }

  /// 上传学习进度到云端
  Future<bool> syncToCloud(
    Map<String, dynamic> progressMap,
    Map<String, dynamic> settings,
  ) async {
    if (!isLoggedIn) return false;

    try {
      final response = await _authorizedPost(
        '/sync/progress',
        body: {'progressMap': progressMap, 'settings': settings},
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Sync to cloud failed: $e');
      return false;
    }
  }

  /// 从云端获取学习进度
  Future<Map<String, dynamic>?> getCloudProgress() async {
    if (!isLoggedIn) return null;

    try {
      final response = await _authorizedGet('/sync/progress');

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Get cloud progress failed: $e');
      return null;
    }
  }

  /// 修改密码
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (!isLoggedIn) {
      _error = L10n.get('please_login_first', 'zh');
      notifyListeners();
      return false;
    }

    try {
      final response = await _authorizedPost(
        '/auth/change-password',
        body: {
          'old_password_hash': _hashPassword(oldPassword),
          'new_password_hash': _hashPassword(newPassword),
        },
      );

      if (response.statusCode == 200) {
        await _clearSavedUser();
        return true;
      } else {
        final data = json.decode(response.body);
        _error = data['error'] ?? L10n.get('change_password_failed', 'zh');
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = L10n.getp('network_error', 'zh', {'error': '$e'});
      notifyListeners();
      return false;
    }
  }
}
