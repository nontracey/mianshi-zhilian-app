import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

const _runtimePlatformChannel = MethodChannel('mianshi_zhilian/runtime');

/// 返回当前平台的本机运行时架构标识。
///
/// macOS/Linux：'aarch64' 或 'x64'
/// Android：'arm64-v8a' / 'armeabi-v7a' / 'x86_64' / 'x86'
/// 其他平台：'x64'
String currentSherpaOnnxRuntimeArch() {
  final abi = Abi.current();
  // Android ABIs
  if (abi == Abi.androidArm64) return 'arm64-v8a';
  if (abi == Abi.androidArm) return 'armeabi-v7a';
  if (abi == Abi.androidX64) return 'x86_64';
  if (abi == Abi.androidIA32) return 'x86';
  // macOS / Linux
  if (abi == Abi.macosArm64 || abi == Abi.linuxArm64) return 'aarch64';
  return 'x64';
}

Future<AndroidRuntimeInfo?> currentAndroidRuntimeInfo() async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await _runtimePlatformChannel
        .invokeMapMethod<String, Object?>('getAndroidRuntimeInfo');
    if (result == null) return null;
    return AndroidRuntimeInfo(
      is64Bit: result['is64Bit'] as bool? ?? false,
      supportedAbis: (result['supportedAbis'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      supported64BitAbis:
          (result['supported64BitAbis'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(),
      supported32BitAbis:
          (result['supported32BitAbis'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(),
    );
  } catch (_) {
    return null;
  }
}

class AndroidRuntimeInfo {
  const AndroidRuntimeInfo({
    required this.is64Bit,
    required this.supportedAbis,
    required this.supported64BitAbis,
    required this.supported32BitAbis,
  });

  final bool is64Bit;
  final List<String> supportedAbis;
  final List<String> supported64BitAbis;
  final List<String> supported32BitAbis;
}
