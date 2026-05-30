import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

/// WebDAV 同步服务：支持备份（上传）和恢复（下载）
class WebDavSyncService {
  WebDavSyncService(this._storage);
  final StorageService _storage;

  static const _timeout = Duration(seconds: 30);

  /// 测试 WebDAV 连接
  Future<SyncResult> testConnection({
    required String url,
    required String username,
    required String password,
  }) async {
    final base = _normalizeUrl(url);
    if (base == null) return SyncResult.failure('请输入有效的 WebDAV 地址');
    try {
      final uri = Uri.parse('$base/');
      final response = await _request('PROPFIND', uri, username, password, {
        'Depth': '0',
      });
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SyncResult.success('连接成功');
      }
      if (response.statusCode == 401) {
        return SyncResult.failure('认证失败，请检查用户名和密码');
      }
      return SyncResult.failure('连接失败：${response.statusCode}');
    } catch (e) {
      return SyncResult.failure('连接错误：$e');
    }
  }

  /// 备份数据到 WebDAV
  Future<SyncResult> backup({
    required String url,
    required String username,
    required String password,
  }) async {
    final base = _normalizeUrl(url);
    if (base == null) return SyncResult.failure('请输入有效的 WebDAV 地址');
    try {
      final fullData = await _storage.exportAllDataRaw();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(fullData);

      final uri = Uri.parse('$base/mianshi-zhilian-backup.json');

      final response = await _request('PUT', uri, username, password, {
        'Content-Type': 'application/json; charset=utf-8',
      }, jsonStr);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _storage.setLastSyncTime(DateTime.now());
        return SyncResult.success('备份完成');
      }
      return SyncResult.failure('备份失败：${response.statusCode}');
    } catch (e) {
      return SyncResult.failure('备份错误：$e');
    }
  }

  /// 从 WebDAV 恢复数据
  Future<SyncResult> restore({
    required String url,
    required String username,
    required String password,
  }) async {
    final base = _normalizeUrl(url);
    if (base == null) return SyncResult.failure('请输入有效的 WebDAV 地址');
    try {
      final uri = Uri.parse('$base/mianshi-zhilian-backup.json');

      final response = await _request('GET', uri, username, password);

      if (response.statusCode == 404) {
        return SyncResult.failure('云端无备份文件');
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = utf8.decode(response.bodyBytes);
        final Map<String, dynamic> remoteData = json.decode(body);

        final data = remoteData['data'] as Map<String, dynamic>?;
        if (data == null) {
          return SyncResult.failure('备份文件格式错误');
        }

        await _storage.importAllData(data);
        return SyncResult.success('恢复完成，共导入 ${data.length} 项数据');
      }
      return SyncResult.failure('下载失败：${response.statusCode}');
    } catch (e) {
      return SyncResult.failure('恢复错误：$e');
    }
  }

  /// 获取 WebDAV 备份文件信息
  Future<SyncFileInfo?> getRemoteFileInfo({
    required String url,
    required String username,
    required String password,
  }) async {
    final base = _normalizeUrl(url);
    if (base == null) return const SyncFileInfo(exists: false);
    try {
      final uri = Uri.parse('$base/mianshi-zhilian-backup.json');

      final response = await _request('HEAD', uri, username, password);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final contentLength = response.headers['content-length'];
        final lastModified = response.headers['last-modified'];
        return SyncFileInfo(
          exists: true,
          size: contentLength != null ? int.tryParse(contentLength) : null,
          lastModified: lastModified,
        );
      }
      return const SyncFileInfo(exists: false);
    } catch (_) {
      return const SyncFileInfo(exists: false);
    }
  }

  String? _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    String username,
    String password, [
    Map<String, String>? headers,
    String? body,
  ]) async {
    final request = http.Request(method, uri);
    final basic = base64Encode(utf8.encode('$username:$password'));
    request.headers['Authorization'] = 'Basic $basic';
    if (headers != null) {
      request.headers.addAll(headers);
    }
    if (body != null) {
      request.body = body;
    }
    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(_timeout);
      return http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }
}

class SyncResult {
  final bool success;
  final String message;
  const SyncResult._(this.success, this.message);
  factory SyncResult.success(String msg) => SyncResult._(true, msg);
  factory SyncResult.failure(String msg) => SyncResult._(false, msg);
}

class SyncFileInfo {
  final bool exists;
  final int? size;
  final String? lastModified;
  const SyncFileInfo({required this.exists, this.size, this.lastModified});
}
