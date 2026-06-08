import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/services/app_log_service.dart';

class LogManagementPage extends StatefulWidget {
  const LogManagementPage({super.key});

  @override
  State<LogManagementPage> createState() => _LogManagementPageState();
}

class _LogManagementPageState extends State<LogManagementPage> {
  AppLogLevel _minimumLevel = AppLogLevel.error;

  @override
  Widget build(BuildContext context) {
    final logger = AppLogService.instance;
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('log_management')),
        actions: [
          IconButton(
            tooltip: l10n.get('copy'),
            onPressed: () => _copyLogs(logger, l10n),
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
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear_noise',
                child: Text(l10n.get('clear_regular_logs')),
              ),
              PopupMenuItem(
                value: 'clear_all',
                child: Text(l10n.get('clear_all_logs')),
              ),
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
                      l10n.getp('log_management_summary', {
                        'count': '${logs.length}',
                      }),
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
                    ? Center(child: Text(l10n.get('no_logs')))
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

  Future<void> _copyLogs(
    AppLogService logger,
    LocalizationProvider l10n,
  ) async {
    final logs = logger.filter(_minimumLevel);
    await Clipboard.setData(ClipboardData(text: logger.formatEntries(logs)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.getp('logs_copied', {'count': '${logs.length}'})),
      ),
    );
  }

  Future<void> _confirmClearAll(AppLogService logger) async {
    final l10n = context.read<LocalizationProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('clear_logs')),
        content: Text(l10n.get('clear_logs_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.get('clear')),
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
