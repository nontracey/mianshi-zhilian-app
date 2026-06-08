import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

class AppearanceLanguagePage extends StatelessWidget {
  const AppearanceLanguagePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;
    return ProfileSubPage(
      title: l10n.get('appearance_language'),
      children: [
        AppearancePanel(
          settings: settings,
          onThemeTypeChanged: settingsProvider.setThemeType,
          onPrimaryColorChanged: settingsProvider.updatePrimaryColor,
          onAccentColorChanged: settingsProvider.updateAccentColor,
          onFontScaleChanged: settingsProvider.updateFontScale,
          onDensityChanged: settingsProvider.updateDensity,
        ),
        const SizedBox(height: 16),
        LanguagePanel(
          settings: settings,
          onLanguageChanged: (lang) {
            settingsProvider.updateLanguage(lang);
            context.read<LocalizationProvider>().setLanguage(lang);
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

class AppearancePanel extends StatelessWidget {
  const AppearancePanel({
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
      title: l10n.get('appearance_and_theme'),
      icon: Icons.palette_outlined,
      children: [
        Text(
          l10n.get('theme_wind_style'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AppThemeType.values.map((type) {
            final isSelected = themeType == type;
            return ChoiceChip(
              label: Text(l10n.get(type.labelKey)),
              selected: isSelected,
              onSelected: (_) => onThemeTypeChanged(type),
              avatar: _getThemeIcon(type),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('main_color_select'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            ColorButton(
              color: const Color(0xFF1A2B4A),
              selected: primaryColor == const Color(0xFF1A2B4A),
              onTap: () => onPrimaryColorChanged(const Color(0xFF1A2B4A)),
            ),
            ColorButton(
              color: const Color(0xFF0A2540),
              selected: primaryColor == const Color(0xFF0A2540),
              onTap: () => onPrimaryColorChanged(const Color(0xFF0A2540)),
            ),
            ColorButton(
              color: const Color(0xFF12372A),
              selected: primaryColor == const Color(0xFF12372A),
              onTap: () => onPrimaryColorChanged(const Color(0xFF12372A)),
            ),
            ColorButton(
              color: const Color(0xFF111827),
              selected: primaryColor == const Color(0xFF111827),
              onTap: () => onPrimaryColorChanged(const Color(0xFF111827)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l10n.get('accent_schedule_color_select'),
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            ColorButton(
              color: const Color(0xFF3078F0),
              selected: accentColor == const Color(0xFF3078F0),
              onTap: () => onAccentColorChanged(const Color(0xFF3078F0)),
            ),
            ColorButton(
              color: const Color(0xFF00CCF9),
              selected: accentColor == const Color(0xFF00CCF9),
              onTap: () => onAccentColorChanged(const Color(0xFF00CCF9)),
            ),
            ColorButton(
              color: const Color(0xFF10B981),
              selected: accentColor == const Color(0xFF10B981),
              onTap: () => onAccentColorChanged(const Color(0xFF10B981)),
            ),
            ColorButton(
              color: const Color(0xFFF59E0B),
              selected: accentColor == const Color(0xFFF59E0B),
              onTap: () => onAccentColorChanged(const Color(0xFFF59E0B)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              l10n.get('font_size'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
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
          decoration: InputDecoration(
            labelText: l10n.get('card_density'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'comfortable',
              child: Text(l10n.get('comfortable')),
            ),
            DropdownMenuItem(
              value: 'compact',
              child: Text(l10n.get('compact')),
            ),
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

class ColorButton extends StatelessWidget {
  const ColorButton({
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

class LanguagePanel extends StatelessWidget {
  const LanguagePanel({
    required this.settings,
    required this.onLanguageChanged,
  });

  final AppSettings settings;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('language_settings'),
      icon: Icons.translate,
      children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'zh', label: Text(l10n.get('chinese'))),
            ButtonSegment(value: 'en', label: Text(l10n.get('english'))),
          ],
          selected: {settings.language},
          onSelectionChanged: (value) => onLanguageChanged(value.first),
        ),
      ],
    );
  }
}
