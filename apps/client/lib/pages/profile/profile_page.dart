import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;

    return ListView(
      children: [
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
          onLanguageChanged: (lang) => settingsProvider.updateLanguage(lang),
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

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({
    required this.settings,
    required this.onThemeModeChanged,
    required this.onPrimaryColorChanged,
    required this.onAccentColorChanged,
    required this.onFontScaleChanged,
    required this.onDensityChanged,
  });

  final dynamic settings;
  final ValueChanged<String> onThemeModeChanged;
  final ValueChanged<String> onPrimaryColorChanged;
  final ValueChanged<String> onAccentColorChanged;
  final ValueChanged<double> onFontScaleChanged;
  final ValueChanged<String> onDensityChanged;

  @override
  Widget build(BuildContext context) {
    final themeMode = settings.themeMode as String;
    final primaryColor = settings.primaryColor as String;
    final accentColor = settings.accentColor as String;
    final fontScale = settings.fontScale as double;
    final density = settings.density as String;

    final themeModeValue = switch (themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return WorkPanel(
      title: '外观与主题',
      children: [
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
            ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
            ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
          ],
          selected: {themeModeValue},
          onSelectionChanged: (value) {
            final modeStr = switch (value.first) {
              ThemeMode.light => 'light',
              ThemeMode.dark => 'dark',
              _ => 'system',
            };
            onThemeModeChanged(modeStr);
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
              selected: primaryColor == 'blue',
              onTap: () => onPrimaryColorChanged('blue'),
            ),
            _ColorButton(
              color: const Color(0xFF12372A),
              selected: primaryColor == 'green',
              onTap: () => onPrimaryColorChanged('green'),
            ),
            _ColorButton(
              color: const Color(0xFF111827),
              selected: primaryColor == 'gray',
              onTap: () => onPrimaryColorChanged('gray'),
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
              selected: accentColor == 'cyan',
              onTap: () => onAccentColorChanged('cyan'),
            ),
            _ColorButton(
              color: const Color(0xFF10B981),
              selected: accentColor == 'emerald',
              onTap: () => onAccentColorChanged('emerald'),
            ),
            _ColorButton(
              color: const Color(0xFFF59E0B),
              selected: accentColor == 'amber',
              onTap: () => onAccentColorChanged('amber'),
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
          value: density,
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

  final dynamic settings;
  final ValueChanged<String> onStrategyChanged;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '学习设置',
      children: [
        DropdownButtonFormField<String>(
          value: settings.recommendStrategy as String,
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

  final dynamic settings;
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
          selected: {settings.language as String},
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

  final dynamic settings;
  final VoidCallback onSync;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final lastSync = settings.lastSyncAt as DateTime?;
    return WorkPanel(
      title: '数据管理',
      children: [
        InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: '手动同步',
          subtitle: lastSync != null
              ? '上次同步：${_formatDateTime(lastSync)}'
              : '尚未同步',
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

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '关于面试智练',
      children: const [
        InfoRow(
          icon: Icons.info_outline,
          title: '版本 1.0.0',
          subtitle: 'AI 主动回忆学习工作台',
        ),
        InfoRow(
          icon: Icons.cloud_sync_outlined,
          title: '本地优先 + 云端同步',
          subtitle: '云同步失败不会阻断学习，本地事件会等待重试。',
        ),
        InfoRow(
          icon: Icons.system_update_alt_outlined,
          title: '检查更新',
          subtitle: '读取 GitHub Releases / update.json，校验 sha256 后引导安装。',
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
