import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

class LearningPreferencesPage extends StatelessWidget {
  const LearningPreferencesPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    return ProfileSubPage(
      title: l10n.get('learning_preferences'),
      children: [
        LearningSettingsPanel(
          settings: settingsProvider.settings,
          onSettingsChanged: settingsProvider.updateSettings,
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

class LearningSettingsPanel extends StatelessWidget {
  const LearningSettingsPanel({
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
          decoration: InputDecoration(
            labelText: l10n.get('recommend_strategy'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'smart',
              child: Text(l10n.get('intelligence_enable_recommend')),
            ),
            DropdownMenuItem(
              value: 'low-score-first',
              child: Text(l10n.get('low_score_priority')),
            ),
            DropdownMenuItem(
              value: 'path-order',
              child: Text(l10n.get('road_path_smooth_sequence')),
            ),
            DropdownMenuItem(
              value: 'high-frequency',
              child: Text(l10n.get('high_freq_priority')),
            ),
            DropdownMenuItem(
              value: 'review-first',
              child: Text(l10n.get('review_priority')),
            ),
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
              child: NumberSetting(
                label: l10n.get('daily_new_learn'),
                value: settings.dailyNewCount,
                onChanged: (value) =>
                    onSettingsChanged(settings.copyWith(dailyNewCount: value)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NumberSetting(
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
          title: Text(l10n.get('allow_skip_pass_low_freq_knowledge')),
          onChanged: (value) => onSettingsChanged(
            settings.copyWith(allowSkipLowFrequency: value),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: settings.mockInterviewPreference,
          decoration: InputDecoration(
            labelText: l10n.get('mode_mock_interview_group_volume_bias_good'),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'mixed',
              child: Text(l10n.get('mix_combine')),
            ),
            DropdownMenuItem(
              value: 'foundation',
              child: Text(l10n.get('basic_knowledge')),
            ),
            DropdownMenuItem(
              value: 'systemDesign',
              child: Text(l10n.get('system_design')),
            ),
            DropdownMenuItem(
              value: 'code',
              child: Text(l10n.get('code_question_count')),
            ),
            DropdownMenuItem(
              value: 'project',
              child: Text(l10n.get('project_deep_dig')),
            ),
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

class NumberSetting extends StatelessWidget {
  const NumberSetting({
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
