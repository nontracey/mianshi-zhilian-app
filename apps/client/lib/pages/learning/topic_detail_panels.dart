import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/voice_input_button.dart';

import 'topic_detail_cards.dart';
import 'topic_detail_page.dart';

// ── 桌面端左侧目录栏 ─────────────────────────────────────────

class LeftSidebar extends StatelessWidget {
  const LeftSidebar({required this.topic});
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (topic.interviewerFocus != null &&
            topic.interviewerFocus!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: AppColors.accent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      l10n.get('interview_official_close_note_point'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  topic.interviewerFocus!,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          l10n.get('knowledge_catalog'),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...topic.learningCards.asMap().entries.map((entry) {
          final card = entry.value;
          final typeIcons = {
            'explain': Icons.article_outlined,
            'interviewAnswer': Icons.auto_awesome,
            'interview': Icons.auto_awesome,
            'checklist': Icons.checklist,
            'code': Icons.code,
            'animation': Icons.animation,
            'diagram': Icons.schema_outlined,
            'svg': Icons.draw_outlined,
            'table': Icons.table_chart_outlined,
            'compareTable': Icons.compare_arrows,
          };
          final icon = typeIcons[card.type] ?? Icons.description_outlined;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(icon, size: 16, color: AppColors.accent),
              title: Text(
                card.title,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              minLeadingWidth: 24,
            ),
          );
        }),
        if (topic.prerequisites.isNotEmpty) ...[
          const Divider(height: 24),
          Text(
            l10n.get('prerequisite_knowledge'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...topic.prerequisites.map(
            (prereq) => PrerequisiteTile(
              key: ValueKey('prereq_$prereq'),
              prereqId: prereq,
            ),
          ),
        ],
        if (topic.leetcodeUrl != null && topic.leetcodeUrl!.isNotEmpty) ...[
          const Divider(height: 24),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.code, size: 16, color: AppColors.success),
            title: Text(
              l10n.get('leetcode_practice'),
              style: TextStyle(fontSize: 13),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            minLeadingWidth: 24,
          ),
        ],
      ],
    );
  }
}

// ── 顶部标签信息 ──────────────────────────────────────────────

