import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.onResult,
    this.onListeningChanged,
  });

  final ValueChanged<String> onResult;
  final ValueChanged<bool>? onListeningChanged;

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _isAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
          widget.onListeningChanged?.call(false);
        }
      },
      onError: (error) {
        setState(() => _isListening = false);
        widget.onListeningChanged?.call(false);
        debugPrint('Speech error: $error');
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (!_isAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('语音识别不可用，请检查麦克风权限')));
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      widget.onListeningChanged?.call(false);
    } else {
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
  }

  @override
  void dispose() {
    _speech.stop();
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
      tooltip: _isListening ? '停止录音' : '语音输入',
    );
  }
}
