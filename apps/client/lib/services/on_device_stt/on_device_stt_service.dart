import 'dart:typed_data';

/// 本机语音转写结果
class OnDeviceSttResult {
  const OnDeviceSttResult({
    required this.text,
    this.language,
    this.emotion,
    this.event,
  });

  final String text;
  final String? language;
  final String? emotion;
  final String? event;
}

/// 本机 STT 抽象基类
abstract class OnDeviceSttService {
  /// 初始化识别器（加载模型）
  Future<void> initialize();

  /// 转写 16kHz 单声道 PCM 音频数据
  /// [samples] Float32List，值域 [-1.0, 1.0]
  /// [sampleRate] 采样率，通常 16000
  Future<OnDeviceSttResult> transcribe(Float32List samples, int sampleRate);

  /// 释放资源
  Future<void> dispose();

  /// 引擎是否已初始化
  bool get isInitialized;
}

/// Web 桩：任何操作都不支持的占位
class OnDeviceSttStub implements OnDeviceSttService {
  @override
  bool isInitialized = false;

  @override
  Future<void> initialize() async {
    throw UnsupportedError('On-device STT is not supported on web');
  }

  @override
  Future<OnDeviceSttResult> transcribe(Float32List samples, int sampleRate) async {
    throw UnsupportedError('On-device STT is not supported on web');
  }

  @override
  Future<void> dispose() async {}
}