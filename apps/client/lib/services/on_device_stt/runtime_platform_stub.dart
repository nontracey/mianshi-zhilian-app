String currentSherpaOnnxRuntimeArch() => 'x64';

Future<AndroidRuntimeInfo?> currentAndroidRuntimeInfo() async => null;

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
