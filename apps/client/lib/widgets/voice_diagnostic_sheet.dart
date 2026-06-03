import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../providers/localization_provider.dart';
import '../providers/settings_provider.dart';
import '../services/whisper_stt_service.dart';

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
  _DiagStatus _whisperConnStatus = _DiagStatus.checking;
  _DiagStatus _whisperKitModelStatus = _DiagStatus.checking;
  String _speechDetail = '';
  String _whisperConnDetail = '';
  String _whisperKitDetail = '';
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

    // Whisper 配置检测（仅检查字段是否填写，不代表 API 一定可用）
    if (settings.sttMode == 'whisper') {
      final baseUrlOk =
          settings.whisperBaseUrl != null && settings.whisperBaseUrl!.trim().isNotEmpty;
      final apiKeyOk =
          settings.whisperApiKey != null && settings.whisperApiKey!.trim().isNotEmpty;
      if (baseUrlOk && apiKeyOk) {
        _whisperConfigStatus = _DiagStatus.pass;
        // 启动后台静默测试实际 API 连通性
        _testWhisperConnection(settings);
      } else {
        _whisperConfigStatus = _DiagStatus.fail;
      }
    } else {
      _whisperConfigStatus = _DiagStatus.checking;
    }

    // WhisperKit 本机模型检测
    if (settings.sttMode == 'whisper_kit') {
      await _checkWhisperKitModel();
    } else {
      _whisperKitModelStatus = _DiagStatus.checking;
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

  /// 后台静默测试 Whisper API 实际连通性
  Future<void> _testWhisperConnection(dynamic settings) async {
    final l10n = context.read<LocalizationProvider>();
    try {
      final svc = WhisperSttService();
      final ok = await svc.testConnection(
        baseUrl: settings.whisperBaseUrl!,
        apiKey: settings.whisperApiKey!,
        model: settings.whisperModel,
      );
      if (mounted) {
        setState(() {
          _whisperConnStatus = ok ? _DiagStatus.pass : _DiagStatus.fail;
          _whisperConnDetail = ok
              ? ''
              : l10n.get('whisper_kit_endpoint_unreachable');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _whisperConnStatus = _DiagStatus.fail;
          _whisperConnDetail = '$e';
        });
      }
    }
  }

  /// 检测本机 Whisper 模型下载状态（只读，不会触发模型下载）
  Future<void> _checkWhisperKitModel() async {
    final l10n = context.read<LocalizationProvider>();
    try {
      // 路径逻辑与 whisper_kit 内部 _getModelDir() 保持一致
      final dir = Platform.isAndroid
          ? await getApplicationSupportDirectory()
          : await getLibraryDirectory();
      final modelFile = File('${dir.path}/ggml-tiny.bin');
      final exists = await modelFile.exists();
      if (mounted) {
        setState(() {
          _whisperKitModelStatus = exists ? _DiagStatus.pass : _DiagStatus.fail;
          _whisperKitDetail =
              exists ? l10n.get('whisper_kit_model_downloaded') : '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _whisperKitModelStatus = _DiagStatus.fail;
          _whisperKitDetail = '$e';
        });
      }
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
    final isWhisperKit = settings.sttMode == 'whisper_kit';

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
              icon: isWhisperKit
                  ? Icons.memory
                  : isWhisper
                      ? Icons.cloud_outlined
                      : Icons.phone_android,
              color: Theme.of(context).colorScheme.secondary,
              label: l10n.get('mode_type_name'),
              trailing: Text(
                isWhisperKit
                    ? l10n.get('whisper_kit_mode_label')
                    : isWhisper
                        ? 'Whisper API'
                        : l10n.get('system_speech_voice'),
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

            // 系统语音引擎诊断（仅供参考）
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

            // Whisper 配置检测（仅 whisper 模式下显示）
            if (isWhisper) ...[
              _DiagRow(
                icon: _iconFor(_whisperConfigStatus),
                color: _colorFor(_whisperConfigStatus),
                label: l10n.get('whisper_config_label'),
                trailing: Text(
                  _whisperConfigStatus == _DiagStatus.pass
                      ? l10n.get('stt_configured')
                      : l10n.get('stt_not_configured'),
                  style: TextStyle(
                    color: _colorFor(_whisperConfigStatus),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // 只有配置正确后才尝试 API 连通性检测
              if (_whisperConfigStatus == _DiagStatus.pass)
                _DiagRow(
                  icon: _iconFor(_whisperConnStatus),
                  color: _colorFor(_whisperConnStatus),
                  label: l10n.get('whisper_api_connectivity'),
                  trailing: Text(
                    _whisperConnStatus == _DiagStatus.checking
                        ? l10n.get('stt_testing')
                        : (_whisperConnStatus == _DiagStatus.pass
                            ? l10n.get('stt_reachable')
                            : l10n.get('stt_unreachable')),
                    style: TextStyle(
                      color: _colorFor(_whisperConnStatus),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  detail: _whisperConnDetail.isNotEmpty
                      ? _whisperConnDetail
                      : null,
                ),
            ],

            // WhisperKit 模型状态（仅 whisper_kit 模式显示）
            if (isWhisperKit)
              _DiagRow(
                icon: _iconFor(_whisperKitModelStatus),
                color: _colorFor(_whisperKitModelStatus),
                label: l10n.get('whisper_kit_model_label'),
                trailing: Text(
                  _whisperKitModelStatus == _DiagStatus.checking
                      ? l10n.get('stt_testing')
                      : (_whisperKitModelStatus == _DiagStatus.pass
                          ? l10n.get('whisper_kit_model_downloaded')
                          : l10n.get('whisper_kit_model_not_downloaded')),
                  style: TextStyle(
                    color: _colorFor(_whisperKitModelStatus),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                detail: _whisperKitDetail.isNotEmpty ? _whisperKitDetail : null,
              ),

            const SizedBox(height: 20),

            // 提示信息
            if (_speechStatus == _DiagStatus.fail && !isWhisper && !isWhisperKit)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${l10n.get('system_speech_voice')}${l10n.get('stt_unavailable')}。'
                  '${l10n.get('stt_system_unavailable_tip_whisper_kit')}',
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
                          _whisperConnStatus = _DiagStatus.checking;
                          _whisperKitModelStatus = _DiagStatus.checking;
                          _speechDetail = '';
                          _whisperConnDetail = '';
                          _whisperKitDetail = '';
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