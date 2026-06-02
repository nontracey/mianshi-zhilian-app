import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_headers.dart';
import 'storage_service.dart';

/// R2 图片上传 / 删除服务。
///
/// 客户端约定：
/// - 工单图片：先调 `uploadImage(bytes)` 拿到 R2 URL，再把 URL 数组交给工单提交。
/// - 头像：data_sync 阶段统一把本地 base64/file path 上传到 R2，并把 R2 URL 写回本地。
/// - 删除：`deleteAvatar(url)` 仅删 `avatars/{userId}/` 路径下的对象（后端会校验所有权）。
class UploadService {
  UploadService({
    required StorageService storage,
    required String? Function() getApiUrl,
    String? Function()? getToken,
  })  : _storage = storage,
        _getApiUrl = getApiUrl,
        _getToken = getToken;

  final StorageService _storage;
  final String? Function() _getApiUrl;
  final String? Function()? _getToken;

  static const _timeout = Duration(seconds: 30);

  /// 工单图片上传（无需登录，公开端点）。
  /// 客户端在调工单提交前应先调此接口，避免 base64 直接进 D1。
  Future<String> uploadImage({
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final apiUrl = _getApiUrl();
    if (apiUrl == null || apiUrl.isEmpty) {
      throw StateError('API URL 未配置');
    }
    final dataUrl = 'data:${mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}';
    final response = await http
        .post(
          Uri.parse('$apiUrl/uploads/image'),
          headers: await ApiHeaders.build(_storage, json: true),
          body: json.encode({'data_url': dataUrl}),
        )
        .timeout(_timeout);
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['success'] != true) {
      throw StateError(data['error']?.toString() ?? '上传失败 (${response.statusCode})');
    }
    return data['url'] as String;
  }

  /// 头像上传（需要登录）。后端会把对象存到 `avatars/{userId}/` 路径下。
  /// 客户端应把返回的 R2 URL 写回 `user_profile.avatarUrl`。
  Future<String> uploadAvatar({
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final apiUrl = _getApiUrl();
    if (apiUrl == null || apiUrl.isEmpty) {
      throw StateError('API URL 未配置');
    }
    final token = _getToken?.call();
    if (token == null || token.isEmpty) {
      throw StateError('未登录');
    }
    final dataUrl = 'data:${mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}';
    final response = await http
        .post(
          Uri.parse('$apiUrl/uploads/avatar'),
          headers: await ApiHeaders.build(_storage, token: token),
          body: json.encode({'data_url': dataUrl}),
        )
        .timeout(_timeout);
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['success'] != true) {
      throw StateError(data['error']?.toString() ?? '头像上传失败 (${response.statusCode})');
    }
    return data['url'] as String;
  }

  /// 删除头像（需要登录）。后端会校验 URL 是否属于本用户的 `avatars/{userId}/`。
  /// 删除失败不抛异常（孤儿文件不影响后续同步）。
  Future<bool> deleteAvatar({required String url}) async {
    try {
      final apiUrl = _getApiUrl();
      if (apiUrl == null || apiUrl.isEmpty) return false;
      final token = _getToken?.call();
      if (token == null || token.isEmpty) return false;
      final response = await http
          .delete(
            Uri.parse('$apiUrl/uploads/avatar'),
            headers: await ApiHeaders.build(_storage, token: token),
            body: json.encode({'url': url}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('deleteAvatar: ${response.statusCode}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('deleteAvatar error: $e');
      return false;
    }
  }
}
