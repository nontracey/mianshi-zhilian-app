import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/status_dot.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.currentDomainId,
    required this.onDomainChanged,
    required this.onTopicLearn,
    required this.onTopicPractice,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;
  final ValueChanged<String> onTopicLearn;
  final ValueChanged<String> onTopicPractice;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  bool _roadmapView = false;

  /// 按分类下已加载 topic 的平均难度升序排列（由易到难）
  List<Category> _sortedCategories(
    List<Category> categories,
    List<Topic> domainTopics,
  ) {
    final sorted = List<Category>.from(categories);
    sorted.sort((a, b) {
      final avgA = _avgDifficulty(a.id, domainTopics);
      final avgB = _avgDifficulty(b.id, domainTopics);
      return avgA.compareTo(avgB);
    });
    return sorted;
  }

  double _avgDifficulty(String categoryId, List<Topic> domainTopics) {
    final topics = domainTopics
        .where((t) => t.category == categoryId)
        .toList();
    if (topics.isEmpty) return 999; // 无数据的排最后
    return topics.map((t) => t.difficulty).reduce((a, b) => a + b) /
        topics.length;
  }

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();

    final domains = contentProvider.domains;
    final currentDomain = domains
        .where((d) => d.id == widget.currentDomainId)
        .firstOrNull;
    if (currentDomain == null) {
      return const Center(child: Text('请选择一个领域'));
    }

    final domainTopics = contentProvider.getTopicsByDomain(
      widget.currentDomainId,
    );
    final domainProgress = progressProvider.getDomainProgress(
      widget.currentDomainId,
      contentProvider.topics.values.toList(),
    );
    final masteryPercent = domainProgress.masteryPercent;
    final loaded = contentProvider.getLoadedTopicCount(widget.currentDomainId);
    final total = currentDomain.topicCount;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        WorkPanel(
          title: currentDomain.title,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 路径/列表切换
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('列表')),
                  ButtonSegment(value: true, label: Text('路径')),
                ],
                selected: {_roadmapView},
                onSelectionChanged: (next) {
                  setState(() => _roadmapView = next.first);
                },
              ),
              const SizedBox(width: 12),
              // 领域切换
              SegmentedButton<String>(
                segments: domains
                    .map((d) => ButtonSegment(value: d.id, label: Text(d.id)))
                    .toList(),
                selected: {widget.currentDomainId},
                onSelectionChanged: (next) {
                  widget.onDomainChanged(next.first);
                  if (contentProvider.getLoadedTopicCount(next.first) == 0) {
                    contentProvider.loadDomainTopics(next.first);
                  }
                },
              ),
            ],
          ),
          children: [
            Text(currentDomain.description),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: masteryPercent / 100),
                ),
                const SizedBox(width: 12),
                Text('$masteryPercent%'),
              ],
            ),
            if (contentProvider.isLoadingTopics && loaded < total) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('正在加载知识点 $loaded/$total ...'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (_roadmapView)
              _RoadmapView(
                categories: _sortedCategories(
                  currentDomain.categories,
                  domainTopics,
                ),
                domainTopics: domainTopics,
                progressProvider: progressProvider,
                onTopicLearn: widget.onTopicLearn,
                onTopicPractice: widget.onTopicPractice,
              )
            else
              ..._sortedCategories(
                currentDomain.categories,
                domainTopics,
              ).map((category) {
                final categoryTopics = domainTopics
                    .where((t) => t.category == category.id)
                    .toList();
                if (categoryTopics.isEmpty &&
                    !contentProvider.isLoadingTopics) {
                  return _CategorySection(
                    category: category,
                    topics: const [],
                    isLoading: contentProvider.isLoadingTopics,
                    progressProvider: progressProvider,
                    onTopicLearn: widget.onTopicLearn,
                    onTopicPractice: widget.onTopicPractice,
                  );
                }
                return _CategorySection(
                  category: category,
                  topics: categoryTopics,
                  isLoading: false,
                  progressProvider: progressProvider,
                  onTopicLearn: widget.onTopicLearn,
                  onTopicPractice: widget.onTopicPractice,
                );
              }),
          ],
        ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.topics,
    required this.isLoading,
    required this.progressProvider,
    required this.onTopicLearn,
    required this.onTopicPractice,
  });

  final Category category;
  final List<Topic> topics;
  final bool isLoading;
  final ProgressProvider progressProvider;
  final ValueChanged<String> onTopicLearn;
  final ValueChanged<String> onTopicPractice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(
          category.title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (category.description != null &&
            category.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            category.description!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        if (isLoading && topics.isEmpty)
          // 加载中骨架
          ...List.generate(
            3,
            (_) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Container(
                  width: 160,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                subtitle: Container(
                  width: 240,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          )
        else if (topics.isEmpty)
          // 暂无数据
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '暂无知识点',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          )
        else
          ...topics.map((topic) {
            final progress = progressProvider.getTopicProgress(topic.id);
            final score = progress?.score ?? 0;
            // 难度标签
            final difficultyLabel = switch (topic.difficulty) {
              1 => '入门',
              2 => '基础',
              3 => '中等',
              4 => '较难',
              5 => '困难',
              _ => '',
            };
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: StatusDot(score: score),
                title: Row(
                  children: [
                    Expanded(child: Text(topic.title)),
                    if (difficultyLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _difficultyColor(
                            topic.difficulty,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          difficultyLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _difficultyColor(topic.difficulty),
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(topic.summary),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    // 知识查阅 — 使用 accent 高亮色
                    FilledButton.tonal(
                      onPressed: () => onTopicLearn(topic.id),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00CCF9),
                        foregroundColor: const Color(0xFF06111F),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('知识查阅'),
                    ),
                    // 学习模式 — 使用 primary 强调色
                    FilledButton(
                      onPressed: () => onTopicPractice(topic.id),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF334B66),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('学习模式'),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Color _difficultyColor(int difficulty) {
    return switch (difficulty) {
      1 => const Color(0xFF10B981), // 绿
      2 => const Color(0xFF00CCF9), // 青
      3 => const Color(0xFFF59E0B), // 黄
      4 => const Color(0xFFEF4444), // 红
      5 => const Color(0xFF7C3AED), // 紫
      _ => Colors.grey,
    };
  }
}

// ── 学习路径视图 ─────────────────────────────────────────────

class _RoadmapView extends StatelessWidget {
  const _RoadmapView({
    required this.categories,
    required this.domainTopics,
    required this.progressProvider,
    required this.onTopicLearn,
    required this.onTopicPractice,
  });

  final List<Category> categories;
  final List<Topic> domainTopics;
  final ProgressProvider progressProvider;
  final ValueChanged<String> onTopicLearn;
  final ValueChanged<String> onTopicPractice;

  @override
  Widget build(BuildContext context) {
    // 按 phase 分组：基础 → 进阶 → 高级 → 未标记
    final phases = <String, List<Topic>>{};
    for (final topic in domainTopics) {
      final phase = topic.phase ?? '未分类';
      phases.putIfAbsent(phase, () => []).add(topic);
    }

    // phase 排序优先级
    const phaseOrder = ['基础', '入门', '进阶', '中级', '高级', '困难'];
    final sortedPhases = phases.keys.toList()..sort((a, b) {
      final ia = phaseOrder.indexOf(a);
      final ib = phaseOrder.indexOf(b);
      final va = ia == -1 ? 999 : ia;
      final vb = ib == -1 ? 999 : ib;
      return va.compareTo(vb);
    });

    if (domainTopics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '暂无知识点数据',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ),
      );
    }

    // 如果没有任何 phase 标记，按分类作为阶段显示
    final useCategoryFallback =
        sortedPhases.length == 1 && sortedPhases.first == '未分类';

    final displayGroups = useCategoryFallback
        ? categories
              .where((c) => domainTopics.any((t) => t.category == c.id))
              .map(
                (c) => _RoadmapGroup(
                  label: c.title,
                  topics: domainTopics
                      .where((t) => t.category == c.id)
                      .toList(),
                ),
              )
              .toList()
        : sortedPhases
              .where((p) => phases[p]!.isNotEmpty)
              .map(
                (p) => _RoadmapGroup(
                  label: p,
                  topics: phases[p]!,
                ),
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var gi = 0; gi < displayGroups.length; gi++) ...[
          // 阶段标题
          _buildPhaseHeader(context, displayGroups[gi].label, gi),
          const SizedBox(height: 12),
          // 该阶段下的知识点节点
          ...displayGroups[gi].topics.asMap().entries.map((entry) {
            final ti = entry.key;
            final topic = entry.value;
            final isLast =
                gi == displayGroups.length - 1 &&
                ti == displayGroups[gi].topics.length - 1;
            return _buildTopicNode(
              context,
              topic,
              isFirst: ti == 0,
              isLast: isLast,
            );
          }),
          // 阶段之间的连接箭头
          if (gi < displayGroups.length - 1)
            _buildPhaseConnector(),
        ],
      ],
    );
  }

  Widget _buildPhaseHeader(BuildContext context, String label, int index) {
    const colors = [
      AppColors.success,
      AppColors.accent,
      AppColors.warning,
      Color(0xFF8B5CF6),
    ];
    final color = colors[index % colors.length];

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                '阶段 ${index + 1}：$label',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: color.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }

  Widget _buildTopicNode(
    BuildContext context,
    Topic topic, {
    required bool isFirst,
    required bool isLast,
  }) {
    final progress = progressProvider.getTopicProgress(topic.id);
    final score = progress?.score ?? 0;
    final hasProgress = score > 0;

    final nodeColor = hasProgress
        ? (score >= 85 ? AppColors.success : AppColors.warning)
        : Colors.grey.shade400;

    final difficultyLabel = switch (topic.difficulty) {
      1 => '入门',
      2 => '基础',
      3 => '中等',
      4 => '较难',
      5 => '困难',
      _ => '',
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧：时间线
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // 上半连接线（非第一个节点显示）
                if (!isFirst)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: nodeColor.withValues(alpha: 0.3),
                    ),
                  )
                else
                  const SizedBox(height: 20),
                // 节点圆点
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasProgress
                        ? nodeColor.withValues(alpha: 0.2)
                        : Colors.grey.shade100,
                    border: Border.all(color: nodeColor, width: 2.5),
                  ),
                  child: hasProgress
                      ? Icon(
                          score >= 85
                              ? Icons.check
                              : Icons.trending_up,
                          size: 14,
                          color: nodeColor,
                        )
                      : null,
                ),
                // 下半连接线（非最后一个节点显示）
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: nodeColor.withValues(alpha: 0.3),
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ),
          // 右侧：知识点卡片
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasProgress
                        ? nodeColor.withValues(alpha: 0.4)
                        : Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    if (hasProgress)
                      BoxShadow(
                        color: nodeColor.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题行
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            topic.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: hasProgress
                                  ? null
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                        // 难度
                        if (difficultyLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _difficultyColor(topic.difficulty)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              difficultyLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _difficultyColor(topic.difficulty),
                              ),
                            ),
                          ),
                        // 分数
                        if (hasProgress) ...[
                          const SizedBox(width: 8),
                          StatusDot(score: score),
                          const SizedBox(width: 4),
                          Text(
                            '$score 分',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: nodeColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // 摘要
                    if (topic.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        topic.summary,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // 前置依赖
                    if (topic.prerequisites.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          Icon(
                            Icons.link,
                            size: 12,
                            color: Colors.grey.shade500,
                          ),
                          ...topic.prerequisites.map(
                            (dep) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                dep,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    // 操作按钮
                    Row(
                      children: [
                        FilledButton.tonal(
                          onPressed: () => onTopicLearn(topic.id),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF00CCF9),
                            foregroundColor: const Color(0xFF06111F),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('查阅', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => onTopicPractice(topic.id),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF334B66),
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('学习', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseConnector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Icon(
            Icons.arrow_downward,
            size: 20,
            color: AppColors.accent.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Container(
            height: 1,
            width: 40,
            color: AppColors.accent.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  Color _difficultyColor(int difficulty) {
    return switch (difficulty) {
      1 => const Color(0xFF10B981),
      2 => const Color(0xFF00CCF9),
      3 => const Color(0xFFF59E0B),
      4 => const Color(0xFFEF4444),
      5 => const Color(0xFF7C3AED),
      _ => Colors.grey,
    };
  }
}

class _RoadmapGroup {
  final String label;
  final List<Topic> topics;
  _RoadmapGroup({required this.label, required this.topics});
}
