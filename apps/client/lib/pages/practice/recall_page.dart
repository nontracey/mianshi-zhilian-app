import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/models/ai_config.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/widgets/voice_input_button.dart';
import 'package:mianshi_zhilian/services/app_permission_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/privacy_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'recall_panels.dart';

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
  final Map<String, int> _recallPromptSeeds = {};

  // 流式输出相关
  String _streamingContent = '';
  bool _isStreaming = false;
  StreamSubscription<String>? _streamSubscription;

  @override
  void dispose() {
    _streamSubscription?.cancel();
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
    final recallPrompt = _selectedRecallPrompt(topic);
    final content = isDesktop
        ? _buildDesktopLayout(context, topic, recallPrompt, aiProvider)
        : _buildMobileLayout(context, topic, recallPrompt, aiProvider);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: content,
    );
  }

  // ── 桌面端分栏布局 ──
  Widget _buildDesktopLayout(
    BuildContext context,
    Topic topic,
    RecallPrompt? recallPrompt,
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
              QuestionPanel(topic: topic, recallPrompt: recallPrompt),
              if (topic.rubric != null) ...[
                const SizedBox(height: 16),
                RubricPanel(rubric: topic.rubric!),
              ],
            ],
          ),
        ),
        // 右侧：输入 + 结果
        Expanded(
          flex: 6,
          child: Column(
            children: [
              PracticeProgress(
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
                      EvaluationResultPanel(
                        result: _evaluationResult!,
                        topic: topic,
                      ),
                    ],
                  ],
                ),
              ),
              NavigationButtons(
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
    Topic topic,
    RecallPrompt? recallPrompt,
    AiProvider aiProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PracticeProgress(
          current: _currentIndex + 1,
          total: widget.topicIds.length,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              QuestionPanel(topic: topic, recallPrompt: recallPrompt),
              const SizedBox(height: 16),
              _buildInputSection(context, aiProvider),
              if (_evaluationResult != null) ...[
                const SizedBox(height: 16),
                EvaluationResultPanel(result: _evaluationResult!, topic: topic),
              ],
              const SizedBox(height: 80), // 底部留空给操作条
            ],
          ),
        ),
        // 底部操作条
        BottomActionBar(
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

  RecallPrompt? _selectedRecallPrompt(Topic topic) {
    final seed = _recallPromptSeeds.putIfAbsent(topic.id, () {
      return context
          .read<ProgressProvider>()
          .getAttemptsForTopic(topic.id)
          .length;
    });
    final mode = _inputMode == 'code' ? 'code' : null;
    return topic.recallPromptAt(seed, mode: mode);
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
        ModelSelector(
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
        AiReadinessNotice(config: selectedConfig),
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
              InputModeTab(
                icon: Icons.notes_outlined,
                label: l10n.get('text_local'),
                value: 'text',
                selected: _inputMode == 'text',
                onTap: () => setState(() => _inputMode = 'text'),
              ),
              InputModeTab(
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
              InputModeTab(
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
              InputModeTab(
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
        AnswerInputField(
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
      final recallPrompt = _selectedRecallPrompt(topic);
      final question = recallPrompt?.prompt ?? topic.title;
      final enabledConfigs = aiProvider.enabledConfigs;
      final aiConfigId =
          _selectedAiConfigId ??
          aiProvider.defaultConfig?.id ??
          (enabledConfigs.isNotEmpty ? enabledConfigs.first.id : null);

      // 使用流式输出
      final streamResult = aiProvider.evaluateAnswerStream(
        aiConfigId: aiConfigId,
        topicId: topicId,
        question: question,
        userAnswer: answer,
        rubric: topic.rubric,
        imageBytes: _selectedImageBytes,
      );

      // 监听流式输出
      _streamSubscription?.cancel();
      _streamSubscription = streamResult.stream.listen(
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
            promptId: recallPrompt?.id ?? '',
            mode: _inputMode == 'code' ? 'code' : 'recall',
            question: question,
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
            final createdAt = DateTime.now().toIso8601String();
            final version = {
              'type': 'ai_modified',
              'content': improvedAnswer,
              'createdAt': createdAt,
              'updatedAt': createdAt,
              'source': 'auto_eval',
            };
            version['id'] = StorageService.answerVersionIdFor(version);
            versions.add(version);
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
    final recallPrompt = _selectedRecallPrompt(topic);
    final question = recallPrompt?.prompt ?? topic.title;
    final enabledConfigs = aiProvider.enabledConfigs;
    final aiConfigId =
        _selectedAiConfigId ??
        aiProvider.defaultConfig?.id ??
        (enabledConfigs.isNotEmpty ? enabledConfigs.first.id : null);
    await progressProvider.addAttempt(
      PracticeAttempt(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        topicId: topicId,
        promptId: recallPrompt?.id ?? '',
        mode: _inputMode == 'code' ? 'code' : 'recall',
        question: question,
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
