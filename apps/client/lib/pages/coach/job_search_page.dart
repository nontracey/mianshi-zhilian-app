/// 岗位搜索页（§6.7、§11）。
///
/// 职责边界：
/// - 只**展示**通道返回的真实岗位卡，不做去重/排序/补全，不根据岗位名猜公司或薪资；
/// - 未配置搜索通道时如实说明，并给出「链接导入 / 粘贴 JD」的替代入口，
///   而不是显示一个空的搜索结果列表；
/// - 卡片必须带「完整度」标记：未读到 JD 正文的只能作为线索，
///   选中后才真正建立目标（不选不建）。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../coach/jobs/models.dart';
import '../../coach/jobs/platform_catalog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../pages/profile/job_search_settings_page.dart';
import '../../providers/goal_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import 'coach_widgets.dart';

class JobSearchPage extends StatefulWidget {
  const JobSearchPage({super.key});

  @override
  State<JobSearchPage> createState() => _JobSearchPageState();
}

class _JobSearchPageState extends State<JobSearchPage> {
  final _keywords = TextEditingController();
  final _region = TextEditingController();
  final _salary = TextEditingController();

  List<JobCard> _results = const [];
  bool _running = false;
  bool _truncated = false;
  String? _failureText;
  String? _addedGoalId;

