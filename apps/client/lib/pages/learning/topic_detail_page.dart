import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/widgets/score_badge.dart';
import 'package:mianshi_zhilian/widgets/voice_input_button.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.topic,
    required this.onBack,
    this.initialTabIndex = 0,
  });

  final Topic topic;
  final VoidCallback onBack;
  final int initialTabIndex;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _answerController = TextEditingController();
  bool _isEvaluating = false;
  Map<String, dynamic>? _evaluationResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1100;

    // 桌面端：三栏布局（左侧目录 + 中间知识 + 右侧复述）
    if (isDesktop) {
      return _buildDesktopLayout(context, topic);
    }
    // 移动端/平板：原有 TabBar 布局
    return _buildMobileLayout(context, topic);
  }

  Widget _buildDesktopLayout(BuildContext context, Topic topic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部导航
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  topic.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        _TopicHeader(topic: topic),
        const SizedBox(height: 8),
        // 三栏内容
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：目录与前置知识
              SizedBox(
                width: 240,
                child: _LeftSidebar(topic: topic),
              ),
              const VerticalDivider(width: 1),
              // 中间：知识卡片流
              Expanded(
                flex: 3,
                child: _KnowledgeTab(topic: topic),
              ),
              const VerticalDivider(width: 1),
              // 右侧：复述与 AI 评估
              SizedBox(
                width: 380,
                child: _RecallTab(
                  topic: topic,
                  answerController: _answerController,
                  isEvaluating: _isEvaluating,
                  evaluationResult: _evaluationResult,
                  onEvaluate: _handleEvaluate,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, Topic topic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部导航
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  topic.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              // 右侧快捷操作
              FilledButton.tonalIcon(
                onPressed: () => _tabController.animateTo(1),
                icon: const Icon(Icons.record_voice_over_outlined),
                label: const Text('开始复述'),
              ),
            ],
          ),
        ),
        // 标签信息
        _TopicHeader(topic: topic),
        const SizedBox(height: 8),
        // Tab 栏
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '知识学习'),
            Tab(text: '复述练习'),
          ],
        ),
        const SizedBox(height: 16),
        // Tab 内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _KnowledgeTab(topic: topic),
              _RecallTab(
                topic: topic,
                answerController: _answerController,
                isEvaluating: _isEvaluating,
                evaluationResult: _evaluationResult,
                onEvaluate: _handleEvaluate,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleEvaluate() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入你的回答')));
      return;
    }

    final aiProvider = context.read<AiProvider>();
    if (aiProvider.defaultConfig == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在个人中心配置 AI')));
      return;
    }

    setState(() => _isEvaluating = true);

    try {
      final topic = widget.topic;
      final result = await aiProvider.evaluateAnswer(
        topicId: topic.id,
        question: topic.recallPrompts.isNotEmpty
            ? topic.recallPrompts.first.prompt
            : topic.title,
        userAnswer: answer,
        rubric: topic.rubric,
      );

      if (mounted) {
        setState(() => _evaluationResult = result);
        final progressProvider = context.read<ProgressProvider>();
        final score = result['score'] as int? ?? 0;
        await progressProvider.updateTopicProgress(topic.id, score: score);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI 评估失败：$e'),
            action: SnackBarAction(label: '重试', onPressed: _handleEvaluate),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }
}

// ── 桌面端左侧目录栏 ─────────────────────────────────────────

class _LeftSidebar extends StatelessWidget {
  const _LeftSidebar({required this.topic});
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 面试官关注点（突出显示）
        if (topic.interviewerFocus != null &&
            topic.interviewerFocus!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.visibility_outlined, size: 14, color: AppColors.accent),
                    SizedBox(width: 6),
                    Text(
                      '面试官关注点',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  topic.interviewerFocus!,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // 知识卡片目录
        Text(
          '知识目录',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...topic.learningCards.asMap().entries.map((entry) {
          final card = entry.value;
          final typeIcons = {
            'explain': Icons.article_outlined,
            'interviewAnswer': Icons.auto_awesome,
            'interview': Icons.auto_awesome,
            'checklist': Icons.checklist,
            'code': Icons.code,
            'animation': Icons.animation,
            'diagram': Icons.schema_outlined,
            'svg': Icons.draw_outlined,
            'table': Icons.table_chart_outlined,
            'compareTable': Icons.compare_arrows,
          };
          final icon = typeIcons[card.type] ?? Icons.description_outlined;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(icon, size: 16, color: AppColors.accent),
              title: Text(
                card.title,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              minLeadingWidth: 24,
            ),
          );
        }),
        // 前置知识
        if (topic.prerequisites.isNotEmpty) ...[
          const Divider(height: 24),
          Text(
            '前置知识',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...topic.prerequisites.map((prereq) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.arrow_right, size: 16, color: AppColors.warning),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    prereq,
                    style: const TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ),
              ],
            ),
          )),
        ],
        // LeetCode 链接
        if (topic.leetcodeUrl != null && topic.leetcodeUrl!.isNotEmpty) ...[
          const Divider(height: 24),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.code, size: 16, color: AppColors.success),
            title: const Text('LeetCode 练习', style: TextStyle(fontSize: 13)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            minLeadingWidth: 24,
          ),
        ],
      ],
    );
  }
}

