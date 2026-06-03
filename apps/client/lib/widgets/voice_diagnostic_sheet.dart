import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../providers/localization_provider.dart';
import '../providers/settings_provider.dart';

enum _DiagStatus { checking, pass, fail }

class VoiceDiagnosticSheet extends StatefulWidget {
  const VoiceDiagnosticSheet({super.key});

  @override
  State<VoiceDiagnosticSheet> createState() => _VoiceDiagnosticSheetState();
}

class _VoiceDiagnosticSheetState extends State<VoiceDiagnosticSheet> {
  _DiagStatus _micStatus = _DiagStatus.checking;
  _DiagStatus _speechStatus = _DiagStatus.checking;
  _DiagStatus _whisperConfigStatus = _DiagStatus.checking;
  String _speechDetail = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _runAll();
  }

  Future<void> _runAll() async {
    if (_running) return;
    setState(() => _running = true);

    // 在 async 间隙前捕获 settings，避免 use_build_context_synchronously
    final settings = context.read<SettingsProvider>().settings;

    // 麦克风权限
    _micStatus = await _checkMicPermission()
        ? _DiagStatus.pass
        : _DiagStatus.fail;
    if (mounted) setState(() {});

    // 系统语音引擎（非 Web）
    if (!kIsWeb) {
      final (ok, detail) = await _checkSpeechEngine();
      _speechStatus = ok ? _DiagStatus.pass : _DiagStatus.fail;
      _speechDetail = detail;
      if (mounted) setState(() {});
    } else {
      _speechStatus = _DiagStatus.fail;
      _speechDetail = 'Web platform';
      if (mounted) setState(() {});
    }

    // Whisper 配置
    if (settings.sttMode == 'whisper') {
      final baseUrlOk =
          settings.whisperBaseUrl != null && settings.whisperBaseUrl!.trim().isNotEmpty;
      final apiKeyOk =
          settings.whisperApiKey != null && settings.whisperApiKey!.trim().isNotEmpty;
      _whisperConfigStatus =
          baseUrlOk && apiKeyOk ? _DiagStatus.pass : _DiagStatus.fail;
    } else {
      _whisperConfigStatus = _DiagStatus.checking;
    }
    if (mounted) setState(() => _running = false);
  }

  Future<bool> _checkMicPermission() async {
    if (kIsWeb) return true;
    final status = await Permission.microphone.status;
    if (status.isGranted || status.isLimited) return true;
    final result = await Permission.microphone.request();
    return result.isGranted || result.isLimited;
  }

  Future<(bool, String)> _checkSpeechEngine() async {
    try {
      final speech = stt.SpeechToText();
      final available = await speech.initialize(
        onStatus: (_) {},
        onError: (_) {},
      );
      speech.stop();
      if (available) {
        return (true, '');
      } else {
        return (false, 'initialize() returned false');
      }
    } catch (e) {
      return (false, '$e');
    }
  }

  IconData _iconFor(_DiagStatus status) {
    switch (status) {
      case _DiagStatus.checking:
        return Icons.hourglass_top;
      case _DiagStatus.pass:
        return Icons.check_circle;
      case _DiagStatus.fail:
        return Icons.error;
    }
  }

  Color _colorFor(_DiagStatus status) {
    switch (status) {
      case _DiagStatus.checking:
        return Colors.grey;
      case _DiagStatus.pass:
        return Colors.green;
      case _DiagStatus.fail:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final isWhisper = settings.sttMode == 'whisper';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.get('voice_diagnostic_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),

            // 当前模式
            _DiagRow(
              icon: isWhisper ? Icons.cloud_outlined : Icons.phone_android,
              color: Theme.of(context).colorScheme.secondary,
              label: l10n.get('mode_type_name'),
              trailing: Text(
                isWhisper ? 'Whisper API' : l10n.get('system_speech_voice'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Divider(height: 12),

            // 麦克风权限
            _DiagRow(
              icon: _iconFor(_micStatus),
              color: _colorFor(_micStatus),
              label: l10n.get('permission_microphone_name'),
              trailing: Text(
                _micStatus == _DiagStatus.checking
                    ? l10n.get('stt_testing')
                    : (_micStatus == _DiagStatus.pass
                        ? l10n.get('stt_available')
                        : l10n.get('stt_unavailable')),
                style: TextStyle(
                  color: _colorFor(_micStatus),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // 系统语音引擎
            _DiagRow(
              icon: _iconFor(_speechStatus),
              color: _colorFor(_speechStatus),
              label: l10n.get('system_speech_voice'),
              trailing: Text(
                _speechStatus == _DiagStatus.checking
                    ? l10n.get('stt_testing')
                    : (_speechStatus == _DiagStatus.pass
                        ? l10n.get('stt_available')
                        : l10n.get('stt_unavailable')),
                style: TextStyle(
                  color: _colorFor(_speechStatus),
                  fontWeight: FontWeight.w500,
                ),
              ),
              detail: _speechDetail.isNotEmpty ? _speechDetail : null,
            ),

            // Whisper 配置（仅 whisper 模式下显示）
            if (isWhisper)
              _DiagRow(
                icon: _iconFor(_whisperConfigStatus),
                color: _colorFor(_whisperConfigStatus),
                label: 'Whisper',
                trailing: Text(
                  _whisperConfigStatus == _DiagStatus.pass
                      ? l10n.get('stt_available')
                      : l10n.get('stt_unavailable'),
                  style: TextStyle(
                    color: _colorFor(_whisperConfigStatus),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // 提示信息
            if (_speechStatus == _DiagStatus.fail && !isWhisper)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${l10n.get('system_speech_voice')}${l10n.get('stt_unavailable')}。'
                  '${l10n.get('use_design_alternate_internal_set_speech_voice_identify_distinct_offline_53')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            // 重新检测
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _running
                    ? null
                    : () {
                        setState(() {
                          _micStatus = _DiagStatus.checking;
                          _speechStatus = _DiagStatus.checking;
                          _whisperConfigStatus = _DiagStatus.checking;
                          _speechDetail = '';
                        });
                        _runAll();
                      },
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                    _running ? l10n.get('stt_testing') : l10n.get('refresh')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.trailing,
    this.detail,
  });

  final IconData icon;
  final Color color;
  final String label;
  final Widget trailing;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              trailing,
            ],
          ),
          if (detail != null && detail!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text(
                detail!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}