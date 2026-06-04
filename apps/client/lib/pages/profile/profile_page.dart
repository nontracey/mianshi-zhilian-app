import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/models/user.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/app_version_service.dart';
import 'package:mianshi_zhilian/generated/release_notes.dart';
import 'package:mianshi_zhilian/services/app_permission_service.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
import 'package:mianshi_zhilian/services/on_device_stt_service.dart';
import 'package:mianshi_zhilian/utils/platform_file_reader.dart';
import 'package:mianshi_zhilian/l10n/l10n.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/auth/login_page.dart';
import 'package:mianshi_zhilian/pages/profile/ai_config_page.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/voice_diagnostic_sheet.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;
    final authProvider = context.watch<AuthProvider>();
    final progressProvider = context.watch<ProgressProvider>();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _AccountPanel(
          authProvider: authProvider,
          profile: progressProvider.localProfile,
          syncSettings: progressProvider.syncSettings,
          attemptsCount: progressProvider.attempts.length,
          streakDays: progressProvider.practiceStreakDays,
          onProfileChanged: progressProvider.updateLocalProfile,
          onLogin: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
          },
          onLogout: () => authProvider.logout(),
        ),
        const SizedBox(height: 16),
        _ProfileSectionGrid(
          items: [
            _ProfileSectionItem(
              icon: Icons.cloud_sync_outlined,
              title: l10n.get('sync_and_backup'),
              subtitle: l10n.getp('profile_sync_summary', {
                'method': _syncMethodLabel(
                  progressProvider.syncSettings.method,
                  l10n,
                ),
              }),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _SyncBackupPage()),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.smart_toy_outlined,
              title: l10n.get('ai_and_voice'),
              subtitle: l10n.get('ai_and_voice_desc'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiVoiceSettingsPage()),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.tune_outlined,
              title: l10n.get('learning_preferences'),
              subtitle: l10n.get('learning_preferences_desc'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _LearningPreferencesPage(),
                ),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.palette_outlined,
              title: l10n.get('appearance_language'),
              subtitle: l10n.getp('appearance_language_desc', {
                'language': settings.language.toUpperCase(),
              }),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _AppearanceLanguagePage(),
                ),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.source_outlined,
              title: l10n.get('content_source'),
              subtitle: l10n.get(settings.contentEnv.labelKey),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _ContentSourcePage()),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.route_outlined,
              title: '线路诊断',
              subtitle: '自动 / pages.dev / de5.net',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _RoutePreferencePage()),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.info_outline,
              title: l10n.get('about_update'),
              subtitle: l10n.get('about_update_desc'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _AboutUpdatePage()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _syncMethodLabel(String method, LocalizationProvider l10n) =>
      switch (method) {
        'file' => l10n.get('file_import_export'),
        'webdav' => 'WebDAV',
        'github' => 'GitHub',
        'gitee' => 'Gitee',
        'cloud' => l10n.get('account_cloud_sync'),
        _ => l10n.get('local_mode'),
      };
}

class _RoutePreferencePage extends StatelessWidget {
  const _RoutePreferencePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('route_diagnosis'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [_RoutePreferencePanel()],
      ),
    );
  }
}

class _RoutePreferencePanel extends StatefulWidget {
  const _RoutePreferencePanel();

  @override
  State<_RoutePreferencePanel> createState() => _RoutePreferencePanelState();
}

