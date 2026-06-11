import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/utils/platform_file_reader.dart';
import 'package:mianshi_zhilian/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

class SyncBackupPage extends StatelessWidget {
  const SyncBackupPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    return ProfileSubPage(
      title: l10n.get('sync_and_backup'),
      children: [
        DataManagementPanel(
          settings: settingsProvider.settings,
          syncSettings: progressProvider.syncSettings,
          onSyncSettingsChanged: progressProvider.updateSyncSettings,
          onSync: () => _syncNow(context),
          onTestConnection: () => _testConnection(context),
          onRestore: () => _restoreRemote(context),
          onExport: settingsProvider.exportData,
          onImport: () => _importFile(context),
          onClearPracticeData: () => _clearPracticeData(context),
        ),
      ],
    );
  }

  Future<void> _clearPracticeData(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('clear_practice_data')),
        content: Text(l10n.get('confirm_clear_practice_data')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.get('clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await context.read<ProgressProvider>().clearPracticeData();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.get('practice_data_cleared'))));
  }

  Future<void> _syncNow(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final message = await settingsProvider.syncData(
      progressProvider.syncSettings,
    );
    await progressProvider.loadProgress();
    if (context.mounted) {
      context.read<LocalizationProvider>().setLanguage(
        settingsProvider.settings.language,
      );
    }
    await progressProvider.updateSyncSettings(
      progressProvider.syncSettings.copyWith(
        lastSyncAt: DateTime.now(),
        lastSyncStatus: message,
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.get(message, l10n.language))));
  }

  Future<void> _testConnection(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    final result = await context.read<SettingsProvider>().testSyncConnection(
      context.read<ProgressProvider>().syncSettings,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.getp(result.l10nKey, l10n.language, result.params)),
        backgroundColor: result.success ? null : AppColors.danger,
      ),
    );
  }

  Future<void> _restoreRemote(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('from_cloud_restore')),
        content: Text(
          l10n.get(
            'restore_will_overwrite_cover_current_all_has_local_data_this_operate',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.get('confirm_restore')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final settingsProvider = context.read<SettingsProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final aiProvider = context.read<AiProvider>();
    final localizationProvider = context.read<LocalizationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await settingsProvider.restoreFromRemote(
      progressProvider.syncSettings,
    );
    await _reloadAfterImport(
      progressProvider,
      settingsProvider,
      aiProvider,
      localizationProvider,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(L10n.getp(result.l10nKey, l10n.language, result.params)),
        backgroundColor: result.success ? AppColors.success : AppColors.danger,
      ),
    );
  }

  Future<void> _importFile(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final aiProvider = context.read<AiProvider>();
    final localizationProvider = context.read<LocalizationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await readBytesFromPath(file.path!));
      if (bytes == null) {
        throw StateError('selected file has no readable bytes');
      }
      final importResult = await settingsProvider.importData(
        utf8.decode(bytes),
      );
      await _reloadAfterImport(
        progressProvider,
        settingsProvider,
        aiProvider,
        localizationProvider,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            L10n.getp(importResult.l10nKey, l10n.language, importResult.params),
          ),
          backgroundColor: importResult.success
              ? AppColors.success
              : AppColors.danger,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.getp('import_failed', {'error': '$e'})),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _reloadAfterImport(
    ProgressProvider progressProvider,
    SettingsProvider settingsProvider,
    AiProvider aiProvider,
    LocalizationProvider localizationProvider,
  ) async {
    await progressProvider.loadProgress();
    await settingsProvider.loadSettings();
    await aiProvider.loadConfigs();
    localizationProvider.setLanguage(settingsProvider.settings.language);
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

class MiniStat extends StatelessWidget {
  const MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class BindingButton extends StatelessWidget {
  const BindingButton({
    required this.icon,
    required this.label,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text('$label · $status'),
    );
  }
}

class DataManagementPanel extends StatelessWidget {
  const DataManagementPanel({
    required this.settings,
    required this.syncSettings,
    required this.onSyncSettingsChanged,
    required this.onSync,
    required this.onExport,
    required this.onImport,
    required this.onClearPracticeData,
    this.onTestConnection,
    this.onRestore,
  });

  final AppSettings settings;
  final SyncSettings syncSettings;
  final ValueChanged<SyncSettings> onSyncSettingsChanged;
  final VoidCallback onSync;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onClearPracticeData;
  final VoidCallback? onTestConnection;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('sync_and_backup'),
      children: [
        InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: l10n.getp('current_method_mode_method_2', {
            'method': _methodLabel(syncSettings.method, l10n),
          }),
          subtitle: syncSettings.lastSyncAt == null
              ? l10n.get(syncSettings.lastSyncStatus)
              : '${l10n.get(syncSettings.lastSyncStatus)} · ${syncSettings.lastSyncAt}',
        ),
        DropdownButtonFormField<String>(
          initialValue: syncSettings.method,
          decoration: InputDecoration(
            labelText: l10n.get('sync_method_mode'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'local',
              child: Text(l10n.get('local_mode')),
            ),
            DropdownMenuItem(
              value: 'file',
              child: Text(l10n.get('file_import_export')),
            ),
            DropdownMenuItem(
              value: 'webdav',
              child: Text(l10n.get('custom_webdav')),
            ),
            const DropdownMenuItem(value: 'github', child: Text('GitHub')),
            const DropdownMenuItem(value: 'gitee', child: Text('Gitee')),
            DropdownMenuItem(
              value: 'baidu',
              child: Text(l10n.get('hundred_degree_web_disk_pending_open')),
            ),
            DropdownMenuItem(
              value: 'quark',
              child: Text(l10n.get('quark_web_disk_coming_soon')),
            ),
            DropdownMenuItem(
              value: 'aliyun',
              child: Text(l10n.get('ali_cloud_disk_coming_soon')),
            ),
            DropdownMenuItem(
              value: 'onedrive',
              child: Text(l10n.get('onedrive_pending_open')),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (['baidu', 'quark', 'aliyun', 'onedrive'].contains(value)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.getp('method_feature_pending_open_2', {
                      'method': _methodLabel(value, l10n),
                    }),
                  ),
                ),
              );
            }
            onSyncSettingsChanged(
              syncSettings.copyWith(
                method: value,
                lastSyncStatus: value == 'local'
                    ? 'local_mode'
                    : 'pending_config',
              ),
            );
          },
        ),
        if (syncSettings.isAutomaticMethod) ...[
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: syncSettings.autoSyncEnabled,
            title: Text(l10n.get('auto_sync')),
            subtitle: Text(l10n.get('auto_sync_target_only')),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(autoSyncEnabled: value),
            ),
          ),
          TextFormField(
            initialValue: syncSettings.autoSyncIntervalMinutes.toString(),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.get('auto_sync_interval_minutes'),
            ),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(
                autoSyncIntervalMinutes: int.tryParse(value) ?? 5,
              ),
            ),
          ),
        ],
        if (syncSettings.method == 'webdav') ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: syncSettings.webDavUrl,
            decoration: InputDecoration(
              labelText: l10n.get('webdav_address'),
              hintText: 'https://dav.example.com/remote.php/dav/files/me',
            ),
            onChanged: (value) =>
                onSyncSettingsChanged(syncSettings.copyWith(webDavUrl: value)),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: syncSettings.webDavUsername,
            decoration: InputDecoration(labelText: l10n.get('username')),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(webDavUsername: value),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: syncSettings.webDavPassword,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.get('application_password'),
            ),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(webDavPassword: value),
            ),
          ),
        ],
        if (syncSettings.method == 'github') ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: syncSettings.githubToken,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'GitHub token'),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(githubToken: value.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: syncSettings.githubOwner,
                  decoration: InputDecoration(
                    labelText: l10n.get('repository_owner'),
                  ),
                  onChanged: (value) => onSyncSettingsChanged(
                    syncSettings.copyWith(githubOwner: value.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: syncSettings.githubRepo,
                  decoration: InputDecoration(
                    labelText: l10n.get('repository_name'),
                  ),
                  onChanged: (value) => onSyncSettingsChanged(
                    syncSettings.copyWith(githubRepo: value.trim()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: syncSettings.githubBranch,
                  decoration: InputDecoration(
                    labelText: l10n.get('repository_branch'),
                  ),
                  onChanged: (value) => onSyncSettingsChanged(
                    syncSettings.copyWith(githubBranch: value.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: syncSettings.githubPath,
                  decoration: InputDecoration(
                    labelText: l10n.get('sync_file_path'),
                  ),
                  onChanged: (value) => onSyncSettingsChanged(
                    syncSettings.copyWith(githubPath: value.trim()),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (syncSettings.method == 'gitee') ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: syncSettings.giteeToken,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Gitee access token'),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(giteeToken: value.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: syncSettings.giteeOwner,
                  decoration: InputDecoration(
                    labelText: l10n.get('repository_owner'),
                  ),
                  onChanged: (value) => onSyncSettingsChanged(
                    syncSettings.copyWith(giteeOwner: value.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: syncSettings.giteeRepo,
                  decoration: InputDecoration(
                    labelText: l10n.get('repository_name'),
                  ),
                  onChanged: (value) => onSyncSettingsChanged(
                    syncSettings.copyWith(giteeRepo: value.trim()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: syncSettings.giteeBranch,
                  decoration: InputDecoration(
                    labelText: l10n.get('repository_branch'),
                  ),
                  onChanged: (value) => onSyncSettingsChanged(
                    syncSettings.copyWith(giteeBranch: value.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: syncSettings.giteePath,
                  decoration: InputDecoration(
                    labelText: l10n.get('sync_file_path'),
                  ),
                  onChanged: (value) => onSyncSettingsChanged(
                    syncSettings.copyWith(giteePath: value.trim()),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (syncSettings.isAutomaticMethod) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onTestConnection,
              icon: const Icon(Icons.wifi_find, size: 16),
              label: Text(l10n.get('test_connect')),
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: syncSettings.syncFullPracticeText,
            title: Text(l10n.get('sync_full_practice_answers')),
            subtitle: Text(l10n.get('sync_full_practice_answers_desc')),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(syncFullPracticeText: value ?? false),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: syncSettings.syncPrivatePrepData,
            title: Text(l10n.get('sync_private_prep_data')),
            subtitle: Text(l10n.get('sync_private_prep_data_desc')),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(syncPrivatePrepData: value ?? true),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: syncSettings.syncAiConfigMetadata,
            title: Text(l10n.get('sync_ai_config_metadata')),
            subtitle: Text(l10n.get('sync_ai_config_metadata_desc')),
            onChanged: (value) => onSyncSettingsChanged(
              syncSettings.copyWith(syncAiConfigMetadata: value ?? false),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: onSync,
              icon: const Icon(Icons.cloud_upload),
              label: Text(l10n.get('backup_to_cloud')),
            ),
            if (syncSettings.isAutomaticMethod)
              FilledButton.tonalIcon(
                onPressed: onRestore,
                icon: const Icon(Icons.cloud_download),
                label: Text(l10n.get('from_cloud_restore')),
              ),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download),
              label: Text(l10n.get('data_export')),
            ),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file),
              label: Text(l10n.get('data_import')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.restart_alt_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(l10n.get('clear_practice_data')),
          subtitle: Text(l10n.get('clear_practice_data_desc')),
          trailing: TextButton(
            onPressed: onClearPracticeData,
            child: Text(l10n.get('clear')),
          ),
        ),
      ],
    );
  }

  String _methodLabel(String method, LocalizationProvider l10n) =>
      switch (method) {
        'file' => l10n.get('file_import_export'),
        'webdav' => 'WebDAV',
        'github' => 'GitHub',
        'gitee' => 'Gitee',
        'baidu' => l10n.get('hundred_degree_web_disk'),
        'quark' => l10n.get('quark_web_disk'),
        'aliyun' => l10n.get('ali_cloud_disk'),
        'onedrive' => 'OneDrive',
        _ => l10n.get('local_mode'),
      };
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

class LinkTile extends StatelessWidget {
  const LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.url,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? (url != null ? () => _launchUrl(context) : null),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _launchUrl(BuildContext context) {
    if (url == null) return;
    final uri = Uri.tryParse(url!);
    if (uri == null) return;
    // ignore: deprecated_member_use
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
