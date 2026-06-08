import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/pages/practice/answer_versions_page.dart';

// ── 问题面板 ──────────────────────────────────────────────

class QuestionPanel extends StatelessWidget {
  const QuestionPanel({super.key, required this.topic});

  final dynamic topic;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  topic.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (topic.highFrequency)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    l10n.get('high_freq'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            topic.recallPrompts.isNotEmpty
                ? topic.recallPrompts.first.prompt
                : l10n.getp('please_use_self_word_explain_title_core_cont_2', {
                    'title': topic.title,
                  }),
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
          if (topic.interviewerFocus?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l10n.get('interviewer_focus')}${topic.interviewerFocus}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 评分标准面板 ──────────────────────────────────────────────

class RubricPanel extends StatelessWidget {
  const RubricPanel({super.key, required this.rubric});

  final dynamic rubric;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final mustHave = rubric.mustHave as List<dynamic>? ?? [];
    final commonMistakes = rubric.commonMistakes as List<dynamic>? ?? [];

    if (mustHave.isEmpty && commonMistakes.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.get('evaluation_score_key_point'),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          if (mustHave.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...mustHave
                .take(4)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.toString(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (commonMistakes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.get('common_wrong'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 4),
            ...commonMistakes
                .take(3)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '· ${item.toString()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

// ── AI 就绪提示 ──────────────────────────────────────────────

class AiReadinessNotice extends StatelessWidget {
  const AiReadinessNotice({super.key, required this.config});

  final AiConfig? config;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final (icon, color, text) = _status(context, l10n);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _status(
    BuildContext context,
    LocalizationProvider l10n,
  ) {
    if (config == null) {
      return (
        Icons.info_outline,
        AppColors.warning,
        l10n.get('ai_status_not_configured_local_save'),
      );
    }
    final record = config!.testRecord(AiCapability.text);
    if (record.state == CapabilityTestState.passed && config!.canEvaluate) {
      return (
        Icons.check_circle_outline,
        AppColors.success,
        l10n.getp('ai_status_ready_model', {'model': config!.name}),
      );
    }
    if (record.state == CapabilityTestState.failed) {
      return (
        Icons.error_outline,
        AppColors.danger,
        l10n.getp('ai_status_failed_model', {'model': config!.name}),
      );
    }
    return (
      Icons.pending_outlined,
      AppColors.warning,
      l10n.getp('ai_status_untested_model', {'model': config!.name}),
    );
  }
}

// ── 模型选择器 ──────────────────────────────────────────────

class ModelSelector extends StatelessWidget {
  const ModelSelector({super.key, required this.selectedId, required this.onChanged});

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final aiProvider = context.watch<AiProvider>();
    final configs = aiProvider.enabledConfigs;
    if (configs.isEmpty) {
      final l10n = context.watch<LocalizationProvider>();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.hub_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.get('ai_not_configured_using_local_practice')),
            ),
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.get(
                      'please_to_personal_center_ai_config_add_your_mode_type',
                    ),
                  ),
                ),
              ),
              child: Text(l10n.get('go_config')),
            ),
          ],
        ),
      );
    }

    final selected =
        selectedId ?? aiProvider.defaultConfig?.id ?? configs.first.id;
    return DropdownButtonFormField<String>(
      initialValue: configs.any((c) => c.id == selected)
          ? selected
          : configs.first.id,
      decoration: InputDecoration(
        labelText: l10n.get('evaluation_score_mode_type'),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items: configs
          .map(
            (config) => DropdownMenuItem(
              value: config.id,
              child: Row(
                children: [
                  Flexible(
                    child: Text(config.name, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  CapabilityTags(config: config),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ── 能力标签 ──────────────────────────────────────────────

class CapabilityTags extends StatelessWidget {
  const CapabilityTags({super.key, required this.config});

  final dynamic config;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final tags = <Widget>[];
    if (config.supportsTextInput == true) {
      tags.add(_tag(l10n.get('text_local'), AppColors.accent));
    }
    if (config.supportsImageInput == true) {
      tags.add(_tag(l10n.get('image_picture'), AppColors.success));
    }
    if (config.audioMode != AiAudioMode.none) {
      tags.add(_tag(l10n.get('speech_voice'), AppColors.warning));
    }
    if (tags.isEmpty) return const SizedBox();
    return Row(mainAxisSize: MainAxisSize.min, children: tags);
  }

  Widget _tag(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── 输入模式 Tab ──────────────────────────────────────────────

class InputModeTab extends StatelessWidget {
  const InputModeTab({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.disabledTooltip,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledTooltip;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled
        ? (selected
              ? AppColors.accent
              : Theme.of(context).colorScheme.onSurfaceVariant)
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3);

    return Expanded(
      child: Tooltip(
        message: !enabled && disabledTooltip != null ? disabledTooltip! : '',
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected && enabled
                  ? Theme.of(context).colorScheme.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected && enabled
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: effectiveColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: effectiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 答案输入框 ──────────────────────────────────────────────

class AnswerInputField extends StatelessWidget {
  const AnswerInputField({
    super.key,
    required this.controller,
    required this.inputMode,
    this.onChanged,
  });

  final TextEditingController controller;
  final String inputMode;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return TextField(
      controller: controller,
      minLines: 6,
      maxLines: inputMode == 'code' ? 16 : 12,
      style: inputMode == 'code'
          ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
          : null,
      decoration: InputDecoration(
        hintText: switch (inputMode) {
          'code' => l10n.get(
            'write_lower_thinking_road_complexity_edge_boundary_item_condition_or_code',
          ),
          'image' => l10n.get(
            'description_image_picture_architecture_hand_write_note_in',
          ),
          'voice' => l10n.get(
            'speech_voice_transfer_write_text_local_will_output_current_at_upper_method',
          ),
          _ => l10n.get('input_your_recall_answer_here'),
        },
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
      ),
      onChanged: (_) => onChanged?.call(),
    );
  }
}

// ── 进度指示器 ──────────────────────────────────────────────

class PracticeProgress extends StatelessWidget {
  const PracticeProgress({super.key, required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Text(
            l10n.getp('current_total_question_count_2', {
              'current': current,
              'total': total,
            }),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: current / total,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 评估结果面板 ──────────────────────────────────────────────

class EvaluationResultPanel extends StatefulWidget {
  const EvaluationResultPanel({super.key, required this.result, this.topic});

  final Map<String, dynamic> result;
  final Topic? topic;

  @override
  State<EvaluationResultPanel> createState() => EvaluationResultPanelState();
}

class EvaluationResultPanelState extends State<EvaluationResultPanel> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  bool _showReference = false;
  int? _selfScore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final result = widget.result;
    final score = result['score'] as int? ?? 0;
    final missed = result['missedPoints'] as List<dynamic>? ?? [];
    final errors =
        (result['errorPoints'] ?? result['wrongPoints']) as List<dynamic>? ??
        [];
    final optimized =
        (result['optimizedAnswer'] ?? result['improvedAnswer']) as String? ??
        '';
    final summary = result['summary'] as String? ?? '';
    final nextAction = result['nextAction'] as String? ?? '';
    final aiUnavailable = result['aiUnavailable'] == true;

    final referenceAnswer = widget.topic?.learningCards
        .where((c) => c.type == 'interviewAnswer')
        .map((c) => c.content)
        .firstOrNull;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                aiUnavailable ? Icons.save_outlined : Icons.assessment_outlined,
                size: 18,
                color: aiUnavailable ? Colors.grey : AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                aiUnavailable
                    ? l10n.get('local_practice_already_save')
                    : l10n.get('ai_evaluation_result'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (!aiUnavailable) ScoreBadge(score: score),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(summary, style: const TextStyle(height: 1.5)),
          ],

          if (!aiUnavailable) ...[
            Builder(
              builder: (context) {
                final tags = <(String, IconData, Color)>[];
                if (missed.isNotEmpty) {
                  final l10n = context.watch<LocalizationProvider>();
                  tags.add((
                    l10n.get('concept_lack_lose'),
                    Icons.visibility_off_outlined,
                    AppColors.warning,
                  ));
                }
                if (errors.isNotEmpty) {
                  final l10n = context.watch<LocalizationProvider>();
                  tags.add((
                    l10n.get('concept_mix_confuse'),
                    Icons.swap_horiz,
                    AppColors.danger,
                  ));
                }
                if (summary.contains('表达') || summary.contains('结构')) {
                  final l10n = context.watch<LocalizationProvider>();
                  tags.add((
                    l10n.get('expression_not_clarify'),
                    Icons.chat_bubble_outline,
                    AppColors.info,
                  ));
                }
                if (tags.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: tags.map((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: t.$3.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: t.$3.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.$2, size: 14, color: t.$3),
                            const SizedBox(width: 4),
                            Text(
                              t.$1,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: t.$3,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],

          if (aiUnavailable) ...[
            if (referenceAnswer != null && referenceAnswer.isNotEmpty) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => setState(() => _showReference = !_showReference),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lightbulb_outline,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.get('check_view_reference_answer'),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.accent,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _showReference
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: AppColors.accent,
                          ),
                        ],
                      ),
                      if (_showReference) ...[
                        const SizedBox(height: 10),
                        Text(
                          referenceAnswer,
                          style: const TextStyle(height: 1.6, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.get('self_evaluation_mastery_process_degree'),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SelfEvalChip(
                        label: l10n.get('not_too_principle_understand'),
                        icon: Icons.sentiment_dissatisfied,
                        color: AppColors.danger,
                        selected: _selfScore == 0,
                        onTap: () => setState(() => _selfScore = 0),
                      ),
                      const SizedBox(width: 8),
                      SelfEvalChip(
                        label: l10n.get(
                          'department_score_principle_understand',
                        ),
                        icon: Icons.sentiment_neutral,
                        color: AppColors.warning,
                        selected: _selfScore == 1,
                        onTap: () => setState(() => _selfScore = 1),
                      ),
                      const SizedBox(width: 8),
                      SelfEvalChip(
                        label: l10n.get('principle_understand_good'),
                        icon: Icons.sentiment_satisfied,
                        color: AppColors.success,
                        selected: _selfScore == 2,
                        onTap: () => setState(() => _selfScore = 2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (missed.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionHeader(
              icon: Icons.tips_and_updates_outlined,
              label: l10n.get('missed_point'),
              color: AppColors.warning,
            ),
            const SizedBox(height: 8),
            ...missed.map(
              (item) =>
                  BulletPoint(text: item.toString(), color: AppColors.warning),
            ),
          ],
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionHeader(
              icon: Icons.cancel_outlined,
              label: l10n.get('wrong_point'),
              color: AppColors.danger,
            ),
            const SizedBox(height: 8),
            ...errors.map(
              (item) =>
                  BulletPoint(text: item.toString(), color: AppColors.danger),
            ),
          ],
          if (optimized.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionHeader(
              icon: Icons.auto_fix_high_outlined,
              label: l10n.get('optimize_answer'),
              color: AppColors.success,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.15),
                ),
              ),
              child: Text(optimized, style: const TextStyle(height: 1.6)),
            ),
          ],
          if (nextAction.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nextAction,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (widget.topic != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                context.push(
                  '/practice/answer-versions',
                  extra: AnswerVersionsPage(
                    topicId: widget.topic!.id,
                    topicTitle: widget.topic!.title,
                    question: widget.topic!.recallPrompts.isNotEmpty
                        ? widget.topic!.recallPrompts.first.prompt
                        : widget.topic!.title,
                  ),
                );
              },
              icon: const Icon(Icons.library_books_outlined, size: 16),
              label: Text(l10n.get('check_view_answer_version_library')),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 自评 Chip ──────────────────────────────────────────────

class SelfEvalChip extends StatelessWidget {
  const SelfEvalChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? color
                  : Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? color : Colors.grey),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? color : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 区块标题 ──────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ── 圆点列表项 ──────────────────────────────────────────────

class BulletPoint extends StatelessWidget {
  const BulletPoint({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}

// ── 导航按钮 ──────────────────────────────────────────────

class NavigationButtons extends StatelessWidget {
  const NavigationButtons({
    super.key,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton.icon(
            onPressed: hasPrevious ? onPrevious : null,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(l10n.get('prev')),
          ),
          FilledButton.icon(
            onPressed: hasNext ? onNext : null,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(l10n.get('next')),
          ),
        ],
      ),
    );
  }
}

// ── 底部操作条（移动端） ──────────────────────────────────────────────

class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.hasPrevious,
    required this.hasNext,
    required this.isEvaluating,
    required this.hasAnswer,
    required this.hasAi,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
  });

  final bool hasPrevious;
  final bool hasNext;
  final bool isEvaluating;
  final bool hasAnswer;
  final bool hasAi;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              onPressed: hasPrevious ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: (isEvaluating || !hasAnswer) ? null : onSubmit,
                icon: isEvaluating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  isEvaluating
                      ? l10n.get('evaluation_in')
                      : hasAi
                      ? l10n.get('ai_evaluation')
                      : l10n.get('save_practice'),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: hasNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