// ── 顶部标签信息 ──────────────────────────────────────────────

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final difficultyLabel = switch (topic.difficulty) {
      1 => '入门',
      2 => '基础',
      3 => '中等',
      4 => '较难',
      5 => '困难',
      _ => '未知',
    };

    final difficultyColor = switch (topic.difficulty) {
      1 => AppColors.success,
      2 => AppColors.accent,
      3 => AppColors.warning,
      4 || 5 => AppColors.danger,
      _ => Colors.grey,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...topic.tags.map(
            (tag) => Chip(
              label: Text(tag, style: const TextStyle(fontSize: 12)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          Chip(
            label: Text(
              difficultyLabel,
              style: TextStyle(fontSize: 12, color: difficultyColor),
            ),
            avatar: Icon(
              Icons.signal_cellular_alt,
              size: 14,
              color: difficultyColor,
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Chip(
            label: Text(
              '${topic.estimatedMinutes} 分钟',
              style: const TextStyle(fontSize: 12),
            ),
            avatar: const Icon(Icons.timer_outlined, size: 14),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          if (topic.highFrequency)
            Chip(
              label: Text(
                topic.interviewFrequencyLabel ?? '高频',
                style: TextStyle(
                  fontSize: 12,
                  color: topic.interviewFrequency == 'medium'
                      ? AppColors.warning
                      : topic.interviewFrequency == 'low'
                      ? Colors.grey
                      : AppColors.danger,
                ),
              ),
              avatar: Icon(
                Icons.local_fire_department,
                size: 14,
                color: topic.interviewFrequency == 'medium'
                    ? AppColors.warning
                    : topic.interviewFrequency == 'low'
                    ? Colors.grey
                    : AppColors.danger,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

// ── 知识学习 Tab ──────────────────────────────────────────────

class _KnowledgeTab extends StatelessWidget {
  const _KnowledgeTab({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        // 面试官关注点
        if (topic.interviewerFocus != null &&
            topic.interviewerFocus!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '面试官关注点',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        topic.interviewerFocus!,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // 知识卡片：按类型分别渲染
        ...topic.learningCards.map(
          (card) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildCard(context, card),
          ),
        ),
        // 评分标准（Rubric）
        if (topic.rubric != null) ...[
          const SizedBox(height: 8),
          _RubricSection(rubric: topic.rubric!),
        ],
        // 常见追问（FollowUp）
        if (topic.followUps.isNotEmpty) ...[
          const SizedBox(height: 8),
          _FollowUpSection(followUps: topic.followUps),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCard(BuildContext context, LearningCard card) {
    return switch (card.type) {
      'explain' => _ExplainCard(card: card),
      'interviewAnswer' => _InterviewAnswerCard(card: card),
      'interview' => _InterviewAnswerCard(card: card),
      'checklist' => _ChecklistCard(card: card),
      'code' => _CodeCard(card: card),
      'animation' => _DiagramCard(card: card),
      'diagram' => _DiagramCard(card: card),
      'svg' => _SvgDiagramCard(card: card),
      'table' => _TableCard(card: card),
      'compareTable' => _TableCard(card: card),
      _ => _GenericCard(card: card),
    };
  }
}

// ── 核心概念卡片（Markdown 渲染）──────────────────────────────

class _ExplainCard extends StatelessWidget {
  const _ExplainCard({required this.card});
  final LearningCard card;

  String _formatContent(String content) {
    // 处理内容格式，确保 Markdown 正确渲染
    String formatted = content;

    // 处理可能的转义换行符
    formatted = formatted.replaceAll('\\n', '\n');

    // 识别裸代码块（没有被 ``` 包裹的代码）
    final lines = formatted.split('\n');
    final buffer = StringBuffer();
    bool inFencedCodeBlock = false; // 已有 ``` 包裹的代码块
    bool inBareCodeBlock = false; // 自动识别的裸代码块

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // 处理已有的 ``` 代码块
      if (trimmed.startsWith('```')) {
        if (inFencedCodeBlock) {
          // 结束代码块
          buffer.writeln(line);
          inFencedCodeBlock = false;
        } else {
          // 如果正在裸代码块中，先关闭
          if (inBareCodeBlock) {
            buffer.writeln('```');
            inBareCodeBlock = false;
          }
          // 开始代码块
          buffer.writeln(line);
          inFencedCodeBlock = true;
        }
        continue;
      }

      // 在已有的代码块中，直接保留内容
      if (inFencedCodeBlock) {
        buffer.writeln(line);
        continue;
      }

      // 空行处理
      if (trimmed.isEmpty) {
        // 空行关闭裸代码块
        if (inBareCodeBlock) {
          buffer.writeln('```');
          buffer.writeln();
          inBareCodeBlock = false;
        }
        buffer.writeln(line);
        continue;
      }

      // 检测是否是 Markdown 格式行（优先级最高）
      if (_isMarkdownLine(trimmed)) {
        // 如果正在裸代码块中，先关闭
        if (inBareCodeBlock) {
          buffer.writeln('```');
          buffer.writeln();
          inBareCodeBlock = false;
        }
        buffer.writeln(line);
        continue;
      }

      // 检测是否是代码行
      if (_isCodeLine(trimmed)) {
        // 开始裸代码块
        if (!inBareCodeBlock) {
          buffer.writeln('```java');
          inBareCodeBlock = true;
        }
        buffer.writeln(line);
        continue;
      }

      // 其他情况（普通文本）
      if (inBareCodeBlock) {
        buffer.writeln('```');
        buffer.writeln();
        inBareCodeBlock = false;
      }
      buffer.writeln(line);
    }

    // 关闭未关闭的代码块
    if (inBareCodeBlock) {
      buffer.writeln('```');
    }

    return buffer.toString();
  }

  /// 检测是否是 Markdown 格式行（这些一定不是代码）
  bool _isMarkdownLine(String trimmed) {
    if (trimmed.isEmpty) return false;

    // 标题：# ## ### #### ##### ######
    if (RegExp(r'^#{1,6}\s').hasMatch(trimmed)) return true;

    // 无序列表：- item 或 * item
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) return true;

    // 有序列表：1. item
    if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) return true;

    // 引用：> quote
    if (trimmed.startsWith('>')) return true;

    // 表格行：| col1 | col2 |
    if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.length > 2)
      return true;

    // 表格分隔行：| --- | --- |
    if (RegExp(r'^\|[\s\-:|]+\|$').hasMatch(trimmed)) return true;

    // 分隔线：--- 或 *** 或 ___
    if (RegExp(r'^[-*_]{3,}\s*$').hasMatch(trimmed)) return true;

    // 粗体开头：**text**
    if (trimmed.startsWith('**') && trimmed.contains('**')) return true;

    // 斜体开头：*text*（但不是列表）
    if (trimmed.startsWith('*') &&
        !trimmed.startsWith('* ') &&
        trimmed.endsWith('*') &&
        trimmed.length > 2)
      return true;

    // 链接：[text](url)
    if (RegExp(r'^\[.*\]\(.*\)').hasMatch(trimmed)) return true;

    // 图片：![alt](url)
    if (trimmed.startsWith('![')) return true;

    return false;
  }

  /// 检测是否是代码行（这些可能是裸代码）
  bool _isCodeLine(String trimmed) {
    if (trimmed.isEmpty) return false;

    // 单行注释
    if (trimmed.startsWith('//')) return true;

    // 多行注释开始或结束
    if (trimmed.startsWith('/*') ||
        trimmed.startsWith('*') && trimmed.endsWith('*/'))
      return true;

    // Java 关键字开头（严格匹配）
    if (RegExp(
      r'^(?:public|private|protected|static|final|abstract|class|interface|enum|import|package)\s',
    ).hasMatch(trimmed))
      return true;

    // 控制流关键字
    if (RegExp(
      r'^(?:if|else|for|while|try|catch|finally|switch|case|default|return|throw|throws|new|assert)\b',
    ).hasMatch(trimmed))
      return true;

    // 类型声明
    if (RegExp(
      r'^(?:void|int|long|double|float|boolean|char|byte|short|String|Object|List|Map|Set)\s+\w+',
    ).hasMatch(trimmed))
      return true;

    // 行尾有分号（代码特征）
    if (trimmed.endsWith(';') && !trimmed.startsWith('|')) return true;

    // 花括号单独成行
    if (trimmed == '{' || trimmed == '}' || trimmed == '};') return true;

    // 赋值语句：Type var = value;
    if (RegExp(r'^\w+\s+\w+\s*=\s*').hasMatch(trimmed) && trimmed.endsWith(';'))
      return true;

    // 方法调用：object.method();
    if (RegExp(r'^\w+[\.\[]\w+.*\)\s*;?\s*$').hasMatch(trimmed) &&
        !trimmed.startsWith('|'))
      return true;

    // new 关键字
    if (RegExp(r'^\w+\s+\w+\s*=\s*new\s').hasMatch(trimmed)) return true;

    // 注解：@Override, @Autowired 等
    if (trimmed.startsWith('@')) return true;

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final formattedContent = _formatContent(card.content);

    return WorkPanel(
      title: card.title,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _MarkdownContent(data: formattedContent),
        ),
      ],
    );
  }
}

// ── 面试回答模板卡片（深色背景）──────────────────────────────

class _InterviewAnswerCard extends StatelessWidget {
  const _InterviewAnswerCard({required this.card});
  final LearningCard card;

  String _formatInterviewContent(String content) {
    // 处理面试回答内容格式
    String formatted = content;

    // 处理可能的转义换行符
    formatted = formatted.replaceAll('\\n', '\n');

    // 如果内容包含数字列表，确保格式正确
    // 例如 "1. xxx\n2. xxx" 格式
    final lines = formatted.split('\n');
    final buffer = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        // 检测是否是列表项
        if (RegExp(r'^\d+\.\s').hasMatch(line)) {
          buffer.writeln(line);
        } else if (line.startsWith('- ') || line.startsWith('* ')) {
          buffer.writeln(line);
        } else {
          buffer.writeln(line);
        }
      } else {
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final formattedContent = _formatInterviewContent(card.content);

    return WorkPanel(
      title: card.title,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '面试回答框架',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DefaultTextStyle(
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 14,
                  height: 1.7,
                ),
                child: _MarkdownContent(data: formattedContent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Checklist 卡片（勾选项）────────────────────────────────────

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.card});
  final LearningCard card;

  @override
  Widget build(BuildContext context) {
    final items = card.items.isNotEmpty ? card.items : [card.content];
    return WorkPanel(
      title: card.title,
      children: [
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.accent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 12,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item, style: const TextStyle(height: 1.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 代码卡片（深色代码块 + 语法高亮）─────────────────────────

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.card});
  final LearningCard card;

  ({String language, String code, bool isDiagram}) _parseCodeContent(
    String content,
  ) {
    String cleaned = content.trim();
    // 优先使用数据中显式指定的 language 字段
    String language = card.language ?? 'java';

    // 检测并移除 ``` 标记
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
      // 提取语言标识（仅当没有显式指定 language 时才覆盖）
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline != -1) {
        final langCandidate = cleaned.substring(0, firstNewline).trim();
        if (langCandidate.isNotEmpty &&
            !langCandidate.contains(' ') &&
            card.language == null) {
          language = langCandidate;
        }
        cleaned = cleaned.substring(firstNewline + 1);
      }
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }

    cleaned = cleaned.trim();

    // 检测是否是文字图形（ASCII 艺术、结构图等）
    final isDiagram = _isAsciiDiagram(cleaned);

    // 自动检测语言（仅当没有显式指定且默认为 java 时尝试检测）
    if (!isDiagram &&
        card.language == null &&
        language == 'java' &&
        !cleaned.contains('class ') &&
        !cleaned.contains('public ')) {
      if (cleaned.contains('def ') ||
          (cleaned.contains('import ') && cleaned.contains('self'))) {
        language = 'python';
      } else if (cleaned.contains('function ') ||
          cleaned.contains('const ') ||
          cleaned.contains('let ')) {
        language = 'javascript';
      } else if (cleaned.contains('fn ') || cleaned.contains('let mut ')) {
        language = 'rust';
      }
    }

    return (language: language, code: cleaned, isDiagram: isDiagram);
  }

  bool _isAsciiDiagram(String content) {
    if (content.isEmpty) return false;

    final lines = content.split('\n');
    int diagramScore = 0;

    for (final line in lines) {
      // 检测箭头符号（流程指示）
      if (line.contains('→') ||
          line.contains('←') ||
          line.contains('↑') ||
          line.contains('↓') ||
          line.contains('->') ||
          line.contains('<-') ||
          line.contains('=>') ||
          line.contains('<=') ||
          line.contains('┌') ||
          line.contains('┐') ||
          line.contains('└') ||
          line.contains('┘') ||
          line.contains('│') ||
          line.contains('─') ||
          line.contains('├') ||
          line.contains('┤')) {
        diagramScore += 2;
      }

      // 检测大量空格对齐（结构图特征）
      final leadingSpaces = line.length - line.trimLeft().length;
      if (leadingSpaces > 4 && line.trim().isNotEmpty) {
        diagramScore += 1;
      }

      // 检测 box-drawing 字符
      if (RegExp(r'[╔╗╚╝║═╠╣╦╩╬]').hasMatch(line)) {
        diagramScore += 3;
      }

      // 检测简单的 ASCII 图形字符
      if (line.contains('+--') ||
          line.contains('| ') ||
          line.contains('+-+') ||
          line.contains('[->') ||
          line.contains(']--') ||
          line.contains('-->')) {
        diagramScore += 2;
      }
    }

    // 如果得分超过阈值，认为是图形
    return diagramScore >= lines.length * 0.5 || diagramScore >= 4;
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseCodeContent(card.content);

    // 如果是文字图形，使用图解组件渲染
    if (parsed.isDiagram) {
      return WorkPanel(
        title: card.title,
        children: [_AsciiDiagramView(content: parsed.code)],
      );
    }

    // 否则使用代码高亮渲染
    return WorkPanel(
      title: card.title,
      children: [
        _HighlightedCode(code: parsed.code, language: parsed.language),
      ],
    );
  }
}

// ── ASCII 图形视图 ──────────────────────────────────────────

class _AsciiDiagramView extends StatelessWidget {
  const _AsciiDiagramView({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF07182A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 14,
            height: 1.6,
            color: Color(0xFFE7EEF8),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── 语法高亮代码组件 ─────────────────────────────────────────

class _HighlightedCode extends StatelessWidget {
  const _HighlightedCode({required this.code, this.language = 'java'});

  final String code;
  final String language;

  // 颜色方案：关键字、字符串、注释、数字等
  static const _keywordColor = Color(0xFFC792EA); // 紫色
  static const _stringColor = Color(0xFFC3E88D); // 绿色
  static const _commentColor = Color(0xFF546E7A); // 灰色
  static const _numberColor = Color(0xFFF78C6C); // 橙色
  static const _typeColor = Color(0xFF82AAFF); // 蓝色
  static const _functionColor = Color(0xFFEEFFFF); // 白色
  static const _defaultColor = Color(0xFFE7EEF8); // 默认色

  List<_CodeToken> _tokenize(String code) {
    final tokens = <_CodeToken>[];
    final keywords = {
      'abstract',
      'assert',
      'boolean',
      'break',
      'byte',
      'case',
      'catch',
      'char',
      'class',
      'const',
      'continue',
      'default',
      'do',
      'double',
      'else',
      'enum',
      'extends',
      'final',
      'finally',
      'float',
      'for',
      'goto',
      'if',
      'implements',
      'import',
      'instanceof',
      'int',
      'interface',
      'long',
      'native',
      'new',
      'package',
      'private',
      'protected',
      'public',
      'return',
      'short',
      'static',
      'strictfp',
      'super',
      'switch',
      'synchronized',
      'this',
      'throw',
      'throws',
      'transient',
      'try',
      'void',
      'volatile',
      'while',
      'true',
      'false',
      'null',
      'var',
      'record',
      'sealed',
      'permits',
      'yield',
      'with',
    };

    final typeKeywords = {
      'String',
      'Object',
      'List',
      'Map',
      'Set',
      'Collection',
      'Iterator',
      'Integer',
      'Long',
      'Double',
      'Float',
      'Boolean',
      'Character',
      'Byte',
      'Short',
      'Number',
      'Comparable',
      'Iterable',
      'Stream',
      'Optional',
      'ArrayList',
      'HashMap',
      'HashSet',
      'LinkedList',
      'TreeMap',
      'TreeSet',
      'ConcurrentHashMap',
      'CopyOnWriteArrayList',
      'ThreadPoolExecutor',
      'ExecutorService',
      'Future',
      'CompletableFuture',
      'Thread',
      'Runnable',
    };

    final buffer = StringBuffer();
    var i = 0;

    while (i < code.length) {
      // 单行注释
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '/') {
        if (buffer.isNotEmpty) {
          tokens.add(_CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final start = i;
        while (i < code.length && code[i] != '\n') {
          i++;
        }
        tokens.add(_CodeToken(code.substring(start, i), _commentColor));
        continue;
      }

      // 多行注释
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
        if (buffer.isNotEmpty) {
          tokens.add(_CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final start = i;
        i += 2;
        while (i + 1 < code.length && !(code[i] == '*' && code[i + 1] == '/')) {
          i++;
        }
        i += 2;
        tokens.add(_CodeToken(code.substring(start, i), _commentColor));
        continue;
      }

      // 字符串
      if (code[i] == '"' || code[i] == '\'') {
        if (buffer.isNotEmpty) {
          tokens.add(_CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final quote = code[i];
        final start = i;
        i++;
        while (i < code.length && code[i] != quote) {
          if (code[i] == '\\') i++; // 跳过转义字符
          i++;
        }
        i++; // 跳过结束引号
        tokens.add(_CodeToken(code.substring(start, i), _stringColor));
        continue;
      }

      // 数字
      if (RegExp(r'[0-9]').hasMatch(code[i])) {
        if (buffer.isNotEmpty) {
          tokens.add(_CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final start = i;
        while (i < code.length && RegExp(r'[0-9.xXa-fA-F]').hasMatch(code[i])) {
          i++;
        }
        tokens.add(_CodeToken(code.substring(start, i), _numberColor));
        continue;
      }

      // 标识符或关键字
      if (RegExp(r'[a-zA-Z_$]').hasMatch(code[i])) {
        if (buffer.isNotEmpty) {
          tokens.add(_CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final start = i;
        while (i < code.length && RegExp(r'[a-zA-Z0-9_$]').hasMatch(code[i])) {
          i++;
        }
        final word = code.substring(start, i);
        Color color;
        if (keywords.contains(word)) {
          color = _keywordColor;
        } else if (typeKeywords.contains(word)) {
          color = _typeColor;
        } else if (i < code.length && code[i] == '(') {
          color = _functionColor;
        } else {
          color = _defaultColor;
        }
        tokens.add(_CodeToken(word, color));
        continue;
      }

      // 其他字符
      buffer.write(code[i]);
      i++;
    }

    if (buffer.isNotEmpty) {
      tokens.add(_CodeToken(buffer.toString(), _defaultColor));
    }

    return tokens;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokenize(code);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 语言标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              language.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 代码内容
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText.rich(
              TextSpan(
                children: tokens
                    .map(
                      (token) => TextSpan(
                        text: token.text,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 13,
                          height: 1.6,
                          color: token.color,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeToken {
  final String text;
  final Color color;
  _CodeToken(this.text, this.color);
}

// ── 图解卡片（自动识别布局）─────────────────────────────────

class _DiagramCard extends StatelessWidget {
  const _DiagramCard({required this.card});
  final LearningCard card;

  @override
  Widget build(BuildContext context) {
    // 优先使用 SVG 资源：svgPath > asset > 智能图解
    final svgUrl = card.svgPath ?? card.asset;

    return WorkPanel(
      title: card.title,
      children: [
        if (svgUrl != null && svgUrl.isNotEmpty)
          // 有 SVG/图片资源时直接展示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF07182A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.32),
              ),
            ),
            child: svgUrl.endsWith('.svg')
                ? SvgPicture.network(
                    svgUrl,
                    width: double.infinity,
                    placeholderBuilder: (_) => Container(
                      height: 120,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorBuilder: (ctx, err, stack) => Text(
                      card.fallback ?? 'SVG 加载失败',
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  )
                : Image.network(
                    svgUrl,
                    width: double.infinity,
                    errorBuilder: (ctx, err, stack) => Text(
                      card.fallback ?? '图片加载失败',
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
          )
        else
          // 无资源时使用智能图解
          _SmartDiagram(card: card),
        if (card.content.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(card.content, style: const TextStyle(height: 1.6)),
        ],
      ],
    );
  }
}

// ── 智能图解组件（自动识别内容类型）──────────────────────────

class _SmartDiagram extends StatelessWidget {
  const _SmartDiagram({required this.card});
  final LearningCard card;

  // 识别图解类型（基于内容结构特征，不依赖特定关键词）
  _DiagramType _detectType() {
    final items = card.items;
    if (items.isEmpty) return _DiagramType.flow;

    // 分析内容结构特征
    final features = _analyzeFeatures(items);

    // 根据特征权重选择布局类型
    if (features.isCycle) return _DiagramType.cycle;
    if (features.isHierarchy) return _DiagramType.hierarchy;
    if (features.isCompare) return _DiagramType.compare;
    return _DiagramType.flow;
  }

  _ContentFeatures _analyzeFeatures(List<String> items) {
    int colonCount = 0; // 冒号分隔的键值对
    int arrowCount = 0; // 箭头符号
    int sequentialCount = 0; // 顺序词
    int compareCount = 0; // 对比词
    bool hasCycleIndicator = false;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final lower = item.toLowerCase();

      // 检测冒号分隔（键值对结构，表示分类/层级）
      if (item.contains('：') || item.contains(':')) {
        colonCount++;
      }

      // 检测箭头（流程指示）
      if (item.contains('→') || item.contains('->') || item.contains('=>')) {
        arrowCount++;
      }

      // 检测顺序词
      if (lower.contains('首先') ||
          lower.contains('然后') ||
          lower.contains('最后') ||
          lower.contains('接着') ||
          lower.contains('步骤') ||
          lower.contains('第') ||
          RegExp(r'^\d+[.、]').hasMatch(item)) {
        sequentialCount++;
      }

      // 检测对比词
      if (lower.contains('vs') ||
          lower.contains('对比') ||
          lower.contains('比较') ||
          lower.contains('区别') ||
          lower.contains('优缺') ||
          lower.contains('利弊')) {
        compareCount++;
      }

      // 检测循环指示（首尾相关）
      if (i == items.length - 1 && items.length >= 3) {
        final firstParts = items.first.split(RegExp(r'[：:、]'));
        final lastParts = item.split(RegExp(r'[：:、]'));
        if (firstParts.isNotEmpty && lastParts.isNotEmpty) {
          // 首尾有相似的关键词
          if (firstParts.first.contains(lastParts.first) ||
              lastParts.first.contains(firstParts.first)) {
            hasCycleIndicator = true;
          }
        }
      }
    }

    // 计算特征得分
    final totalItems = items.length;
    final colonRatio = colonCount / totalItems;
    final arrowRatio = arrowCount / totalItems;

    return _ContentFeatures(
      isHierarchy: colonRatio >= 0.5, // 超过一半是键值对 → 层级结构
      isCompare:
          compareCount >= 1 ||
          (totalItems >= 2 && totalItems % 2 == 0 && colonRatio >= 0.3),
      isCycle: hasCycleIndicator,
      isSequential: sequentialCount >= 2 || arrowRatio >= 0.3,
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = _detectType();
    final items = card.items;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF07182A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图解类型标签
          _buildTypeTag(type),
          const SizedBox(height: 16),
          // 根据类型渲染不同的布局
          switch (type) {
            _DiagramType.flow => _buildFlowLayout(items),
            _DiagramType.hierarchy => _buildHierarchyLayout(items),
            _DiagramType.compare => _buildCompareLayout(items),
            _DiagramType.cycle => _buildCycleLayout(items),
          },
          // fallback 提示
          if (card.fallback != null && card.fallback!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildFallbackHint(),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeTag(_DiagramType type) {
    final (icon, label, color) = switch (type) {
      _DiagramType.flow => (Icons.linear_scale, '流程图', AppColors.accent),
      _DiagramType.hierarchy => (Icons.account_tree, '结构图', AppColors.success),
      _DiagramType.compare => (Icons.compare_arrows, '对比图', AppColors.warning),
      _DiagramType.cycle => (Icons.autorenew, '循环图', const Color(0xFF8B5CF6)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // 流程图布局
  Widget _buildFlowLayout(List<String> items) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _buildFlowStep(i + 1, items[i]),
          if (i < items.length - 1) ...[
            const SizedBox(height: 8),
            Icon(
              Icons.arrow_downward,
              size: 20,
              color: AppColors.accent.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildFlowStep(int index, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.accent,
            child: Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // 层级/结构图布局
  Widget _buildHierarchyLayout(List<String> items) {
    // 解析层级关系
    final parsed = _parseHierarchy(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in parsed)
          Padding(
            padding: EdgeInsets.only(left: item.level * 20.0, bottom: 8),
            child: _buildHierarchyNode(item),
          ),
      ],
    );
  }

  List<_HierarchyItem> _parseHierarchy(List<String> items) {
    final result = <_HierarchyItem>[];

    for (final item in items) {
      int level = 0;
      String text = item;

      // 检测是否有层级标记（如 "定位：" 表示顶层，"输入：" 表示下一层）
      if (item.startsWith('定位') ||
          item.startsWith('概述') ||
          item.startsWith('总体')) {
        level = 0;
      } else if (item.startsWith('输入') ||
          item.startsWith('输出') ||
          item.startsWith('机制') ||
          item.startsWith('特点') ||
          item.startsWith('优点') ||
          item.startsWith('缺点')) {
        level = 1;
      } else if (item.startsWith('包含') ||
          item.startsWith('分为') ||
          item.startsWith('组成')) {
        level = 1;
      }

      result.add(_HierarchyItem(level: level, text: text));
    }

    return result;
  }

  Widget _buildHierarchyNode(_HierarchyItem item) {
    final colors = [
      AppColors.accent,
      AppColors.success,
      AppColors.warning,
      const Color(0xFF8B5CF6),
    ];
    final color = colors[item.level % colors.length];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.level > 0) ...[
            Icon(
              Icons.subdirectory_arrow_right,
              size: 16,
              color: color.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(
                color: Colors.white.withValues(
                  alpha: item.level == 0 ? 1.0 : 0.85,
                ),
                fontWeight: item.level == 0 ? FontWeight.w700 : FontWeight.w500,
                fontSize: item.level == 0 ? 14 : 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 对比图布局
  Widget _buildCompareLayout(List<String> items) {
    // 将 items 分成两列
    final half = (items.length / 2).ceil();
    final leftItems = items.sublist(0, half);
    final rightItems = items.sublist(half);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildCompareColumn('方案 A', leftItems, AppColors.accent),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildCompareColumn('方案 B', rightItems, AppColors.warning),
        ),
      ],
    );
  }

  Widget _buildCompareColumn(String title, List<String> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: color.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // 循环图布局
  Widget _buildCycleLayout(List<String> items) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _buildCycleStep(i + 1, items[i]),
          if (i < items.length - 1) ...[
            const SizedBox(height: 4),
            Icon(
              Icons.arrow_downward,
              size: 18,
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.6),
            ),
            const SizedBox(height: 4),
          ],
        ],
        // 循环回到起点的箭头
        if (items.length > 2) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.refresh, size: 18, color: const Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              Text(
                '循环执行',
                style: TextStyle(
                  color: const Color(0xFF8B5CF6),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCycleStep(int index, String text) {
    const color = Color(0xFF8B5CF6);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.accent.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              card.fallback!,
              style: const TextStyle(
                color: Color(0xFFBFD6EA),
                height: 1.5,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentFeatures {
  final bool isHierarchy;
  final bool isCompare;
  final bool isCycle;
  final bool isSequential;

  _ContentFeatures({
    required this.isHierarchy,
    required this.isCompare,
    required this.isCycle,
    required this.isSequential,
  });
}

enum _DiagramType { flow, hierarchy, compare, cycle }

class _HierarchyItem {
  final int level;
  final String text;
  _HierarchyItem({required this.level, required this.text});
}

// ── SVG 图解卡片 ─────────────────────────────────────────────

class _SvgDiagramCard extends StatelessWidget {
  const _SvgDiagramCard({required this.card});
  final LearningCard card;

  @override
  Widget build(BuildContext context) {
    // 优先使用内联 svg 字段，其次用 asset 字段
    final svgData = card.svg;
    final svgAsset = card.asset;

    return WorkPanel(
      title: card.title,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF07182A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
          ),
          child: Column(
            children: [
              if (svgData != null && svgData.isNotEmpty)
                // 内联 SVG 字符串
                SvgPicture.string(
                  svgData,
                  width: double.infinity,
                  placeholderBuilder: (_) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (svgAsset != null && svgAsset.isNotEmpty)
                // 远程 SVG URL 或本地 asset 路径
                SvgPicture.network(
                  svgAsset,
                  width: double.infinity,
                  placeholderBuilder: (_) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorBuilder: (ctx, err, stack) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.warning,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          card.fallback ?? 'SVG 加载失败',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // 降级：fallback 文本
                Container(
                  height: 120,
                  alignment: Alignment.center,
                  child: Text(
                    card.fallback ?? '暂无图解内容',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 补充说明文字
        if (card.content.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(card.content, style: const TextStyle(height: 1.6)),
        ],
      ],
    );
  }
}

// ── 追问区域（可折叠）────────────────────────────────────────

class _FollowUpSection extends StatelessWidget {
  const _FollowUpSection({required this.followUps});
  final List<FollowUpQuestion> followUps;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '常见追问',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${followUps.length} 题',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8B5CF6),
          ),
        ),
      ),
      children: [
        ...followUps.asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _FollowUpCard(index: entry.key + 1, question: entry.value),
          ),
        ),
      ],
    );
  }
}

class _FollowUpCard extends StatefulWidget {
  const _FollowUpCard({required this.index, required this.question});
  final int index;
  final FollowUpQuestion question;

  @override
  State<_FollowUpCard> createState() => _FollowUpCardState();
}

class _FollowUpCardState extends State<_FollowUpCard> {
  bool _expanded = false;

  Color get _difficultyColor {
    return switch (widget.question.difficulty) {
      1 => AppColors.success,
      2 => AppColors.accent,
      3 => AppColors.warning,
      4 || 5 => AppColors.danger,
      _ => Colors.grey,
    };
  }

  String get _difficultyLabel {
    return switch (widget.question.difficulty) {
      1 => '入门',
      2 => '基础',
      3 => '中等',
      4 => '较难',
      5 => '困难',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _expanded
            ? const Color(0xFF8B5CF6).withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _expanded
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
              : Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 问题行（可点击展开）
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 序号
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 问题文本
                  Expanded(
                    child: Text(
                      widget.question.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  // 难度标签
                  if (_difficultyLabel.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _difficultyColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _difficultyLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _difficultyColor,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // 展开/收起图标
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的答案区域
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // 提示要点
                  if (widget.question.hints.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.question.hints
                          .map(
                            (hint) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                hint,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 答案内容
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07182A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: Color(0xFF8B5CF6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '参考答案',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF8B5CF6),
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: widget.question.answer),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已复制到剪贴板'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DefaultTextStyle(
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 13,
                            height: 1.6,
                          ),
                          child: _MarkdownContent(data: widget.question.answer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ── 表格卡片 ─────────────────────────────────────────────────

class _TableCard extends StatelessWidget {
  const _TableCard({required this.card});
  final LearningCard card;

  String _formatTableContent(String content) {
    // 处理表格内容格式
    String formatted = content;

    // 处理可能的转义换行符
    formatted = formatted.replaceAll('\\n', '\n');

    // 确保表格格式正确
    final lines = formatted.split('\n');
    final buffer = StringBuffer();
    bool isFirstLine = true;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        // 检测是否是表格行
        if (line.startsWith('|') && line.endsWith('|')) {
          buffer.writeln(line);

          // 如果是第一行（表头），添加分隔行
          if (isFirstLine && !line.contains('---')) {
            // 计算列数
            final columns = line
                .split('|')
                .where((c) => c.trim().isNotEmpty)
                .length;
            buffer.writeln('| ${'--- | ' * (columns - 1)}--- |');
            isFirstLine = false;
          }
        } else {
          buffer.writeln(line);
        }
      } else {
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  /// 将 columns/rows 结构化数据转换为 Markdown 表格
  String _buildMarkdownFromStructured() {
    if (card.columns.isEmpty) return '';
    final buffer = StringBuffer();
    // 表头
    buffer.writeln('| ${card.columns.join(' | ')} |');
    buffer.writeln('| ${card.columns.map((_) => '---').join(' | ')} |');
    // 数据行
    for (final row in card.rows) {
      buffer.writeln('| ${row.join(' | ')} |');
    }
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    // 优先使用结构化的 columns/rows 数据，兜底用 content (Markdown)
    final formattedContent = card.columns.isNotEmpty
        ? _buildMarkdownFromStructured()
        : _formatTableContent(card.content);

    return WorkPanel(
      title: card.title,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 600),
            child: _MarkdownContent(data: formattedContent),
          ),
        ),
      ],
    );
  }
}

// ── 通用卡片 ─────────────────────────────────────────────────

class _GenericCard extends StatelessWidget {
  const _GenericCard({required this.card});
  final LearningCard card;

  bool _shouldUseMarkdown(String content) {
    // 检测是否应该使用 Markdown 渲染
    final trimmed = content.trim();

    // 包含 Markdown 语法
    if (trimmed.contains('# ') ||
        trimmed.contains('## ') ||
        trimmed.contains('### ') ||
        trimmed.contains('**') ||
        trimmed.contains('```') ||
        trimmed.contains('- ') ||
        trimmed.contains('* ') ||
        trimmed.contains('> ') ||
        RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
      return true;
    }

    // 包含表格
    if (trimmed.contains('| ') && trimmed.contains(' |')) {
      return true;
    }

    // 包含链接
    if (RegExp(r'\[.*\]\(.*\)').hasMatch(trimmed)) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: card.title,
      children: [
        if (_shouldUseMarkdown(card.content))
          _MarkdownContent(data: card.content)
        else
          SelectableText(card.content, style: const TextStyle(height: 1.7)),
      ],
    );
  }
}

class _MarkdownContent extends StatelessWidget {
  const _MarkdownContent({required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;

    return MarkdownBody(
      data: data,
      selectable: true,
      syntaxHighlighter: _CodeSyntaxHighlighter(),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: baseStyle.copyWith(height: 1.7),
        h1: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 22,
        ),
        h2: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
        h3: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
        code: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 13,
          color: const Color(0xFFE7EEF8),
          backgroundColor: const Color(0xFF14263A).withValues(alpha: 0.6),
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF0B1220),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        codeblockPadding: const EdgeInsets.all(16),
        listBullet: baseStyle.copyWith(height: 1.7),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppColors.accent.withValues(alpha: 0.5),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 16),
      ),
    );
  }
}

// ── 代码语法高亮器 ─────────────────────────────────────────

class _CodeSyntaxHighlighter extends SyntaxHighlighter {
  // 关键字颜色
  static const _keywordColor = Color(0xFFC792EA);
  static const _stringColor = Color(0xFFC3E88D);
  static const _commentColor = Color(0xFF546E7A);
  static const _numberColor = Color(0xFFF78C6C);
  static const _typeColor = Color(0xFF82AAFF);
  static const _functionColor = Color(0xFFEEFFFF);
  static const _defaultColor = Color(0xFFE7EEF8);

  static const _keywords = {
    'abstract',
    'assert',
    'boolean',
    'break',
    'byte',
    'case',
    'catch',
    'char',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'double',
    'else',
    'enum',
    'extends',
    'final',
    'finally',
    'float',
    'for',
    'goto',
    'if',
    'implements',
    'import',
    'instanceof',
    'int',
    'interface',
    'long',
    'native',
    'new',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'short',
    'static',
    'strictfp',
    'super',
    'switch',
    'synchronized',
    'this',
    'throw',
    'throws',
    'transient',
    'try',
    'void',
    'volatile',
    'while',
    'true',
    'false',
    'null',
    'var',
    'record',
    'sealed',
    'permits',
    'yield',
    'with',
    'def',
    'fn',
    'let',
    'async',
    'await',
  };

  static const _typeKeywords = {
    'String',
    'Object',
    'List',
    'Map',
    'Set',
    'Collection',
    'Iterator',
    'Integer',
    'Long',
    'Double',
    'Float',
    'Boolean',
    'Character',
    'Byte',
    'Short',
    'Number',
    'Comparable',
    'Iterable',
    'Stream',
    'Optional',
    'ArrayList',
    'HashMap',
    'HashSet',
    'LinkedList',
    'TreeMap',
    'TreeSet',
  };

  @override
  TextSpan format(String source) {
    final tokens = _tokenize(source);
    return TextSpan(children: tokens);
  }

  List<TextSpan> _tokenize(String code) {
    final tokens = <TextSpan>[];
    final buffer = StringBuffer();
    var i = 0;

    while (i < code.length) {
      // 单行注释
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '/') {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final start = i;
        while (i < code.length && code[i] != '\n') {
          i++;
        }
        tokens.add(
          TextSpan(
            text: code.substring(start, i),
            style: TextStyle(
              color: _commentColor,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      // 多行注释
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final start = i;
        i += 2;
        while (i + 1 < code.length && !(code[i] == '*' && code[i + 1] == '/')) {
          i++;
        }
        i += 2;
        tokens.add(
          TextSpan(
            text: code.substring(start, i),
            style: TextStyle(
              color: _commentColor,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      // 字符串
      if (code[i] == '"' || code[i] == '\'') {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final quote = code[i];
        final start = i;
        i++;
        while (i < code.length && code[i] != quote) {
          if (code[i] == '\\') i++;
          i++;
        }
        i++;
        tokens.add(
          TextSpan(
            text: code.substring(start, i),
            style: TextStyle(
              color: _stringColor,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      // 数字
      if (RegExp(r'[0-9]').hasMatch(code[i])) {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final start = i;
        while (i < code.length && RegExp(r'[0-9.xXa-fA-F]').hasMatch(code[i])) {
          i++;
        }
        tokens.add(
          TextSpan(
            text: code.substring(start, i),
            style: TextStyle(
              color: _numberColor,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      // 标识符或关键字
      if (RegExp(r'[a-zA-Z_$]').hasMatch(code[i])) {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final start = i;
        while (i < code.length && RegExp(r'[a-zA-Z0-9_$]').hasMatch(code[i])) {
          i++;
        }
        final word = code.substring(start, i);
        Color color;
        if (_keywords.contains(word)) {
          color = _keywordColor;
        } else if (_typeKeywords.contains(word)) {
          color = _typeColor;
        } else if (i < code.length && code[i] == '(') {
          color = _functionColor;
        } else {
          color = _defaultColor;
        }
        tokens.add(
          TextSpan(
            text: word,
            style: TextStyle(
              color: color,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      // 其他字符
      buffer.write(code[i]);
      i++;
    }

    if (buffer.isNotEmpty) {
      tokens.add(
        TextSpan(
          text: buffer.toString(),
          style: TextStyle(
            color: _defaultColor,
            fontFamily: 'JetBrainsMono',
            fontSize: 13,
            height: 1.6,
          ),
        ),
      );
    }

    return tokens;
  }
}

// ── 评分标准面板 ──────────────────────────────────────────────

class _RubricSection extends StatelessWidget {
  const _RubricSection({required this.rubric});
  final Rubric rubric;

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: '评分标准',
      children: [
        // 必须覆盖的关键点
        Text(
          '必须覆盖的关键点',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 8),
        ...rubric.mustHave.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          ),
        ),
        // 加分项
        if (rubric.goodToHave.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '加分项',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          ...rubric.goodToHave.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.star_outline, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
        ],
        // 常见错误
        if (rubric.commonMistakes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '常见错误',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 8),
          ...rubric.commonMistakes.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cancel_outlined,
                    size: 18,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── 复述练习 Tab（Prompt / Answer 分栏布局）──────────────────

class _RecallTab extends StatelessWidget {
  const _RecallTab({
    required this.topic,
    required this.answerController,
    required this.isEvaluating,
    required this.evaluationResult,
    required this.onEvaluate,
  });

  final Topic topic;
  final TextEditingController answerController;
  final bool isEvaluating;
  final Map<String, dynamic>? evaluationResult;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;

    if (wide) {
      // 宽屏：左右分栏
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：Prompt（题目 + checklist）
          Expanded(flex: 5, child: _PromptPanel(topic: topic)),
          const VerticalDivider(width: 1),
          // 右侧：Answer（输入 + 评估）
          Expanded(
            flex: 5,
            child: _AnswerPanel(
              topic: topic,
              answerController: answerController,
              isEvaluating: isEvaluating,
              evaluationResult: evaluationResult,
              onEvaluate: onEvaluate,
            ),
          ),
        ],
      );
    }

    // 窄屏：上下排列
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _PromptPanel(topic: topic),
        const SizedBox(height: 16),
        _AnswerPanel(
          topic: topic,
          answerController: answerController,
          isEvaluating: isEvaluating,
          evaluationResult: evaluationResult,
          onEvaluate: onEvaluate,
        ),
      ],
    );
  }
}

// ── 左侧 Prompt 面板 ────────────────────────────────────────

class _PromptPanel extends StatelessWidget {
  const _PromptPanel({required this.topic});
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 题目
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.quiz_outlined, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    '复述题目',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (topic.recallPrompts.isNotEmpty)
                ...topic.recallPrompts.map(
                  (prompt) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 18,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              prompt.prompt,
                              style: const TextStyle(height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 18,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text('用自己的话解释这个知识点的核心内容。')),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Checklist：必须说到的关键点
        if (topic.rubric != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.checklist_outlined,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '必须说到的关键点',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...topic.rubric!.mustHave.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 常见错误提示
          if (topic.rubric!.commonMistakes.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_outlined,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '常见错误',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...topic.rubric!.commonMistakes.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            size: 16,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// ── 右侧 Answer 面板 ────────────────────────────────────────

class _AnswerPanel extends StatelessWidget {
  const _AnswerPanel({
    required this.topic,
    required this.answerController,
    required this.isEvaluating,
    required this.evaluationResult,
    required this.onEvaluate,
  });

  final Topic topic;
  final TextEditingController answerController;
  final bool isEvaluating;
  final Map<String, dynamic>? evaluationResult;
  final VoidCallback onEvaluate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 输入区
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_outlined, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    '你的回答',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${answerController.text.length} 字',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: answerController,
                minLines: 8,
                maxLines: 16,
                decoration: InputDecoration(
                  hintText: '在这里输入你的复述答案...\n\n建议：先说定义 → 再拆机制 → 最后讲场景和误区',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: VoiceInputButton(
                    onResult: (text) {
                      answerController.text += text;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isEvaluating ? null : onEvaluate,
                  icon: isEvaluating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(isEvaluating ? 'AI 评估中...' : '获取 AI 深度评估'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 评估结果
        if (evaluationResult != null) ...[
          const SizedBox(height: 16),
          _EvaluationResultPanel(result: evaluationResult!),
        ],
      ],
    );
  }
}

// ── AI 评估结果面板（含环形分数 + feedback tags）───────────────

class _EvaluationResultPanel extends StatelessWidget {
  const _EvaluationResultPanel({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final score = result['score'] as int? ?? 0;
    final missed = result['missedPoints'] as List<dynamic>? ?? [];
    final errors = result['errorPoints'] as List<dynamic>? ?? [];
    final optimized = result['optimizedAnswer'] as String? ?? '';
    final feedbackTags = result['feedbackTags'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assessment_outlined, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'AI 评估结果',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 环形分数 + 标签
          Row(
            children: [
              _ScoreRing(score: score, size: 80),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ScoreBadge(score: score),
                    if (feedbackTags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: feedbackTags
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  tag.toString(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 遗漏点
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '遗漏点',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 6),
            ...missed.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              ),
            ),
          ],
          // 错误点
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '错误点',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 6),
            ...errors.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cancel_outlined,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              ),
            ),
          ],
          // 优化回答
          if (optimized.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '优化回答',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(optimized, style: const TextStyle(height: 1.6)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 环形分数组件 ──────────────────────────────────────────────

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, this.size = 80});

  final int score;
  final double size;

  Color get _color {
    if (score >= 85) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 背景圆环
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 6,
              color: Colors.grey.shade200,
            ),
          ),
          // 分数圆环
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 6,
              color: _color,
              backgroundColor: Colors.transparent,
            ),
          ),
          // 分数文字
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.w900,
                  color: _color,
                ),
              ),
              Text(
                '分',
                style: TextStyle(fontSize: size * 0.12, color: _color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
