/// 场后复盘：把本轮的原答、出题依据与待补缺口摊开给用户看（§11）。
///
/// 三条硬约束：
/// 1. **不泄题**：复盘只在会话结束后进入，过程中不展示评分与讲解；
/// 2. **不编造**：未接入模型时，只做确定性统计（原答条数、依据类型、缺口），
///    并如实说明「没有自动点评」，绝不伪造评语；
/// 3. **缺口是提示而非判决**：缺口按「岗位要求有没有对应知识点」确定性计算，
///    与「你答得好不好」无关，界面里必须写清这一点。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/domain/common.dart';
import '../../coach/domain/goal.dart';
import '../../coach/domain/evidence.dart';
import '../../coach/domain/session.dart';
import '../../coach/persistence/coach_store.dart';
import '../../providers/coach_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import 'coach_widgets.dart';

/// 一条「岗位要求 ↔ 知识点」的覆盖判断结果（确定性计算）。
class _CoverageRow {
  const _CoverageRow({required this.requirement, required this.covered});

  final GoalRequirement requirement;
  final bool covered;
}

/// 复盘数据加载失败（会话不属于本档案或存储不可用）。
class CoachReportLoadException implements Exception {
  const CoachReportLoadException(this.reason);
  final String reason;
  @override
  String toString() => 'CoachReportLoadException: $reason';
}

class InterviewReportPage extends StatefulWidget {
  const InterviewReportPage({
    super.key,
    required this.sessionId,
    required this.mode,
  });

  final SessionId sessionId;
  final SessionMode mode;

  @override
  State<InterviewReportPage> createState() => _InterviewReportPageState();
}

class _InterviewReportPageState extends State<InterviewReportPage> {
  List<CoachMessage> _answers = const [];
  List<AssessmentEvent> _events = const [];
  List<_CoverageRow> _coverage = const [];
  CoachSession? _session;
  bool _loading = true;
  bool _reviewing = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    // 首帧后再读 provider，避免在 build 期间触发 notifyListeners。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final coach = context.read<CoachProvider>();
    final store = coach.store;
    try {
      await _loadInto(coach, store);
    } catch (_) {
      // 加载失败必须让用户看到并可重试，不能停在永久转圈里。
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadInto(CoachProvider coach, CoachStore store) async {
    final messages = await store.messagesOf(widget.sessionId);
    final session = await store.getSession(widget.sessionId);

    final answers = messages.where((m) => m.role == 'user').toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));

    if (session?.profileId != coach.profileId) {
      throw const CoachReportLoadException('Session scope mismatch');
    }
    final events = await store.listAssessmentEvents(widget.sessionId);
    final snapshot = session?.coverageSnapshot;
    final asked = messages
        .expand((m) => m.references)
        .where((r) => r.startsWith('reviewPoint:'))
        .map((r) => r.substring('reviewPoint:'.length))
        .toSet();
    final testedKnowledge = (snapshot?.reviewPoints ?? [])
        .where((p) => asked.contains(p['id']))
        .map((p) => p['knowledgeItemId'])
        .toSet();
    final coveredRequirements = (snapshot?.knowledgeLinks ?? [])
        .where((l) => testedKnowledge.contains(l['knowledgeItemId']))
        .expand((l) => (l['requirementIds'] as List? ?? []))
        .toSet();
    final coverage = (snapshot?.requirements ?? [])
        .map(
          (r) => _CoverageRow(
            requirement: GoalRequirement.fromJson(r),
            covered: coveredRequirements.contains(r['id']),
          ),
        )
        .toList();

