import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
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
import 'package:mianshi_zhilian/services/on_device_stt_service.dart';
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

  OnDeviceSttService? _onDevice;
  VoiceInputState _state = VoiceInputState.idle;
  bool _systemAvailable = false;
  bool _running = false;
  String _lastSystemText = '';
  String _lastCumulativeText = '';
  String _previewText = '';

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
    _lastCumulativeText = '';
    _previewText = '';

    switch (provider.kind) {
      case _VoiceProviderKind.ai:
        await _startAiStreaming(provider.config!);
        break;
      case _VoiceProviderKind.system:
        await _startSystemListening();
        break;
      case _VoiceProviderKind.whisperKit:
        await _startOnDeviceStreaming();
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
    if (mode == 'system') return const _ResolvedVoiceProvider.system();
    if (mode == 'whisper_kit') return const _ResolvedVoiceProvider.whisperKit();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return const _ResolvedVoiceProvider.whisperKit();
    }
    return const _ResolvedVoiceProvider.system();
  }

  Future<void> _startSystemListening() async {
    if (!await AppPermissionService.ensureSpeechRecognition(context)) return;
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
      _showError('system_speech_unsupported');
      return;
    }

    _setStateKind(VoiceInputState.recording);
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
      _showError('voice_web_unsupported');
      return;
    }
    if (!await AppPermissionService.ensureMicrophone(context)) return;
    _setStateKind(VoiceInputState.recording);
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
        if (!_running && bytes.isEmpty) break;
        final text = await aiProvider.transcribeAudio(
          config: config,
          audioBytes: bytes,
        );
        _emitText(text);
        if (_running) _setStateKind(VoiceInputState.recording);
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

  Future<void> _startOnDeviceStreaming() async {
    if (kIsWeb) {
      _showError('whisper_kit_web_unsupported');
      return;
    }
    if (!await AppPermissionService.ensureMicrophone(context)) return;
    _onDevice ??= OnDeviceSttService();
    if (!_onDevice!.isModelReady) {
      if (await _onDevice!.isModelFilePresent()) {
        await _onDevice!.initModel();
      } else {
        _showError('whisper_kit_model_not_downloaded');
        return;
      }
    }
    _setStateKind(VoiceInputState.recording);
    unawaited(
      _onDevice!
          .startStreaming(
            onResult: (text) {
              final delta = _deltaFromCumulative(text, _lastCumulativeText);
              _lastCumulativeText = text;
              _emitText(delta);
            },
            onStatus: (status) {
              if (status == 'transcribing') {
                _setStateKind(VoiceInputState.transcribing);
              } else if (status == 'recording') {
                _setStateKind(VoiceInputState.recording);
              }
            },
          )
          .catchError((e) {
            _showError(_messageKeyForError(e));
          }),
    );
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

  Future<void> _stopListening() async {
    _running = false;
    _setStateKind(VoiceInputState.stopping);
    try {
      await _speech.stop();
    } catch (_) {}
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _onDevice?.stopStreaming();
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
    _running = false;
    _setStateKind(VoiceInputState.error);
    widget.onError?.call(messageKey);
    if (mounted) {
      final l10n = context.read<LocalizationProvider>();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get(messageKey))));
      _setStateKind(VoiceInputState.idle);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _recorder.dispose();
    _onDevice?.dispose();
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
        if (_previewText.isNotEmpty && _isActive)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                _previewText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

enum _VoiceProviderKind { ai, system, whisperKit, none }

class _ResolvedVoiceProvider {
  const _ResolvedVoiceProvider._(this.kind, this.config);
  const _ResolvedVoiceProvider.ai(AiConfig config)
    : this._(_VoiceProviderKind.ai, config);
  const _ResolvedVoiceProvider.system()
    : this._(_VoiceProviderKind.system, null);
  const _ResolvedVoiceProvider.whisperKit()
    : this._(_VoiceProviderKind.whisperKit, null);

  final _VoiceProviderKind kind;
  final AiConfig? config;
}
