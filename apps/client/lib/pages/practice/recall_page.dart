import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class RecallPage extends StatefulWidget {
  const RecallPage({
    super.key,
    required this.topicIds,
  });

  final List<String> topicIds;

  @override
  State<RecallPage> createState() => _RecallPageState();
}

class _RecallPageState extends State<RecallPage> {
  int _currentIndex = 0;
  final _answerController = TextEditingController();
  bool _isEvaluating = false;
  Map<String, dynamic>? _evaluationResult;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.topicIds.isEmpty) {
      return const Center(child: Text('没有可练习的知识点'));
    }

    final contentProvider = context.watch<ContentProvider>();
    final topic = contentProvider.getTopicById(widget.topicIds[_currentIndex]);

    if (topic == null) {
      return const Center(child: Text('知识点未找到'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProgressIndicator(
          current: _currentIndex + 1,
          total: widget.topicIds.length,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              WorkPanel(
                title: topic.title,
                children: [
                  Text(
                    topic.recallPrompts.isNotEmpty
                        ? topic.recallPrompts.first
                        : '请用自己的话解释 ${topic.title} 的核心内容。',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              WorkPanel(
                title: '你的回答',
                children: [
                  TextField(
                    controller: _answerController,
                    minLines: 6,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: '在这里输入你的复述答案...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isEvaluating ? null : _handleEvaluate,
                    icon: _isEvaluating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(_isEvaluating ? '评估中...' : '获取 AI 深度评估'),
                  ),
                ],
              ),
              if (_evaluationResult != null) ...[
                const SizedBox(height: 16),
                _EvaluationResultPanel(result: _evaluationResult!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _NavigationButtons(
          hasPrevious: _currentIndex > 0,
          hasNext: _currentIndex < widget.topicIds.length - 1,
          onPrevious: _goPrevious,
          onNext: _goNext,
        ),
      ],
    );
  }

  Future<void> _handleEvaluate() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) return;

    setState(() => _isEvaluating = true);

    try {
      final aiProvider = context.read<AiProvider>();
      final contentProvider = context.read<ContentProvider>();
      final topicId = widget.topicIds[_currentIndex];
      final topic = contentProvider.getTopicById(topicId);
      if (topic == null) return;

      final result = await aiProvider.evaluateAnswer(
        topicId: topicId,
        question: topic.recallPrompts.isNotEmpty ? topic.recallPrompts.first : topic.title,
        userAnswer: answer,
        rubric: topic.rubric,
      );

      if (mounted) {
        setState(() => _evaluationResult = result);
        final progressProvider = context.read<ProgressProvider>();
        final score = result['score'] as int? ?? 0;
        await progressProvider.updateTopicProgress(
          topicId,
          score: score,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('评估失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _answerController.clear();
        _evaluationResult = null;
      });
    }
  }

  void _goNext() {
    if (_currentIndex < widget.topicIds.length - 1) {
      setState(() {
        _currentIndex++;
        _answerController.clear();
        _evaluationResult = null;
      });
    }
  }
}

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({
    required this.current,
    required this.total,
  });

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '第 $current / $total 题',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: LinearProgressIndicator(value: current / total),
        ),
      ],
    );
  }
}

class _EvaluationResultPanel extends StatelessWidget {
  const _EvaluationResultPanel({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final score = result['score'] as int? ?? 0;
    final missed = result['missedPoints'] as List<dynamic>? ?? [];
    final errors = result['errorPoints'] as List<dynamic>? ?? [];
    final optimized = result['optimizedAnswer'] as String? ?? '';

    return WorkPanel(
      title: 'AI 评估结果',
      children: [
        ScoreBadge(score: score),
        if (missed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '遗漏点',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning),
          ),
          const SizedBox(height: 6),
          ...missed.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.tips_and_updates_outlined, size: 18, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              )),
        ],
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '错误点',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
          ),
          const SizedBox(height: 6),
          ...errors.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cancel_outlined, size: 18, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              )),
        ],
        if (optimized.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '优化回答',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(optimized),
          ),
        ],
      ],
    );
  }
}

class _NavigationButtons extends StatelessWidget {
  const _NavigationButtons({
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        OutlinedButton.icon(
          onPressed: hasPrevious ? onPrevious : null,
          icon: const Icon(Icons.arrow_back),
          label: const Text('上一个'),
        ),
        FilledButton.icon(
          onPressed: hasNext ? onNext : null,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('下一个'),
        ),
      ],
    );
  }
}
