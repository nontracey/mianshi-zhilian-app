import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'device_info_helper.dart';
import 'storage_service.dart';

class ApiHeaders {
  static Future<Map<String, String>> build(
    StorageService storage, {
    String? token,
    bool json = true,
  }) async {
    final deviceId = await storage.getOrCreateDeviceId();
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = await DeviceInfoHelper.instance;
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'X-Device-Id': deviceId,
      'X-Platform': defaultTargetPlatform.name,
      'X-App-Version': packageInfo.version,
      'X-OS-Version': deviceInfo.osVersion,
      'X-Device-Model': deviceInfo.deviceModel,
    };
  }
}
