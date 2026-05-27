import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/widgets/voice_input_button.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class MockInterviewPage extends StatefulWidget {
  const MockInterviewPage({
    super.key,
    required this.topicIds,
  });

  final List<String> topicIds;

  @override
  State<MockInterviewPage> createState() => _MockInterviewPageState();
}

class _MockInterviewPageState extends State<MockInterviewPage> {
  final _answerController = TextEditingController();
  int _currentIndex = 0;
  bool _isEvaluating = false;
  Map<String, dynamic>? _evaluationResult;
  final List<Map<String, dynamic>> _results = [];
  bool _isCompleted = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Topic? _getCurrentTopic() {
    if (_currentIndex >= widget.topicIds.length) return null;
    final contentProvider = context.read<ContentProvider>();
    return contentProvider.findTopic(widget.topicIds[_currentIndex]);
  }

  Future<void> _evaluate() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入你的回答')),
      );
      return;
    }

    final topic = _getCurrentTopic();
    if (topic == null) return;

    final aiProvider = context.read<AiProvider>();
    if (aiProvider.defaultConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在个人中心配置 AI')),
      );
      return;
    }

    setState(() => _isEvaluating = true);

    try {
      final result = await aiProvider.evaluateAnswer(
        topicId: topic.id,
        question: topic.recallPrompts.isNotEmpty
            ? topic.recallPrompts.first.prompt
            : topic.title,
        userAnswer: answer,
        rubric: topic.rubric,
      );

      if (mounted) {
        setState(() {
          _evaluationResult = result;
          _results.add({
            'topicId': topic.id,
            'topicTitle': topic.title,
            'score': result['score'] ?? 0,
            'answer': answer,
          });
        });

        // 更新进度
        final progressProvider = context.read<ProgressProvider>();
        final score = result['score'] as int? ?? 0;
        await progressProvider.updateTopicProgress(topic.id, score: score);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI 评估失败：$e'),
            action: SnackBarAction(label: '重试', onPressed: _evaluate),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }

  void _nextQuestion() {
    if (_currentIndex < widget.topicIds.length - 1) {
      setState(() {
        _currentIndex++;
        _answerController.clear();
        _evaluationResult = null;
      });
    } else {
      setState(() => _isCompleted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.topicIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('模拟面试')),
        body: const Center(child: Text('没有可用的知识点')),
      );
    }

    if (_isCompleted) {
      return _buildResultPage();
    }

    final topic = _getCurrentTopic();
    if (topic == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('模拟面试')),
        body: const Center(child: Text('知识点加载失败')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('模拟面试 (${_currentIndex + 1}/${widget.topicIds.length})'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '得分: ${_results.fold(0, (sum, r) => sum + (r['score'] as int))}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // 进度条
          LinearProgressIndicator(
            value: (_currentIndex + 1) / widget.topicIds.length,
            backgroundColor: Colors.grey.shade200,
          ),
          const SizedBox(height: 24),

          // 题目
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.quiz, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      '问题 ${_currentIndex + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  topic.recallPrompts.isNotEmpty
                      ? topic.recallPrompts.first.prompt
                      : '请解释 ${topic.title} 的核心概念',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  topic.title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 输入区
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit_note),
                    const SizedBox(width: 8),
                    const Text(
                      '你的回答',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      '${_answerController.text.length} 字',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _answerController,
                  minLines: 6,
                  maxLines: 12,
                  decoration: InputDecoration(
                    hintText: '请输入你的回答...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: VoiceInputButton(
                      onResult: (text) {
                        _answerController.text += text;
                      },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
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
                    label: Text(_isEvaluating ? 'AI 评估中...' : '提交并评估'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 评估结果
          if (_evaluationResult != null) ...[
            const SizedBox(height: 20),
            _buildEvaluationResult(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _nextQuestion,
                child: Text(
                  _currentIndex < widget.topicIds.length - 1
                      ? '下一题'
                      : '查看结果',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEvaluationResult() {
    final score = _evaluationResult!['score'] as int? ?? 0;
    final summary = _evaluationResult!['summary'] as String? ?? '';
    final missed = _evaluationResult!['missedPoints'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assessment),
              const SizedBox(width: 8),
              const Text(
                '评估结果',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              ScoreBadge(score: score),
            ],
          ),
          const SizedBox(height: 12),
          Text(summary),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '遗漏点：',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            ...missed.map((p) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $p'),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildResultPage() {
    final totalScore = _results.fold(0, (sum, r) => sum + (r['score'] as int));
    final avgScore = _results.isEmpty ? 0 : totalScore ~/ _results.length;

    return Scaffold(
      appBar: AppBar(title: const Text('模拟面试结果')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // 总分
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  '面试完成！',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$avgScore',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: avgScore >= 85
                        ? AppColors.success
                        : avgScore >= 60
                            ? AppColors.warning
                            : AppColors.danger,
                  ),
                ),
                const Text(
                  '平均分',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '共 ${_results.length} 题',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 各题得分
          const Text(
            '各题得分',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ..._results.asMap().entries.map((entry) {
            final index = entry.key;
            final result = entry.value;
            final score = result['score'] as int;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: score >= 85
                    ? AppColors.success
                    : score >= 60
                        ? AppColors.warning
                        : AppColors.danger,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(result['topicTitle'] as String),
              trailing: Text(
                '$score 分',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: score >= 85
                      ? AppColors.success
                      : score >= 60
                          ? AppColors.warning
                          : AppColors.danger,
                ),
              ),
            );
          }),
          const SizedBox(height: 24),

          // 返回按钮
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
