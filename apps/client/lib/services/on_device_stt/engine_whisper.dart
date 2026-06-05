import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'model_downloader.dart';
import 'on_device_stt_service.dart';

/// Whisper 引擎实现（基于 sherpa_onnx OfflineRecognizer）
///
/// 特点：需要 encoder + decoder 两个 onnx 文件，支持 tiny/base/small/medium 四种尺寸。
/// 非流式，需要完整音频后统一转写。
class WhisperOnnxEngine implements OnDeviceSttService {
  WhisperOnnxEngine({required this.modelDir, this.modelSize = 'base'});

  final String modelDir;
  final String modelSize;
  OfflineRecognizer? _recognizer;

  @override
  bool isInitialized = false;

  @override
  Future<void> initialize() async {
    await ModelDownloader.initSherpaOnnxBindings();
    _recognizer = OfflineRecognizer(_whisperOnnxConfig(modelDir));
    isInitialized = true;
  }

  @override
  Future<OnDeviceSttResult> transcribe(
    Float32List samples,
    int sampleRate,
  ) async {
    final r = _recognizer;
    if (r == null) {
      throw StateError(
        'WhisperOnnxEngine not initialized. Call initialize() first.',
      );
    }
    final stream = r.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      r.decode(stream);
      final result = r.getResult(stream);
      return OnDeviceSttResult(
        text: result.text,
        language: null,
        emotion: null,
        event: null,
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

OfflineRecognizerConfig _whisperOnnxConfig(String modelDir) {
  return OfflineRecognizerConfig(
    feat: const FeatureConfig(sampleRate: 16000, featureDim: 80),
    model: OfflineModelConfig(
      whisper: OfflineWhisperModelConfig(
        encoder: '$modelDir/encoder.int8.onnx',
        decoder: '$modelDir/decoder.int8.onnx',
        language: 'zh',
        task: 'transcribe',
      ),
      tokens: '$modelDir/tokens.txt',
      modelType: 'whisper',
      numThreads: 1,
      provider: 'cpu',
    ),
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
  );
}
