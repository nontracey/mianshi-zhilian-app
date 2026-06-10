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

  // 三套智能推荐权重预设：[低分优先, 逾期优先, 高频优先, 路径顺序, 未练习]
  static const Map<String, List<int>> _presetWeights = {
    'conservative': [45, 30, 10, 10, 5],
    'balanced': [35, 25, 25, 10, 5],
    'aggressive': [20, 25, 40, 5, 10],
  };

  String _currentPreset(AppSettings s) {
    for (final entry in _presetWeights.entries) {
      final w = entry.value;
      if (s.lowScoreWeight == w[0] &&
          s.overdueWeight == w[1] &&
          s.highFrequencyWeight == w[2] &&
          s.pathOrderWeight == w[3] &&
          s.notPracticedWeight == w[4]) {
        return entry.key;
      }
    }
    return 'balanced';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('study_settings'),
      icon: Icons.school_outlined,
      children: [
        // 一键推荐默认：面向新手，一次性把推荐策略/权重/每日学习量
        // 配置为均衡、开箱即用的组合，避免逐项摸索设置项。
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => onSettingsChanged(settings.copyWith(
              recommendStrategy: 'smart',
              lowScoreWeight: _presetWeights['balanced']![0],
              overdueWeight: _presetWeights['balanced']![1],
              highFrequencyWeight: _presetWeights['balanced']![2],
              pathOrderWeight: _presetWeights['balanced']![3],
              notPracticedWeight: _presetWeights['balanced']![4],
              dailyNewCount: 3,
              dailyReviewCount: 6,
              prioritizePrerequisites: true,
              allowSkipLowFrequency: false,
            )),
            icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
            label: Text(l10n.get('apply_recommended_defaults')),
          ),
        ),
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
        // 智能推荐的权重设置默认沉睡，提供三套预设让用户一键启用，
        // 而不必逐项调整 lowScoreWeight/overdueWeight 等隐藏权重。
        if (settings.recommendStrategy == 'smart') ...[
          const SizedBox(height: 12),
          Text(
            l10n.get('recommend_preset'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'conservative',
                label: Text(l10n.get('recommend_preset_conservative')),
              ),
              ButtonSegment(
                value: 'balanced',
                label: Text(l10n.get('recommend_preset_balanced')),
              ),
              ButtonSegment(
                value: 'aggressive',
                label: Text(l10n.get('recommend_preset_aggressive')),
              ),
            ],
            selected: {_currentPreset(settings)},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              final preset = selection.first;
              onSettingsChanged(settings.copyWith(
                lowScoreWeight: _presetWeights[preset]![0],
                overdueWeight: _presetWeights[preset]![1],
                highFrequencyWeight: _presetWeights[preset]![2],
                pathOrderWeight: _presetWeights[preset]![3],
                notPracticedWeight: _presetWeights[preset]![4],
              ));
            },
          ),
        ],
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
