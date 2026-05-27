import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
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

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _AccountPanel(
          authProvider: authProvider,
          onLogin: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage()),
            );
          },
          onLogout: () => authProvider.logout(),
        ),
        const SizedBox(height: 16),
        _ContentEnvPanel(
          settings: settings,
          onEnvChanged: (env) async {
            await settingsProvider.setContentEnv(env);
            // 切换环境后，自动重载内容
            if (context.mounted) {
              final contentProvider = context.read<ContentProvider>();
              await contentProvider.switchContentEnv(settingsProvider.settings.contentBaseUrl);
            }
          },
          onTestUrlChanged: (url) async {
            await settingsProvider.setCustomTestContentUrl(url);
          },
          onProdUrlChanged: (url) async {
            await settingsProvider.setCustomProdContentUrl(url);
          },
          onApplyChanged: () async {
            // 清空本地知识缓存
            final contentProvider = context.read<ContentProvider>();
            await contentProvider.clearAllDomainCache();

            // 重新加载内容，使用当前领域
            await contentProvider.switchContentEnv(
              settingsProvider.settings.contentBaseUrl,
              currentDomainId: settingsProvider.settings.currentDomain,
            );

            // 显示提示
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
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiConfigPage()),
            );
          },
        ),
        const SizedBox(height: 16),
        _AppearancePanel(
          settings: settings,
          onThemeModeChanged: (mode) => settingsProvider.updateThemeMode(mode),
          onPrimaryColorChanged: (color) => settingsProvider.updatePrimaryColor(color),
          onAccentColorChanged: (color) => settingsProvider.updateAccentColor(color),
          onFontScaleChanged: (scale) => settingsProvider.updateFontScale(scale),
          onDensityChanged: (density) => settingsProvider.updateDensity(density),
        ),
        const SizedBox(height: 16),
        _LearningSettingsPanel(
          settings: settings,
          onStrategyChanged: (strategy) => settingsProvider.updateRecommendStrategy(strategy),
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
          onSync: () => settingsProvider.syncData(),
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
    required this.onLogin,
    required this.onLogout,
  });

  final AuthProvider authProvider;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '账号',
      children: [
        if (authProvider.isLoggedIn) ...[
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  authProvider.user!.nickname.isNotEmpty
                      ? authProvider.user!.nickname[0].toUpperCase()
                      : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authProvider.user!.nickname,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '@${authProvider.user!.username}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('退出登录'),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Icon(
                Icons.person_outline,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('登录后可同步学习进度到云端'),
              ),
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('登录'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── 知识源配置面板 ──────────────────────────────────────────────

class _ContentEnvPanel extends StatelessWidget {
  const _ContentEnvPanel({
    required this.settings,
    required this.onEnvChanged,
    required this.onTestUrlChanged,
    required this.onProdUrlChanged,
    required this.onApplyChanged,
  });

  final AppSettings settings;
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
      trailing: FilledButton.tonalIcon(
        onPressed: onApplyChanged,
        icon: const Icon(Icons.refresh),
        label: const Text('应用并重载'),
      ),
      children: [
        // 环境切换
        SegmentedButton<ContentEnv>(
          segments: const [
            ButtonSegment(value: ContentEnv.test, label: Text('测试版')),
            ButtonSegment(value: ContentEnv.production, label: Text('发布版')),
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
            subtitle: '模型：${defaultConfig.model} · ${defaultConfig.enabled ? '已启用' : '已禁用'}',
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

// ── 外观面板 ──────────────────────────────────────────────

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({
    required this.settings,
    required this.onThemeModeChanged,
    required this.onPrimaryColorChanged,
    required this.onAccentColorChanged,
    required this.onFontScaleChanged,
    required this.onDensityChanged,
  });

  final AppSettings settings;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<Color> onPrimaryColorChanged;
  final ValueChanged<Color> onAccentColorChanged;
  final ValueChanged<double> onFontScaleChanged;
  final ValueChanged<String> onDensityChanged;

  @override
  Widget build(BuildContext context) {
    final themeMode = settings.themeMode;
    final primaryColor = settings.primaryColor;
    final accentColor = settings.accentColor;
    final fontScale = 1.0; // Not yet in AppSettings
    final density = 'comfortable'; // Not yet in AppSettings

    return WorkPanel(
      title: '外观与主题',
      children: [
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
            ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
            ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
          ],
          selected: {themeMode},
          onSelectionChanged: (value) {
            onThemeModeChanged(value.first);
          },
        ),
        const SizedBox(height: 16),
        const Text('主色选择', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
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
          decoration: const InputDecoration(
            labelText: '卡片密度',
            isDense: true,
          ),
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
}

class _LearningSettingsPanel extends StatelessWidget {
  const _LearningSettingsPanel({
    required this.settings,
    required this.onStrategyChanged,
  });

  final AppSettings settings;
  final ValueChanged<String> onStrategyChanged;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '学习设置',
      children: [
        DropdownButtonFormField<String>(
          initialValue: settings.recommendStrategy,
          decoration: const InputDecoration(
            labelText: '推荐策略',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'weighted', child: Text('加权推荐（综合考虑熟练度与复习时间）')),
            DropdownMenuItem(value: 'random', child: Text('随机推荐')),
            DropdownMenuItem(value: 'sequential', child: Text('顺序推荐')),
          ],
          onChanged: (value) {
            if (value != null) onStrategyChanged(value);
          },
        ),
      ],
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
      title: '语言设置',
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
    required this.onSync,
    required this.onExport,
  });

  final AppSettings settings;
  final VoidCallback onSync;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '数据管理',
      children: [
        const InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: '手动同步',
          subtitle: '尚未同步',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: onSync,
              icon: const Icon(Icons.sync),
              label: const Text('立即同步'),
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
}

class _AboutPanel extends StatefulWidget {
  const _AboutPanel();

  @override
  State<_AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends State<_AboutPanel> {
  bool _isChecking = false;
  String? _updateMessage;

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
            ...updateInfo.notes.map((note) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $note'),
            )),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台暂无更新包')),
      );
      return;
    }

    // Web 端提示刷新
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web 端请刷新页面获取最新版本')),
      );
      return;
    }

    // 显示下载进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('下载更新'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在下载 v${updateInfo.version}...'),
            const SizedBox(height: 8),
            Text(
              '大小：${UpdateService.formatSize(platformUpdate.size)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );

    // TODO: 实际下载和校验 sha256
    // 1. 下载文件到临时目录
    // 2. 计算 sha256 并与 platformUpdate.sha256 比对
    // 3. 校验通过后引导安装

    // 模拟下载完成
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Navigator.pop(context); // 关闭下载对话框
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成，请手动安装更新包')),
      );
    }
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
