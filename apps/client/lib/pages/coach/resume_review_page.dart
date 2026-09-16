/// 简历核对页（§6.9、§11）。
///
/// 三件事，按「原文 → 提取物 → 动作」的顺序排：
/// 1. **原文对照**：把简历原文原样展示，供用户逐条比对；
/// 2. **主张确认**：模型提取的主张默认 `pending`，必须由用户点「我确实做过」
///    才升级为可当事实使用；未确认的只用于提问；
/// 3. **项目入口**：「梳理这个项目」/「针对这个项目提问」都以项目为范围起会话。
///
/// 本页**不会**改写简历原文，也不会替用户补写未写明的经历。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../coach/domain/common.dart';
import '../../coach/domain/goal.dart';
import '../../coach/domain/resume.dart';
import '../../providers/coach_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import 'coach_session_page.dart';
import 'coach_widgets.dart';

class ResumeReviewPage extends StatefulWidget {
  const ResumeReviewPage({super.key, this.resumeId});

  /// 指定要核对的简历；不传则用当前档案选中的简历。
  final ResumeId? resumeId;

  @override
  State<ResumeReviewPage> createState() => _ResumeReviewPageState();
}

class _ResumeReviewPageState extends State<ResumeReviewPage> {
  List<Project> _projects = const [];

