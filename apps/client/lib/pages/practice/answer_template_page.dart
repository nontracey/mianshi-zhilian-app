import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
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
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('回答模板')),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showTemplateGuide(context, l10n),
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
                    l10n.get('选择适合面试场景的回答模板，可以帮你组织回答结构'),
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
            title: l10n.get('简短版'),
            subtitle: l10n.get('适合电话面试、快速回答'),
            icon: Icons.short_text,
            color: const Color(0xFF10B981),
            duration: l10n.get('30秒 - 1分钟'),
            structure: [
              _TemplateSection(nameKey: '核心定义', descKey: '一句话解释概念'),
              _TemplateSection(nameKey: '关键特点', descKey: '2_3个核心要点'),
              _TemplateSection(nameKey: '应用场景', descKey: '1个实际例子'),
            ],
            example: _getShortExample(l10n),
            onSelect: () => onSelectTemplate?.call('short'),
          ),
          const SizedBox(height: 12),
          
          // 标准版模板
          _TemplateCard(
            title: l10n.get('标准版'),
            subtitle: l10n.get('适合大多数技术面试'),
            icon: Icons.article_outlined,
            color: AppColors.accent,
            duration: l10n.get('2-3分钟'),
            structure: [
              _TemplateSection(nameKey: '概念定义', descKey: '清晰解释是什么'),
              _TemplateSection(nameKey: '核心原理', descKey: '工作原理和机制'),
              _TemplateSection(nameKey: '特点对比', descKey: '优缺点或与其他方案对比'),
              _TemplateSection(nameKey: '实际应用', descKey: '项目中的使用场景'),
              _TemplateSection(nameKey: '注意事项', descKey: '常见坑点和最佳实践'),
            ],
            example: _getStandardExample(l10n),
            onSelect: () => onSelectTemplate?.call('standard'),
          ),
          const SizedBox(height: 12),

          // 深入版模板
          _TemplateCard(
            title: l10n.get('深入版'),
            subtitle: l10n.get('适合深入探讨、高级岗位'),
            icon: Icons.psychology_outlined,
            color: const Color(0xFF8B5CF6),
            duration: l10n.get('3-5分钟'),
            structure: [
              _TemplateSection(nameKey: '概念定义', descKey: '清晰解释是什么'),
              _TemplateSection(nameKey: '底层原理', descKey: '深入工作原理'),
              _TemplateSection(nameKey: '源码分析', descKey: '关键实现细节'),
              _TemplateSection(nameKey: '性能分析', descKey: '时间_空间复杂度'),
              _TemplateSection(nameKey: '设计模式', descKey: '涉及的设计思想'),
              _TemplateSection(nameKey: '实际案例', descKey: '项目中的应用'),
              _TemplateSection(nameKey: '扩展思考', descKey: '相关技术延伸'),
            ],
            example: _getDeepExample(l10n),
            onSelect: () => onSelectTemplate?.call('deep'),
          ),
          const SizedBox(height: 20),

          // 使用技巧
          _buildTipsSection(context, l10n),
        ],
      ),
    );
  }

  void _showTemplateGuide(BuildContext context, LocalizationProvider l10n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('模板使用指南')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.get('1. 选择合适的模板'), style: TextStyle(fontWeight: FontWeight.w600)),
              Text(l10n.get('根据面试场景和问题深度选择模板')),
              SizedBox(height: 12),
              Text(l10n.get('2. 个性化调整'), style: TextStyle(fontWeight: FontWeight.w600)),
              Text(l10n.get('模板只是框架，需要根据具体问题填充内容')),
              SizedBox(height: 12),
              Text(l10n.get('3. 结合实际经验'), style: TextStyle(fontWeight: FontWeight.w600)),
              Text(l10n.get('用项目中的真实案例来支撑你的回答')),
              SizedBox(height: 12),
              Text(l10n.get('4. 练习表达'), style: TextStyle(fontWeight: FontWeight.w600)),
              Text(l10n.get('不仅要记住内容，还要练习流畅表达')),
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

  Widget _buildTipsSection(BuildContext context, LocalizationProvider l10n) {
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
            Text(
              l10n.get('回答技巧'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            _buildTipItem(l10n.get('STAR法则'), l10n.get('STAR法则描述')),
            _buildTipItem(l10n.get('对比分析'), l10n.get('与其他方案对比')),
            _buildTipItem(l10n.get('实际案例'), l10n.get('用项目经验支撑')),
            _buildTipItem(l10n.get('深入原理'), l10n.get('展示底层理解')),
            _buildTipItem(l10n.get('总结升华'), l10n.get('最后总结要点')),
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

  String _getShortExample(LocalizationProvider l10n) {
    return l10n.get('template_short_example');
  }

  String _getStandardExample(LocalizationProvider l10n) {
    return l10n.get('template_standard_example');
  }

  String _getDeepExample(LocalizationProvider l10n) {
    return l10n.get('template_deep_example');
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
    final l10n = context.watch<LocalizationProvider>();
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
                  child: Text(
                    l10n.get('问题'),
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
  final String nameKey;
  final String descKey;

  const _TemplateSection({
    required this.nameKey,
    required this.descKey,
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
    final l10n = context.watch<LocalizationProvider>();
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
                Text(
                  l10n.get('回答结构'),
                  style: const TextStyle(
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
                                l10n.get(section.nameKey),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                l10n.get(section.descKey),
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
                    Text(
                      l10n.get('示例回答'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: example));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.get('已复制示例'))),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 14),
                      label: Text(l10n.get('复制'), style: const TextStyle(fontSize: 11)),
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
                    child: Text(l10n.get('使用此模板')),
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
