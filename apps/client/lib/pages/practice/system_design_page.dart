import 'package:flutter/material.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class SystemDesignPage extends StatefulWidget {
  const SystemDesignPage({super.key});

  @override
  State<SystemDesignPage> createState() => _SystemDesignPageState();
}

class _SystemDesignPageState extends State<SystemDesignPage> {
  String _selectedCategory = 'all';
  final List<Map<String, dynamic>> _savedDesigns = [];

  final List<Map<String, dynamic>> _designTopics = [
    {
      'id': 'url_shortener',
      'title': '短链接系统',
      'category': '基础',
      'difficulty': 2,
      'description': '设计一个短链接生成和跳转服务',
      'keyPoints': ['哈希算法', '数据库设计', '缓存策略', '重定向机制'],
      'estimatedMinutes': 30,
    },
    {
      'id': 'feed_system',
      'title': '信息流系统',
      'category': '社交',
      'difficulty': 3,
      'description': '设计社交媒体的信息流推送系统',
      'keyPoints': ['推拉模式', '时间线排序', '缓存策略', '分页加载'],
      'estimatedMinutes': 45,
    },
    {
      'id': 'chat_system',
      'title': '即时通讯系统',
      'category': '通讯',
      'difficulty': 3,
      'description': '设计一个支持单聊和群聊的即时通讯系统',
      'keyPoints': ['WebSocket', '消息队列', '离线消息', '已读状态'],
      'estimatedMinutes': 45,
    },
    {
      'id': 'search_engine',
      'title': '搜索引擎',
      'category': '搜索',
      'difficulty': 4,
      'description': '设计一个全文搜索引擎',
      'keyPoints': ['倒排索引', '分词器', '相关性排序', '分布式搜索'],
      'estimatedMinutes': 60,
    },
    {
      'id': 'payment_system',
      'title': '支付系统',
      'category': '金融',
      'difficulty': 4,
      'description': '设计一个安全可靠的支付系统',
      'keyPoints': ['事务一致性', '幂等性', '对账机制', '风控策略'],
      'estimatedMinutes': 60,
    },
    {
      'id': 'recommendation',
      'title': '推荐系统',
      'category': 'AI',
      'difficulty': 4,
      'description': '设计一个个性化内容推荐系统',
      'keyPoints': ['协同过滤', '内容推荐', '实时特征', 'AB测试'],
      'estimatedMinutes': 60,
    },
    {
      'id': 'distributed_cache',
      'title': '分布式缓存',
      'category': '基础设施',
      'difficulty': 3,
      'description': '设计一个分布式缓存系统',
      'keyPoints': ['一致性哈希', '缓存穿透', '缓存雪崩', '数据同步'],
      'estimatedMinutes': 45,
    },
    {
      'id': 'message_queue',
      'title': '消息队列',
      'category': '基础设施',
      'difficulty': 4,
      'description': '设计一个高可用的消息队列系统',
      'keyPoints': ['持久化', '消费确认', '顺序消息', '死信队列'],
      'estimatedMinutes': 60,
    },
    {
      'id': 'rate_limiter',
      'title': '限流系统',
      'category': '基础设施',
      'difficulty': 2,
      'description': '设计一个API限流系统',
      'keyPoints': ['令牌桶', '滑动窗口', '分布式限流', '降级策略'],
      'estimatedMinutes': 30,
    },
    {
      'id': 'task_scheduler',
      'title': '任务调度系统',
      'category': '基础设施',
      'difficulty': 3,
      'description': '设计一个分布式任务调度系统',
      'keyPoints': ['定时任务', '任务依赖', '失败重试', '负载均衡'],
      'estimatedMinutes': 45,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredTopics = _selectedCategory == 'all'
        ? _designTopics
        : _designTopics.where((t) => t['category'] == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('系统设计练习'),
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
          _buildStatsHeader(context, isDark),
          
          // 分类筛选
          _buildCategoryFilter(context, isDark),
          
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

  Widget _buildStatsHeader(BuildContext context, bool isDark) {
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
          _buildStatItem('总题数', '${_designTopics.length}', AppColors.accent),
          _buildStatItem('已练习', '${_savedDesigns.length}', AppColors.success),
          _buildStatItem('待练习', '${_designTopics.length - _savedDesigns.length}', AppColors.warning),
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

  Widget _buildCategoryFilter(BuildContext context, bool isDark) {
    final categories = ['all', '基础', '社交', '通讯', '搜索', '金融', 'AI', '基础设施'];
    
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
              label: Text(cat == 'all' ? '全部' : cat),
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
    final difficultyLabels = {1: '入门', 2: '基础', 3: '中等', 4: '较难', 5: '困难'};
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
                      difficultyLabels[difficulty] ?? '未知',
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
                    '预计 ${topic['estimatedMinutes']} 分钟',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : const Color(0xFF999999),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _startDesignPractice(context, topic),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('开始练习'),
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
          _buildDesignStep('1. 需求澄清', [
            '确认功能范围和非功能需求',
            '明确用户规模和流量预估',
            '确定数据一致性要求',
            '识别核心功能和次要功能',
          ]),
          _buildDesignStep('2. 容量估算', [
            '日活用户数（DAU）',
            '每用户每日请求数（QPS）',
            '存储容量估算',
            '带宽需求估算',
          ]),
          _buildDesignStep('3. 系统架构', [
            '整体架构图设计',
            '核心组件划分',
            '数据流向设计',
            '接口设计',
          ]),
          _buildDesignStep('4. 数据存储', [
            '数据库选型（SQL/NoSQL）',
            '表结构设计',
            '索引设计',
            '分库分表策略',
          ]),
          _buildDesignStep('5. 核心设计', [
            '关键业务流程',
            '并发处理方案',
            '缓存策略',
            '消息队列使用',
          ]),
          _buildDesignStep('6. 扩展优化', [
            '性能瓶颈分析',
            '可扩展性设计',
            '高可用方案',
            '监控告警',
          ]),
          const SizedBox(height: 20),
          
          // 开始练习按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('关闭'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    // TODO: 进入AI对话练习
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('开始练习：${topic['title']}')),
                    );
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始练习'),
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
        title: const Text('系统设计面试指南'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('面试流程', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('1. 需求澄清（5分钟）'),
              Text('2. 容量估算（5分钟）'),
              Text('3. 系统架构（15分钟）'),
              Text('4. 核心设计（15分钟）'),
              Text('5. 扩展优化（10分钟）'),
              SizedBox(height: 16),
              Text('评分维度', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('• 问题分析能力'),
              Text('• 架构设计能力'),
              Text('• 技术深度'),
              Text('• 沟通表达能力'),
              SizedBox(height: 16),
              Text('注意事项', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('• 先确认需求再设计方案'),
              Text('• 从高层设计逐步深入'),
              Text('• 主动讨论 trade-off'),
              Text('• 考虑边界情况和异常处理'),
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
