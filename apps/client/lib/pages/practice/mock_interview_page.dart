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
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/pages/practice/mock_interview_widgets.dart';

part 'mock_interview_page/sections.dart';

enum _InterviewStage { main, followUp, clarify, summary }

class MockInterviewPage extends StatefulWidget {
  const MockInterviewPage({
    super.key,
    required this.topicIds,
    this.sourceRouteId,
    this.interviewScenario,
    this.timeLimitMinutes,
  });

  final List<String> topicIds;
  final String? sourceRouteId;
  final String? interviewScenario;
  final int? timeLimitMinutes;

  @override
  State<MockInterviewPage> createState() => _MockInterviewPageState();
}

class _MockInterviewPageState extends State<MockInterviewPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();

  /// part 文件中的 extension（_MockInterviewPageSections）不是 State 的子类成员，
  /// 直接调用 protected 的 setState 会触发 invalid_use_of_protected_member，
  /// 统一经由该方法刷新。
  void _refresh(VoidCallback fn) => setState(fn);

  final _answerController = TextEditingController();
  int _currentIndex = 0;
  bool _isEvaluating = false;
  Map<String, dynamic>? _evaluationResult;
  final List<Map<String, dynamic>> _results = [];
  bool _isCompleted = false;
  bool _formalMode = false;
  bool _savedSession = false;
  bool _isVoiceListening = false;
  String _scenario = '';
  late final DateTime _startedAt = DateTime.now();

  // 追问流状态
  _InterviewStage _stage = _InterviewStage.main;
  String? _followUpQuestion;
  final List<Map<String, String>> _followUpHistory = [];
  final Map<String, int> _recallPromptSeeds = {};

  late DateTime _questionStartTime;
  final List<int> _questionDurations = [];
  late final Stopwatch _overallTimer = Stopwatch()..start();

  /// 根据场景过滤后的题目 ID 列表
  List<String> get _activeTopicIds {
    if (_scenario == 'mixed') return widget.topicIds;
    final contentProvider = context.read<ContentProvider>();
    return widget.topicIds.where((id) {
      final topic = contentProvider.findTopic(id);
      if (topic == null) return true;
      return _topicMatchesScenario(topic, _scenario);
    }).toList();
  }

  bool _topicMatchesScenario(Topic topic, String scenario) {
    switch (scenario) {
      case 'foundation':
        return topic.leetcodeUrl == null && topic.interviewFrequency != 'low';
      case 'systemDesign':
        return topic.tags.any((t) => t.toLowerCase() == 'system-design') ||
            topic.category.toLowerCase() == 'system-design' ||
            topic.category.toLowerCase() == '架构';
      case 'code':
        return topic.leetcodeUrl != null ||
            topic.category.toLowerCase() == 'algorithm';
      case 'project':
        return false;
      default:
        return true;
    }
  }

  RecallPrompt? _selectedRecallPrompt(Topic topic) {
    final seed = _recallPromptSeeds.putIfAbsent(topic.id, () {
      return context
          .read<ProgressProvider>()
          .getAttemptsForTopic(topic.id)
          .length;
    });
    return topic.recallPromptAt(seed);
  }

  void _onScenarioChanged(String value) {
    if (value == _scenario) return;
    final hasProgress = _results.isNotEmpty || _evaluationResult != null;
    if (hasProgress) {
      final l10n = context.read<LocalizationProvider>();
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.get('toggle_switch_scenario')),
          content: Text(
            l10n.get(
              'toggle_switch_scenario_will_restart_new_start_interview_current_pro',
            ),
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(ctx).pop,
              child: Text(l10n.get('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.get('confirm_fixed')),
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
    _scenario = widget.interviewScenario ?? 'mixed';
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
    final l10n = context.read<LocalizationProvider>();
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('please_first_input_your_answer'))),
      );
      return;
    }

    final topic = _getCurrentTopic();
    if (topic == null) return;

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
      contextualAnswer =
          '[追问回答] $contextualAnswer\n\n'
          '${l10n.get('evaluation_instruction')}';
    } else if (_stage == _InterviewStage.clarify) {
      contextualAnswer =
          '[澄清回答] $contextualAnswer\n\n'
          '${l10n.get('please_give_output_most_final_comprehensive_combine_evaluation_not_again_follo')}';
    }

    try {
      final aiProvider = context.read<AiProvider>();
      final recallPrompt = _selectedRecallPrompt(topic);
      final mainQuestion = recallPrompt?.prompt ?? topic.title;
      final result = await aiProvider.evaluateAnswer(
        usageTag: 'mockInterview',
        topicId: topic.id,
        question: mainQuestion,
        userAnswer: contextualAnswer,
        rubric: topic.rubric,
      );

      if (mounted) {
        final hasFollowUp =
            result['followUp'] != null &&
            (result['followUp'] as String).isNotEmpty;

        if (hasFollowUp && _followUpHistory.length < 2) {
          // AI 要求追问
          setState(() {
            _followUpQuestion = result['followUp'] as String;
            _followUpHistory.add({
              'question': _stage == _InterviewStage.main
                  ? mainQuestion
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
            final scoreForDisplay = result['score'] is int
                ? result['score'] as int
                : 0;
            _results.add({
              'topicId': topic.id,
              'topicTitle': topic.title,
              'score': scoreForDisplay,
              'answer': answer,
              'question': mainQuestion,
              'summary': result['summary'] ?? '',
              'missedPoints': result['missedPoints'] ?? [],
              'wrongPoints':
                  result['wrongPoints'] ?? result['errorPoints'] ?? [],
              'improvedAnswer':
                  result['improvedAnswer'] ?? result['optimizedAnswer'] ?? '',
              'nextAction': result['nextAction'] ?? '',
              'aiUnavailable': result['aiUnavailable'] == true,
              'followUpCount': _followUpHistory.length,
            });
          });

          final progressProvider = context.read<ProgressProvider>();
          await progressProvider.addAttempt(
            PracticeAttempt(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              topicId: topic.id,
              promptId: recallPrompt?.id ?? '',
              mode: 'mockInterview',
              question: mainQuestion,
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
              localOnly: result['aiUnavailable'] == true,
              analysisStatus: result['aiUnavailable'] == true
                  ? 'unanalysed'
                  : result['score'] == null
                  ? 'unanalysed'
                  : 'success',
            ),
          );
          if (result['aiUnavailable'] != true && result['score'] is int) {
            await progressProvider.updateTopicProgress(
              topic.id,
              score: result['score'] as int,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = context.read<LocalizationProvider>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.getp('ai_evaluation_fail_error_2', {'error': e}),
            ),
            action: SnackBarAction(
              label: l10n.get('retry'),
              onPressed: _evaluate,
            ),
          ),
        );
      }
    } finally {
      if (mounted &&
          _stage != _InterviewStage.followUp &&
          _stage != _InterviewStage.clarify) {
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
        appBar: AppBar(title: Text(l10n.get('mode_mock_interview'))),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.get('not_has_optional_use_knowledge_point')),
              if (_scenario != 'mixed') ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => setState(() => _scenario = 'mixed'),
                  child: Text(l10n.get('mix_combine')),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_isCompleted) {
      return _buildResultPage();
    }

    final topic = _getCurrentTopic();
    if (topic == null) {
      final l10n = context.watch<LocalizationProvider>();
      return Scaffold(
        appBar: AppBar(title: Text(l10n.get('mode_mock_interview'))),
        body: Center(child: Text(l10n.get('knowledge_point_loading_fail'))),
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
            Text(l10n.get('mode_mock_interview')),
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
}
