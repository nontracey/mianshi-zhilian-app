import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'on_device_stt_service.dart';

/// Paraformer 流式引擎实现（基于 sherpa_onnx OnlineRecognizer）
///
/// 特点：支持真正的流式转写（边录边识别），适合长音频实时转写场景。
/// 本实现自动做端点检测，每次返回增量转写文本。
class ParaformerEngine implements OnDeviceSttService {
  ParaformerEngine({required this.modelDir});

  final String modelDir;

  /// 是否使用在线流式模式
  bool _useOnline = false;
  OnlineRecognizer? _onlineRecognizer;
  OfflineRecognizer? _offlineRecognizer;
  OnlineStream? _onlineStream;
  StringBuffer _accumulated = StringBuffer();

  @override
  bool isInitialized = false;

  @override
  Future<void> initialize() async {
    initBindings();
    try {
      _onlineRecognizer = OnlineRecognizer(_paraformerOnlineConfig(modelDir));
      _onlineStream = _onlineRecognizer!.createStream();
      _useOnline = true;
    } catch (_) {
      _offlineRecognizer = OfflineRecognizer(_paraformerOfflineConfig(modelDir));
      _useOnline = false;
    }
    isInitialized = true;
  }

  @override
  Future<OnDeviceSttResult> transcribe(Float32List samples, int sampleRate) async {
    if (!isInitialized) {
      throw StateError('ParaformerEngine not initialized. Call initialize() first.');
    }
    return _useOnline ? _transcribeOnline(samples, sampleRate) : _transcribeOffline(samples, sampleRate);
  }

  Future<OnDeviceSttResult> _transcribeOnline(Float32List samples, int sampleRate) async {
    final r = _onlineRecognizer!;
    final s = _onlineStream!;

    s.acceptWaveform(samples: samples, sampleRate: sampleRate);

    while (r.isReady(s)) {
      r.decode(s);
    }

    final result = r.getResult(s);
    final text = result.text;
    final accumulated = _accumulated.toString();
    final delta = (accumulated.isNotEmpty && text.startsWith(accumulated))
        ? text.substring(accumulated.length)
        : text;

    _accumulated.write(delta);

    if (r.isEndpoint(s)) {
      r.reset(s);
      _accumulated = StringBuffer();
    }

    return OnDeviceSttResult(text: delta);
  }

  Future<OnDeviceSttResult> _transcribeOffline(Float32List samples, int sampleRate) async {
    final r = _offlineRecognizer!;
    final stream = r.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      r.decode(stream);
      final result = r.getResult(stream);
      return OnDeviceSttResult(text: result.text);
    } finally {
      stream.free();
    }
  }

  /// 重置流式状态（新会话时调用）
  void resetStream() {
    if (_onlineStream != null) {
      _onlineRecognizer!.reset(_onlineStream!);
    }
    _accumulated = StringBuffer();
  }

  @override
  Future<void> dispose() async {
    _onlineStream?.free();
    _onlineRecognizer?.free();
    _offlineRecognizer?.free();
    _onlineStream = null;
    _onlineRecognizer = null;
    _offlineRecognizer = null;
    isInitialized = false;
  }
}

OnlineRecognizerConfig _paraformerOnlineConfig(String modelDir) {
  return OnlineRecognizerConfig(
    feat: const FeatureConfig(sampleRate: 16000, featureDim: 80),
    model: OnlineModelConfig(
      paraformer: OnlineParaformerModelConfig(
        encoder: '$modelDir/encoder.int8.onnx',
        decoder: '$modelDir/decoder.int8.onnx',
      ),
      tokens: '$modelDir/tokens.txt',
      modelType: 'paraformer',
      numThreads: 2,
    ),
    decodingMethod: 'greedy_search',
    enableEndpoint: true,
    rule1MinTrailingSilence: 2.4,
    rule2MinTrailingSilence: 1.2,
    rule3MinUtteranceLength: 20,
  );
}

OfflineRecognizerConfig _paraformerOfflineConfig(String modelDir) {
  return OfflineRecognizerConfig(
    feat: const FeatureConfig(sampleRate: 16000, featureDim: 80),
    model: OfflineModelConfig(
      paraformer: OfflineParaformerModelConfig(model: '$modelDir/model.int8.onnx'),
      tokens: '$modelDir/tokens.txt',
      modelType: 'paraformer',
      numThreads: 2,
      provider: 'cpu',
    ),
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
  );
}