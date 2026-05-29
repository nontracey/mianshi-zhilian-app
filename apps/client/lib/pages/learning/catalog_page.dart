import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
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
  String _searchQuery = '';
  final Set<int> _difficultyFilters = {};
  bool _highFrequencyOnly = false;
  bool _hasCodeOnly = false;
  bool _hasLeetcodeOnly = false;
  final Set<String> _statusFilters = {};
  String _sortBy = 'order'; // order, difficulty, score, reviewTime

  List<Topic> _applyFilters(List<Topic> topics, ProgressProvider progress) {
    var result = topics;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((t) =>
          t.title.toLowerCase().contains(q) ||
          t.summary.toLowerCase().contains(q) ||
          t.tags.any((tag) => tag.toLowerCase().contains(q))).toList();
    }
    if (_difficultyFilters.isNotEmpty) {
      result = result.where((t) => _difficultyFilters.contains(t.difficulty)).toList();
    }
    if (_highFrequencyOnly) {
      result = result.where((t) => t.highFrequency).toList();
    }
    if (_hasCodeOnly) {
      result = result.where((t) => t.recallPrompts.any((p) => p.mode == 'code')).toList();
    }
    if (_hasLeetcodeOnly) {
      result = result.where((t) => t.leetcodeUrl != null && t.leetcodeUrl!.isNotEmpty).toList();
    }
    if (_statusFilters.isNotEmpty) {
      result = result.where((t) {
        final score = progress.getTopicProgress(t.id)?.score ?? 0;
        final status = score >= 85 ? 'skilled' : score > 0 ? 'familiar' : 'unfamiliar';
        return _statusFilters.contains(status);
      }).toList();
    }
    return result;
  }

  List<Topic> _sortTopics(List<Topic> topics, ProgressProvider progress) {
    final sorted = List<Topic>.from(topics);
    switch (_sortBy) {
      case 'difficulty':
        sorted.sort((a, b) => a.difficulty.compareTo(b.difficulty));
      case 'score':
        sorted.sort((a, b) {
          final scoreA = progress.getTopicProgress(a.id)?.score ?? 0;
          final scoreB = progress.getTopicProgress(b.id)?.score ?? 0;
          return scoreA.compareTo(scoreB);
        });
      case 'reviewTime':
        sorted.sort((a, b) {
          final nextA = progress.getTopicProgress(a.id)?.nextReviewAt;
          final nextB = progress.getTopicProgress(b.id)?.nextReviewAt;
          if (nextA == null && nextB == null) return 0;
          if (nextA == null) return 1;
          if (nextB == null) return -1;
          return nextA.compareTo(nextB);
        });
      default:
        sorted.sort((a, b) => a.order.compareTo(b.order));
    }
    return sorted;
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _difficultyFilters.isNotEmpty ||
      _highFrequencyOnly ||
      _hasCodeOnly ||
      _hasLeetcodeOnly ||
      _statusFilters.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _difficultyFilters.clear();
      _highFrequencyOnly = false;
      _hasCodeOnly = false;
      _hasLeetcodeOnly = false;
      _statusFilters.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final domains = contentProvider.domains;
    final currentDomain = domains.where((d) => d.id == widget.currentDomainId).firstOrNull;
    if (currentDomain == null) {
      return const Center(child: Text('请选择一个领域'));
    }

    final domainTopics = contentProvider.getTopicsByDomain(widget.currentDomainId);
    final domainProgress = progressProvider.getDomainProgress(
      widget.currentDomainId,
      contentProvider.topics.values.toList(),
    );
    final masteryPercent = domainProgress.masteryPercent;
    final loaded = contentProvider.getLoadedTopicCount(widget.currentDomainId);
    final total = currentDomain.topicCount;
    
    final filteredTopics = _applyFilters(domainTopics, progressProvider);
    final sortedTopics = _sortTopics(filteredTopics, progressProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：领域信息 + 视图切换
          _buildHeader(context, currentDomain, masteryPercent, domains, contentProvider, isDark),
          const SizedBox(height: 16),
          
          // 搜索和筛选栏
          _buildFilterBar(context, isDark),
          
          // 筛选结果统计
          if (_hasActiveFilters) ...[
            const SizedBox(height: 8),
            Text(
              '筛选结果：${sortedTopics.length} / ${domainTopics.length} 个知识点',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : const Color(0xFF999999)),
            ),
          ],
          
          // 加载状态
          if (contentProvider.isLoadingTopics && loaded < total) ...[
            const SizedBox(height: 12),
            _buildLoadingBar(context, loaded, total),
          ],
          
          const SizedBox(height: 12),
          
          // 知识点列表
          Expanded(
            child: sortedTopics.isEmpty
                ? _buildEmptyState(context)
                : _buildTopicList(context, sortedTopics, progressProvider, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Domain domain, int masteryPercent, 
      List<Domain> domains, ContentProvider contentProvider, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15202E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Row(
        children: [
          // 领域信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  domain.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  domain.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : const Color(0xFF666666),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // 掌握度进度条
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: masteryPercent / 100,
                          backgroundColor: const Color(0xFF3078F0).withValues(alpha: 0.1),
                          color: const Color(0xFF3078F0),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$masteryPercent%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3078F0),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          
          // 领域切换
          SegmentedButton<String>(
            segments: domains.map((d) => ButtonSegment(
              value: d.id,
              label: Text(d.id.toUpperCase()),
            )).toList(),
            selected: {widget.currentDomainId},
            onSelectionChanged: (next) {
              widget.onDomainChanged(next.first);
              if (contentProvider.getLoadedTopicCount(next.first) == 0) {
                contentProvider.loadDomainTopics(next.first);
              }
            },
          ),
          const SizedBox(width: 16),
          
          // 视图切换
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Icon(Icons.view_list, size: 18)),
              ButtonSegment(value: true, label: Icon(Icons.account_tree, size: 18)),
            ],
            selected: {_roadmapView},
            onSelectionChanged: (next) {
              setState(() => _roadmapView = next.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2332) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // 搜索框
          TextField(
            decoration: InputDecoration(
              hintText: '搜索知识点、标签...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF15202E) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 10),
          
          // 筛选器行
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 难度筛选
              ...([1, 2, 3, 4, 5].map((d) {
                final labels = {1: '入门', 2: '基础', 3: '中等', 4: '较难', 5: '困难'};
                final colors = {
                  1: const Color(0xFF10B981),
                  2: const Color(0xFF00CCF9),
                  3: const Color(0xFFF59E0B),
                  4: const Color(0xFFEF4444),
                  5: const Color(0xFF7C3AED),
                };
                return FilterChip(
                  label: Text(labels[d]!, style: const TextStyle(fontSize: 11)),
                  selected: _difficultyFilters.contains(d),
                  selectedColor: colors[d]!.withValues(alpha: 0.2),
                  checkmarkColor: colors[d],
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _difficultyFilters.add(d);
                      } else {
                        _difficultyFilters.remove(d);
                      }
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              })),
              
              // 高频筛选
              FilterChip(
                label: const Text('高频', style: TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.local_fire_department, size: 14),
                selected: _highFrequencyOnly,
                selectedColor: AppColors.danger.withValues(alpha: 0.15),
                checkmarkColor: AppColors.danger,
                onSelected: (v) => setState(() => _highFrequencyOnly = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              
              // 含代码题
              FilterChip(
                label: const Text('代码题', style: TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.code, size: 14),
                selected: _hasCodeOnly,
                selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFF8B5CF6),
                onSelected: (v) => setState(() => _hasCodeOnly = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              
              // 含LeetCode
              FilterChip(
                label: const Text('LeetCode', style: TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.link, size: 14),
                selected: _hasLeetcodeOnly,
                selectedColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFF10B981),
                onSelected: (v) => setState(() => _hasLeetcodeOnly = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              
              // 掌握度筛选
              ...({'skilled': '熟练', 'familiar': '不熟练', 'unfamiliar': '未掌握'}.entries.map((e) {
                final colors = {'skilled': AppColors.success, 'familiar': AppColors.warning, 'unfamiliar': AppColors.danger};
                return FilterChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 11)),
                  selected: _statusFilters.contains(e.key),
                  selectedColor: colors[e.key]!.withValues(alpha: 0.15),
                  checkmarkColor: colors[e.key],
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _statusFilters.add(e.key);
                      } else {
                        _statusFilters.remove(e.key);
                      }
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              })),
              
              // 清除筛选
              if (_hasActiveFilters)
                ActionChip(
                  label: const Text('清除筛选', style: TextStyle(fontSize: 11)),
                  avatar: const Icon(Icons.filter_alt_off, size: 14),
                  onPressed: _clearFilters,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          
          // 排序选项
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '排序：',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF666666),
                ),
              ),
              const SizedBox(width: 8),
              _buildSortChip('默认', 'order', isDark),
              _buildSortChip('难度', 'difficulty', isDark),
              _buildSortChip('分数', 'score', isDark),
              _buildSortChip('复习时间', 'reviewTime', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, String value, bool isDark) {
    final isSelected = _sortBy == value;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF3078F0)
              : (isDark ? const Color(0xFF15202E) : Colors.white),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3078F0)
                : (isDark ? const Color(0xFF263238) : const Color(0xFFE0E0E0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF666666)),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingBar(BuildContext context, int loaded, int total) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3078F0).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('正在加载知识点 $loaded/$total ...', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            '没有找到匹配的知识点',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          if (_hasActiveFilters)
            TextButton(
              onPressed: _clearFilters,
              child: const Text('清除筛选'),
            ),
        ],
      ),
    );
  }

  Widget _buildTopicList(BuildContext context, List<Topic> topics, 
      ProgressProvider progressProvider, bool isDark) {
    if (_roadmapView) {
      return _buildRoadmapView(context, topics, progressProvider, isDark);
    }
    
    return ListView.builder(
      itemCount: topics.length,
      itemBuilder: (context, index) {
        final topic = topics[index];
        return _buildTopicCard(context, topic, progressProvider, isDark);
      },
    );
  }

  Widget _buildTopicCard(BuildContext context, Topic topic, 
      ProgressProvider progressProvider, bool isDark) {
    final progress = progressProvider.getTopicProgress(topic.id);
    final score = progress?.score ?? 0;
    final nextReview = progress?.nextReviewAt;
    
    // 难度标签
    final difficultyLabel = switch (topic.difficulty) {
      1 => '入门',
      2 => '基础',
      3 => '中等',
      4 => '较难',
      5 => '困难',
      _ => '',
    };
    final difficultyColor = switch (topic.difficulty) {
      1 => const Color(0xFF10B981),
      2 => const Color(0xFF00CCF9),
      3 => const Color(0xFFF59E0B),
      4 => const Color(0xFFEF4444),
      5 => const Color(0xFF7C3AED),
      _ => Colors.grey,
    };
    
    // 状态颜色
    final statusColor = score >= 85
        ? AppColors.success
        : score > 0
        ? AppColors.warning
        : Colors.grey;
    
    // 是否含代码题
    final hasCode = topic.recallPrompts.any((p) => p.mode == 'code');
    // 是否含LeetCode
    final hasLeetcode = topic.leetcodeUrl != null && topic.leetcodeUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15202E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
        ),
      ),
      child: InkWell(
        onTap: () => widget.onTopicLearn(topic.id),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 状态指示器
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              
              // 主要信息
              Expanded(
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
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 高频标签
                        if (topic.highFrequency)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '高频',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.danger),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    
                    // 标签行
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // 难度
                        _buildMiniTag(difficultyLabel, difficultyColor, isDark),
                        // 面试频率
                        if (topic.interviewFrequencyLabel != null && !topic.highFrequency)
                          _buildMiniTag(topic.interviewFrequencyLabel!, AppColors.warning, isDark),
                        // 预计时间
                        if (topic.estimatedMinutes > 0)
                          _buildMiniTag('${topic.estimatedMinutes}分钟', Colors.grey, isDark),
                        // 代码题
                        if (hasCode)
                          _buildMiniTag('代码', const Color(0xFF8B5CF6), isDark),
                        // LeetCode
                        if (hasLeetcode)
                          _buildMiniTag('LeetCode', const Color(0xFF10B981), isDark),
                      ],
                    ),
                    const SizedBox(height: 6),
                    
                    // 摘要
                    Text(
                      topic.summary,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : const Color(0xFF666666),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 12),
              
              // 右侧信息
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 分数
                  if (score > 0)
                    Text(
                      '$score 分',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  const SizedBox(height: 4),
                  // 下次复习时间
                  if (nextReview != null)
                    Text(
                      _formatReviewTime(nextReview),
                      style: TextStyle(
                        fontSize: 11,
                        color: nextReview.isBefore(DateTime.now())
                            ? AppColors.danger
                            : (isDark ? Colors.white38 : const Color(0xFF999999)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  // 操作按钮
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        '查阅',
                        const Color(0xFF00CCF9),
                        () => widget.onTopicLearn(topic.id),
                      ),
                      const SizedBox(width: 6),
                      _buildActionButton(
                        '练习',
                        const Color(0xFF3078F0),
                        () => widget.onTopicPractice(topic.id),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniTag(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  String _formatReviewTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);
    
    if (diff.isNegative) {
      final pastDiff = now.difference(time);
      if (pastDiff.inMinutes < 60) return '${pastDiff.inMinutes}分钟前';
      if (pastDiff.inHours < 24) return '${pastDiff.inHours}小时前';
      return '${pastDiff.inDays}天前';
    }
    
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟后';
    if (diff.inHours < 24) return '${diff.inHours}小时后';
    return '${diff.inDays}天后';
  }

  Widget _buildRoadmapView(BuildContext context, List<Topic> topics, 
      ProgressProvider progressProvider, bool isDark) {
    // 按 phase 分组
    final phases = <String, List<Topic>>{};
    for (final topic in topics) {
      final phase = topic.phase ?? '未分类';
      phases.putIfAbsent(phase, () => []).add(topic);
    }

    const phaseOrder = ['基础', '入门', '进阶', '中级', '高级', '困难'];
    final sortedPhases = phases.keys.toList()
      ..sort((a, b) {
        final ia = phaseOrder.indexOf(a);
        final ib = phaseOrder.indexOf(b);
        return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
      });

    return ListView.builder(
      itemCount: sortedPhases.length,
      itemBuilder: (context, index) {
        final phase = sortedPhases[index];
        final phaseTopics = phases[phase]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 阶段标题
            _buildPhaseHeader(context, phase, index, isDark),
            const SizedBox(height: 8),
            // 阶段内的知识点
            ...phaseTopics.map((topic) => _buildTopicCard(context, topic, progressProvider, isDark)),
            if (index < sortedPhases.length - 1) const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildPhaseHeader(BuildContext context, String label, int index, bool isDark) {
    const colors = [
      Color(0xFF10B981),
      Color(0xFF3078F0),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
    ];
    final color = colors[index % colors.length];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag, size: 16, color: color),
          const SizedBox(width: 8),
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
    );
  }
}
