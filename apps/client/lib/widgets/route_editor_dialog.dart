import 'package:flutter/material.dart';
import 'package:mianshi_zhilian/models/learning_route.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:provider/provider.dart';

class RouteEditorDialog extends StatefulWidget {
  const RouteEditorDialog({
    super.key,
    required this.availableDomains,
    this.existingRoute,
    required this.onSave,
  });

  final List<DomainItem> availableDomains;
  final LearningRoute? existingRoute;
  final ValueChanged<LearningRoute> onSave;

  @override
  State<RouteEditorDialog> createState() => _RouteEditorDialogState();
}

class DomainItem {
  final String id;
  final String title;
  const DomainItem({required this.id, required this.title});
}

class _RouteEditorDialogState extends State<RouteEditorDialog> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();

  late TextEditingController _nameController;
  late TextEditingController _descController;
  late List<String> _selectedDomainIds;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingRoute?.name ?? '');
    _descController = TextEditingController(text: widget.existingRoute?.description ?? '');
    _selectedDomainIds = List.from(widget.existingRoute?.domainIds ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('请输入路线名称'))),
      );
      return;
    }
    if (_selectedDomainIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('请至少选择一个领域'))),
      );
      return;
    }

    widget.onSave(LearningRoute(
      id: widget.existingRoute?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      domainIds: _selectedDomainIds,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  const Icon(Icons.route, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    widget.existingRoute != null ? l10n.get('编辑路线') : l10n.get('创建自定义路线'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 路线名称
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.get('路线名称'),
                  hintText: l10n.get('例如：Java 后端开发'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 16),

              // 路线描述
              TextField(
                controller: _descController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.get('路线描述（可选）'),
                  hintText: l10n.get('简要描述这条路线的学习目标'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.description_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // 选择领域
              Text(
                l10n.get('选择领域（点击添加，拖动排序）'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              // 已选领域（可拖动排序）
              if (_selectedDomainIds.isNotEmpty) ...[
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _selectedDomainIds.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = _selectedDomainIds.removeAt(oldIndex);
                      _selectedDomainIds.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final domainId = _selectedDomainIds[index];
                    final domain = widget.availableDomains.firstWhere(
                      (d) => d.id == domainId,
                      orElse: () => DomainItem(id: domainId, title: domainId),
                    );
                    return Container(
                      key: ValueKey(domainId),
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_handle, size: 16, color: AppColors.accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(domain.title, style: const TextStyle(fontSize: 13))),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setState(() => _selectedDomainIds.removeAt(index)),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              // 可选领域
              Text(
                l10n.get('可选领域'),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.availableDomains
                    .where((d) => !_selectedDomainIds.contains(d.id))
                    .map((domain) {
                  return ActionChip(
                    label: Text(domain.title, style: const TextStyle(fontSize: 12)),
                    avatar: const Icon(Icons.add, size: 14),
                    onPressed: () => setState(() => _selectedDomainIds.add(domain.id)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // 保存按钮
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(l10n.get('保存路线')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
