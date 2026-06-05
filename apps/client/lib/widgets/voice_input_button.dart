import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/app_log_service.dart';
import 'package:mianshi_zhilian/services/app_permission_service.dart';
import 'package:mianshi_zhilian/services/on_device_stt/model_downloader.dart';
import 'package:mianshi_zhilian/services/on_device_stt/on_device_stt_factory.dart';
import 'package:mianshi_zhilian/services/on_device_stt/on_device_stt_service.dart';
import 'package:mianshi_zhilian/utils/platform_file_reader.dart';

enum VoiceInputState {
  idle,
  preparing,
  ready,
  recording,
  transcribing,
  stopping,
  error,
}

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.onResult,
    this.onListeningChanged,
    this.onStateChanged,
    this.onError,
    this.aiConfigId,
    this.sttMode,
  });

  final ValueChanged<String> onResult;
  final ValueChanged<bool>? onListeningChanged;
  final ValueChanged<VoiceInputState>? onStateChanged;
  final ValueChanged<String>? onError;
  final String? aiConfigId;

  // Kept for older call sites; the component now resolves settings itself.
  final String? sttMode;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();

  VoiceInputState _state = VoiceInputState.idle;
  VoiceInputState _lastNotifiedState = VoiceInputState.idle;
  bool _systemAvailable = false;
  bool _running = false;
  bool _producerRunning = false;
  bool _consumerRunning = false;
  bool _finishAfterQueue = false;
  int _sessionId = 0;
  String _lastSystemText = '';
  String? _statusMessageKey;
  OnDeviceSttService? _sherpaOnnxService;
  String? _sherpaOnnxServiceKey;
  Timer? _sherpaIdleDisposeTimer;
  _VoiceProviderKind? _activeProviderKind;
  final Queue<_VoiceChunkJob> _chunkQueue = Queue<_VoiceChunkJob>();

  /// 当前活跃的 AI 配置名（用于转写时显示模型信息）
  String? _activeConfigLabel;
  bool get _isActive =>
      _state == VoiceInputState.preparing ||
      _state == VoiceInputState.ready ||
      _state == VoiceInputState.recording ||
      _state == VoiceInputState.transcribing ||
      _state == VoiceInputState.stopping;

  void _setStateKind(VoiceInputState state) {
    if (_state == state) return;
    final wasActive = _isActive;
    if (mounted) setState(() => _state = state);
    final isActive = _isActive;
    if (wasActive != isActive) widget.onListeningChanged?.call(isActive);
    if (_lastNotifiedState != state) {
      _lastNotifiedState = state;
      widget.onStateChanged?.call(state);
    }
  }

  Future<void> _toggleListening() async {
    if (_isActive) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    final aiProvider = context.read<AiProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final provider = _resolveProvider(settings, aiProvider);
    final sessionId = ++_sessionId;

    _running = true;
    _finishAfterQueue = false;
    _producerRunning = false;
    _consumerRunning = false;
    _activeProviderKind = provider.kind;
    _discardQueuedChunks();
    _lastSystemText = '';
    _activeConfigLabel = null;
    _setStatusMessage('voice_preparing');
    _setStateKind(VoiceInputState.preparing);

    switch (provider.kind) {
      case _VoiceProviderKind.ai:
        await _startAiStreaming(sessionId, aiProvider, provider.config!);
        break;
      case _VoiceProviderKind.system:
        await _startSystemListening(sessionId);
        break;
      case _VoiceProviderKind.sherpaOnnx:
        final engine = provider.engine;
        final whisperModel = provider.whisperModel;
        if (engine == null || whisperModel == null) break;
        await _startSherpaOnnxListening(
          sessionId: sessionId,
          engine: engine,
          whisperModel: whisperModel,
        );
        break;
      case _VoiceProviderKind.none:
        _showError('voice_provider_unavailable');
        break;
    }
  }

  _ResolvedVoiceProvider _resolveProvider(
    dynamic settings,
    AiProvider aiProvider,
  ) {
    final mode = widget.sttMode ?? settings.sttMode;
    final selected = aiProvider.configById(widget.aiConfigId);
    final fixed = settings.sttAiConfigId == null
        ? null
        : aiProvider.configById(settings.sttAiConfigId);
    final defaultConfig = aiProvider.defaultConfig;

    if (mode == 'sherpa_onnx') {
      return _ResolvedVoiceProvider.sherpaOnnx(
        engine: settings.onDeviceEngine,
        whisperModel: settings.whisperModel,
      );
    }

    AiConfig? audioConfig;
    if (mode == 'fixed_ai_config') {
      audioConfig = fixed?.canTranscribe == true ? fixed : null;
    } else if (mode == 'follow_current_ai') {
      audioConfig = selected?.canTranscribe == true ? selected : null;
    } else if (mode == 'auto') {
      audioConfig = selected?.canTranscribe == true
          ? selected
          : (fixed?.canTranscribe == true
                ? fixed
                : (defaultConfig?.canTranscribe == true
                      ? defaultConfig
                      : null));
    }

    if (audioConfig != null) {
      return _ResolvedVoiceProvider.ai(audioConfig);
    }

    // 无可用 AI 语音配置时，auto 模式尝试本机 sherpa-onnx 兜底
    if (mode == 'auto') {
      final onDeviceEngine = settings.onDeviceEngine;
      if (onDeviceEngine != null && onDeviceEngine.isNotEmpty) {
        return _ResolvedVoiceProvider.sherpaOnnx(
          engine: onDeviceEngine,
          whisperModel: settings.whisperModel,
        );
      }
    }

    if (mode == 'system' || mode == 'auto') {
      return const _ResolvedVoiceProvider.system();
    }

    return const _ResolvedVoiceProvider.none();
  }

  Future<void> _startSystemListening(int sessionId) async {
    if (!await AppPermissionService.ensureSpeechRecognition(context)) {
      _resetStartFailure();
      return;
    }
    if (!_isCurrentRecordingSession(sessionId)) return;
    if (!_systemAvailable) {
      _systemAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _running = false;
            _setStateKind(VoiceInputState.idle);
          }
        },
        onError: (error) {
          _running = false;
          _showError('system_speech_unsupported');
        },
      );
    }
    if (!_isCurrentRecordingSession(sessionId)) return;
    if (!_systemAvailable) {
      _resetStartFailure();
      _showError('system_speech_unsupported');
      return;
    }

    _setStateKind(VoiceInputState.ready);
    _setStatusMessage('voice_ready');
    bool hadSystemResult = false;
    await _speech.listen(
      onResult: (result) {
        if (!hadSystemResult && mounted) {
          hadSystemResult = true;
          _setStateKind(VoiceInputState.recording);
          _setStatusMessage(null);
        }
        final words = result.recognizedWords;
        final delta = _deltaFromCumulative(words, _lastSystemText);
        _lastSystemText = words;
        _emitText(delta);
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        localeId: 'zh_CN',
      ),
    );
  }

  Future<void> _startAiStreaming(
    int sessionId,
    AiProvider aiProvider,
    AiConfig config,
  ) async {
    if (kIsWeb) {
      _resetStartFailure();
      _showError('voice_web_unsupported');
      return;
    }
    if (!await AppPermissionService.ensureMicrophone(context)) {
      _resetStartFailure();
      return;
    }
    if (!_isCurrentRecordingSession(sessionId)) return;
    _activeConfigLabel = '${config.name} · ${config.model}';
    _setStateKind(VoiceInputState.ready);
    _setStatusMessage('voice_ready');
    _producerRunning = true;
    unawaited(_runAiChunkLoop(sessionId, aiProvider, config));
  }

  /// 生产者循环：不间断录制音频块，每块转写异步派发不阻塞收音。
  Future<void> _runAiChunkLoop(
    int sessionId,
    AiProvider aiProvider,
    AiConfig config,
  ) async {
    try {
      while (_isCurrentRecordingSession(sessionId)) {
        final chunkPath = await _recordVadChunk(
          onSpeechStart: () {
            if (mounted) {
              _setStateKind(VoiceInputState.recording);
              _setStatusMessage(null);
            }
          },
        );
        if (!_isCurrentSession(sessionId)) break;
        if (chunkPath == null) {
          if (_running) continue;
          break;
        }
        _enqueueTranscription(
          _VoiceChunkJob.ai(
            sessionId: sessionId,
            chunkPath: chunkPath,
            aiProvider: aiProvider,
            config: config,
          ),
        );
      }
    } catch (e) {
      if (_isCurrentSession(sessionId)) _showError(_messageKeyForError(e));
    } finally {
      if (_isCurrentSession(sessionId)) {
        _producerRunning = false;
        _finishSessionIfReady();
      }
    }
  }

  /// 读取音频块 → 调用 AI 转写 → 返回文本。
  Future<String> _transcribeAiChunk(
    AiProvider aiProvider,
    AiConfig config,
    String chunkPath,
  ) async {
    final bytes = await readBytesFromPath(chunkPath);
    try {
      await deleteFileAtPath(chunkPath);
    } catch (_) {}
    return aiProvider.transcribeAudio(config: config, audioBytes: bytes);
  }

  /// 使用 VAD 语音活动检测录制音频块，返回临时文件路径。
  /// 当检测到持续静音或达到最大时长时自动停止。
  /// 返回 null 表示无有效语音输入或录制失败。
  Future<String?> _recordVadChunk({VoidCallback? onSpeechStart}) async {
    String? chunkPath;
    try {
      if (!_running) return null;

      final tempDir = await getTemporaryDirectory();
      chunkPath =
          '${tempDir.path}/voice_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: chunkPath,
      );

      // VAD: record uses dB-like values on some platforms and normalized
      // linear values on others, so speech detection has to handle both.
      bool speechStarted = false;
      int silentChecks = 0;
      int speechChecks = 0;
      int totalChecks = 0;
      const pollInterval = Duration(milliseconds: 80);
      const warmupChecks = 4;
      const minSpeechChecks = 3;
      const maxSilentChecks = 12;
      const maxTotalChecks = 150;
      const noSpeechChecks = 100;

      while (_running) {
        await Future.delayed(pollInterval);
        final amplitude = await _recorder.getAmplitude();
        totalChecks++;
        final speechLike =
            totalChecks > warmupChecks && _isSpeechAmplitude(amplitude.current);

        if (speechLike) {
          speechChecks++;
          silentChecks = 0;
          if (!speechStarted && speechChecks >= minSpeechChecks) {
            speechStarted = true;
            onSpeechStart?.call();
          }
        } else if (speechChecks > 0) {
          silentChecks++;
        }

        if (speechChecks >= minSpeechChecks &&
            silentChecks >= maxSilentChecks) {
          break;
        }
        if (speechChecks == 0 && totalChecks >= noSpeechChecks) break;
        if (totalChecks >= maxTotalChecks) break;
      }

      final path = await _recorder.stop();
      final hasEnoughSpeech = speechChecks >= minSpeechChecks;
      if (path == null || path.isEmpty || !hasEnoughSpeech) {
        if (path != null && path.isNotEmpty) {
          unawaited(deleteFileAtPath(path));
        }
        return null;
      }
      return path;
    } catch (e) {
      unawaited(
        AppLog.warning(
          'Voice VAD chunk recording failed',
          source: 'voice',
          error: e,
        ),
      );
      if (_running) rethrow;
      if (chunkPath != null) {
        try {
          await deleteFileAtPath(chunkPath);
        } catch (_) {}
      }
      return null;
    }
  }

  bool _isSpeechAmplitude(double value) {
    if (value.isNaN || value.isInfinite) return false;
    if (value <= 0) return value > -45; // dBFS-style values.
    if (value <= 1) return value >= 0.018; // Normalized linear values.
    return value >= 8; // Defensive fallback for positive dB-style values.
  }

  Future<void> _startSherpaOnnxListening({
    required int sessionId,
    required String engine,
    required String whisperModel,
  }) async {
    if (kIsWeb) {
      _resetStartFailure();
      _showError('voice_web_unsupported');
      return;
    }
    if (!await AppPermissionService.ensureMicrophone(context)) {
      _resetStartFailure();
      return;
    }
    if (!_isCurrentRecordingSession(sessionId)) return;

    // 确定模型配置并检查是否就绪
    final modelConfig = _sherpaOnnxModelConfig(engine, whisperModel);
    if (modelConfig == null) {
      _showError('on_device_engine_unknown');
      _resetStartFailure();
      return;
    }
    final ready = await ModelDownloader.isOnDeviceReady(modelConfig);
    if (!_isCurrentRecordingSession(sessionId)) return;
    if (!ready) {
      _showError('on_device_model_not_downloaded');
      _resetStartFailure();
      return;
    }

    // 创建并初始化本机 STT 服务
    final modelDir = await ModelDownloader.getModelDir(modelConfig.id);
    if (!_isCurrentRecordingSession(sessionId)) return;
    final serviceKey = '$engine|$whisperModel|${modelDir.path}';
    _sherpaIdleDisposeTimer?.cancel();
    var service = _sherpaOnnxService;
    if (service == null ||
        _sherpaOnnxServiceKey != serviceKey ||
        !service.isInitialized) {
      await _disposeSherpaOnnxService();
      service = createOnDeviceSttService(
        engine: engine,
        modelDir: modelDir.path,
        whisperModelSize: whisperModel,
      );
      _sherpaOnnxService = service;
      _sherpaOnnxServiceKey = serviceKey;
    }
    try {
      if (!service.isInitialized) await service.initialize();
    } catch (e) {
      _showErrorDetail('on_device_stt_init_failed', e);
      await service.dispose();
      if (_sherpaOnnxService == service) {
        _sherpaOnnxService = null;
        _sherpaOnnxServiceKey = null;
      }
      _resetStartFailure();
      return;
    }
    if (!_isCurrentRecordingSession(sessionId)) {
      _finishSessionIfReady();
      return;
    }

    _activeConfigLabel = _sherpaOnnxEngineLabel(engine);
    _setStateKind(VoiceInputState.ready);
    _setStatusMessage('voice_ready');
    _producerRunning = true;
    unawaited(_runSherpaOnnxChunkLoop(sessionId, service));
  }

  /// 生产者循环：不间断录制音频块，每块转写异步派发（本机离线引擎）。
  Future<void> _runSherpaOnnxChunkLoop(
    int sessionId,
    OnDeviceSttService service,
  ) async {
    try {
      while (_isCurrentRecordingSession(sessionId)) {
        final chunkPath = await _recordVadChunk(
          onSpeechStart: () {
            if (mounted) {
              _setStateKind(VoiceInputState.recording);
              _setStatusMessage(null);
            }
          },
        );
        if (!_isCurrentSession(sessionId)) break;
        if (chunkPath == null) {
          if (_running) continue;
          break;
        }
        _enqueueTranscription(
          _VoiceChunkJob.sherpa(
            sessionId: sessionId,
            chunkPath: chunkPath,
            service: service,
          ),
        );
      }
    } catch (e) {
      if (_isCurrentSession(sessionId)) _showError('voice_recognize_failed');
    } finally {
      if (_isCurrentSession(sessionId)) {
        _producerRunning = false;
        _finishSessionIfReady();
      }
    }
  }

  /// 读取音频块 → 调用 sherpa-onnx 转写 → 返回文本。
  Future<String> _transcribeSherpaChunk(
    String chunkPath,
    OnDeviceSttService service,
  ) async {
    final bytes = await readBytesFromPath(chunkPath);
    try {
      await deleteFileAtPath(chunkPath);
    } catch (_) {}

    final samples = _wavBytesToFloat32List(bytes);
    if (samples == null || samples.isEmpty) return '';

    try {
      final result = await service.transcribe(samples, 16000);
      return _cleanTranscriptionText(result.text);
    } catch (e) {
      debugPrint('sherpa_onnx chunk transcribe failed: $e');
      unawaited(
        AppLog.warning(
          'On-device voice chunk transcription failed',
          source: 'voice',
          error: e,
        ),
      );
      return '';
    }
  }

  /// 将 16-bit PCM WAV 字节数据转为 Float32List（值域 [-1.0, 1.0]）
  Float32List? _wavBytesToFloat32List(Uint8List bytes) {
    // WAV 头部至少 44 字节
    if (bytes.length < 44) return null;
    // 跳过 WAV 头部，从第 44 字节开始读取 PCM 数据
    final dataSize = bytes.length - 44;
    if (dataSize < 2) return null;
    final sampleCount = dataSize ~/ 2;
    final result = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      final offset = 44 + i * 2;
      // 小端 16-bit signed
      final sample = (bytes[offset] | (bytes[offset + 1] << 8)).toSigned(16);
      result[i] = sample / 32768.0;
    }
    return result;
  }

  OnDeviceModelConfig? _sherpaOnnxModelConfig(
    String engine,
    String whisperModel,
  ) {
    return KnownModels.forEngine(engine, whisperSize: whisperModel);
  }

  String _sherpaOnnxEngineLabel(String engine) {
    return switch (engine) {
      'sense_voice' => 'SenseVoice',
      'whisper' => 'Whisper',
      'paraformer' => 'Paraformer',
      _ => engine,
    };
  }

  Future<void> _disposeSherpaOnnxService() async {
    _sherpaIdleDisposeTimer?.cancel();
    _sherpaIdleDisposeTimer = null;
    try {
      await _sherpaOnnxService?.dispose();
    } catch (_) {}
    _sherpaOnnxService = null;
    _sherpaOnnxServiceKey = null;
  }

  void _scheduleSherpaIdleDispose() {
    _sherpaIdleDisposeTimer?.cancel();
    _sherpaIdleDisposeTimer = Timer(const Duration(minutes: 2), () {
      unawaited(_disposeSherpaOnnxService());
    });
  }

  bool _isCurrentSession(int sessionId) => _sessionId == sessionId;

  bool _isCurrentRecordingSession(int sessionId) =>
      _isCurrentSession(sessionId) && _running;

  void _enqueueTranscription(_VoiceChunkJob job) {
    if (!_isCurrentSession(job.sessionId)) {
      unawaited(deleteFileAtPath(job.chunkPath));
      return;
    }
    _chunkQueue.add(job);
    if (!_running) {
      _setStateKind(VoiceInputState.transcribing);
      _setStatusMessage('voice_transcribing');
    } else if (_chunkQueue.length > 1) {
      _setStatusMessage('voice_transcribing_background');
    }
    if (!_consumerRunning) unawaited(_consumeTranscriptionQueue());
  }

  Future<void> _consumeTranscriptionQueue() async {
    if (_consumerRunning) return;
    _consumerRunning = true;
    try {
      while (_chunkQueue.isNotEmpty) {
        final job = _chunkQueue.removeFirst();
        if (!_isCurrentSession(job.sessionId)) {
          unawaited(deleteFileAtPath(job.chunkPath));
          continue;
        }
        if (!_running) {
          _setStateKind(VoiceInputState.transcribing);
          _setStatusMessage('voice_transcribing');
        }

        try {
          final text = switch (job.kind) {
            _VoiceChunkKind.ai => await _transcribeAiChunk(
              job.aiProvider!,
              job.config!,
              job.chunkPath,
            ),
            _VoiceChunkKind.sherpa => await _transcribeSherpaChunk(
              job.chunkPath,
              job.service!,
            ),
          };
          if (_isCurrentSession(job.sessionId) &&
              (_running || _finishAfterQueue)) {
            _emitText(_cleanTranscriptionText(text));
          }
        } catch (e) {
          unawaited(
            AppLog.warning(
              'Voice chunk transcription failed',
              source: 'voice',
              error: e,
            ),
          );
          if (_isCurrentSession(job.sessionId) && _running) {
            _showError(_messageKeyForError(e));
          }
        }
      }
    } finally {
      _consumerRunning = false;
      _finishSessionIfReady();
    }
  }

  void _finishSessionIfReady() {
    if (!_finishAfterQueue) return;
    if (_producerRunning || _consumerRunning || _chunkQueue.isNotEmpty) return;
    _finishAfterQueue = false;
    _running = false;
    _setStatusMessage(null);
    if (mounted && _state != VoiceInputState.error) {
      _setStateKind(VoiceInputState.idle);
    }
    if (_activeProviderKind == _VoiceProviderKind.sherpaOnnx) {
      _scheduleSherpaIdleDispose();
    }
  }

  void _discardQueuedChunks() {
    while (_chunkQueue.isNotEmpty) {
      final job = _chunkQueue.removeFirst();
      unawaited(deleteFileAtPath(job.chunkPath));
    }
  }

  Future<void> _stopListening() async {
    if (_state == VoiceInputState.stopping) return;
    final providerKind = _activeProviderKind;
    _running = false;
    _finishAfterQueue = true;
    _setStateKind(VoiceInputState.stopping);
    _setStatusMessage('voice_stopping');
    if (providerKind == _VoiceProviderKind.system) {
      try {
        await _speech.stop();
      } catch (_) {}
      _producerRunning = false;
      _consumerRunning = false;
      _finishAfterQueue = false;
      _setStatusMessage(null);
      if (mounted) _setStateKind(VoiceInputState.idle);
      return;
    }
    _finishSessionIfReady();
  }

  void _emitText(String text) {
    final cleaned = _cleanTranscriptionText(text);
    if (cleaned.isEmpty) return;
    widget.onResult(cleaned);
  }

  String _cleanTranscriptionText(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'<\|[^>]*\|>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final lower = cleaned.toLowerCase();
    const silenceHallucinations = {
      '谢谢观看',
      '感谢观看',
      '字幕由 amara.org 社区提供',
      'thanks for watching',
    };
    return silenceHallucinations.contains(lower) ? '' : cleaned;
  }

  String _deltaFromCumulative(String current, String previous) {
    if (current.isEmpty) return '';
    if (previous.isNotEmpty && current.startsWith(previous)) {
      return current.substring(previous.length);
    }
    return current == previous ? '' : current;
  }

  String _messageKeyForError(Object error) {
    final text = error.toString();
    if (text.contains('401') || text.contains('403')) {
      return 'ai_test_auth_error';
    }
    if (text.contains('404')) return 'ai_test_not_found';
    if (text.contains('429')) return 'ai_test_rate_limited';
    if (text.contains('timeout')) return 'ai_test_timeout';
    return 'voice_recognize_failed';
  }

  void _showError(String messageKey) {
    _showErrorDetail(messageKey, null);
  }

  void _resetStartFailure() {
    _running = false;
    _finishAfterQueue = false;
    _producerRunning = false;
    _consumerRunning = false;
    _activeProviderKind = null;
    _discardQueuedChunks();
    _setStatusMessage(null);
    if (mounted && _state != VoiceInputState.idle) {
      _setStateKind(VoiceInputState.idle);
    }
  }

  void _showErrorDetail(String messageKey, Object? error) {
    _running = false;
    _finishAfterQueue = false;
    _producerRunning = false;
    _discardQueuedChunks();
    _setStateKind(VoiceInputState.error);
    widget.onError?.call(messageKey);
    unawaited(
      AppLog.warning(
        'Voice input error: $messageKey',
        source: 'voice',
        error: error,
      ),
    );
    if (mounted) {
      final l10n = context.read<LocalizationProvider>();
      final message = error == null
          ? l10n.get(messageKey)
          : l10n.getp('voice_recognize_failed_with_error', {
              'error': _safeErrorText(error),
            });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      _setStateKind(VoiceInputState.idle);
    }
  }

  void _setStatusMessage(String? messageKey) {
    if (!mounted) return;
    if (_statusMessageKey == messageKey) return;
    setState(() => _statusMessageKey = messageKey);
  }

  String _safeErrorText(Object error) {
    final text = error.toString();
    final redacted = text.replaceAll(
      RegExp(r'sk-[A-Za-z0-9_\-]{8,}'),
      'sk-***',
    );
    return redacted.length > 120
        ? '${redacted.substring(0, 120)}...'
        : redacted;
  }

  @override
  void dispose() {
    _sessionId++;
    _running = false;
    _finishAfterQueue = false;
    _discardQueuedChunks();
    _speech.stop();
    _recorder.dispose();
    _sherpaIdleDisposeTimer?.cancel();
    _disposeSherpaOnnxService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final color = switch (_state) {
      VoiceInputState.idle => null,
      VoiceInputState.preparing => Theme.of(context).colorScheme.primary,
      VoiceInputState.ready => Theme.of(context).colorScheme.primary,
      VoiceInputState.recording => Colors.green,
      VoiceInputState.transcribing => Theme.of(context).colorScheme.primary,
      VoiceInputState.stopping => Colors.orange,
      VoiceInputState.error => Colors.red,
    };
    final tooltip = switch (_state) {
      VoiceInputState.idle => l10n.get('voice_input'),
      VoiceInputState.preparing => l10n.get('voice_preparing'),
      VoiceInputState.ready => l10n.get('voice_ready'),
      VoiceInputState.recording => l10n.get('voice_stop_recording'),
      VoiceInputState.transcribing => l10n.get('voice_transcribing'),
      VoiceInputState.stopping => l10n.get('voice_stopping'),
      VoiceInputState.error => l10n.get('voice_recognize_failed'),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _toggleListening,
          icon: Icon(_isActive ? Icons.mic : Icons.mic_none, color: color),
          style: IconButton.styleFrom(
            backgroundColor: color?.withValues(alpha: 0.12),
          ),
          tooltip: tooltip,
        ),
        if (_statusMessageKey != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.get(_statusMessageKey!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (_activeConfigLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _activeConfigLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

enum _VoiceProviderKind { ai, system, sherpaOnnx, none }

enum _VoiceChunkKind { ai, sherpa }

class _VoiceChunkJob {
  const _VoiceChunkJob._({
    required this.kind,
    required this.sessionId,
    required this.chunkPath,
    this.aiProvider,
    this.config,
    this.service,
  });

  const _VoiceChunkJob.ai({
    required int sessionId,
    required String chunkPath,
    required AiProvider aiProvider,
    required AiConfig config,
  }) : this._(
         kind: _VoiceChunkKind.ai,
         sessionId: sessionId,
         chunkPath: chunkPath,
         aiProvider: aiProvider,
         config: config,
       );

  const _VoiceChunkJob.sherpa({
    required int sessionId,
    required String chunkPath,
    required OnDeviceSttService service,
  }) : this._(
         kind: _VoiceChunkKind.sherpa,
         sessionId: sessionId,
         chunkPath: chunkPath,
         service: service,
       );

  final _VoiceChunkKind kind;
  final int sessionId;
  final String chunkPath;
  final AiProvider? aiProvider;
  final AiConfig? config;
  final OnDeviceSttService? service;
}

class _ResolvedVoiceProvider {
  const _ResolvedVoiceProvider._(
    this.kind,
    this.config,
    this.engine,
    this.whisperModel,
  );
  const _ResolvedVoiceProvider.ai(AiConfig config)
    : this._(_VoiceProviderKind.ai, config, null, null);
  const _ResolvedVoiceProvider.system()
    : this._(_VoiceProviderKind.system, null, null, null);
  const _ResolvedVoiceProvider.none()
    : this._(_VoiceProviderKind.none, null, null, null);
  const _ResolvedVoiceProvider.sherpaOnnx({
    required String engine,
    required String whisperModel,
  }) : this._(_VoiceProviderKind.sherpaOnnx, null, engine, whisperModel);

  final _VoiceProviderKind kind;
  final AiConfig? config;
  final String? engine;
  final String? whisperModel;
}
