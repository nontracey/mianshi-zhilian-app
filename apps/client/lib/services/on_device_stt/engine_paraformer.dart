import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'model_downloader_io.dart';
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
    await ModelDownloader.initSherpaOnnxBindings();

    // 优先使用离线模式（sherpa-onnx-paraformer-zh-small 仅支持离线，
    // 存档不含 encoder.int8.onnx/decoder.int8.onnx）。
    // 若检测到流式模型文件，再尝试升级为在线模式。
    _offlineRecognizer = OfflineRecognizer(_paraformerOfflineConfig(modelDir));
    _useOnline = false;

    // 尝试热升级为在线模式（需要 encoder/decoder 文件）
    try {
      final encoderFile = File('$modelDir/encoder.int8.onnx');
      final decoderFile = File('$modelDir/decoder.int8.onnx');
      if (await encoderFile.exists() && await decoderFile.exists()) {
        _onlineRecognizer = OnlineRecognizer(_paraformerOnlineConfig(modelDir));
        _onlineStream = _onlineRecognizer!.createStream();

        // 在线模式就绪，释放离线资源
        _offlineRecognizer?.free();
        _offlineRecognizer = null;
        _useOnline = true;
      }
    } catch (_) {
      // 升级失败不阻塞——保留离线模式可用
    }

    isInitialized = true;
  }

  @override
  Future<OnDeviceSttResult> transcribe(
    Float32List samples,
    int sampleRate,
  ) async {
    if (!isInitialized) {
      throw StateError(
        'ParaformerEngine not initialized. Call initialize() first.',
      );
    }
    return _useOnline
        ? _transcribeOnline(samples, sampleRate)
        : _transcribeOffline(samples, sampleRate);
  }

  Future<OnDeviceSttResult> _transcribeOnline(
    Float32List samples,
    int sampleRate,
  ) async {
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

  Future<OnDeviceSttResult> _transcribeOffline(
    Float32List samples,
    int sampleRate,
  ) async {
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
      paraformer: OfflineParaformerModelConfig(
        model: '$modelDir/model.int8.onnx',
      ),
      tokens: '$modelDir/tokens.txt',
      modelType: 'paraformer',
      numThreads: 2,
      provider: 'cpu',
    ),
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
  );
}
