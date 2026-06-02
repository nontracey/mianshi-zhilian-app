import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/services/ticket_service.dart';
import 'package:mianshi_zhilian/services/upload_service.dart';
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

class _PendingImage {
  _PendingImage({required this.bytes});
  final Uint8List bytes;
  String? uploadedUrl; // 提交时上传 R2 后填入
}

class _SubmitTicketPageState extends State<SubmitTicketPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _contactController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<_PendingImage> _images = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  bool get _isPasswordReset => widget.type == 'password_reset';
  int get _minDescriptionLength => _isPasswordReset ? 10 : 2;

  @override
  void dispose() {
    _subjectController.dispose();
    _contactController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _sanitize(String input) {
    return input
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>'), '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _images.add(_PendingImage(bytes: bytes));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('submit_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final auth = context.read<AuthProvider>();
      final storage = StorageService();
      final uploadService = UploadService(
        storage: storage,
        getApiUrl: () => auth.apiBaseUrl,
      );
      final ticketService = TicketService(
        storage: storage,
        getApiUrl: () => auth.apiBaseUrl,
        getToken: () => auth.token,
      );

      // 1. 上传所有图片到 R2（不阻塞 UI 反馈）
      final r2Urls = <String>[];
      for (var i = 0; i < _images.length; i++) {
        final img = _images[i];
        if (img.uploadedUrl != null) {
          r2Urls.add(img.uploadedUrl!);
          continue;
        }
        try {
          final url = await uploadService.uploadImage(
            bytes: img.bytes,
          );
          img.uploadedUrl = url;
          r2Urls.add(url);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${l10n.get('submit_failed')}: $e')),
            );
          }
          return; // 任一图上传失败，整体取消提交
        }
      }

      // 2. 提交工单（只发 R2 URL，不带 base64）
      await ticketService.submitTicket(
        type: widget.type,
        subject: _sanitize(_subjectController.text),
        contact: _sanitize(_contactController.text),
        description: _sanitize(_descriptionController.text),
        imageUrls: r2Urls,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isPasswordReset
                  ? l10n.get('password_reset_ticket_submitted')
                  : l10n.get('ticket_submitted'),
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.get('submit_failed')}: $e')),
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
        title: Text(_isPasswordReset ? l10n.get('reset_password_ticket') : l10n.get('submit_feedback')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                          ? l10n.get('forgot_password_ticket_desc')
                          : l10n.get('feedback_guide'),
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

            TextFormField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: l10n.get('subject'),
                hintText: _isPasswordReset ? l10n.get('example_forgot_password_reset') : l10n.get('briefly_describe_issue'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.subject),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.get('please_enter_subject');
                return null;
              },
            ),
            const SizedBox(height: 16),

            if (_isPasswordReset) ...[
              TextFormField(
                controller: _contactController,
                decoration: InputDecoration(
                  labelText: l10n.get('contact_method'),
                  hintText: l10n.get('contact_method_hint'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.contact_mail_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l10n.get('please_enter_contact_method');
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _descriptionController,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.get('detailed_description'),
                hintText: _isPasswordReset
                    ? l10n.get('describe_situation_for_reset')
                    : l10n.get('describe_issue_detail'),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.get('please_enter_detailed_description');
                if (v.trim().length < _minDescriptionLength) {
                  return l10n.getp('describe_min_chars', {'count': _minDescriptionLength.toString()});
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            Text(
              l10n.get('upload_images_max5'),
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
                ..._images.asMap().entries.map((entry) {
                  final img = entry.value;
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
                          image: DecorationImage(
                            image: MemoryImage(img.bytes),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: img.uploadedUrl != null
                            ? Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  margin: const EdgeInsets.all(2),
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, size: 10, color: Colors.white),
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.removeAt(entry.key)),
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
                if (_images.length < 5)
                  GestureDetector(
                    onTap: _pickImage,
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

            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.get('submit_ticket')),
            ),
          ],
        ),
      ),
    );
  }
}
