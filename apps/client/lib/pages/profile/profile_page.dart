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
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/auth/login_page.dart';
import 'package:mianshi_zhilian/pages/profile/ai_config_page.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('缓存已清除，正在重新加载当前领域...'),
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
              ).showSnackBar(SnackBar(content: Text(message)));
            }
          },
          onTestConnection: () async {
            final result = await settingsProvider.testWebDavConnection(
              progressProvider.syncSettings,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message),
                  backgroundColor: result.success ? null : AppColors.danger,
                ),
              );
            }
          },
          onRestore: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('从云端恢复'),
                content: const Text(
                  '恢复将覆盖当前所有本地数据，此操作不可撤销。是否继续？',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('确认恢复'),
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
                  content: Text(result.message),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return WorkPanel(
      title: '账户管理',
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
                    _displayName,
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
                        : '本地游客模式 · 数据保存在本机',
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
                label: const Text('退出'),
              )
            else
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('登录'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MiniStat(label: '练习记录', value: '$attemptsCount'),
            _MiniStat(label: '连续天数', value: '$streakDays'),
            _MiniStat(label: '同步方式', value: _syncLabel(syncSettings.method)),
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
              label: const Text('修改资料'),
            ),
            _BindingButton(
              icon: Icons.mail_outline,
              label: profile.emailBound ? '邮箱已绑定' : '绑定邮箱',
              status: profile.emailBound ? '已绑定' : '待开通',
              onTap: () => _showUnavailable(context, '邮箱绑定'),
            ),
            _BindingButton(
              icon: Icons.wechat,
              label: profile.wechatBound ? '微信已绑定' : '绑定微信',
              status: profile.wechatBound ? '已绑定' : '待开通',
              onTap: () => _showUnavailable(context, '微信绑定'),
            ),
            _BindingButton(
              icon: Icons.link_outlined,
              label: '绑定其他账号',
              status: '待开通',
              onTap: () => _showUnavailable(context, '第三方账号绑定'),
            ),
          ],
        ),
        if (!authProvider.isLoggedIn) ...[
          const SizedBox(height: 12),
          Text(
            '不登录也可以完整学习和练习。登录只用于云端备份和跨设备恢复，登录后会提示合并本地数据。',
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
                ? Text(
                    _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '本',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
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
            const Text(
              '更换头像',
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
                    label: '拍照',
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _pickImageFromCamera(context);
                    },
                  ),
                // 相册选择
                _buildAvatarOption(
                  context,
                  icon: Icons.photo_library,
                  label: '相册',
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
                  label: '随机',
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
                child: const Text('恢复默认头像', style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageFromCamera(BuildContext context) async {
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
          SnackBar(content: Text('拍照失败: $e')),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery(BuildContext context) async {
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
          SnackBar(content: Text('选择图片失败: $e')),
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
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入头像 URL'),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(
            hintText: 'https://example.com/avatar.jpg',
            labelText: '头像链接',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                onProfileChanged(profile.copyWith(avatarUrl: url));
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _syncLabel(String method) => switch (method) {
    'webdav' => 'WebDAV',
    'cloud' => '云同步',
    'file' => '文件',
    _ => '本地',
  };

  void _showUnavailable(BuildContext context, String name) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$name 功能待开通，可先使用本地数据和 WebDAV 备份')));
  }

  void _showEditProfileDialog(BuildContext context) {
    final nicknameController = TextEditingController(text: profile.nickname);
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
            const Text(
              '编辑个人资料',
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
                                : '用',
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
                    label: const Text('更换头像'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // 昵称输入
            TextField(
              controller: nicknameController,
              decoration: InputDecoration(
                labelText: '昵称',
                hintText: '输入你的昵称',
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
                labelText: '邮箱（展示用）',
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
              '邮箱仅用于展示，不影响数据同步',
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
                          ? '本地用户'
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
                    const SnackBar(content: Text('资料已更新')),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('保存'),
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
    final testController = TextEditingController(
      text: settings.customTestContentUrl ?? '',
    );
    final prodController = TextEditingController(
      text: settings.customProdContentUrl ?? '',
    );

    return WorkPanel(
      title: '知识源配置',
      icon: Icons.cloud_outlined,
      trailing: FilledButton.tonalIcon(
        onPressed: onApplyChanged,
        icon: const Icon(Icons.refresh),
        label: const Text('应用并重载'),
      ),
      children: [
        // 环境切换
        SegmentedButton<ContentEnv>(
          segments: [
            const ButtonSegment(value: ContentEnv.production, label: Text('发布版')),
            ButtonSegment(
              value: ContentEnv.test,
              label: const Text('测试版'),
              enabled: userRole.allowedContentEnvs.contains('test'),
            ),
            ButtonSegment(
              value: ContentEnv.draft,
              label: const Text('草稿版'),
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
                  '当前：${settings.contentBaseUrl}',
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
          '测试版地址（留空使用默认）',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '默认：${AppSettings.defaultWorkerApiUrl}/content/test',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: testController,
          decoration: const InputDecoration(
            hintText: '自定义测试版 URL',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => onTestUrlChanged(value.isEmpty ? null : value),
        ),
        const SizedBox(height: 16),

        // 发布版自定义 URL
        Text(
          '发布版地址（留空使用默认）',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '默认：${AppSettings.defaultWorkerApiUrl}/content/production',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: prodController,
          decoration: const InputDecoration(
            hintText: '自定义发布版 URL',
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
    final aiProvider = context.watch<AiProvider>();
    final configs = aiProvider.configs;
    final defaultConfig = configs.where((c) => c.isDefault).firstOrNull;

    return WorkPanel(
      title: 'AI 配置',
      icon: Icons.smart_toy_outlined,
      trailing: FilledButton.tonalIcon(
        onPressed: onNavigateToConfig,
        icon: const Icon(Icons.settings_outlined),
        label: const Text('管理配置'),
      ),
      children: [
        if (defaultConfig != null) ...[
          InfoRow(
            icon: Icons.hub_outlined,
            title: defaultConfig.name,
            subtitle:
                '模型：${defaultConfig.model} · ${defaultConfig.enabled ? '已启用' : '已禁用'}',
          ),
        ] else ...[
          const InfoRow(
            icon: Icons.warning_amber_outlined,
            title: '未配置 AI',
            subtitle: '请添加 AI 配置以使用评估功能。',
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
    final isWhisper = settings.sttMode == 'whisper';

    return WorkPanel(
      title: '语音识别',
      icon: Icons.mic_outlined,
      children: [
        // STT 模式切换
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _SttModeCard(
                  label: '系统语音',
                  icon: Icons.phone_android,
                  description: '使用设备内置语音识别',
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
                  description: '使用 Whisper 兼容 API',
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
                  decoration: const InputDecoration(
                    labelText: 'API 地址',
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
                  decoration: const InputDecoration(
                    labelText: '模型名称',
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
                ? 'Whisper API 支持更高质量的语音识别，需要网络连接。支持 OpenAI、Groq 等兼容接口。'
                : '使用设备内置语音识别，离线可用，但识别质量因设备而异。',
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
    final themeType = settings.themeType;
    final primaryColor = settings.primaryColor;
    final accentColor = settings.accentColor;
    final fontScale = settings.fontScale;
    final density = settings.cardDensity;

    return WorkPanel(
      title: '外观与主题',
      icon: Icons.palette_outlined,
      children: [
        // 主题选择
        const Text('主题风格', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppThemeType.values.map((type) {
            final isSelected = themeType == type;
            return ChoiceChip(
              label: Text(type.label),
              selected: isSelected,
              onSelected: (_) => onThemeTypeChanged(type),
              avatar: _getThemeIcon(type),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text('主色选择', style: TextStyle(fontWeight: FontWeight.w700)),
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
        const Text('强调色选择', style: TextStyle(fontWeight: FontWeight.w700)),
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
            const Text('字体大小', style: TextStyle(fontWeight: FontWeight.w700)),
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
          decoration: const InputDecoration(labelText: '卡片密度', isDense: true),
          items: const [
            DropdownMenuItem(value: 'comfortable', child: Text('舒适')),
            DropdownMenuItem(value: 'compact', child: Text('紧凑')),
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
    return WorkPanel(
      title: '学习设置',
      icon: Icons.school_outlined,
      children: [
        DropdownButtonFormField<String>(
          initialValue: settings.recommendStrategy,
          decoration: const InputDecoration(labelText: '推荐策略', isDense: true),
          items: const [
            DropdownMenuItem(value: 'smart', child: Text('智能推荐')),
            DropdownMenuItem(value: 'low-score-first', child: Text('低分优先')),
            DropdownMenuItem(value: 'path-order', child: Text('路径顺序')),
            DropdownMenuItem(value: 'high-frequency', child: Text('高频优先')),
            DropdownMenuItem(value: 'review-first', child: Text('复习优先')),
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
                label: '每日新学',
                value: settings.dailyNewCount,
                onChanged: (value) =>
                    onSettingsChanged(settings.copyWith(dailyNewCount: value)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberSetting(
                label: '每日复习',
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
          title: const Text('优先补前置知识'),
          onChanged: (value) => onSettingsChanged(
            settings.copyWith(prioritizePrerequisites: value),
          ),
        ),
        SwitchListTile(
          value: settings.allowSkipLowFrequency,
          title: const Text('允许跳过低频知识'),
          onChanged: (value) => onSettingsChanged(
            settings.copyWith(allowSkipLowFrequency: value),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: settings.mockInterviewPreference,
          decoration: const InputDecoration(
            labelText: '模拟面试组卷偏好',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'mixed', child: Text('混合')),
            DropdownMenuItem(value: 'foundation', child: Text('基础知识')),
            DropdownMenuItem(value: 'systemDesign', child: Text('系统设计')),
            DropdownMenuItem(value: 'code', child: Text('代码题')),
            DropdownMenuItem(value: 'project', child: Text('项目深挖')),
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
    return WorkPanel(
      title: '关于',
      icon: Icons.info_outline,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'zh', label: Text('中文')),
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
    return WorkPanel(
      title: '同步与备份',
      children: [
        InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: '当前方式：${_methodLabel(syncSettings.method)}',
          subtitle: syncSettings.lastSyncAt == null
              ? syncSettings.lastSyncStatus
              : '${syncSettings.lastSyncStatus} · ${syncSettings.lastSyncAt}',
        ),
        DropdownButtonFormField<String>(
          initialValue: syncSettings.method,
          decoration: const InputDecoration(labelText: '同步方式', isDense: true),
          items: const [
            DropdownMenuItem(value: 'local', child: Text('本地模式')),
            DropdownMenuItem(value: 'file', child: Text('文件导入/导出')),
            DropdownMenuItem(value: 'webdav', child: Text('自定义 WebDAV')),
            DropdownMenuItem(value: 'cloud', child: Text('账号云同步')),
            DropdownMenuItem(value: 'baidu', child: Text('百度网盘（待开通）')),
            DropdownMenuItem(value: 'quark', child: Text('夸克网盘（待开通）')),
            DropdownMenuItem(value: 'aliyun', child: Text('阿里云盘（待开通）')),
            DropdownMenuItem(value: 'onedrive', child: Text('OneDrive（待开通）')),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (['baidu', 'quark', 'aliyun', 'onedrive'].contains(value)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${_methodLabel(value)} 功能待开通')),
              );
            }
            onSyncSettingsChanged(
              SyncSettings(
                method: value,
                webDavUrl: syncSettings.webDavUrl,
                webDavUsername: syncSettings.webDavUsername,
                webDavPassword: syncSettings.webDavPassword,
                lastSyncAt: syncSettings.lastSyncAt,
                lastSyncStatus: value == 'local' ? '本地模式' : '待配置',
              ),
            );
          },
        ),
        if (syncSettings.method == 'webdav') ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: syncSettings.webDavUrl,
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
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
            decoration: const InputDecoration(labelText: '用户名'),
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
            decoration: const InputDecoration(labelText: '应用密码'),
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
              label: const Text('测试连接'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: onSync,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('备份到云端'),
            ),
            const SizedBox(width: 12),
            if (syncSettings.method == 'webdav')
              FilledButton.tonalIcon(
                onPressed: onRestore,
                icon: const Icon(Icons.cloud_download),
                label: const Text('从云端恢复'),
              ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download),
              label: const Text('数据导出'),
            ),
          ],
        ),
      ],
    );
  }

  String _methodLabel(String method) => switch (method) {
    'file' => '文件导入/导出',
    'webdav' => 'WebDAV',
    'cloud' => '账号云同步',
    'baidu' => '百度网盘',
    'quark' => '夸克网盘',
    'aliyun' => '阿里云盘',
    'onedrive' => 'OneDrive',
    _ => '本地模式',
  };
}

class _AboutPanel extends StatefulWidget {
  const _AboutPanel();

  @override
  State<_AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends State<_AboutPanel> {
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
        setState(() {
          _isChecking = false;
          if (updateInfo != null) {
            _updateMessage = '发现新版本 v${updateInfo.version}';
            _showUpdateDialog(updateInfo);
          } else {
            _updateMessage = '已是最新版本';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _updateMessage = '检查更新失败';
        });
      }
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${updateInfo.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发布日期：${updateInfo.releaseDate}'),
            const SizedBox(height: 12),
            const Text('更新内容：', style: TextStyle(fontWeight: FontWeight.w700)),
            ...updateInfo.notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $note'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '平台：${UpdateService.formatSize(updateInfo.platforms.values.first.size)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadUpdate(updateInfo);
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadUpdate(UpdateInfo updateInfo) async {
    final updateService = UpdateService();
    final platformUpdate = updateService.getPlatformUpdate(updateInfo);

    if (platformUpdate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前平台暂无更新包')));
      return;
    }

    // Web 端提示刷新
    if (kIsWeb) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Web 端请刷新页面获取最新版本')));
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
            title: const Text('下载更新'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  value: total > 0 ? received / total : null,
                ),
                const SizedBox(height: 16),
                Text('正在下载 v${updateInfo.version}...'),
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
      Navigator.pop(context); // 关闭下载对话框

      if (filePath != null) {
        _showInstallGuide(filePath, updateInfo.version);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败或校验不通过，请重试')),
        );
      }
    }
  }

  void _showInstallGuide(String filePath, String version) {
    final ext = filePath.split('.').last.toLowerCase();
    String instruction;
    IconData icon;
    switch (ext) {
      case 'apk':
        icon = Icons.android;
        instruction = '下载完成。请在通知栏或文件管理器中打开 APK 文件进行安装。\n'
            '如提示"未知来源"，请在设置中允许安装。';
      case 'dmg':
        icon = Icons.apple;
        instruction = '下载完成。请打开 DMG 文件，将应用拖入"应用程序"文件夹。';
      case 'exe':
        icon = Icons.desktop_windows;
        instruction = '下载完成。请运行 EXE 文件按照向导完成安装。';
      default:
        icon = Icons.folder_open;
        instruction = '下载完成。请在文件管理器中找到安装包并运行。';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, size: 40, color: AppColors.success),
        title: Text('v$version 下载完成'),
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
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '关于面试智练',
      children: [
        const InfoRow(
          icon: Icons.info_outline,
          title: '版本 0.1.0',
          subtitle: 'AI 主动回忆学习工作台',
        ),
        const InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: '本地优先 + 云端同步',
          subtitle: '云同步失败不会阻断学习，本地事件会等待重试。',
        ),
        InkWell(
          onTap: _isChecking ? null : _checkUpdate,
          child: InfoRow(
            icon: Icons.system_update_alt_outlined,
            title: '检查更新',
            subtitle: _updateMessage ?? '点击检查是否有新版本',
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
