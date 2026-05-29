import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/widgets/voice_input_button.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class MockInterviewPage extends StatefulWidget {
  const MockInterviewPage({super.key, required this.topicIds});

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
  bool _formalMode = false;
  bool _savedSession = false;
  String _scenario = 'mixed';
  late final DateTime _startedAt = DateTime.now();

  late DateTime _questionStartTime;
  final List<int> _questionDurations = [];
  late final Stopwatch _overallTimer = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _questionStartTime = DateTime.now();
  }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入你的回答')));
      return;
    }

    final topic = _getCurrentTopic();
    if (topic == null) return;

    final aiProvider = context.read<AiProvider>();
    if (aiProvider.defaultConfig == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在个人中心配置 AI')));
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
            'question': topic.recallPrompts.isNotEmpty
                ? topic.recallPrompts.first.prompt
                : topic.title,
            'summary': result['summary'] ?? '',
            'missedPoints': result['missedPoints'] ?? [],
            'wrongPoints': result['wrongPoints'] ?? result['errorPoints'] ?? [],
            'improvedAnswer':
                result['improvedAnswer'] ?? result['optimizedAnswer'] ?? '',
            'nextAction': result['nextAction'] ?? '',
            'aiUnavailable': result['aiUnavailable'] == true,
          });
        });

        final progressProvider = context.read<ProgressProvider>();
        final score = result['score'] as int? ?? 0;
        await progressProvider.addAttempt(
          PracticeAttempt(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            topicId: topic.id,
            promptId: topic.recallPrompts.isNotEmpty
                ? topic.recallPrompts.first.id
                : '',
            mode: 'mockInterview',
            question: topic.recallPrompts.isNotEmpty
                ? topic.recallPrompts.first.prompt
                : topic.title,
            answer: answer,
            createdAt: DateTime.now(),
            score: result['score'] as int?,
            level: result['level'] as String?,
            summary: result['summary'] as String?,
            missedPoints:
                (result['missedPoints'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            wrongPoints:
                ((result['wrongPoints'] ?? result['errorPoints'])
                        as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            improvedAnswer:
                (result['improvedAnswer'] ?? result['optimizedAnswer'])
                    as String?,
            nextAction: result['nextAction'] as String?,
            aiEvaluated: result['aiUnavailable'] != true,
          ),
        );
        if (result['score'] is int) {
          await progressProvider.updateTopicProgress(topic.id, score: score);
        }
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
    final elapsed = DateTime.now().difference(_questionStartTime).inSeconds;
    _questionDurations.add(elapsed);

    if (_currentIndex < widget.topicIds.length - 1) {
      setState(() {
        _currentIndex++;
        _answerController.clear();
        _evaluationResult = null;
        _questionStartTime = DateTime.now();
      });
    } else {
      _overallTimer.stop();
      setState(() => _isCompleted = true);
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;

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
                '${_currentIndex + 1}/${widget.topicIds.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('模拟面试'),
          ],
        ),
        actions: [
          // 计时器
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (context, _) {
              final elapsed = _overallTimer.elapsed.inSeconds;
              final isOvertime = elapsed > 1800;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isOvertime
                      ? AppColors.danger.withValues(alpha: 0.12)
                      : AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 15,
                      color: isOvertime ? AppColors.danger : AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(elapsed),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: isOvertime ? AppColors.danger : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // 累计得分
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.stars_outlined,
                  size: 15,
                  color: AppColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_results.fold(0, (sum, r) => sum + (r['score'] as int))}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: isDesktop
          ? _buildDesktopInterviewLayout(topic)
          : _buildMobileInterviewLayout(topic),
    );
  }

  // ── 桌面端面试房间布局 ──
  Widget _buildDesktopInterviewLayout(Topic topic) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：题目 + 面试官关注点
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildQuestionCard(topic),
              if (_currentIndex == 0 && _results.isEmpty) ...[
                const SizedBox(height: 16),
                _buildSetupPanel(),
              ],
            ],
          ),
        ),
        // 右侧：输入 + 评估
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildInputSection(),
                    if (_evaluationResult != null) ...[
                      const SizedBox(height: 20),
                      if (_formalMode)
                        _buildFormalRecorded()
                      else
                        _buildEvaluationResult(),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _nextQuestion,
                          icon: Icon(
                            _currentIndex < widget.topicIds.length - 1
                                ? Icons.arrow_forward
                                : Icons.emoji_events_outlined,
                          ),
                          label: Text(
                            _currentIndex < widget.topicIds.length - 1
                                ? '下一题'
                                : '查看面试报告',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 移动端面试房间布局 ──
  Widget _buildMobileInterviewLayout(Topic topic) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_currentIndex + 1) / widget.topicIds.length,
            backgroundColor: Colors.grey.shade200,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 16),
        if (_currentIndex == 0 && _results.isEmpty) ...[
          _buildSetupPanel(),
          const SizedBox(height: 16),
        ],
        _buildQuestionCard(topic),
        const SizedBox(height: 16),
        _buildInputSection(),
        if (_evaluationResult != null) ...[
          const SizedBox(height: 16),
          if (_formalMode)
            _buildFormalRecorded()
          else
            _buildEvaluationResult(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _nextQuestion,
              icon: Icon(
                _currentIndex < widget.topicIds.length - 1
                    ? Icons.arrow_forward
                    : Icons.emoji_events_outlined,
              ),
              label: Text(
                _currentIndex < widget.topicIds.length - 1
                    ? '下一题'
                    : '查看面试报告',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // ── 题目卡片 ──
  Widget _buildQuestionCard(Topic topic) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.quiz_outlined,
                      size: 13,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '问题 ${_currentIndex + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                topic.title,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            topic.recallPrompts.isNotEmpty
                ? topic.recallPrompts.first.prompt
                : '请解释 ${topic.title} 的核心概念',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.5,
              color: Colors.white,
            ),
          ),
          if (topic.interviewerFocus?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '面试官关注：${topic.interviewerFocus}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
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

  // ── 输入区 ──
  Widget _buildInputSection() {
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
              const Icon(Icons.edit_note_outlined, size: 18),
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
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
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
    );
  }

  Widget _buildSetupPanel() {
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
          const Text(
            '面试设置',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ScenarioChip(
                label: '混合',
                value: 'mixed',
                selected: _scenario == 'mixed',
                onSelected: (value) => setState(() => _scenario = value),
              ),
              _ScenarioChip(
                label: '基础知识',
                value: 'foundation',
                selected: _scenario == 'foundation',
                onSelected: (value) => setState(() => _scenario = value),
              ),
              _ScenarioChip(
                label: '系统设计',
                value: 'systemDesign',
                selected: _scenario == 'systemDesign',
                onSelected: (value) => setState(() => _scenario = value),
              ),
              _ScenarioChip(
                label: '代码题',
                value: 'code',
                selected: _scenario == 'code',
                onSelected: (value) => setState(() => _scenario = value),
              ),
              _ScenarioChip(
                label: '项目深挖',
                value: 'project',
                selected: _scenario == 'project',
                onSelected: (value) => setState(() => _scenario = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _formalMode,
            title: const Text('正式模拟模式'),
            subtitle: const Text('逐题不展示详细反馈，结束后统一复盘'),
            onChanged: (value) => setState(() => _formalMode = value),
          ),
        ],
      ),
    );
  }

  Widget _buildFormalRecorded() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.accent),
          SizedBox(width: 8),
          Expanded(child: Text('回答已记录。正式模拟模式将在结束后统一展示报告。')),
        ],
      ),
    );
  }

  Widget _buildEvaluationResult() {
    final score = _evaluationResult!['score'] as int? ?? 0;
    final summary = _evaluationResult!['summary'] as String? ?? '';
    final missed = _evaluationResult!['missedPoints'] as List<dynamic>? ?? [];
    final wrong =
        (_evaluationResult!['wrongPoints'] ?? _evaluationResult!['errorPoints'])
            as List<dynamic>? ??
        [];
    final improved =
        (_evaluationResult!['improvedAnswer'] ??
                _evaluationResult!['optimizedAnswer'])
            as String? ??
        '';
    final nextAction = _evaluationResult!['nextAction'] as String? ?? '';

    final topic = _getCurrentTopic();
    final weights = topic?.rubric?.scoreWeights;

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
              const Icon(Icons.assessment_outlined, size: 18),
              const SizedBox(width: 8),
              const Text(
                '评估结果',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              ScoreBadge(score: score),
            ],
          ),
          const SizedBox(height: 16),
          if (weights != null && weights.isNotEmpty) ...[
            _buildDimensionScores(score, weights),
            const SizedBox(height: 16),
          ],
          Text(summary, style: const TextStyle(height: 1.5)),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPointList('遗漏点', missed, AppColors.warning),
          ],
          if (wrong.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPointList('错误点', wrong, AppColors.danger),
          ],
          if (improved.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '优化回答：',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
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
              child: Text(improved, style: const TextStyle(height: 1.6)),
            ),
          ],
          if (nextAction.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
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
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_questionDurations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '本题用时 ${_formatDuration(_questionDurations.last)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPointList(String title, List<dynamic> points, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 6),
        ...points.map(
          (p) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('$p', style: const TextStyle(height: 1.4))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDimensionScores(int totalScore, Map<String, int> weights) {
    final dimensions = [
      {
        'label': '概念完整性',
        'weight': weights['concept'] ?? weights['mustHave'] ?? 40,
        'color': AppColors.accent,
      },
      {
        'label': '表达准确性',
        'weight': weights['expression'] ?? weights['accuracy'] ?? 25,
        'color': AppColors.success,
      },
      {
        'label': '面试表达',
        'weight': weights['interview'] ?? weights['structure'] ?? 20,
        'color': AppColors.warning,
      },
      {
        'label': '扩展深度',
        'weight': weights['depth'] ?? weights['goodToHave'] ?? 15,
        'color': const Color(0xFF8B5CF6),
      },
    ];

    return Column(
      children: dimensions.map((dim) {
        final weight = dim['weight'] as int;
        final color = dim['color'] as Color;
        final dimScore = (totalScore * weight / 100).round();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  dim['label'] as String,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: dimScore / 100,
                    backgroundColor: Colors.grey.shade200,
                    color: color,
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text(
                  '$dimScore',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── 结果页面 ──
  Widget _buildResultPage() {
    final totalScore = _results.fold(0, (sum, r) => sum + (r['score'] as int));
    final avgScore = _results.isEmpty ? 0 : totalScore ~/ _results.length;
    final totalSeconds = _overallTimer.elapsed.inSeconds;
    final weakCount = _results.where((r) => (r['score'] as int) < 60).length;
    _saveSessionIfNeeded(avgScore);

    return Scaffold(
      appBar: AppBar(title: const Text('面试报告')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── 总分 Hero ──
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  const Color(0xFF0F3460),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  '面试完成！',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
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
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ResultStat(
                      icon: Icons.timer_outlined,
                      value: _formatDuration(totalSeconds),
                      label: '总用时',
                    ),
                    const SizedBox(width: 24),
                    _ResultStat(
                      icon: Icons.quiz_outlined,
                      value: '${_results.length}',
                      label: '题目数',
                    ),
                    const SizedBox(width: 24),
                    _ResultStat(
                      icon: Icons.warning_amber_outlined,
                      value: '$weakCount',
                      label: '需复习',
                      valueColor: weakCount > 0 ? AppColors.danger : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── 下一轮训练包 ──
          if (weakCount > 0) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.auto_fix_high_outlined,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '建议：下一轮训练包',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$weakCount 题得分低于 60 分，建议先复盘这些薄弱知识点，再进行下一场模拟面试。',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final weakIds = _results
                          .where((r) => (r['score'] as int) < 60)
                          .map((r) => r['topicId'] as String)
                          .toList();
                      Navigator.of(context).pop(weakIds);
                    },
                    icon: const Icon(Icons.replay_outlined, size: 18),
                    label: const Text('复盘薄弱知识点'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 各题得分 ──
          const Text(
            '各题得分',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ..._results.asMap().entries.map((entry) {
            final index = entry.key;
            final result = entry.value;
            final score = result['score'] as int;
            final duration = index < _questionDurations.length
                ? _questionDurations[index]
                : null;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: score >= 85
                        ? AppColors.success
                        : score >= 60
                        ? AppColors.warning
                        : AppColors.danger,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result['topicTitle'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if ((result['summary'] as String?)?.isNotEmpty == true)
                          Text(
                            result['summary'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (duration != null)
                          Text(
                            '用时 ${_formatDuration(duration)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$score 分',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: score >= 85
                              ? AppColors.success
                              : score >= 60
                              ? AppColors.warning
                              : AppColors.danger,
                        ),
                      ),
                      if (score < 60)
                        const Text(
                          '需复习',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.danger,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),

          // ── 返回按钮 ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // 可以从外部触发再来一场
                  },
                  icon: const Icon(Icons.replay_outlined, size: 18),
                  label: const Text('再来一场'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _saveSessionIfNeeded(int avgScore) {
    if (_savedSession) return;
    _savedSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final attempts = _results.map((result) {
        final rawMissed = result['missedPoints'] as List<dynamic>? ?? [];
        final rawWrong = result['wrongPoints'] as List<dynamic>? ?? [];
        return PracticeAttempt(
          id: '${DateTime.now().microsecondsSinceEpoch}-${result['topicId']}',
          topicId: result['topicId'] as String,
          mode: 'mockInterview',
          question: result['question'] as String? ?? '',
          answer: result['answer'] as String? ?? '',
          createdAt: DateTime.now(),
          score: result['score'] as int?,
          summary: result['summary'] as String?,
          missedPoints: rawMissed.map((e) => e.toString()).toList(),
          wrongPoints: rawWrong.map((e) => e.toString()).toList(),
          improvedAnswer: result['improvedAnswer'] as String?,
          aiEvaluated: result['aiUnavailable'] != true,
        );
      }).toList();
      context.read<ProgressProvider>().addMockSession(
        MockInterviewSession(
          id: _startedAt.microsecondsSinceEpoch.toString(),
          scenario: _scenario,
          startedAt: _startedAt,
          completedAt: DateTime.now(),
          topicIds: widget.topicIds,
          attempts: attempts,
          averageScore: avgScore,
          reportSummary: avgScore >= 85
              ? '整体表现稳定，可以继续正式模拟。'
              : '建议先复盘低分题，再进行下一场模拟面试。',
          weakTopicIds: _results
              .where((r) => (r['score'] as int? ?? 0) < 60)
              .map((r) => r['topicId'] as String)
              .toList(),
          nextActions: const ['复盘低分题', '清理今日复习', '再进行一场模拟面试'],
          formalMode: _formalMode,
        ),
      );
    });
  }
}

// ── 辅助组件 ──────────────────────────────────────────────

class _ScenarioChip extends StatelessWidget {
  const _ScenarioChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _ResultStat extends StatelessWidget {
  const _ResultStat({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Colors.white60),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: valueColor ?? Colors.white,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}
