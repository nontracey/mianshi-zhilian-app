import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/ai_config.dart';
import '../providers/ai_provider.dart';
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
  _DiagStatus _whisperKitModelStatus = _DiagStatus.checking;
  String _speechDetail = '';
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
    final currentMode = settings.sttMode;
    final aiProvider = context.read<AiProvider>();
    final route = _resolveRoute(settings, aiProvider);

    // ── 麦克风权限（所有模式都检查）──
    _micStatus = await _checkMicPermission()
        ? _DiagStatus.pass
        : _DiagStatus.fail;
    if (mounted) setState(() {});

    // ── 系统语音引擎（实际会走 system 时检查）──
    if (route.kind == _DiagRouteKind.system || currentMode == 'system') {
      final (ok, detail) = await _checkSpeechEngine();
      _speechStatus = ok ? _DiagStatus.pass : _DiagStatus.fail;
      _speechDetail = detail;
    } else {
      _speechStatus = _DiagStatus.checking;
      _speechDetail = '';
    }
    if (mounted) setState(() {});

    // ── WhisperKit 本机模型检测（实际会走 whisper_kit 时检查）──
    if (route.kind == _DiagRouteKind.whisperKit ||
        currentMode == 'whisper_kit') {
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

  /// 检测本机 Whisper 模型下载状态（只读，不会触发模型下载）
  Future<void> _checkWhisperKitModel() async {
    final l10n = context.read<LocalizationProvider>();
    try {
      final dir = Platform.isAndroid
          ? await getApplicationSupportDirectory()
          : await getLibraryDirectory();
      final modelFile = File('${dir.path}/ggml-tiny.bin');
      final exists = await modelFile.exists();
      if (mounted) {
        setState(() {
          _whisperKitModelStatus = exists ? _DiagStatus.pass : _DiagStatus.fail;
          _whisperKitDetail = exists
              ? l10n.get('whisper_kit_model_downloaded')
              : '';
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
    final aiProvider = context.watch<AiProvider>();
    final isWhisperKit = settings.sttMode == 'whisper_kit';
    final isSystem = settings.sttMode == 'system';
    final route = _resolveRoute(settings, aiProvider);

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
              icon: isWhisperKit ? Icons.memory : Icons.phone_android,
              color: Theme.of(context).colorScheme.secondary,
              label: l10n.get('voice_setting_mode'),
              trailing: Text(
                _modeLabel(l10n, settings.sttMode),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _DiagRow(
              icon: _routeIcon(route.kind),
              color: _routeColor(context, route.kind),
              label: l10n.get('voice_actual_route'),
              trailing: Text(
                _routeLabel(l10n, route),
                style: TextStyle(
                  color: _routeColor(context, route.kind),
                  fontWeight: FontWeight.w600,
                ),
              ),
              detail: route.detail,
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

            // 系统语音引擎诊断（仅 system 模式）
            if (isSystem || route.kind == _DiagRouteKind.system)
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

            // WhisperKit 模型状态（仅 whisper_kit 模式）
            if (isWhisperKit || route.kind == _DiagRouteKind.whisperKit)
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
            if (_speechStatus == _DiagStatus.fail && isSystem)
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

            if (_whisperKitModelStatus == _DiagStatus.fail && isWhisperKit)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.get('whisper_kit_model_not_downloaded'),
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
                          _whisperKitModelStatus = _DiagStatus.checking;
                          _speechDetail = '';
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
                  _running ? l10n.get('stt_testing') : l10n.get('refresh'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _DiagRoute _resolveRoute(dynamic settings, AiProvider aiProvider) {
    final mode = settings.sttMode as String;
    final fixed = settings.sttAiConfigId == null
        ? null
        : aiProvider.configById(settings.sttAiConfigId as String?);
    final defaultConfig = aiProvider.defaultConfig;

    AiConfig? audioConfig;
    if (mode == 'fixed_ai_config') {
      audioConfig = fixed?.canTranscribe == true ? fixed : null;
    } else if (mode == 'follow_current_ai') {
      audioConfig = defaultConfig?.canTranscribe == true ? defaultConfig : null;
    } else if (mode == 'auto') {
      audioConfig = fixed?.canTranscribe == true
          ? fixed
          : (defaultConfig?.canTranscribe == true ? defaultConfig : null);
    }

    if (audioConfig != null) {
      return _DiagRoute(
        _DiagRouteKind.ai,
        '${audioConfig.name} · ${audioConfig.model}',
      );
    }
    if (mode == 'system') return const _DiagRoute(_DiagRouteKind.system);
    if (mode == 'whisper_kit') {
      return const _DiagRoute(_DiagRouteKind.whisperKit);
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return const _DiagRoute(_DiagRouteKind.whisperKit);
    }
    return const _DiagRoute(_DiagRouteKind.system);
  }

  String _modeLabel(LocalizationProvider l10n, String mode) {
    return switch (mode) {
      'auto' => l10n.get('stt_mode_auto'),
      'follow_current_ai' => l10n.get('stt_mode_follow_current_ai'),
      'fixed_ai_config' => l10n.get('stt_mode_fixed_ai'),
      'whisper_kit' => l10n.get('whisper_kit_mode_label'),
      'system' => l10n.get('system_speech_voice'),
      _ => mode,
    };
  }

  String _routeLabel(LocalizationProvider l10n, _DiagRoute route) {
    return switch (route.kind) {
      _DiagRouteKind.ai => l10n.get('voice_route_ai'),
      _DiagRouteKind.whisperKit => l10n.get('whisper_kit_mode_label'),
      _DiagRouteKind.system => l10n.get('system_speech_voice'),
    };
  }

  IconData _routeIcon(_DiagRouteKind kind) {
    return switch (kind) {
      _DiagRouteKind.ai => Icons.cloud_outlined,
      _DiagRouteKind.whisperKit => Icons.memory,
      _DiagRouteKind.system => Icons.phone_android,
    };
  }

  Color _routeColor(BuildContext context, _DiagRouteKind kind) {
    return switch (kind) {
      _DiagRouteKind.ai => Theme.of(context).colorScheme.primary,
      _DiagRouteKind.whisperKit => Colors.deepPurple,
      _DiagRouteKind.system => Theme.of(context).colorScheme.secondary,
    };
  }
}

enum _DiagRouteKind { ai, whisperKit, system }

class _DiagRoute {
  const _DiagRoute(this.kind, [this.detail]);

  final _DiagRouteKind kind;
  final String? detail;
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
                child: Text(label, style: const TextStyle(fontSize: 14)),
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
