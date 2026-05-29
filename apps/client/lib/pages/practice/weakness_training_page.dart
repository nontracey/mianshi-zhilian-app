import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/pages/practice/recall_page.dart';

class WeaknessTrainingPage extends StatefulWidget {
  const WeaknessTrainingPage({
    super.key,
    required this.currentDomainId,
  });

  final String currentDomainId;

  @override
  State<WeaknessTrainingPage> createState() => _WeaknessTrainingPageState();
}

class _WeaknessTrainingPageState extends State<WeaknessTrainingPage> {
  String _selectedCategory = 'all';
  String _sortBy = 'score'; // score, frequency, recent

  @override
  Widget build(BuildContext context) {
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final domainTopics = contentProvider.getTopicsByDomain(widget.currentDomainId);
    final weakTopics = _getWeakTopics(domainTopics, progressProvider);
    final categorizedWeakness = _categorizeWeakness(weakTopics, progressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('弱点训练包'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showTrainingGuide(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部统计
          _buildStatsHeader(context, weakTopics, categorizedWeakness, isDark),
          
          // 分类筛选
          _buildCategoryFilter(context, categorizedWeakness, isDark),
          
          // 弱点列表
          Expanded(
            child: _buildWeaknessList(context, weakTopics, progressProvider, isDark),
          ),
        ],
      ),
      bottomNavigationBar: _buildStartButton(context, weakTopics),
    );
  }

  List<Topic> _getWeakTopics(List<Topic> domainTopics, ProgressProvider progress) {
    return domainTopics.where((topic) {
      final score = progress.getTopicProgress(topic.id)?.score ?? 0;
      return score > 0 && score < 85; // 有练习记录但未达熟练
    }).toList();
  }

  Map<String, List<Topic>> _categorizeWeakness(List<Topic> weakTopics, ProgressProvider progress) {
    final categories = <String, List<Topic>>{
      'all': weakTopics,
      'concept': [], // 概念缺失
      'confusion': [], // 混淆
      'expression': [], // 表达不清
      'depth': [], // 深度不足
      'code': [], // 代码边界
    };

    for (final topic in weakTopics) {
      final attempts = progress.getAttemptsForTopic(topic.id);
      final lastAttempt = attempts.isNotEmpty ? attempts.last : null;
      final errorTags = lastAttempt?.errorTags ?? [];

      if (errorTags.contains('concept') || errorTags.contains('概念缺失')) {
        categories['concept']!.add(topic);
      } else if (errorTags.contains('confusion') || errorTags.contains('混淆')) {
        categories['confusion']!.add(topic);
      } else if (errorTags.contains('expression') || errorTags.contains('表达不清')) {
        categories['expression']!.add(topic);
      } else if (errorTags.contains('depth') || errorTags.contains('深度不足')) {
        categories['depth']!.add(topic);
      } else if (errorTags.contains('code') || errorTags.contains('代码边界')) {
        categories['code']!.add(topic);
      } else {
        // 根据分数和难度推断
        final score = progress.getTopicProgress(topic.id)?.score ?? 0;
        if (score < 40) {
          categories['concept']!.add(topic);
        } else if (score < 60) {
          categories['confusion']!.add(topic);
        } else {
          categories['expression']!.add(topic);
        }
      }
    }

    return categories;
  }

  List<Topic> _getFilteredTopics(List<Topic> weakTopics, ProgressProvider progress) {
    var filtered = weakTopics;

    // 按分类筛选
    if (_selectedCategory != 'all') {
      final categorized = _categorizeWeakness(weakTopics, progress);
      filtered = categorized[_selectedCategory] ?? [];
    }

    // 排序
    switch (_sortBy) {
      case 'score':
        filtered.sort((a, b) {
          final scoreA = progress.getTopicProgress(a.id)?.score ?? 0;
          final scoreB = progress.getTopicProgress(b.id)?.score ?? 0;
          return scoreA.compareTo(scoreB);
        });
        break;
      case 'frequency':
        filtered.sort((a, b) {
          final freqA = a.highFrequency ? 1 : 0;
          final freqB = b.highFrequency ? 1 : 0;
          return freqB.compareTo(freqA);
        });
        break;
      case 'recent':
        filtered.sort((a, b) {
          final lastA = progress.getTopicProgress(a.id)?.lastPracticeAt;
          final lastB = progress.getTopicProgress(b.id)?.lastPracticeAt;
          if (lastA == null && lastB == null) return 0;
          if (lastA == null) return 1;
          if (lastB == null) return -1;
          return lastA.compareTo(lastB);
        });
        break;
    }

    return filtered;
  }

