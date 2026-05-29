import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/voice_input_button.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class RecallPage extends StatefulWidget {
  const RecallPage({super.key, required this.topicIds});

  final List<String> topicIds;

  @override
  State<RecallPage> createState() => _RecallPageState();
}

class _RecallPageState extends State<RecallPage> {
  int _currentIndex = 0;
  final _answerController = TextEditingController();
  bool _isEvaluating = false;
  Map<String, dynamic>? _evaluationResult;
  String? _selectedAiConfigId;
  String _inputMode = 'text';
  bool _hasLocalImageReference = false;
  bool _voiceTranscribed = false;
  
  // 流式输出相关
  String _streamingContent = '';
  bool _isStreaming = false;

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
    final aiProvider = context.watch<AiProvider>();
    final topic = contentProvider.findTopic(widget.topicIds[_currentIndex]);

    if (topic == null) {
      return const Center(child: Text('知识点未找到'));
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;

    if (isDesktop) {
      return _buildDesktopLayout(context, topic, aiProvider);
    }
    return _buildMobileLayout(context, topic, aiProvider);
  }

  // ── 桌面端分栏布局 ──
  Widget _buildDesktopLayout(
    BuildContext context,
    dynamic topic,
    AiProvider aiProvider,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：题目 + 评分标准
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _QuestionPanel(topic: topic),
              if (topic.rubric != null) ...[
                const SizedBox(height: 16),
                _RubricPanel(rubric: topic.rubric!),
              ],
            ],
          ),
        ),
        // 右侧：输入 + 结果
        Expanded(
          flex: 6,
          child: Column(
            children: [
              _ProgressIndicator(
                current: _currentIndex + 1,
                total: widget.topicIds.length,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildInputSection(context, aiProvider),
                    // 流式内容显示
                    if (_isStreaming && _streamingContent.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildStreamingContent(context),
                    ],
                    // 完整评估结果
                    if (_evaluationResult != null) ...[
                      const SizedBox(height: 16),
                      _EvaluationResultPanel(result: _evaluationResult!),
                    ],
                  ],
                ),
              ),
              _NavigationButtons(
                hasPrevious: _currentIndex > 0,
                hasNext: _currentIndex < widget.topicIds.length - 1,
                onPrevious: _goPrevious,
                onNext: _goNext,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 移动端布局 ──
  Widget _buildMobileLayout(
    BuildContext context,
    dynamic topic,
    AiProvider aiProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProgressIndicator(
          current: _currentIndex + 1,
          total: widget.topicIds.length,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _QuestionPanel(topic: topic),
              const SizedBox(height: 16),
              _buildInputSection(context, aiProvider),
              if (_evaluationResult != null) ...[
                const SizedBox(height: 16),
                _EvaluationResultPanel(result: _evaluationResult!),
              ],
              const SizedBox(height: 80), // 底部留空给操作条
            ],
          ),
        ),
        // 底部操作条
        _BottomActionBar(
          hasPrevious: _currentIndex > 0,
          hasNext: _currentIndex < widget.topicIds.length - 1,
          isEvaluating: _isEvaluating,
          hasAnswer: _answerController.text.trim().isNotEmpty,
          hasAi: aiProvider.enabledConfigs.isNotEmpty,
          onPrevious: _goPrevious,
          onNext: _goNext,
          onSubmit: _handleEvaluate,
        ),
      ],
    );
  }

  // ── 输入区域（共享） ──
  Widget _buildInputSection(BuildContext context, AiProvider aiProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 模型选择器 + 能力标签
        _ModelSelector(
          selectedId: _selectedAiConfigId,
          onChanged: (id) => setState(() => _selectedAiConfigId = id),
        ),
        const SizedBox(height: 16),

        // 输入模式切换
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _InputModeTab(
                icon: Icons.notes_outlined,
                label: '文本',
                value: 'text',
                selected: _inputMode == 'text',
                onTap: () => setState(() => _inputMode = 'text'),
              ),
              _InputModeTab(
                icon: Icons.mic_outlined,
                label: '语音',
                value: 'voice',
                selected: _inputMode == 'voice',
                onTap: () => setState(() {
                  _inputMode = 'voice';
                  _voiceTranscribed = false;
                }),
              ),
              _InputModeTab(
                icon: Icons.image_outlined,
                label: '图片',
                value: 'image',
                selected: _inputMode == 'image',
                onTap: () => setState(() => _inputMode = 'image'),
              ),
              _InputModeTab(
                icon: Icons.code,
                label: '代码',
                value: 'code',
                selected: _inputMode == 'code',
                onTap: () => setState(() => _inputMode = 'code'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 语音模式
        if (_inputMode == 'voice') _buildVoiceSection(context),
        // 图片模式
        if (_inputMode == 'image') _buildImageSection(context),

        // 文本输入框
        _AnswerInputField(
          controller: _answerController,
          inputMode: _inputMode,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),

        // 提交按钮（桌面端显示，移动端由底部操作条处理）
        if (MediaQuery.sizeOf(context).width >= 900)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isEvaluating ? null : _handleEvaluate,
              icon: _isEvaluating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _isEvaluating
                    ? '评估中...'
                    : aiProvider.enabledConfigs.isEmpty
                    ? '保存本地练习'
                    : '获取 AI 评估',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        if (aiProvider.enabledConfigs.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '未配置 AI 模型，将保存为本地练习。配置后可获得深度评分。',
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
    );
  }

  // ── 语音区域 ──
  Widget _buildVoiceSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              VoiceInputButton(
                onResult: (text) {
                  setState(() {
                    _answerController.text =
                        '${_answerController.text}$text';
                    _voiceTranscribed = true;
                  });
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _voiceTranscribed
                          ? '语音已转写，可编辑后提交'
                          : '点击麦克风开始语音复述',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Text(
                      '语音会先转成可编辑文字，再进入 AI 评分',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 图片区域 ──
  Widget _buildImageSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _hasLocalImageReference
                    ? Icons.image
                    : Icons.image_outlined,
                color: AppColors.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _hasLocalImageReference
                      ? '已标记本地图片参考，请在下方用文字描述图片关键信息'
                      : '可把截图、架构图或手写笔记作为参考，用文字描述关键点',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _hasLocalImageReference = !_hasLocalImageReference,
                ),
                child: Text(_hasLocalImageReference ? '移除标记' : '标记参考'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingContent(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI 正在分析...',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _streamingContent,
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
          // 闪烁光标效果
          if (_isStreaming)
            const Text(
              '▊',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleEvaluate() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) return;

    setState(() {
      _isEvaluating = true;
      _streamingContent = '';
      _isStreaming = true;
      _evaluationResult = null;
    });

    try {
      final aiProvider = context.read<AiProvider>();
      final contentProvider = context.read<ContentProvider>();
      final topicId = widget.topicIds[_currentIndex];
      final topic = contentProvider.findTopic(topicId);
      if (topic == null) return;
      final enabledConfigs = aiProvider.enabledConfigs;
      final aiConfigId =
          _selectedAiConfigId ??
          aiProvider.defaultConfig?.id ??
          (enabledConfigs.isNotEmpty ? enabledConfigs.first.id : null);

      // 使用流式输出
      final streamResult = aiProvider.evaluateAnswerStream(
        aiConfigId: aiConfigId,
        topicId: topicId,
        question: topic.recallPrompts.isNotEmpty
            ? topic.recallPrompts.first.prompt
            : topic.title,
        userAnswer: answer,
        rubric: topic.rubric,
      );

      // 监听流式输出
      streamResult.stream.listen(
        (chunk) {
          if (mounted) {
            setState(() {
              _streamingContent += chunk;
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isStreaming = false;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isStreaming = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('流式输出失败：$error')),
            );
          }
        },
      );

      // 等待完整结果
      final result = await streamResult.result;

      if (mounted) {
        setState(() {
          _evaluationResult = result;
          _isStreaming = false;
        });
        final progressProvider = context.read<ProgressProvider>();
        final score = result['score'] as int? ?? 0;
        await progressProvider.addAttempt(
          PracticeAttempt(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            topicId: topicId,
            promptId: topic.recallPrompts.isNotEmpty
                ? topic.recallPrompts.first.id
                : '',
            mode: _inputMode == 'code' ? 'code' : 'recall',
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
            errorTags: _inferErrorTags(result),
            improvedAnswer:
                (result['improvedAnswer'] ?? result['optimizedAnswer'])
                    as String?,
            nextAction: result['nextAction'] as String?,
            aiConfigId: aiConfigId,
            aiEvaluated: result['aiUnavailable'] != true,
          ),
        );
        if (result['score'] is int) {
          await progressProvider.updateTopicProgress(topicId, score: score);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('评估失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }

  List<String> _inferErrorTags(Map<String, dynamic> result) {
    final tags = <String>[];
    final missed = result['missedPoints'] as List<dynamic>? ?? [];
    final wrong =
        (result['wrongPoints'] ?? result['errorPoints']) as List<dynamic>? ??
        [];
    if (missed.isNotEmpty) tags.add('概念缺失');
    if (wrong.isNotEmpty) tags.add('概念混淆');
    final summary = (result['summary'] ?? '').toString();
    if (summary.contains('表达') || summary.contains('结构')) {
      tags.add('表达不清');
    }
    return tags;
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _answerController.clear();
        _evaluationResult = null;
        _voiceTranscribed = false;
      });
    }
  }

  void _goNext() {
    if (_currentIndex < widget.topicIds.length - 1) {
      setState(() {
        _currentIndex++;
        _answerController.clear();
        _evaluationResult = null;
        _voiceTranscribed = false;
      });
    }
  }
}

// ── 问题面板 ──────────────────────────────────────────────

class _QuestionPanel extends StatelessWidget {
  const _QuestionPanel({required this.topic});

  final dynamic topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
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
                  child: const Text(
                    '高频',
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
                : '请用自己的话解释 ${topic.title} 的核心内容。',
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
                      '面试官关注：${topic.interviewerFocus}',
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

class _RubricPanel extends StatelessWidget {
  const _RubricPanel({required this.rubric});

  final dynamic rubric;

  @override
  Widget build(BuildContext context) {
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
          const Text(
            '评分要点',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          if (mustHave.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...mustHave.take(4).map(
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
              '常见错误：',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 4),
            ...commonMistakes.take(3).map(
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

// ── 模型选择器 ──────────────────────────────────────────────

class _ModelSelector extends StatelessWidget {
  const _ModelSelector({required this.selectedId, required this.onChanged});

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final aiProvider = context.watch<AiProvider>();
    final configs = aiProvider.enabledConfigs;
    if (configs.isEmpty) {
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
            const Expanded(child: Text('未配置 AI 模型，本次使用本地练习模式')),
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请到个人中心 -> AI 配置添加你的模型')),
              ),
              child: const Text('去配置'),
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
        labelText: '评分模型',
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      items: configs
          .map(
            (config) => DropdownMenuItem(
              value: config.id,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      config.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CapabilityTags(config: config),
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

class _CapabilityTags extends StatelessWidget {
  const _CapabilityTags({required this.config});

  final dynamic config;

  @override
  Widget build(BuildContext context) {
    final tags = <Widget>[];
    if (config.supportsTextInput == true) {
      tags.add(_tag('文本', AppColors.accent));
    }
    if (config.supportsImageInput == true) {
      tags.add(_tag('图片', AppColors.success));
    }
    if (config.supportsAudioInput == true) {
      tags.add(_tag('语音', AppColors.warning));
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

class _InputModeTab extends StatelessWidget {
  const _InputModeTab({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
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
              Icon(
                icon,
                size: 16,
                color: selected
                    ? AppColors.accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AppColors.accent
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 答案输入框 ──────────────────────────────────────────────

class _AnswerInputField extends StatelessWidget {
  const _AnswerInputField({
    required this.controller,
    required this.inputMode,
    this.onChanged,
  });

  final TextEditingController controller;
  final String inputMode;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 6,
      maxLines: inputMode == 'code' ? 16 : 12,
      style: inputMode == 'code'
          ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
          : null,
      decoration: InputDecoration(
        hintText: switch (inputMode) {
          'code' => '写下思路、复杂度、边界条件或代码...',
          'image' => '描述图片/架构图/手写笔记中的关键信息...',
          'voice' => '语音转写文本会出现在这里，可编辑后再提交...',
          _ => '在这里输入你的复述答案...',
        },
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        filled: true,
      ),
      onChanged: (_) => onChanged?.call(),
    );
  }
}

// ── 进度指示器 ──────────────────────────────────────────────

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Text(
            '第 $current / $total 题',
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

class _EvaluationResultPanel extends StatelessWidget {
  const _EvaluationResultPanel({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
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
          // 标题行
          Row(
            children: [
              Icon(
                aiUnavailable
                    ? Icons.save_outlined
                    : Icons.assessment_outlined,
                size: 18,
                color: aiUnavailable ? Colors.grey : AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                aiUnavailable ? '本地练习已保存' : 'AI 评估结果',
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
          // 遗漏点
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(
              icon: Icons.tips_and_updates_outlined,
              label: '遗漏点',
              color: AppColors.warning,
            ),
            const SizedBox(height: 8),
            ...missed.map(
              (item) => _BulletPoint(
                text: item.toString(),
                color: AppColors.warning,
              ),
            ),
          ],
          // 错误点
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(
              icon: Icons.cancel_outlined,
              label: '错误点',
              color: AppColors.danger,
            ),
            const SizedBox(height: 8),
            ...errors.map(
              (item) => _BulletPoint(
                text: item.toString(),
                color: AppColors.danger,
              ),
            ),
          ],
          // 优化回答
          if (optimized.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(
              icon: Icons.auto_fix_high_outlined,
              label: '优化回答',
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
          // 下一步
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
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
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

class _BulletPoint extends StatelessWidget {
  const _BulletPoint({required this.text, required this.color});

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
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}

// ── 导航按钮 ──────────────────────────────────────────────

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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton.icon(
            onPressed: hasPrevious ? onPrevious : null,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('上一个'),
          ),
          FilledButton.icon(
            onPressed: hasNext ? onNext : null,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('下一个'),
          ),
        ],
      ),
    );
  }
}

// ── 底部操作条（移动端） ──────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
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
            // 上一题
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
            // 提交按钮
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
                      ? '评估中...'
                      : hasAi
                      ? 'AI 评估'
                      : '保存练习',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 下一题
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
