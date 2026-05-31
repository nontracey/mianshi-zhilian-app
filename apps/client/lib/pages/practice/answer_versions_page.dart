import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import '../../providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

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
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final List<Map<String, dynamic>> _versions = [];
  final _answerController = TextEditingController();
  final _storage = StorageService();
  String _selectedVersionType = 'draft';
  

  String get _storageKey => 'answer_versions_${widget.topicId}';

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    final data = await _storage.loadJsonList(_storageKey);
    setState(() {
      _versions.clear();
      _versions.addAll(data);
    });
  }

  Future<void> _saveVersions() async {
    await _storage.saveJsonList(_storageKey, _versions);
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('answer_version_5e93')),
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
                    l10n.get('save_4f60_7684_591a_7248_answer_652f_6301_521d_7a3f_ai_modif'),
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
        label: Text(l10n.get('add_version')),
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
                  child: Text(
                    l10n.get('problem'),
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
              l10n.get('8fd8_6ca1_has_save_7684_answer_version'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('70b9_51fb_4e0b_65b9_button_add_4f60_7684_7b2c_4e00_7248_answ'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showAddVersionDialog(context),
              icon: const Icon(Icons.add),
              label: Text(l10n.get('add_version')),
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
      'draft': l10n.get('521d_7a3f'),
      'ai_modified': l10n.get('ai_modify_7248'),
      'interview': l10n.get('interview_7248'),
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
        subtitle: Row(
          children: [
            Text(
              version['createdAt'] ?? '',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : const Color(0xFF999999),
              ),
            ),
            if (version['source'] == 'auto_eval') ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  l10n.get('ai_evaluation_81ea_52a8_save'),
                  style: TextStyle(fontSize: 10, color: AppColors.accent),
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: version['content'] ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.get('already_590d_5236_5230_526a_8d34_677f'))),
                );
              },
              tooltip: l10n.get('590d_5236'),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _deleteVersion(index),
              tooltip: l10n.get('delete'),
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
                        label: Text(l10n.get('edit')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _askAIForImprovement(version),
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: Text(l10n.get('ai_improve')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _setAsInterviewVersion(index),
                        icon: const Icon(Icons.check, size: 16),
                        label: Text(l10n.get('8bbe_4e3a_interview_7248')),
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
          title: Text(l10n.get('add_answer_version')),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 版本类型选择
                  Text(l10n.get('version_type'), style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.get('521d_7a3f')),
                        selected: _selectedVersionType == 'draft',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'draft'),
                      ),
                      ChoiceChip(
                        label: Text(l10n.get('ai_modify_7248')),
                        selected: _selectedVersionType == 'ai_modified',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'ai_modified'),
                      ),
                      ChoiceChip(
                        label: Text(l10n.get('interview_7248')),
                        selected: _selectedVersionType == 'interview',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'interview'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 回答内容
                  Text(l10n.get('answer_content'), style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _answerController,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: l10n.get('input_4f60_7684_answer'),
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
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () {
                _saveVersion();
                Navigator.pop(ctx);
              },
              child: Text(l10n.get('save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveVersion() async {
    if (_answerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('8bf7_input_answer_content'))),
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

    await _saveVersions();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('version_already_save'))),
      );
    }
  }

  Future<void> _deleteVersion(int index) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('confirm_delete')),
        content: Text(l10n.get('786e_5b9a_8981_delete_8fd9_4e2a_version_5417')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              setState(() {
                _versions.removeAt(index);
              });
              await _saveVersions();
              if (!context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop();
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.get('version_already_delete'))),
              );
            },
            child: Text(l10n.get('delete')),
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
          title: Text(l10n.get('edit_version')),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 版本类型选择
                  Text(l10n.get('version_type'), style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.get('521d_7a3f')),
                        selected: _selectedVersionType == 'draft',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'draft'),
                      ),
                      ChoiceChip(
                        label: Text(l10n.get('ai_modify_7248')),
                        selected: _selectedVersionType == 'ai_modified',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'ai_modified'),
                      ),
                      ChoiceChip(
                        label: Text(l10n.get('interview_7248')),
                        selected: _selectedVersionType == 'interview',
                        onSelected: (_) => setDialogState(() => _selectedVersionType = 'interview'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 回答内容
                  Text(l10n.get('answer_content'), style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _answerController,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: l10n.get('input_4f60_7684_answer'),
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
              child: Text(l10n.get('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                setState(() {
                  _versions[index] = {
                    'type': _selectedVersionType,
                    'content': _answerController.text.trim(),
                    'createdAt': _versions[index]['createdAt'],
                    'updatedAt': DateTime.now().toString().substring(0, 16),
                  };
                });
                await _saveVersions();
                if (!context.mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.get('version_already_update'))),
                );
              },
              child: Text(l10n.get('save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _askAIForImprovement(Map<String, dynamic> version) async {
    final content = version['content'] as String? ?? '';
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('8bf7_5148_586b_5199_answer_content'))),
      );
      return;
    }

    final aiProvider = context.read<AiProvider>();
    if (!aiProvider.hasAnyConfig) {
      // 无 AI 配置时降级为复制到剪贴板
      await Clipboard.setData(ClipboardData(
        text: l10n.getp('8bf7_5e2e_6211_improve_4ee5_4e0b_interview_answer_n_n{conten', {'content': content}),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.get('un_config_ai_already_590d_5236_5230_526a_8d34_677f_53ef_past')),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // 显示 AI 改进对话框
    if (!mounted) return;
    _showAIImprovementDialog(content);
  }

  void _showAIImprovementDialog(String originalAnswer) {
    final aiProvider = context.read<AiProvider>();
    String improvedText = '';
    bool isLoading = true;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // 首次构建时启动 AI 改进
          if (isLoading && improvedText.isEmpty && error == null) {
            _runAIImprovement(
              originalAnswer,
              aiProvider,
              onToken: (token) {
                if (ctx.mounted) {
                  setDialogState(() {
                    improvedText += token;
                    isLoading = false;
                  });
                }
              },
              onComplete: () {
                if (ctx.mounted) {
                  setDialogState(() => isLoading = false);
                }
              },
              onError: (e) {
                if (ctx.mounted) {
                  setDialogState(() {
                    error = e;
                    isLoading = false;
                  });
                }
              },
            );
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 20, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(l10n.get('ai_improve_suggestion')),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLoading && improvedText.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text(l10n.get('ai_6b63_5728_analysis_4f60_7684_answer')),
                            ],
                          ),
                        ),
                      ),
                    if (error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                            const SizedBox(width: 8),
                            Expanded(child: Text(error!, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    if (improvedText.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(improvedText, style: const TextStyle(height: 1.6)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.get('5173_95ed')),
              ),
              if (improvedText.isNotEmpty)
                FilledButton.icon(
                  onPressed: () async {
                    // 保存为 AI 修改版
                    setState(() {
                      _versions.add({
                        'type': 'ai_modified',
                        'content': improvedText,
                        'createdAt': DateTime.now().toString().substring(0, 16),
                        'source': 'ai_improve',
                      });
                    });
                    await _saveVersions();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.get('already_save_4e3a_ai_modify_7248'))),
                      );
                    }
                  },
                  icon: const Icon(Icons.save, size: 16),
                  label: Text(l10n.get('save_4e3a_ai_modify_7248')),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runAIImprovement(
    String originalAnswer,
    AiProvider aiProvider, {
    required void Function(String token) onToken,
    required void Function() onComplete,
    required void Function(String error) onError,
  }) async {
    try {
      final prompt = l10n.get('8bf7_5e2e_6211_improve_4ee5_4e0b_interview_answer_4f7f_5176')
          + l10n.get('4fdd_7559_core_8981_70b9_optimize_expression_65b9_5f0f_suppl')
          + l10n.get('53ea_output_improve_540e_7684_answer_content_not_8981_52a0_5')
          + l10n.getp('539f_59cb_answer_n{answer}', {'answer': originalAnswer});

      final stream = aiProvider.sendMessageStream(
        prompt,
        systemPrompt: l10n.get('4f60_is_4e00_4f4d_8d44_6df1_interview_8f85_5bfc_expert_64c5'),
      );

      await for (final token in stream) {
        onToken(token);
      }
      onComplete();
    } catch (e) {
      onError(l10n.getp('ai_improve_fail_{error}', {'error': e}));
    }
  }

  Future<void> _setAsInterviewVersion(int index) async {
    setState(() {
      _versions[index]['type'] = 'interview';
    });
    await _saveVersions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('already_8bbe_4e3a_interview_7248'))),
      );
    }
  }
}
