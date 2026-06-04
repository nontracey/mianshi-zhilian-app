import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_kit/download_model.dart' show downloadModel;
import 'package:whisper_kit/whisper_kit.dart';

/// 本机 Whisper 语音转写服务
///
/// 基于 whisper_kit (whisper.cpp 的 Flutter 封装)，完全离线运行，无需 API Key。
/// 采用静音检测断句 + 逐块转写策略，实现"边说边转"的近实时体验。
///
/// 使用方式：
/// ```dart
/// final svc = OnDeviceSttService(model: WhisperModel.base);
/// await svc.initModel();
/// await svc.startStreaming(onResult: (text) { ... });
/// await svc.stopStreaming();
/// ```
class OnDeviceSttService {
  final WhisperModel _model;
  Whisper? _whisper;
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRunning = false;
  bool _modelReady = false;
  bool _modelDownloading = false;
  String _modelStatus = '';

  /// 当前积累的全部转写结果
  final List<String> _allResults = [];

  /// 上一分块的尾部文本，用于重叠去重比对
  String _lastAccumulatedTail = '';

  /// 模型是否已就绪（内存中已加载）
  bool get isModelReady => _modelReady;

  /// 是否正在下载模型
  bool get isModelDownloading => _modelDownloading;

  /// 模型状态描述（英文，UI 层通过 l10n 翻译展示）
  String get modelStatus {
    if (_modelReady) return 'ready';
    if (_modelDownloading) return _modelStatus;
    return 'not_downloaded';
  }

  /// 当前使用的模型
  WhisperModel get model => _model;

  // ---------- 静音检测参数 ----------

  /// 振幅阈值（dBFS），低于此值视为静音
  /// dBFS 范围：0（最大）到 -∞（静音），典型对话在 -30 ~ -12 dBFS，
  /// 静音环境通常在 -50 dBFS 以下。
  static const double _silenceThresholdDbFs = -40.0;

  /// 连续静音超过此时长即断句
  static const Duration _silenceDuration = Duration(milliseconds: 1500);

  /// 振幅采样间隔
  static const Duration _amplitudeCheckInterval = Duration(milliseconds: 200);

  /// 单分块最大时长（安全防护，防止异常情况下无限录制）
  static const Duration _maxChunkDuration = Duration(seconds: 30);

  /// 去重比对窗口（字符数），新分块头部与之比对去除重复
  static const int _overlapWindowChars = 8;

  /// 最小有效分块时长（低于此值不转写）
  static const Duration _minChunkDuration = Duration(seconds: 1);

  OnDeviceSttService({WhisperModel model = WhisperModel.base})
      : _model = model;

  /// 检查模型文件是否已存在于磁盘（不加载到内存）
  Future<bool> isModelFilePresent() async {
    try {
      final dir = await _getModelDir();
      final modelFile = File(_model.getPath(dir.path));
      return await modelFile.exists();
    } catch (_) {
      return false;
    }
  }

  /// 删除已下载的模型文件，释放存储空间
  Future<void> deleteModel() async {
    _modelReady = false;
    try {
      final dir = await _getModelDir();
      final modelFile = File(_model.getPath(dir.path));
      if (await modelFile.exists()) {
        await modelFile.delete();
      }
    } catch (e) {
      debugPrint('OnDeviceStt: delete model failed: $e');
    }
  }

  /// 获取模型存放目录，路径逻辑与 whisper_kit 内部 _getModelDir() 保持一致
  Future<Directory> _getModelDir() async {
    if (Platform.isAndroid) {
      return await getApplicationSupportDirectory();
    }
    return await getLibraryDirectory();
  }

  /// 录音采样率（16kHz — whisper.cpp 要求）
  static const int sampleRate = 16000;

  /// 初始化 Whisper 模型
  ///
  /// 首次调用会下载模型文件，后续直接加载已缓存的文件。
  /// 模型类型由构造函数的 [model] 参数决定（默认 [WhisperModel.base]）。
  ///
  /// [onProgress] 模型下载进度回调 (received, total)
  Future<void> initModel({
    void Function(int received, int total)? onProgress,
  }) async {
    if (_modelReady) return;
    if (_modelDownloading) return;

    _modelDownloading = true;
    _modelStatus = 'downloading';

    try {
      final dir = await _getModelDir();
      final modelPath = _model.getPath(dir.path);
      final modelFile = File(modelPath);
      if (!await modelFile.exists()) {
        await downloadModel(
          model: _model,
          destinationPath: dir.path,
          downloadHost:
              'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main',
          onDownloadProgress: onProgress == null
              ? null
              : (received, total) {
                  onProgress(received, total);
                  if (total > 0) {
                    final pct = (received / total * 100).toStringAsFixed(0);
                    _modelStatus = 'downloading:$pct';
                  }
                },
        );
      }

      _whisper = Whisper(
        model: _model,
        downloadHost:
            'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main',
      );

      await _whisper!.getVersion();
      _modelReady = true;
      _modelStatus = 'ready';
    } catch (e) {
      _modelReady = false;
      _modelStatus = 'not_downloaded';
      debugPrint(
        'OnDeviceStt: initModel failed (platform may not support native whisper): $e',
      );
    } finally {
      _modelDownloading = false;
    }
  }

