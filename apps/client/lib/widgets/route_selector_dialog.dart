import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/learning_route.dart';
import '../providers/localization_provider.dart';
import '../theme/colors.dart';

class RouteSelectorDialog extends StatelessWidget {
  const RouteSelectorDialog({
    super.key,
    required this.routes,
    required this.currentRouteId,
    required this.onRouteSelected,
    required this.onCreateRoute,
  });

  final List<LearningRoute> routes;
  final String? currentRouteId;
  final ValueChanged<LearningRoute> onRouteSelected;
  final VoidCallback onCreateRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
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
                  l10n.get('select_study_route'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 路线列表
            ...routes.map((route) {
              final isSelected = route.id == currentRouteId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    onRouteSelected(route);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.accent
                            : (isDark ? const Color(0xFF30363D) : const Color(0xFFE0E0E0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                route.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isSelected ? AppColors.accent : null,
                                ),
                              ),
                              if (route.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  route.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white54 : Colors.grey,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: route.domainIds.map((id) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      id,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: AppColors.accent),
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 16),

            // 创建自定义路线
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCreateRoute,
                icon: const Icon(Icons.add),
                label: Text(l10n.get('create_build_custom_route')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
