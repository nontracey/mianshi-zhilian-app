import 'dart:ffi';

/// 返回当前平台的本机运行时架构标识。
///
/// macOS/Linux：'aarch64' 或 'x64'
/// Android：'arm64-v8a' / 'armeabi-v7a' / 'x86_64'
/// 其他平台：'x64'
String currentSherpaOnnxRuntimeArch() {
  final abi = Abi.current();
  // Android ABIs
  if (abi == Abi.androidArm64) return 'arm64-v8a';
  if (abi == Abi.androidArm) return 'armeabi-v7a';
  if (abi == Abi.androidX64) return 'x86_64';
  // macOS / Linux
  if (abi == Abi.macosArm64 || abi == Abi.linuxArm64) return 'aarch64';
  return 'x64';
}
