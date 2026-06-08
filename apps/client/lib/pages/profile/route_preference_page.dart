import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

class RoutePreferencePage extends StatelessWidget {
  const RoutePreferencePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('route_diagnosis'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [RoutePreferencePanel()],
      ),
    );
  }
}

class RoutePreferencePanel extends StatefulWidget {
  const RoutePreferencePanel();

  @override
  State<RoutePreferencePanel> createState() => RoutePreferencePanelState();
}

class RoutePreferencePanelState extends State<RoutePreferencePanel> {
  late final RouteStateStore _store;
  RouteMode _appApiMode = RouteMode.auto;
  RouteMode _contentMode = RouteMode.auto;
  DownloadSourceMode _downloadSourceMode = DownloadSourceMode.auto;
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
          value: DownloadSourceMode.auto,
          child: Text(l10n.get('download_auto_fastest')),
        ),
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
