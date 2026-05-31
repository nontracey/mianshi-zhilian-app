import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/widgets/voice_input_button.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import '../../providers/localization_provider.dart';

enum _InterviewStage { main, followUp, clarify, summary }

class MockInterviewPage extends StatefulWidget {
  const MockInterviewPage({super.key, required this.topicIds});

  final List<String> topicIds;

  @override
  State<MockInterviewPage> createState() => _MockInterviewPageState();
}

class _MockInterviewPageState extends State<MockInterviewPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
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

  // 追问流状态
  _InterviewStage _stage = _InterviewStage.main;
  String? _followUpQuestion;
  final List<Map<String, String>> _followUpHistory = [];

  late DateTime _questionStartTime;
  final List<int> _questionDurations = [];
  late final Stopwatch _overallTimer = Stopwatch()..start();

  /// 根据场景过滤后的题目 ID 列表
  List<String> get _activeTopicIds {
    if (_scenario == 'mixed') return widget.topicIds;
    final contentProvider = context.read<ContentProvider>();
    return widget.topicIds.where((id) {
      final topic = contentProvider.findTopic(id);
      if (topic == null) return false;
      return _matchesScenario(topic, _scenario);
    }).toList();
  }

  static bool _matchesScenario(Topic topic, String scenario) {
    final cat = topic.category.toLowerCase();
    final tags = topic.tags.map((t) => t.toLowerCase()).toList();
    switch (scenario) {
      case 'foundation':
        return cat.contains('基础') ||
            cat.contains('概念') ||
            cat.contains('原理') ||
            tags.any((t) => t.contains('基础') || t.contains('概念')) ||
            topic.leetcodeUrl == null;
      case 'systemDesign':
        return cat.contains('系统设计') ||
            cat.contains('架构') ||
            tags.any((t) =>
                t.contains('系统设计') ||
                t.contains('架构') ||
                t.contains('system'));
      case 'code':
        return cat.contains('算法') ||
            cat.contains('代码') ||
            cat.contains('编程') ||
            topic.leetcodeUrl != null ||
            tags.any((t) => t.contains('算法') || t.contains('代码'));
      case 'project':
        return cat.contains('项目') ||
            cat.contains('实战') ||
            cat.contains('工程') ||
            tags.any((t) => t.contains('项目') || t.contains('实战'));
      default:
        return true;
    }
  }

  void _onScenarioChanged(String value) {
    if (value == _scenario) return;
    final hasProgress = _results.isNotEmpty || _evaluationResult != null;
    if (hasProgress) {
      final l10n = context.watch<LocalizationProvider>();
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.get('切换场景')),
          content: Text(l10n.get('切换场景将重新开始面试_当前进度会丢失_确定切换吗')),
          actions: [
            TextButton(
              onPressed: Navigator.of(ctx).pop,
              child: Text(l10n.get('取消')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.get('确定')),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true) _applyScenario(value);
      });
    } else {
      _applyScenario(value);
    }
  }

  void _applyScenario(String value) {
    setState(() {
      _scenario = value;
      _currentIndex = 0;
      _results.clear();
      _evaluationResult = null;
      _isCompleted = false;
      _savedSession = false;
      _followUpHistory.clear();
      _stage = _InterviewStage.main;
      _followUpQuestion = null;
      _answerController.clear();
      _questionDurations.clear();
      _questionStartTime = DateTime.now();
    });
  }

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
    final ids = _activeTopicIds;
    if (_currentIndex >= ids.length) return null;
    final contentProvider = context.read<ContentProvider>();
    return contentProvider.findTopic(ids[_currentIndex]);
  }

  Future<void> _evaluate() async {
    final l10n = context.watch<LocalizationProvider>();
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      final l10n = context.watch<LocalizationProvider>();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('请先输入你的回答'))));
      return;
    }

    final topic = _getCurrentTopic();
    if (topic == null) return;

    final aiProvider = context.read<AiProvider>();
    if (aiProvider.defaultConfig == null) {
      final l10n = context.watch<LocalizationProvider>();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('请先在个人中心配置_AI'))));
      return;
    }

    setState(() => _isEvaluating = true);

    // 构建追问上下文
    String contextualAnswer = answer;
    if (_followUpHistory.isNotEmpty) {
      final contextParts = <String>[];
      for (final qa in _followUpHistory) {
        contextParts.add('追问：${qa['question']}');
        contextParts.add('回答：${qa['answer']}');
      }
      contextualAnswer = '${contextParts.join('\n')}\n\n当前回答：$answer';
    }

    // 追问阶段的特殊指令
    if (_stage == _InterviewStage.followUp) {
      contextualAnswer = '[追问回答] $contextualAnswer\n\n'
          '${l10n.get('text_ea189e1f')}';
    } else if (_stage == _InterviewStage.clarify) {
      contextualAnswer = '[澄清回答] $contextualAnswer\n\n'
          '${l10n.get('请给出最终综合评估_不再追问')}';
    }

    try {
      final result = await aiProvider.evaluateAnswer(
        topicId: topic.id,
        question: topic.recallPrompts.isNotEmpty
            ? topic.recallPrompts.first.prompt
            : topic.title,
        userAnswer: contextualAnswer,
        rubric: topic.rubric,
      );

      if (mounted) {
        final hasFollowUp = result['followUp'] != null &&
            (result['followUp'] as String).isNotEmpty;

        if (hasFollowUp && _followUpHistory.length < 2) {
          // AI 要求追问
          setState(() {
            _followUpQuestion = result['followUp'] as String;
            _followUpHistory.add({
              'question': _stage == _InterviewStage.main
                  ? (topic.recallPrompts.isNotEmpty
                      ? topic.recallPrompts.first.prompt
                      : topic.title)
                  : (_followUpQuestion ?? ''),
              'answer': answer,
            });
            _stage = _stage == _InterviewStage.main
                ? _InterviewStage.followUp
                : _InterviewStage.clarify;
            _answerController.clear();
            _isEvaluating = false;
          });
        } else {
          // 最终评估
          setState(() {
            _evaluationResult = result;
            _stage = _InterviewStage.summary;
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
              'followUpCount': _followUpHistory.length,
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
              answer: contextualAnswer,
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
      }
    } catch (e) {
      final l10n = context.watch<LocalizationProvider>();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.getp('AI 评估失败：{error}', {'error': e})),
            action: SnackBarAction(label: l10n.get('重试'), onPressed: _evaluate),
          ),
        );
      }
    } finally {
      if (mounted && _stage != _InterviewStage.followUp && _stage != _InterviewStage.clarify) {
        setState(() => _isEvaluating = false);
      }
    }
  }

  void _nextQuestion() {
    final elapsed = DateTime.now().difference(_questionStartTime).inSeconds;
    _questionDurations.add(elapsed);

    if (_currentIndex < _activeTopicIds.length - 1) {
      setState(() {
        _currentIndex++;
        _answerController.clear();
        _evaluationResult = null;
        _stage = _InterviewStage.main;
        _followUpQuestion = null;
        _followUpHistory.clear();
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
    if (_activeTopicIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.get('模拟面试'))),
        body: Center(child: Text(l10n.get('没有可用的知识点'))),
      );
    }

    if (_isCompleted) {
      return _buildResultPage();
    }

    final topic = _getCurrentTopic();
    if (topic == null) {
      final l10n = context.watch<LocalizationProvider>();
      return Scaffold(
        appBar: AppBar(title: Text(l10n.get('模拟面试'))),
        body: Center(child: Text(l10n.get('知识点加载失败'))),
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
                '${_currentIndex + 1}/${_activeTopicIds.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(l10n.get('模拟面试')),
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
    final l10n = context.watch<LocalizationProvider>();
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
                      if (_followUpHistory.isNotEmpty) ...[
                        _buildFollowUpHistory(),
                        const SizedBox(height: 16),
                      ],
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
                            _currentIndex < _activeTopicIds.length - 1
                                ? Icons.arrow_forward
                                : Icons.emoji_events_outlined,
                          ),
                          label: Text(
                            _currentIndex < _activeTopicIds.length - 1
                                ? l10n.get('下一题')
                                : l10n.get('查看面试报告'),
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
    final l10n = context.watch<LocalizationProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_currentIndex + 1) / _activeTopicIds.length,
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
          if (_followUpHistory.isNotEmpty) ...[
            _buildFollowUpHistory(),
            const SizedBox(height: 12),
          ],
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
                _currentIndex < _activeTopicIds.length - 1
                    ? Icons.arrow_forward
                    : Icons.emoji_events_outlined,
              ),
              label: Text(
                _currentIndex < _activeTopicIds.length - 1
                    ? l10n.get('下一题')
                    : l10n.get('查看面试报告'),
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
    final l10n = context.watch<LocalizationProvider>();
    final stageLabel = switch (_stage) {
      _InterviewStage.main => l10n.get('主问'),
      _InterviewStage.followUp => l10n.get('追问'),
      _InterviewStage.clarify => l10n.get('澄清'),
      _InterviewStage.summary => l10n.get('总结'),
    };
    final stageColor = switch (_stage) {
      _InterviewStage.main => AppColors.accent,
      _InterviewStage.followUp => AppColors.warning,
      _InterviewStage.clarify => AppColors.categoryPurple,
      _InterviewStage.summary => AppColors.success,
    };
    final displayQuestion = _followUpQuestion ??
        (topic.recallPrompts.isNotEmpty
            ? topic.recallPrompts.first.prompt
            : l10n.getp('请解释 {title} 的核心概念', {'title': topic.title}));
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
                  color: stageColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _stage == _InterviewStage.followUp
                          ? Icons.question_answer_outlined
                          : Icons.quiz_outlined,
                      size: 13,
                      color: stageColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      stageLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: stageColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.getp('问题 {index}', {'index': _currentIndex + 1}),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                    fontSize: 11,
                  ),
                ),
              ),
              const Spacer(),
              if (_followUpHistory.isNotEmpty)
                Text(
                  l10n.getp('第 {round} 轮', {'round': _followUpHistory.length + 1}),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            displayQuestion,
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
                      l10n.getp('面试官关注：{focus}', {'focus': topic.interviewerFocus}),
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
    final l10n = context.watch<LocalizationProvider>();
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
              Text(
                l10n.get('你的回答'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                l10n.getp('{count} 字', {'count': _answerController.text.length}),
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
              hintText: l10n.get('请输入你的回答'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              suffixIcon: VoiceInputButton(
                onResult: (text) {
                  final current = _answerController.text;
                  final separator = current.isNotEmpty && !current.endsWith(' ') ? ' ' : '';
                  final newValue = '$current$separator$text';
                  _answerController.text = newValue;
                  _answerController.selection = TextSelection.fromPosition(
                    TextPosition(offset: newValue.length),
                  );
                },
                sttMode: context.read<SettingsProvider>().settings.sttMode,
                whisperBaseUrl: context.read<SettingsProvider>().settings.whisperBaseUrl,
                whisperApiKey: context.read<SettingsProvider>().settings.whisperApiKey,
                whisperModel: context.read<SettingsProvider>().settings.whisperModel,
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
              label: Text(_isEvaluating
                  ? l10n.get('AI_评估中')
                  : _stage == _InterviewStage.main
                      ? l10n.get('提交并评估')
                      : l10n.get('提交回答')),
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
    final l10n = context.watch<LocalizationProvider>();
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
          Text(
            l10n.get('面试设置'),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ScenarioChip(
                label: l10n.get('混合'),
                value: 'mixed',
                selected: _scenario == 'mixed',
                onSelected: _onScenarioChanged,
              ),
              _ScenarioChip(
                label: l10n.get('基础知识'),
                value: 'foundation',
                selected: _scenario == 'foundation',
                onSelected: _onScenarioChanged,
              ),
              _ScenarioChip(
                label: l10n.get('系统设计'),
                value: 'systemDesign',
                selected: _scenario == 'systemDesign',
                onSelected: _onScenarioChanged,
              ),
              _ScenarioChip(
                label: l10n.get('代码题'),
                value: 'code',
                selected: _scenario == 'code',
                onSelected: _onScenarioChanged,
              ),
              _ScenarioChip(
                label: l10n.get('项目深挖'),
                value: 'project',
                selected: _scenario == 'project',
                onSelected: _onScenarioChanged,
              ),
            ],
          ),
          if (_scenario != 'mixed') ...[
            const SizedBox(height: 6),
            Text(
              l10n.getp('匹配 {matched} / {total} 题', {'matched': _activeTopicIds.length, 'total': widget.topicIds.length}),
              style: TextStyle(
                fontSize: 12,
                color: _activeTopicIds.isEmpty
                    ? AppColors.danger
                    : AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _formalMode,
            title: Text(l10n.get('正式模拟模式')),
            subtitle: Text(l10n.get('逐题不展示详细反馈_结束后统一复盘')),
            onChanged: (value) => setState(() => _formalMode = value),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowUpHistory() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.question_answer_outlined, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                l10n.getp('追问记录（{count} 轮）', {'count': _followUpHistory.length}),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._followUpHistory.asMap().entries.map((entry) {
            final index = entry.key;
            final qa = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Q${index + 1}：${qa['question']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A：${qa['answer']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFormalRecorded() {
    final l10n = context.watch<LocalizationProvider>();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.accent),
          SizedBox(width: 8),
          Expanded(child: Text(l10n.get('回答已记录_正式模拟模式将在结束后统一展示报告'))),
        ],
      ),
    );
  }

  Widget _buildEvaluationResult() {
    final l10n = context.watch<LocalizationProvider>();
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
              Text(
                l10n.get('评估结果'),
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
            _buildPointList(l10n.get('遗漏点'), missed, AppColors.warning),
          ],
          if (wrong.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPointList(l10n.get('错误点'), wrong, AppColors.danger),
          ],
          if (improved.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.get('优化回答'),
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
                  l10n.getp('本题用时 {duration}', {'duration': _formatDuration(_questionDurations.last)}),
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
    final l10n = context.watch<LocalizationProvider>();
    final dimensions = [
      {
        'label': l10n.get('概念完整性'),
        'weight': weights['concept'] ?? weights['mustHave'] ?? 40,
        'color': AppColors.accent,
      },
      {
        'label': l10n.get('表达准确性'),
        'weight': weights['expression'] ?? weights['accuracy'] ?? 25,
        'color': AppColors.success,
      },
      {
        'label': l10n.get('面试表达'),
        'weight': weights['interview'] ?? weights['structure'] ?? 20,
        'color': AppColors.warning,
      },
      {
        'label': l10n.get('扩展深度'),
        'weight': weights['depth'] ?? weights['goodToHave'] ?? 15,
        'color': AppColors.categoryPurple,
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
    final l10n = context.watch<LocalizationProvider>();
    final totalScore = _results.fold(0, (sum, r) => sum + (r['score'] as int));
    final avgScore = _results.isEmpty ? 0 : totalScore ~/ _results.length;
    final totalSeconds = _overallTimer.elapsed.inSeconds;
    final weakCount = _results.where((r) => (r['score'] as int) < 60).length;
    _saveSessionIfNeeded(avgScore);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('面试报告'))),
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
                  AppColors.categoryDeepBlue,
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
                Text(
                  l10n.get('面试完成'),
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
                Text(
                  l10n.get('平均分'),
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ResultStat(
                      icon: Icons.timer_outlined,
                      value: _formatDuration(totalSeconds),
                      label: l10n.get('总用时'),
                    ),
                    const SizedBox(width: 24),
                    _ResultStat(
                      icon: Icons.quiz_outlined,
                      value: '${_results.length}',
                      label: l10n.get('题目数'),
                    ),
                    const SizedBox(width: 24),
                    _ResultStat(
                      icon: Icons.warning_amber_outlined,
                      value: '$weakCount',
                      label: l10n.get('需复习'),
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
                  Row(
                    children: [
                      Icon(
                        Icons.auto_fix_high_outlined,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      SizedBox(width: 8),
                      Text(
                        l10n.get('建议_下一轮训练包'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.getp('{count} 题得分低于 60 分，建议先复盘这些薄弱知识点，再进行下一场模拟面试。', {'count': weakCount}),
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
                    label: Text(l10n.get('复盘薄弱知识点')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 各题得分 ──
          Text(
            l10n.get('各题得分'),
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
                        Row(
                          children: [
                            if (duration != null)
                              Text(
                                l10n.getp('用时 {duration}', {'duration': _formatDuration(duration)}),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            if ((result['followUpCount'] as int? ?? 0) > 0) ...[
                              if (duration != null)
                                Text(
                                  ' · ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              Text(
                                '${result['followUpCount'] ?? 0}${l10n.get('轮追问')}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l10n.getp('{score} 分', {'score': score}),
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
                        Text(
                          l10n.get('需复习'),
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
                  child: Text(l10n.get('返回')),
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
                  label: Text(l10n.get('再来一场')),
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
      final l10n = context.watch<LocalizationProvider>();
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
          topicIds: _activeTopicIds,
          attempts: attempts,
          averageScore: avgScore,
          reportSummary: avgScore >= 85
              ? l10n.get('整体表现稳定_可以继续正式模拟')
              : l10n.get('建议先复盘低分题_再进行下一场模拟面试'),
          weakTopicIds: _results
              .where((r) => (r['score'] as int? ?? 0) < 60)
              .map((r) => r['topicId'] as String)
              .toList(),
          nextActions: [l10n.get('复盘低分题'), l10n.get('清理今日复习'), l10n.get('再进行一场模拟面试')],
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
