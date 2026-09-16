/// 「模拟面试」入口。
///
/// 三种模式（学习 / 回测 / 模拟）共用一个对话界面（§1、§5）；本页只负责
/// 选模式、起会话、进历史，真正的问答在 [CoachSessionPage]。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/domain/common.dart';
import '../../providers/coach_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import 'coach_session_page.dart';
import 'coach_widgets.dart';
import 'training_arrangement_page.dart';
import 'interview_report_page.dart';

class InterviewPage extends StatefulWidget {
  const InterviewPage({super.key});
  @override
  State<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends State<InterviewPage> {
  int _minutes = 20;
  String _style = 'neutral';
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final goal = coach.activeGoal;

    return CoachPageScaffold(
      title: l10n.get('coach_interview_title'),
      subtitle: goal == null
          ? l10n.get('coach_interview_subtitle_no_goal')
          : l10n.getp('coach_interview_subtitle_goal', {'title': goal.title}),
      children: [
        if (goal == null)
          CoachNoticeBanner(
            message: l10n.get('coach_interview_goal_hint'),
            tone: CoachNoticeTone.warning,
          ),

        coachPanel(
          title: l10n.get('coach_interview_choose_mode'),
          icon: Icons.tune,
          children: [
            ...SessionMode.values.map((mode) {
              final selected = coach.mode == mode;
              return InkWell(
                onTap: () => coach.setMode(mode),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : (isDark ? Colors.white38 : Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.get(mode.l10nKey),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.get(mode.descriptionL10nKey),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: isDark
                                    ? Colors.white54
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),

        if (coach.mode == SessionMode.interview)
          coachPanel(
            title: l10n.get('coach_interview_options'),
            icon: Icons.timer_outlined,
            children: [
              Wrap(
                spacing: 8,
                children: [10, 20, 30, 45]
                    .map(
                      (m) => ChoiceChip(
                        label: Text(l10n.getp('coach_minutes', {'minutes': m})),
                        selected: _minutes == m,
                        onSelected: (_) => setState(() => _minutes = m),
                      ),
                    )
                    .toList(),
              ),
              Wrap(
                spacing: 8,
                children: ['neutral', 'supportive', 'pressure']
                    .map(
                      (style) => ChoiceChip(
                        label: Text(l10n.get(_styleKey(style))),
                        selected: _style == style,
                        onSelected: (_) => setState(() => _style = style),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),

        coachPanel(
          title: l10n.get('coach_today_start'),
          icon: Icons.play_arrow_outlined,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.mic_none),
                label: Text(
                  l10n.getp('coach_interview_start', {
                    'label': l10n.get(coach.mode.l10nKey),
                  }),
                ),
                onPressed: _starting || coach.isGenerating
                    ? null
                    : () async {
                        setState(() => _starting = true);
                        try {
                          await coach.startSession(
                            mode: coach.mode,
                            durationMinutes: coach.mode == SessionMode.interview
                                ? _minutes
                                : null,
                            interviewStyle: _style,
                          );
                        } finally {
                          if (mounted) setState(() => _starting = false);
                        }
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CoachSessionPage(mode: coach.mode),
                          ),
                        );
                      },
              ),
            ),
            if (coach.activeSession != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CoachSessionPage(mode: coach.activeSession!.mode),
                    ),
                  );
                },
                child: Text(l10n.get('coach_interview_continue')),
              ),
            ],
          ],
        ),

        coachPanel(
          title: l10n.get('coach_arrange_title'),
          icon: Icons.event_note_outlined,
          children: [
            Text(
              l10n.get('coach_arrange_entry_note'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: isDark ? Colors.white60 : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.tune, size: 16),
              label: Text(l10n.get('coach_arrange_open')),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TrainingArrangementPage(),
                ),
              ),
            ),
          ],
        ),

        coachPanel(
          title: l10n.get('coach_interview_history'),
          icon: Icons.history,
          children: [
            if (coach.sessions.isEmpty)
              CoachEmptyHint(
                icon: Icons.chat_bubble_outline,
                message: l10n.get('coach_interview_history_empty'),
              )
            else
              ...coach.sessions.map(
                (session) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    session.status == RuntimeStatus.completed
                        ? Icons.fact_check_outlined
                        : Icons.chat_bubble_outline,
                  ),
                  title: Text(l10n.get(session.mode.l10nKey)),
                  subtitle: Text(_formatTime(session.createdAt)),
                  onTap: () async {
                    await coach.openSession(session.id);
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            session.status == RuntimeStatus.completed
                            ? InterviewReportPage(
                                sessionId: session.id,
                                mode: session.mode,
                              )
                            : CoachSessionPage(mode: session.mode),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _formatTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

String _styleKey(String style) => switch (style) {
  'supportive' => 'coach_style_supportive',
  'pressure' => 'coach_style_pressure',
  _ => 'coach_style_neutral',
};
