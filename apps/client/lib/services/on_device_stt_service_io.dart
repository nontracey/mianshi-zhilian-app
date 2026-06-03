import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_kit/whisper_kit.dart';

/// 本机 Whisper 语音转写服务
///
/// 基于 whisper_kit (whisper.cpp 的 Flutter 封装)，完全离线运行，无需 API Key。
/// 采用分块录音+逐块转写策略，实现"边说边转"的近实时体验。
///
/// 使用方式：
/// ```dart
/// final svc = OnDeviceSttService();
/// await svc.initModel();  // 首次需下载模型 (~75MB)
/// await svc.startStreaming(onResult: (text) { ... });
/// await svc.stopStreaming();
/// ```
class OnDeviceSttService {
  Whisper? _whisper;
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRunning = false;
  bool _modelReady = false;
  bool _modelDownloading = false;
  String _modelStatus = '';

  /// 当前积累的全部转写结果
  final List<String> _allResults = [];

  /// 模型是否已就绪
  bool get isModelReady => _modelReady;

  /// 是否正在下载模型
  bool get isModelDownloading => _modelDownloading;

  /// 模型状态描述（英文，UI 层通过 l10n 翻译展示）
  String get modelStatus {
    if (_modelReady) return 'ready';
    if (_modelDownloading) return _modelStatus;
    return 'not_downloaded';
  }

  /// 删除已下载的模型文件，释放 ~75MB 存储空间
  Future<void> deleteModel() async {
    _modelReady = false;
    try {
      // 路径逻辑与 whisper_kit 内部 _getModelDir() 保持一致
      final dir = Platform.isAndroid
          ? await getApplicationSupportDirectory()
          : await getLibraryDirectory();
      final modelPath = '${dir.path}/ggml-tiny.bin';
      final file = File(modelPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('OnDeviceStt: delete model failed: $e');
    }
  }

  /// 是否正在录音+转写中
  bool get isRunning => _isRunning;

  /// 录音采样率（16kHz — whisper.cpp 要求）
  static const int sampleRate = 16000;

  /// 初始化 Whisper 模型（tiny 版 ~75MB）
  /// 首次调用会下载模型文件，后续直接加载已缓存的文件。
  ///
  /// [onProgress] 模型下载进度回调 (received, total)
  Future<void> initModel({
    void Function(int received, int total)? onProgress,
  }) async {
    if (_modelReady) return;

    _modelDownloading = true;
    _modelStatus = 'downloading';

    _whisper = Whisper(
      model: WhisperModel.tiny,
      downloadHost:
          'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main',
      onDownloadProgress: (received, total) {
        onProgress?.call(received, total);
        if (total > 0) {
          final pct = (received / total * 100).toStringAsFixed(0);
          _modelStatus = 'downloading:$pct';
        }
      },
    );

    // 触发模型初始化（调用 getVersion 会内部触发模型下载/加载）
    await _whisper!.getVersion();

    _modelReady = true;
    _modelDownloading = false;
    _modelStatus = 'ready';
  }

  /// 开始边说边转
  ///
  /// 点击开始后自动循环：录音 → 转写 → 录音 → 转写 ...
  /// 每次录音 3-4 秒作为一个分块，转写完成后通过 [onResult] 回调累加结果。
  ///
  /// [onResult] 每次分块转写完成后的累加文本
  /// [onStatus] 状态变化回调 (如 "录音中" / "转写中")
  Future<void> startStreaming({
    required void Function(String accumulatedText) onResult,
    void Function(String status)? onStatus,
  }) async {
    if (!_modelReady) {
      throw StateError('Model not ready, call initModel() first');
    }
    if (_isRunning) return;

    _isRunning = true;
    _allResults.clear();

    while (_isRunning) {
      // 1. 录音一个分块 (3-4 秒)
      onStatus?.call('recording');
      final chunkPath = await _recordChunk();
      if (chunkPath == null || !_isRunning) break;

      // 2. 转写分块
      onStatus?.call('transcribing');
      try {
        final text = await _transcribeChunk(chunkPath);
        if (text.isNotEmpty) {
          _allResults.add(text);
          onResult(_allResults.join());
        }
      } catch (e) {
        debugPrint('OnDeviceStt: chunk transcribe failed: $e');
      }

      // 3. 清理临时文件
      try {
        await File(chunkPath).delete();
      } catch (_) {}
    }

    _isRunning = false;
    onStatus?.call('stopped');
  }

  /// 停止边说边转
  Future<void> stopStreaming() async {
    _isRunning = false;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  /// 录制一个音频分块（3 秒），返回临时文件路径
  Future<String?> _recordChunk() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final chunkPath =
          '${tempDir.path}/whisper_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
        path: chunkPath,
      );

      // 录音 3 秒
      await Future.delayed(const Duration(seconds: 3));

      if (!_isRunning) {
        await _recorder.stop();
        return null;
      }

      final path = await _recorder.stop();
      return (path != null && path.isNotEmpty) ? path : null;
    } catch (e) {
      debugPrint('OnDeviceStt: record chunk failed: $e');
      return null;
    }
  }

  /// 转写单个音频分块
  Future<String> _transcribeChunk(String filePath) async {
    if (_whisper == null) {
      throw StateError('Whisper not initialized');
    }

    final file = File(filePath);
    if (!await file.exists()) return '';

    final response = await _whisper!.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: filePath,
        language: 'zh',
        threads: 4,
        isNoTimestamps: true, // 不需要时间戳，只需文本
      ),
    );

    return response.text.trim();
  }

  /// 释放资源
  void dispose() {
    _isRunning = false;
    _recorder.dispose();
    // whisper_kit 实例在 Dart GC 时自动释放 native 资源
  }
}
