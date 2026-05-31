import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/user.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
import 'package:mianshi_zhilian/l10n/l10n.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/auth/login_page.dart';
import 'package:mianshi_zhilian/pages/profile/ai_config_page.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

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
        _ContentEnvPanel(
          settings: settings,
          userRole: authProvider.userRole,
          onEnvChanged: (env) async {
            await settingsProvider.setContentEnv(env);
            if (context.mounted) {
              final contentProvider = context.read<ContentProvider>();
              await contentProvider.switchContentEnv(
                settingsProvider.settings.contentBaseUrl,
              );
            }
          },
          onTestUrlChanged: (url) async {
            await settingsProvider.setCustomTestContentUrl(url);
          },
          onProdUrlChanged: (url) async {
            await settingsProvider.setCustomProdContentUrl(url);
          },
          onApplyChanged: () async {
            final contentProvider = context.read<ContentProvider>();
            await contentProvider.clearAllDomainCache();
            await contentProvider.switchContentEnv(
              settingsProvider.settings.contentBaseUrl,
              currentDomainId: settingsProvider.settings.currentDomain,
            );
            if (context.mounted) {
              final l10n = context.watch<LocalizationProvider>();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.get('cache_already_clear_6b63_5728_91cd_new_loading_current_domai')),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 16),
        _AiConfigPanel(
          onNavigateToConfig: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AiConfigPage()));
          },
        ),
        const SizedBox(height: 16),
        _SttConfigPanel(
          settings: settings,
          onSettingsChanged: (next) => settingsProvider.updateSettings(next),
        ),
        const SizedBox(height: 16),
        _AppearancePanel(
          settings: settings,
          onThemeTypeChanged: (type) => settingsProvider.setThemeType(type),
          onPrimaryColorChanged: (color) =>
              settingsProvider.updatePrimaryColor(color),
          onAccentColorChanged: (color) =>
              settingsProvider.updateAccentColor(color),
          onFontScaleChanged: (scale) =>
              settingsProvider.updateFontScale(scale),
          onDensityChanged: (density) =>
              settingsProvider.updateDensity(density),
        ),
        const SizedBox(height: 16),
        _LearningSettingsPanel(
          settings: settings,
          onSettingsChanged: (next) => settingsProvider.updateSettings(next),
        ),
        const SizedBox(height: 16),
        _LanguagePanel(
          settings: settings,
          onLanguageChanged: (lang) {
            settingsProvider.updateLanguage(lang);
            context.read<LocalizationProvider>().setLanguage(lang);
          },
        ),
        const SizedBox(height: 16),
        _DataManagementPanel(
          settings: settings,
          syncSettings: progressProvider.syncSettings,
          onSyncSettingsChanged: progressProvider.updateSyncSettings,
          onSync: () async {
            final message = await settingsProvider.syncData(
              progressProvider.syncSettings,
            );
            await progressProvider.updateSyncSettings(
              SyncSettings(
                method: progressProvider.syncSettings.method,
                webDavUrl: progressProvider.syncSettings.webDavUrl,
                webDavUsername: progressProvider.syncSettings.webDavUsername,
                webDavPassword: progressProvider.syncSettings.webDavPassword,
                lastSyncAt: DateTime.now(),
                lastSyncStatus: message,
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(L10n.get(message, l10n.language))));
            }
          },
          onTestConnection: () async {
            final result = await settingsProvider.testWebDavConnection(
              progressProvider.syncSettings,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(L10n.getp(result.l10nKey, l10n.language, result.params)),
                  backgroundColor: result.success ? null : AppColors.danger,
                ),
              );
            }
          },
          onRestore: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.get('4ece_cloud_restore')),
                content: Text(
                  l10n.get('restore_5c06_8986_76d6_current_6240_has_local_data_6b64_64cd'),
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
            if (confirmed != true) return;
            final result = await settingsProvider.restoreFromWebDav(
              progressProvider.syncSettings,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(L10n.getp(result.l10nKey, l10n.language, result.params)),
                  backgroundColor: result.success ? AppColors.success : AppColors.danger,
                ),
              );
              if (result.success) {
                await context.read<ProgressProvider>().loadProgress();
                await context.read<SettingsProvider>().loadSettings();
                await context.read<AiProvider>().loadConfigs();
              }
            }
          },
          onExport: () => settingsProvider.exportData(),
        ),
        const SizedBox(height: 16),
        const _AboutPanel(),
      ],
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
      title: l10n.get('8d26_6237_management'),
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
                    authProvider.isLoggedIn ? _displayName : l10n.get(_displayName),
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
                        : l10n.get('local_6e38_5ba2_6a21_5f0f_data_save_5728_672c_673a'),
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
                label: Text(l10n.get('9000_51fa')),
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
            _MiniStat(label: l10n.get('practice_8bb0_5f55'), value: '$attemptsCount'),
            _MiniStat(label: l10n.get('streak_day_6570'), value: '$streakDays'),
            _MiniStat(label: l10n.get('sync_65b9_5f0f'), value: _syncLabel(syncSettings.method, l10n)),
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
              label: Text(l10n.get('modify_8d44_6599')),
            ),
            _BindingButton(
              icon: Icons.mail_outline,
              label: profile.emailBound ? l10n.get('email_already_bind') : l10n.get('bind_email'),
              status: profile.emailBound ? l10n.get('already_bind') : l10n.get('5f85_5f00_901a'),
              onTap: () => _showUnavailable(context, l10n.get('email_bind')),
            ),
            _BindingButton(
              icon: Icons.wechat,
              label: profile.wechatBound ? l10n.get('wechat_already_bind') : l10n.get('bind_wechat'),
              status: profile.wechatBound ? l10n.get('already_bind') : l10n.get('5f85_5f00_901a'),
              onTap: () => _showUnavailable(context, l10n.get('wechat_bind')),
            ),
            _BindingButton(
              icon: Icons.link_outlined,
              label: l10n.get('bind_5176_4ed6_account'),
              status: l10n.get('5f85_5f00_901a'),
              onTap: () => _showUnavailable(context, l10n.get('7b2c_4e09_65b9_account_bind')),
            ),
          ],
        ),
        if (!authProvider.isLoggedIn) ...[
          const SizedBox(height: 12),
          Text(
            l10n.get('text_84761062'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String get _displayName =>
      authProvider.isLoggedIn ? authProvider.user!.nickname : profile.nickname;

  Widget _buildAvatar(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: () => _showAvatarPicker(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            backgroundImage: profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
                ? NetworkImage(profile.avatarUrl!)
                : null,
            child: profile.avatarUrl == null || profile.avatarUrl!.isEmpty
                ? Builder(
                    builder: (context) {
                      final l10n = context.watch<LocalizationProvider>();
                      final name = authProvider.isLoggedIn
                          ? _displayName
                          : l10n.get(_displayName);
                      return Text(
                        name.isNotEmpty ? name[0].toUpperCase() : l10n.get('672c'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
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
              child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
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
              l10n.get('66f4_6362_avatar'),
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
                    label: l10n.get('62cd_7167'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _pickImageFromCamera(context);
                    },
                  ),
                // 相册选择
                _buildAvatarOption(
                  context,
                  icon: Icons.photo_library,
                  label: l10n.get('76f8_518c'),
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
                  label: l10n.get('968f_673a'),
                  onTap: () {
                    Navigator.pop(ctx);
                    final newSeed = DateTime.now().millisecondsSinceEpoch.toString();
                    onProfileChanged(profile.copyWith(avatarSeed: newSeed, avatarUrl: null));
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
                child: Text(l10n.get('restore_default_avatar'), style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageFromCamera(BuildContext context) async {
    final l10n = context.watch<LocalizationProvider>();
    try {
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
          SnackBar(content: Text(l10n.getp('62cd_7167_fail_{error}', {'error': e}))),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery(BuildContext context) async {
    final l10n = context.watch<LocalizationProvider>();
    try {
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
          final base64 = Uri.dataFromBytes(bytes, mimeType: 'image/jpeg').toString();
          onProfileChanged(profile.copyWith(avatarUrl: base64));
        } else {
          // 移动端直接使用文件路径
          onProfileChanged(profile.copyWith(avatarUrl: image.path));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.getp('select_56fe_7247_fail_{error}', {'error': e}))),
        );
      }
    }
  }

  Widget _buildAvatarOption(BuildContext context, {
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
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
            child: Text(l10n.get('786e_5b9a')),
          ),
        ],
      ),
    );
  }

  String _syncLabel(String method, LocalizationProvider l10n) => switch (method) {
    'webdav' => 'WebDAV',
    'cloud' => l10n.get('4e91_sync'),
    'file' => l10n.get('file'),
    _ => l10n.get('local'),
  };

  void _showUnavailable(BuildContext context, String name) {
    final l10n = context.watch<LocalizationProvider>();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.getp('{name}_feature_5f85_5f00_901a_53ef_5148_4f7f_7528_local_data', {'name': name}))));
  }

  void _showEditProfileDialog(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final nicknameController = TextEditingController(text: l10n.get(profile.nickname));
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
              l10n.get('edit_personal_8d44_6599'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            
            // 头像预览
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    backgroundImage: profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl == null || profile.avatarUrl!.isEmpty
                        ? Text(
                            nicknameController.text.isNotEmpty
                                ? nicknameController.text[0].toUpperCase()
                                : l10n.get('7528'),
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
                    label: Text(l10n.get('66f4_6362_avatar')),
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
                hintText: l10n.get('input_4f60_7684_nickname'),
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
                labelText: l10n.get('email_5c55_793a_7528'),
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
              l10n.get('email_4ec5_7528_4e8e_5c55_793a_not_5f71_54cd_data_sync'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            
            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  onProfileChanged(
                    LocalProfile(
                      nickname: nicknameController.text.trim().isEmpty
                          ? l10n.get('local_user')
                          : nicknameController.text.trim() == l10n.get('local_user')
                              ? l10n.get('local_user')
                              : nicknameController.text.trim(),
                      email: emailController.text.trim(),
                      avatarSeed: profile.avatarSeed,
                      avatarUrl: profile.avatarUrl,
                      emailBound: profile.emailBound,
                      wechatBound: profile.wechatBound,
                    ),
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.get('8d44_6599_already_update'))),
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
      title: l10n.get('knowledge_6e90_config'),
      icon: Icons.cloud_outlined,
      trailing: FilledButton.tonalIcon(
        onPressed: onApplyChanged,
        icon: const Icon(Icons.refresh),
        label: Text(l10n.get('application_5e76_91cd_8f7d')),
      ),
      children: [
        // 环境切换
        SegmentedButton<ContentEnv>(
          segments: [
            ButtonSegment(value: ContentEnv.production, label: Text(l10n.get('publish_7248'))),
            ButtonSegment(
              value: ContentEnv.test,
              label: Text(l10n.get('test_7248')),
              enabled: userRole.allowedContentEnvs.contains('test'),
            ),
            ButtonSegment(
              value: ContentEnv.draft,
              label: Text(l10n.get('8349_7a3f_7248')),
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
                  l10n.getp('current_{url}', {'url': settings.contentBaseUrl}),
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
          l10n.get('test_7248_address_7559_7a7a_4f7f_7528_default'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.getp('default_{url}_content_test', {'url': AppSettings.defaultWorkerApiUrl}),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: testController,
          decoration: InputDecoration(
            hintText: l10n.get('custom_test_7248_url'),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => onTestUrlChanged(value.isEmpty ? null : value),
        ),
        const SizedBox(height: 16),

        // 发布版自定义 URL
        Text(
          l10n.get('publish_7248_address_7559_7a7a_4f7f_7528_default'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.getp('default_url', {'url': AppSettings.defaultProdContentUrl}),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: prodController,
          decoration: InputDecoration(
            hintText: l10n.get('custom_publish_7248_url'),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => onProdUrlChanged(value.isEmpty ? null : value),
        ),
      ],
    );
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
            subtitle:
                '模型：${defaultConfig.model} · ${defaultConfig.enabled ? l10n.get('already_enable') : l10n.get('already_disable')}',
          ),
        ] else ...[
          InfoRow(
            icon: Icons.warning_amber_outlined,
            title: l10n.get('un_config_ai'),
            subtitle: l10n.get('8bf7_add_ai_config_4ee5_4f7f_7528_evaluation_feature'),
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
    final isWhisper = settings.sttMode == 'whisper';

    return WorkPanel(
      title: l10n.get('8bed_97f3_8bc6_522b'),
      icon: Icons.mic_outlined,
      children: [
        // STT 模式切换
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _SttModeCard(
                  label: l10n.get('system_8bed_97f3'),
                  icon: Icons.phone_android,
                  description: l10n.get('4f7f_7528_8bbe_5907_5185_7f6e_8bed_97f3_8bc6_522b'),
                  selected: !isWhisper,
                  onTap: () => onSettingsChanged(
                    settings.copyWith(sttMode: 'system'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SttModeCard(
                  label: 'Whisper API',
                  icon: Icons.cloud_outlined,
                  description: l10n.get('4f7f_7528_whisper_517c_5bb9_api'),
                  selected: isWhisper,
                  onTap: () => onSettingsChanged(
                    settings.copyWith(sttMode: 'whisper'),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Whisper 配置
        if (isWhisper) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextField(
                  controller: TextEditingController(
                    text: settings.whisperBaseUrl ?? '',
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.get('api_address'),
                    hintText: 'https://api.openai.com/v1',
                    isDense: true,
                  ),
                  onChanged: (v) => onSettingsChanged(
                    settings.copyWith(whisperBaseUrl: v),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: TextEditingController(
                    text: settings.whisperApiKey ?? '',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                    isDense: true,
                  ),
                  obscureText: true,
                  onChanged: (v) => onSettingsChanged(
                    settings.copyWith(whisperApiKey: v),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: TextEditingController(
                    text: settings.whisperModel,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.get('6a21_578b_name'),
                    hintText: 'whisper-1',
                    isDense: true,
                  ),
                  onChanged: (v) => onSettingsChanged(
                    settings.copyWith(whisperModel: v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            isWhisper
                ? l10n.get('text_60307d1a')
                : l10n.get('4f7f_7528_8bbe_5907_5185_7f6e_8bed_97f3_8bc6_522b_offline_53'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),
      ],
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
      title: l10n.get('appearance_4e0e_theme'),
      icon: Icons.palette_outlined,
      children: [
        // 主题选择
        Text(l10n.get('theme_98ce_683c'), style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppThemeType.values.map((type) {
            final isSelected = themeType == type;
            return ChoiceChip(
              label: Text(l10n.get(type.label)),
              selected: isSelected,
              onSelected: (_) => onThemeTypeChanged(type),
              avatar: _getThemeIcon(type),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(l10n.get('4e3b_8272_select'), style: TextStyle(fontWeight: FontWeight.w700)),
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
        Text(l10n.get('5f3a_8c03_8272_select'), style: TextStyle(fontWeight: FontWeight.w700)),
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
            Text(l10n.get('font_size'), style: TextStyle(fontWeight: FontWeight.w700)),
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
          decoration: InputDecoration(labelText: l10n.get('card_density'), isDense: true),
          items: [
            DropdownMenuItem(value: 'comfortable', child: Text(l10n.get('comfortable'))),
            DropdownMenuItem(value: 'compact', child: Text(l10n.get('compact'))),
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
          decoration: InputDecoration(labelText: l10n.get('recommend_strategy'), isDense: true),
          items: [
            DropdownMenuItem(value: 'smart', child: Text(l10n.get('667a_80fd_recommend'))),
            DropdownMenuItem(value: 'low-score-first', child: Text(l10n.get('4f4e_5206_priority'))),
            DropdownMenuItem(value: 'path-order', child: Text(l10n.get('8def_5f84_987a_5e8f'))),
            DropdownMenuItem(value: 'high-frequency', child: Text(l10n.get('high_freq_priority'))),
            DropdownMenuItem(value: 'review-first', child: Text(l10n.get('review_priority'))),
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
          title: Text(l10n.get('5141_8bb8_8df3_8fc7_low_freq_knowledge')),
          onChanged: (value) => onSettingsChanged(
            settings.copyWith(allowSkipLowFrequency: value),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: settings.mockInterviewPreference,
          decoration: InputDecoration(
            labelText: l10n.get('6a21_62df_interview_7ec4_5377_504f_597d'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(value: 'mixed', child: Text(l10n.get('6df7_5408'))),
            DropdownMenuItem(value: 'foundation', child: Text(l10n.get('basic_knowledge'))),
            DropdownMenuItem(value: 'systemDesign', child: Text(l10n.get('system_design'))),
            DropdownMenuItem(value: 'code', child: Text(l10n.get('code_question_count'))),
            DropdownMenuItem(value: 'project', child: Text(l10n.get('project_deep_dig'))),
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
      title: l10n.get('about'),
      icon: Icons.info_outline,
      children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'zh', label: Text(l10n.get('chinese'))),
            ButtonSegment(value: 'en', label: Text('English')),
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
    this.onTestConnection,
    this.onRestore,
  });

  final AppSettings settings;
  final SyncSettings syncSettings;
  final ValueChanged<SyncSettings> onSyncSettingsChanged;
  final VoidCallback onSync;
  final VoidCallback onExport;
  final VoidCallback? onTestConnection;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('sync_4e0e_backup'),
      children: [
        InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: l10n.getp('current_65b9_5f0f_{method}', {'method': _methodLabel(syncSettings.method, l10n)}),
          subtitle: syncSettings.lastSyncAt == null
              ? l10n.get(syncSettings.lastSyncStatus)
              : '${l10n.get(syncSettings.lastSyncStatus)} · ${syncSettings.lastSyncAt}',
        ),
        DropdownButtonFormField<String>(
          initialValue: syncSettings.method,
          decoration: InputDecoration(labelText: l10n.get('sync_65b9_5f0f'), isDense: true),
          items: [
            DropdownMenuItem(value: 'local', child: Text(l10n.get('local_6a21_5f0f'))),
            DropdownMenuItem(value: 'file', child: Text(l10n.get('file_import_export'))),
            DropdownMenuItem(value: 'webdav', child: Text(l10n.get('custom_webdav'))),
            DropdownMenuItem(value: 'cloud', child: Text(l10n.get('account_4e91_sync'))),
            DropdownMenuItem(value: 'baidu', child: Text(l10n.get('767e_5ea6_7f51_76d8_5f85_5f00_901a'))),
            DropdownMenuItem(value: 'quark', child: Text(l10n.get('5938_514b_7f51_76d8_5f85_5f00_901a'))),
            DropdownMenuItem(value: 'aliyun', child: Text(l10n.get('963f_91cc_4e91_76d8_5f85_5f00_901a'))),
            DropdownMenuItem(value: 'onedrive', child: Text(l10n.get('onedrive_5f85_5f00_901a'))),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (['baidu', 'quark', 'aliyun', 'onedrive'].contains(value)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.getp('{method}_feature_5f85_5f00_901a', {'method': _methodLabel(value, l10n)}))),
              );
            }
            onSyncSettingsChanged(
              SyncSettings(
                method: value,
                webDavUrl: syncSettings.webDavUrl,
                webDavUsername: syncSettings.webDavUsername,
                webDavPassword: syncSettings.webDavPassword,
                lastSyncAt: syncSettings.lastSyncAt,
                lastSyncStatus: value == 'local' ? l10n.get('local_6a21_5f0f') : l10n.get('5f85_config'),
              ),
            );
          },
        ),
        if (syncSettings.method == 'webdav') ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: syncSettings.webDavUrl,
            decoration: InputDecoration(
              labelText: l10n.get('webdav_address'),
              hintText: 'https://dav.example.com/remote.php/dav/files/me',
            ),
            onChanged: (value) => onSyncSettingsChanged(
              SyncSettings(
                method: syncSettings.method,
                webDavUrl: value,
                webDavUsername: syncSettings.webDavUsername,
                webDavPassword: syncSettings.webDavPassword,
                lastSyncAt: syncSettings.lastSyncAt,
                lastSyncStatus: syncSettings.lastSyncStatus,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: syncSettings.webDavUsername,
            decoration: InputDecoration(labelText: l10n.get('username')),
            onChanged: (value) => onSyncSettingsChanged(
              SyncSettings(
                method: syncSettings.method,
                webDavUrl: syncSettings.webDavUrl,
                webDavUsername: value,
                webDavPassword: syncSettings.webDavPassword,
                lastSyncAt: syncSettings.lastSyncAt,
                lastSyncStatus: syncSettings.lastSyncStatus,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: syncSettings.webDavPassword,
            obscureText: true,
            decoration: InputDecoration(labelText: l10n.get('application_password')),
            onChanged: (value) => onSyncSettingsChanged(
              SyncSettings(
                method: syncSettings.method,
                webDavUrl: syncSettings.webDavUrl,
                webDavUsername: syncSettings.webDavUsername,
                webDavPassword: value,
                lastSyncAt: syncSettings.lastSyncAt,
                lastSyncStatus: syncSettings.lastSyncStatus,
              ),
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
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: onSync,
              icon: const Icon(Icons.cloud_upload),
              label: Text(l10n.get('backup_5230_cloud')),
            ),
            const SizedBox(width: 12),
            if (syncSettings.method == 'webdav')
              FilledButton.tonalIcon(
                onPressed: onRestore,
                icon: const Icon(Icons.cloud_download),
                label: Text(l10n.get('4ece_cloud_restore')),
              ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download),
              label: Text(l10n.get('data_export')),
            ),
          ],
        ),
      ],
    );
  }

  String _methodLabel(String method, LocalizationProvider l10n) => switch (method) {
    'file' => l10n.get('file_import_export'),
    'webdav' => 'WebDAV',
    'cloud' => l10n.get('account_4e91_sync'),
    'baidu' => l10n.get('767e_5ea6_7f51_76d8'),
    'quark' => l10n.get('5938_514b_7f51_76d8'),
    'aliyun' => l10n.get('963f_91cc_4e91_76d8'),
    'onedrive' => 'OneDrive',
    _ => l10n.get('local_6a21_5f0f'),
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

  Future<void> _checkUpdate() async {
    setState(() {
      _isChecking = true;
      _updateMessage = null;
    });

    try {
      final updateService = UpdateService();
      final updateInfo = await updateService.checkForUpdate('0.1.0');

      if (mounted) {
        final l10n = context.watch<LocalizationProvider>();
        setState(() {
          _isChecking = false;
          if (updateInfo != null) {
            _updateMessage = l10n.getp('53d1_73b0_new_version_v{version}', {'version': updateInfo.version});
            _showUpdateDialog(updateInfo);
          } else {
            _updateMessage = l10n.get('already_is_6700_new_version');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = context.watch<LocalizationProvider>();
        setState(() {
          _isChecking = false;
          _updateMessage = l10n.get('68c0_67e5_update_fail');
        });
      }
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    final l10n = context.watch<LocalizationProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.getp('53d1_73b0_new_version_v{version}', {'version': updateInfo.version})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.getp('publish_day_671f_{date}', {'date': updateInfo.releaseDate})),
            const SizedBox(height: 12),
            Text(l10n.get('update_content'), style: TextStyle(fontWeight: FontWeight.w700)),
            ...updateInfo.notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $note'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.getp('5e73_53f0_{size}', {'size': UpdateService.formatSize(updateInfo.platforms.values.first.size)}),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('7a0d_540e_518d_8bf4')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadUpdate(updateInfo);
            },
            child: Text(l10n.get('7acb_5373_update')),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadUpdate(UpdateInfo updateInfo) async {
    final l10n = context.watch<LocalizationProvider>();
    final updateService = UpdateService();
    final platformUpdate = updateService.getPlatformUpdate(updateInfo);

    if (platformUpdate == null) {
      final l10n = context.watch<LocalizationProvider>();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('current_5e73_53f0_6682_no_update_5305'))));
      return;
    }

    // Web 端提示刷新
    if (kIsWeb) {
      final l10n = context.watch<LocalizationProvider>();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('web_7aef_8bf7_5237_new_page_83b7_53d6_6700_new_version'))));
      return;
    }

    // 显示下载进度
    int received = 0;
    int total = platformUpdate.size;
    bool dialogOpen = true;

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
                Text(l10n.getp('6b63_5728_download_v{version}', {'version': updateInfo.version})),
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
              ],
            ),
          );
        },
      ),
    ).then((_) => dialogOpen = false);

    // 实际下载和校验
    final filePath = await updateService.downloadUpdate(
      platformUpdate: platformUpdate,
      version: updateInfo.version,
      onProgress: (r, t) {
        received = r;
        total = t;
        if (mounted && dialogOpen) {
          _currentSetDialogState?.call(() {});
        }
      },
    );

    if (mounted) {
      final l10n = context.watch<LocalizationProvider>();
      Navigator.pop(context); // 关闭下载对话框

      if (filePath != null) {
        _showInstallGuide(filePath, updateInfo.version);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('download_fail_6216_6821_9a8c_not_901a_8fc7_8bf7_retry'))),
        );
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
        instruction = l10n.get('download_complete_8bf7_5728_notification_680f_6216_file_mana')
            + l10n.get('5982_hint_un_77e5_6765_6e90_8bf7_5728_settings_4e2d_5141_8bb');
        break;
      case 'dmg':
        icon = Icons.apple;
        instruction = l10n.get('download_complete_8bf7_6253_5f00_dmg_file_5c06_application_6');
        break;
      case 'exe':
        icon = Icons.desktop_windows;
        instruction = l10n.get('download_complete_8bf7_8fd0_884c_exe_file_6309_7167_5411_5bf');
        break;
      default:
        icon = Icons.folder_open;
        instruction = l10n.get('download_complete_8bf7_5728_file_management_5668_4e2d_627e_5');
        break;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, size: 40, color: AppColors.success),
        title: Text(l10n.getp('v{version}_download_complete', {'version': version})),
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
            child: Text(l10n.get('77e5_9053_4e86')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('about_interview_667a_7ec3'),
      children: [
        InfoRow(
          icon: Icons.info_outline,
          title: l10n.get('version_010'),
          subtitle: l10n.get('ai_4e3b_52a8_56de_5fc6_study_5de5_4f5c_53f0'),
        ),
        InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: l10n.get('local_priority_cloud_sync'),
          subtitle: l10n.get('4e91_sync_fail_not_4f1a_963b_65ad_study_local_4e8b_4ef6_4f1a'),
        ),
        InkWell(
          onTap: _isChecking ? null : _checkUpdate,
          child: InfoRow(
            icon: Icons.system_update_alt_outlined,
            title: l10n.get('68c0_67e5_update'),
            subtitle: _updateMessage ?? l10n.get('70b9_51fb_68c0_67e5_is_or_has_new_version'),
          ),
        ),
        if (_isChecking)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
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
