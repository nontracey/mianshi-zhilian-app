import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// 缓存一次设备信息（系统重启前不变），避免每次请求都异步获取。
class DeviceInfoHelper {
  static DeviceInfoHelper? _instance;
  String _osVersion = 'unknown';
  String _deviceModel = 'unknown';
  bool _loaded = false;

  DeviceInfoHelper._();

  static Future<DeviceInfoHelper> get instance async {
    if (_instance != null && _instance!._loaded) return _instance!;
    _instance = DeviceInfoHelper._();
    await _instance!._fetch();
    return _instance!;
  }

  String get osVersion => _osVersion;
  String get deviceModel => _deviceModel;

  Future<void> _fetch() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await plugin.androidInfo;
        _osVersion = info.version.release;
        _deviceModel = '${info.manufacturer} ${info.model}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await plugin.iosInfo;
        _osVersion = info.systemVersion;
        _deviceModel = info.model;
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final info = await plugin.macOsInfo;
        _osVersion = info.osRelease;
        _deviceModel = info.model;
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final info = await plugin.windowsInfo;
        _osVersion = info.releaseId;
        _deviceModel = info.computerName;
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        final info = await plugin.linuxInfo;
        _osVersion = info.versionId ?? 'unknown';
        _deviceModel = info.prettyName;
      }
      _loaded = true;
    } catch (_) {
      // Web 或获取失败时保持 'unknown'
      _loaded = true;
    }
  }
}
