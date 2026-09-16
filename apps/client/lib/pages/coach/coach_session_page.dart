/// 统一会话页：学习 / 回测 / 模拟三种模式共用一套对话界面。
///
/// 设计约束（§1、§5、§7.3）：
/// - 三种模式**不**在 UI 上分叉，差别只在提示词规则与 [ModePolicy] 边界；
/// - 每轮完整保存用户原答，不做前端裁剪；
/// - 模型未接入时如实提示「不会编造评语」，而不是假装有反馈；
/// - 结束时进入复盘页，评分/讲解只在**结束后**展示，避免过程中泄题。
library;

import 'package:flutter/material.dart';
import '../../widgets/voice_input_button.dart';
import '../../providers/settings_provider.dart';
import 'package:provider/provider.dart';

import '../../coach/domain/common.dart';
import '../../coach/domain/session.dart';
import '../../providers/coach_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import 'coach_widgets.dart';
import 'interview_report_page.dart';

/// 会话页：一个模式下的一轮轮问答。
class CoachSessionPage extends StatefulWidget {
  const CoachSessionPage({super.key, required this.mode});

  final SessionMode mode;

  @override
  State<CoachSessionPage> createState() => _CoachSessionPageState();
}

class _CoachSessionPageState extends State<CoachSessionPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final coach = context.read<CoachProvider>();
      if (coach.messages.isEmpty &&
          coach.modelConfigured &&
          !coach.isGenerating) {
        try {
          await coach.generateCurrentReply();
        } catch (_) {
          /* Durable error shown below. */
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messages = coach.messages;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: Text(
          l10n.getp('coach_interview_session_title', {
            'label': l10n.get(
              (coach.activeSession?.mode ?? widget.mode).l10nKey,
            ),
          }),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => _finish(
              context,
              openReport:
                  (coach.activeSession?.mode ?? widget.mode) ==
                  SessionMode.interview,
            ),
            child: Text(l10n.get('coach_interview_end')),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: CoachNoticeBanner(
                message: l10n.get('coach_interview_notice'),
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: CoachEmptyHint(
                          icon: Icons.forum_outlined,
                          message: l10n.get('coach_interview_empty'),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: messages.length,
                      itemBuilder: (_, i) =>
                          _MessageBubble(message: messages[i]),
                    ),
            ),
            if (coach.isGenerating)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  TextButton(
                    onPressed: coach.cancelGeneration,
                    child: Text(l10n.get('cancel')),
                  ),
                ],
              ),
            if (coach.lastGenerationError != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(child: Text(l10n.get('coach_generation_failed'))),
                    TextButton(
                      onPressed: coach.isGenerating
                          ? null
                          : () async {
                              try {
                                await coach.generateCurrentReply();
                              } catch (_) {}
                            },
                      child: Text(l10n.get('retry')),
                    ),
                  ],
                ),
              ),
            if (coach.activeSession?.status == RuntimeStatus.completed)
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => InterviewReportPage(
                      sessionId: coach.activeSession!.id,
                      mode: coach.activeSession!.mode,
                    ),
                  ),
                ),
                child: Text(l10n.get('coach_report_title')),
              )
            else if (!coach.isGenerating)
              _Composer(
                controller: _controller,
                onSubmit: _submit,
                hintText: l10n.get(
                  (coach.activeSession?.mode ?? widget.mode) ==
                          SessionMode.learning
                      ? 'coach_interview_input_learning'
                      : 'coach_interview_input_review',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final coach = context.read<CoachProvider>();
    await coach.sendUserMessage(text);
    if (!mounted) return;
    if (_controller.text.trim() == text) _controller.clear();
    // 滚动到底部。
    if (_scroll.hasClients) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    }
  }

  /// 结束会话。[openReport] 为真时进入复盘页（模拟模式默认如此）。
  Future<void> _finish(BuildContext context, {required bool openReport}) async {
    final coach = context.read<CoachProvider>();
    final sessionId = coach.activeSession?.id;
    final mode = coach.activeSession?.mode ?? widget.mode;
    await coach.endSession();
    if (!context.mounted) return;
    if (!openReport || sessionId == null) {
      Navigator.of(context).pop();
      return;
    }
    // 用「复盘」替换当前会话页：结束后不应再回到答题界面。
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => InterviewReportPage(sessionId: sessionId, mode: mode),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final CoachMessage message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.role == 'user';
    final bg = isUser
        ? (isDark
              ? AppColors.surfaceDarkHigh
              : AppColors.accent.withValues(alpha: 0.1))
        : (isDark ? AppColors.surfaceDark : Colors.white);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: SelectableText(
          message.content,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSubmit,
    required this.hintText,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: hintText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (context.read<SettingsProvider?>() != null)
            VoiceInputButton(
              onResult: (text) {
                final before = controller.text;
                controller.text = before.isEmpty ? text : '$before\n$text';
                controller.selection = TextSelection.collapsed(
                  offset: controller.text.length,
                );
              },
            ),
          IconButton.filled(onPressed: onSubmit, icon: const Icon(Icons.send)),
        ],
      ),
    );
  }
}
