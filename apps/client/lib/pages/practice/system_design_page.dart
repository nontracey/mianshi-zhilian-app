import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import '../../providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

class SystemDesignPage extends StatefulWidget {
  const SystemDesignPage({super.key});

  @override
  State<SystemDesignPage> createState() => _SystemDesignPageState();
}

class _SystemDesignPageState extends State<SystemDesignPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  String _selectedCategory = 'all';
  final List<Map<String, dynamic>> _savedDesigns = [];

  List<Map<String, dynamic>> get _fallbackTopics => [
    {
      'id': 'url_shortener',
      'title': l10n.get('77ed_link_system'),
      'category': l10n.get('basic'),
      'difficulty': 2,
      'description': l10n.get('design_4e00_4e2a_77ed_link_751f_6210_548c_8df3_8f6c_670d_52a'),
      'keyPoints': [l10n.get('hash_algorithm'), l10n.get('database_design'), l10n.get('cache_strategy'), l10n.get('91cd_5b9a_5411_mechanism')],
      'estimatedMinutes': 30,
    },
    {
      'id': 'feed_system',
      'title': l10n.get('info_6d41_system'),
      'category': l10n.get('social'),
      'difficulty': 3,
      'description': l10n.get('design_social_5a92_4f53_7684_info_6d41_63a8_9001_system'),
      'keyPoints': [l10n.get('63a8_62c9_6a21_5f0f'), l10n.get('time_7ebf_sort'), l10n.get('cache_strategy'), l10n.get('5206_9875_loading')],
      'estimatedMinutes': 45,
    },
    {
      'id': 'chat_system',
      'title': l10n.get('5373_65f6_communication_system'),
      'category': l10n.get('communication'),
      'difficulty': 3,
      'description': l10n.get('design_4e00_4e2a_652f_6301_5355_804a_548c_7fa4_804a_7684_537'),
      'keyPoints': ['WebSocket', l10n.get('message_queue'), l10n.get('offline_message'), l10n.get('already_8bfb_status')],
      'estimatedMinutes': 45,
    },
    {
      'id': 'search_engine',
      'title': l10n.get('search_5f15_64ce'),
      'category': l10n.get('search'),
      'difficulty': 4,
      'description': l10n.get('design_4e00_4e2a_5168_6587_search_5f15_64ce'),
      'keyPoints': [l10n.get('inverted_index'), l10n.get('5206_8bcd_5668'), l10n.get('76f8_5173_6027_sort'), l10n.get('distributed_search')],
      'estimatedMinutes': 60,
    },
    {
      'id': 'payment_system',
      'title': l10n.get('payment_system'),
      'category': l10n.get('finance'),
      'difficulty': 4,
      'description': l10n.get('design_4e00_4e2a_security_53ef_9760_7684_payment_system'),
      'keyPoints': [l10n.get('transaction_consistency'), l10n.get('idempotent_6027'), l10n.get('5bf9_8d26_mechanism'), l10n.get('98ce_63a7_strategy')],
      'estimatedMinutes': 60,
    },
    {
      'id': 'recommendation',
      'title': l10n.get('recommend_system'),
      'category': 'AI',
      'difficulty': 4,
      'description': l10n.get('design_4e00_4e2a_4e2a_6027_5316_content_recommend_system'),
      'keyPoints': [l10n.get('534f_540c_8fc7_6ee4'), l10n.get('content_recommend'), l10n.get('realtime_7279_5f81'), l10n.get('ab_test')],
      'estimatedMinutes': 60,
    },
    {
      'id': 'distributed_cache',
      'title': l10n.get('distributed_cache'),
      'category': l10n.get('basic_8bbe_65bd'),
      'difficulty': 3,
      'description': l10n.get('design_4e00_4e2a_distributed_cache_system'),
      'keyPoints': [l10n.get('consistency_hash'), l10n.get('cache_7a7f_900f'), l10n.get('cache_96ea_5d29'), l10n.get('data_sync')],
      'estimatedMinutes': 45,
    },
    {
      'id': 'message_queue',
      'title': l10n.get('message_queue'),
      'category': l10n.get('basic_8bbe_65bd'),
      'difficulty': 4,
      'description': l10n.get('design_4e00_4e2a_ha_7684_message_queue_system'),
      'keyPoints': [l10n.get('6301_4e45_5316'), l10n.get('6d88_8d39_confirm'), l10n.get('987a_5e8f_message'), l10n.get('6b7b_4fe1_queue')],
      'estimatedMinutes': 60,
    },
    {
      'id': 'rate_limiter',
      'title': l10n.get('rate_limit_system'),
      'category': l10n.get('basic_8bbe_65bd'),
      'difficulty': 2,
      'description': l10n.get('design_4e00_4e2a_api_rate_limit_system'),
      'keyPoints': [l10n.get('4ee4_724c_6876'), l10n.get('6ed1_52a8_7a97_53e3'), l10n.get('distributed_rate_limit'), l10n.get('degrade_strategy')],
      'estimatedMinutes': 30,
    },
    {
      'id': 'task_scheduler',
      'title': l10n.get('task_8c03_5ea6_system'),
      'category': l10n.get('basic_8bbe_65bd'),
      'difficulty': 3,
      'description': l10n.get('design_4e00_4e2a_distributed_task_8c03_5ea6_system'),
      'keyPoints': [l10n.get('5b9a_65f6_task'), l10n.get('task_4f9d_8d56'), l10n.get('fail_retry'), l10n.get('load_balance')],
      'estimatedMinutes': 45,
    },
  ];

  /// 从内容仓库加载系统设计主题，无内容时使用硬编码回退
  List<Map<String, dynamic>> _getContentTopics(BuildContext context) {
    final contentProvider = context.read<ContentProvider>();
    // 尝试从所有领域中找系统设计相关的主题
    final allTopics = <Topic>[];
    for (final domain in contentProvider.domains) {
      allTopics.addAll(contentProvider.getTopicsByDomain(domain.id));
    }
    final systemDesignTopics = allTopics.where((t) {
      final cat = t.category.toLowerCase();
      final tags = t.tags.map((e) => e.toLowerCase()).toList();
      return cat.contains('系统设计') ||
          cat.contains('架构') ||
          tags.any((e) =>
              e.contains('系统设计') ||
              e.contains('架构') ||
              e.contains('system-design'));
    }).toList();

    if (systemDesignTopics.isEmpty) return _fallbackTopics;

    return systemDesignTopics.map((t) => <String, dynamic>{
      'id': t.id,
      'title': t.title,
      'category': t.category.isEmpty ? l10n.get('901a_7528') : t.category,
      'difficulty': t.difficulty,
      'description': t.summary,
      'keyPoints': t.tags.isEmpty ? [l10n.get('system_design')] : t.tags.take(4).toList(),
      'estimatedMinutes': t.estimatedMinutes,
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final designTopics = _getContentTopics(context);
    final filteredTopics = _selectedCategory == 'all'
        ? designTopics
        : designTopics.where((t) => t['category'] == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('system_design_practice')),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showDesignGuide(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部统计
          _buildStatsHeader(context, isDark, designTopics),

          // 分类筛选
          _buildCategoryFilter(context, isDark, designTopics),
          
          // 题目列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredTopics.length,
              itemBuilder: (context, index) {
                return _buildDesignCard(context, filteredTopics[index], isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(BuildContext context, bool isDark, List<Map<String, dynamic>> topics) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(l10n.get('603b_question_count_6570'), '${topics.length}', AppColors.accent),
          _buildStatItem(l10n.get('already_practice'), '${_savedDesigns.length}', AppColors.success),
          _buildStatItem(l10n.get('5f85_practice'), '${topics.length - _savedDesigns.length}', AppColors.warning),
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
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter(BuildContext context, bool isDark, List<Map<String, dynamic>> topics) {
    final dynamicCategories = topics.map((t) => t['category'] as String).toSet().toList()..sort();
    final categories = ['all', ...dynamicCategories];
    
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Text(cat == 'all' ? l10n.get('all') : cat),
              onSelected: (_) => setState(() => _selectedCategory = cat),
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

  Widget _buildDesignCard(BuildContext context, Map<String, dynamic> topic, bool isDark) {
    final difficulty = topic['difficulty'] as int;
    final difficultyLabels = {1: l10n.get('beginner'), 2: l10n.get('basic'), 3: l10n.get('medium'), 4: l10n.get('8f83_96be'), 5: l10n.get('hard')};
    final difficultyColors = {
      1: const Color(0xFF10B981),
      2: const Color(0xFF00CCF9),
      3: const Color(0xFFF59E0B),
      4: const Color(0xFFEF4444),
      5: const Color(0xFF7C3AED),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
        ),
      ),
      child: InkWell(
        onTap: () => _startDesignPractice(context, topic),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      topic['title'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (difficultyColors[difficulty] ?? Colors.grey).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      difficultyLabels[difficulty] ?? l10n.get('un_77e5'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: difficultyColors[difficulty] ?? Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // 描述
              Text(
                topic['description'],
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : const Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 12),
              
              // 关键点
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (topic['keyPoints'] as List<String>).map((point) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      point,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.accent,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              
              // 底部信息
              Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: isDark ? Colors.white38 : const Color(0xFF999999),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${l10n.get('9884_8ba1')} ${topic['estimatedMinutes']} ${l10n.get('min')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : const Color(0xFF999999),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _startDesignPractice(context, topic),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(l10n.get('start_practice')),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startDesignPractice(BuildContext context, Map<String, dynamic> topic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) => _buildDesignPracticeSheet(
          ctx,
          topic,
          scrollController,
        ),
      ),
    );
  }

  Widget _buildDesignPracticeSheet(
    BuildContext context,
    Map<String, dynamic> topic,
    ScrollController scrollController,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: ListView(
        controller: scrollController,
        children: [
          // 拖动指示器
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 标题
          Text(
            topic['title'],
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            topic['description'],
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 20),
          
          // 设计步骤
          _buildDesignStep(l10n.get('1_9700_6c42_6f84_6e05'), [
            l10n.get('confirm_feature_8303_56f4_548c_975e_feature_9700_6c42'),
            l10n.get('660e_786e_user_89c4_6a21_548c_6d41_91cf_9884_4f30'),
            l10n.get('786e_5b9a_data_consistency_8981_6c42'),
            l10n.get('8bc6_522b_core_feature_548c_secondary_feature'),
          ]),
          _buildDesignStep(l10n.get('2_5bb9_91cf_4f30_7b97'), [
            l10n.get('day_6d3b_user_6570_dau'),
            l10n.get('6bcf_user_daily_8bf7_6c42_6570_qps'),
            l10n.get('5b58_50a8_5bb9_91cf_4f30_7b97'),
            l10n.get('5e26_5bbd_9700_6c42_4f30_7b97'),
          ]),
          _buildDesignStep(l10n.get('3_system_architecture'), [
            l10n.get('6574_4f53_architecture_56fe_design'),
            l10n.get('core_7ec4_4ef6_5212_5206'),
            l10n.get('data_6d41_5411_design'),
            l10n.get('interface_design'),
          ]),
          _buildDesignStep(l10n.get('4_data_5b58_50a8'), [
            l10n.get('database_9009_578b_sql_nosql'),
            l10n.get('8868_structure_design'),
            l10n.get('index_design'),
            l10n.get('5206_5e93_5206_8868_strategy'),
          ]),
          _buildDesignStep(l10n.get('5_core_design'), [
            l10n.get('key_4e1a_52a1_6d41_7a0b'),
            l10n.get('concurrent_5904_7406_solution'),
            l10n.get('cache_strategy'),
            l10n.get('message_queue_4f7f_7528'),
          ]),
          _buildDesignStep(l10n.get('6_extension_optimize'), [
            l10n.get('performance_74f6_9888_analysis'),
            l10n.get('53ef_extension_6027_design'),
            l10n.get('ha_solution'),
            l10n.get('monitor_alert'),
          ]),
          const SizedBox(height: 20),
          
          // 开始练习按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: Text(l10n.get('5173_95ed')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    // 显示练习提示
                    _showPracticeGuide(context, topic);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.get('start_practice')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesignStep(String title, List<String> points) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          ...points.map((point) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: Colors.grey.shade600)),
                Expanded(
                  child: Text(
                    point,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  void _showDesignGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('system_design_interview_6307_5357')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.get('interview_6d41_7a0b'), style: TextStyle(fontWeight: FontWeight.w700)),
              Text(l10n.get('1_9700_6c42_6f84_6e05_5_min')),
              Text(l10n.get('2_5bb9_91cf_4f30_7b97_5_min')),
              Text(l10n.get('3_system_architecture_15_min')),
              Text(l10n.get('4_core_design_15_min')),
              Text(l10n.get('5_extension_optimize_10_min')),
              SizedBox(height: 16),
              Text(l10n.get('8bc4_5206_7ef4_5ea6'), style: TextStyle(fontWeight: FontWeight.w700)),
              Text(l10n.get('problem_analysis_ability')),
              Text(l10n.get('architecture_design_ability')),
              Text(l10n.get('tech_depth')),
              Text(l10n.get('communication_expression_ability')),
              SizedBox(height: 16),
              Text(l10n.get('6ce8_610f_4e8b_9879'), style: TextStyle(fontWeight: FontWeight.w700)),
              Text(l10n.get('5148_confirm_9700_6c42_518d_design_solution')),
              Text(l10n.get('4ece_9ad8_5c42_design_9010_6b65_6df1_5165')),
              Text(l10n.get('4e3b_52a8_8ba8_8bba_tradeoff')),
              Text(l10n.get('8003_8651_8fb9_754c_60c5_51b5_548c_5f02_5e38_5904_7406')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('77e5_9053_4e86')),
          ),
        ],
      ),
    );
  }

  void _showPracticeGuide(BuildContext context, Map<String, dynamic> topic) {
    final keyPoints = topic['keyPoints'] as List<String>? ?? [];
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.getp('practice_{title}', {'title': topic['title']})),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(topic['description'] ?? '', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              Text(l10n.get('key_knowledge_point'), style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...keyPoints.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• '),
                    Expanded(child: Text(point)),
                  ],
                ),
              )),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.get('practice_suggestion'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    SizedBox(height: 4),
                    Text(l10n.get('1_6309_7167_9700_6c42_6f84_6e05_5bb9_91cf_4f30_7b97_architec'), style: TextStyle(fontSize: 12)),
                    Text(l10n.get('2_7528_7eb8_7b14_753b_51fa_architecture_56fe'), style: TextStyle(fontSize: 12)),
                    Text(l10n.get('3_8bb0_5f55_key_decision_548c_tradeoff'), style: TextStyle(fontSize: 12)),
                    Text(l10n.get('4_63a7_5236_time_5728_3045_min_5185'), style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('5173_95ed')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.get('start_8ba1_65f6_6309_6b65_9aa4_complete_system_design')),
                  duration: Duration(seconds: 3),
                ),
              );
            },
            child: Text(l10n.get('start_practice')),
          ),
        ],
      ),
    );
  }
}
