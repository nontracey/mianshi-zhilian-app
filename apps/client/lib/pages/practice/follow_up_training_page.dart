import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/l10n/l10n.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class FollowUpTrainingPage extends StatefulWidget {
  const FollowUpTrainingPage({super.key, required this.topicIds});

  final List<String> topicIds;

  @override
  State<FollowUpTrainingPage> createState() => _FollowUpTrainingPageState();
}

class _FollowUpTrainingPageState extends State<FollowUpTrainingPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();

  int _currentTopicIndex = 0;
  int _currentFollowUpIndex = -1; // -1 表示初始问题
  final _answerController = TextEditingController();
  bool _isEvaluating = false;
  Map<String, dynamic>? _evaluationResult;
  bool _showHint = false;
  int _hintLevel = 0; // 0: 未显示, 1: 方向提示, 2: 关键词, 3: 结构提示
  final List<Map<String, dynamic>> _answers = [];
  final Map<String, int> _recallPromptSeeds = {};
  bool _isCompleted = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Topic? _getCurrentTopic() {
    if (_currentTopicIndex >= widget.topicIds.length) return null;
    final contentProvider = context.read<ContentProvider>();
    return contentProvider.findTopic(widget.topicIds[_currentTopicIndex]);
  }

  FollowUpQuestion? _getCurrentFollowUp() {
    final topic = _getCurrentTopic();
    if (topic == null || topic.followUps.isEmpty) return null;
    if (_currentFollowUpIndex < 0 ||
        _currentFollowUpIndex >= topic.followUps.length) {
      return null;
    }
    return topic.followUps[_currentFollowUpIndex];
  }

  RecallPrompt? _getCurrentRecallPrompt() {
    final topic = _getCurrentTopic();
    if (topic == null) return null;
    final seed = _recallPromptSeeds.putIfAbsent(topic.id, () {
      return context
          .read<ProgressProvider>()
          .getAttemptsForTopic(topic.id)
          .length;
    });
    return topic.recallPromptAt(seed);
  }

  String _getCurrentQuestion() {
    final topic = _getCurrentTopic();
    if (topic == null) return '';

    if (_currentFollowUpIndex < 0) {
      return _getCurrentRecallPrompt()?.prompt ?? topic.title;
    }

    final followUp = _getCurrentFollowUp();
    return followUp?.question ?? '';
  }

  List<String> _getCurrentHints() {
    final followUp = _getCurrentFollowUp();
    if (followUp != null && followUp.hints.isNotEmpty) {
      return followUp.hints;
    }
    return [];
  }

  void _nextQuestion() {
    final topic = _getCurrentTopic();
    if (topic == null) return;

    setState(() {
      _answerController.clear();
      _evaluationResult = null;
      _showHint = false;
      _hintLevel = 0;

      if (_currentFollowUpIndex < topic.followUps.length - 1) {
        _currentFollowUpIndex++;
      } else {
        // 当前主题的追问完成，进入下一个主题
        if (_currentTopicIndex < widget.topicIds.length - 1) {
          _currentTopicIndex++;
          _currentFollowUpIndex = -1;
        } else {
          _isCompleted = true;
        }
      }
    });
  }

  void _showNextHint() {
    final hints = _getCurrentHints();
    if (hints.isEmpty) {
      // 没有预设提示，使用渐进提示
      setState(() {
        _hintLevel++;
        _showHint = true;
      });
    } else {
      // 使用预设提示
      setState(() {
        _showHint = true;
        if (_hintLevel < hints.length) {
          _hintLevel++;
        }
      });
    }
  }

  String _getProgressiveHint() {
    switch (_hintLevel) {
      case 1:
        return l10n.get('progressive_hint_core_concept');
      case 2:
        return l10n.get('progressive_hint_definition_features');
      case 3:
        return l10n.get('progressive_hint_answer_structure');
      default:
        return '';
    }
  }

  Future<void> _evaluate() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('please_first_input_your_answer'))),
      );
      return;
    }

    final aiProvider = context.read<AiProvider>();
    if (!aiProvider.hasAnyConfig) {
      // 没有启用任何 AI 配置，保存为本地练习
      await _saveLocalAnswer(answer);
      return;
    }

    setState(() => _isEvaluating = true);

    try {
      final question = _getCurrentQuestion();
      final topic = _getCurrentTopic();

      final result = await aiProvider.evaluateAnswer(
        topicId: topic?.id ?? '',
        question: question,
        userAnswer: answer,
        rubric: topic?.rubric,
      );

      if (mounted) {
        setState(() {
          _evaluationResult = result;
          _answers.add({
            'topicId': topic?.id,
            'question': question,
            'answer': answer,
            'score': result['score'] ?? 0,
            'isFollowUp': _currentFollowUpIndex >= 0,
            'followUpIndex': _currentFollowUpIndex,
          });
        });
        // 持久化为练习记录并更新掌握度/复习排期，使追问训练对掌握度、薄弱检测、
        // 连续天数可见（此前该模式评估结果不落任何数据）。
        await _persistAttempt(topic, question, answer, result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.getp('evaluation_fail_error_2', {'error': '$e'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }

  /// 将一次追问训练评估落为练习记录，并在 AI 给出有效分数时更新掌握度。
  /// 沿用 recall_page 的写法，mode 标记为 'follow_up'。
  Future<void> _persistAttempt(
    Topic? topic,
    String question,
    String answer,
    Map<String, dynamic> result,
  ) async {
    final topicId = topic?.id ?? '';
    if (topicId.isEmpty) return;
    final progressProvider = context.read<ProgressProvider>();
    final aiProvider = context.read<AiProvider>();
    final score = result['score'] as int?;
    final aiEvaluated = result['aiUnavailable'] != true;

    await progressProvider.addAttempt(
      PracticeAttempt(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        topicId: topicId,
        promptId: _currentFollowUpIndex < 0
            ? _getCurrentRecallPrompt()?.id ?? ''
            : '',
        mode: 'follow_up',
        question: question,
        answer: answer,
        createdAt: DateTime.now(),
        score: score,
        level: result['level'] as String?,
        summary: result['summary'] as String?,
        missedPoints:
            (result['missedPoints'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        wrongPoints:
            ((result['wrongPoints'] ?? result['errorPoints']) as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        improvedAnswer:
            (result['improvedAnswer'] ?? result['optimizedAnswer']) as String?,
        nextAction: result['nextAction'] as String?,
        aiConfigId: aiProvider.defaultConfig?.id,
        aiEvaluated: aiEvaluated,
        localOnly: !aiEvaluated,
        analysisStatus: aiEvaluated && score != null ? 'success' : 'unanalysed',
      ),
    );
    if (aiEvaluated && score != null) {
      await progressProvider.updateTopicProgress(topicId, score: score);
    }
  }

  Future<void> _saveLocalAnswer(String answer) async {
    final topic = _getCurrentTopic();
    final question = _getCurrentQuestion();
    try {
      await _persistAttempt(topic, question, answer, {'aiUnavailable': true});
      if (!mounted) return;
      setState(() {
        _answers.add({
          'topicId': topic?.id,
          'question': question,
          'answer': answer,
          'score': null,
          'isFollowUp': _currentFollowUpIndex >= 0,
          'followUpIndex': _currentFollowUpIndex,
        });
        _evaluationResult = {
          'local': true,
          'message': L10n.get('saved_as_local_practice', L10n.currentLanguage),
        };
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('storage_write_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompleted) {
      return _buildCompletionScreen();
    }

    final topic = _getCurrentTopic();
    if (topic == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.get('follow_up_training'))),
        body: Center(
          child: Text(l10n.get('not_has_optional_practice_knowledge_point')),
        ),
      );
    }

    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_currentTopicIndex + 1}/${widget.topicIds.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(l10n.get('follow_up_training')),
          ],
        ),
        actions: [
          // 追问进度
          if (topic.followUps.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${l10n.get('follow_up')} ${_currentFollowUpIndex + 1}/${topic.followUps.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppColors.success,
                ),
              ),
            ),
        ],
      ),
      body: isDesktop
          ? _buildDesktopLayout(context, topic)
          : _buildMobileLayout(context, topic),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, Topic topic) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：问题和评分标准
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildQuestionCard(context, topic),
              if (topic.rubric != null) ...[
                const SizedBox(height: 16),
                _buildRubricCard(context, topic.rubric!),
              ],
              if (_showHint) ...[
                const SizedBox(height: 16),
                _buildHintCard(context),
              ],
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 右侧：输入和结果
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildInputSection(context),
              if (_evaluationResult != null) ...[
                const SizedBox(height: 16),
                _buildResultCard(context),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, Topic topic) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildQuestionCard(context, topic),
        const SizedBox(height: 12),
        if (_showHint) ...[_buildHintCard(context), const SizedBox(height: 12)],
        _buildInputSection(context),
        if (_evaluationResult != null) ...[
          const SizedBox(height: 16),
          _buildResultCard(context),
        ],
      ],
    );
  }

  Widget _buildQuestionCard(BuildContext context, Topic topic) {
    final question = _getCurrentQuestion();
    final isFollowUp = _currentFollowUpIndex >= 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFollowUp
              ? AppColors.accent.withValues(alpha: 0.3)
              : Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isFollowUp
                        ? AppColors.accent.withValues(alpha: 0.1)
                        : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isFollowUp
                        ? l10n.get('follow_up')
                        : l10n.get('main_question'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isFollowUp ? AppColors.accent : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    topic.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 问题内容
            Text(
              question,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            // 难度标签
            if (isFollowUp) ...[
              const SizedBox(height: 8),
              _buildDifficultyTag(_getCurrentFollowUp()?.difficulty ?? 2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDifficultyTag(int difficulty) {
    final labels = {
      1: l10n.get('beginner'),
      2: l10n.get('basic'),
      3: l10n.get('medium'),
      4: l10n.get('compare_difficult'),
      5: l10n.get('hard'),
    };
    final colors = {
      1: const Color(0xFF10B981),
      2: const Color(0xFF00CCF9),
      3: const Color(0xFFF59E0B),
      4: const Color(0xFFEF4444),
      5: const Color(0xFF7C3AED),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (colors[difficulty] ?? Colors.grey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        labels[difficulty] ?? l10n.get('un_known'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colors[difficulty] ?? Colors.grey,
        ),
      ),
    );
  }

  Widget _buildRubricCard(BuildContext context, Rubric rubric) {
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
              l10n.get('evaluation_score_standard'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (rubric.mustHave.isNotEmpty) ...[
              _buildRubricSection(
                l10n.get('must_include'),
                rubric.mustHave,
                AppColors.danger,
              ),
              const SizedBox(height: 8),
            ],
            if (rubric.goodToHave.isNotEmpty) ...[
              _buildRubricSection(
                l10n.get('plus_score_item'),
                rubric.goodToHave,
                AppColors.success,
              ),
              const SizedBox(height: 8),
            ],
            if (rubric.commonMistakes.isNotEmpty) ...[
              _buildRubricSection(
                l10n.get('common_wrong'),
                rubric.commonMistakes,
                AppColors.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRubricSection(String title, List<String> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: color, fontSize: 12)),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHintCard(BuildContext context) {
    final hints = _getCurrentHints();
    String hintText;

    if (hints.isNotEmpty && _hintLevel > 0 && _hintLevel <= hints.length) {
      hintText = hints[_hintLevel - 1];
    } else {
      hintText = _getProgressiveHint();
    }

    return Card(
      elevation: 0,
      color: AppColors.warning.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  '${l10n.get('hint')} ($_hintLevel/${hints.isNotEmpty ? hints.length : 3})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(hintText, style: const TextStyle(fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection(BuildContext context) {
    final aiProvider = context.watch<AiProvider>();
    final hasAi = aiProvider.enabledConfigs.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 输入模式提示
        Row(
          children: [
            const Icon(Icons.edit_outlined, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              l10n.get('your_answer'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            // 提示按钮
            TextButton.icon(
              onPressed: _showNextHint,
              icon: const Icon(Icons.lightbulb_outline, size: 14),
              label: Text(
                l10n.get('hint'),
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 输入框
        TextField(
          controller: _answerController,
          maxLines: 8,
          minLines: 4,
          decoration: InputDecoration(
            hintText: l10n.get('input_your_answer'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(14),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        // 提交按钮
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isEvaluating ? null : _evaluate,
            icon: _isEvaluating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _isEvaluating
                  ? l10n.get('evaluation_in')
                  : hasAi
                  ? l10n.get('gain_fetch_ai_evaluation')
                  : l10n.get('save_local_practice'),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (!hasAi) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.get('no_ai_will_save_locally'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _buildResultCard(BuildContext context) {
    final isLocal = _evaluationResult?['local'] == true;
    final score = _evaluationResult?['score'] ?? 0;
    final summary = _evaluationResult?['summary'] ?? '';
    final missedPoints =
        (_evaluationResult?['missedPoints'] as List?)?.cast<String>() ?? [];
    final wrongPoints =
        (_evaluationResult?['wrongPoints'] as List?)?.cast<String>() ?? [];
    final improvedAnswer = _evaluationResult?['improvedAnswer'] ?? '';

    final scoreColor = score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scoreColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和分数
            Row(
              children: [
                Text(
                  l10n.get('evaluation_result'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (!isLocal) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.getp('score_score_2', {'score': '$score'}),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: scoreColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // 本地保存提示
            if (isLocal) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.get('already_save_as_local_practice'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],

            // 摘要
            if (summary.isNotEmpty) ...[
              Text(summary, style: const TextStyle(fontSize: 13, height: 1.5)),
              const SizedBox(height: 12),
            ],

            // 遗漏点
            if (missedPoints.isNotEmpty) ...[
              _buildPointsSection(
                l10n.get('missed_point'),
                missedPoints,
                AppColors.warning,
              ),
              const SizedBox(height: 8),
            ],

            // 错误点
            if (wrongPoints.isNotEmpty) ...[
              _buildPointsSection(
                l10n.get('wrong_point'),
                wrongPoints,
                AppColors.danger,
              ),
              const SizedBox(height: 8),
            ],

            // 优化回答
            if (improvedAnswer.isNotEmpty) ...[
              Text(
                l10n.get('reference_answer'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  improvedAnswer,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],

            const SizedBox(height: 16),
            // 下一步按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _nextQuestion,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(l10n.get('next_question_count')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointsSection(String title, List<String> points, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        ...points.map(
          (point) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: color, fontSize: 12)),
                Expanded(
                  child: Text(
                    point,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionScreen() {
    final totalQuestions = _answers.length;
    final scoredAnswers = _answers.where((a) => a['score'] != null).toList();
    final avgScore = scoredAnswers.isNotEmpty
        ? scoredAnswers.fold<int>(0, (sum, a) => sum + (a['score'] as int)) ~/
              scoredAnswers.length
        : 0;
    final followUpCount = _answers.where((a) => a['isFollowUp'] == true).length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('follow_up_training_complete'))),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 64,
                color: AppColors.success,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.get('follow_up_training_complete_excl'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 24),
              // 统计卡片
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem(
                    l10n.get('total_question_count'),
                    '$totalQuestions',
                  ),
                  _buildStatItem(l10n.get('follow_up_count'), '$followUpCount'),
                  if (scoredAnswers.isNotEmpty)
                    _buildStatItem(l10n.get('flat_average_score'), '$avgScore'),
                ],
              ),
              const SizedBox(height: 32),
              // 操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.get('back')),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _currentTopicIndex = 0;
                        _currentFollowUpIndex = -1;
                        _answers.clear();
                        _isCompleted = false;
                        _answerController.clear();
                        _evaluationResult = null;
                      });
                    },
                    child: Text(l10n.get('practice_again_round')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