class TopicHeader extends StatelessWidget {
  const TopicHeader({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final difficultyLabel = switch (topic.difficulty) {
      1 => l10n.get('beginner'),
      2 => l10n.get('basic'),
      3 => l10n.get('medium'),
      4 => l10n.get('compare_difficult'),
      5 => l10n.get('hard'),
      _ => l10n.get('un_known'),
    };

    final difficultyColor = switch (topic.difficulty) {
      1 => AppColors.success,
      2 => AppColors.accent,
      3 => AppColors.warning,
      4 || 5 => AppColors.danger,
      _ => Colors.grey,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...topic.tags.map(
            (tag) => Chip(
              label: Text(tag, style: const TextStyle(fontSize: 12)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          Chip(
            label: Text(
              difficultyLabel,
              style: TextStyle(fontSize: 12, color: difficultyColor),
            ),
            avatar: Icon(
              Icons.signal_cellular_alt,
              size: 14,
              color: difficultyColor,
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Chip(
            label: Text(
              l10n.getp('minutes_min_2', {'minutes': topic.estimatedMinutes}),
              style: const TextStyle(fontSize: 12),
            ),
            avatar: const Icon(Icons.timer_outlined, size: 14),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          if (topic.highFrequency)
            Chip(
              label: Text(
                topic.interviewFrequencyLabel != null
                    ? l10n.get(topic.interviewFrequencyLabel!)
                    : l10n.get('high_freq'),
                style: TextStyle(
                  fontSize: 12,
                  color: topic.interviewFrequency == 'medium'
                      ? AppColors.warning
                      : topic.interviewFrequency == 'low'
                      ? Colors.grey
                      : AppColors.danger,
                ),
              ),
              avatar: Icon(
                Icons.local_fire_department,
                size: 14,
                color: topic.interviewFrequency == 'medium'
                    ? AppColors.warning
                    : topic.interviewFrequency == 'low'
                    ? Colors.grey
                    : AppColors.danger,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

// ── 知识学习 Tab ──────────────────────────────────────────────

class KnowledgeTab extends StatelessWidget {
  const KnowledgeTab({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        if (topic.interviewerFocus != null &&
            topic.interviewerFocus!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.get('interview_official_close_note_point'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        topic.interviewerFocus!,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        ...topic.learningCards.map(
          (card) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildCard(context, card),
          ),
        ),
        if (topic.rubric != null) ...[
          const SizedBox(height: 8),
          RubricSection(rubric: topic.rubric!),
        ],
        if (topic.followUps.isNotEmpty) ...[
          const SizedBox(height: 8),
          FollowUpSection(followUps: topic.followUps),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCard(BuildContext context, LearningCard card) {
    return switch (card.type) {
      'explain' => ExplainCard(card: card),
      'interviewAnswer' => InterviewAnswerCard(card: card),
      'interview' => InterviewAnswerCard(card: card),
      'checklist' => ChecklistCard(card: card),
      'code' => CodeCard(card: card),
      'animation' => DiagramCard(card: card),
      'diagram' => DiagramCard(card: card),
      'svg' => SvgDiagramCard(card: card),
      'table' => TableCard(card: card),
      'compareTable' => TableCard(card: card),
      _ => GenericCard(card: card),
    };
  }
}

// ── 评分标准面板 ──────────────────────────────────────────────

class RubricSection extends StatelessWidget {
  const RubricSection({required this.rubric});
  final Rubric rubric;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('evaluation_score_standard'),
      children: [
        Text(
          l10n.get('must_cover_key_points'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 8),
        ...rubric.mustHave.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          ),
        ),
        if (rubric.goodToHave.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            l10n.get('plus_score_item'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          ...rubric.goodToHave.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.star_outline, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
        ],
        if (rubric.commonMistakes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            l10n.get('common_wrong'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 8),
          ...rubric.commonMistakes.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cancel_outlined,
                    size: 18,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── 复述练习 Tab（Prompt / Answer 分栏布局）──────────────────

class RecallTab extends StatelessWidget {
  const RecallTab({
    required this.topic,
    required this.answerController,
    required this.isEvaluating,
    required this.isVoiceListening,
    required this.evaluationResult,
    required this.onEvaluate,
    required this.onVoiceListeningChanged,
  });

  final Topic topic;
  final TextEditingController answerController;
  final bool isEvaluating;
  final bool isVoiceListening;
  final Map<String, dynamic>? evaluationResult;
  final VoidCallback onEvaluate;
  final ValueChanged<bool> onVoiceListeningChanged;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: PromptPanel(topic: topic),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AnswerPanel(
                topic: topic,
                answerController: answerController,
                isEvaluating: isEvaluating,
                isVoiceListening: isVoiceListening,
                evaluationResult: evaluationResult,
                onEvaluate: onEvaluate,
                onVoiceListeningChanged: onVoiceListeningChanged,
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PromptPanel(topic: topic),
          const SizedBox(height: 16),
          AnswerPanel(
            topic: topic,
            answerController: answerController,
            isEvaluating: isEvaluating,
            isVoiceListening: isVoiceListening,
            evaluationResult: evaluationResult,
            onEvaluate: onEvaluate,
            onVoiceListeningChanged: onVoiceListeningChanged,
          ),
        ],
      ),
    );
  }
}

// ── 左侧 Prompt 面板 ────────────────────────────────────────

class PromptPanel extends StatelessWidget {
  const PromptPanel({required this.topic});
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.quiz_outlined, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    l10n.get('review_narrate_question'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (topic.recallPrompts.isNotEmpty)
                ...topic.recallPrompts.map(
                  (prompt) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 18,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              prompt.prompt,
                              style: const TextStyle(height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 18,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.get(
                            'use_self_word_explain_this_knowledge_point_7',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (topic.rubric != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.checklist_outlined,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.get('must_mention_key_points'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...topic.rubric!.mustHave.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (topic.rubric!.commonMistakes.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_outlined,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.get('common_wrong'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...topic.rubric!.commonMistakes.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            size: 16,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// ── 右侧 Answer 面板 ────────────────────────────────────────

class AnswerPanel extends StatelessWidget {
  const AnswerPanel({
    required this.topic,
    required this.answerController,
    required this.isEvaluating,
    required this.isVoiceListening,
    required this.evaluationResult,
    required this.onEvaluate,
    required this.onVoiceListeningChanged,
  });

  final Topic topic;
  final TextEditingController answerController;
  final bool isEvaluating;
  final bool isVoiceListening;
  final Map<String, dynamic>? evaluationResult;
  final VoidCallback onEvaluate;
  final ValueChanged<bool> onVoiceListeningChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_outlined, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    l10n.get('your_answer'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    l10n.getp('count_char_2', {
                      'count': answerController.text.length,
                    }),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: answerController,
                minLines: 8,
                maxLines: 16,
                decoration: InputDecoration(
                  hintText: l10n.get(
                    'input_your_recall_answer_here_suggestion',
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isVoiceListening
                          ? Colors.green
                          : const Color(0xFFB0BEC5),
                      width: isVoiceListening ? 2 : 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isVoiceListening
                          ? Colors.green
                          : const Color(0xFFB0BEC5),
                      width: isVoiceListening ? 2 : 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isVoiceListening
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                      width: isVoiceListening ? 2 : 2,
                    ),
                  ),
                  suffixIcon: VoiceInputButton(
                    onResult: (text) {
                      final current = answerController.text;
                      final separator =
                          current.isNotEmpty && !current.endsWith(' ')
                          ? ' '
                          : '';
                      final newValue = '$current$separator$text';
                      answerController.text = newValue;
                      answerController.selection = TextSelection.fromPosition(
                        TextPosition(offset: newValue.length),
                      );
                    },
                    onListeningChanged: onVoiceListeningChanged,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isEvaluating ? null : onEvaluate,
                  icon: isEvaluating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    isEvaluating
                        ? l10n.get('ai_evaluation_in')
                        : l10n.get('gain_fetch_ai_depth_evaluation'),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (evaluationResult != null) ...[
          const SizedBox(height: 16),
          EvaluationResultPanel(result: evaluationResult!),
        ],
      ],
    );
  }
}

// ── AI 评估结果面板（含环形分数 + feedback tags）───────────────

class EvaluationResultPanel extends StatelessWidget {
  const EvaluationResultPanel({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final score = result['score'] as int? ?? 0;
    final missed = result['missedPoints'] as List<dynamic>? ?? [];
    final errors =
        (result['errorPoints'] ?? result['wrongPoints']) as List<dynamic>? ??
        [];
    final optimized =
        (result['optimizedAnswer'] ?? result['improvedAnswer']) as String? ??
        '';
    final feedbackTags = result['feedbackTags'] as List<dynamic>? ?? [];
    final summary = result['summary'] as String? ?? '';
    final aiUnavailable = result['aiUnavailable'] == true;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                aiUnavailable ? Icons.save_outlined : Icons.assessment_outlined,
                color: aiUnavailable ? Colors.grey : AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                aiUnavailable
                    ? l10n.get('local_practice_already_save')
                    : l10n.get('ai_evaluation_result'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (summary.isNotEmpty) ...[
            Text(summary, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 14),
          ],
          if (!aiUnavailable)
            Row(
              children: [
                ScoreRing(score: score, size: 80),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScoreBadge(score: score),
                      if (feedbackTags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: feedbackTags
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    tag.toString(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          if (aiUnavailable)
            Text(
              l10n.get('ai_not_configured_summary'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.get('missed_point'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 6),
            ...missed.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              ),
            ),
          ],
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.get('wrong_point'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 6),
            ...errors.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cancel_outlined,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              ),
            ),
          ],
          if (optimized.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.get('optimize_answer'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(optimized, style: const TextStyle(height: 1.6)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 环形分数组件 ──────────────────────────────────────────────

class ScoreRing extends StatelessWidget {
  const ScoreRing({required this.score, this.size = 80});

  final int score;
  final double size;

  Color get _color {
    if (score >= 85) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return AppColors.textTertiary;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 6,
              color: Colors.grey.shade200,
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 6,
              color: _color,
              backgroundColor: Colors.transparent,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.w900,
                  color: _color,
                ),
              ),
              Text(
                l10n.get('score'),
                style: TextStyle(fontSize: size * 0.12, color: _color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 前置知识条目（异步解析）──────────────────────────────────

class PrerequisiteTile extends StatefulWidget {
  final String prereqId;

  const PrerequisiteTile({required this.prereqId, super.key});

  @override
  State<PrerequisiteTile> createState() => PrerequisiteTileState();
}

class PrerequisiteTileState extends State<PrerequisiteTile> {
  Topic? _topic;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final provider = context.read<ContentProvider>();
    final topic = await provider.resolvePrerequisiteTopic(widget.prereqId);
    if (mounted) {
      setState(() {
        _topic = topic;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _topic?.title ?? widget.prereqId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: _topic != null
            ? () {
                context.push(
                  '/topic',
                  extra: TopicDetailPage(
                    topic: _topic!,
                    onBack: () => Navigator.pop(context),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: [
            const Icon(Icons.arrow_right, size: 16, color: AppColors.warning),
            const SizedBox(width: 4),
            Expanded(
              child: _isLoading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: _topic != null
                            ? AppColors.accent
                            : AppColors.warning,
                        decoration: _topic != null
                            ? TextDecoration.underline
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
