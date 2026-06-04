import 'dart:ffi';

String currentSherpaOnnxRuntimeArch() {
  final abi = Abi.current();
  return switch (abi) {
    Abi.macosArm64 || Abi.linuxArm64 => 'aarch64',
    _ => 'x64',
  };
}