class _RoutePreferencePanelState extends State<_RoutePreferencePanel> {
  late final RouteStateStore _store;
  RouteMode _appApiMode = RouteMode.auto;
  RouteMode _contentMode = RouteMode.auto;
  DownloadSourceMode _downloadSourceMode = DownloadSourceMode.githubFirst;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = RouteStateStore(StorageService());
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _store.loadMode(RouteService.appApi),
      _store.loadMode(RouteService.content),
      _store.loadDownloadSourceMode(),
    ]);
    if (!mounted) return;
    setState(() {
      _appApiMode = results[0] as RouteMode;
      _contentMode = results[1] as RouteMode;
      _downloadSourceMode = results[2] as DownloadSourceMode;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('route_official_preference'),
      icon: Icons.route_outlined,
      children: [
        _buildSelector(
          label: 'App API',
          value: _appApiMode,
          onChanged: (mode) async {
            await _store.saveMode(RouteService.appApi, mode);
            setState(() => _appApiMode = mode);
          },
        ),
        const SizedBox(height: 16),
        _buildSelector(
          label: l10n.get('route_content_cdn'),
          value: _contentMode,
          onChanged: (mode) async {
            await _store.saveMode(RouteService.content, mode);
            setState(() => _contentMode = mode);
          },
        ),
        const SizedBox(height: 16),
        _buildDownloadSourceSelector(),
        const SizedBox(height: 12),
        Text(
          l10n.get('route_setting_local_only'),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadSourceSelector() {
    final l10n = context.watch<LocalizationProvider>();
    return DropdownButtonFormField<DownloadSourceMode>(
      initialValue: _downloadSourceMode,
      decoration: InputDecoration(
        labelText: l10n.get('download_source_mode'),
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(
          value: DownloadSourceMode.githubFirst,
          child: Text(l10n.get('download_github_first')),
        ),
        DropdownMenuItem(
          value: DownloadSourceMode.mirrorFirst,
          child: Text(l10n.get('download_mirror_first')),
        ),
        DropdownMenuItem(
          value: DownloadSourceMode.githubOnly,
          child: Text(l10n.get('download_github_only')),
        ),
      ],
      onChanged: (mode) {
        if (mode != null) {
          _store.saveDownloadSourceMode(mode);
          setState(() => _downloadSourceMode = mode);
        }
      },
    );
  }

  Widget _buildSelector({
    required String label,
    required RouteMode value,
    required ValueChanged<RouteMode> onChanged,
  }) {
    final l10n = context.watch<LocalizationProvider>();
    return DropdownButtonFormField<RouteMode>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(
          value: RouteMode.auto,
          child: Text(l10n.get('route_auto')),
        ),
        DropdownMenuItem(
          value: RouteMode.backupFirst,
          child: Text(l10n.get('route_backup_first')),
        ),
        DropdownMenuItem(
          value: RouteMode.primaryFirst,
          child: Text(l10n.get('route_primary_first')),
        ),
        DropdownMenuItem(
          value: RouteMode.backupOnly,
          child: Text(l10n.get('route_backup_only')),
        ),
        DropdownMenuItem(
          value: RouteMode.primaryOnly,
          child: Text(l10n.get('route_primary_only')),
        ),
      ],
      onChanged: (mode) {
        if (mode != null) onChanged(mode);
      },
    );
  }
}

class _ProfileSectionItem {
  const _ProfileSectionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ProfileSectionGrid extends StatelessWidget {
  const _ProfileSectionGrid({required this.items});

  final List<_ProfileSectionItem> items;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 2 : 1,
        mainAxisExtent: 104,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) => _ProfileSectionCard(item: items[index]),
    );
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({required this.item});

  final _ProfileSectionItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Icon(item.icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSubPage extends StatelessWidget {
  const _ProfileSubPage({required this.title, required this.children});

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

class _ContentSourcePage extends StatelessWidget {
  const _ContentSourcePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final authProvider = context.watch<AuthProvider>();
    return _ProfileSubPage(
      title: l10n.get('content_source'),
      children: [
        _ContentEnvPanel(
          settings: settingsProvider.settings,
          userRole: authProvider.userRole,
          onEnvChanged: (env) async {
            await settingsProvider.setContentEnv(env);
            if (!context.mounted) return;
            await context.read<ContentProvider>().switchContentEnv(
              settingsProvider.settings.contentBaseUrl,
            );
          },
          onTestUrlChanged: settingsProvider.setCustomTestContentUrl,
          onProdUrlChanged: settingsProvider.setCustomProdContentUrl,
          onApplyChanged: () async {
            final contentProvider = context.read<ContentProvider>();
            await contentProvider.clearAllDomainCache();
            await contentProvider.switchContentEnv(
              settingsProvider.settings.contentBaseUrl,
              currentDomainId: settingsProvider.settings.currentDomain,
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  l10n.get(
                    'cache_already_clear_correct_at_restart_new_loading_current_domai',
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class AiVoiceSettingsPage extends StatelessWidget {
  const AiVoiceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    return _ProfileSubPage(
      title: l10n.get('ai_and_voice'),
      children: [
        _AiConfigPanel(
          onNavigateToConfig: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AiConfigPage())),
        ),
        const SizedBox(height: 16),
        _SttConfigPanel(
          settings: settingsProvider.settings,
          onSettingsChanged: settingsProvider.updateSettings,
        ),
      ],
    );
  }
}

class _LearningPreferencesPage extends StatelessWidget {
  const _LearningPreferencesPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    return _ProfileSubPage(
      title: l10n.get('learning_preferences'),
      children: [
        _LearningSettingsPanel(
          settings: settingsProvider.settings,
          onSettingsChanged: settingsProvider.updateSettings,
        ),
      ],
    );
  }
}

class _AppearanceLanguagePage extends StatelessWidget {
  const _AppearanceLanguagePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;
    return _ProfileSubPage(
      title: l10n.get('appearance_language'),
      children: [
        _AppearancePanel(
          settings: settings,
          onThemeTypeChanged: settingsProvider.setThemeType,
          onPrimaryColorChanged: settingsProvider.updatePrimaryColor,
          onAccentColorChanged: settingsProvider.updateAccentColor,
          onFontScaleChanged: settingsProvider.updateFontScale,
          onDensityChanged: settingsProvider.updateDensity,
        ),
        const SizedBox(height: 16),
        _LanguagePanel(
          settings: settings,
          onLanguageChanged: (lang) {
            settingsProvider.updateLanguage(lang);
            context.read<LocalizationProvider>().setLanguage(lang);
          },
        ),
      ],
    );
  }
}

class _SyncBackupPage extends StatelessWidget {
  const _SyncBackupPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    return _ProfileSubPage(
      title: l10n.get('sync_and_backup'),
      children: [
        _DataManagementPanel(
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
    final aiProvider = context.read<AiProvider>();
    final message = await settingsProvider.syncData(
      progressProvider.syncSettings,
    );
    await progressProvider.loadProgress();
    await settingsProvider.loadSettings();
    await aiProvider.loadConfigs();
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
    final result = await context.read<SettingsProvider>().testWebDavConnection(
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
    final result = await settingsProvider.restoreFromWebDav(
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

class _AboutUpdatePage extends StatelessWidget {
  const _AboutUpdatePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return _ProfileSubPage(
      title: l10n.get('about_update'),
      children: const [_AboutPanel()],
    );
  }
}

// ── 账号面板 ──────────────────────────────────────────────

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.authProvider,
    required this.profile,
    required this.syncSettings,
    required this.attemptsCount,
    required this.streakDays,
    required this.onProfileChanged,
    required this.onLogin,
    required this.onLogout,
  });

  final AuthProvider authProvider;
  final LocalProfile profile;
  final SyncSettings syncSettings;
  final int attemptsCount;
  final int streakDays;
  final ValueChanged<LocalProfile> onProfileChanged;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WorkPanel(
      title: l10n.get('accounting_account_management'),
      icon: Icons.person_outline,
      children: [
        Row(
          children: [
            // 头像
            _buildAvatar(context, isDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authProvider.isLoggedIn
                        ? _displayName
                        : l10n.get(_displayName),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    authProvider.isLoggedIn
                        ? '@${authProvider.user!.username}'
                        : l10n.get('local_guest_mode_data_save_at_machine'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (authProvider.isLoggedIn)
              FilledButton.tonalIcon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout, size: 18),
                label: Text(l10n.get('logout')),
              )
            else
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login, size: 18),
                label: Text(l10n.get('login')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MiniStat(
              label: l10n.get('practice_record'),
              value: '$attemptsCount',
            ),
            _MiniStat(
              label: l10n.get('streak_day_count'),
              value: '$streakDays',
            ),
            _MiniStat(
              label: l10n.get('sync_method_mode'),
              value: _syncLabel(syncSettings.method, l10n),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showEditProfileDialog(context),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: Text(l10n.get('modify_resource_material')),
            ),
            _BindingButton(
              icon: Icons.mail_outline,
              label: profile.emailBound
                  ? l10n.get('email_already_bind')
                  : l10n.get('bind_email'),
              status: profile.emailBound
                  ? l10n.get('already_bind')
                  : l10n.get('pending_open'),
              onTap: () => _showUnavailable(context, l10n.get('email_bind')),
            ),
            _BindingButton(
              icon: Icons.wechat,
              label: profile.wechatBound
                  ? l10n.get('wechat_already_bind')
                  : l10n.get('bind_wechat'),
              status: profile.wechatBound
                  ? l10n.get('already_bind')
                  : l10n.get('pending_open'),
              onTap: () => _showUnavailable(context, l10n.get('wechat_bind')),
            ),
            _BindingButton(
              icon: Icons.link_outlined,
              label: l10n.get('bind_its_other_account'),
              status: l10n.get('pending_open'),
              onTap: () => _showUnavailable(
                context,
                l10n.get('three_method_account_bind'),
              ),
            ),
          ],
        ),
        if (!authProvider.isLoggedIn) ...[
          const SizedBox(height: 12),
          Text(
            l10n.get('login_offline_description'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// 显示名优先级：localProfile.nickname（本地，可被 sync 流程回填）
  /// > authProvider.user.nickname（服务端，仅在本地未设置时兜底）
  /// > authProvider.user.username
  /// 不再用 user.nickname 直接覆盖本地（之前是 bug：本地改完昵称不生效）
  String get _displayName {
    if (profile.nickname.isNotEmpty) return profile.nickname;
    if (authProvider.isLoggedIn) {
      final u = authProvider.user;
      if (u != null) {
        if (u.nickname.isNotEmpty) return u.nickname;
        return u.username;
      }
    }
    return '本地用户';
  }

  // 种子头像调色板
  static const List<Color> _seedColors = [
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF673AB7),
    Color(0xFF3F51B5),
    Color(0xFF2196F3),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFFF5722),
    Color(0xFF795548),
    Color(0xFF607D8B),
    Color(0xFFE67E22),
    Color(0xFF2ECC71),
    Color(0xFF3498DB),
    Color(0xFF9B59B6),
    Color(0xFF1ABC9C),
  ];

  Color _seedColor(String seed) {
    final hash = seed.hashCode.abs();
    return _seedColors[hash % _seedColors.length];
  }

  Widget _buildAvatar(BuildContext context, bool isDark) {
    final hasAvatarUrl =
        profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty;
    final hasSeed = profile.avatarSeed.isNotEmpty;
    final seedColor = _seedColor(profile.avatarSeed);
    final diceBearUrl = hasSeed && !hasAvatarUrl
        ? 'https://api.dicebear.com/9.x/fun-emoji/png?seed=${Uri.encodeComponent(profile.avatarSeed)}&backgroundColor=transparent'
        : null;
    final showInitials = !hasAvatarUrl && !hasSeed;

    return GestureDetector(
      onTap: () => _showAvatarPicker(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: showInitials
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : diceBearUrl != null
                ? seedColor.withValues(alpha: 0.15)
                : null,
            backgroundImage: hasAvatarUrl
                ? NetworkImage(profile.avatarUrl!)
                : diceBearUrl != null
                ? NetworkImage(diceBearUrl)
                : null,
            child: showInitials
                ? Builder(
                    builder: (context) {
                      final l10n = context.watch<LocalizationProvider>();
                      final name = authProvider.isLoggedIn
                          ? _displayName
                          : l10n.get(_displayName);
                      return Text(
                        name.isNotEmpty
                            ? name[0].toUpperCase()
                            : l10n.get('local'),
                        style: TextStyle(
                          color: seedColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAvatarPicker(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.get('update_switch_avatar'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 拍照（移动端支持）
                if (!kIsWeb)
                  _buildAvatarOption(
                    context,
                    icon: Icons.camera_alt,
                    label: l10n.get('photo'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _pickImageFromCamera(context);
                    },
                  ),
                // 相册选择
                _buildAvatarOption(
                  context,
                  icon: Icons.photo_library,
                  label: l10n.get('mutual_book'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickImageFromGallery(context);
                  },
                ),
                // URL 输入
                _buildAvatarOption(
                  context,
                  icon: Icons.link,
                  label: 'URL',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAvatarUrlDialog(context);
                  },
                ),
                // 随机生成
                _buildAvatarOption(
                  context,
                  icon: Icons.shuffle,
                  label: l10n.get('random_machine'),
                  onTap: () {
                    Navigator.pop(ctx);
                    final newSeed = DateTime.now().millisecondsSinceEpoch
                        .toString();
                    onProfileChanged(
                      profile.copyWith(avatarSeed: newSeed, avatarUrl: null),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  onProfileChanged(profile.copyWith(avatarUrl: null));
                },
                child: Text(
                  l10n.get('restore_default_avatar'),
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageFromCamera(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    try {
      final granted = await AppPermissionService.ensureCamera(context);
      if (!granted || !context.mounted) return;

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (image != null) {
        // 在移动端，直接使用文件路径
        onProfileChanged(profile.copyWith(avatarUrl: image.path));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.getp('photo_fail_error_2', {'error': e})),
          ),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    try {
      final granted = await AppPermissionService.ensurePhotos(context);
      if (!granted || !context.mounted) return;

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (image != null) {
        if (kIsWeb) {
          // Web 端需要读取为 base64 或 data URL
          final bytes = await image.readAsBytes();
          final base64 = Uri.dataFromBytes(
            bytes,
            mimeType: 'image/jpeg',
          ).toString();
          onProfileChanged(profile.copyWith(avatarUrl: base64));
        } else {
          // 移动端直接使用文件路径
          onProfileChanged(profile.copyWith(avatarUrl: image.path));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.getp('select_image_picture_fail_error_2', {'error': e}),
            ),
          ),
        );
      }
    }
  }

  Widget _buildAvatarOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _showAvatarUrlDialog(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('input_avatar_url')),
        content: TextField(
          controller: urlController,
          decoration: InputDecoration(
            hintText: 'https://example.com/avatar.jpg',
            labelText: l10n.get('avatar_link'),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                onProfileChanged(profile.copyWith(avatarUrl: url));
              }
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('confirm_fixed')),
          ),
        ],
      ),
    );
  }

  String _syncLabel(String method, LocalizationProvider l10n) =>
      switch (method) {
        'webdav' => 'WebDAV',
        'github' => 'GitHub',
        'gitee' => 'Gitee',
        'cloud' => l10n.get('cloud_sync'),
        'file' => l10n.get('file'),
        _ => l10n.get('local'),
      };

  void _showUnavailable(BuildContext context, String name) {
    final l10n = context.watch<LocalizationProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.getp(
            'name_feature_pending_open_optional_first_use_local_data_2',
            {'name': name},
          ),
        ),
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final nicknameController = TextEditingController(
      text: l10n.get(profile.nickname),
    );
    final emailController = TextEditingController(text: profile.email);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.get('edit_personal_resource_material'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),

            // 头像预览
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    backgroundImage:
                        profile.avatarUrl != null &&
                            profile.avatarUrl!.isNotEmpty
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child:
                        profile.avatarUrl == null || profile.avatarUrl!.isEmpty
                        ? Text(
                            nicknameController.text.isNotEmpty
                                ? nicknameController.text[0].toUpperCase()
                                : l10n.get('use'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAvatarPicker(context);
                    },
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: Text(l10n.get('update_switch_avatar')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 昵称输入
            TextField(
              controller: nicknameController,
              decoration: InputDecoration(
                labelText: l10n.get('nickname'),
                hintText: l10n.get('input_your_nickname'),
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 邮箱输入
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: l10n.get('email_expand_show_use'),
                hintText: 'your@email.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),

            // 提示
            Text(
              l10n.get(
                'email_only_use_in_expand_show_not_shadow_response_data_sync',
              ),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),

            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final newNick = nicknameController.text.trim().isEmpty
                      ? l10n.get('local_user')
                      : nicknameController.text.trim() == l10n.get('local_user')
                      ? l10n.get('local_user')
                      : nicknameController.text.trim();
                  final newEmail = emailController.text.trim();

                  // 本地优先：写 localProfile（localStorage）→ UI 立即刷新
                  // 不打任何云端 API；后台 sync 流程（webdav/github/gitee）会按
                  // local 覆盖 remote 的策略把变更推上去。
                  onProfileChanged(
                    LocalProfile(
                      nickname: newNick,
                      email: newEmail,
                      avatarSeed: profile.avatarSeed,
                      avatarUrl: profile.avatarUrl,
                      emailBound: profile.emailBound,
                      wechatBound: profile.wechatBound,
                    ),
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.get('resource_material_already_update'),
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(l10n.get('save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

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

class _BindingButton extends StatelessWidget {
  const _BindingButton({
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

// ── 知识源配置面板 ──────────────────────────────────────────────

class _ContentEnvPanel extends StatelessWidget {
  const _ContentEnvPanel({
    required this.settings,
    required this.userRole,
    required this.onEnvChanged,
    required this.onTestUrlChanged,
    required this.onProdUrlChanged,
    required this.onApplyChanged,
  });

  final AppSettings settings;
  final UserRole userRole;
  final ValueChanged<ContentEnv> onEnvChanged;
  final ValueChanged<String?> onTestUrlChanged;
  final ValueChanged<String?> onProdUrlChanged;
  final VoidCallback onApplyChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final testController = TextEditingController(
      text: settings.customTestContentUrl ?? '',
    );
    final prodController = TextEditingController(
      text: settings.customProdContentUrl ?? '',
    );

    return WorkPanel(
      title: l10n.get('knowledge_source_config'),
      icon: Icons.cloud_outlined,
      trailing: FilledButton.tonalIcon(
        onPressed: onApplyChanged,
        icon: const Icon(Icons.refresh),
        label: Text(l10n.get('application_and_restart_load')),
      ),
      children: [
        // 环境切换
        SegmentedButton<ContentEnv>(
          segments: [
            ButtonSegment(
              value: ContentEnv.production,
              label: Text(l10n.get('publish_version')),
            ),
            ButtonSegment(
              value: ContentEnv.test,
              label: Text(l10n.get('test_version')),
              enabled: userRole.allowedContentEnvs.contains('test'),
            ),
            ButtonSegment(
              value: ContentEnv.draft,
              label: Text(l10n.get('draft_version')),
              enabled: userRole.allowedContentEnvs.contains('draft'),
            ),
          ],
          selected: {settings.contentEnv},
          onSelectionChanged: (value) => onEnvChanged(value.first),
        ),
        const SizedBox(height: 16),

        // 当前生效地址
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                settings.contentEnv == ContentEnv.test
                    ? Icons.science_outlined
                    : Icons.verified_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.getp('current_url_2', {
                    'url': _contentRouteLabel(settings, l10n),
                  }),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 测试版自定义 URL
        Text(
          l10n.get('test_version_address_retain_empty_use_default'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.getp('default_url_content_test_2', {
            'url':
                '${AppSettings.defaultWorkerApiUrl}/content/test / ${RouteResolver.appApiBackup}/content/test',
          }),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: testController,
          decoration: InputDecoration(
            hintText: l10n.get('custom_test_version_url'),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => onTestUrlChanged(value.isEmpty ? null : value),
        ),
        const SizedBox(height: 16),

        // 发布版自定义 URL
        Text(
          l10n.get('publish_version_address_retain_empty_use_default'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.getp('default_url', {
            'url':
                '${AppSettings.defaultProdContentUrl} / ${RouteResolver.contentBackup}',
          }),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: prodController,
          decoration: InputDecoration(
            hintText: l10n.get('custom_publish_version_url'),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => onProdUrlChanged(value.isEmpty ? null : value),
        ),
      ],
    );
  }

  String _contentRouteLabel(AppSettings settings, LocalizationProvider l10n) {
    if (settings.contentEnv == ContentEnv.production &&
        settings.customProdContentUrl?.isNotEmpty == true) {
      return '${settings.customProdContentUrl} (${l10n.get('custom_content_source_no_official_fallback')})';
    }
    if (settings.contentEnv != ContentEnv.production &&
        settings.customTestContentUrl?.isNotEmpty == true) {
      return '${settings.customTestContentUrl} (${l10n.get('custom_content_source_no_official_fallback')})';
    }
    if (settings.contentEnv == ContentEnv.production) {
      return '${RouteResolver.contentPrimary} / ${RouteResolver.contentBackup}';
    }
    final stage = settings.contentEnv == ContentEnv.draft ? 'draft' : 'test';
    return '${RouteResolver.appApiPrimary}/content/$stage / ${RouteResolver.appApiBackup}/content/$stage';
  }
}

// ── AI 配置面板 ──────────────────────────────────────────────

class _AiConfigPanel extends StatelessWidget {
  const _AiConfigPanel({required this.onNavigateToConfig});

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

// ── 语音识别配置面板 ──────────────────────────────────────────────

class _SttConfigPanel extends StatelessWidget {
  const _SttConfigPanel({
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final aiProvider = context.watch<AiProvider>();
    final mode = settings.sttMode;
    final audioConfigs = aiProvider.enabledConfigs
        .where((config) => config.audioMode != AiAudioMode.none)
        .toList(growable: false);
    final isSystem = mode == 'system';
    final isWhisperKit = mode == 'whisper_kit';

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
              _SttModeCard(
                label: l10n.get('stt_mode_auto'),
                icon: Icons.auto_awesome,
                description: l10n.get('stt_mode_auto_desc'),
                selected: mode == 'auto',
                onTap: () =>
                    onSettingsChanged(settings.copyWith(sttMode: 'auto')),
              ),
              _SttModeCard(
                label: l10n.get('stt_mode_follow_current_ai'),
                icon: Icons.smart_toy_outlined,
                description: l10n.get('stt_mode_follow_current_ai_desc'),
                selected: mode == 'follow_current_ai',
                onTap: () => onSettingsChanged(
                  settings.copyWith(sttMode: 'follow_current_ai'),
                ),
              ),
              _SttModeCard(
                label: l10n.get('stt_mode_fixed_ai'),
                icon: Icons.record_voice_over_outlined,
                description: l10n.get('stt_mode_fixed_ai_desc'),
                selected: mode == 'fixed_ai_config',
                onTap: () => onSettingsChanged(
                  settings.copyWith(sttMode: 'fixed_ai_config'),
                ),
              ),
              _SttModeCard(
                label: l10n.get('system_speech_voice'),
                icon: Icons.phone_android,
                description: l10n.get('system_speech_voice_desc'),
                selected: isSystem,
                onTap: () =>
                    onSettingsChanged(settings.copyWith(sttMode: 'system')),
              ),
              if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb)
                _SttModeCard(
                  label: l10n.get('whisper_kit_mode_label'),
                  icon: Icons.memory,
                  description: l10n.get('whisper_kit_mode_desc'),
                  selected: isWhisperKit,
                  onTap: () => onSettingsChanged(
                    settings.copyWith(sttMode: 'whisper_kit'),
                  ),
                ),
            ],
          ),
        ),
        if (mode == 'fixed_ai_config') ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue:
                  audioConfigs.any((c) => c.id == settings.sttAiConfigId)
                  ? settings.sttAiConfigId
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
                  onSettingsChanged(settings.copyWith(sttAiConfigId: id)),
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
        if (isWhisperKit) ...[
          const SizedBox(height: 12),
          _WhisperKitModelManager(),
        ],
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
}

// ── 本机 Whisper 模型管理 ──────────────────────────────────────────

class _WhisperKitModelManager extends StatefulWidget {
  @override
  State<_WhisperKitModelManager> createState() =>
      _WhisperKitModelManagerState();
}

class _WhisperKitModelManagerState extends State<_WhisperKitModelManager> {
  final OnDeviceSttService _svc = OnDeviceSttService();
  bool _modelReady = false;
  bool _modelOnDisk = false; // 模型文件是否存在于磁盘
  bool _downloading = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    // 先检查文件系统，再检查内存状态
    final onDisk = await _svc.isModelFilePresent();
    if (mounted) {
      setState(() {
        _modelOnDisk = onDisk;
        _modelReady = _svc.isModelReady;
        _downloading = _svc.isModelDownloading;
        _statusText = _svc.modelStatus;
        // 如果文件存在但内存未加载，显示为"已下载（未加载）"
        if (onDisk && !_modelReady && !_downloading) {
          _statusText = 'ready'; // 文件已存在，标记为 ready
        }
      });
    }
  }

  Future<void> _download() async {
    final l10n = context.read<LocalizationProvider>();
    setState(() {
      _downloading = true;
      _statusText = '...';
    });

    try {
      await _svc.initModel(
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _statusText = '${(received / total * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _modelReady = true;
          _downloading = false;
          _statusText = l10n.get('whisper_kit_model_downloaded');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _statusText = l10n.get('whisper_kit_download_failed');
        });
        // 非 Android 平台大概率是平台不支持，给出降级引导
        if (defaultTargetPlatform != TargetPlatform.android) {
          _showWhisperKitUnavailableDialog(l10n);
        }
      }
    }
  }

  Future<void> _showWhisperKitUnavailableDialog(
    LocalizationProvider l10n,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('voice_not_available')),
        content: Text(l10n.get('whisper_kit_unsupported_platform')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final l10n = context.read<LocalizationProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('whisper_kit_delete_confirm_title')),
        content: Text(l10n.get('whisper_kit_delete_confirm_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _svc.deleteModel();
      _checkStatus();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final theme = Theme.of(context);
    final isAvailable = _modelReady || _modelOnDisk;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isAvailable ? Icons.check_circle : Icons.download_outlined,
              color: isAvailable ? Colors.green : theme.colorScheme.secondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.get('whisper_kit_model_status'),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAvailable
                        ? l10n.get('whisper_kit_model_downloaded')
                        : _downloading
                        ? _statusText
                        : l10n.get('whisper_kit_model_not_downloaded'),
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    l10n.get('whisper_kit_model_size'),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_downloading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!isAvailable)
              TextButton(
                onPressed: _download,
                child: Text(l10n.get('whisper_kit_download_model')),
              )
            else
              TextButton(
                onPressed: _delete,
                child: Text(
                  l10n.get('whisper_kit_delete_model'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SttModeCard extends StatelessWidget {
  const _SttModeCard({
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

// ── 外观面板 ──────────────────────────────────────────────

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({
    required this.settings,
    required this.onThemeTypeChanged,
    required this.onPrimaryColorChanged,
    required this.onAccentColorChanged,
    required this.onFontScaleChanged,
    required this.onDensityChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppThemeType> onThemeTypeChanged;
  final ValueChanged<Color> onPrimaryColorChanged;
  final ValueChanged<Color> onAccentColorChanged;
  final ValueChanged<double> onFontScaleChanged;
  final ValueChanged<String> onDensityChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final themeType = settings.themeType;
    final primaryColor = settings.primaryColor;
    final accentColor = settings.accentColor;
    final fontScale = settings.fontScale;
    final density = settings.cardDensity;

    return WorkPanel(
      title: l10n.get('appearance_and_theme'),
      icon: Icons.palette_outlined,
      children: [
        // 主题选择
        Text(
          l10n.get('theme_wind_style'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppThemeType.values.map((type) {
            final isSelected = themeType == type;
            return ChoiceChip(
              label: Text(l10n.get(type.labelKey)),
              selected: isSelected,
              onSelected: (_) => onThemeTypeChanged(type),
              avatar: _getThemeIcon(type),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('main_color_select'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            _ColorButton(
              color: const Color(0xFF1A2B4A),
              selected: primaryColor == const Color(0xFF1A2B4A),
              onTap: () => onPrimaryColorChanged(const Color(0xFF1A2B4A)),
            ),
            _ColorButton(
              color: const Color(0xFF0A2540),
              selected: primaryColor == const Color(0xFF0A2540),
              onTap: () => onPrimaryColorChanged(const Color(0xFF0A2540)),
            ),
            _ColorButton(
              color: const Color(0xFF12372A),
              selected: primaryColor == const Color(0xFF12372A),
              onTap: () => onPrimaryColorChanged(const Color(0xFF12372A)),
            ),
            _ColorButton(
              color: const Color(0xFF111827),
              selected: primaryColor == const Color(0xFF111827),
              onTap: () => onPrimaryColorChanged(const Color(0xFF111827)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('accent_schedule_color_select'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            _ColorButton(
              color: const Color(0xFF3078F0),
              selected: accentColor == const Color(0xFF3078F0),
              onTap: () => onAccentColorChanged(const Color(0xFF3078F0)),
            ),
            _ColorButton(
              color: const Color(0xFF00CCF9),
              selected: accentColor == const Color(0xFF00CCF9),
              onTap: () => onAccentColorChanged(const Color(0xFF00CCF9)),
            ),
            _ColorButton(
              color: const Color(0xFF10B981),
              selected: accentColor == const Color(0xFF10B981),
              onTap: () => onAccentColorChanged(const Color(0xFF10B981)),
            ),
            _ColorButton(
              color: const Color(0xFFF59E0B),
              selected: accentColor == const Color(0xFFF59E0B),
              onTap: () => onAccentColorChanged(const Color(0xFFF59E0B)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              l10n.get('font_size'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text('${(fontScale * 100).toInt()}%'),
          ],
        ),
        Slider(
          value: fontScale,
          min: 0.8,
          max: 1.4,
          divisions: 6,
          onChanged: onFontScaleChanged,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: density,
          decoration: InputDecoration(
            labelText: l10n.get('card_density'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'comfortable',
              child: Text(l10n.get('comfortable')),
            ),
            DropdownMenuItem(
              value: 'compact',
              child: Text(l10n.get('compact')),
            ),
          ],
          onChanged: (value) {
            if (value != null) onDensityChanged(value);
          },
        ),
      ],
    );
  }

  Widget? _getThemeIcon(AppThemeType type) {
    switch (type) {
      case AppThemeType.system:
        return const Icon(Icons.brightness_auto, size: 16);
      case AppThemeType.elegantWhite:
        return const Icon(Icons.light_mode, size: 16);
      case AppThemeType.qualityBlack:
        return const Icon(Icons.dark_mode, size: 16);
      case AppThemeType.midnightBlue:
        return const Icon(Icons.nights_stay, size: 16);
    }
  }
}

class _LearningSettingsPanel extends StatelessWidget {
  const _LearningSettingsPanel({
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('study_settings'),
      icon: Icons.school_outlined,
      children: [
        DropdownButtonFormField<String>(
          initialValue: settings.recommendStrategy,
          decoration: InputDecoration(
            labelText: l10n.get('recommend_strategy'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'smart',
              child: Text(l10n.get('intelligence_enable_recommend')),
            ),
            DropdownMenuItem(
              value: 'low-score-first',
              child: Text(l10n.get('low_score_priority')),
            ),
            DropdownMenuItem(
              value: 'path-order',
              child: Text(l10n.get('road_path_smooth_sequence')),
            ),
            DropdownMenuItem(
              value: 'high-frequency',
              child: Text(l10n.get('high_freq_priority')),
            ),
            DropdownMenuItem(
              value: 'review-first',
              child: Text(l10n.get('review_priority')),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              onSettingsChanged(settings.copyWith(recommendStrategy: value));
            }
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _NumberSetting(
                label: l10n.get('daily_new_learn'),
                value: settings.dailyNewCount,
                onChanged: (value) =>
                    onSettingsChanged(settings.copyWith(dailyNewCount: value)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberSetting(
                label: l10n.get('daily_review'),
                value: settings.dailyReviewCount,
                onChanged: (value) => onSettingsChanged(
                  settings.copyWith(dailyReviewCount: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: settings.prioritizePrerequisites,
          title: Text(l10n.get('priority_supplement_prerequisite_knowledge')),
          onChanged: (value) => onSettingsChanged(
            settings.copyWith(prioritizePrerequisites: value),
          ),
        ),
        SwitchListTile(
          value: settings.allowSkipLowFrequency,
          title: Text(l10n.get('allow_skip_pass_low_freq_knowledge')),
          onChanged: (value) => onSettingsChanged(
            settings.copyWith(allowSkipLowFrequency: value),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: settings.mockInterviewPreference,
          decoration: InputDecoration(
            labelText: l10n.get('mode_mock_interview_group_volume_bias_good'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'mixed',
              child: Text(l10n.get('mix_combine')),
            ),
            DropdownMenuItem(
              value: 'foundation',
              child: Text(l10n.get('basic_knowledge')),
            ),
            DropdownMenuItem(
              value: 'systemDesign',
              child: Text(l10n.get('system_design')),
            ),
            DropdownMenuItem(
              value: 'code',
              child: Text(l10n.get('code_question_count')),
            ),
            DropdownMenuItem(
              value: 'project',
              child: Text(l10n.get('project_deep_dig')),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              onSettingsChanged(
                settings.copyWith(mockInterviewPreference: value),
              );
            }
          },
        ),
      ],
    );
  }
}

class _NumberSetting extends StatelessWidget {
  const _NumberSetting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: Row(
        children: [
          IconButton(
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _LanguagePanel extends StatelessWidget {
  const _LanguagePanel({
    required this.settings,
    required this.onLanguageChanged,
  });

  final AppSettings settings;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('language_settings'),
      icon: Icons.translate,
      children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'zh', label: Text(l10n.get('chinese'))),
            ButtonSegment(value: 'en', label: Text(l10n.get('english'))),
          ],
          selected: {settings.language},
          onSelectionChanged: (value) => onLanguageChanged(value.first),
        ),
      ],
    );
  }
}

class _DataManagementPanel extends StatelessWidget {
  const _DataManagementPanel({
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
              value: 'cloud',
              enabled: false,
              child: Text(l10n.get('account_cloud_sync_unavailable')),
            ),
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onTestConnection,
              icon: const Icon(Icons.wifi_find, size: 16),
              label: Text(l10n.get('test_connect')),
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
              syncSettings.copyWith(syncAiConfigMetadata: value ?? true),
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
        'cloud' => l10n.get('account_cloud_sync'),
        'baidu' => l10n.get('hundred_degree_web_disk'),
        'quark' => l10n.get('quark_web_disk'),
        'aliyun' => l10n.get('ali_cloud_disk'),
        'onedrive' => 'OneDrive',
        _ => l10n.get('local_mode'),
      };
}

class _AboutPanel extends StatefulWidget {
  const _AboutPanel();

  @override
  State<_AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends State<_AboutPanel> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  bool _isChecking = false;
  String? _updateMessage;
  StateSetter? _currentSetDialogState;
  AppBuildInfo _currentVersion = AppBuildInfo.compileTime;
  DownloadSourceMode _downloadSourceMode = DownloadSourceMode.githubFirst;

  /// 统一获取 UpdateService 实例（避免重复创建导致设置不一致）
  UpdateService get _updateService {
    final settings = context.read<SettingsProvider>().settings;
    return UpdateService(
      customMirrorPrefix: settings.customGithubMirror,
      downloadSourceMode: _downloadSourceMode,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadSettings();
  }

  Future<void> _loadVersion() async {
    final version = await const AppVersionService().load();
    if (mounted) {
      setState(() {
        _currentVersion = version;
      });
    }
  }

  Future<void> _loadSettings() async {
    final store = RouteStateStore(StorageService());
    final mode = await store.loadDownloadSourceMode();
    if (mounted) {
      setState(() => _downloadSourceMode = mode);
    }
  }

  void _showCurrentVersionNotes() {
    final l10n = context.read<LocalizationProvider>();
    final notes = ReleaseNotes.notes;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.getp('publish_current_new_version_v_version_2', {
            'version': _currentVersion.displayVersion,
          }),
        ),
        content: notes.isNotEmpty
            ? SingleChildScrollView(child: Text(notes))
            : Text(l10n.get('no_release_notes')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('known_channel')),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdate() async {
    final l10n = context.read<LocalizationProvider>();
    setState(() {
      _isChecking = true;
      _updateMessage = null;
    });

    try {
      final updateService = _updateService;
      final result = await updateService.checkForUpdate(_currentVersion);

      if (!mounted) return;
      setState(() {
        _isChecking = false;
        if (result.hasUpdate) {
          _updateMessage = l10n.getp(
            'publish_current_new_version_v_version_2',
            {'version': result.updateInfo!.version},
          );
        } else if (result.isError) {
          _updateMessage = l10n.get('inspect_check_update_fail');
        } else {
          _updateMessage = l10n.get('already_is_most_new_version');
        }
      });
      if (result.hasUpdate) {
        _showUpdateDialog(result.updateInfo!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _updateMessage = l10n.get('inspect_check_update_fail');
        });
      }
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    final l10n = context.read<LocalizationProvider>();
    final updateService = _updateService;
    final isRequiredUpdate = updateService.isRequiredUpdate(
      updateInfo,
      _currentVersion,
    );
    final platformUpdate = updateService.getPlatformUpdate(updateInfo);
    final size =
        platformUpdate?.size ??
        (updateInfo.platforms.isEmpty
            ? 0
            : updateInfo.platforms.values.first.size);
    showDialog(
      context: context,
      barrierDismissible: !isRequiredUpdate,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.getp('publish_current_new_version_v_version_2', {
            'version': updateInfo.version,
          }),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.getp('publish_day_date_2', {'date': updateInfo.releaseDate}),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.get('update_content'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            ...updateInfo.notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $note'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.getp('flat_platform_size_2', {
                'size': UpdateService.formatSize(size),
              }),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (!isRequiredUpdate)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('slightly_after_again_explain')),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadUpdate(updateInfo);
            },
            child: Text(l10n.get('establish_instant_update')),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadUpdate(UpdateInfo updateInfo) async {
    final l10n = context.read<LocalizationProvider>();
    final updateService = _updateService;

    // Web 端提示刷新
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.get(
              'web_client_please_refresh_new_page_gain_fetch_most_version',
            ),
          ),
        ),
      );
      return;
    }

    final platformUpdate = updateService.getPlatformUpdate(updateInfo);

    if (platformUpdate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.get('current_flat_platform_temporary_no_update_pack'),
          ),
        ),
      );
      return;
    }

    // 显示下载进度
    int received = 0;
    int total = platformUpdate.size;
    String currentSource = '';
    bool dialogOpen = true;
    final cancelToken = DownloadCancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // 保存 setDialogState 供 onProgress 回调使用
          _currentSetDialogState = setDialogState;
          return AlertDialog(
            title: Text(l10n.get('download_update')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  value: total > 0 ? received / total : null,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.getp('downloading_v_version_2', {
                    'version': updateInfo.version,
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  '${UpdateService.formatSize(received)} / ${UpdateService.formatSize(total)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 4),
                if (total > 0)
                  Text(
                    '${(received / total * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (currentSource.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.getp('downloading_from_source_2', {
                      'source': currentSource,
                    }),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelToken.cancel();
                  dialogOpen = false;
                  Navigator.pop(ctx);
                },
                child: Text(l10n.get('cancel')),
              ),
            ],
          );
        },
      ),
    );

    try {
      // 实际下载和校验
      final (filePath, downloadResult) = await updateService.downloadUpdate(
        platformUpdate: platformUpdate,
        version: updateInfo.version,
        cancelToken: cancelToken,
        onProgress: (r, t, source) {
          received = r;
          total = t;
          currentSource = source;
          if (mounted) {
            _currentSetDialogState?.call(() {});
          }
        },
      );

      if (!mounted) return;

      if (cancelToken.isCancelled) return;

      if (filePath != null) {
        final canInstall = await AppPermissionService.ensureInstallPackages(
          context,
        );
        if (!canInstall || !mounted) return;
        await updateService.openInstaller(filePath);
        if (!mounted) return;
        _showInstallGuide(filePath, updateInfo.version);
      } else {
        // 根据下载失败原因显示不同提示，附带尝试过的源详情
        final attempts = updateService.lastAttempts;
        final String errorMessage;
        switch (downloadResult) {
          case DownloadResult.networkError:
            errorMessage = _buildDownloadErrorMsg(
              l10n,
              'download_fail_network_error_please_check_network_and_retry',
              attempts,
            );
          case DownloadResult.verificationFailed:
            errorMessage = _buildDownloadErrorMsg(
              l10n,
              'download_fail_or_school_verify_not_open_pass_please_retry',
              attempts,
            );
          case DownloadResult.cancelled:
            return;
          case DownloadResult.success:
            errorMessage = '';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        final attempts = updateService.lastAttempts;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _buildDownloadErrorMsg(
                l10n,
                'download_fail_network_error_please_check_network_and_retry',
                attempts,
              ),
            ),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      _currentSetDialogState = null;
      if (mounted && dialogOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      }
    }
  }

  void _showInstallGuide(String filePath, String version) {
    final l10n = context.watch<LocalizationProvider>();
    final ext = filePath.split('.').last.toLowerCase();
    String instruction;
    IconData icon;
    switch (ext) {
      case 'apk':
        icon = Icons.android;
        instruction =
            l10n.get(
              'download_complete_please_at_notification_bar_or_file_mana',
            ) +
            l10n.get(
              'if_hint_un_known_come_source_please_at_settings_in_allow_8bb',
            );
        break;
      case 'dmg':
        icon = Icons.apple;
        instruction = l10n.get(
          'download_complete_please_type_open_dmg_file_will_application_6',
        );
        break;
      case 'exe':
        icon = Icons.desktop_windows;
        instruction = l10n.get(
          'download_complete_please_operate_action_exe_file_press_photo_direction_5bf',
        );
        break;
      default:
        icon = Icons.folder_open;
        instruction = l10n.get(
          'download_complete_please_at_file_management_device_in_find_5',
        );
        break;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, size: 40, color: AppColors.success),
        title: Text(
          l10n.getp('v_version_download_complete_2', {'version': version}),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(instruction),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filePath,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('known_channel')),
          ),
        ],
      ),
    );
  }

  /// 构建下载失败时的详细错误信息，包含每个源的尝试结果
  String _buildDownloadErrorMsg(
    LocalizationProvider l10n,
    String baseKey,
    List<DownloadAttempt> attempts,
  ) {
    final base = l10n.get(baseKey);
    if (attempts.isEmpty) return base;

    final parts = <String>[base];
    for (final a in attempts) {
      parts.add('  · ${a.sourceLabel}: ${a.failureReason}');
    }
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('about_interview_intelligence_training'),
      children: [
        InkWell(
          onTap: _showCurrentVersionNotes,
          child: InfoRow(
            icon: Icons.info_outline,
            title:
                '${l10n.get('version_prefix')} ${_currentVersion.displayVersion}',
            subtitle: l10n.get(
              'ai_main_dynamic_back_memory_study_work_platform',
            ),
          ),
        ),
        InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: l10n.get('local_priority_cloud_sync'),
          subtitle: l10n.get(
            'cloud_sync_fail_not_will_block_break_study_local_matter_condition',
          ),
        ),
        // 检查更新 + 下载设置入口
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: _isChecking ? null : _checkUpdate,
                child: InfoRow(
                  icon: Icons.system_update_alt_outlined,
                  title: l10n.get('inspect_check_update'),
                  subtitle:
                      _updateMessage ??
                      l10n.get('point_hit_inspect_check_is_or_has_new_version'),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              tooltip: l10n.get('download_settings'),
              onPressed: () => _showMirrorConfigDialog(context),
            ),
          ],
        ),
        if (_isChecking)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  /// 显示下载设置弹窗（自定义镜像站配置）
  void _showMirrorConfigDialog(BuildContext context) {
    final l10n = context.read<LocalizationProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final controller = TextEditingController(
      text: settings.customGithubMirror ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final hasCustom = controller.text.isNotEmpty;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.settings_outlined, size: 20),
                const SizedBox(width: 8),
                Text(l10n.get('download_settings')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.get('github_mirror_config_desc'),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: l10n.get('custom_mirror_prefix'),
                    hintText: 'https://ghfast.top',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: hasCustom
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              controller.clear();
                              context
                                  .read<SettingsProvider>()
                                  .setCustomGithubMirror(null);
                              setDialogState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    context.read<SettingsProvider>().setCustomGithubMirror(
                      value.isEmpty ? null : value.trim(),
                    );
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.get('mirror_download_order'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.get('known_channel')),
              ),
            ],
          );
        },
      ),
    ).then((_) => controller.dispose());
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          width: selected ? 4 : 1,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    ),
  );
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