  Widget _buildStatsHeader(BuildContext context, List<Topic> weakTopics, 
      Map<String, List<Topic>> categorized, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15202E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
          ),
        ),
      ),
      child: Column(
        children: [
          // 总数统计
          Row(
            children: [
              _buildStatItem('弱点总数', '${weakTopics.length}', AppColors.warning),
              const SizedBox(width: 24),
              _buildStatItem('概念缺失', '${categorized['concept']?.length ?? 0}', AppColors.danger),
              const SizedBox(width: 24),
              _buildStatItem('混淆不清', '${categorized['confusion']?.length ?? 0}', AppColors.warning),
              const SizedBox(width: 24),
              _buildStatItem('表达问题', '${categorized['expression']?.length ?? 0}', AppColors.accent),
            ],
          ),
          const SizedBox(height: 12),
          // 训练建议
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '建议每天训练 5-10 个弱点，持续 1 周可显著提升',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter(BuildContext context, Map<String, List<Topic>> categorized, bool isDark) {
    final categories = [
      ('all', '全部', Icons.all_inclusive),
      ('concept', '概念缺失', Icons.lightbulb_outline),
      ('confusion', '混淆不清', Icons.compare_arrows),
      ('expression', '表达问题', Icons.record_voice_over),
      ('depth', '深度不足', Icons.layers),
      ('code', '代码边界', Icons.code),
    ];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat.$1;
          final count = categorized[cat.$1]?.length ?? 0;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cat.$3, size: 14),
                  const SizedBox(width: 4),
                  Text(cat.$2),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.accent : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onSelected: (_) => setState(() => _selectedCategory = cat.$1),
              backgroundColor: isDark ? const Color(0xFF1A2332) : Colors.white,
              selectedColor: AppColors.accent.withValues(alpha: 0.2),
              checkmarkColor: AppColors.accent,
              side: BorderSide(
                color: isSelected
                    ? AppColors.accent
                    : (isDark ? const Color(0xFF263238) : const Color(0xFFE0E0E0)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWeaknessList(BuildContext context, List<Topic> weakTopics, 
      ProgressProvider progress, bool isDark) {
    final filteredTopics = _getFilteredTopics(weakTopics, progress);

    if (filteredTopics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              '没有找到弱点知识点',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 排序选项
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '排序：',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF666666),
                ),
              ),
              const SizedBox(width: 8),
              _buildSortChip('分数低→高', 'score', isDark),
              const SizedBox(width: 8),
              _buildSortChip('高频优先', 'frequency', isDark),
              const SizedBox(width: 8),
              _buildSortChip('最近练习', 'recent', isDark),
            ],
          ),
        ),
        
        // 列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredTopics.length,
            itemBuilder: (context, index) {
              final topic = filteredTopics[index];
              return _buildWeaknessItem(context, topic, progress, isDark);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSortChip(String label, String value, bool isDark) {
    final isSelected = _sortBy == value;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent
              : (isDark ? const Color(0xFF1A2332) : const Color(0xFFF5F5F5)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : (isDark ? const Color(0xFF263238) : const Color(0xFFE0E0E0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF666666)),
          ),
        ),
      ),
    );
  }

  Widget _buildWeaknessItem(BuildContext context, Topic topic, 
      ProgressProvider progress, bool isDark) {
    final topicProgress = progress.getTopicProgress(topic.id);
    final score = topicProgress?.score ?? 0;
    final attempts = progress.getAttemptsForTopic(topic.id);
    final lastAttempt = attempts.isNotEmpty ? attempts.last : null;

    final scoreColor = score < 40
        ? AppColors.danger
        : score < 60
            ? AppColors.warning
            : AppColors.accent;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
        ),
      ),
      child: InkWell(
        onTap: () => _startTraining(context, [topic]),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 分数指示器
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$score',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: scoreColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        if (topic.highFrequency)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '高频',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 错误标签
                    if (lastAttempt != null && lastAttempt.errorTags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: lastAttempt.errorTags.take(3).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.warning,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '练习 ${attempts.length} 次 · ${topic.domain}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : const Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ),
              
              // 操作按钮
              IconButton(
                icon: const Icon(Icons.play_circle_outline, color: AppColors.accent),
                onPressed: () => _startTraining(context, [topic]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton(BuildContext context, List<Topic> weakTopics) {
    final filteredTopics = _getFilteredTopics(weakTopics, context.read<ProgressProvider>());
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: FilledButton.icon(
        onPressed: filteredTopics.isEmpty
            ? null
            : () => _startTraining(context, filteredTopics.take(10).toList()),
        icon: const Icon(Icons.play_arrow),
        label: Text('开始训练 (${filteredTopics.length > 10 ? 10 : filteredTopics.length} 题)'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  void _startTraining(BuildContext context, List<Topic> topics) {
    if (topics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可训练的知识点')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecallPage(topicIds: topics.map((t) => t.id).toList()),
      ),
    );
  }

  void _showTrainingGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('弱点训练指南'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('错误类型说明', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('• 概念缺失：对基本概念理解不足'),
              Text('• 混淆不清：与其他概念混淆'),
              Text('• 表达问题：知道但说不清楚'),
              Text('• 深度不足：理解停留在表面'),
              Text('• 代码边界：代码实现细节不清楚'),
              SizedBox(height: 16),
              Text('训练建议', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('1. 每天专注训练 5-10 个弱点'),
              Text('2. 先看参考答案，理解正确思路'),
              Text('3. 用自己的话复述，不要死记硬背'),
              Text('4. 隔天复习，巩固记忆'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
