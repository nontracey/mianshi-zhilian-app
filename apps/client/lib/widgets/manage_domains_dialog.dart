import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/domain.dart';
import '../providers/localization_provider.dart';
import '../theme/colors.dart';

class ManageDomainsDialog extends StatefulWidget {
  const ManageDomainsDialog({
    super.key,
    required this.domains,
    required this.onDomainsReordered,
    required this.onDomainRemoved,
  });

  final List<Domain> domains;
  final ValueChanged<List<Domain>> onDomainsReordered;
  final ValueChanged<Domain> onDomainRemoved;

  @override
  State<ManageDomainsDialog> createState() => _ManageDomainsDialogState();
}

class _ManageDomainsDialogState extends State<ManageDomainsDialog> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();

  late List<Domain> _domains;

  @override
  void initState() {
    super.initState();
    _domains = List.from(widget.domains);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.school_outlined, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  l10n.get('management_domain'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('drag_to_sort_delete_domain'),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ),
            const SizedBox(height: 16),

            // 领域列表
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _domains.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _domains.removeAt(oldIndex);
                  _domains.insert(newIndex, item);
                });
                widget.onDomainsReordered(_domains);
              },
              itemBuilder: (context, index) {
                final domain = _domains[index];
                return Container(
                  key: ValueKey(domain.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161B22) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
                    ),
                  ),
                  child: Row(
                    children: [
                      // 拖动手柄
                      Icon(
                        Icons.drag_handle,
                        size: 20,
                        color: isDark ? Colors.white38 : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      // 领域信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              domain.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                              ),
                            ),
                            Text(
                              l10n.getp('{count}_4e2a_knowledge_point', {'count': domain.topicCount}),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white54 : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 删除按钮
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        color: AppColors.danger,
                        onPressed: () {
                          setState(() {
                            _domains.removeAt(index);
                          });
                          widget.onDomainRemoved(domain);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // 提示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.get('delete_domain_info'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 完成按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.get('complete')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
