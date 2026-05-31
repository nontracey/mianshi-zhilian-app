import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import '../../providers/localization_provider.dart';

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
      'title': l10n.get('短链接系统'),
      'category': l10n.get('基础'),
      'difficulty': 2,
      'description': l10n.get('设计一个短链接生成和跳转服务'),
      'keyPoints': [l10n.get('哈希算法'), l10n.get('数据库设计'), l10n.get('缓存策略'), l10n.get('重定向机制')],
      'estimatedMinutes': 30,
    },
    {
      'id': 'feed_system',
      'title': l10n.get('信息流系统'),
      'category': l10n.get('社交'),
      'difficulty': 3,
      'description': l10n.get('设计社交媒体的信息流推送系统'),
      'keyPoints': [l10n.get('推拉模式'), l10n.get('时间线排序'), l10n.get('缓存策略'), l10n.get('分页加载')],
      'estimatedMinutes': 45,
    },
    {
      'id': 'chat_system',
      'title': l10n.get('即时通讯系统'),
      'category': l10n.get('通讯'),
      'difficulty': 3,
      'description': l10n.get('设计一个支持单聊和群聊的即时通讯系统'),
      'keyPoints': ['WebSocket', l10n.get('消息队列'), l10n.get('离线消息'), l10n.get('已读状态')],
      'estimatedMinutes': 45,
    },
    {
      'id': 'search_engine',
      'title': l10n.get('搜索引擎'),
      'category': l10n.get('搜索'),
      'difficulty': 4,
      'description': l10n.get('设计一个全文搜索引擎'),
      'keyPoints': [l10n.get('倒排索引'), l10n.get('分词器'), l10n.get('相关性排序'), l10n.get('分布式搜索')],
      'estimatedMinutes': 60,
    },
    {
      'id': 'payment_system',
      'title': l10n.get('支付系统'),
      'category': l10n.get('金融'),
      'difficulty': 4,
      'description': l10n.get('设计一个安全可靠的支付系统'),
      'keyPoints': [l10n.get('事务一致性'), l10n.get('幂等性'), l10n.get('对账机制'), l10n.get('风控策略')],
      'estimatedMinutes': 60,
    },
    {
      'id': 'recommendation',
      'title': l10n.get('推荐系统'),
      'category': 'AI',
      'difficulty': 4,
      'description': l10n.get('设计一个个性化内容推荐系统'),
      'keyPoints': [l10n.get('协同过滤'), l10n.get('内容推荐'), l10n.get('实时特征'), l10n.get('AB测试')],
      'estimatedMinutes': 60,
    },
    {
      'id': 'distributed_cache',
      'title': l10n.get('分布式缓存'),
      'category': l10n.get('基础设施'),
      'difficulty': 3,
      'description': l10n.get('设计一个分布式缓存系统'),
      'keyPoints': [l10n.get('一致性哈希'), l10n.get('缓存穿透'), l10n.get('缓存雪崩'), l10n.get('数据同步')],
      'estimatedMinutes': 45,
    },
    {
      'id': 'message_queue',
      'title': l10n.get('消息队列'),
      'category': l10n.get('基础设施'),
      'difficulty': 4,
      'description': l10n.get('设计一个高可用的消息队列系统'),
      'keyPoints': [l10n.get('持久化'), l10n.get('消费确认'), l10n.get('顺序消息'), l10n.get('死信队列')],
      'estimatedMinutes': 60,
    },
    {
      'id': 'rate_limiter',
      'title': l10n.get('限流系统'),
      'category': l10n.get('基础设施'),
      'difficulty': 2,
      'description': l10n.get('设计一个API限流系统'),
      'keyPoints': [l10n.get('令牌桶'), l10n.get('滑动窗口'), l10n.get('分布式限流'), l10n.get('降级策略')],
      'estimatedMinutes': 30,
    },
    {
      'id': 'task_scheduler',
      'title': l10n.get('任务调度系统'),
      'category': l10n.get('基础设施'),
      'difficulty': 3,
      'description': l10n.get('设计一个分布式任务调度系统'),
      'keyPoints': [l10n.get('定时任务'), l10n.get('任务依赖'), l10n.get('失败重试'), l10n.get('负载均衡')],
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
      'category': t.category.isEmpty ? l10n.get('通用') : t.category,
      'difficulty': t.difficulty,
      'description': t.summary,
      'keyPoints': t.tags.isEmpty ? [l10n.get('系统设计')] : t.tags.take(4).toList(),
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
        title: Text(l10n.get('系统设计练习')),
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
          _buildStatItem(l10n.get('总题数'), '${topics.length}', AppColors.accent),
          _buildStatItem(l10n.get('已练习'), '${_savedDesigns.length}', AppColors.success),
          _buildStatItem(l10n.get('待练习'), '${topics.length - _savedDesigns.length}', AppColors.warning),
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
              label: Text(cat == 'all' ? l10n.get('全部') : cat),
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
    final difficultyLabels = {1: l10n.get('入门'), 2: l10n.get('基础'), 3: l10n.get('中等'), 4: l10n.get('较难'), 5: l10n.get('困难')};
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
                      difficultyLabels[difficulty] ?? l10n.get('未知'),
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
                    '${l10n.get('预计')} ${topic['estimatedMinutes']} ${l10n.get('分钟')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : const Color(0xFF999999),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _startDesignPractice(context, topic),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(l10n.get('开始练习')),
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
          _buildDesignStep(l10n.get('1_需求澄清'), [
            l10n.get('确认功能范围和非功能需求'),
            l10n.get('明确用户规模和流量预估'),
            l10n.get('确定数据一致性要求'),
            l10n.get('识别核心功能和次要功能'),
          ]),
          _buildDesignStep(l10n.get('2_容量估算'), [
            l10n.get('日活用户数_DAU'),
            l10n.get('每用户每日请求数_QPS'),
            l10n.get('存储容量估算'),
            l10n.get('带宽需求估算'),
          ]),
          _buildDesignStep(l10n.get('3_系统架构'), [
            l10n.get('整体架构图设计'),
            l10n.get('核心组件划分'),
            l10n.get('数据流向设计'),
            l10n.get('接口设计'),
          ]),
          _buildDesignStep(l10n.get('4_数据存储'), [
            l10n.get('数据库选型_SQL_NoSQL'),
            l10n.get('表结构设计'),
            l10n.get('索引设计'),
            l10n.get('分库分表策略'),
          ]),
          _buildDesignStep(l10n.get('5_核心设计'), [
            l10n.get('关键业务流程'),
            l10n.get('并发处理方案'),
            l10n.get('缓存策略'),
            l10n.get('消息队列使用'),
          ]),
          _buildDesignStep(l10n.get('6_扩展优化'), [
            l10n.get('性能瓶颈分析'),
            l10n.get('可扩展性设计'),
            l10n.get('高可用方案'),
            l10n.get('监控告警'),
          ]),
          const SizedBox(height: 20),
          
          // 开始练习按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: Text(l10n.get('关闭')),
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
                  label: Text(l10n.get('开始练习')),
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
        title: Text(l10n.get('系统设计面试指南')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.get('面试流程'), style: TextStyle(fontWeight: FontWeight.w700)),
              Text(l10n.get('1_需求澄清_5分钟')),
              Text(l10n.get('2_容量估算_5分钟')),
              Text(l10n.get('3_系统架构_15分钟')),
              Text(l10n.get('4_核心设计_15分钟')),
              Text(l10n.get('5_扩展优化_10分钟')),
              SizedBox(height: 16),
              Text(l10n.get('评分维度'), style: TextStyle(fontWeight: FontWeight.w700)),
              Text(l10n.get('问题分析能力')),
              Text(l10n.get('架构设计能力')),
              Text(l10n.get('技术深度')),
              Text(l10n.get('沟通表达能力')),
              SizedBox(height: 16),
              Text(l10n.get('注意事项'), style: TextStyle(fontWeight: FontWeight.w700)),
              Text(l10n.get('先确认需求再设计方案')),
              Text(l10n.get('从高层设计逐步深入')),
              Text(l10n.get('主动讨论_tradeoff')),
              Text(l10n.get('考虑边界情况和异常处理')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('知道了')),
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
        title: Text(l10n.getp('练习：{title}', {'title': topic['title']})),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(topic['description'] ?? '', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              Text(l10n.get('关键知识点'), style: TextStyle(fontWeight: FontWeight.w600)),
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
                    Text(l10n.get('练习建议'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    SizedBox(height: 4),
                    Text(l10n.get('1_按照需求澄清__容量估算__架构设计__核心设计__扩展优化的顺序进行'), style: TextStyle(fontSize: 12)),
                    Text(l10n.get('2_用纸笔画出架构图'), style: TextStyle(fontSize: 12)),
                    Text(l10n.get('3_记录关键决策和_tradeoff'), style: TextStyle(fontSize: 12)),
                    Text(l10n.get('4_控制时间在_3045_分钟内'), style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('关闭')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.get('开始计时_按步骤完成系统设计')),
                  duration: Duration(seconds: 3),
                ),
              );
            },
            child: Text(l10n.get('开始练习')),
          ),
        ],
      ),
    );
  }
}
