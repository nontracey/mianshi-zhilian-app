import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

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
          title: plan.hasTarget ? '面试准备 · ${plan.targetRole}' : '通用技术面试准备',
          trailing: FilledButton.tonalIcon(
            onPressed: () => _showPlanDialog(context, progress, plan),
            icon: const Icon(Icons.tune_outlined),
            label: Text(plan.hasTarget ? '调整目标' : '设置目标'),
          ),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final cards = [
                  _PrepMetric(
                    label: '面试就绪度',
                    value: '$readiness',
                    suffix: '/100',
                    color: _scoreColor(readiness),
                  ),
                  _PrepMetric(
                    label: '今日待复习',
                    value: '$reviewCount',
                    suffix: '项',
                    color: AppColors.warning,
                  ),
                  _PrepMetric(
                    label: '高频未稳',
                    value: '$highFrequencyUnmastered',
                    suffix: '项',
                    color: AppColors.accent,
                  ),
                  _PrepMetric(
                    label: '低分回流',
                    value: '$lowScoreCount',
                    suffix: '次',
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
                  ? _targetDescription(plan)
                  : '未设置目标岗位也可以直接使用。当前按通用技术面试路径推荐复习、高频题和模拟面试。',
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
                  label: const Text('开始今日练习'),
                ),
                OutlinedButton.icon(
                  onPressed: onStartMock,
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: const Text('来一场模拟面试'),
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
          title: '下一步建议',
          children: _buildActions(
            readiness: readiness,
            reviewCount: reviewCount,
            highFrequencyUnmastered: highFrequencyUnmastered,
            hasTarget: plan.hasTarget,
          ),
        ),
        const SizedBox(height: 16),
        WorkPanel(
          title: '隐私与降级',
          children: const [
            InfoLine(
              icon: Icons.lock_outline,
              text: '目标岗位、JD、项目素材和回答草稿默认只保存在本地。',
            ),
            InfoLine(
              icon: Icons.person_outline,
              text: '不登录也能完整练习；登录只用于云端备份和跨设备恢复。',
            ),
            InfoLine(
              icon: Icons.hub_outlined,
              text: '未配置 AI 模型时，练习会降级为本地作答、自评和参考回答。',
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildActions({
    required int readiness,
    required int reviewCount,
    required int highFrequencyUnmastered,
    required bool hasTarget,
  }) {
    final actions = <Widget>[];
    if (reviewCount > 0) {
      actions.add(
        const InfoLine(icon: Icons.replay_outlined, text: '先清今日复习，避免到期内容继续遗忘。'),
      );
    }
    if (highFrequencyUnmastered > 0) {
      actions.add(
        const InfoLine(
          icon: Icons.local_fire_department_outlined,
          text: '优先冲刺高频未稳知识点，适合临近面试。',
        ),
      );
    }
    if (readiness < 70) {
      actions.add(
        const InfoLine(
          icon: Icons.construction_outlined,
          text: '就绪度偏低，建议先低分回流，再做模拟面试。',
        ),
      );
    } else {
      actions.add(
        const InfoLine(
          icon: Icons.groups_outlined,
          text: '可以进入正式模拟模式，结束后统一复盘。',
        ),
      );
    }
    if (!hasTarget) {
      actions.add(
        const InfoLine(
          icon: Icons.flag_outlined,
          text: '设置目标岗位或粘贴 JD 后，可获得更贴近岗位的准备建议。',
        ),
      );
    }
    return actions;
  }

  String _targetDescription(PrepPlan plan) {
    final parts = <String>[];
    if (plan.techStack.isNotEmpty) parts.add('技术栈：${plan.techStack}');
    if (plan.dailyMinutes > 0) parts.add('每日 ${plan.dailyMinutes} 分钟');
    if (plan.interviewDate != null) {
      final days = plan.interviewDate!.difference(DateTime.now()).inDays + 1;
      parts.add(days > 0 ? '距离面试 $days 天' : '面试日期已到');
    }
    return parts.isEmpty ? '目标已设置，App 会增强推荐权重。' : parts.join(' · ');
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
          title: const Text('面试目标'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: roleController,
                    decoration: const InputDecoration(
                      labelText: '目标岗位（可选）',
                      hintText: 'Java 后端 / AI 工程化 / 架构师',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: stackController,
                    decoration: const InputDecoration(
                      labelText: '技术栈（可选）',
                      hintText: 'Spring Cloud, Redis, RAG...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Text('每日投入 $dailyMinutes 分钟')),
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
                          ? '选择面试日期（可选）'
                          : '面试日期：${interviewDate!.year}-${interviewDate!.month}-${interviewDate!.day}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: jdController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: '岗位描述 / JD（可选，本地保存）',
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
              child: const Text('取消'),
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
              child: const Text('保存'),
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

  static const _techKeywords = [
    'java', 'python', 'go', 'golang', 'rust', 'c++', 'javascript', 'typescript',
    'spring', 'springboot', 'spring cloud', 'mybatis', 'hibernate',
    'redis', 'mysql', 'postgresql', 'mongodb', 'elasticsearch', 'es',
    'kafka', 'rabbitmq', 'rocketmq', 'mq',
    'docker', 'kubernetes', 'k8s', 'linux', 'nginx',
    '微服务', '分布式', '高并发', '高可用', '缓存', '消息队列',
    '设计模式', '数据结构', '算法', '系统设计', '架构',
    'jvm', 'gc', '并发', '多线程', '线程池', '锁',
    '网络', 'tcp', 'http', 'https', 'rpc', 'grpc',
    '数据库', '索引', '事务', 'mvcc', 'b+树',
    '集合', 'hashmap', 'arraylist', '链表', '树', '图',
    '排序', '二分', '动态规划', '贪心', '回溯',
    'react', 'vue', 'flutter', 'android', 'ios',
    '机器学习', '深度学习', 'llm', 'rag', 'prompt',
    'ci/cd', 'git', 'jenkins', 'devops',
    '项目', '实习', '经验',
  ];

  List<String> _extractKeywords(String jd) {
    final lower = jd.toLowerCase();
    return _techKeywords.where((kw) => lower.contains(kw)).toList();
  }

  List<Topic> _matchTopics(List<String> keywords) {
    if (keywords.isEmpty) return [];
    final matched = <String, Topic>{};
    for (final topic in topics) {
      final searchText = '${topic.title} ${topic.summary} '
          '${topic.category} ${topic.tags.join(' ')} '
          '${topic.rubric?.mustHave.join(' ') ?? ''}'.toLowerCase();
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
    final keywords = _extractKeywords(jobDescription);
    final matchedTopics = _matchTopics(keywords);

    // 按掌握度排序：未掌握优先
    matchedTopics.sort((a, b) {
      final scoreA = progress.getTopicProgress(a.id)?.score ?? 0;
      final scoreB = progress.getTopicProgress(b.id)?.score ?? 0;
      return scoreA.compareTo(scoreB);
    });

    return WorkPanel(
      title: 'JD 匹配分析',
      trailing: Text(
        '${matchedTopics.length} 项匹配',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        if (keywords.isEmpty)
          const Text('未识别到关键技术词，请检查 JD 内容。')
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: keywords
                .map((kw) => Chip(
                      label: Text(kw, style: const TextStyle(fontSize: 11)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          if (matchedTopics.isEmpty)
            const Text('当前内容库中未找到与 JD 匹配的知识点。')
          else ...[
            Text(
              '建议优先复习（按掌握度从低到高）：',
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
                        score > 0 ? '$score' : '未练习',
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
