import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 内容静态资源（SVG / 位图）的文件缓存。
///
/// 生命周期与 topic 缓存（SharedPreferences 中的 `content_cache_*`）一致：
/// [ContentProvider.clearAllCache] / [StorageService.clearCacheData] 时
/// 同时调用 [clear] 清理磁盘文件。
///
/// Web 平台不支持文件系统，所有方法退化为 no-op，仅依赖内存缓存。
class ContentAssetCache {
  ContentAssetCache._();
  static final ContentAssetCache instance = ContentAssetCache._();

  Directory? _cacheDir;
  bool _dirInitialized = false;

  Future<Directory?> _getCacheDir() async {
    if (_dirInitialized) return _cacheDir;
    _dirInitialized = true;
    if (kIsWeb) return null;
    try {
      final temp = await getTemporaryDirectory();
      _cacheDir = Directory('${temp.path}/content_assets');
      if (!_cacheDir!.existsSync()) {
        _cacheDir!.createSync(recursive: true);
      }
    } catch (_) {
      _cacheDir = null;
    }
    return _cacheDir;
  }

  String _fileName(String url) => 'a${url.hashCode.abs().toRadixString(16)}';

  /// 读取缓存的原始字节。未命中返回 null。
  /// 使用异步 I/O 避免阻塞主 isolate。
  Future<Uint8List?> readBytes(String url) async {
    final dir = await _getCacheDir();
    if (dir == null) return null;
    final file = File('${dir.path}/${_fileName(url)}');
    if (!file.existsSync()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// 写入原始字节到缓存。
  Future<void> writeBytes(String url, Uint8List bytes) async {
    final dir = await _getCacheDir();
    if (dir == null) return;
    try {
      final file = File('${dir.path}/${_fileName(url)}');
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  /// 读取缓存的文本（用于 SVG 改写后的文本）。未命中返回 null。
  Future<String?> readString(String url) async {
    final bytes = await readBytes(url);
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 写入文本到缓存。
  Future<void> writeString(String url, String text) async {
    await writeBytes(url, Uint8List.fromList(utf8.encode(text)));
  }

  /// 清除所有缓存文件。与 topic 缓存清理同步调用。
  Future<void> clear() async {
    final dir = await _getCacheDir();
    if (dir == null) return;
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
      }
    } catch (_) {}
  }
}
