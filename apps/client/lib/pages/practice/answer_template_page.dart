import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'answer_template_widgets.dart';

class AnswerTemplatePage extends StatelessWidget {
  const AnswerTemplatePage({
    super.key,
    required this.topicTitle,
    required this.question,
    this.onSelectTemplate,
  });

  final String topicTitle;
  final String question;
  final ValueChanged<String>? onSelectTemplate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('answer_template')),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showTemplateGuide(context, l10n),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 问题卡片
          QuestionCard(topicTitle: topicTitle, question: question),
          const SizedBox(height: 16),

          // 模板说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.get('choose_template_guide'),
                    style: TextStyle(fontSize: 12, color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 简短版模板
          TemplateCard(
            title: l10n.get('simple_short_version'),
            subtitle: l10n.get(
              'suitable_combine_electric_word_interview_fast_speed_answer',
            ),
            icon: Icons.short_text,
            color: const Color(0xFF10B981),
            duration: l10n.get('time_30sec_to_1min'),
            structure: [
              TemplateSection(
                nameKey: 'core_definition',
                descKey: 'one_sentence_explain_concept',
              ),
              TemplateSection(
                nameKey: 'key_feature',
                descKey: 'two_three_core_points',
              ),
              TemplateSection(
                nameKey: 'actual_application',
                descKey: 'step_1_actual_example_2',
              ),
            ],
            example: _getShortExample(l10n),
            onSelect: () => onSelectTemplate?.call('short'),
          ),
          const SizedBox(height: 12),

          // 标准版模板
          TemplateCard(
            title: l10n.get('standard_version'),
            subtitle: l10n.get(
              'suitable_combine_large_multi_count_tech_interview',
            ),
            icon: Icons.article_outlined,
            color: AppColors.accent,
            duration: l10n.get('time_2to3min'),
            structure: [
              TemplateSection(
                nameKey: 'concept_definition',
                descKey: 'clarify_clear_explain_is_what',
              ),
              TemplateSection(
                nameKey: 'core_principle',
                descKey: 'working_principle_and_mechanism',
              ),
              TemplateSection(
                nameKey: 'comparison_analysis',
                descKey: 'pros_cons_or_comparison',
              ),
              TemplateSection(
                nameKey: 'actual_application',
                descKey: 'project_in_use_scenario',
              ),
              TemplateSection(
                nameKey: 'note_intention_matter_item',
                descKey: 'common_pitfall_and_best_practice',
              ),
            ],
            example: _getStandardExample(l10n),
            onSelect: () => onSelectTemplate?.call('standard'),
          ),
          const SizedBox(height: 12),

          // 深入版模板
          TemplateCard(
            title: l10n.get('deep_enter_version'),
            subtitle: l10n.get(
              'suitable_combine_deep_enter_probe_discuss_senior_position',
            ),
            icon: Icons.psychology_outlined,
            color: const Color(0xFF8B5CF6),
            duration: l10n.get('time_3to5min'),
            structure: [
              TemplateSection(
                nameKey: 'concept_definition',
                descKey: 'clarify_clear_explain_is_what',
              ),
              TemplateSection(
                nameKey: 'underlying_layer_principle',
                descKey: 'deep_enter_working_principle',
              ),
              TemplateSection(
                nameKey: 'source_code_analysis',
                descKey: 'key_implementation_detail',
              ),
              TemplateSection(
                nameKey: 'performance_analysis',
                descKey: 'time_space_complexity',
              ),
              TemplateSection(
                nameKey: 'design_pattern',
                descKey: 'involve_and_design_thinking_want',
              ),
              TemplateSection(
                nameKey: 'actual_case',
                descKey: 'project_in_application',
              ),
              TemplateSection(
                nameKey: 'optional_extension_capability_design',
                descKey: 'mutual_close_tech_extension',
              ),
            ],
            example: _getDeepExample(l10n),
            onSelect: () => onSelectTemplate?.call('deep'),
          ),
          const SizedBox(height: 20),

          // 使用技巧
          _buildTipsSection(context, l10n),
        ],
      ),
    );
  }

  void _showTemplateGuide(BuildContext context, LocalizationProvider l10n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('template_usage_guide')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.get('select_suitable_template'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(l10n.get('choose_template_by_scenario')),
              SizedBox(height: 12),
              Text(
                l10n.get('personalized_adjustment'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(l10n.get('template_is_just_framework')),
              SizedBox(height: 12),
              Text(
                l10n.get('combine_actual_experience'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(l10n.get('use_real_cases')),
              SizedBox(height: 12),
              Text(
                l10n.get('practice_expression'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(l10n.get('remember_and_practice_fluent_expression')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('known_channel')),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsSection(BuildContext context, LocalizationProvider l10n) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.get('answer_tech_skill'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _buildTipItem(
              l10n.get('star_rule_1'),
              l10n.get('star_rule_description'),
            ),
            _buildTipItem(
              l10n.get('comparison_analysis'),
              l10n.get('comparison_with_other_solutions'),
            ),
            _buildTipItem(
              l10n.get('actual_case'),
              l10n.get('use_project_experience_support'),
            ),
            _buildTipItem(
              l10n.get('deep_enter_principle'),
              l10n.get('show_underlying_principle_understanding'),
            ),
            _buildTipItem(
              l10n.get('summary_upgrade_hua'),
              l10n.get('most_after_summary_key_point'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getShortExample(LocalizationProvider l10n) {
    return l10n.get('template_short_example');
  }

  String _getStandardExample(LocalizationProvider l10n) {
    return l10n.get('template_standard_example');
  }

  String _getDeepExample(LocalizationProvider l10n) {
    return l10n.get('template_deep_example');
  }
}
