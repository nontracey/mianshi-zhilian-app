import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'on_device_stt_service.dart';

/// SenseVoice 引擎实现（基于 sherpa_onnx OfflineRecognizer）
///
/// 特点：单一 .onnx 模型文件，支持中/英/日/韩/粤，返回情感和事件标签。
/// 非流式，需要完整音频后统一转写。
class SenseVoiceEngine implements OnDeviceSttService {
  SenseVoiceEngine({required this.modelDir, this.language = ''});

  final String modelDir;
  final String language;
  OfflineRecognizer? _recognizer;

  @override
  bool isInitialized = false;

  @override
  Future<void> initialize() async {
    initBindings();
    _recognizer = OfflineRecognizer(_senseVoiceConfig(modelDir, language));
    isInitialized = true;
  }

  @override
  Future<OnDeviceSttResult> transcribe(Float32List samples, int sampleRate) async {
    final r = _recognizer;
    if (r == null) {
      throw StateError('SenseVoiceEngine not initialized. Call initialize() first.');
    }
    final stream = r.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      r.decode(stream);
      final result = r.getResult(stream);
      return OnDeviceSttResult(
        text: result.text,
        language: result.lang.isNotEmpty ? result.lang : null,
        emotion: result.emotion.isNotEmpty ? result.emotion : null,
        event: result.event.isNotEmpty ? result.event : null,
      );
    } finally {
      stream.free();
    }
  }

  @override
  Future<void> dispose() async {
    _recognizer?.free();
    _recognizer = null;
    isInitialized = false;
  }
}

OfflineRecognizerConfig _senseVoiceConfig(String modelDir, String language) {
  return OfflineRecognizerConfig(
    feat: const FeatureConfig(sampleRate: 16000, featureDim: 80),
    model: OfflineModelConfig(
      senseVoice: OfflineSenseVoiceModelConfig(
        model: '$modelDir/model.int8.onnx',
        language: language,
      ),
      tokens: '$modelDir/tokens.txt',
      modelType: 'sense_voice',
      numThreads: 2,
      provider: 'cpu',
    ),
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
  );
}