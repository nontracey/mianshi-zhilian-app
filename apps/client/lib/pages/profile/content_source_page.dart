import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/user.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

class ContentSourcePage extends StatelessWidget {
  const ContentSourcePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final authProvider = context.watch<AuthProvider>();
    return ProfileSubPage(
      title: l10n.get('content_source'),
      children: [
        ContentEnvPanel(
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
          onDraftUrlChanged: settingsProvider.setCustomDraftContentUrl,
          onProdUrlChanged: settingsProvider.setCustomProdContentUrl,
          onApplyChanged: () async {
            final contentProvider = context.read<ContentProvider>();
            final messenger = ScaffoldMessenger.of(context);
            // 立即反馈：点击后马上提示，避免网络拉取期间"点了没反应"。
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  l10n.get(
                    'cache_already_clear_correct_at_restart_new_loading_current_domai',
                  ),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            await contentProvider.clearAllDomainCache();
            await contentProvider.switchContentEnv(
              settingsProvider.settings.contentBaseUrl,
              currentDomainId: settingsProvider.settings.currentDomain,
            );
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: Text(l10n.get('content_reload_done')),
                duration: const Duration(seconds: 2),
              ),
            );
          },
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

class ContentEnvPanel extends StatefulWidget {
  const ContentEnvPanel({
    super.key,
    required this.settings,
    required this.userRole,
    required this.onEnvChanged,
    required this.onTestUrlChanged,
    required this.onDraftUrlChanged,
    required this.onProdUrlChanged,
    required this.onApplyChanged,
  });

  final AppSettings settings;
  final UserRole userRole;
  final ValueChanged<ContentEnv> onEnvChanged;
  final ValueChanged<String?> onTestUrlChanged;
  final ValueChanged<String?> onDraftUrlChanged;
  final ValueChanged<String?> onProdUrlChanged;
  final Future<void> Function() onApplyChanged;

  @override
  State<ContentEnvPanel> createState() => _ContentEnvPanelState();
}

class _ContentEnvPanelState extends State<ContentEnvPanel> {
  late final TextEditingController _testController;
  late final TextEditingController _draftController;
  late final TextEditingController _prodController;

  @override
  void initState() {
    super.initState();
    _testController = TextEditingController(
      text: widget.settings.customTestContentUrl ?? '',
    );
    _draftController = TextEditingController(
      text: widget.settings.customDraftContentUrl ?? '',
    );
    _prodController = TextEditingController(
      text: widget.settings.customProdContentUrl ?? '',
    );
  }

  @override
  void didUpdateWidget(ContentEnvPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当外部值与当前输入框内容不一致时才同步，避免每次输入都覆盖、光标跳动。
    _syncController(_testController, widget.settings.customTestContentUrl);
    _syncController(_draftController, widget.settings.customDraftContentUrl);
    _syncController(_prodController, widget.settings.customProdContentUrl);
  }

  void _syncController(TextEditingController controller, String? value) {
    final next = value ?? '';
    if (controller.text != next) {
      controller.text = next;
    }
  }

  @override
  void dispose() {
    _testController.dispose();
    _draftController.dispose();
    _prodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settings = widget.settings;
    final userRole = widget.userRole;

    return WorkPanel(
      title: l10n.get('knowledge_source_config'),
      icon: Icons.cloud_outlined,
      trailing: _ApplyReloadButton(
        label: l10n.get('application_and_restart_load'),
        onPressed: widget.onApplyChanged,
      ),
      children: [
        SegmentedButton<ContentEnv>(
          segments: [
            ButtonSegment(
              value: ContentEnv.production,
              label: Text(l10n.get('publish_version')),
            ),
            ButtonSegment(
              value: ContentEnv.staging,
              label: Text(l10n.get('test_version')),
              enabled: ContentEnv.staging.isAllowedBy(
                userRole.allowedContentEnvs,
              ),
            ),
            ButtonSegment(
              value: ContentEnv.draft,
              label: Text(l10n.get('draft_version')),
              enabled: userRole.allowedContentEnvs.contains('draft'),
            ),
          ],
          selected: {settings.contentEnv},
          onSelectionChanged: (value) => widget.onEnvChanged(value.first),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                settings.contentEnv == ContentEnv.staging
                    ? Icons.science_outlined
                    : settings.contentEnv == ContentEnv.draft
                    ? Icons.edit_note_outlined
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
          controller: _testController,
          decoration: InputDecoration(
            hintText: l10n.get('custom_test_version_url'),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) =>
              widget.onTestUrlChanged(value.isEmpty ? null : value),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('draft_version_address_retain_empty_use_default'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.getp('default_url_content_draft_2', {
            'url':
                '${AppSettings.defaultWorkerApiUrl}/content/draft / ${RouteResolver.appApiBackup}/content/draft',
          }),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _draftController,
          decoration: InputDecoration(
            hintText: l10n.get('custom_draft_version_url'),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) =>
              widget.onDraftUrlChanged(value.isEmpty ? null : value),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('produce_version_address_retain_empty_use_default'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _prodController,
          decoration: InputDecoration(
            hintText: l10n.get('custom_production_version_url'),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) =>
              widget.onProdUrlChanged(value.isEmpty ? null : value),
        ),
      ],
    );
  }

  String _contentRouteLabel(AppSettings settings, LocalizationProvider l10n) {
    if (settings.contentEnv == ContentEnv.staging &&
        settings.customTestContentUrl?.isNotEmpty == true) {
      return '${settings.customTestContentUrl} (${l10n.get('custom_content_source_no_official_fallback')})';
    }
    if (settings.contentEnv == ContentEnv.draft &&
        settings.customDraftContentUrl?.isNotEmpty == true) {
      return '${settings.customDraftContentUrl} (${l10n.get('custom_content_source_no_official_fallback')})';
    }
    if (settings.contentEnv == ContentEnv.production) {
      return '${RouteResolver.contentPrimary} / ${RouteResolver.contentBackup}';
    }
    final stage = settings.contentEnv.routeStage;
    return '${RouteResolver.appApiPrimary}/content/$stage / ${RouteResolver.appApiBackup}/content/$stage';
  }
}

/// 「应用并重新加载」按钮：执行期间显示 loading 并禁用，
/// 给出即时反馈，避免网络拉取耗时导致"点了没反应"。
class _ApplyReloadButton extends StatefulWidget {
  const _ApplyReloadButton({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;

  @override
  State<_ApplyReloadButton> createState() => _ApplyReloadButtonState();
}

class _ApplyReloadButtonState extends State<_ApplyReloadButton> {
  bool _loading = false;

  Future<void> _handle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _loading ? null : _handle,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
      label: Text(widget.label),
    );
  }
}
