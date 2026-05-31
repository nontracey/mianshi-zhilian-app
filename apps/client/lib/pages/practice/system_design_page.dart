import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
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
      'title': l10n.get('short_link_system'),
      'category': l10n.get('basic'),
      'difficulty': 2,
      'description': l10n.get(
        'design_one_short_link_life_achievement_and_skip_transfer_service_52a',
      ),
      'keyPoints': [
        l10n.get('hash_algorithm'),
        l10n.get('database_design'),
        l10n.get('cache_strategy'),
        l10n.get('restart_fixed_direction_mechanism'),
      ],
      'estimatedMinutes': 30,
    },
    {
      'id': 'feed_system',
      'title': l10n.get('info_flow_system'),
      'category': l10n.get('social'),
      'difficulty': 3,
      'description': l10n.get(
        'design_social_media_body_info_flow_push_send_system',
      ),
      'keyPoints': [
        l10n.get('push_pull_mode'),
        l10n.get('time_line_sort'),
        l10n.get('cache_strategy'),
        l10n.get('score_page_loading'),
      ],
      'estimatedMinutes': 45,
    },
    {
      'id': 'chat_system',
      'title': l10n.get('instant_time_communication_system'),
      'category': l10n.get('communication'),
      'difficulty': 3,
      'description': l10n.get(
        'design_one_support_long_single_chat_and_group_537',
      ),
      'keyPoints': [
        'WebSocket',
        l10n.get('message_queue'),
        l10n.get('offline_message'),
        l10n.get('already_read_status'),
      ],
      'estimatedMinutes': 45,
    },
    {
      'id': 'search_engine',
      'title': l10n.get('search_engine'),
      'category': l10n.get('search'),
      'difficulty': 4,
      'description': l10n.get('design_one_all_text_search_engine'),
      'keyPoints': [
        l10n.get('inverted_index'),
        l10n.get('score_term_device'),
        l10n.get('mutual_close_capability_sort'),
        l10n.get('distributed_search'),
      ],
      'estimatedMinutes': 60,
    },
    {
      'id': 'payment_system',
      'title': l10n.get('payment_system'),
      'category': l10n.get('finance'),
      'difficulty': 4,
      'description': l10n.get(
        'design_one_security_optional_depend_payment_system',
      ),
      'keyPoints': [
        l10n.get('transaction_consistency'),
        l10n.get('idempotent_capability'),
        l10n.get('peer_accounting_mechanism'),
        l10n.get('wind_control_strategy'),
      ],
      'estimatedMinutes': 60,
    },
    {
      'id': 'recommendation',
      'title': l10n.get('recommend_system'),
      'category': 'AI',
      'difficulty': 4,
      'description': l10n.get(
        'design_one_capability_transform_content_recommend_system',
      ),
      'keyPoints': [
        l10n.get('coordinate_same_pass_filter'),
        l10n.get('content_recommend'),
        l10n.get('realtime_feature_characteristic'),
        l10n.get('ab_test'),
      ],
      'estimatedMinutes': 60,
    },
    {
      'id': 'distributed_cache',
      'title': l10n.get('distributed_cache'),
      'category': l10n.get('basic_design_implement'),
      'difficulty': 3,
      'description': l10n.get('design_one_distributed_cache_system'),
      'keyPoints': [
        l10n.get('consistency_hash'),
        l10n.get('cache_cross_transparent'),
        l10n.get('cache_snow_crash'),
        l10n.get('data_sync'),
      ],
      'estimatedMinutes': 45,
    },
    {
      'id': 'message_queue',
      'title': l10n.get('message_queue'),
      'category': l10n.get('basic_design_implement'),
      'difficulty': 4,
      'description': l10n.get('design_one_ha_message_queue_system'),
      'keyPoints': [
        l10n.get('long_long_term_transform'),
        l10n.get('expire_cost_confirm'),
        l10n.get('smooth_sequence_message'),
        l10n.get('dead_trust_queue'),
      ],
      'estimatedMinutes': 60,
    },
    {
      'id': 'rate_limiter',
      'title': l10n.get('rate_limit_system'),
      'category': l10n.get('basic_design_implement'),
      'difficulty': 2,
      'description': l10n.get('design_one_api_rate_limit_system'),
      'keyPoints': [
        l10n.get('order_token_bucket'),
        l10n.get('slide_dynamic_window_port'),
        l10n.get('distributed_rate_limit'),
        l10n.get('degrade_strategy'),
      ],
      'estimatedMinutes': 30,
    },
    {
      'id': 'task_scheduler',
      'title': l10n.get('task_schedule_degree_system'),
      'category': l10n.get('basic_design_implement'),
      'difficulty': 3,
      'description': l10n.get(
        'design_one_distributed_task_schedule_degree_system',
      ),
      'keyPoints': [
        l10n.get('fixed_time_task'),
        l10n.get('task_according_depend'),
        l10n.get('fail_retry'),
        l10n.get('load_balance'),
      ],
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
          tags.any(
            (e) =>
                e.contains('系统设计') ||
                e.contains('架构') ||
                e.contains('system-design'),
          );
    }).toList();

    if (systemDesignTopics.isEmpty) return _fallbackTopics;

    return systemDesignTopics
        .map(
          (t) => <String, dynamic>{
            'id': t.id,
            'title': t.title,
            'category': t.category.isEmpty ? l10n.get('open_use') : t.category,
            'difficulty': t.difficulty,
            'description': t.summary,
            'keyPoints': t.tags.isEmpty
                ? [l10n.get('system_design')]
                : t.tags.take(4).toList(),
            'estimatedMinutes': t.estimatedMinutes,
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final designTopics = _getContentTopics(context);
    final filteredTopics = _selectedCategory == 'all'
        ? designTopics
        : designTopics
              .where((t) => t['category'] == _selectedCategory)
              .toList();

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

  Widget _buildStatsHeader(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> topics,
  ) {
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
          _buildStatItem(
            l10n.get('total_question_count'),
            '${topics.length}',
            AppColors.accent,
          ),
          _buildStatItem(
            l10n.get('already_practice'),
            '${_savedDesigns.length}',
            AppColors.success,
          ),
          _buildStatItem(
            l10n.get('pending_practice'),
            '${topics.length - _savedDesigns.length}',
            AppColors.warning,
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
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> topics,
  ) {
    final dynamicCategories =
        topics.map((t) => t['category'] as String).toSet().toList()..sort();
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
                    : (isDark
                          ? const Color(0xFF263238)
                          : const Color(0xFFE0E0E0)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDesignCard(
    BuildContext context,
    Map<String, dynamic> topic,
    bool isDark,
  ) {
    final difficulty = topic['difficulty'] as int;
    final difficultyLabels = {
      1: l10n.get('beginner'),
      2: l10n.get('basic'),
      3: l10n.get('medium'),
      4: l10n.get('compare_difficult'),
      5: l10n.get('hard'),
    };
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (difficultyColors[difficulty] ?? Colors.grey)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      difficultyLabels[difficulty] ?? l10n.get('un_known'),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                    '${l10n.get('pre_plan')} ${topic['estimatedMinutes']} ${l10n.get('min')}',
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
        builder: (ctx, scrollController) =>
            _buildDesignPracticeSheet(ctx, topic, scrollController),
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            topic['description'],
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // 设计步骤
          _buildDesignStep(l10n.get('step_1_requirement_clarify'), [
            l10n.get('confirm_feature_scope_and_non_demand_requirement'),
            l10n.get(
              'clear_confirm_user_plan_mode_and_flow_volume_pre_estimate',
            ),
            l10n.get('confirm_fixed_data_consistency_key_requirement'),
            l10n.get('identify_distinct_core_feature_and_secondary'),
          ]),
          _buildDesignStep(l10n.get('step_2_capacity_estimation'), [
            l10n.get('day_live_user_count_dau'),
            l10n.get('per_user_daily_please_requirement_count_qps'),
            l10n.get('storage_capacity_estimation'),
            l10n.get('bandwidth_requirement_estimation'),
          ]),
          _buildDesignStep(l10n.get('step_3_system_architecture_2'), [
            l10n.get('overall_architecture_design'),
            l10n.get('core_group_condition_plan_score'),
            l10n.get('data_flow_direction_design'),
            l10n.get('interface_design'),
          ]),
          _buildDesignStep(l10n.get('step_4_data_storage'), [
            l10n.get('database_select_type_sql_nosql'),
            l10n.get('surface_structure_design'),
            l10n.get('index_design'),
            l10n.get('score_library_surface_strategy'),
          ]),
          _buildDesignStep(l10n.get('step_5_core_design_2'), [
            l10n.get('key_business_service_flow_process'),
            l10n.get('concurrent_handle_principle_solution'),
            l10n.get('cache_strategy'),
            l10n.get('message_queue_use'),
          ]),
          _buildDesignStep(l10n.get('step_6_extension_optimize_2'), [
            l10n.get('performance_bottleneck_neck_analysis'),
            l10n.get('optional_extension_capability_design'),
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
                  label: Text(l10n.get('close')),
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
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...points.map(
            (point) => Padding(
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
            ),
          ),
        ],
      ),
    );
  }

  void _showDesignGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('system_design_interview_finger_south')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.get('interview_flow_process'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(l10n.get('step_1_requirement_clarify_5_min')),
              Text(l10n.get('step_2_capacity_estimation_5_min')),
              Text(l10n.get('time_3_system_architecture_15_min_2')),
              Text(l10n.get('time_4_core_design_15_min_2')),
              Text(l10n.get('time_5_extension_optimize_10_min_2')),
              SizedBox(height: 16),
              Text(
                l10n.get('evaluation_score_dimension_degree'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(l10n.get('problem_analysis_ability')),
              Text(l10n.get('architecture_design_ability')),
              Text(l10n.get('tech_depth')),
              Text(l10n.get('communication_expression_ability')),
              SizedBox(height: 16),
              Text(
                l10n.get('note_intention_matter_item'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(l10n.get('confirm_requirement_before_design')),
              Text(l10n.get('top_down_design_approach')),
              Text(l10n.get('proactive_tradeoff_discussion')),
              Text(
                l10n.get(
                  'exam_consider_edge_boundary_context_situation_and_abnormal_often_handle_principle',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('known_channel')),
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
        title: Text(l10n.getp('practice_title_3', {'title': topic['title']})),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                topic['description'] ?? '',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.get('key_knowledge_point'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...keyPoints.map(
                (point) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• '),
                      Expanded(child: Text(point)),
                    ],
                  ),
                ),
              ),
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
                    Text(
                      l10n.get('practice_suggestion'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      l10n.get('system_design_steps'),
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      l10n.get('step_2_draw_architecture'),
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      l10n.get('step_3_record_key_decision_tradeoff'),
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      l10n.get('step_4_control_time_30_45_min'),
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('close')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.get(
                      'start_plan_time_press_step_complete_system_design',
                    ),
                  ),
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
