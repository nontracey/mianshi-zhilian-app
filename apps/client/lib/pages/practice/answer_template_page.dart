import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class AnswerTemplatePage extends StatelessWidget {
  const AnswerTemplatePage({
    super.key,
    required this.topicTitle,
    required this.question,
    this.onSelectTemplate,
  });

  final String topicTitle;
  final String question;
  final ValueChanged<String>? onSelectTemplate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回答模板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showTemplateGuide(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 问题卡片
          _QuestionCard(topicTitle: topicTitle, question: question),
          const SizedBox(height: 16),
          
          // 模板说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '选择适合面试场景的回答模板，可以帮你组织回答结构',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // 简短版模板
          _TemplateCard(
            title: '简短版',
            subtitle: '适合电话面试、快速回答',
            icon: Icons.short_text,
            color: const Color(0xFF10B981),
            duration: '30秒 - 1分钟',
            structure: [
              _TemplateSection(name: '核心定义', description: '一句话解释概念'),
              _TemplateSection(name: '关键特点', description: '2-3个核心要点'),
              _TemplateSection(name: '应用场景', description: '1个实际例子'),
            ],
            example: _getShortExample(),
            onSelect: () => onSelectTemplate?.call('short'),
          ),
          const SizedBox(height: 12),
          
          // 标准版模板
          _TemplateCard(
            title: '标准版',
            subtitle: '适合大多数技术面试',
            icon: Icons.article_outlined,
            color: AppColors.accent,
            duration: '2-3分钟',
            structure: [
              _TemplateSection(name: '概念定义', description: '清晰解释是什么'),
              _TemplateSection(name: '核心原理', description: '工作原理和机制'),
              _TemplateSection(name: '特点对比', description: '优缺点或与其他方案对比'),
              _TemplateSection(name: '实际应用', description: '项目中的使用场景'),
              _TemplateSection(name: '注意事项', description: '常见坑点和最佳实践'),
            ],
            example: _getStandardExample(),
            onSelect: () => onSelectTemplate?.call('standard'),
          ),
          const SizedBox(height: 12),
          
          // 深入版模板
          _TemplateCard(
            title: '深入版',
            subtitle: '适合深入探讨、高级岗位',
            icon: Icons.psychology_outlined,
            color: const Color(0xFF8B5CF6),
            duration: '3-5分钟',
            structure: [
              _TemplateSection(name: '概念定义', description: '清晰解释是什么'),
              _TemplateSection(name: '底层原理', description: '深入工作原理'),
              _TemplateSection(name: '源码分析', description: '关键实现细节'),
              _TemplateSection(name: '性能分析', description: '时间/空间复杂度'),
              _TemplateSection(name: '设计模式', description: '涉及的设计思想'),
              _TemplateSection(name: '实际案例', description: '项目中的应用'),
              _TemplateSection(name: '扩展思考', description: '相关技术延伸'),
            ],
            example: _getDeepExample(),
            onSelect: () => onSelectTemplate?.call('deep'),
          ),
          const SizedBox(height: 20),
          
          // 使用技巧
          _buildTipsSection(context),
        ],
      ),
    );
  }

  void _showTemplateGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('模板使用指南'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. 选择合适的模板', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('根据面试场景和问题深度选择模板'),
              SizedBox(height: 12),
              Text('2. 个性化调整', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('模板只是框架，需要根据具体问题填充内容'),
              SizedBox(height: 12),
              Text('3. 结合实际经验', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('用项目中的真实案例来支撑你的回答'),
              SizedBox(height: 12),
              Text('4. 练习表达', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('不仅要记住内容，还要练习流畅表达'),
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

  Widget _buildTipsSection(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '回答技巧',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            _buildTipItem('STAR法则', 'Situation-Task-Action-Result，适合行为面试题'),
            _buildTipItem('对比分析', '与其他方案对比，展示你的技术广度'),
            _buildTipItem('实际案例', '用项目经验支撑，增加可信度'),
            _buildTipItem('深入原理', '展示你对底层实现的理解'),
            _buildTipItem('总结升华', '最后总结要点，给面试官留下深刻印象'),
          ],
        ),
      ),
    );
  }

  Widget _buildTipItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getShortExample() {
    return '''Q: 什么是 HashMap？

A: HashMap 是一种基于哈希表实现的键值对数据结构。

核心特点：
• O(1) 的平均查找和插入时间复杂度
• 允许 null 键和值
• 非线程安全

典型应用：缓存实现、配置存储、快速查找场景。''';
  }

  String _getStandardExample() {
    return '''Q: 什么是 HashMap？

A: HashMap 是 Java 中基于哈希表实现的 Map 接口，用于存储键值对。

核心原理：
通过 key 的 hashCode() 计算桶位置，使用数组+链表/红黑树存储。JDK 8 后，链表长度超过 8 会转为红黑树。

特点对比：
• 与 Hashtable 相比：非线程安全但性能更高
• 与 LinkedHashMap 相比：无序但查询更快
• 与 TreeMap 相比：无序但 O(1) vs O(log n)

实际应用：
在项目中用于缓存用户会话信息，配合 LRU 策略管理缓存大小。

注意事项：
• 需要正确实现 hashCode() 和 equals()
• 多线程环境使用 ConcurrentHashMap
• 合理设置初始容量避免频繁扩容''';
  }

  String _getDeepExample() {
    return '''Q: 什么是 HashMap？

A: HashMap 是 Java 集合框架中最常用的数据结构之一，基于哈希表实现。

底层原理：
1. 数组+链表+红黑树结构
2. 通过扰动函数减少碰撞：(h = key.hashCode()) ^ (h >>> 16)
3. 容量始终为 2 的幂，用位运算替代取模

源码分析：
• put 流程：计算 hash → 定位桶 → 判断是否为空 → 链表/树插入 → 扩容检查
• 扩容机制：负载因子 0.75，容量翻倍，rehash 优化

性能分析：
• 时间复杂度：O(1) 平均，O(n) 最坏（退化为链表）
• 空间复杂度：O(n)

设计模式：
• 懒加载：首次 put 时初始化数组
• 策略模式：链表和红黑树的切换

实际案例：
在分布式缓存中，使用 ConcurrentHashMap 实现本地缓存，配合过期策略。

扩展思考：
• 与 HashMap 的变体：WeakHashMap、EnumMap
• 并发方案：ConcurrentHashMap 的分段锁和 CAS
• 其他语言实现：Python dict、Go map''';
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.topicTitle,
    required this.question,
  });

  final String topicTitle;
  final String question;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '问题',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    topicTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              question,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateSection {
  final String name;
  final String description;

  const _TemplateSection({
    required this.name,
    required this.description,
  });
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.duration,
    required this.structure,
    required this.example,
    this.onSelect,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String duration;
  final List<_TemplateSection> structure;
  final String example;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                duration,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.expand_more, color: Colors.grey.shade400),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 结构说明
                const Text(
                  '回答结构',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                ...structure.asMap().entries.map((entry) {
                  final index = entry.key;
                  final section = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                section.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                section.description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                
                // 示例
                Row(
                  children: [
                    const Text(
                      '示例回答',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: example));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制示例')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    example,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // 使用按钮
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onSelect,
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('使用此模板'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
