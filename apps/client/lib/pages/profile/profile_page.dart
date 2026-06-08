import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/pages/auth/login_page.dart';
import 'package:mianshi_zhilian/pages/profile/log_management_page.dart';
import 'package:mianshi_zhilian/pages/profile/on_device_model_management_page.dart';
import 'package:mianshi_zhilian/pages/profile/sync_backup_page.dart';
import 'package:mianshi_zhilian/pages/profile/ai_voice_settings_page.dart';
import 'package:mianshi_zhilian/pages/profile/learning_preferences_page.dart';
import 'package:mianshi_zhilian/pages/profile/appearance_language_page.dart';
import 'package:mianshi_zhilian/pages/profile/content_source_page.dart';
import 'package:mianshi_zhilian/pages/profile/route_preference_page.dart';
import 'package:mianshi_zhilian/pages/profile/about_update_page.dart';
import 'package:mianshi_zhilian/services/app_permission_service.dart';
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
            context.push('/auth/login', extra: const LoginPage());
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
              onTap: () => context.push(
                '/profile/sync-backup',
                extra: const SyncBackupPage(),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.smart_toy_outlined,
              title: l10n.get('ai_and_voice'),
              subtitle: l10n.get('ai_and_voice_desc'),
              onTap: () => context.push(
                '/profile/ai-voice-settings',
                extra: const AiVoiceSettingsPage(),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.tune_outlined,
              title: l10n.get('learning_preferences'),
              subtitle: l10n.get('learning_preferences_desc'),
              onTap: () => context.push(
                '/profile/learning-preferences',
                extra: const LearningPreferencesPage(),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.palette_outlined,
              title: l10n.get('appearance_language'),
              subtitle: l10n.getp('appearance_language_desc', {
                'language': settings.language.toUpperCase(),
              }),
              onTap: () => context.push(
                '/profile/appearance-language',
                extra: const AppearanceLanguagePage(),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.source_outlined,
              title: l10n.get('content_source'),
              subtitle: l10n.get(settings.contentEnv.labelKey),
              onTap: () => context.push(
                '/profile/content-source',
                extra: const ContentSourcePage(),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.model_training_outlined,
              title: l10n.get('on_device_model_management'),
              subtitle: l10n.get('model_management_subtitle'),
              onTap: () => context.push(
                '/profile/model-management',
                extra: const OnDeviceModelManagementPage(),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.route_outlined,
              title: l10n.get('route_diagnosis'),
              subtitle: l10n.get('route_diagnostics_subtitle'),
              onTap: () => context.push(
                '/profile/route-preference',
                extra: const RoutePreferencePage(),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.article_outlined,
              title: l10n.get('log_management'),
              subtitle: l10n.get('log_management_subtitle'),
              onTap: () => context.push(
                '/profile/log-management',
                extra: const LogManagementPage(),
              ),
            ),
            _ProfileSectionItem(
              icon: Icons.info_outline,
              title: l10n.get('about_update'),
              subtitle: l10n.get('about_update_desc'),
              onTap: () => context.push(
                '/profile/about-update',
                extra: const AboutUpdatePage(),
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
        _ => l10n.get('local_mode'),
      };
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

// ── 账号面板 ──────────────────────────────────────────────

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
            BindingButton(
              icon: Icons.mail_outline,
              label: profile.emailBound
                  ? l10n.get('email_already_bind')
                  : l10n.get('bind_email'),
              status: profile.emailBound
                  ? l10n.get('already_bind')
                  : l10n.get('pending_open'),
              onTap: () => _showUnavailable(context, l10n.get('email_bind')),
            ),
            BindingButton(
              icon: Icons.wechat,
              label: profile.wechatBound
                  ? l10n.get('wechat_already_bind')
                  : l10n.get('bind_wechat'),
              status: profile.wechatBound
                  ? l10n.get('already_bind')
                  : l10n.get('pending_open'),
              onTap: () => _showUnavailable(context, l10n.get('wechat_bind')),
            ),
            BindingButton(
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
    return 'local_user';
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

