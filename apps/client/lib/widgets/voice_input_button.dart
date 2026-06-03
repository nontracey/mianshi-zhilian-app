import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:mianshi_zhilian/services/app_permission_service.dart';
import 'package:mianshi_zhilian/services/on_device_stt_service.dart';
import 'package:mianshi_zhilian/services/whisper_stream_stt_service.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/utils/platform_file_reader.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.onResult,
    this.onListeningChanged,
    this.sttMode = 'whisper_kit',
    this.whisperBaseUrl,
    this.whisperApiKey,
    this.whisperModel = 'whisper-1',
  });

  final ValueChanged<String> onResult;
  final ValueChanged<bool>? onListeningChanged;
  final String sttMode;
  final String? whisperBaseUrl;
  final String? whisperApiKey;
  final String whisperModel;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  // System STT
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;

  // Whisper STT
  final AudioRecorder _recorder = AudioRecorder();

  // WhisperKit (本机 whisper.cpp)
  OnDeviceSttService? _whisperKit;
  bool _whisperKitReady = false;
  String _accumulatedText = '';

  bool _isListening = false;
  late LocalizationProvider l10n;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initSystemSpeech() async {
    _isAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) {
            setState(() => _isListening = false);
            widget.onListeningChanged?.call(false);
          }
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _isListening = false);
          widget.onListeningChanged?.call(false);
        }
        debugPrint('Speech error: $error');
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (widget.sttMode == 'whisper_kit') {
      await _startWhisperKitStreaming();
    } else if (widget.sttMode == 'whisper') {
      await _startWhisperStreaming();
    } else {
      await _startSystemListening();
    }
  }

  Future<void> _stopListening() async {
    if (widget.sttMode == 'whisper_kit') {
      await _stopWhisperKitStreaming();
    } else if (widget.sttMode == 'whisper') {
      await _stopWhisperStreaming();
    } else {
      await _stopSystemListening();
    }
  }

  // ── System STT ──

  /// 本地模式不可用时的降级弹窗
  Future<void> _showLocalModeUnavailable({
    required String messageKey,
    required String currentMode,
  }) async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('voice_not_available')),
        content: Text(l10n.get(messageKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'switch'),
            child: Text(l10n.get('switch_to_whisper_api')),
          ),
        ],
      ),
    );
    if (choice == 'switch' && mounted) {
      context
          .read<SettingsProvider>()
          .updateSettings(
            context.read<SettingsProvider>().settings.copyWith(sttMode: 'whisper'),
          );
    }
  }

  Future<void> _startSystemListening() async {
    if (!await AppPermissionService.ensureSpeechRecognition(context)) return;
    if (!mounted) return;

    try {
      if (!_isAvailable) {
        await _initSystemSpeech();
        if (!mounted) return;
      }

      if (!_isAvailable) {
        if (mounted) {
          _showLocalModeUnavailable(
            messageKey: 'system_speech_unsupported',
            currentMode: 'system',
          );
        }
        return;
      }

      setState(() => _isListening = true);
      widget.onListeningChanged?.call(true);

      await _speech.listen(
        onResult: (result) {
          widget.onResult(result.recognizedWords);
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
          localeId: 'zh_CN',
        ),
      );
    } catch (e) {
      debugPrint('System STT error: $e');
      if (mounted) {
        setState(() => _isListening = false);
        widget.onListeningChanged?.call(false);
        _showLocalModeUnavailable(
          messageKey: 'system_speech_unsupported',
          currentMode: 'system',
        );
      }
    }
  }

  Future<void> _stopSystemListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
    widget.onListeningChanged?.call(false);
  }

  // ── Whisper STT (API 流式模式) ──

  /// 录制一个音频分块（3 秒），返回临时 WAV 文件路径。
  /// whisper_kit 和 Whisper API 流式模式共用此方法。
  Future<String?> _recordChunk() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final chunkPath =
          '${tempDir.path}/whisper_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: chunkPath,
      );

      await Future.delayed(const Duration(seconds: 3));

      if (!_isListening) {
        await _recorder.stop();
        return null;
      }

      final path = await _recorder.stop();
      return (path != null && path.isNotEmpty) ? path : null;
    } catch (e) {
      debugPrint('Record chunk failed: $e');
      return null;
    }
  }

  Future<void> _startWhisperStreaming() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('voice_web_unsupported'))),
        );
      }
      return;
    }

    if (widget.whisperBaseUrl == null ||
        widget.whisperApiKey == null ||
        widget.whisperBaseUrl!.trim().isEmpty ||
        widget.whisperApiKey!.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('voice_no_whisper_key'))),
        );
      }
      return;
    }

    if (!await AppPermissionService.ensureMicrophone(context)) return;
    if (!mounted) return;

    _accumulatedText = '';
    setState(() => _isListening = true);
    widget.onListeningChanged?.call(true);

    final baseUrl = widget.whisperBaseUrl!;
    final apiKey = widget.whisperApiKey!;
    final model = widget.whisperModel;

    // 分块录音 + 流式转写循环
    _runWhisperStreamLoop(baseUrl, apiKey, model);
  }

  Future<void> _runWhisperStreamLoop(
    String baseUrl,
    String apiKey,
    String model,
  ) async {
    final streamSvc = WhisperStreamSttService();
    try {
      while (_isListening) {
        final chunkPath = await _recordChunk();
        if (chunkPath == null || !_isListening) break;

        final audioBytes = await readBytesFromPath(chunkPath);
        try {
          await deleteFileAtPath(chunkPath);
        } catch (_) {}

        if (!_isListening) break;

        try {
          await for (final text in streamSvc.transcribeStream(
            audioBytes: audioBytes,
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            language: 'zh',
          )) {
            if (!_isListening) break;
            _accumulatedText += text;
            if (mounted) setState(() {});
          }
        } catch (e) {
          debugPrint('Whisper stream chunk error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '转写失败: ${e.toString().length > 100 ? '${e.toString().substring(0, 100)}...' : e}',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          break; // 停止重试，一次失败说明 API 不可用
        }
      }
    } catch (e) {
      debugPrint('Whisper streaming error: $e');
    } finally {
      if (mounted) {
        setState(() => _isListening = false);
        widget.onListeningChanged?.call(false);
        if (_accumulatedText.isNotEmpty) {
          widget.onResult(_accumulatedText);
          _accumulatedText = '';
        }
      }
    }
  }

  Future<void> _stopWhisperStreaming() async {
    _isListening = false;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  // ── WhisperKit (本机 whisper.cpp 边说边转) ──

  Future<void> _ensureWhisperKit() async {
    if (_whisperKitReady) return;

    _whisperKit ??= OnDeviceSttService();
    if (_whisperKit!.isModelReady) {
      _whisperKitReady = true;
      return;
    }

    if (_whisperKit!.isModelDownloading) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.get('whisper_kit_model_downloading')),
          ),
        );
      }
      return;
    }

    // 模型未下载，弹出引导弹窗
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('whisper_kit_download_prompt_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.get('whisper_kit_download_prompt_desc')),
            const SizedBox(height: 8),
            Text(
              l10n.get('whisper_kit_model_size'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(l10n.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'settings'),
            child: Text(l10n.get('whisper_kit_go_settings')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'download'),
            child: Text(l10n.get('whisper_kit_download_now')),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (choice == 'settings') {
      // 导航到个人中心设置页
      Navigator.of(context).pushNamed('/profile');
      return;
    }
    if (choice != 'download') return;

    // 开始下载
    try {
      await _whisperKit!.initModel(
        onProgress: (received, total) {
          if (mounted && total > 0 && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  l10n.getp('whisper_kit_downloading_percent', {
                    'percent': (received / total * 100).toStringAsFixed(0),
                  }),
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
      );
      if (mounted) {
        setState(() => _whisperKitReady = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.get('whisper_kit_download_complete')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showLocalModeUnavailable(
          messageKey: 'whisper_kit_unsupported_platform',
          currentMode: 'whisper_kit',
        );
      }
    }
  }

  Future<void> _startWhisperKitStreaming() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('whisper_kit_web_unsupported'))),
        );
      }
      return;
    }

    await _ensureWhisperKit();
    if (!_whisperKitReady || !mounted) return;

    if (!await AppPermissionService.ensureMicrophone(context)) return;
    if (!mounted) return;

    _accumulatedText = '';
    setState(() => _isListening = true);
    widget.onListeningChanged?.call(true);

    // 在后台启动边说边转循环
    unawaited(_whisperKit!.startStreaming(
      onResult: (text) {
        if (mounted) {
          _accumulatedText = text;
          setState(() {});
        }
      },
      onStatus: (_) {},
    ));
  }

  Future<void> _stopWhisperKitStreaming() async {
    await _whisperKit?.stopStreaming();
    setState(() => _isListening = false);
    widget.onListeningChanged?.call(false);

    if (_accumulatedText.isNotEmpty) {
      widget.onResult(_accumulatedText);
      _accumulatedText = '';
    }
  }

  /// 将服务层 modelStatus 码解析为 UI 可显示文本
  /// modelStatus 格式: 'ready' | 'not_downloaded' | 'downloading' | 'downloading:45'
  String _formatModelStatus(LocalizationProvider l10n_, String status) {
    if (status.startsWith('downloading:')) {
      final pct = status.split(':').last;
      return l10n_.getp('whisper_kit_downloading_percent', {'percent': pct});
    }
    switch (status) {
      case 'ready':
        return l10n_.get('whisper_kit_model_downloaded');
      case 'not_downloaded':
        return l10n_.get('whisper_kit_model_not_downloaded');
      case 'downloading':
        return l10n_.get('whisper_kit_model_downloading');
      default:
        return status;
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _recorder.dispose();
    _whisperKit?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    l10n = context.watch<LocalizationProvider>();
    final isWhisperKit = widget.sttMode == 'whisper_kit';
    final showModelProgress =
        isWhisperKit && _whisperKit != null && _whisperKit!.isModelDownloading;

    String tooltip;
    if (_isListening) {
      tooltip = l10n.get('voice_stop_recording');
    } else if (isWhisperKit) {
      tooltip = _whisperKitReady
          ? l10n.get('whisper_kit_input_tooltip')
          : l10n.get('whisper_kit_need_download_tooltip');
    } else if (widget.sttMode == 'whisper') {
      tooltip = l10n.get('voice_whisper_input');
    } else {
      tooltip = l10n.get('voice_input');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: showModelProgress ? null : _toggleListening,
          icon: Icon(
            _isListening ? Icons.mic : Icons.mic_none,
            color: _isListening ? Colors.green : null,
          ),
          style: IconButton.styleFrom(
            backgroundColor: _isListening
                ? Colors.green.withValues(alpha: 0.12)
                : null,
          ),
          tooltip: tooltip,
        ),
        // 模型下载进度指示
        if (showModelProgress && _whisperKit != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _formatModelStatus(l10n, _whisperKit!.modelStatus),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        // 边说边转实时文字预览
        if (isWhisperKit && _isListening && _accumulatedText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _accumulatedText,
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
