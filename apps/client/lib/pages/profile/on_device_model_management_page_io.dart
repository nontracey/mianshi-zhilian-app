import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/app_log_service.dart';
import 'package:mianshi_zhilian/services/on_device_stt/model_downloader_io.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

/// 模型管理页面——统一查看所有已下载的本机 STT 模型/运行时，
/// 查看存储路径、磁盘占用、删除模型，并清理孤立目录。
class OnDeviceModelManagementPage extends StatefulWidget {
  const OnDeviceModelManagementPage({super.key});

  @override
  State<OnDeviceModelManagementPage> createState() =>
      _OnDeviceModelManagementPageState();
}

class _OnDeviceModelManagementPageState
    extends State<OnDeviceModelManagementPage> {
  bool _loading = true;
  final List<_ModelEntry> _entries = [];
  final List<_OrphanDir> _orphanDirs = [];
  int? _totalSizeBytes;
  String? _storagePath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _collectEntries(),
        _collectOrphanDirs(),
        _calcTotalSize(),
        ModelDownloader.getStorageDir(),
      ]);
      final entries = results[0] as List<_ModelEntry>;
      final orphans = results[1] as List<_OrphanDir>;
      final totalSize = results[2] as int;
      final storageDir = results[3] as Directory;
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
        _orphanDirs
          ..clear()
          ..addAll(orphans);
        _totalSizeBytes = totalSize;
        _storagePath = storageDir.path;
        _loading = false;
      });
    } catch (e) {
      await AppLog.error(
        'Load on-device model management state failed',
        source: 'model_management',
        error: e,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _orphanDirs.clear();
          _error = '$e';
        });
      }
    }
  }

  Future<List<_ModelEntry>> _collectEntries() async {
    final entries = <_ModelEntry>[];

    // Runtime
    final runtimeConfig = KnownRuntimes.current();
    if (runtimeConfig != null) {
      final ready = await ModelDownloader.isRuntimeReady(runtimeConfig);
      final size = await ModelDownloader.getRuntimeSize(runtimeConfig.id);
      final dir = await ModelDownloader.getRuntimeDirectory(runtimeConfig.id);
      entries.add(
        _ModelEntry(
          id: runtimeConfig.id,
          name: runtimeConfig.displayName,
          type: 'runtime',
          ready: ready,
          sizeBytes: size,
          path: dir.path,
        ),
      );
    }

    // All known models
    for (final config in KnownModels.all) {
      final ready = await ModelDownloader.isModelReady(config);
      final size = await ModelDownloader.getModelSize(config.id);
      final dir = await ModelDownloader.getModelDirectory(config.id);
      entries.add(
        _ModelEntry(
          id: config.id,
          name: config.displayName,
          type: 'model',
          ready: ready,
          sizeBytes: size,
          path: dir.path,
        ),
      );
    }

    return entries;
  }

  Future<List<_OrphanDir>> _collectOrphanDirs() async {
    final root = await ModelDownloader.getStorageDir();
    if (!await root.exists()) return [];

    final knownModelIds = KnownModels.all.map((c) => c.id).toSet();

    final orphans = <_OrphanDir>[];
    final subDirs = root.list().where((e) => e is Directory);
    await for (final entity in subDirs) {
      final dir = entity as Directory;
      final name = _entityName(dir);

      // Runtime resources are managed by the runtime entry above. They are not
      // model directories, so do not report platform/runtime variants as
      // orphaned model folders.
      if (name == 'runtimes') {
        continue;
      }

      if (name == 'runtimes' || name.startsWith('.')) continue;

      final isEmpty = await _isDirectoryEmpty(dir);
      if (knownModelIds.contains(name) && !isEmpty) {
        continue;
      }
      orphans.add(_OrphanDir(path: dir.path, name: name, isEmpty: isEmpty));
    }
    return orphans;
  }

  /// 检查目录是否空（没有任何文件或子目录）。
  Future<bool> _isDirectoryEmpty(Directory dir) async {
    try {
      await for (final _ in dir.list()) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<int> _calcTotalSize() async {
    try {
      final root = await ModelDownloader.getStorageDir();
      if (!await root.exists()) return 0;
      int total = 0;
      await for (final entity in root.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _deleteEntry(_ModelEntry entry) async {
    final l10n = context.read<LocalizationProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          entry.type == 'runtime'
              ? l10n.get('confirm_delete_runtime_title')
              : l10n.get('confirm_delete_model_title'),
        ),
        content: Text(
          entry.type == 'runtime'
              ? l10n.get('confirm_delete_runtime_desc')
              : l10n.getp('confirm_delete_model_item_desc', {
                  'name': entry.name,
                }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (entry.type == 'runtime') {
        await ModelDownloader.deleteRuntime(entry.id);
      } else {
        await ModelDownloader.deleteModel(entry.id);
      }
      await AppLog.info(
        'Deleted ${entry.type}: ${entry.id}',
        source: 'model_management',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              entry.type == 'runtime'
                  ? l10n.get('runtime_deleted_success')
                  : l10n.get('model_deleted_success'),
            ),
          ),
        );
        _load();
      }
    } catch (e) {
      await AppLog.error(
        'Delete ${entry.type} failed: ${entry.id}',
        source: 'model_management',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('delete_failed_message')}: $e')),
        );
      }
    }
  }

  Future<void> _cleanOrphanDirs() async {
    final l10n = context.read<LocalizationProvider>();

    // 二次确认：非空的当前模型/runtime 目录跳过，空目录视为残留可清理。
    final validModelIds = <String>{...KnownModels.all.map((c) => c.id)};
    final validRuntimeIds = <String>{};
    final runtimeConfig = KnownRuntimes.current();
    if (runtimeConfig != null) {
      validRuntimeIds.add(runtimeConfig.id);
    }

    int cleaned = 0;
    for (final orphan in _orphanDirs) {
      final isEmpty = await _isDirectoryEmpty(Directory(orphan.path));
      if (!isEmpty &&
          !_isUnderRuntimesDir(orphan.path) &&
          validModelIds.contains(orphan.name)) {
        continue;
      }
      if (_isUnderRuntimesDir(orphan.path) &&
          validRuntimeIds.contains(orphan.name) &&
          !isEmpty) {
        continue;
      }
      try {
        await Directory(orphan.path).delete(recursive: true);
        cleaned++;
      } catch (e) {
        await AppLog.warning(
          'Clean orphan directory failed: ${orphan.name}',
          source: 'model_management',
          error: e,
        );
      }
    }
    await AppLog.info(
      'Cleaned orphan directories: $cleaned/${_orphanDirs.length}',
      source: 'model_management',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.getp('orphan_dirs_cleaned', {'count': '$cleaned'}),
          ),
        ),
      );
      _load();
    }
  }

  bool _isUnderRuntimesDir(String path) {
    return path.split(Platform.pathSeparator).contains('runtimes');
  }

  String _entityName(FileSystemEntity entity) {
    return entity.path
        .split(Platform.pathSeparator)
        .where((part) => part.isNotEmpty)
        .last;
  }

  Future<void> _downloadEntry(_ModelEntry entry) async {
    final l10n = context.read<LocalizationProvider>();
    if (!mounted) return;

    // 获取镜像配置
    final settings = context.read<SettingsProvider>().settings;
    final mirrorBaseUrl = settings.customGithubMirror;
    final downloadSourceMode = await RouteStateStore(
      StorageService(),
    ).loadDownloadSourceMode();
    if (!mounted) return;

    // 进度对话框
    final progressNotifier = ValueNotifier<double>(0);
    final sourceNotifier = ValueNotifier<String>('');
    final speedNotifier = ValueNotifier<double>(0);
    final phaseNotifier = ValueNotifier<String>('resource_status_downloading');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        entryName: entry.name,
        progressNotifier: progressNotifier,
        sourceNotifier: sourceNotifier,
        speedNotifier: speedNotifier,
        phaseNotifier: phaseNotifier,
      ),
    );

    try {
      await AppLog.info(
        'Download started: ${entry.type} ${entry.id}',
        source: 'model_management',
      );
      if (entry.type == 'runtime') {
        final runtimeConfig = KnownRuntimes.current();
        if (runtimeConfig == null) {
          await AppLog.error(
            'Runtime download failed: no runtime config for platform',
            source: 'model_management',
          );
          if (mounted) Navigator.of(context).pop();
          // 不 throw，catch 里会二次 pop
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${l10n.get('download_failed')}: '
                  'No runtime config for this platform',
                ),
              ),
            );
          }
          return;
        }
        await ModelDownloader.downloadRuntime(
          config: runtimeConfig,
          mirrorBaseUrl: mirrorBaseUrl,
          downloadSourceMode: downloadSourceMode,
          onProgress: (progress) {
            progressNotifier.value = progress.fraction ?? 0;
            sourceNotifier.value = progress.sourceLabel;
            speedNotifier.value = progress.bytesPerSecond;
            phaseNotifier.value = progress.extracting
                ? 'resource_status_extracting'
                : 'resource_status_downloading';
          },
        );
      } else {
        // entry.id → OnDeviceModelConfig
        final allConfigs = [
          KnownModels.senseVoice,
          KnownModels.whisperTiny,
          KnownModels.whisperBase,
          KnownModels.whisperSmall,
          KnownModels.whisperMedium,
          KnownModels.paraformer,
        ];
        final match = allConfigs.where((c) => c.id == entry.id);
        if (match.isEmpty) {
          await AppLog.error(
            'Model download failed: unknown model ${entry.id}',
            source: 'model_management',
          );
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${l10n.get('download_failed')}: '
                  'Unknown model "${entry.id}"',
                ),
              ),
            );
          }
          return;
        }
        final config = match.first;
        await ModelDownloader.downloadModel(
          config: config,
          mirrorBaseUrl: mirrorBaseUrl,
          downloadSourceMode: downloadSourceMode,
          onDetailedProgress: (progress) {
            progressNotifier.value = progress.fraction ?? 0;
            sourceNotifier.value = progress.sourceLabel;
            speedNotifier.value = progress.bytesPerSecond;
            phaseNotifier.value = progress.extracting
                ? 'resource_status_extracting'
                : 'resource_status_downloading';
          },
        );
      }

      phaseNotifier.value = 'resource_status_verifying';
      await AppLog.info(
        'Download completed: ${entry.type} ${entry.id}',
        source: 'model_management',
      );
      if (mounted) {
        Navigator.of(context).pop(); // 关掉进度对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('model_download_success'))),
        );
        _load();
      }
    } on ResourceDownloadStopped catch (_) {
      await AppLog.info(
        'Download paused: ${entry.type} ${entry.id}',
        source: 'model_management',
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.get('download_paused'))));
      }
    } catch (e) {
      await AppLog.error(
        'Download failed: ${entry.type} ${entry.id}',
        source: 'model_management',
        error: e,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('download_failed')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('on_device_model_management'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('$_error'))
          : _buildContent(l10n, theme),
    );
  }

  Widget _buildContent(LocalizationProvider l10n, ThemeData theme) {
    final runtimeEntries = _entries.where((e) => e.type == 'runtime').toList();
    final modelEntries = _entries.where((e) => e.type == 'model').toList();
    final hasRuntime = runtimeEntries.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── 总占用 Summary ──
        _buildSummaryCard(l10n, theme),
        const SizedBox(height: 24),

        // ── 存储路径 ──
        if (_storagePath != null) ...[
          _buildPathCard(l10n, theme),
          const SizedBox(height: 24),
        ],

        // ── 运行时 ──
        if (hasRuntime) ...[
          WorkPanel(
            title:
                '${l10n.get('model_management_others_runtime')} (${runtimeEntries.first.name})',
            icon: Icons.memory_outlined,
            children: [_buildEntryTile(runtimeEntries.first, l10n, theme)],
          ),
          const SizedBox(height: 24),
        ],

        // ── 所有模型 ──
        WorkPanel(
          title: l10n.get('model_management_all_models'),
          icon: Icons.model_training_outlined,
          children: modelEntries.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        l10n.get('no_models_downloaded'),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ]
              : modelEntries
                    .map((e) => _buildEntryTile(e, l10n, theme))
                    .toList(),
        ),
        const SizedBox(height: 24),

        // ── 孤立目录 ──
        if (_orphanDirs.isNotEmpty) ...[
          _buildOrphanSection(l10n, theme),
          const SizedBox(height: 24),
        ],

        // ── 刷新按钮 ──
        Center(
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.get('refresh')),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSummaryCard(LocalizationProvider l10n, ThemeData theme) {
    final readyCount = _entries.where((e) => e.ready).length;
    final totalCount = _entries.length;
    final sizeText = _totalSizeBytes != null
        ? UpdateService.formatSize(_totalSizeBytes!)
        : '--';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.get('total_storage_usage'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sizeText,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$readyCount / $totalCount',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: readyCount == totalCount
                        ? Colors.green
                        : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.get('model_ready_summary'),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathCard(LocalizationProvider l10n, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.get('model_storage_path'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _storagePath!,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryTile(
    _ModelEntry entry,
    LocalizationProvider l10n,
    ThemeData theme,
  ) {
    final statusColor = entry.ready ? Colors.green : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: name + status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      entry.ready
                          ? l10n.get('model_ready')
                          : l10n.get('model_not_ready'),
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Size row
              if (entry.sizeBytes != null && entry.sizeBytes! > 0) ...[
                _infoRow(
                  Icons.storage_outlined,
                  UpdateService.formatSize(entry.sizeBytes!),
                  theme,
                ),
                const SizedBox(height: 4),
              ],

              // Path row
              _infoRow(Icons.folder_outlined, entry.path, theme),
              const SizedBox(height: 8),

              // Action buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Download / Re-download button
                  TextButton.icon(
                    onPressed: () => _downloadEntry(entry),
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: Text(
                      entry.ready
                          ? l10n.get('model_redownload')
                          : l10n.get('model_download'),
                    ),
                  ),

                  // Delete button (for entries with files on disk)
                  if (entry.ready ||
                      (entry.sizeBytes != null && entry.sizeBytes! > 0))
                    TextButton.icon(
                      onPressed: () => _deleteEntry(entry),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(l10n.get('model_delete')),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontFamily: text.startsWith('/') || text.contains(':\\')
                  ? 'monospace'
                  : null,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrphanSection(LocalizationProvider l10n, ThemeData theme) {
    return WorkPanel(
      title: l10n.get('clean_orphan_dirs'),
      icon: Icons.cleaning_services_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.get('clean_orphan_dirs_desc'),
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ...(_orphanDirs.map(
          (o) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.name.isNotEmpty
                                ? o.name
                                : l10n.get('unnamed_directory'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (o.isEmpty) ...[
                            Text(
                              l10n.get('empty_directory'),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            o.path,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )),
        const SizedBox(height: 12),
        // 清理按钮（带确认弹窗）
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: () => _confirmCleanOrphanDirs(l10n),
            icon: const Icon(Icons.cleaning_services, size: 16),
            label: Text(l10n.get('clean_orphan_dirs')),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmCleanOrphanDirs(LocalizationProvider l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('clean_orphan_dirs')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.getp('orphan_dirs_clean_confirm', {
                'count': '${_orphanDirs.length}',
              }),
            ),
            const SizedBox(height: 12),
            ...(_orphanDirs
                .take(10)
                .map(
                  (o) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_off_outlined, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            o.displayName(l10n),
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
            if (_orphanDirs.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '...${l10n.getp('and_more_items', {'count': '${_orphanDirs.length - 10}'})}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _cleanOrphanDirs();
  }
}

class _ModelEntry {
  const _ModelEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.ready,
    this.sizeBytes,
    required this.path,
  });

  final String id;
  final String name;
  final String type; // 'runtime' or 'model'
  final bool ready;
  final int? sizeBytes;
  final String path;
}

class _OrphanDir {
  const _OrphanDir({
    required this.path,
    required this.name,
    required this.isEmpty,
  });

  final String path;
  final String name;
  final bool isEmpty;

  String displayName(LocalizationProvider l10n) {
    return name.isNotEmpty ? name : l10n.get('unnamed_directory');
  }
}

/// 下载进度对话框
class _DownloadProgressDialog extends StatelessWidget {
  const _DownloadProgressDialog({
    required this.entryName,
    required this.progressNotifier,
    required this.sourceNotifier,
    required this.speedNotifier,
    required this.phaseNotifier,
  });

  final String entryName;
  final ValueNotifier<double> progressNotifier;
  final ValueNotifier<String> sourceNotifier;
  final ValueNotifier<double> speedNotifier;
  final ValueNotifier<String> phaseNotifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(entryName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (_, progress, _) =>
                LinearProgressIndicator(value: progress > 0 ? progress : null),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: phaseNotifier,
            builder: (_, phaseKey, _) {
              if (phaseKey.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  context.read<LocalizationProvider>().get(phaseKey),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (_, progress, _) {
              final pct = (progress * 100).toStringAsFixed(1);
              return Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<String>(
            valueListenable: sourceNotifier,
            builder: (_, source, _) {
              if (source.isEmpty) return const SizedBox.shrink();
              return Text(
                source,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          ValueListenableBuilder<double>(
            valueListenable: speedNotifier,
            builder: (_, speed, _) {
              if (speed <= 0) return const SizedBox.shrink();
              final speedText = speed >= 1_000_000
                  ? '${(speed / 1_000_000).toStringAsFixed(1)} MB/s'
                  : '${(speed / 1_000).toStringAsFixed(0)} KB/s';
              return Text(
                speedText,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
