import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/services/ticket_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

class SubmitTicketPage extends StatefulWidget {
  const SubmitTicketPage({
    super.key,
    required this.type,
  });

  final String type; // 'password_reset' or 'feedback'

  @override
  State<SubmitTicketPage> createState() => _SubmitTicketPageState();
}

class _SubmitTicketPageState extends State<SubmitTicketPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<String> _imageUrls = [];
  bool _isSubmitting = false;

  bool get _isPasswordReset => widget.type == 'password_reset';
  int get _minDescriptionLength => _isPasswordReset ? 10 : 2;

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // 防注入：清理输入
  String _sanitize(String input) {
    return input
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>'), '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final ticketService = TicketService(storage: StorageService());
      await ticketService.submitTicket(
        type: widget.type,
        subject: _sanitize(_subjectController.text),
        description: _sanitize(_descriptionController.text),
        imageUrls: _imageUrls,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('工单已提交，我们会尽快处理'))),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('提交失败')}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isPasswordReset ? l10n.get('重置密码工单') : l10n.get('提交反馈')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 提示信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isPasswordReset
                          ? l10n.get('如果您忘记了密码且无法通过其他方式重置，请提交工单，管理员会审核处理。')
                          : l10n.get('有任何问题或建议，请在这里告诉我们。'),
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 主题
            TextFormField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: l10n.get('主题'),
                hintText: _isPasswordReset ? l10n.get('例：忘记密码需要重置') : l10n.get('简要描述您的问题'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.subject),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.get('请输入主题');
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 详细描述
            TextFormField(
              controller: _descriptionController,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.get('详细描述'),
                hintText: _isPasswordReset
                    ? l10n.get('请详细描述您的情况，包括注册时使用的用户名等信息...')
                    : l10n.get('请详细描述您的问题或建议...'),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.get('请输入详细描述');
                if (v.trim().length < _minDescriptionLength) {
                  return l10n.getp('描述至少需要 {count} 个字', {'count': _minDescriptionLength.toString()});
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 上传图片
            Text(
              l10n.get('上传图片（可选，最多5张）'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._imageUrls.asMap().entries.map((entry) {
                  return Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? Colors.white24 : Colors.grey.shade300,
                          ),
                        ),
                        child: const Icon(Icons.image, size: 32),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _imageUrls.removeAt(entry.key)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                if (_imageUrls.length < 5)
                  GestureDetector(
                    onTap: () {
                      // TODO: 实现图片选择
                      setState(() => _imageUrls.add('placeholder'));
                    },
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 32,
                        color: isDark ? Colors.white38 : Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // 提交按钮
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.get('提交工单')),
            ),
          ],
        ),
      ),
    );
  }
}
