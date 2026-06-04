import 'dart:async';
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
import 'package:mianshi_zhilian/services/app_permission_service.dart';
import 'package:mianshi_zhilian/services/on_device_stt/model_downloader.dart';
import 'package:mianshi_zhilian/services/on_device_stt/on_device_stt_factory.dart';
import 'package:mianshi_zhilian/services/on_device_stt/on_device_stt_service.dart';
import 'package:mianshi_zhilian/utils/platform_file_reader.dart';

enum VoiceInputState { idle, recording, transcribing, stopping, error }

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
  bool _systemAvailable = false;
  bool _running = false;
  String _lastSystemText = '';
  String _previewText = '';
  String? _statusMessageKey;
  OnDeviceSttService? _sherpaOnnxService;

  /// 当前活跃的 AI 配置名（用于转写时显示模型信息）
  String? _activeConfigLabel;
  bool get _isActive =>
      _state == VoiceInputState.recording ||
      _state == VoiceInputState.transcribing ||
      _state == VoiceInputState.stopping;

  void _setStateKind(VoiceInputState state) {
    if (!mounted) return;
    setState(() => _state = state);
    widget.onListeningChanged?.call(_isActive);
    widget.onStateChanged?.call(state);
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

    _running = true;
    _lastSystemText = '';
    _previewText = '';
    _statusMessageKey = null;
    _activeConfigLabel = null;

    switch (provider.kind) {
      case _VoiceProviderKind.ai:
        await _startAiStreaming(provider.config!);
        break;
      case _VoiceProviderKind.system:
        await _startSystemListening();
        break;
      case _VoiceProviderKind.sherpaOnnx:
        final engine = provider.engine;
        final whisperModel = provider.whisperModel;
        if (engine == null || whisperModel == null) break;
        await _startSherpaOnnxListening(
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

  Future<void> _startSystemListening() async {
    if (!await AppPermissionService.ensureSpeechRecognition(context)) {
      _resetStartFailure();
      return;
    }
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
    if (!_systemAvailable) {
      _resetStartFailure();
      _showError('system_speech_unsupported');
      return;
    }

    _setStateKind(VoiceInputState.recording);
    _setStatusMessage('voice_recording_hint');
    await _speech.listen(
      onResult: (result) {
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

  Future<void> _startAiStreaming(AiConfig config) async {
    if (kIsWeb) {
      _resetStartFailure();
      _showError('voice_web_unsupported');
      return;
    }
    if (!await AppPermissionService.ensureMicrophone(context)) {
      _resetStartFailure();
      return;
    }
    _activeConfigLabel = '${config.name} · ${config.model}';
    _setStateKind(VoiceInputState.recording);
    _setStatusMessage('voice_recording_hint');
    unawaited(_runAiChunkLoop(config));
  }

  Future<void> _runAiChunkLoop(AiConfig config) async {
    final aiProvider = context.read<AiProvider>();
    try {
      while (_running) {
        final chunkPath = await _recordChunk(const Duration(seconds: 2));
        if (chunkPath == null) break;
        _setStateKind(VoiceInputState.transcribing);
        final bytes = await readBytesFromPath(chunkPath);
        try {
          await deleteFileAtPath(chunkPath);
        } catch (_) {}
        // 如果在录音/加载过程中用户停止了，丢弃此段结果
        if (!_running) break;
        final text = await aiProvider.transcribeAudio(
          config: config,
          audioBytes: bytes,
        );
        // 转写完成后再检查一次：如果已停止，丢弃结果避免竞态写入
        if (!_running) break;
        _emitText(text);
        if (_running) _setStateKind(VoiceInputState.recording);
        if (_running) _setStatusMessage('voice_recording_hint');
      }
    } catch (e) {
      _showError(_messageKeyForError(e));
    } finally {
      _running = false;
      if (mounted && _state != VoiceInputState.error) {
        _setStateKind(VoiceInputState.idle);
      }
    }
  }

  Future<String?> _recordChunk(Duration duration) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final chunkPath =
          '${tempDir.path}/voice_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: chunkPath,
      );
      await Future.delayed(duration);
      final path = await _recorder.stop();
      return (path != null && path.isNotEmpty) ? path : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _startSherpaOnnxListening({
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

    // 确定模型配置并检查是否就绪
    final modelConfig = _sherpaOnnxModelConfig(engine, whisperModel);
    if (modelConfig == null) {
      _showError('on_device_engine_unknown');
      _resetStartFailure();
      return;
    }
    final ready = await ModelDownloader.isModelReady(modelConfig);
    if (!ready) {
      _showError('on_device_model_not_downloaded');
      _resetStartFailure();
      return;
    }

    // 创建并初始化本机 STT 服务
    final modelDir = await ModelDownloader.getModelDir(modelConfig.id);
    final service = createOnDeviceSttService(
      engine: engine,
      modelDir: modelDir.path,
      whisperModelSize: whisperModel,
    );
    try {
      await service.initialize();
    } catch (e) {
      _showError('on_device_stt_init_failed');
      await service.dispose();
      _resetStartFailure();
      return;
    }
    _sherpaOnnxService = service;

    _activeConfigLabel = _sherpaOnnxEngineLabel(engine);
    _setStateKind(VoiceInputState.recording);
    _setStatusMessage('voice_recording_hint');
    unawaited(_runSherpaOnnxChunkLoop());
  }

  Future<void> _runSherpaOnnxChunkLoop() async {
    try {
      while (_running) {
        final chunkPath = await _recordChunk(const Duration(seconds: 3));
        if (chunkPath == null) break;
        _setStateKind(VoiceInputState.transcribing);
        final bytes = await readBytesFromPath(chunkPath);
        try {
          await deleteFileAtPath(chunkPath);
        } catch (_) {}
        if (!_running || _sherpaOnnxService == null) break;

        // 将 WAV bytes 转为 Float32List（16-bit PCM → [-1, 1]）
        final samples = _wavBytesToFloat32List(bytes);
        if (samples == null || samples.isEmpty) {
          if (_running) _setStateKind(VoiceInputState.recording);
          if (_running) _setStatusMessage('voice_recording_hint');
          continue;
        }

        try {
          final result = await _sherpaOnnxService!.transcribe(samples, 16000);
          if (!_running) break;
          final text = result.text.trim();
          if (text.isNotEmpty) {
            _emitText(text);
          }
        } catch (e) {
          // 单段转录失败不影响连续录音
          debugPrint('sherpa_onnx chunk transcribe failed: $e');
        }

        if (_running) _setStateKind(VoiceInputState.recording);
        if (_running) _setStatusMessage('voice_recording_hint');
      }
    } catch (e) {
      _showError('voice_recognize_failed');
    } finally {
      _running = false;
      await _disposeSherpaOnnxService();
      if (mounted && _state != VoiceInputState.error) {
        _setStateKind(VoiceInputState.idle);
      }
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

  OnDeviceModelConfig? _sherpaOnnxModelConfig(String engine, String whisperModel) {
    return switch (engine) {
      'sense_voice' => KnownModels.senseVoice,
      'whisper' => switch (whisperModel) {
        'tiny' => KnownModels.whisperTiny,
        'small' => KnownModels.whisperSmall,
        'medium' => KnownModels.whisperMedium,
        _ => KnownModels.whisperBase,
      },
      'paraformer' => KnownModels.paraformer,
      _ => null,
    };
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
    try {
      await _sherpaOnnxService?.dispose();
    } catch (_) {}
    _sherpaOnnxService = null;
  }

  Future<void> _stopListening() async {
    _running = false;
    _setStateKind(VoiceInputState.stopping);
    _setStatusMessage('voice_stopping');
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) _setStateKind(VoiceInputState.idle);
  }

  void _emitText(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    widget.onResult(cleaned);
    if (mounted) {
      setState(() {
        _previewText = (_previewText + cleaned).trim();
        if (_previewText.length > 80) {
          _previewText = _previewText.substring(_previewText.length - 80);
        }
      });
    }
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
    if (mounted && _state != VoiceInputState.idle) {
      _setStateKind(VoiceInputState.idle);
    }
  }

  void _showErrorDetail(String messageKey, Object? error) {
    _running = false;
    _setStateKind(VoiceInputState.error);
    widget.onError?.call(messageKey);
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

  void _setStatusMessage(String messageKey) {
    if (!mounted) return;
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
    _speech.stop();
    _recorder.dispose();
    _disposeSherpaOnnxService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final color = switch (_state) {
      VoiceInputState.idle => null,
      VoiceInputState.recording => Colors.green,
      VoiceInputState.transcribing => Theme.of(context).colorScheme.primary,
      VoiceInputState.stopping => Colors.orange,
      VoiceInputState.error => Colors.red,
    };
    final tooltip = switch (_state) {
      VoiceInputState.idle => l10n.get('voice_input'),
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
        if (_isActive && (_previewText.isNotEmpty || _statusMessageKey != null))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _previewText.isNotEmpty
                        ? _previewText
                        : l10n.get(_statusMessageKey!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
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
              ),
            ),
          ),
      ],
    );
  }
}

enum _VoiceProviderKind { ai, system, sherpaOnnx, none }

class _ResolvedVoiceProvider {
  const _ResolvedVoiceProvider._(this.kind, this.config, this.engine, this.whisperModel);
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
