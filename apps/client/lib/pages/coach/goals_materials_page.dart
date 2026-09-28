/// 「目标与资料」入口：导入并管理目标 JD、简历、参考资料。
///
/// 全部导入都保留「原文 + 出处 + 待确认标记」：AI 提取的内容默认是草稿，
/// 未经用户确认不作为事实进入出题依据（§6.9）。
library;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../../coach/domain/common.dart';
import '../../coach/domain/goal.dart';
import '../../coach/domain/resume.dart';
import '../../coach/knowledge/source.dart';
import '../../providers/coach_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import 'coach_widgets.dart';
import 'deletion_preview_page.dart';
import 'job_search_page.dart';
import 'resume_review_page.dart';

class GoalsMaterialsPage extends StatelessWidget {
  const GoalsMaterialsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final goals = context.watch<GoalProvider>();
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CoachPageScaffold(
      title: l10n.get('coach_goals_title'),
      subtitle: l10n.get('coach_goals_subtitle'),
      children: [
        if (goals.busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (goals.lastOutcome != null)
          CoachNoticeBanner(
            message: coachOutcomeText(l10n, goals.lastOutcome!),
            tone: goals.lastOutcome!.ok
                ? CoachNoticeTone.info
                : CoachNoticeTone.warning,
          ),

        // 目标 JD
        coachPanel(
          title: l10n.getp('coach_goals_section_targets', {
            'count': coach.goals.length,
          }),
          icon: Icons.flag_outlined,
          children: [
            if (coach.goals.isEmpty)
              CoachEmptyHint(
                icon: Icons.flag_outlined,
                message: l10n.get('coach_goals_targets_empty'),
              )
            else
              ...coach.goals.map(
                (g) => _GoalTile(
                  goal: g,
                  selected: g.id == coach.activeGoalId,
                  onSelect: () => coach.selectGoal(g.id),
                  onDelete: () => openDeletionPreview(context, goalIds: [g.id]),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(l10n.get('coach_job_search_title')),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JobSearchPage()),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(l10n.get('coach_goals_import_link')),
                  onPressed: () => _promptLinkImport(context, goals, l10n),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: Text(l10n.get('coach_goals_paste_jd')),
                  onPressed: () => _promptTextImport(
                    context,
                    l10n: l10n,
                    title: l10n.get('coach_goals_paste_jd_title'),
                    hint: l10n.get('coach_goals_paste_jd_hint'),
                    onSubmit: (text) => goals.importJdFromText(text),
                  ),
                ),
              ],
            ),
          ],
        ),

        // 当前目标的要求
        if (coach.activeGoal != null)
          coachPanel(
            title: l10n.getp('coach_goals_section_requirements', {
              'count': coach.activeRequirements.length,
            }),
            icon: Icons.list_alt,
            children: [
              if (coach.activeRequirements.isEmpty)
                CoachEmptyHint(
                  icon: Icons.list_alt,
                  message: l10n.get('coach_goals_requirements_empty'),
                )
              else
                ..._sortedRequirements(coach.activeRequirements).map(
                  (r) => _RequirementTile(
                    requirement: r,
                    l10n: l10n,
                    onEdit: () => _editRequirement(context, goals, r, l10n),
                  ),
                ),
            ],
          ),

        // 简历
        coachPanel(
          title: l10n.getp('coach_goals_section_resumes', {
            'count': coach.resumes.length,
          }),
          icon: Icons.description_outlined,
          children: [
            if (coach.resumes.isEmpty)
              CoachEmptyHint(
                icon: Icons.description_outlined,
                message: l10n.get('coach_goals_resumes_empty'),
              )
            else
              ...coach.resumes.map(
                (r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  selected: r.id == coach.activeResumeId,
                  leading: const Icon(Icons.description_outlined, size: 18),
                  title: Text(r.versionLabel),
                  subtitle: Text(
                    r.fileName ??
                        l10n.getp('coach_goals_resume_chars', {
                          'count': r.originalText.length,
                        }),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => coach.selectResume(r.id),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: Text(l10n.get('coach_resume_review_title')),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ResumeReviewPage(resumeId: coach.activeResumeId),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: Text(l10n.get('coach_goals_paste_resume')),
                  onPressed: () => _promptTextImport(
                    context,
                    l10n: l10n,
                    title: l10n.get('coach_goals_paste_resume_title'),
                    hint: l10n.get('coach_goals_paste_resume_hint'),
                    onSubmit: (text) => goals.importResumeFromText(
                      text,
                      versionLabel: 'v${coach.resumes.length + 1}',
                      requirements: coach.activeRequirements,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file_outlined, size: 16),
                  label: Text(l10n.get('file')),
                  onPressed: () => _pickResumeFile(context, goals, coach, l10n),
                ),
              ],
            ),
          ],
        ),

        // 待确认主张
        if (coach.activeClaims.isNotEmpty)
          coachPanel(
            title: l10n.get('coach_goals_section_claims'),
            icon: Icons.fact_check_outlined,
            children: [
              Text(
                l10n.get('coach_goals_claims_note'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? Colors.white54 : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ...coach.activeClaims.map(
                (c) => _ClaimTile(
                  claim: c,
                  l10n: l10n,
                  onConfirm: () =>
                      goals.setClaimStatus(c, ClaimStatus.confirmed),
                  onDispute: () =>
                      goals.setClaimStatus(c, ClaimStatus.disputed),
                ),
              ),
            ],
          ),

        // 参考资料
        coachPanel(
          title: l10n.getp('coach_goals_section_sources', {
            'count': coach.sources.length,
          }),
          icon: Icons.library_books_outlined,
          children: [
            if (coach.sources.isEmpty)
              CoachEmptyHint(
                icon: Icons.library_books_outlined,
                message: l10n.get('coach_goals_sources_empty'),
              )
            else
              ...coach.sources.map(
                (src) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(_sourceIcon(src.type), size: 18),
                  title: Text(
                    l10n.get(src.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    l10n.getp('coach_goals_source_meta', {
                      'type': src.type.name,
                      'revision': src.revision,
                      'status': src.status.name,
                    }),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: l10n.get('coach_source_update'),
                    icon: const Icon(Icons.edit_document, size: 19),
                    onPressed:
                        goals.busy ||
                            coach.isGenerating ||
                            src.status != IngestionStatus.ready
                        ? null
                        : () => _promptTextImport(
                            context,
                            l10n: l10n,
                            title: l10n.get('coach_source_update'),
                            hint: l10n.get('coach_source_update_hint'),
                            initialText: src.content,
                            onSubmit: (text) =>
                                goals.updateDocumentSource(src, text),
                          ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.get('coach_goals_add_source')),
              onPressed: () => _promptTextImport(
                context,
                l10n: l10n,
                title: l10n.get('coach_goals_add_source_title'),
                hint: l10n.get('coach_goals_add_source_hint'),
                onSubmit: (text) => goals.importDocument(
                  text: text,
                  title: l10n.getp('coach_goals_source_default_name', {
                    'index': coach.sources.length + 1,
                  }),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static List<GoalRequirement> _sortedRequirements(List<GoalRequirement> list) {
    final copy = [...list]
      ..sort((a, b) => b.importance.index.compareTo(a.importance.index));
    return copy;
  }

  static IconData _sourceIcon(SourceType type) {
    switch (type) {
      case SourceType.markdown:
        return Icons.code;
      case SourceType.txt:
      case SourceType.paste:
        return Icons.article_outlined;
      case SourceType.pdf:
        return Icons.picture_as_pdf_outlined;
      case SourceType.docx:
        return Icons.description_outlined;
      case SourceType.web:
        return Icons.language;
    }
  }

  static Future<void> _pickResumeFile(
    BuildContext context,
    GoalProvider goals,
    CoachProvider coach,
    LocalizationProvider l10n,
  ) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !context.mounted) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    final messenger = ScaffoldMessenger.of(context);
    if (bytes == null || bytes.isEmpty) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.get('coach_import_parse_failed'))),
      );
      return;
    }
    final outcome = await goals.importResumeFromBytes(
      bytes,
      fileName: file.name,
      versionLabel: 'v${coach.resumes.length + 1}',
      requirements: coach.activeRequirements,
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(coachOutcomeText(l10n, outcome))),
    );
  }

  static Future<void> _editRequirement(
    BuildContext context,
    GoalProvider goals,
    GoalRequirement requirement,
    LocalizationProvider l10n,
  ) async {
    final controller = TextEditingController(text: requirement.title);
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.get('edit')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.get('coach_job_search_keywords'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(controller.text.trim()),
            child: Text(l10n.get('save')),
          ),
        ],
      ),
    );
    try {
      final title = edited?.trim();
      if (title == null || title.isEmpty || title == requirement.title) return;
      await goals.updateRequirement(
        requirement.copyWith(title: title, inferred: false),
      );
    } finally {
      disposeControllersNextFrame([controller]);
    }
  }

  static Future<void> _promptLinkImport(
    BuildContext context,
    GoalProvider goals,
    LocalizationProvider l10n,
  ) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.get('coach_goals_import_link_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.get('coach_goals_link_label'),
            hintText: kJobLinkExample,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n.get('coach_goals_import')),
          ),
        ],
      ),
    );
    try {
      if (ok != true) return;
      final outcome = await goals.importJdFromUrl(controller.text.trim());
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(coachOutcomeText(l10n, outcome))),
      );
    } finally {
      disposeControllersNextFrame([controller]);
    }
  }

  static Future<void> _promptTextImport(
    BuildContext context, {
    required LocalizationProvider l10n,
    required String title,
    required String hint,
    required Future<ImportOutcome> Function(String text) onSubmit,
    String? initialText,
  }) async {
    final controller = TextEditingController(text: initialText);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 12,
            minLines: 6,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n.get('coach_goals_import')),
          ),
        ],
      ),
    );
    try {
      if (ok != true) return;
      final outcome = await onSubmit(controller.text);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(coachOutcomeText(l10n, outcome))),
      );
    } finally {
      disposeControllersNextFrame([controller]);
    }
  }
}

