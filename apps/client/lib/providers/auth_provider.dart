import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final StorageService _storage;
  final String apiBaseUrl;

  AuthProvider(
    this._storage, {
    this.apiBaseUrl = 'https://mianshi-zhilian-api.nontracey.workers.dev',
  });

  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  String? get token => _token;
  bool get isLoggedIn => _user != null && _token != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 加载已保存的用户信息
  Future<void> loadUser() async {
    try {
      final userData = await _storage.load('auth_user');
      if (userData != null && userData is Map<String, dynamic>) {
        _user = User.fromJson(userData);
        _token = await _storage.load('auth_token') as String?;
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
      final response = await http.post(
        Uri.parse('$apiBaseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'nickname': nickname,
        }),
      );

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        _user = User.fromJson(data['user'] as Map<String, dynamic>);
        _token = data['token'] as String;
        await _saveUser();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = data['error'] as String? ?? '注册失败';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = '网络错误：$e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 登录
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        _user = User.fromJson(data['user'] as Map<String, dynamic>);
        _token = data['token'] as String;
        await _saveUser();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = data['error'] as String? ?? '登录失败';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = '网络错误：$e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 退出登录
  Future<void> logout() async {
    _user = null;
    _token = null;
    await _storage.save('auth_user', null);
    await _storage.save('auth_token', null);
    notifyListeners();
  }

  /// 保存用户信息到本地
  Future<void> _saveUser() async {
    if (_user != null) {
      await _storage.save('auth_user', _user!.toJson());
    }
    if (_token != null) {
      await _storage.save('auth_token', _token);
    }
  }

  /// 上传学习进度到云端
  Future<bool> syncToCloud(
    Map<String, dynamic> progressMap,
    Map<String, dynamic> settings,
  ) async {
    if (!isLoggedIn) return false;

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/sync/progress'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({'progressMap': progressMap, 'settings': settings}),
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
      final response = await http.get(
        Uri.parse('$apiBaseUrl/sync/progress'),
        headers: {'Authorization': 'Bearer $_token'},
      );

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
      _error = '请先登录';
      notifyListeners();
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/auth/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        final data = json.decode(response.body);
        _error = data['error'] ?? '修改密码失败';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = '网络错误：$e';
      notifyListeners();
      return false;
    }
  }
}
