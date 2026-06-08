import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mianshi_zhilian/generated/release_notes.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/app_permission_service.dart';
import 'package:mianshi_zhilian/services/app_version_service.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

class AboutUpdatePage extends StatelessWidget {
  const AboutUpdatePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return ProfileSubPage(
      title: l10n.get('about_update'),
      children: const [AboutPanel()],
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

class AboutPanel extends StatefulWidget {
  const AboutPanel();

  @override
  State<AboutPanel> createState() => AboutPanelState();
}

class AboutPanelState extends State<AboutPanel> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  bool _isChecking = false;
  String? _updateMessage;
  StateSetter? _currentSetDialogState;
  AppBuildInfo _currentVersion = AppBuildInfo.compileTime;
  DownloadSourceMode _downloadSourceMode = DownloadSourceMode.auto;

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
      final currentVersion = await const AppVersionService().load();
      if (!mounted) return;
      setState(() {
        _currentVersion = currentVersion;
      });
      final updateService = _updateService;
      final result = await updateService.checkForUpdate(currentVersion);

      if (!mounted) return;
      setState(() {
        _isChecking = false;
        final localFullVersion =
            result.localVersion?.fullVersion ?? currentVersion.fullVersion;
        final remoteFullVersion = result.remoteFullVersion ?? '--';
        if (result.hasUpdate) {
          _updateMessage = l10n.getp('update_available_with_versions', {
            'local': localFullVersion,
            'remote': remoteFullVersion,
          });
        } else if (result.isError) {
          _updateMessage = l10n.get('inspect_check_update_fail');
        } else {
          _updateMessage = l10n.getp('already_latest_with_versions', {
            'local': localFullVersion,
            'remote': remoteFullVersion,
          });
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
        const Divider(height: 32),
        Text(
          l10n.get('about_about'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        LinkTile(
          icon: Icons.language,
          title: l10n.get('about_homepage'),
          subtitle: l10n.get('about_homepage_desc'),
          url: 'https://mianshizhilian.nontracey.de5.net',
        ),
        LinkTile(
          icon: Icons.code,
          title: l10n.get('about_github'),
          subtitle: l10n.get('about_github_desc'),
          url: 'https://github.com/nontracey/mianshi-zhilian-app',
        ),
        LinkTile(
          icon: Icons.favorite_outline,
          title: l10n.get('about_sponsor'),
          subtitle: l10n.get('about_sponsor_desc'),
          url:
              'https://github.com/nontracey/mianshi-zhilian-app/blob/main/docs/sponsor.md',
        ),
        LinkTile(
          icon: Icons.replay_outlined,
          title: l10n.get('re_view_onboarding'),
          subtitle: '',
          onTap: () async {
            await context.read<SettingsProvider>().resetOnboarding();
            if (context.mounted) {
              context.go('/');
            }
          },
        ),
      ],
    );
  }

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
