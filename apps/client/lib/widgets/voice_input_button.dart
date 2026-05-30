import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:mianshi_zhilian/services/whisper_stt_service.dart';
import 'package:mianshi_zhilian/utils/platform_file_reader.dart';

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.onResult,
    this.onListeningChanged,
    this.sttMode = 'system',
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
  final WhisperSttService _whisperService = WhisperSttService();

  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    if (widget.sttMode == 'system') {
      _initSystemSpeech();
    }
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
    if (widget.sttMode == 'whisper') {
      await _startWhisperRecording();
    } else {
      await _startSystemListening();
    }
  }

  Future<void> _stopListening() async {
    if (widget.sttMode == 'whisper') {
      await _stopWhisperRecording();
    } else {
      await _stopSystemListening();
    }
  }

  // ── System STT ──

  Future<void> _startSystemListening() async {
    if (!_isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别不可用，请检查麦克风权限')),
        );
      }
      return;
    }

    setState(() => _isListening = true);
    widget.onListeningChanged?.call(true);

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          widget.onResult(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        localeId: 'zh_CN',
      ),
    );
  }

  Future<void> _stopSystemListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
    widget.onListeningChanged?.call(false);
  }

  // ── Whisper STT ──

  Future<void> _startWhisperRecording() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Whisper 语音输入暂不支持 Web 端，请使用系统语音')),
        );
      }
      return;
    }

    if (widget.whisperBaseUrl == null || widget.whisperApiKey == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中配置 Whisper API')),
        );
      }
      return;
    }

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请授予麦克风权限')),
          );
        }
        return;
      }

      setState(() => _isListening = true);
      widget.onListeningChanged?.call(true);

      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/mianshi_stt_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: tempPath,
      );
    } catch (e) {
      setState(() => _isListening = false);
      widget.onListeningChanged?.call(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('录音启动失败: $e')),
        );
      }
    }
  }

  Future<void> _stopWhisperRecording() async {
    try {
      final path = await _recorder.stop();
      setState(() => _isListening = false);
      widget.onListeningChanged?.call(false);

      if (path == null || path.isEmpty) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('正在识别语音...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      final audioBytes = await readBytesFromPath(path);
      await deleteFileAtPath(path);

      final result = await _whisperService.transcribe(
        audioBytes: audioBytes,
        baseUrl: widget.whisperBaseUrl!,
        apiKey: widget.whisperApiKey!,
        model: widget.whisperModel,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        if (result.isNotEmpty) {
          widget.onResult(result);
        }
      }
    } catch (e) {
      setState(() => _isListening = false);
      widget.onListeningChanged?.call(false);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('语音识别失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _toggleListening,
      icon: Icon(
        _isListening ? Icons.mic : Icons.mic_none,
        color: _isListening ? Colors.red : null,
      ),
      tooltip: _isListening
          ? '停止录音'
          : (widget.sttMode == 'whisper' ? 'Whisper 语音输入' : '语音输入'),
    );
  }
}
