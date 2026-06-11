import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
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
      _versions.addAll(data.map(_versionWithIdentity));
    });
  }

  Future<void> _saveVersions() async {
    await _storage.saveJsonList(_storageKey, _versions);
  }

  Map<String, dynamic> _versionWithIdentity(
    Map<dynamic, dynamic> version, {
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toIso8601String();
    final normalized = version.map((k, v) => MapEntry(k.toString(), v));
    normalized['id'] = StorageService.answerVersionIdFor(normalized);
    normalized['createdAt'] ??= timestamp;
    normalized['updatedAt'] ??= normalized['createdAt'];
    return normalized;
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
        title: Text(l10n.get('answer_version_library')),
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
                const Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.get(
                      'save_your_multi_version_answer_support_long_draft_ai_modif',
                    ),
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
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
            Icon(Icons.edit_note, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              l10n.get('still_not_has_save_answer_version'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get(
                'point_hit_lower_method_button_add_your_one_version_answ',
              ),
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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
      'draft': l10n.get('draft'),
      'ai_modified': l10n.get('ai_modify_version'),
      'interview': l10n.get('interview_version'),
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
                  l10n.get('ai_evaluation_self_dynamic_save'),
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
                Clipboard.setData(
                  ClipboardData(text: version['content'] ?? ''),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l10n.get(
                        'already_review_control_to_clip_clipboard_board',
                      ),
                    ),
                  ),
                );
              },
              tooltip: l10n.get('review_control'),
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
                    color: isDark
                        ? const Color(0xFF1A2332)
                        : Colors.grey.shade50,
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
                        label: Text(l10n.get('design_as_interview_version')),
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
                  Text(
                    l10n.get('version_type'),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.get('draft')),
                        selected: _selectedVersionType == 'draft',
                        onSelected: (_) => setDialogState(
                          () => _selectedVersionType = 'draft',
                        ),
                      ),
                      ChoiceChip(
                        label: Text(l10n.get('ai_modify_version')),
                        selected: _selectedVersionType == 'ai_modified',
                        onSelected: (_) => setDialogState(
                          () => _selectedVersionType = 'ai_modified',
                        ),
                      ),
                      ChoiceChip(
                        label: Text(l10n.get('interview_version')),
                        selected: _selectedVersionType == 'interview',
                        onSelected: (_) => setDialogState(
                          () => _selectedVersionType = 'interview',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 回答内容
                  Text(
                    l10n.get('answer_content'),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _answerController,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: l10n.get('input_your_answer'),
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
        SnackBar(content: Text(l10n.get('please_input_answer_content'))),
      );
      return;
    }

    setState(() {
      _versions.add(
        _versionWithIdentity({
          'type': _selectedVersionType,
          'content': _answerController.text.trim(),
          'createdAt': DateTime.now().toIso8601String(),
        }),
      );
    });

    await _saveVersions();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.get('version_already_save'))));
    }
  }

  Future<void> _deleteVersion(int index) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('confirm_delete')),
        content: Text(l10n.get('confirm_fixed_key_delete_this_version')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final removed = Map<String, dynamic>.from(_versions[index]);
              setState(() {
                _versions.removeAt(index);
              });
              await _saveVersions();
              await _storage.recordAnswerVersionDeletion(
                widget.topicId,
                removed,
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
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
                  Text(
                    l10n.get('version_type'),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.get('draft')),
                        selected: _selectedVersionType == 'draft',
                        onSelected: (_) => setDialogState(
                          () => _selectedVersionType = 'draft',
                        ),
                      ),
                      ChoiceChip(
                        label: Text(l10n.get('ai_modify_version')),
                        selected: _selectedVersionType == 'ai_modified',
                        onSelected: (_) => setDialogState(
                          () => _selectedVersionType = 'ai_modified',
                        ),
                      ),
                      ChoiceChip(
                        label: Text(l10n.get('interview_version')),
                        selected: _selectedVersionType == 'interview',
                        onSelected: (_) => setDialogState(
                          () => _selectedVersionType = 'interview',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 回答内容
                  Text(
                    l10n.get('answer_content'),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _answerController,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: l10n.get('input_your_answer'),
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
                final messenger = ScaffoldMessenger.of(context);
                final existing = _versionWithIdentity(_versions[index]);
                setState(() {
                  _versions[index] = {
                    ...existing,
                    'type': _selectedVersionType,
                    'content': _answerController.text.trim(),
                    'createdAt': existing['createdAt'],
                    'updatedAt': DateTime.now().toIso8601String(),
                  };
                });
                await _saveVersions();
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
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
        SnackBar(
          content: Text(l10n.get('please_first_fill_write_answer_content')),
        ),
      );
      return;
    }

    final aiProvider = context.read<AiProvider>();
    if (!aiProvider.hasAnyConfig) {
      // 无 AI 配置时降级为复制到剪贴板
      await Clipboard.setData(
        ClipboardData(
          text: l10n.getp(
            'please_help_we_improve_by_lower_interview_answer_n_n_conten_2',
            {'content': content},
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.get('ai_not_configured_copied_to_clipboard')),
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
                const Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: AppColors.accent,
                ),
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
                              Text(l10n.get('ai_analyzing_your_answer')),
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
                            const Icon(
                              Icons.error_outline,
                              size: 16,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                error!,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
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
                        child: Text(
                          improvedText,
                          style: const TextStyle(height: 1.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.get('close')),
              ),
              if (improvedText.isNotEmpty)
                FilledButton.icon(
                  onPressed: () async {
                    // 保存为 AI 修改版
                    setState(() {
                      _versions.add(
                        _versionWithIdentity({
                          'type': 'ai_modified',
                          'content': improvedText,
                          'createdAt': DateTime.now().toIso8601String(),
                          'source': 'ai_improve',
                        }),
                      );
                    });
                    await _saveVersions();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.get('already_save_as_ai_modify_version'),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.save, size: 16),
                  label: Text(l10n.get('save_as_ai_modify_version')),
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
      final prompt =
          l10n.get('please_help_we_improve_by_lower_interview_answer_use_its') +
          l10n.get('retain_core_points_optimize_expression') +
          l10n.get('output_improved_answer_only_no_prefix') +
          l10n.getp('original_start_answer_n_answer_2', {
            'answer': originalAnswer,
          });

      final stream = aiProvider.sendMessageStream(
        prompt,
        systemPrompt: l10n.get('you_are_senior_interview_coach'),
      );

      await for (final token in stream) {
        onToken(token);
      }
      onComplete();
    } catch (e) {
      onError(l10n.getp('ai_improve_fail_error_2', {'error': e}));
    }
  }

  Future<void> _setAsInterviewVersion(int index) async {
    setState(() {
      _versions[index] = _versionWithIdentity(_versions[index]);
      _versions[index]['type'] = 'interview';
      _versions[index]['updatedAt'] = DateTime.now().toIso8601String();
    });
    await _saveVersions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.get('already_design_as_interview_version')),
        ),
      );
    }
  }
}