/// 岗位链接输入框的示例（非 UI 文案，是格式示范）。
const String kJobLinkExample = 'https://example.com/job/detail/123456.html';

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    required this.selected,
    required this.onSelect,
    required this.onDelete,
  });

  final Goal goal;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      selected: selected,
      leading: Icon(
        selected ? Icons.flag : Icons.flag_outlined,
        size: 18,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(goal.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (goal.company != null) goal.company!,
          if (goal.location != null) goal.location!,
          if (goal.salaryText != null) goal.salaryText!,
          goal.extractionStatus,
        ].join(' · '),
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white54 : AppColors.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        tooltip: l10n.get('coach_goals_delete_goal'),
        // 删除一律走影响预览（§6.8）：先看清会动到哪些知识，
        // 已学内容必须由用户逐项决定，默认只删这个 JD。
        onPressed: onDelete,
      ),
      onTap: onSelect,
    );
  }
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile({
    required this.requirement,
    required this.l10n,
    required this.onEdit,
  });

  final GoalRequirement requirement;
  final LocalizationProvider l10n;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (requirement.importance) {
      Importance.high => AppColors.danger,
      Importance.medium => AppColors.warning,
      Importance.low => AppColors.info,
    };
    final label = switch (requirement.importance) {
      Importance.high => l10n.get('coach_goals_importance_high'),
      Importance.medium => l10n.get('coach_goals_importance_medium'),
      Importance.low => l10n.get('coach_goals_importance_low'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        requirement.title,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      tooltip: l10n.get('edit'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (requirement.inferred)
                  Text(
                    l10n.get('coach_goals_inferred'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({
    required this.claim,
    required this.l10n,
    required this.onConfirm,
    required this.onDispute,
  });

  final ResumeClaim claim;
  final LocalizationProvider l10n;
  final VoidCallback onConfirm;
  final VoidCallback onDispute;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusLabel = switch (claim.status) {
      ClaimStatus.pending => l10n.get('coach_goals_claim_pending'),
      ClaimStatus.confirmed => l10n.get('coach_goals_claim_confirmed'),
      ClaimStatus.disputed => l10n.get('coach_goals_claim_disputed'),
    };
    final color = switch (claim.status) {
      ClaimStatus.pending => AppColors.warning,
      ClaimStatus.confirmed => AppColors.success,
      ClaimStatus.disputed => AppColors.danger,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  claim.statement,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (claim.status == ClaimStatus.pending)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 4),
              child: Row(
                children: [
                  TextButton(
                    onPressed: onConfirm,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    child: Text(
                      l10n.get('coach_goals_claim_confirm_action'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: onDispute,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    child: Text(
                      l10n.get('coach_goals_claim_dispute_action'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
