import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/widgets/privacy_dialog.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/voice_input_button.dart';
import 'package:mianshi_zhilian/pages/practice/answer_versions_page.dart';
import 'package:mianshi_zhilian/services/app_permission_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

class RecallPage extends StatefulWidget {
  const RecallPage({super.key, required this.topicIds});

  final List<String> topicIds;

  @override
  State<RecallPage> createState() => _RecallPageState();
}

class _RecallPageState extends State<RecallPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  int _currentIndex = 0;
  final _answerController = TextEditingController();
  bool _isEvaluating = false;
  Map<String, dynamic>? _evaluationResult;
  String? _selectedAiConfigId;
  String _inputMode = 'text';
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _voiceTranscribed = false;
  bool _isVoiceListening = false;
  final _voiceTranscriptController = TextEditingController();

  // 流式输出相关
  String _streamingContent = '';
  bool _isStreaming = false;

  @override
  void dispose() {
    _answerController.dispose();
    _voiceTranscriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    if (widget.topicIds.isEmpty) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Text(l10n.get('not_has_optional_practice_knowledge_point')),
        ),
      );
    }

    final contentProvider = context.watch<ContentProvider>();
    final aiProvider = context.watch<AiProvider>();
    final topic = contentProvider.findTopic(widget.topicIds[_currentIndex]);

    if (topic == null) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Center(child: Text(l10n.get('knowledge_point_un_find_to'))),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;
    final content = isDesktop
        ? _buildDesktopLayout(context, topic, aiProvider)
        : _buildMobileLayout(context, topic, aiProvider);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: content,
    );
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
                      _EvaluationResultPanel(
                        result: _evaluationResult!,
                        topic: topic,
                      ),
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
                _EvaluationResultPanel(
                  result: _evaluationResult!,
                  topic: topic,
                ),
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
          hasAi: _selectedEvaluationConfig(aiProvider)?.canEvaluate == true,
          onPrevious: _goPrevious,
          onNext: _goNext,
          onSubmit: _handleEvaluate,
        ),
      ],
    );
  }

  AiConfig? _selectedEvaluationConfig(AiProvider aiProvider) {
    final selectedConfigId =
        _selectedAiConfigId ??
        aiProvider.defaultConfig?.id ??
        aiProvider.enabledConfigs.firstOrNull?.id;
    if (selectedConfigId == null) return null;
    return aiProvider.enabledConfigs
        .where((config) => config.id == selectedConfigId)
        .firstOrNull;
  }

  // ── 输入区域（共享） ──
  Widget _buildInputSection(BuildContext context, AiProvider aiProvider) {
    final selectedConfigId =
        _selectedAiConfigId ??
        aiProvider.defaultConfig?.id ??
        aiProvider.enabledConfigs.firstOrNull?.id;
    final selectedConfig = selectedConfigId != null
        ? aiProvider.enabledConfigs
              .where((c) => c.id == selectedConfigId)
              .firstOrNull
        : null;
    final supportsImage = selectedConfig?.supportsImageInput ?? false;
    final supportsAudio = selectedConfig?.audioMode != AiAudioMode.none;
    final canEvaluate = selectedConfig?.canEvaluate ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 模型选择器 + 能力标签
        _ModelSelector(
          selectedId: _selectedAiConfigId,
          onChanged: (id) => setState(() {
            _selectedAiConfigId = id;
            // 切换模型后，若当前模式不支持则回落到文本
            final config = aiProvider.enabledConfigs
                .where((c) => c.id == id)
                .firstOrNull;
            if (_inputMode == 'image' &&
                !(config?.supportsImageInput ?? false)) {
              _inputMode = 'text';
            }
            if (_inputMode == 'voice' &&
                !(config?.audioMode != AiAudioMode.none)) {
              _inputMode = 'text';
            }
          }),
        ),
        const SizedBox(height: 10),
        _AiReadinessNotice(config: selectedConfig),
        const SizedBox(height: 16),

        // 输入模式切换（根据模型能力动态启用/禁用）
        Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _InputModeTab(
                icon: Icons.notes_outlined,
                label: l10n.get('text_local'),
                value: 'text',
                selected: _inputMode == 'text',
                onTap: () => setState(() => _inputMode = 'text'),
              ),
              _InputModeTab(
                icon: Icons.mic_outlined,
                label: l10n.get('speech_voice'),
                value: 'voice',
                selected: _inputMode == 'voice',
                enabled: supportsAudio,
                disabledTooltip: l10n.get(
                  'current_mode_type_not_support_long_speech_voice_input',
                ),
                onTap: () => setState(() {
                  _inputMode = 'voice';
                  _voiceTranscribed = false;
                }),
              ),
              _InputModeTab(
                icon: Icons.image_outlined,
                label: l10n.get('image_picture'),
                value: 'image',
                selected: _inputMode == 'image',
                enabled: supportsImage,
                disabledTooltip: l10n.get(
                  'current_mode_type_not_support_long_image_picture_input',
                ),
                onTap: () => setState(() => _inputMode = 'image'),
              ),
              _InputModeTab(
                icon: Icons.code,
                label: l10n.get('code'),
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
                    ? l10n.get('evaluation_in')
                    : !canEvaluate
                    ? l10n.get('save_local_practice')
                    : l10n.get('gain_fetch_ai_evaluation'),
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
                    l10n.get('ai_not_configured_save_as_local_practice'),
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
        color: _isVoiceListening
            ? Colors.green.withValues(alpha: 0.06)
            : AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isVoiceListening
              ? Colors.green.withValues(alpha: 0.5)
              : AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VoiceInputButton(
                onResult: (text) {
                  setState(() {
                    _voiceTranscriptController.text =
                        '${_voiceTranscriptController.text}$text';
                    _voiceTranscribed = true;
                  });
                },
                onListeningChanged: (listening) {
                  setState(() => _isVoiceListening = listening);
                },
                aiConfigId: _selectedAiConfigId,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _voiceTranscribed
                          ? l10n.get(
                              'speech_voice_already_transfer_write_optional_edit_after_add_to_answer',
                            )
                          : l10n.get(
                              'point_hit_wheat_gram_wind_start_speech_voice_review_narrate',
                            ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _isVoiceListening
                          ? l10n.get('voice_recording_hint')
                          : l10n.get(
                              'transfer_write_text_local_optional_independent_establish_edit_confirm_after_add_523',
                            ),
                      style: TextStyle(
                        fontSize: 11,
                        color: _isVoiceListening ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 转写编辑区
          if (_voiceTranscribed) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                ),
              ),
              child: TextField(
                controller: _voiceTranscriptController,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: l10n.get('speech_voice_transfer_write_result'),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: l10n.get('clarify_empty_transfer_write'),
                    onPressed: () {
                      setState(() {
                        _voiceTranscriptController.clear();
                        _voiceTranscribed = false;
                      });
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      final transcript = _voiceTranscriptController.text.trim();
                      if (transcript.isNotEmpty) {
                        setState(() {
                          final separator = _answerController.text.isNotEmpty
                              ? '\n'
                              : '';
                          _answerController.text =
                              '${_answerController.text}$separator$transcript';
                          _voiceTranscriptController.clear();
                          _voiceTranscribed = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.get('already_add_to_answer')),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.get('add_to_answer')),
                  ),
                ),
              ],
            ),
          ],
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
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedImageBytes != null) ...[
            // 已选图片预览
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _selectedImageBytes!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.getp('selected_image_name', {
                      'name': _selectedImageName ?? l10n.get('image_picture'),
                    }),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selectedImageBytes = null;
                    _selectedImageName = null;
                  }),
                  child: Text(
                    l10n.get('move_remove'),
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ] else ...[
            // 选择图片
            Row(
              children: [
                const Icon(Icons.image_outlined, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.get(
                      'add_screenshot_image_architecture_wait_ai_will_result_combine',
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: Text(
                      l10n.get('mutual_book'),
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 16),
                    label: Text(
                      l10n.get('photo'),
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      bool granted;
      if (source == ImageSource.camera) {
        granted = await AppPermissionService.ensureCamera(context);
      } else {
        granted = await AppPermissionService.ensurePhotos(context);
      }
      if (!granted || !mounted) return;

      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _selectedImageBytes = bytes;
            _selectedImageName = file.name;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.getp('select_image_picture_fail_error_2', {'error': e}),
            ),
          ),
        );
      }
    }
  }

  Widget _buildStreamingContent(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
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
              Text(
                l10n.get('ai_analyzing'),
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
            Text(
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

    // 图片上传前隐私确认
    if (_selectedImageBytes != null) {
      final confirmed = await PrivacyService.confirmUpload(
        context: context,
        dataType: l10n.get('image_picture'),
        dataDescription: l10n.get('selected_image_will_be_sent_to_ai'),
      );
      if (!confirmed) return;
      if (!mounted) return;
    }

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
        imageBytes: _selectedImageBytes,
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
              SnackBar(
                content: Text(
                  l10n.getp('flow_mode_output_fail_error_2', {'error': error}),
                ),
              ),
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
        final aiEvaluated = result['aiUnavailable'] != true;
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
            localOnly: result['aiUnavailable'] == true,
            analysisStatus: result['aiUnavailable'] == true
                ? 'unanalysed'
                : result['score'] == null
                ? 'unanalysed'
                : 'success',
          ),
        );
        if (aiEvaluated && result['score'] is int) {
          await progressProvider.updateTopicProgress(topicId, score: score);
        }

        // 自动保存 AI 改进版到回答版本库
        final improvedAnswer =
            (result['improvedAnswer'] ?? result['optimizedAnswer']) as String?;
        if (improvedAnswer != null && improvedAnswer.isNotEmpty) {
          final storage = StorageService();
          final versionsKey = 'answer_versions_$topicId';
          final versions = await storage.loadJsonList(versionsKey);
          // 避免重复保存相同内容
          final alreadySaved = versions.any(
            (v) => v['content'] == improvedAnswer && v['type'] == 'ai_modified',
          );
          if (!alreadySaved) {
            versions.add({
              'type': 'ai_modified',
              'content': improvedAnswer,
              'createdAt': DateTime.now().toString().substring(0, 16),
              'source': 'auto_eval',
            });
            await storage.saveJsonList(versionsKey, versions);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        await _saveFailedAttempt(answer, e);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.getp('evaluation_fail_error_2', {'error': e})),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }

  Future<void> _saveFailedAttempt(String answer, Object error) async {
    final aiProvider = context.read<AiProvider>();
    final contentProvider = context.read<ContentProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final topicId = widget.topicIds[_currentIndex];
    final topic = contentProvider.findTopic(topicId);
    if (topic == null) return;
    final enabledConfigs = aiProvider.enabledConfigs;
    final aiConfigId =
        _selectedAiConfigId ??
        aiProvider.defaultConfig?.id ??
        (enabledConfigs.isNotEmpty ? enabledConfigs.first.id : null);
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
        summary: error.toString(),
        aiConfigId: aiConfigId,
        aiEvaluated: false,
        localOnly: true,
        analysisStatus: 'failed',
      ),
    );
  }

  List<String> _inferErrorTags(Map<String, dynamic> result) {
    final tags = <String>[];
    final missed = result['missedPoints'] as List<dynamic>? ?? [];
    final wrong =
        (result['wrongPoints'] ?? result['errorPoints']) as List<dynamic>? ??
        [];
    if (missed.isNotEmpty) tags.add(l10n.get('concept_lack_lose'));
    if (wrong.isNotEmpty) tags.add(l10n.get('concept_mix_confuse'));
    final summary = (result['summary'] ?? '').toString();
    if (summary.contains('表达') || summary.contains('结构')) {
      tags.add(l10n.get('expression_not_clarify'));
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
        _voiceTranscriptController.clear();
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
        _voiceTranscriptController.clear();
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

class _RubricPanel extends StatelessWidget {
  const _RubricPanel({required this.rubric});

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

// ── 模型选择器 ──────────────────────────────────────────────

class _AiReadinessNotice extends StatelessWidget {
  const _AiReadinessNotice({required this.config});

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

class _ModelSelector extends StatelessWidget {
  const _ModelSelector({required this.selectedId, required this.onChanged});

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

class _InputModeTab extends StatelessWidget {
  const _InputModeTab({
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

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({required this.current, required this.total});

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

class _EvaluationResultPanel extends StatefulWidget {
  const _EvaluationResultPanel({required this.result, this.topic});

  final Map<String, dynamic> result;
  final Topic? topic;

  @override
  State<_EvaluationResultPanel> createState() => _EvaluationResultPanelState();
}

class _EvaluationResultPanelState extends State<_EvaluationResultPanel> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  bool _showReference = false;
  int? _selfScore; // 0=不太理解, 1=部分理解, 2=理解良好

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

    // 从 learningCards 中提取参考答案
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
          // 标题行
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

          // 错因标签
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

          // ── 本地练习模式专属：参考答案 + 自评 ──
          if (aiUnavailable) ...[
            // 参考答案
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

            // 自评
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
                      _SelfEvalChip(
                        label: l10n.get('not_too_principle_understand'),
                        icon: Icons.sentiment_dissatisfied,
                        color: AppColors.danger,
                        selected: _selfScore == 0,
                        onTap: () => setState(() => _selfScore = 0),
                      ),
                      const SizedBox(width: 8),
                      _SelfEvalChip(
                        label: l10n.get(
                          'department_score_principle_understand',
                        ),
                        icon: Icons.sentiment_neutral,
                        color: AppColors.warning,
                        selected: _selfScore == 1,
                        onTap: () => setState(() => _selfScore = 1),
                      ),
                      const SizedBox(width: 8),
                      _SelfEvalChip(
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

          // 遗漏点
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(
              icon: Icons.tips_and_updates_outlined,
              label: l10n.get('missed_point'),
              color: AppColors.warning,
            ),
            const SizedBox(height: 8),
            ...missed.map(
              (item) =>
                  _BulletPoint(text: item.toString(), color: AppColors.warning),
            ),
          ],
          // 错误点
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(
              icon: Icons.cancel_outlined,
              label: l10n.get('wrong_point'),
              color: AppColors.danger,
            ),
            const SizedBox(height: 8),
            ...errors.map(
              (item) =>
                  _BulletPoint(text: item.toString(), color: AppColors.danger),
            ),
          ],
          // 优化回答
          if (optimized.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeader(
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
          // 版本库入口
          if (widget.topic != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AnswerVersionsPage(
                      topicId: widget.topic!.id,
                      topicTitle: widget.topic!.title,
                      question: widget.topic!.recallPrompts.isNotEmpty
                          ? widget.topic!.recallPrompts.first.prompt
                          : widget.topic!.title,
                    ),
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

class _SelfEvalChip extends StatelessWidget {
  const _SelfEvalChip({
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
