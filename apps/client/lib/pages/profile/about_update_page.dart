import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mianshi_zhilian/generated/release_notes.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/update_download_provider.dart';
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
      // 恢复此前下载好但尚未安装的安装包（文件仍在 + 版本仍较新才显示入口）。
      if (!kIsWeb) {
        await context
            .read<UpdateDownloadProvider>()
            .restore(version, _updateService);
      }
    }
  }

  Future<void> _loadSettings() async {
    final store = EndpointStateStore(StorageService());
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

    // 安装权限在下载前确认（避免下完才发现没权限）。
    final canInstall = await AppPermissionService.ensureInstallPackages(context);
    if (!canInstall || !mounted) return;

    final download = context.read<UpdateDownloadProvider>();
    // 下载交给全局控制器：切换页面也不会中断；进度在本页内联展示。
    await download.startDownload(
      service: updateService,
      platformUpdate: platformUpdate,
      version: updateInfo.version,
      buildNumber: updateInfo.buildNumber,
    );
    if (!mounted) return;

    switch (download.lastResult) {
      case DownloadResult.success:
        // 下载完成且本页仍在前台：直接拉起安装；否则用户可从"已下载"入口安装。
        await download.install();
      case DownloadResult.networkError:
        _showDownloadError(
          l10n,
          'download_fail_network_error_please_check_network_and_retry',
          download.lastAttempts,
        );
      case DownloadResult.verificationFailed:
        _showDownloadError(
          l10n,
          'download_fail_or_school_verify_not_open_pass_please_retry',
          download.lastAttempts,
        );
      case DownloadResult.cancelled:
      case null:
        break;
    }
  }

  void _showDownloadError(
    LocalizationProvider l10n,
    String baseKey,
    List<DownloadAttempt> attempts,
  ) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_buildDownloadErrorMsg(l10n, baseKey, attempts)),
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// 进行中下载的内联进度条。
  Widget _buildDownloadingTile(
    UpdateDownloadProvider download,
    LocalizationProvider l10n,
  ) {
    final total = download.total;
    final received = download.received;
    final pct = total > 0 ? received / total : null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.getp('downloading_v_version_2', {
                    'version': download.readyVersionOrPending,
                  }),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: download.cancel,
                child: Text(l10n.get('cancel')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: pct),
          const SizedBox(height: 6),
          Text(
            '${UpdateService.formatSize(received)} / ${UpdateService.formatSize(total)}'
            '${download.source.isNotEmpty ? ' · ${download.source}' : ''}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// 已下载安装包的常驻入口：随时可再次打开安装，或删除安装包。
  Widget _buildReadyToInstallTile(
    UpdateDownloadProvider download,
    LocalizationProvider l10n,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.download_done_outlined, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.getp('installer_ready', {
                    'version': download.readyVersion ?? '',
                  }),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (download.filePath != null)
                  Text(
                    download.filePath!,
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.get('delete_installer'),
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => download.discard(),
          ),
          FilledButton(
            onPressed: () async {
              final canInstall =
                  await AppPermissionService.ensureInstallPackages(context);
              if (!canInstall) return;
              await download.install();
            },
            child: Text(l10n.get('install_now')),
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
    final download = context.watch<UpdateDownloadProvider>();
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
        // 下载进行中 / 已下载待安装的内联入口（切页不中断、随时可再次安装）。
        if (download.isDownloading) _buildDownloadingTile(download, l10n),
        if (download.readyVersion != null)
          _buildReadyToInstallTile(download, l10n),
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
