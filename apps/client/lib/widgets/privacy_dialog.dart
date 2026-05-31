import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class PrivacyConfirmDialog extends StatelessWidget {
  const PrivacyConfirmDialog({
    super.key,
    required this.dataType,
    required this.dataDescription,
    required this.onConfirm,
    this.onCancel,
  });

  final String dataType;
  final String dataDescription;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  static Future<bool> show({
    required BuildContext context,
    required String dataType,
    required String dataDescription,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => PrivacyConfirmDialog(
        dataType: dataType,
        dataDescription: dataDescription,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.privacy_tip_outlined,
              color: AppColors.warning,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.get('data_upload_confirmation'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 数据类型说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${l10n.get('about_to_upload')}$dataType',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 数据内容预览
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.get('data_content_prefix'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dataDescription,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 隐私说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 16, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      l10n.get('privacy_protection'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildPrivacyItem(l10n.get('data_4ec5_53d1_9001_5230_60a8_config_7684_ai_670d_52a1')),
                _buildPrivacyItem(l10n.get('not_4f1a_5b58_50a8_5230_6211_4eec_7684_670d_52a1_5668')),
                _buildPrivacyItem(l10n.get('60a8_53ef_4ee5_968f_65f6_5728_settings_4e2d_64a4_9500_author')),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel ?? () => Navigator.pop(context, false),
          child: Text(l10n.get('cancel')),
        ),
        FilledButton.icon(
          onPressed: onConfirm,
          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
          label: Text(l10n.get('confirm_upload')),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 12, color: AppColors.success)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// 隐私控制服务
class PrivacyService {
  static bool _hasConfirmed = false;
  static String? _confirmedDataType;

  static bool get hasConfirmed => _hasConfirmed;

  static Future<bool> confirmUpload({
    required BuildContext context,
    required String dataType,
    required String dataDescription,
  }) async {
    // 如果已经确认过相同类型的数据，直接返回
    if (_hasConfirmed && _confirmedDataType == dataType) {
      return true;
    }

    final confirmed = await PrivacyConfirmDialog.show(
      context: context,
      dataType: dataType,
      dataDescription: dataDescription,
    );

    if (confirmed) {
      _hasConfirmed = true;
      _confirmedDataType = dataType;
    }

    return confirmed;
  }

  static void reset() {
    _hasConfirmed = false;
    _confirmedDataType = null;
  }
}

// 隐私设置页面
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  bool _confirmBeforeUpload = true;
  bool _saveAnswerLocally = true;
  bool _saveImageLocally = true;
  bool _saveVoiceLocally = true;
  bool _saveProjectLocally = true;
  bool _saveJdLocally = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('privacy_settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 隐私说明
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 20, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      l10n.get('privacy_protection_commitment'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.get('60a8_7684_data_security_is_6211_4eec_7684_9996_8981_task_624'),
                  style: TextStyle(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.get('privacy_description_list'),
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 上传确认设置
          _buildSectionHeader(l10n.get('upload_confirmation'), Icons.cloud_upload_outlined, isDark),
          const SizedBox(height: 12),
          _buildSwitchTile(
            title: l10n.get('confirm_before_upload'),
            subtitle: l10n.get('always_show_upload_confirmation'),
            value: _confirmBeforeUpload,
            onChanged: (v) => setState(() => _confirmBeforeUpload = v),
            isDark: isDark,
          ),
          const SizedBox(height: 20),

          // 本地保存设置
          _buildSectionHeader(l10n.get('save_locally'), Icons.save_outlined, isDark),
          const SizedBox(height: 12),
          _buildSwitchTile(
            title: l10n.get('answer_draft'),
            subtitle: l10n.get('save_answer_drafts_locally'),
            value: _saveAnswerLocally,
            onChanged: (v) => setState(() => _saveAnswerLocally = v),
            isDark: isDark,
          ),
          _buildSwitchTile(
            title: l10n.get('image_attachment'),
            subtitle: l10n.get('save_uploaded_images_locally'),
            value: _saveImageLocally,
            onChanged: (v) => setState(() => _saveImageLocally = v),
            isDark: isDark,
          ),
          _buildSwitchTile(
            title: l10n.get('voice_recording'),
            subtitle: l10n.get('save_voice_recordings_locally'),
            value: _saveVoiceLocally,
            onChanged: (v) => setState(() => _saveVoiceLocally = v),
            isDark: isDark,
          ),
          _buildSwitchTile(
            title: l10n.get('project_info'),
            subtitle: l10n.get('save_project_dig_info_locally'),
            value: _saveProjectLocally,
            onChanged: (v) => setState(() => _saveProjectLocally = v),
            isDark: isDark,
          ),
          _buildSwitchTile(
            title: l10n.get('job_description'),
            subtitle: l10n.get('save_jd_locally'),
            value: _saveJdLocally,
            onChanged: (v) => setState(() => _saveJdLocally = v),
            isDark: isDark,
          ),
          const SizedBox(height: 20),

          // 数据管理
          _buildSectionHeader(l10n.get('data_management'), Icons.storage_outlined, isDark),
          const SizedBox(height: 12),
          _buildActionButton(
            title: l10n.get('export_local_data'),
            subtitle: l10n.get('export_all_as_json'),
            icon: Icons.file_download_outlined,
            onTap: () => _exportData(context, l10n),
            isDark: isDark,
          ),
          _buildActionButton(
            title: l10n.get('clear_local_data'),
            subtitle: l10n.get('delete_all_local_practice_data'),
            icon: Icons.delete_outline,
            iconColor: Colors.red,
            onTap: () => _showClearDataDialog(context, l10n),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15202E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
        ),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : const Color(0xFF666666),
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.accent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildActionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15202E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? AppColors.accent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : const Color(0xFF666666),
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Future<void> _exportData(BuildContext context, LocalizationProvider l10n) async {
    try {
      final storage = StorageService();
      final data = await storage.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      // 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: jsonStr));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.get('data_copied_to_clipboard')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('export_failed')}: $e')),
        );
      }
    }
  }

  void _showClearDataDialog(BuildContext context, LocalizationProvider l10n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('confirm_clear')),
        content: Text(l10n.get('confirm_clear_all_data')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final storage = StorageService();
                await storage.clearAllData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.get('data_cleared'))),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${l10n.get('clear_failed')}: $e')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.get('clear')),
          ),
        ],
      ),
    );
  }
}
