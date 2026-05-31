import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import '../../providers/localization_provider.dart';

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
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final _storage = StorageService();
  List<String> _disabledIds = [];

  @override
  void initState() {
    super.initState();
    _loadDisabled();
  }

  Future<void> _loadDisabled() async {
    final ids = await _storage.loadDisabledDomains();
    if (mounted) setState(() => _disabledIds = ids);
  }

  List<Domain> _filterDomains(List<Domain> all) {
    return all.where((d) => !_disabledIds.contains(d.id)).toList();
  }
  bool _roadmapView = false;
  String _searchQuery = '';
  final Set<int> _difficultyFilters = {};
  bool _highFrequencyOnly = false;
  bool _hasCodeOnly = false;
  bool _hasLeetcodeOnly = false;
  final Set<String> _statusFilters = {};
  String _sortBy = 'order';
  bool _showFilters = false;

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
    final l10n = context.watch<LocalizationProvider>();
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allDomains = contentProvider.domains;
    final domains = _filterDomains(allDomains);
    final currentDomain = allDomains.where((d) => d.id == widget.currentDomainId).firstOrNull;
    if (currentDomain == null) {
      return Center(child: Text(l10n.get('请选择一个领域')));
    }

    final domainTopics = contentProvider.getTopicsByDomain(widget.currentDomainId);
    final domainProgress = progressProvider.getDomainProgress(
      widget.currentDomainId,
      contentProvider.topics.values.toList(),
    );
    final masteryPercent = domainProgress.masteryPercent;
    final totalTopics = currentDomain.topicCount;
    
    final filteredTopics = _applyFilters(domainTopics, progressProvider);
    final sortedTopics = _sortTopics(filteredTopics, progressProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：紧凑的领域选择和搜索
          _buildCompactHeader(context, currentDomain, masteryPercent, totalTopics, domains, contentProvider, isDark),
          const SizedBox(height: 12),
          
          // 筛选栏（可折叠）
          if (_showFilters) ...[
            _buildFilterBar(context, isDark),
            const SizedBox(height: 12),
          ],
          
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

  Widget _buildCompactHeader(BuildContext context, Domain domain, int masteryPercent, 
      int totalTopics, List<Domain> domains, ContentProvider contentProvider, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Column(
        children: [
          // 第一行：领域下拉 + 搜索 + 筛选按钮 + 视图切换
          Row(
            children: [
              // 领域下拉选择
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: widget.currentDomainId,
                    isDense: true,
                    items: domains.map((d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(d.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    )).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        widget.onDomainChanged(value);
                        if (contentProvider.getLoadedTopicCount(value) == 0) {
                          contentProvider.loadDomainTopics(value);
                        }
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // 搜索框
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: l10n.get('搜索当前领域'),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => setState(() => _searchQuery = ''),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // 筛选按钮
              IconButton(
                icon: Icon(
                  _showFilters ? Icons.filter_list_off : Icons.filter_list,
                  size: 20,
                  color: _hasActiveFilters ? Theme.of(context).colorScheme.primary : null,
                ),
                onPressed: () => setState(() => _showFilters = !_showFilters),
                tooltip: _showFilters ? l10n.get('隐藏筛选') : l10n.get('显示筛选'),
                style: IconButton.styleFrom(
                  backgroundColor: _hasActiveFilters 
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                      : null,
                ),
              ),
              const SizedBox(width: 4),
              
              // 视图切换
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.view_list, size: 16)),
                  ButtonSegment(value: true, icon: Icon(Icons.account_tree, size: 16)),
                ],
                selected: {_roadmapView},
                onSelectionChanged: (next) => setState(() => _roadmapView = next.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          
          // 第二行：掌握度进度条
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                l10n.getp('{count} 个知识点', {'count': totalTopics}),
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: masteryPercent / 100,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    color: Theme.of(context).colorScheme.primary,
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$masteryPercent%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 筛选标签
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 难度筛选
              ...([1, 2, 3, 4, 5].map((d) {
                final labels = {1: l10n.get('入门'), 2: l10n.get('基础'), 3: l10n.get('中等'), 4: l10n.get('较难'), 5: l10n.get('困难')};
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
                label: Text(l10n.get('高频'), style: TextStyle(fontSize: 11)),
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
                label: Text(l10n.get('代码题'), style: TextStyle(fontSize: 11)),
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
                label: Text('LeetCode', style: TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.link, size: 14),
                selected: _hasLeetcodeOnly,
                selectedColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFF10B981),
                onSelected: (v) => setState(() => _hasLeetcodeOnly = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              
              // 掌握度筛选
              ...({'skilled': l10n.get('熟练'), 'familiar': l10n.get('不熟练'), 'unfamiliar': l10n.get('未掌握')}.entries.map((e) {
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
                  label: Text(l10n.get('清除'), style: TextStyle(fontSize: 11)),
                  avatar: const Icon(Icons.filter_alt_off, size: 14),
                  onPressed: _clearFilters,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          
          // 排序选项
          const SizedBox(height: 12),
          Row(
            children: [
              Text(l10n.get('排序'), style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey)),
              const SizedBox(width: 8),
              _buildSortChip(l10n.get('默认'), 'order', isDark),
              _buildSortChip(l10n.get('难度'), 'difficulty', isDark),
              _buildSortChip(l10n.get('分数'), 'score', isDark),
              _buildSortChip(l10n.get('复习时间'), 'reviewTime', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, String value, bool isDark) {
    final isSelected = _sortBy == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _sortBy = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : (isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
            ),
          ),
        ),
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
          Text(l10n.get('没有找到匹配的知识点'), style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          if (_hasActiveFilters)
            TextButton(
              onPressed: _clearFilters,
              child: Text(l10n.get('清除筛选')),
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
        return _buildTopicCard(context, topics[index], progressProvider, isDark);
      },
    );
  }

  Widget _buildTopicCard(BuildContext context, Topic topic, 
      ProgressProvider progressProvider, bool isDark) {
    final progress = progressProvider.getTopicProgress(topic.id);
    final score = progress?.score ?? 0;
    final nextReview = progress?.nextReviewAt;
    
    final difficultyLabel = switch (topic.difficulty) {
      1 => l10n.get('入门'),
      2 => l10n.get('基础'),
      3 => l10n.get('中等'),
      4 => l10n.get('较难'),
      5 => l10n.get('困难'),
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
    
    final statusColor = score >= 85
        ? AppColors.success
        : score > 0
        ? AppColors.warning
        : Colors.grey;
    
    final hasCode = topic.recallPrompts.any((p) => p.mode == 'code');
    final hasLeetcode = topic.leetcodeUrl != null && topic.leetcodeUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
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
                        if (topic.status != null && topic.status != 'production')
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: topic.status == 'test'
                                  ? AppColors.warning.withValues(alpha: 0.1)
                                  : AppColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              topic.status == 'test' ? l10n.get('测试') : l10n.get('草稿'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: topic.status == 'test'
                                    ? AppColors.warning
                                    : AppColors.info,
                              ),
                            ),
                          ),
                        if (topic.highFrequency)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(l10n.get('高频'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.danger)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    
                    // 标签行
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (difficultyLabel.isNotEmpty)
                          _buildMiniTag(difficultyLabel, difficultyColor, isDark),
                        if (topic.interviewFrequencyLabel != null && !topic.highFrequency)
                          _buildMiniTag(l10n.get(topic.interviewFrequencyLabel!), AppColors.warning, isDark),
                        if (topic.estimatedMinutes > 0)
                          _buildMiniTag(l10n.getp('{minutes}分钟', {'minutes': topic.estimatedMinutes}), Colors.grey, isDark),
                        if (hasCode)
                          _buildMiniTag(l10n.get('代码'), Color(0xFF8B5CF6), isDark),
                        if (hasLeetcode)
                          _buildMiniTag('LeetCode', const Color(0xFF10B981), isDark),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 12),
              
              // 右侧信息
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (score > 0)
                    Text(
                      l10n.getp('{score}分', {'score': score}),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: statusColor),
                    ),
                  if (nextReview != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatReviewTime(nextReview),
                      style: TextStyle(
                        fontSize: 11,
                        color: nextReview.isBefore(DateTime.now()) ? AppColors.danger : (isDark ? Colors.white38 : const Color(0xFF999999)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(l10n.get('查阅'), AppColors.categoryCyan, () => widget.onTopicLearn(topic.id)),
                      const SizedBox(width: 6),
                      _buildActionButton(l10n.get('练习'), AppColors.accent, () => widget.onTopicPractice(topic.id)),
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
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
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
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }

  String _formatReviewTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);
    
    if (diff.isNegative) {
      final pastDiff = now.difference(time);
      if (pastDiff.inMinutes < 60) return l10n.getp('{n}分钟前', {'n': pastDiff.inMinutes});
      if (pastDiff.inHours < 24) return l10n.getp('{n}小时前', {'n': pastDiff.inHours});
      return l10n.getp('{n}天前', {'n': pastDiff.inDays});
    }
    
    if (diff.inMinutes < 60) return l10n.getp('{n}分钟后', {'n': diff.inMinutes});
    if (diff.inHours < 24) return l10n.getp('{n}小时后', {'n': diff.inHours});
    return l10n.getp('{n}天后', {'n': diff.inDays});
  }

  Widget _buildRoadmapView(BuildContext context, List<Topic> topics, 
      ProgressProvider progressProvider, bool isDark) {
    // 检查是否有 phase 数据
    final hasPhaseData = topics.any((t) => t.phase != null && t.phase!.isNotEmpty);
    
    final Map<String, List<Topic>> groups = {};
    
    if (hasPhaseData) {
      // 按 phase 分组
      for (final topic in topics) {
        final phase = topic.phase ?? l10n.get('未分类');
        groups.putIfAbsent(phase, () => []).add(topic);
      }
    } else {
      // 按 category 分组（用 domain 作为分类）
      for (final topic in topics) {
        final category = topic.domain.isNotEmpty ? topic.domain : l10n.get('未分类');
        groups.putIfAbsent(category, () => []).add(topic);
      }
    }

    // 排序
    final phaseOrder = [l10n.get('基础'), l10n.get('入门'), l10n.get('进阶'), l10n.get('中级'), l10n.get('高级'), l10n.get('困难')];
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        final ia = phaseOrder.indexOf(a);
        final ib = phaseOrder.indexOf(b);
        final va = ia == -1 ? 999 : ia;
        final vb = ib == -1 ? 999 : ib;
        if (va != vb) return va.compareTo(vb);
        return a.compareTo(b);
      });

    if (topics.isEmpty) {
      return Center(
        child: Text(l10n.get('暂无知识点'), style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return ListView.builder(
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final key = sortedKeys[index];
        final groupTopics = groups[key]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPhaseHeader(context, key, index, isDark, groupTopics.length),
            const SizedBox(height: 8),
            ...groupTopics.map((topic) => _buildTopicCard(context, topic, progressProvider, isDark)),
            if (index < sortedKeys.length - 1) const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildPhaseHeader(BuildContext context, String label, int index, bool isDark, int count) {
    const colors = [AppColors.categoryGreen, AppColors.accent, AppColors.categoryAmber, AppColors.categoryPurple, AppColors.categoryRed];
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
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              l10n.getp('{count} 题', {'count': count}),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
