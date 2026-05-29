import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class AnswerVersionsPage extends StatefulWidget {
  const AnswerVersionsPage({
    super.key,
    required this.topicId,
    required this.topicTitle,
    required this.question,
  });

  final String topicId;
  final String topicTitle;
  final String question;

  @override
  State<AnswerVersionsPage> createState() => _AnswerVersionsPageState();
}

class _AnswerVersionsPageState extends State<AnswerVersionsPage> {
  final List<Map<String, dynamic>> _versions = [];
  final _answerController = TextEditingController();
  String _selectedVersionType = 'draft';

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  void _loadVersions() {
    // TODO: 从本地存储加载已保存的版本
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回答版本库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddVersionDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 问题卡片
          _buildQuestionCard(context, isDark),
          const SizedBox(height: 16),

          // 版本说明
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
                    '保存你的多版回答，支持"初稿 -> AI 修改 -> 面试版"迭代',
                    style: TextStyle(fontSize: 12, color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 版本列表
          if (_versions.isEmpty)
            _buildEmptyState(context, isDark)
          else
            ..._versions.asMap().entries.map((entry) {
              return _buildVersionCard(context, entry.key, entry.value, isDark);
            }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddVersionDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('添加版本'),
      ),
    );
  }

  Widget _buildQuestionCard(BuildContext context, bool isDark) {
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
                    widget.topicTitle,
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
              widget.question,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.edit_note,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有保存的回答版本',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮添加你的第一版回答',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showAddVersionDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('添加版本'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionCard(
    BuildContext context,
    int index,
    Map<String, dynamic> version,
    bool isDark,
  ) {
    final type = version['type'] as String;
    final typeLabels = {
      'draft': '初稿',
      'ai_modified': 'AI 修改版',
      'interview': '面试版',
    };
    final typeColors = {
      'draft': Colors.grey,
      'ai_modified': AppColors.accent,
      'interview': AppColors.success,
    };
    final typeIcons = {
      'draft': Icons.edit_note,
      'ai_modified': Icons.auto_awesome,
      'interview': Icons.workspace_premium,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: (typeColors[type] ?? Colors.grey).withValues(alpha: 0.3),
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (typeColors[type] ?? Colors.grey).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            typeIcons[type] ?? Icons.article,
            color: typeColors[type] ?? Colors.grey,
            size: 20,
          ),
        ),
        title: Text(
          '${typeLabels[type] ?? type} - v${index + 1}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: typeColors[type] ?? Colors.grey,
          ),
        ),
        subtitle: Text(
          version['createdAt'] ?? '',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white38 : const Color(0xFF999999),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: version['content'] ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              },
              tooltip: '复制',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _deleteVersion(index),
              tooltip: '删除',
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A2332) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    version['content'] ?? '',
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
                const SizedBox(height: 12),
                // 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editVersion(index),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('编辑'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _askAIForImprovement(version),
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const Text('AI 改进'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _setAsInterviewVersion(index),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('设为面试版'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddVersionDialog(BuildContext context) {
    _answerController.clear();
    _selectedVersionType = 'draft';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加回答版本'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 版本类型选择
                  const Text('版本类型', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('初稿'),
                        selected: _selectedVersionType == 'draft',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'draft'),
                      ),
                      ChoiceChip(
                        label: const Text('AI 修改版'),
                        selected: _selectedVersionType == 'ai_modified',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'ai_modified'),
                      ),
                      ChoiceChip(
                        label: const Text('面试版'),
                        selected: _selectedVersionType == 'interview',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'interview'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 回答内容
                  const Text('回答内容', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _answerController,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: '输入你的回答...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                _saveVersion();
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveVersion() {
    if (_answerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入回答内容')),
      );
      return;
    }

    setState(() {
      _versions.add({
        'type': _selectedVersionType,
        'content': _answerController.text.trim(),
        'createdAt': DateTime.now().toString().substring(0, 16),
      });
    });

    // TODO: 保存到本地存储

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('版本已保存')),
    );
  }

  void _deleteVersion(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个版本吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _versions.removeAt(index);
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('版本已删除')),
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _editVersion(int index) {
    _answerController.text = _versions[index]['content'] ?? '';
    _selectedVersionType = _versions[index]['type'] ?? 'draft';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑版本'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 版本类型选择
                  const Text('版本类型', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('初稿'),
                        selected: _selectedVersionType == 'draft',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'draft'),
                      ),
                      ChoiceChip(
                        label: const Text('AI 修改版'),
                        selected: _selectedVersionType == 'ai_modified',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'ai_modified'),
                      ),
                      ChoiceChip(
                        label: const Text('面试版'),
                        selected: _selectedVersionType == 'interview',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'interview'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 回答内容
                  const Text('回答内容', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _answerController,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: '输入你的回答...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _versions[index] = {
                    'type': _selectedVersionType,
                    'content': _answerController.text.trim(),
                    'createdAt': _versions[index]['createdAt'],
                    'updatedAt': DateTime.now().toString().substring(0, 16),
                  };
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('版本已更新')),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _askAIForImprovement(Map<String, dynamic> version) {
    // TODO: 调用AI改进回答
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI 改进功能开发中...')),
    );
  }

  void _setAsInterviewVersion(int index) {
    setState(() {
      _versions[index]['type'] = 'interview';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已设为面试版')),
    );
  }
}
