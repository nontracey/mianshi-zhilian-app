import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mianshi_zhilian/services/app_log_service.dart';

class LogManagementPage extends StatefulWidget {
  const LogManagementPage({super.key});

  @override
  State<LogManagementPage> createState() => _LogManagementPageState();
}

class _LogManagementPageState extends State<LogManagementPage> {
  AppLogLevel _minimumLevel = AppLogLevel.debug;

  @override
  Widget build(BuildContext context) {
    final logger = AppLogService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志管理'),
        actions: [
          IconButton(
            tooltip: '复制',
            onPressed: () => _copyLogs(logger),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear_all') {
                _confirmClearAll(logger);
              } else if (value == 'clear_noise') {
                logger.clear(belowLevel: AppLogLevel.warning);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear_noise', child: Text('清理普通日志')),
              PopupMenuItem(value: 'clear_all', child: Text('清空全部日志')),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: logger,
        builder: (context, _) {
          final logs = logger.filter(_minimumLevel);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final level in AppLogLevel.values)
                          ChoiceChip(
                            label: Text(level.label),
                            selected: _minimumLevel == level,
                            onSelected: (_) {
                              setState(() => _minimumLevel = level);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '显示 ${logs.length} 条，最多保留 1000 条或 14 天。复制日志会自动脱敏常见 Key 和 Authorization。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: logs.isEmpty
                    ? const Center(child: Text('暂无日志'))
                    : ListView.separated(
                        itemCount: logs.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          return _LogTile(entry: logs[index]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyLogs(AppLogService logger) async {
    final logs = logger.filter(_minimumLevel);
    await Clipboard.setData(ClipboardData(text: logger.formatEntries(logs)));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 ${logs.length} 条日志')));
  }

  Future<void> _confirmClearAll(AppLogService logger) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定清空所有本地日志吗？这不会影响学习数据、模型或设置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await logger.clear();
    }
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      AppLogLevel.debug => Theme.of(context).colorScheme.onSurfaceVariant,
      AppLogLevel.info => Theme.of(context).colorScheme.primary,
      AppLogLevel.warning => Colors.orange,
      AppLogLevel.error => Theme.of(context).colorScheme.error,
    };
    final details = [
      if (entry.error != null && entry.error!.isNotEmpty) entry.error!,
      if (entry.stackTrace != null && entry.stackTrace!.isNotEmpty)
        entry.stackTrace!,
    ].join('\n');

    return ExpansionTile(
      leading: Icon(_iconForLevel(entry.level), color: color),
      title: Text(entry.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_formatTime(entry.timestamp)} · ${entry.level.label} · ${entry.source}',
      ),
      children: [
        if (details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SelectableText(
              details,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
      ],
    );
  }

  IconData _iconForLevel(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.debug => Icons.bug_report_outlined,
      AppLogLevel.info => Icons.info_outline,
      AppLogLevel.warning => Icons.warning_amber_outlined,
      AppLogLevel.error => Icons.error_outline,
    };
  }

  String _formatTime(DateTime time) {
    final date =
        '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return '$date $clock';
  }
}
