import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/localization_provider.dart';
import '../theme/colors.dart';

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score});

  final int score;

  Color get _color {
    if (score >= 85) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return const Color(0xFF64748B);
  }

  String get _label {
    if (score >= 85) return '熟练';
    if (score >= 60) return '不熟练';
    return '未掌握';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final label = l10n.get(_label);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        l10n.getp('{score} 分 · {label}', {'score': '$score', 'label': label}),
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: _color,
        ),
      ),
    );
  }
}