    if (!mounted) return;
    setState(() {
      _answers = answers;
      _events = events;
      _coverage = coverage;
      _session = session;
      _loading = false;
    });
  }

  Future<void> _review(AssessmentEvent event, bool reassess) async {
    setState(() => _reviewing = true);
    try {
      await context.read<CoachProvider>().reviewAssessment(
        event,
        reassess: reassess,
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LocalizationProvider>().get(
                'coach_assessment_review_failed',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coach = context.watch<CoachProvider>();

    if (_loading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        appBar: AppBar(
          title: Text(l10n.get('coach_report_title')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadFailed) {
      return CoachPageScaffold(
        title: l10n.get('coach_report_title'),
        subtitle: l10n.get('coach_report_subtitle'),
        children: [
          CoachNoticeBanner(
            message: l10n.get('coach_report_load_failed'),
            tone: CoachNoticeTone.warning,
            action: TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _loadFailed = false;
                });
                _load();
              },
              child: Text(l10n.get('retry')),
            ),
          ),
        ],
      );
    }

    if (_session?.status != RuntimeStatus.completed) {
      return CoachPageScaffold(
        title: l10n.get('coach_report_title'),
        subtitle: l10n.get('coach_report_subtitle'),
        children: [
          CoachNoticeBanner(message: l10n.get('coach_report_finish_first')),
        ],
      );
    }
    final latest = <String, AssessmentEvent>{};
    for (final e in _events) {
      final prior = latest[e.turnGroupId];
      if (prior == null || e.assessmentRevision > prior.assessmentRevision) {
        latest[e.turnGroupId] = e;
      }
    }
    final gaps = _coverage.where((r) => !r.covered).toList();

    return CoachPageScaffold(
      title: l10n.get('coach_report_title'),
      subtitle: l10n.get('coach_report_subtitle'),
      children: [
        // 未接入模型时如实说明「没有自动点评」，不把「无评价」包装成「评价已通过」。
        if (_events.isEmpty)
          CoachNoticeBanner(
            message: coach.modelConfigured
                ? l10n.get('coach_report_no_assessment')
                : l10n.get('coach_report_no_model'),
          ),
        if (_session?.partial == true)
          CoachNoticeBanner(message: l10n.get('coach_report_partial')),
        if (_events.isNotEmpty)
          coachPanel(
            title: l10n.get('coach_report_evidence'),
            icon: Icons.fact_check_outlined,
            children: latest.values
                .map(
                  (e) => ExpansionTile(
                    title: Text(l10n.get(_outcomeKey(e.result))),
                    subtitle: Text(
                      '${e.askedDimensions.join(', ')} · ${l10n.get(_validityKey(e.validity))}\n${e.rationale ?? ''}',
                    ),
                    children: [
                      if (_reviewing) const LinearProgressIndicator(),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (e.validity != EvidenceValidity.disputed)
                            TextButton.icon(
                              icon: const Icon(Icons.flag_outlined),
                              label: Text(l10n.get('coach_assessment_dispute')),
                              onPressed: _reviewing
                                  ? null
                                  : () => _review(e, false),
                            ),
                          if (e.validity == EvidenceValidity.disputed)
                            TextButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                l10n.get('coach_assessment_reassess'),
                              ),
                              onPressed:
                                  _reviewing ||
                                      !context
                                          .read<CoachProvider>()
                                          .modelConfigured
                                  ? null
                                  : () => _review(e, true),
                            ),
                        ],
                      ),
                      Text(l10n.get('coach_assessment_history_note')),
                      for (final old in _events.where(
                        (old) =>
                            old.turnGroupId == e.turnGroupId && old.id != e.id,
                      ))
                        ListTile(
                          title: Text(
                            l10n.getp('coach_assessment_revision', {
                              'revision': old.assessmentRevision,
                            }),
                          ),
                          subtitle: Text(
                            '${l10n.get(_outcomeKey(old.result))} · ${l10n.get(_validityKey(old.validity))}\n${old.rationale ?? ''}',
                          ),
                        ),
                    ],
                  ),
                )
                .toList(),
          ),

        coachPanel(
          title: l10n.getp('coach_report_answers', {'count': _answers.length}),
          icon: Icons.record_voice_over_outlined,
          children: [
            if (_answers.isEmpty)
              CoachEmptyHint(
                icon: Icons.record_voice_over_outlined,
                message: l10n.get('coach_report_answers_empty'),
              )
            else
              ..._answers.map((m) => _AnswerCard(message: m)),
          ],
        ),

        coachPanel(
          title: l10n.get('coach_report_basis'),
          icon: Icons.link_outlined,
          children: [_BasisRow(basis: _basisKind(l10n))],
        ),

        coachPanel(
          title: l10n.getp('coach_report_gaps', {'count': gaps.length}),
          icon: Icons.rule_outlined,
          children: [
            Text(
              l10n.get('coach_report_gaps_note'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: isDark ? Colors.white60 : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (_coverage.isEmpty)
              CoachEmptyHint(
                icon: Icons.rule_outlined,
                message: l10n.get('coach_report_gaps_empty'),
              )
            else
              ...gaps.take(12).map((r) => _GapRow(requirement: r.requirement)),
            if (gaps.isEmpty && _coverage.isNotEmpty)
              CoachEmptyHint(
                icon: Icons.check_circle_outline,
                message: l10n.get('coach_report_gaps_none'),
              ),
          ],
        ),

        coachPanel(
          title: l10n.get('coach_report_coverage'),
          icon: Icons.checklist_outlined,
          children: [
            ..._coverage.take(20).map((r) => _CoverageRowTile(row: r)),
          ],
        ),
      ],
    );
  }

  /// 出题依据：本轮的会话快照决定，不看事后是否切换了目标。
  String _basisKind(LocalizationProvider l10n) {
    final session = _session;
    if (session == null) return l10n.get('coach_report_basis_general');
    final hasGoal = session.goalId != null;
    final hasResume = session.resumeId != null;
    if (hasGoal && hasResume) {
      return l10n.get('coach_report_basis_jd_resume');
    }
    if (hasGoal) return l10n.get('coach_report_basis_jd_only');
    if (hasResume) return l10n.get('coach_report_basis_resume_only');
    return l10n.get('coach_report_basis_general');
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.message});

  final CoachMessage message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark
            : AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        message.content,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.55,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _BasisRow extends StatelessWidget {
  const _BasisRow({required this.basis});

  final String basis;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.link_outlined,
          size: 16,
          color: isDark ? Colors.white38 : Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            basis,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _GapRow extends StatelessWidget {
  const _GapRow({required this.requirement});

  final GoalRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.circle_outlined,
            size: 14,
            color: AppColors.warning.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requirement.title,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                if (requirement.summary != null &&
                    requirement.summary!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    requirement.summary!,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: isDark ? Colors.white54 : AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverageRowTile extends StatelessWidget {
  const _CoverageRowTile({required this.row});

  final _CoverageRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            row.covered ? Icons.check_circle_outline : Icons.error_outline,
            size: 15,
            color: row.covered ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.requirement.title,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? Colors.white70 : AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            row.covered
                ? l10n.get('coach_report_covered')
                : l10n.get('coach_report_uncovered'),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

String _outcomeKey(ReviewOutcome outcome) => switch (outcome) {
  ReviewOutcome.independentPass => 'coach_result_independent_pass',
  ReviewOutcome.needsReinforcement => 'coach_result_needs_reinforcement',
  ReviewOutcome.hintCompleted => 'coach_result_hint_completed',
};
String _validityKey(EvidenceValidity validity) => switch (validity) {
  EvidenceValidity.accepted => 'coach_validity_accepted',
  EvidenceValidity.pending => 'coach_validity_pending',
  EvidenceValidity.disputed => 'coach_validity_disputed',
};
