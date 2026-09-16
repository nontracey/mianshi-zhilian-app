/// 岗位搜索通道设置（§6.7、§8.3）。
///
/// 三种模式必须让用户自己选清楚：
/// - 关闭：不搜索，只用链接导入/粘贴；
/// - 本机演示：离线合成岗位，能走通流程但不是真实招聘信息；
/// - 自定义服务：用户自己的搜索服务，结果真实。
///
/// 密钥只写系统安全存储，不进 SharedPreferences，也不回显明文。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/localization_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/job_search_config.dart';
import '../../theme/colors.dart';
import 'job_search_settings_controller.dart';

class JobSearchSettingsPage extends StatefulWidget {
  const JobSearchSettingsPage({super.key});

  @override
  State<JobSearchSettingsPage> createState() => _JobSearchSettingsPageState();
}

class _JobSearchSettingsPageState extends State<JobSearchSettingsPage> {
  late final JobSearchSettingsController _c;

  @override
  void initState() {
    super.initState();
    _c = JobSearchSettingsController()
      ..loadFrom(context.read<SettingsProvider>().settings);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('coach_job_search_settings_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            l10n.get('coach_job_search_settings_subtitle'),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: isDark ? Colors.white60 : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _modeCard(l10n, isDark),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (_c.mode != JobSearchMode.custom)
                return const SizedBox.shrink();
              return _customCard(l10n, isDark);
            },
          ),
          const SizedBox(height: 14),
          _privacyCard(l10n, isDark),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => FilledButton.icon(
              onPressed: _c.saving ? null : () => _save(context),
              icon: _c.saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.get('coach_job_search_settings_save')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeCard(LocalizationProvider l10n, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Column(
          children: [
            _modeTile(
              context,
              l10n,
              JobSearchMode.off,
              'coach_job_search_mode_off',
              null,
            ),
            _modeTile(
              context,
              l10n,
              JobSearchMode.zhaopinPublic,
              'coach_job_search_mode_public',
              'coach_job_search_public_note',
            ),
            _modeTile(
              context,
              l10n,
              JobSearchMode.demo,
              'coach_job_search_mode_demo',
              'coach_job_search_mode_demo_note',
            ),
            _modeTile(
              context,
              l10n,
              JobSearchMode.custom,
              'coach_job_search_mode_custom',
              'coach_job_search_mode_custom_note',
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTile(
    BuildContext context,
    LocalizationProvider l10n,
    String mode,
    String labelKey,
    String? noteKey,
  ) {
    final selected = _c.mode == mode;
    return RadioListTile<String>(
      value: mode,
      groupValue: _c.mode,
      onChanged: (v) {
        if (v != null) _c.setMode(v);
      },
      title: Text(
        l10n.get(labelKey),
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: noteKey == null
          ? null
          : Text(
              l10n.get(noteKey),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color:
                    Colors.grey[Theme.of(context).brightness == Brightness.dark
                        ? 400
                        : 600],
              ),
            ),
      dense: true,
    );
  }

  Widget _customCard(LocalizationProvider l10n, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _c.endpoint,
              decoration: InputDecoration(
                labelText: l10n.get('coach_job_search_endpoint'),
                hintText: l10n.get('coach_job_search_endpoint_hint'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _c.apiKey,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.get('coach_job_search_api_key'),
                hintText: _c.hasStoredKey
                    ? l10n.get('coach_job_search_api_key_saved')
                    : l10n.get('coach_job_search_api_key_hint'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _c.testing ? null : () => _test(context),
                    icon: _c.testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_outlined, size: 16),
                    label: Text(l10n.get('coach_job_search_test')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _c.testResultKey == null
                          ? ''
                          : l10n.get(_c.testResultKey!),
                      style: TextStyle(
                        fontSize: 12,
                        color: _c.testOk ? AppColors.success : AppColors.danger,
                      ),
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

  Widget _privacyCard(LocalizationProvider l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.privacy_tip_outlined, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.get('coach_job_search_privacy_note'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.55,
                color: isDark ? Colors.white60 : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final l10n = context.read<LocalizationProvider>();
    final settings = context.read<SettingsProvider>();
    final config = context.read<JobSearchConfigController>();
    final ok = await _c.save(settings: settings, config: config);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.get(
            ok
                ? 'coach_job_search_settings_saved'
                : 'coach_job_search_settings_save_failed',
          ),
        ),
      ),
    );
  }

  Future<void> _test(BuildContext context) =>
      _c.testConnection(config: context.read<JobSearchConfigController>());
}
