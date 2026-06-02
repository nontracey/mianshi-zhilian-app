import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

class InterviewPrepPage extends StatelessWidget {
  const InterviewPrepPage({
    super.key,
    required this.currentDomainId,
    required this.onStartPractice,
    required this.onStartMock,
  });

  final String currentDomainId;
  final VoidCallback onStartPractice;
  final VoidCallback onStartMock;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final content = context.watch<ContentProvider>();
    final progress = context.watch<ProgressProvider>();
    final topics = content.getTopicsByDomain(currentDomainId);
    final plan = progress.prepPlan;
    final readiness = progress.readinessScore(topics);
    final reviewCount = progress.getTodayReviewTopics(topics).length;
    final lowScoreCount = progress.lowScoreAttempts.length;
    final highFrequencyUnmastered = topics.where((topic) {
      final topicProgress = progress.getTopicProgress(topic.id);
      return topic.highFrequency && (topicProgress?.score ?? 0) < 85;
    }).length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        WorkPanel(
          title: plan.hasTarget
              ? l10n.getp('interview_preparation_role_2', {
                  'role': plan.targetRole,
                })
              : l10n.get('open_use_tech_interview_preparation'),
          trailing: FilledButton.tonalIcon(
            onPressed: () => _showPlanDialog(context, progress, plan, l10n),
            icon: const Icon(Icons.tune_outlined),
            label: Text(
              plan.hasTarget
                  ? l10n.get('schedule_overall_goal')
                  : l10n.get('settings_goal'),
            ),
          ),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final cards = [
                  _PrepMetric(
                    label: l10n.get('interview_readiness'),
                    value: '$readiness',
                    suffix: '/100',
                    color: _scoreColor(readiness),
                  ),
                  _PrepMetric(
                    label: l10n.get('today_day_pending_review'),
                    value: '$reviewCount',
                    suffix: l10n.get('item'),
                    color: AppColors.warning,
                  ),
                  _PrepMetric(
                    label: l10n.get('high_freq_unstable'),
                    value: '$highFrequencyUnmastered',
                    suffix: l10n.get('item'),
                    color: AppColors.accent,
                  ),
                  _PrepMetric(
                    label: l10n.get('low_score_back_flow'),
                    value: '$lowScoreCount',
                    suffix: l10n.get('round'),
                    color: AppColors.danger,
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map(
                        (card) => SizedBox(
                          width: compact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 36) / 4,
                          child: card,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              plan.hasTarget
                  ? _targetDescription(context, plan)
                  : l10n.get(
                      'un_settings_goal_position_also_optional_by_direct_connect_use',
                    ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onStartPractice,
                  icon: const Icon(Icons.today_outlined),
                  label: Text(l10n.get('start_today_day_practice')),
                ),
                OutlinedButton.icon(
                  onPressed: onStartMock,
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: Text(l10n.get('come_one_round_mode_mock_interview')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (plan.jobDescription.trim().isNotEmpty) ...[
          _JdAnalysisSection(
            jobDescription: plan.jobDescription,
            topics: topics,
            progress: progress,
          ),
          const SizedBox(height: 16),
        ],
        WorkPanel(
          title: l10n.get('next_step_suggestion'),
          children: _buildActions(
            context,
            readiness: readiness,
            reviewCount: reviewCount,
            highFrequencyUnmastered: highFrequencyUnmastered,
            hasTarget: plan.hasTarget,
          ),
        ),
        const SizedBox(height: 16),
        WorkPanel(
          title: l10n.get('privacy_and_degrade'),
          children: [
            InfoLine(
              icon: Icons.lock_outline,
              text: l10n.get(
                'goal_position_jd_project_element_material_and_answer_draft_def',
              ),
            ),
            InfoLine(
              icon: Icons.person_outline,
              text: l10n.get(
                'not_login_also_enable_complete_overall_practice_only_use_in',
              ),
            ),
            InfoLine(
              icon: Icons.hub_outlined,
              text: l10n.get('ai_not_configured_practice_falls_back_to_local'),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildActions(
    BuildContext context, {
    required int readiness,
    required int reviewCount,
    required int highFrequencyUnmastered,
    required bool hasTarget,
  }) {
    final l10n = context.watch<LocalizationProvider>();
    final actions = <Widget>[];
    if (reviewCount > 0) {
      actions.add(
        InfoLine(
          icon: Icons.replay_outlined,
          text: l10n.get('clear_today_review_first_avoid_overflow'),
        ),
      );
    }
    if (highFrequencyUnmastered > 0) {
      actions.add(
        InfoLine(
          icon: Icons.local_fire_department_outlined,
          text: l10n.get(
            'priority_sprint_high_freq_unstable_knowledge_point_suitable_combine',
          ),
        ),
      );
    }
    if (readiness < 70) {
      actions.add(
        InfoLine(
          icon: Icons.construction_outlined,
          text: l10n.get(
            'readiness_bias_low_suggestion_first_score_back_flow_again',
          ),
        ),
      );
    } else {
      actions.add(
        InfoLine(
          icon: Icons.groups_outlined,
          text: l10n.get(
            'optional_by_progress_enter_correct_mode_mock_end_after_7',
          ),
        ),
      );
    }
    if (!hasTarget) {
      actions.add(
        InfoLine(
          icon: Icons.flag_outlined,
          text: l10n.get(
            'settings_goal_position_or_paste_jd_after_optional_gain_get_66f',
          ),
        ),
      );
    }
    return actions;
  }

  String _targetDescription(BuildContext context, PrepPlan plan) {
    final l10n = context.watch<LocalizationProvider>();
    final parts = <String>[];
    if (plan.techStack.isNotEmpty) {
      parts.add(
        l10n.getp('tech_stack_techstack_2', {'techStack': plan.techStack}),
      );
    }
    if (plan.dailyMinutes > 0) {
      parts.add(
        l10n.getp('daily_minutes_min_2', {'minutes': plan.dailyMinutes}),
      );
    }
    if (plan.interviewDate != null) {
      final days = plan.interviewDate!.difference(DateTime.now()).inDays + 1;
      parts.add(
        days > 0
            ? l10n.getp('distance_offline_interview_still_has_days_day_2', {
                'days': days,
              })
            : l10n.get('interview_day_already_to'),
      );
    }
    return parts.isEmpty
        ? l10n.get(
            'goal_already_settings_app_will_increase_accent_recommend_rights_restart',
          )
        : parts.join(' · ');
  }

  Color _scoreColor(int score) {
    if (score >= 85) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  void _showPlanDialog(
    BuildContext context,
    ProgressProvider progress,
    PrepPlan current,
    LocalizationProvider l10n,
  ) {
    final roleController = TextEditingController(text: current.targetRole);
    final stackController = TextEditingController(text: current.techStack);
    final jdController = TextEditingController(text: current.jobDescription);
    var dailyMinutes = current.dailyMinutes;
    DateTime? interviewDate = current.interviewDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.get('interview_goal')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: roleController,
                    decoration: InputDecoration(
                      labelText: l10n.get('goal_position_optional_select'),
                      hintText: l10n.get(
                        'java_backend_ai_engineering_transform_architect',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stackController,
                    decoration: InputDecoration(
                      labelText: l10n.get('tech_stack_optional_select'),
                      hintText: 'Spring Cloud, Redis, RAG...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.getp('daily_send_enter_minutes_min_2', {
                            'minutes': dailyMinutes,
                          }),
                        ),
                      ),
                      IconButton(
                        onPressed: dailyMinutes > 15
                            ? () => setDialogState(() => dailyMinutes -= 15)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        onPressed: () =>
                            setDialogState(() => dailyMinutes += 15),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate:
                            interviewDate ??
                            DateTime.now().add(const Duration(days: 14)),
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => interviewDate = picked);
                      }
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      interviewDate == null
                          ? l10n.get('select_interview_day_optional')
                          : l10n.getp('interview_day_year_month_day', {
                              'year': interviewDate!.year,
                              'month': interviewDate!.month,
                              'day': interviewDate!.day,
                            }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: jdController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: l10n.get(
                        'position_description_jd_optional_select_local_save',
                      ),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                progress.updatePrepPlan(
                  PrepPlan(
                    targetRole: roleController.text.trim(),
                    techStack: stackController.text.trim(),
                    interviewDate: interviewDate,
                    dailyMinutes: dailyMinutes,
                    jobDescription: jdController.text.trim(),
                    updatedAt: DateTime.now(),
                  ),
                );
                Navigator.pop(ctx);
              },
              child: Text(l10n.get('save')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrepMetric extends StatelessWidget {
  const _PrepMetric({
    required this.label,
    required this.value,
    required this.suffix,
    required this.color,
  });

  final String label;
  final String value;
  final String suffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(text: ' $suffix'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _JdAnalysisSection extends StatelessWidget {
  const _JdAnalysisSection({
    required this.jobDescription,
    required this.topics,
    required this.progress,
  });

  final String jobDescription;
  final List<Topic> topics;
  final ProgressProvider progress;

  static List<String> _techKeywords(LocalizationProvider l10n) => [
    'java',
    'python',
    'go',
    'golang',
    'rust',
    'c++',
    'javascript',
    'typescript',
    'spring',
    'springboot',
    'spring cloud',
    'mybatis',
    'hibernate',
    'redis',
    'mysql',
    'postgresql',
    'mongodb',
    'elasticsearch',
    'es',
    'kafka',
    'rabbitmq',
    'rocketmq',
    'mq',
    'docker',
    'kubernetes',
    'k8s',
    'linux',
    'nginx',
    l10n.get('microservice'),
    l10n.get('distributed'),
    l10n.get('high_concurrent'),
    l10n.get('ha'),
    l10n.get('cache'),
    l10n.get('message_queue'),
    l10n.get('design_pattern'),
    l10n.get('data_structure'),
    l10n.get('algorithm'),
    l10n.get('system_design'),
    l10n.get('architecture'),
    'jvm',
    'gc',
    l10n.get('concurrent'),
    l10n.get('multi_thread'),
    l10n.get('thread_pool'),
    l10n.get('lock'),
    l10n.get('network'),
    'tcp',
    'http',
    'https',
    'rpc',
    'grpc',
    l10n.get('database'),
    l10n.get('index'),
    l10n.get('transaction'),
    'mvcc',
    l10n.get('b_tree'),
    l10n.get('collect_combine'),
    'hashmap',
    'arraylist',
    l10n.get('chain_surface'),
    l10n.get('tree'),
    l10n.get('graph'),
    l10n.get('sort'),
    l10n.get('two_score'),
    l10n.get('dynamic_state_plan'),
    l10n.get('greedy_core'),
    l10n.get('back_trace'),
    'react',
    'vue',
    'flutter',
    'android',
    'ios',
    l10n.get('machine_device_study'),
    l10n.get('depth_study'),
    'llm',
    'rag',
    'prompt',
    'ci/cd',
    'git',
    'jenkins',
    'devops',
    l10n.get('project'),
    l10n.get('actual_practice'),
    l10n.get('experience'),
  ];

  List<String> _extractKeywords(String jd, LocalizationProvider l10n) {
    final lower = jd.toLowerCase();
    return _techKeywords(l10n).where((kw) => lower.contains(kw)).toList();
  }

  List<Topic> _matchTopics(List<String> keywords) {
    if (keywords.isEmpty) return [];
    final matched = <String, Topic>{};
    for (final topic in topics) {
      final searchText =
          '${topic.title} ${topic.summary} '
                  '${topic.category} ${topic.tags.join(' ')} '
                  '${topic.rubric?.mustHave.join(' ') ?? ''}'
              .toLowerCase();
      for (final kw in keywords) {
        if (searchText.contains(kw)) {
          matched[topic.id] = topic;
          break;
        }
      }
    }
    return matched.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final keywords = _extractKeywords(jobDescription, l10n);
    final matchedTopics = _matchTopics(keywords);

    // 按掌握度排序：未掌握优先
    matchedTopics.sort((a, b) {
      final scoreA = progress.getTopicProgress(a.id)?.score ?? 0;
      final scoreB = progress.getTopicProgress(b.id)?.score ?? 0;
      return scoreA.compareTo(scoreB);
    });

    return WorkPanel(
      title: l10n.get('jd_match_assign_analysis'),
      trailing: Text(
        l10n.getp('count_matches_2', {'count': matchedTopics.length}),
        style: TextStyle(
          fontSize: 12,
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        if (keywords.isEmpty)
          Text(
            l10n.get(
              'un_identify_distinct_to_key_tech_term_please_inspect_check_jd_content',
            ),
          )
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: keywords
                .map(
                  (kw) => Chip(
                    label: Text(kw, style: const TextStyle(fontSize: 11)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          if (matchedTopics.isEmpty)
            Text(
              l10n.get(
                'current_content_library_in_un_find_to_and_jd_match_assign_768',
              ),
            )
          else ...[
            Text(
              l10n.get(
                'suggestion_priority_review_press_mastery_from_low_to_high',
              ),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...matchedTopics.take(10).map((topic) {
              final topicProgress = progress.getTopicProgress(topic.id);
              final score = topicProgress?.score ?? 0;
              final color = score >= 85
                  ? AppColors.success
                  : score >= 60
                  ? AppColors.warning
                  : AppColors.danger;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topic.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            topic.category,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        score > 0 ? '$score' : l10n.get('un_practice'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    );
  }
}