  /// claimId → 该主张映射到的岗位要求（用于展示「这条主张对应岗位上的什么」）。
  Map<ClaimId, List<GoalRequirement>> _claimTargets = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final coach = context.read<CoachProvider>();
    final store = coach.store;
    final resumeId = widget.resumeId ?? coach.activeResumeId;
    if (resumeId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final projects = await store.listProjects(resumeId);
    final requirements = await store.listGoalRequirements(
      coach.activeGoalId ?? '',
    );
    final byId = {for (final r in requirements) r.id: r};

    final targets = <ClaimId, List<GoalRequirement>>{};
    for (final claim in coach.activeClaims) {
      final links = await store.listClaimRequirementLinks(claim.id);
      final mapped = links
          .map((l) => byId[l.requirementId])
          .whereType<GoalRequirement>()
          .toList();
      if (mapped.isNotEmpty) targets[claim.id] = mapped;
    }

    if (!mounted) return;
    setState(() {
      _projects = projects;
      _claimTargets = targets;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final goals = context.watch<GoalProvider>();
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resume = widget.resumeId == null
        ? coach.activeResume
        : coach.resumes.firstWhere(
            (r) => r.id == widget.resumeId,
            orElse: () =>
                coach.activeResume ??
                Resume(
                  id: widget.resumeId!,
                  profileId: coach.profileId,
                  versionLabel: '',
                  originalText: '',
                  createdAt: DateTime.now(),
                ),
          );
    final claims = coach.activeClaims;

    if (resume == null) {
      return CoachPageScaffold(
        title: l10n.get('coach_resume_review_title'),
        subtitle: l10n.get('coach_resume_review_subtitle'),
        children: [
          CoachEmptyHint(
            icon: Icons.description_outlined,
            message: l10n.get('coach_resume_review_no_resume'),
          ),
        ],
      );
    }

    return CoachPageScaffold(
      title: l10n.get('coach_resume_review_title'),
      subtitle: l10n.get('coach_resume_review_subtitle'),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),

        coachPanel(
          title: l10n.getp('coach_resume_review_claims', {
            'count': claims.length,
          }),
          icon: Icons.fact_check_outlined,
          children: [
            Text(
              l10n.get('coach_goals_claims_note'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: isDark ? Colors.white60 : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (claims.isEmpty)
              CoachEmptyHint(
                icon: Icons.fact_check_outlined,
                message: l10n.get('coach_resume_review_claims_empty'),
              )
            else
              ...claims.map(
                (c) => _ClaimRow(
                  claim: c,
                  targets: _claimTargets[c.id] ?? const [],
                  onConfirm: () =>
                      goals.setClaimStatus(c, ClaimStatus.confirmed),
                  onDispute: () =>
                      goals.setClaimStatus(c, ClaimStatus.disputed),
                  onReset: () => goals.setClaimStatus(c, ClaimStatus.pending),
                ),
              ),
          ],
        ),

        coachPanel(
          title: l10n.getp('coach_resume_review_projects', {
            'count': _projects.length,
          }),
          icon: Icons.account_tree_outlined,
          children: [
            if (_projects.isEmpty)
              CoachEmptyHint(
                icon: Icons.account_tree_outlined,
                message: l10n.get('coach_resume_review_projects_empty'),
              )
            else
              ..._projects.map(
                (p) => _ProjectRow(
                  project: p,
                  onTidy: () => _startProjectSession(
                    coach,
                    projectId: p.id,
                    mode: SessionMode.learning,
                  ),
                  onAsk: () => _startProjectSession(
                    coach,
                    projectId: p.id,
                    mode: SessionMode.interview,
                  ),
                ),
              ),
          ],
        ),

        coachPanel(
          title: l10n.get('coach_resume_review_original'),
          icon: Icons.article_outlined,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceDark
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  resume.originalText,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.65,
                    color: isDark ? Colors.white70 : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _startProjectSession(
    CoachProvider coach, {
    required ProjectId projectId,
    required SessionMode mode,
  }) async {
    await coach.startSession(mode: mode, projectIds: [projectId]);
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CoachSessionPage(mode: mode)));
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow({
    required this.claim,
    required this.targets,
    required this.onConfirm,
    required this.onDispute,
    required this.onReset,
  });

  final ResumeClaim claim;
  final List<GoalRequirement> targets;
  final VoidCallback onConfirm;
  final VoidCallback onDispute;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (label, color) = switch (claim.status) {
      ClaimStatus.pending => (
        l10n.get('coach_goals_claim_pending'),
        AppColors.warning,
      ),
      ClaimStatus.confirmed => (
        l10n.get('coach_goals_claim_confirmed'),
        AppColors.success,
      ),
      ClaimStatus.disputed => (
        l10n.get('coach_goals_claim_disputed'),
        AppColors.danger,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  claim.statement,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          if (claim.originalSpan != null &&
              claim.originalSpan!.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              l10n.getp('coach_resume_review_original_span', {
                'span': claim.originalSpan!,
              }),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: isDark ? Colors.white54 : AppColors.textSecondary,
              ),
            ),
          ],
          if (targets.isNotEmpty) ...[
            const SizedBox(height: 3),
            ...targets
                .take(3)
                .map(
                  (t) => Text(
                    l10n.getp('coach_resume_review_linked_req', {
                      'title': t.title,
                    }),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: isDark ? Colors.white54 : AppColors.textSecondary,
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (claim.status != ClaimStatus.confirmed)
                OutlinedButton(
                  onPressed: onConfirm,
                  child: Text(
                    l10n.get('coach_goals_claim_confirm_action'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              if (claim.status != ClaimStatus.disputed) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onDispute,
                  child: Text(
                    l10n.get('coach_goals_claim_dispute_action'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (claim.status != ClaimStatus.pending) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onReset,
                  child: Text(
                    l10n.get('coach_resume_review_claim_reset'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.onTidy,
    required this.onAsk,
  });

  final Project project;
  final VoidCallback onTidy;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meta = <String>[
      if (project.timeRange != null && project.timeRange!.isNotEmpty)
        project.timeRange!,
      if (project.techStack != null && project.techStack!.isNotEmpty)
        project.techStack!,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.name,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              meta,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white54 : AppColors.textSecondary,
              ),
            ),
          ],
          if (project.responsibilities != null &&
              project.responsibilities!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              project.responsibilities!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: isDark ? Colors.white70 : AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: Text(l10n.get('coach_resume_review_project_tidy')),
                onPressed: onTidy,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.help_outline, size: 16),
                label: Text(l10n.get('coach_resume_review_project_ask')),
                onPressed: onAsk,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
