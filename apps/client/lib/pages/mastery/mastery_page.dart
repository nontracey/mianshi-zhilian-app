import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

enum MasterySort { scoreAsc, scoreDesc }

enum MasteryFilter { all, skilled, familiar, unfamiliar }

class MasteryPage extends StatefulWidget {
  const MasteryPage({
    super.key,
    required this.currentDomainId,
    required this.onDomainChanged,
  });

  final String currentDomainId;
  final ValueChanged<String> onDomainChanged;

  @override
  State<MasteryPage> createState() => _MasteryPageState();
}

class _MasteryPageState extends State<MasteryPage> {
  MasterySort _sort = MasterySort.scoreAsc;
  MasteryFilter _filter = MasteryFilter.all;
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

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allDomains = contentProvider.domains;
    final domains = _filterDomains(allDomains);
    final currentDomain = allDomains
        .where((d) => d.id == widget.currentDomainId)
        .firstOrNull;
    if (currentDomain == null) {
      return const Center(child: Text('请选择一个领域'));
    }

    final domainTopics = contentProvider.getTopicsByDomain(widget.currentDomainId);
    final domainProgress = progressProvider.getDomainProgress(
      widget.currentDomainId,
      contentProvider.topics.values.toList(),
    );
    final masteryPercent = domainProgress.masteryPercent;
    final dueCount = progressProvider.getTodayReviewTopics(domainTopics).length;
    final readiness = progressProvider.readinessScore(domainTopics);
    final highFrequencyWeak = domainTopics.where((topic) {
      final score = progressProvider.getTopicProgress(topic.id)?.score ?? 0;
      return topic.highFrequency && score < 85;
    }).length;
    final lowScoreCount = progressProvider.lowScoreAttempts.length;

    final filteredTopics = _applyFilter(domainTopics, progressProvider);
    final sortedTopics = _applySort(filteredTopics, progressProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：紧凑的领域选择和统计
          _buildCompactHeader(context, currentDomain, masteryPercent, domains, contentProvider, isDark),
          const SizedBox(height: 12),
          
          // 诊断指标
          _buildDiagnosticCards(context, readiness, dueCount, highFrequencyWeak, lowScoreCount, isDark),
          const SizedBox(height: 12),
          
          // 筛选和排序
          _buildFilterSortBar(context, isDark),
          const SizedBox(height: 12),
          
          // 知识点列表
          Expanded(
            child: sortedTopics.isEmpty
                ? Center(child: Text('暂无数据', style: TextStyle(color: Colors.grey.shade500)))
                : ListView.builder(
                    itemCount: sortedTopics.length,
                    itemBuilder: (context, index) {
                      return _buildTopicItem(context, sortedTopics[index], progressProvider, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader(BuildContext context, Domain domain, int masteryPercent, 
      List<Domain> domains, ContentProvider contentProvider, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Row(
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
          const SizedBox(width: 16),
          
          // 掌握度信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$masteryPercent%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: masteryPercent / 100,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    color: Theme.of(context).colorScheme.primary,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticCards(BuildContext context, int readiness, int dueCount, 
      int highFrequencyWeak, int lowScoreCount, bool isDark) {
    return Row(
      children: [
        Expanded(child: _buildDiagnosticCard('就绪度', '$readiness', AppColors.accent, isDark)),
        const SizedBox(width: 8),
        Expanded(child: _buildDiagnosticCard('待复习', '$dueCount', AppColors.warning, isDark)),
        const SizedBox(width: 8),
        Expanded(child: _buildDiagnosticCard('高频未稳', '$highFrequencyWeak', AppColors.accent, isDark)),
        const SizedBox(width: 8),
        Expanded(child: _buildDiagnosticCard('低分回流', '$lowScoreCount', AppColors.danger, isDark)),
      ],
    );
  }

  Widget _buildDiagnosticCard(String label, String value, Color color, bool isDark) {
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
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSortBar(BuildContext context, bool isDark) {
    return Row(
      children: [
        // 筛选
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('全部', MasteryFilter.all, isDark),
                _buildFilterChip('熟练', MasteryFilter.skilled, isDark),
                _buildFilterChip('不熟练', MasteryFilter.familiar, isDark),
                _buildFilterChip('未掌握', MasteryFilter.unfamiliar, isDark),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 排序
        _buildSortChip('低→高', MasterySort.scoreAsc, isDark),
        const SizedBox(width: 8),
        _buildSortChip('高→低', MasterySort.scoreDesc, isDark),
      ],
    );
  }

  Widget _buildFilterChip(String label, MasteryFilter filter, bool isDark) {
    final isSelected = _filter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  Widget _buildSortChip(String label, MasterySort sort, bool isDark) {
    final isSelected = _sort == sort;
    return GestureDetector(
      onTap: () => setState(() => _sort = sort),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    );
  }

  Widget _buildTopicItem(BuildContext context, Topic topic, ProgressProvider progressProvider, bool isDark) {
    final progress = progressProvider.getTopicProgress(topic.id);
    final score = progress?.score ?? 0;
    final scoreColor = score >= 85 ? AppColors.success : score >= 60 ? AppColors.warning : AppColors.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Row(
        children: [
          // 分数
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(fontWeight: FontWeight.w700, color: scoreColor),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (topic.highFrequency)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text('高频', style: TextStyle(fontSize: 10, color: AppColors.danger)),
                      ),
                    Text(
                      '${topic.domain} · ${topic.difficultyLabel}',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // 操作
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('开始练习', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  List<Topic> _applyFilter(List<Topic> topics, ProgressProvider progress) {
    switch (_filter) {
      case MasteryFilter.skilled:
        return topics.where((t) => (progress.getTopicProgress(t.id)?.score ?? 0) >= 85).toList();
      case MasteryFilter.familiar:
        return topics.where((t) {
          final score = progress.getTopicProgress(t.id)?.score ?? 0;
          return score >= 60 && score < 85;
        }).toList();
      case MasteryFilter.unfamiliar:
        return topics.where((t) => (progress.getTopicProgress(t.id)?.score ?? 0) < 60).toList();
      case MasteryFilter.all:
        return topics;
    }
  }

  List<Topic> _applySort(List<Topic> topics, ProgressProvider progress) {
    final sorted = List<Topic>.from(topics);
    switch (_sort) {
      case MasterySort.scoreAsc:
        sorted.sort((a, b) => 
          (progress.getTopicProgress(a.id)?.score ?? 0).compareTo(progress.getTopicProgress(b.id)?.score ?? 0));
      case MasterySort.scoreDesc:
        sorted.sort((a, b) => 
          (progress.getTopicProgress(b.id)?.score ?? 0).compareTo(progress.getTopicProgress(a.id)?.score ?? 0));
    }
    return sorted;
  }
}

extension on Topic {
  String get difficultyLabel => switch (difficulty) {
    1 => '入门',
    2 => '基础',
    3 => '中等',
    4 => '较难',
    5 => '困难',
    _ => '',
  };
}
