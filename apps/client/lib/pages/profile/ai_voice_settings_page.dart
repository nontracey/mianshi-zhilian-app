import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/app_log_service.dart';
import 'package:mianshi_zhilian/services/on_device_stt/model_downloader.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/voice_diagnostic_sheet.dart';
import 'package:mianshi_zhilian/pages/profile/ai_config_page.dart';

class AiVoiceSettingsPage extends StatelessWidget {
  const AiVoiceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    return ProfileSubPage(
      title: l10n.get('ai_and_voice'),
      children: [
        AiConfigPanel(
          onNavigateToConfig: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AiConfigPage())),
        ),
        const SizedBox(height: 16),
        SttConfigPanel(
          settings: settingsProvider.settings,
          onSettingsChanged: settingsProvider.updateSettings,
        ),
      ],
    );
  }
}

class ProfileSubPage extends StatelessWidget {
  const ProfileSubPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(24), children: children),
    );
  }
}

class AiConfigPanel extends StatelessWidget {
  const AiConfigPanel({required this.onNavigateToConfig});

  final VoidCallback onNavigateToConfig;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final aiProvider = context.watch<AiProvider>();
    final configs = aiProvider.configs;
    final defaultConfig = configs.where((c) => c.isDefault).firstOrNull;

    return WorkPanel(
      title: l10n.get('ai_config'),
      icon: Icons.smart_toy_outlined,
      trailing: FilledButton.tonalIcon(
        onPressed: onNavigateToConfig,
        icon: const Icon(Icons.settings_outlined),
        label: Text(l10n.get('management_config')),
      ),
      children: [
        if (defaultConfig != null) ...[
          InfoRow(
            icon: Icons.hub_outlined,
            title: defaultConfig.name,
            subtitle: l10n.getp('model_status', {
              'model': defaultConfig.model,
              'status': defaultConfig.enabled
                  ? l10n.get('already_enable')
                  : l10n.get('already_disable'),
            }),
          ),
        ] else ...[
          InfoRow(
            icon: Icons.warning_amber_outlined,
            title: l10n.get('un_config_ai'),
            subtitle: l10n.get(
              'please_add_ai_config_by_use_evaluation_feature',
            ),
          ),
        ],
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SttConfigPanel extends StatefulWidget {
  const SttConfigPanel({
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<SttConfigPanel> createState() => SttConfigPanelState();
}

class SttConfigPanelState extends State<SttConfigPanel> {
  bool _onDeviceChecking = true;
  bool _onDeviceReady = false;
  bool _onDeviceModelReady = false;
  bool _onDeviceRuntimeReady = false;
  int? _onDeviceModelSizeBytes;
  int? _onDeviceRuntimeSizeBytes;
  bool _onDeviceDownloading = false;
  bool _onDeviceRuntimeDownloading = false;
  double _onDeviceProgress = 0.0;
  double _onDeviceRuntimeProgress = 0.0;
  String _onDeviceSource = '';
  String _onDeviceRuntimeSource = '';
  String _onDevicePhaseKey = '';
  String _onDeviceRuntimePhaseKey = '';
  double _onDeviceSpeed = 0;
  double _onDeviceRuntimeSpeed = 0;
  String? _onDeviceError;
  ResourceDownloadController? _modelDownloadController;
  ResourceDownloadController? _runtimeDownloadController;
  int _onDeviceStatusEpoch = 0;

  @override
  void initState() {
    super.initState();
    _checkOnDeviceStatus();
  }

  @override
  void didUpdateWidget(covariant SttConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.onDeviceEngine != widget.settings.onDeviceEngine ||
        oldWidget.settings.whisperModel != widget.settings.whisperModel) {
      _checkOnDeviceStatus(settings: widget.settings);
    }
  }

  AppSettings get _settings => widget.settings;

  Future<void> _checkOnDeviceStatus({AppSettings? settings}) async {
    final epoch = ++_onDeviceStatusEpoch;
    final activeSettings = settings ?? _settings;
    if (kIsWeb) {
      if (mounted && epoch == _onDeviceStatusEpoch) {
        setState(() {
          _onDeviceChecking = false;
          _onDeviceReady = false;
        });
      }
      return;
    }

    final engine = activeSettings.onDeviceEngine;
    final onDeviceModelConfig = _modelConfigForEngine(
      engine,
      activeSettings.whisperModel,
    );
    final runtimeConfig = KnownRuntimes.current();

    if (onDeviceModelConfig == null || runtimeConfig == null) {
      if (mounted && epoch == _onDeviceStatusEpoch) {
        setState(() {
          _onDeviceChecking = false;
          _onDeviceReady = false;
          _onDeviceModelReady = false;
          _onDeviceRuntimeReady = false;
        });
      }
      return;
    }

    try {
      final modelReady = await ModelDownloader.isModelReady(
        onDeviceModelConfig,
      );
      final runtimeReady = await ModelDownloader.isRuntimeReady(runtimeConfig);
      final size = await ModelDownloader.getModelSize(onDeviceModelConfig.id);
      final runtimeSize = await ModelDownloader.getRuntimeSize(
        runtimeConfig.id,
      );
      if (mounted && epoch == _onDeviceStatusEpoch) {
        setState(() {
          _onDeviceChecking = false;
          _onDeviceReady = modelReady && runtimeReady;
          _onDeviceModelReady = modelReady;
          _onDeviceRuntimeReady = runtimeReady;
          _onDeviceModelSizeBytes = size;
          _onDeviceRuntimeSizeBytes = runtimeSize;
        });
      }
    } catch (e) {
      if (mounted && epoch == _onDeviceStatusEpoch) {
        setState(() {
          _onDeviceChecking = false;
          _onDeviceReady = false;
          _onDeviceModelReady = false;
          _onDeviceRuntimeReady = false;
          _onDeviceError = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final aiProvider = context.watch<AiProvider>();
    final mode = _settings.sttMode;
    final audioConfigs = aiProvider.enabledConfigs
        .where((config) => config.audioMode != AiAudioMode.none)
        .toList(growable: false);
    final isSystem = mode == 'system';
    final isOnDevice = mode == 'sherpa_onnx';

    return WorkPanel(
      title: l10n.get('speech_voice_identify_distinct'),
      icon: Icons.mic_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SttModeCard(
                label: l10n.get('stt_mode_auto'),
                icon: Icons.auto_awesome,
                description: l10n.get('stt_mode_auto_desc'),
                selected: mode == 'auto',
                onTap: () => widget.onSettingsChanged(
                  _settings.copyWith(sttMode: 'auto'),
                ),
              ),
              SttModeCard(
                label: l10n.get('stt_mode_follow_current_ai'),
                icon: Icons.smart_toy_outlined,
                description: l10n.get('stt_mode_follow_current_ai_desc'),
                selected: mode == 'follow_current_ai',
                onTap: () => widget.onSettingsChanged(
                  _settings.copyWith(sttMode: 'follow_current_ai'),
                ),
              ),
              SttModeCard(
                label: l10n.get('stt_mode_fixed_ai'),
                icon: Icons.record_voice_over_outlined,
                description: l10n.get('stt_mode_fixed_ai_desc'),
                selected: mode == 'fixed_ai_config',
                onTap: () => widget.onSettingsChanged(
                  _settings.copyWith(sttMode: 'fixed_ai_config'),
                ),
              ),
              SttModeCard(
                label: l10n.get('system_speech_voice'),
                icon: Icons.phone_android,
                description: l10n.get('system_speech_voice_desc'),
                selected: isSystem,
                onTap: () => widget.onSettingsChanged(
                  _settings.copyWith(sttMode: 'system'),
                ),
              ),
              SttModeCard(
                label: l10n.get('on_device_stt_title'),
                icon: Icons.memory_outlined,
                description: l10n.get('on_device_stt_desc'),
                selected: isOnDevice,
                onTap: () => widget.onSettingsChanged(
                  _settings.copyWith(sttMode: 'sherpa_onnx'),
                ),
              ),
            ],
          ),
        ),
        if (mode == 'fixed_ai_config') ...[
          const SizedBox(height: 12),
          _buildFixedAiSelector(l10n, audioConfigs),
        ],
        if (isOnDevice) ...[
          const SizedBox(height: 12),
          _buildOnDeviceSettings(l10n),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.get('stt_settings_desc'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              builder: (_) => const VoiceDiagnosticSheet(),
            ),
            icon: const Icon(Icons.bug_report_outlined, size: 16),
            label: Text(l10n.get('voice_diagnostic_title')),
          ),
        ),
      ],
    );
  }

  Widget _buildFixedAiSelector(
    LocalizationProvider l10n,
    List<AiConfig> audioConfigs,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            initialValue:
                audioConfigs.any((c) => c.id == _settings.sttAiConfigId)
                ? _settings.sttAiConfigId
                : null,
            decoration: InputDecoration(
              labelText: l10n.get('fixed_voice_ai_config'),
              isDense: true,
            ),
            items: audioConfigs
                .map(
                  (config) => DropdownMenuItem(
                    value: config.id,
                    child: Text(config.name),
                  ),
                )
                .toList(),
            onChanged: (id) =>
                widget.onSettingsChanged(_settings.copyWith(sttAiConfigId: id)),
          ),
        ),
        if (audioConfigs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.get('no_voice_ai_config'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOnDeviceSettings(LocalizationProvider l10n) {
    final theme = Theme.of(context);

    if (kIsWeb) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          l10n.get('on_device_stt_web_unsupported'),
          style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _settings.onDeviceEngine,
            decoration: InputDecoration(
              labelText: l10n.get('on_device_engine_select'),
              isDense: true,
            ),
            items: ['sense_voice', 'whisper', 'paraformer'].map((engine) {
              return DropdownMenuItem(
                value: engine,
                child: Text(_engineLabel(context, engine)),
              );
            }).toList(),
            onChanged: (engine) {
              if (engine != null) {
                final nextSettings = _settings.copyWith(onDeviceEngine: engine);
                widget.onSettingsChanged(nextSettings);
                setState(() {
                  _onDeviceChecking = true;
                  _onDeviceReady = false;
                });
                _checkOnDeviceStatus(settings: nextSettings);
              }
            },
          ),
          const SizedBox(height: 8),
          if (_settings.onDeviceEngine == 'whisper') ...[
            DropdownButtonFormField<String>(
              initialValue: _settings.whisperModel,
              decoration: InputDecoration(
                labelText: l10n.get('on_device_whisper_model_select'),
                isDense: true,
              ),
              items: ['tiny', 'base', 'small', 'medium'].map((size) {
                return DropdownMenuItem(
                  value: size,
                  child: Text(_whisperModelLabel(l10n, size)),
                );
              }).toList(),
              onChanged: (size) {
                if (size != null) {
                  final nextSettings = _settings.copyWith(whisperModel: size);
                  widget.onSettingsChanged(nextSettings);
                  setState(() {
                    _onDeviceChecking = true;
                    _onDeviceReady = false;
                  });
                  _checkOnDeviceStatus(settings: nextSettings);
                }
              },
            ),
            const SizedBox(height: 4),
            Text(
              _whisperModelHint(l10n, _settings.whisperModel),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            _engineHint(context, _settings.onDeviceEngine),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildModelStatus(l10n, theme),
        ],
      ),
    );
  }

  Widget _buildModelStatus(LocalizationProvider l10n, ThemeData theme) {
    if (_onDeviceChecking) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.get('stt_testing'),
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _onDeviceReady ? Icons.check_circle : Icons.info_outline,
              size: 18,
              color: _onDeviceReady ? Colors.green : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _onDeviceReady
                    ? l10n.get('on_device_stt_ready')
                    : l10n.get('on_device_stt_requires_runtime_and_model'),
                style: TextStyle(
                  fontSize: 13,
                  color: _onDeviceReady
                      ? Colors.green
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (!_onDeviceReady) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _canStartMissingOnDeviceDownloads
                ? () => _downloadMissingOnDeviceResources(l10n)
                : null,
            icon: const Icon(Icons.download, size: 16),
            label: Text(l10n.get('download_required_resources')),
          ),
        ],
        const SizedBox(height: 8),
        _buildRuntimeResourceStatus(l10n, theme),
        const SizedBox(height: 10),
        _buildModelResourceStatus(l10n, theme),
        if (_onDeviceError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _onDeviceError!,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  bool get _canStartMissingOnDeviceDownloads {
    return (!_onDeviceRuntimeReady && !_onDeviceRuntimeDownloading) ||
        (!_onDeviceModelReady && !_onDeviceDownloading);
  }

  Widget _buildRuntimeResourceStatus(
    LocalizationProvider l10n,
    ThemeData theme,
  ) {
    final config = KnownRuntimes.current();
    if (config == null) return const SizedBox.shrink();
    final sizeText = _onDeviceRuntimeSizeBytes != null
        ? ' (${UpdateService.formatSize(_onDeviceRuntimeSizeBytes!)})'
        : '';
    return ResourceStatusBlock(
      icon: Icons.memory_outlined,
      title: l10n.get('on_device_runtime'),
      ready: _onDeviceRuntimeReady,
      readyText: '${l10n.get('runtime_ready')}$sizeText',
      missingText: l10n.get('runtime_not_ready'),
      downloading: _onDeviceRuntimeDownloading,
      progress: _onDeviceRuntimeProgress,
      source: _onDeviceRuntimeSource,
      speed: _onDeviceRuntimeSpeed,
      phaseKey: _onDeviceRuntimePhaseKey,
      onDownload: () => _downloadRuntime(config, l10n),
      onPause: () => _runtimeDownloadController?.pause(),
      onCancel: () => _runtimeDownloadController?.cancel(),
      onDelete: _onDeviceRuntimeReady ? () => _deleteRuntime(l10n) : null,
    );
  }

  Widget _buildModelResourceStatus(LocalizationProvider l10n, ThemeData theme) {
    final engine = _settings.onDeviceEngine;
    final modelConfig = _modelConfigForEngine(engine, _settings.whisperModel);
    if (modelConfig == null) return const SizedBox.shrink();
    final sizeInfo = modelConfig.estimatedSizeMb != null
        ? ' (~${modelConfig.estimatedSizeMb} MB)'
        : '';
    final sizeText = _onDeviceModelSizeBytes != null
        ? ' (${UpdateService.formatSize(_onDeviceModelSizeBytes!)})'
        : '';
    return ResourceStatusBlock(
      icon: Icons.folder_special_outlined,
      title: l10n.get('on_device_model'),
      ready: _onDeviceModelReady,
      readyText: '${l10n.get('model_ready')}$sizeText',
      missingText: l10n.get('model_not_ready'),
      downloading: _onDeviceDownloading,
      progress: _onDeviceProgress,
      source: _onDeviceSource,
      speed: _onDeviceSpeed,
      phaseKey: _onDevicePhaseKey,
      onDownload: () => _downloadModel(modelConfig, l10n),
      onPause: () => _modelDownloadController?.pause(),
      onCancel: () => _modelDownloadController?.cancel(),
      onDelete: _onDeviceModelReady ? () => _deleteModel(l10n) : null,
      downloadLabelSuffix: sizeInfo,
    );
  }

  Future<void> _downloadModel(
    OnDeviceModelConfig config,
    LocalizationProvider l10n,
  ) async {
    if (!mounted) return;
    if (_onDeviceDownloading) return;
    final settings = context.read<SettingsProvider>().settings;
    final controller = ResourceDownloadController();
    _modelDownloadController = controller;
    setState(() {
      _onDeviceDownloading = true;
      _onDeviceProgress = 0.0;
      _onDeviceSource = '';
      _onDevicePhaseKey = 'resource_status_downloading';
      _onDeviceSpeed = 0;
      _onDeviceError = null;
    });

    try {
      final downloadSourceMode = await RouteStateStore(
        StorageService(),
      ).loadDownloadSourceMode();
      if (!mounted) return;
      await ModelDownloader.downloadModel(
        config: config,
        mirrorBaseUrl: settings.customGithubMirror,
        downloadSourceMode: downloadSourceMode,
        controller: controller,
        onDetailedProgress: (progress) {
          if (mounted) {
            setState(() {
              _onDeviceProgress = progress.fraction ?? _onDeviceProgress;
              _onDeviceSource = progress.sourceLabel;
              _onDeviceSpeed = progress.bytesPerSecond;
              _onDevicePhaseKey = progress.extracting
                  ? 'resource_status_extracting'
                  : 'resource_status_downloading';
            });
          }
        },
      );
      if (mounted) {
        setState(() => _onDevicePhaseKey = 'resource_status_verifying');
      }
      await _checkOnDeviceStatus();
      unawaited(
        AppLog.info(
          'Downloaded on-device model ${config.id}',
          source: 'on_device_stt',
        ),
      );
    } on ResourceDownloadStopped catch (e) {
      if (mounted) {
        setState(() {
          _onDeviceError = e.reason == DownloadStopReason.paused
              ? l10n.get('download_paused')
              : null;
        });
      }
    } catch (e) {
      unawaited(
        AppLog.error(
          'Failed to download on-device model ${config.id}',
          source: 'on_device_stt',
          error: e,
        ),
      );
      if (mounted) {
        setState(() {
          _onDeviceError = '$e';
          _onDeviceDownloading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _onDeviceDownloading = false;
          _onDevicePhaseKey = '';
        });
      }
      if (_modelDownloadController == controller) {
        _modelDownloadController = null;
      }
    }
  }

  Future<void> _downloadMissingOnDeviceResources(
    LocalizationProvider l10n,
  ) async {
    final runtimeConfig = KnownRuntimes.current();
    final modelConfig = _modelConfigForEngine(
      _settings.onDeviceEngine,
      _settings.whisperModel,
    );
    if (runtimeConfig == null || modelConfig == null) return;
    final tasks = <Future<void>>[];
    if (!_onDeviceRuntimeReady && !_onDeviceRuntimeDownloading) {
      tasks.add(_downloadRuntime(runtimeConfig, l10n));
    }
    if (!_onDeviceModelReady && !_onDeviceDownloading) {
      tasks.add(_downloadModel(modelConfig, l10n));
    }
    if (tasks.isEmpty) return;
    await Future.wait(tasks);
  }

  Future<void> _downloadRuntime(
    OnDeviceRuntimeConfig config,
    LocalizationProvider l10n,
  ) async {
    if (!mounted) return;
    if (_onDeviceRuntimeDownloading) return;
    final settings = context.read<SettingsProvider>().settings;
    final controller = ResourceDownloadController();
    _runtimeDownloadController = controller;
    setState(() {
      _onDeviceRuntimeDownloading = true;
      _onDeviceRuntimeProgress = 0.0;
      _onDeviceRuntimeSource = '';
      _onDeviceRuntimePhaseKey = 'resource_status_downloading';
      _onDeviceRuntimeSpeed = 0;
      _onDeviceError = null;
    });

    try {
      final downloadSourceMode = await RouteStateStore(
        StorageService(),
      ).loadDownloadSourceMode();
      if (!mounted) return;
      await ModelDownloader.downloadRuntime(
        config: config,
        mirrorBaseUrl: settings.customGithubMirror,
        downloadSourceMode: downloadSourceMode,
        controller: controller,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _onDeviceRuntimeProgress =
                  progress.fraction ?? _onDeviceRuntimeProgress;
              _onDeviceRuntimeSource = progress.sourceLabel;
              _onDeviceRuntimeSpeed = progress.bytesPerSecond;
              _onDeviceRuntimePhaseKey = progress.extracting
                  ? 'resource_status_extracting'
                  : 'resource_status_downloading';
            });
          }
        },
      );
      if (mounted) {
        setState(() => _onDeviceRuntimePhaseKey = 'resource_status_verifying');
      }
      await _checkOnDeviceStatus();
      unawaited(
        AppLog.info(
          'Downloaded on-device runtime ${config.id}',
          source: 'on_device_stt',
        ),
      );
    } on ResourceDownloadStopped catch (e) {
      if (mounted) {
        setState(() {
          _onDeviceError = e.reason == DownloadStopReason.paused
              ? l10n.get('download_paused')
              : null;
        });
      }
    } catch (e) {
      unawaited(
        AppLog.error(
          'Failed to download on-device runtime ${config.id}',
          source: 'on_device_stt',
          error: e,
        ),
      );
      if (mounted) {
        setState(() {
          _onDeviceError = '$e';
          _onDeviceRuntimeDownloading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _onDeviceRuntimeDownloading = false;
          _onDeviceRuntimePhaseKey = '';
        });
      }
      if (_runtimeDownloadController == controller) {
        _runtimeDownloadController = null;
      }
    }
  }

  Future<void> _deleteModel(LocalizationProvider l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('confirm_delete_model_title')),
        content: Text(l10n.get('confirm_delete_model_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final engine = _settings.onDeviceEngine;
    final modelConfig = _modelConfigForEngine(engine, _settings.whisperModel);
    if (modelConfig != null) {
      await ModelDownloader.deleteModel(modelConfig.id);
    }
    await _checkOnDeviceStatus();
  }

  Future<void> _deleteRuntime(LocalizationProvider l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('confirm_delete_runtime_title')),
        content: Text(l10n.get('confirm_delete_runtime_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final runtimeConfig = KnownRuntimes.current();
    if (runtimeConfig != null) {
      await ModelDownloader.deleteRuntime(runtimeConfig.id);
    }
    await _checkOnDeviceStatus();
  }

  String _engineLabel(BuildContext context, String engine) {
    final l10n = context.read<LocalizationProvider>();
    return switch (engine) {
      'sense_voice' => l10n.get('on_device_engine_sense_voice'),
      'whisper' => l10n.get('on_device_engine_whisper'),
      'paraformer' => l10n.get('on_device_engine_paraformer'),
      _ => engine,
    };
  }

  String _engineHint(BuildContext context, String engine) {
    final l10n = context.read<LocalizationProvider>();
    return switch (engine) {
      'sense_voice' => l10n.get('on_device_engine_sense_voice_hint'),
      'whisper' => l10n.get('on_device_engine_whisper_hint'),
      'paraformer' => l10n.get('on_device_engine_paraformer_hint'),
      _ => '',
    };
  }

  String _whisperModelLabel(LocalizationProvider l10n, String size) {
    return switch (size) {
      'tiny' => l10n.get('whisper_model_tiny'),
      'base' => l10n.get('whisper_model_base'),
      'small' => l10n.get('whisper_model_small'),
      'medium' => l10n.get('whisper_model_medium'),
      _ => size,
    };
  }

  String _whisperModelHint(LocalizationProvider l10n, String size) {
    return switch (size) {
      'tiny' => l10n.get('whisper_model_tiny_hint'),
      'base' => l10n.get('whisper_model_base_hint'),
      'small' => l10n.get('whisper_model_small_hint'),
      'medium' => l10n.get('whisper_model_medium_hint'),
      _ => '',
    };
  }

  OnDeviceModelConfig? _modelConfigForEngine(
    String engine,
    String whisperSize,
  ) {
    return KnownModels.forEngine(engine, whisperSize: whisperSize);
  }
}

class ResourceStatusBlock extends StatelessWidget {
  const ResourceStatusBlock({
    required this.icon,
    required this.title,
    required this.ready,
    required this.readyText,
    required this.missingText,
    required this.downloading,
    required this.progress,
    required this.source,
    required this.speed,
    required this.phaseKey,
    required this.onDownload,
    required this.onPause,
    required this.onCancel,
    this.onDelete,
    this.downloadLabelSuffix = '',
  });

  final IconData icon;
  final String title;
  final bool ready;
  final String readyText;
  final String missingText;
  final bool downloading;
  final double progress;
  final String source;
  final double speed;
  final String phaseKey;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final String downloadLabelSuffix;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final theme = Theme.of(context);
    final statusColor = ready ? Colors.green : theme.colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  ready ? Icons.check_circle : Icons.error_outline,
                  size: 17,
                  color: statusColor,
                ),
                const SizedBox(width: 4),
                Text(
                  ready ? readyText : missingText,
                  style: TextStyle(fontSize: 12, color: statusColor),
                ),
              ],
            ),
            if (downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress > 0 ? progress : null),
              const SizedBox(height: 6),
              if (phaseKey.isNotEmpty) ...[
                Text(
                  l10n.get(phaseKey),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                _downloadDetailText(l10n),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause, size: 16),
                    label: Text(l10n.get('pause_download')),
                  ),
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(l10n.get('cancel')),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!ready)
                    FilledButton.tonalIcon(
                      onPressed: onDownload,
                      icon: const Icon(Icons.download, size: 16),
                      label: Text(
                        '${l10n.get('model_download')}$downloadLabelSuffix',
                      ),
                    ),
                  if (onDelete != null)
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(l10n.get('delete')),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _downloadDetailText(LocalizationProvider l10n) {
    final percent = '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
    final speedText = speed > 0
        ? '${UpdateService.formatSize(speed.round())}/s'
        : '--';
    final sourceText = source.isNotEmpty ? source : '--';
    return l10n.getp('download_progress_source_speed', {
      'percent': percent,
      'source': sourceText,
      'speed': speedText,
    });
  }
}

class SttModeCard extends StatelessWidget {
  const SttModeCard({
    required this.label,
    required this.icon,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? accent
                : Theme.of(context).dividerColor.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
          color: selected ? accent.withValues(alpha: 0.06) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: selected ? accent : null),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: selected ? accent : null,
                  ),
                ),
                if (selected) ...[
                  const Spacer(),
                  Icon(Icons.check_circle, size: 16, color: accent),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
