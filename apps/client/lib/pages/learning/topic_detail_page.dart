import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.topic,
    required this.onBack,
  });

  final Topic topic;
  final VoidCallback onBack;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _answerController = TextEditingController();
  bool _isEvaluating = false;
  Map<String, dynamic>? _evaluationResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  topic.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        _TopicHeader(topic: topic),
        const SizedBox(height: 8),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '知识学习'),
            Tab(text: '复述练习'),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _KnowledgeTab(topic: topic),
              _RecallTab(
                topic: topic,
                answerController: _answerController,
                isEvaluating: _isEvaluating,
                evaluationResult: _evaluationResult,
                onEvaluate: _handleEvaluate,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleEvaluate() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入你的回答')),
      );
      return;
    }

    // 检查是否有可用的 AI 配置
    final aiProvider = context.read<AiProvider>();
    if (aiProvider.defaultConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在个人中心配置 AI')),
      );
      return;
    }

    setState(() => _isEvaluating = true);

    try {
      final topic = widget.topic;
      final result = await aiProvider.evaluateAnswer(
        topicId: topic.id,
        question: topic.recallPrompts.isNotEmpty ? topic.recallPrompts.first : topic.title,
        userAnswer: answer,
        rubric: topic.rubric,
      );

      if (mounted) {
        setState(() => _evaluationResult = result);
        final progressProvider = context.read<ProgressProvider>();
        final score = result['score'] as int? ?? 0;
        await progressProvider.updateTopicProgress(topic.id, score: score);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI 评估失败：$e'),
            action: SnackBarAction(
              label: '重试',
              onPressed: _handleEvaluate,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final difficultyLabel = switch (topic.difficulty) {
      1 => '入门',
      2 => '基础',
      3 => '中等',
      4 => '较难',
      5 => '困难',
      _ => '未知',
    };

    return WorkPanel(
      title: topic.title,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...topic.tags.map((tag) => Chip(
                  label: Text(tag),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )),
            Chip(
              label: Text(difficultyLabel),
              avatar: const Icon(Icons.signal_cellular_alt, size: 16),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Chip(
              label: Text('${topic.estimatedMinutes} 分钟'),
              avatar: const Icon(Icons.timer_outlined, size: 16),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ],
    );
  }
}

class _KnowledgeTab extends StatelessWidget {
  const _KnowledgeTab({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ...topic.learningCards.map((card) => _LearningCardWidget(card: card)),
        if (topic.rubric != null) ...[
          const SizedBox(height: 16),
          _RubricSection(rubric: topic.rubric!),
        ],
      ],
    );
  }
}

class _LearningCardWidget extends StatelessWidget {
  const _LearningCardWidget({required this.card});

  final LearningCard card;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: card.title,
      children: [
        switch (card.type) {
          'code' => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                card.content,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 13,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          'animation' => Column(
              children: [
                if (card.asset != null)
                  Image.asset(
                    card.asset!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _AnimationPlaceholder(),
                  )
                else
                  _AnimationPlaceholder(),
                const SizedBox(height: 12),
                Text(card.content),
              ],
            ),
          _ => Text(card.content),
        },
      ],
    );
  }
}

class _AnimationPlaceholder extends StatelessWidget {
  const _AnimationPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.animation_outlined, size: 48),
            SizedBox(height: 8),
            Text('动画/图示占位区域'),
          ],
        ),
      ),
    );
  }
}

class _RubricSection extends StatelessWidget {
  const _RubricSection({required this.rubric});

  final Rubric rubric;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '评分标准',
      children: [
        Text(
          '必须覆盖的关键点',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
        ),
        const SizedBox(height: 8),
        ...rubric.mustHave.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            )),
        const SizedBox(height: 12),
        Text(
          '常见错误',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
        ),
        const SizedBox(height: 8),
        ...rubric.commonMistakes.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cancel_outlined, size: 18, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            )),
      ],
    );
  }
}

class _RecallTab extends StatelessWidget {
  const _RecallTab({
    required this.topic,
    required this.answerController,
    required this.isEvaluating,
    required this.evaluationResult,
    required this.onEvaluate,
  });

  final Topic topic;
  final TextEditingController answerController;
  final bool isEvaluating;
  final Map<String, dynamic>? evaluationResult;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        WorkPanel(
          title: '复述提示',
          children: [
            if (topic.recallPrompts.isNotEmpty)
              ...topic.recallPrompts.map((prompt) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 18, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(child: Text(prompt)),
                      ],
                    ),
                  ))
            else
              const Text('用自己的话解释这个知识点的核心内容。'),
          ],
        ),
        const SizedBox(height: 16),
        WorkPanel(
          title: '你的回答',
          children: [
            TextField(
              controller: answerController,
              minLines: 6,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: '在这里输入你的复述答案...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isEvaluating ? null : onEvaluate,
              icon: isEvaluating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(isEvaluating ? '评估中...' : '获取 AI 深度评估'),
            ),
          ],
        ),
        if (evaluationResult != null) ...[
          const SizedBox(height: 16),
          _EvaluationResultPanel(result: evaluationResult!),
        ],
      ],
    );
  }
}

class _EvaluationResultPanel extends StatelessWidget {
  const _EvaluationResultPanel({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final score = result['score'] as int? ?? 0;
    final missed = result['missedPoints'] as List<dynamic>? ?? [];
    final errors = result['errorPoints'] as List<dynamic>? ?? [];
    final optimized = result['optimizedAnswer'] as String? ?? '';

    return WorkPanel(
      title: 'AI 评估结果',
      children: [
        ScoreBadge(score: score),
        if (missed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '遗漏点',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning),
          ),
          const SizedBox(height: 6),
          ...missed.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.tips_and_updates_outlined, size: 18, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              )),
        ],
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '错误点',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
          ),
          const SizedBox(height: 6),
          ...errors.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cancel_outlined, size: 18, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              )),
        ],
        if (optimized.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '优化回答',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(optimized),
          ),
        ],
      ],
    );
  }
}