  /// 开始边说边转
  ///
  /// 自动循环：录音（静音检测断句）→ 转写 → 去重合并 → 录音 ...
  /// 每次录音到静音或超时时停止，转写后与历史结果去重合并。
  ///
  /// [onResult] 每次分块转写完成后的累加文本
  /// [onStatus] 状态变化回调 (如 "录音中" / "转写中")
  Future<void> startStreaming({
    required void Function(String accumulatedText) onResult,
    void Function(String status)? onStatus,
    void Function()? onEmptyResult,
    void Function(Object error)? onError,
  }) async {
    if (!_modelReady) {
      throw StateError('Model not ready, call initModel() first');
    }
    if (_isRunning) return;

    _isRunning = true;
    _allResults.clear();
    _lastAccumulatedTail = '';

    while (_isRunning) {
      // 1. 录音一个分块（静音检测断句）
      onStatus?.call('recording');
      final chunkPath = await _recordChunkWithSilenceDetection();
      if (chunkPath == null || !_isRunning) break;

      // 检查分块时长是否太短
      final chunkFile = File(chunkPath);
      if (await chunkFile.exists()) {
        final fileSize = await chunkFile.length();
        // 约 1 秒 16kHz mono wav = 16000*2 = 32000 bytes + header
        // 文件太小说明录音片段太短，跳过
        if (fileSize < _minChunkDuration.inMilliseconds * 2 * 16 ~/ 1000) {
          try {
            await chunkFile.delete();
          } catch (_) {}
          continue;
        }
      }

      // 2. 转写分块
      onStatus?.call('transcribing');
      try {
        var text = await _transcribeChunk(chunkPath);
        text = text.trim();

        if (text.isNotEmpty) {
          // 3. 重叠去重：去除与上一分块尾部重复的前缀
          text = _deduplicateText(text);

          if (text.isNotEmpty) {
            _allResults.add(text);
            final accumulated = _allResults.join();

            // 保存尾部用于下次去重
            _lastAccumulatedTail = accumulated.length > _overlapWindowChars * 2
                ? accumulated.substring(accumulated.length -
                    _overlapWindowChars * 2)
                : accumulated;

            onResult(accumulated);
          } else {
            onEmptyResult?.call();
          }
        } else {
          onEmptyResult?.call();
        }
      } catch (e) {
        debugPrint('OnDeviceStt: chunk transcribe failed: $e');
        onError?.call(e);
        rethrow;
      } finally {
        try {
          await File(chunkPath).delete();
        } catch (_) {}
      }
    }

    _isRunning = false;
    onStatus?.call('stopped');
  }

  /// 录音一个分块，通过静音检测自动断句
  ///
  /// 流程：
  /// 1. 开始录制到临时文件
  /// 2. 每 200ms 检查振幅，连续低于阈值 1.5s 视为静音，结束分块
  /// 3. 最长录制 30s（安全防护）
  /// 4. 返回临时文件路径，或 null（停止/出错）
  Future<String?> _recordChunkWithSilenceDetection() async {
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

      int silenceFrames = 0;
      // 连续静音帧数阈值 = 1.5s / 200ms = 7.5 -> 7 帧即可
      final int silenceFramesNeeded =
          _silenceDuration.inMilliseconds ~/ _amplitudeCheckInterval.inMilliseconds;
      final stopwatch = Stopwatch()..start();

      while (_isRunning && stopwatch.elapsed < _maxChunkDuration) {
        await Future.delayed(_amplitudeCheckInterval);

        try {
          final amplitude = await _recorder.getAmplitude();
          if (amplitude.current < _silenceThresholdDbFs) {
            silenceFrames++;
          } else {
            silenceFrames = 0;
          }
        } catch (_) {
          // getAmplitude 可能在某些平台不兼容，回退到固定时长
          // 此时用 stopwatch 检查 _maxChunkDuration，不卡住流程
          break;
        }

        if (silenceFrames >= silenceFramesNeeded) {
          // 确认静音后略微多等一小段，让音频自然结束
          await Future.delayed(const Duration(milliseconds: 200));
          break;
        }
      }

      if (!_isRunning) {
        try {
          await _recorder.stop();
        } catch (_) {}
        return null;
      }

      final path = await _recorder.stop();
      return (path != null && path.isNotEmpty) ? path : null;
    } catch (e) {
      debugPrint('OnDeviceStt: record chunk failed: $e');
      rethrow;
    }
  }

  /// 文本级重叠去重
  ///
  /// 将新转写文本的开头与累积文本的尾部进行字符串比对，
  /// 去掉重复部分，避免因分块边界导致字词重复。
  String _deduplicateText(String newText) {
    if (_allResults.isEmpty) return newText;
    final tail = _lastAccumulatedTail;
    if (tail.isEmpty || newText.length < 2) return newText;

    // 从长到短尝试匹配，取最长匹配
    int matchLen = 0;
    final int maxMatch =
        tail.length < newText.length ? tail.length : newText.length;
    for (int i = maxMatch; i >= 1; i--) {
      if (tail.substring(tail.length - i) == newText.substring(0, i)) {
        matchLen = i;
        break;
      }
    }

    if (matchLen > 0) {
      return newText.substring(matchLen);
    }
    return newText;
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
        isNoTimestamps: true,
      ),
    );

    return response.text.trim();
  }

  /// 停止边说边转
  Future<void> stopStreaming() async {
    _isRunning = false;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  /// 释放资源
  void dispose() {
    _isRunning = false;
    _recorder.dispose();
    // whisper_kit 实例在 Dart GC 时自动释放 native 资源
  }
}