  @override
  void dispose() {
    _keywords.dispose();
    _region.dispose();
    _salary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final goals = context.watch<GoalProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final configured = goals.jobSearchConfigured;
    final publicSearch =
        goals.jobSearchChannel?.mode == JobSearchMode.zhaopinPublic;

    return CoachPageScaffold(
      title: l10n.get('coach_job_search_title'),
      subtitle: l10n.get('coach_job_search_subtitle'),
      children: [
        coachPanel(
          title: l10n.get('coach_job_search_channel'),
          icon: Icons.hub_outlined,
          children: [
            Row(
              children: [
                Icon(
                  configured ? Icons.check_circle_outline : Icons.error_outline,
                  size: 16,
                  color: configured ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 8),
                Text(
                  configured
                      ? l10n.get('coach_job_search_channel_ready')
                      : l10n.get('coach_job_search_channel_missing'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (!configured) ...[
              const SizedBox(height: 6),
              Text(
                l10n.get('coach_job_search_channel_missing_note'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: isDark ? Colors.white60 : AppColors.textSecondary,
                ),
              ),
            ],
            if (publicSearch) Text(l10n.get('coach_job_search_public_note')),
            if (goals.jobSearchChannel?.isDemo ?? false) ...[
              const SizedBox(height: 6),
              Text(
                l10n.get('coach_job_search_demo_note'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.warning,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => context.push(
                  '/profile/job-search',
                  extra: const JobSearchSettingsPage(),
                ),
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: Text(l10n.get('coach_job_search_configure')),
              ),
            ),
          ],
        ),

        coachPanel(
          title: l10n.get('coach_job_search_criteria'),
          icon: Icons.search,
          children: [
            TextField(
              controller: _keywords,
              decoration: InputDecoration(
                labelText: l10n.get('coach_job_search_keywords'),
                hintText: l10n.get('coach_job_search_keywords_hint'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _region,
                    decoration: InputDecoration(
                      labelText: l10n.get('coach_job_search_region'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _salary,
                    enabled: !publicSearch,
                    decoration: InputDecoration(
                      labelText: l10n.get('coach_job_search_salary'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: Text(
                  l10n.get(
                    _running
                        ? 'coach_job_search_running'
                        : 'coach_job_search_run',
                  ),
                ),
                onPressed: (!configured || _running) ? null : _run,
              ),
            ),
            if (_failureText != null) ...[
              const SizedBox(height: 8),
              CoachNoticeBanner(
                message: l10n.getp('coach_job_search_failed', {
                  'reason': _failureText!,
                }),
                tone: CoachNoticeTone.warning,
              ),
            ],
          ],
        ),

        coachPanel(
          title: l10n.get('coach_platform_open_title'),
          icon: Icons.open_in_new,
          children: [
            Text(l10n.get('coach_platform_open_note')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final platform in mainstreamJobPlatforms)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(l10n.get(platform.platform.l10nKey)),
                    onPressed: () async {
                      final opened = await launchUrl(
                        platform.searchUri(_keywords.text),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.get('coach_platform_open_failed'),
                            ),
                          ),
                        );
                    },
                  ),
              ],
            ),
          ],
        ),
        coachPanel(
          title: l10n.getp('coach_job_search_results', {
            'count': _results.length,
          }),
          icon: Icons.work_outline,
          children: [
            if (_truncated)
              CoachNoticeBanner(
                message: l10n.get('coach_job_search_truncated'),
              ),
            if (_results.isEmpty)
              CoachEmptyHint(
                icon: Icons.work_outline,
                message: l10n.get('coach_job_search_empty'),
                actionLabel: l10n.get('coach_job_search_manual'),
                onAction: () => _promptPaste(context),
              )
            else
              ..._results.map(
                (card) => _JobCardTile(
                  card: card,
                  added: _addedGoalId == card.id,
                  onAdd: () => _addCard(card),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _run() async {
    final goals = context.read<GoalProvider>();
    final keywords = _keywords.text.trim();
    if (keywords.isEmpty) return;
    setState(() {
      _running = true;
      _failureText = null;
    });
    try {
      final result = await goals.searchJobsResult(
        SearchQuery(
          keywords: keywords,
          region: _region.text.trim().isEmpty ? null : _region.text.trim(),
          salary:
              goals.jobSearchChannel?.mode == JobSearchMode.zhaopinPublic ||
                  _salary.text.trim().isEmpty
              ? null
              : _salary.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _results = result.cards;
        _truncated = result.truncated;
        _running = false;
      });
    } catch (e) {
      // 通道未配置/协议不符/网络失败都走这里：如实展示原因，不伪造空结果。
      if (!mounted) return;
      setState(() {
        _results = const [];
        _running = false;
        _failureText = _shortError(e);
      });
    }
  }

  /// 把异常压成一行可读原因（供 l10n 占位符使用）。
  static String _shortError(Object e) {
    final s = e.toString();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  Future<void> _addCard(JobCard card) async {
    final goals = context.read<GoalProvider>();
    final l10n = context.read<LocalizationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    // 有链接走链接导入（会去抓正文）；只有摘要时退化为按摘要建目标。
    final outcome = card.url != null
        ? await goals.importJdFromUrl(card.url!)
        : await goals.importJdFromText(
            card.description ?? card.title,
            title: card.title,
            platform: card.platform,
          );
    if (!mounted) return;
    setState(() {
      _addedGoalId = outcome.ok ? card.id : null;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome.ok
              ? l10n.getp('coach_job_search_added', {'title': card.title})
              : coachOutcomeText(l10n, outcome),
        ),
      ),
    );
  }

  Future<void> _promptPaste(BuildContext context) async {
    final goals = context.read<GoalProvider>();
    final l10n = context.read<LocalizationProvider>();
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.get('coach_goals_paste_jd_title')),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 12,
            minLines: 6,
            decoration: InputDecoration(
              hintText: l10n.get('coach_goals_paste_jd_hint'),
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
    if (ok != true) return;
    final outcome = await goals.importJdFromText(controller.text);
    messenger.showSnackBar(
      SnackBar(content: Text(coachOutcomeText(l10n, outcome))),
    );
  }
}

class _JobCardTile extends StatelessWidget {
  const _JobCardTile({
    required this.card,
    required this.added,
    required this.onAdd,
  });

  final JobCard card;
  final bool added;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomplete =
        card.completeness == 'summary' ||
        card.completeness == 'link_only' ||
        card.completeness == 'demo';

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  card.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _Chip(text: l10n.get(card.platform.l10nKey)),
              const SizedBox(width: 4),
              _Chip(text: _completenessLabel(l10n), muted: !incomplete),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle(),
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: isDark ? Colors.white60 : AppColors.textSecondary,
            ),
          ),
          if (card.description != null &&
              card.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              card.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: isDark ? Colors.white54 : AppColors.textSecondary,
              ),
            ),
          ],
          if (incomplete) ...[
            const SizedBox(height: 6),
            Text(
              card.completeness == 'link_only'
                  ? l10n.get('coach_job_search_link_only')
                  : l10n.get('coach_job_search_partial_warning'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.warning,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: added
                ? Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.get('coach_job_search_added_short'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  )
                : OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(l10n.get('coach_job_search_add')),
                    onPressed: onAdd,
                  ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      if (card.company != null && card.company!.isNotEmpty) card.company!,
      if (card.location != null && card.location!.isNotEmpty) card.location!,
      if (card.salaryText != null && card.salaryText!.isNotEmpty)
        card.salaryText!,
    ];
    return parts.join(' · ');
  }

  String _completenessLabel(LocalizationProvider l10n) {
    switch (card.completeness) {
      case 'full':
        return l10n.get('coach_job_search_completeness_full');
      case 'partial':
        return l10n.get('coach_job_search_completeness_partial');
      case 'summary':
        return l10n.get('coach_job_search_completeness_summary');
      case 'link_only':
        return l10n.get('coach_job_search_completeness_link_only');
      case 'demo':
        return l10n.get('coach_job_search_completeness_demo');
      default:
        return card.completeness;
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.muted = true});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = muted
        ? (isDark ? Colors.white38 : Colors.grey)
        : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
    );
  }
}
