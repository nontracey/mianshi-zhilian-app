import 'package:flutter/material.dart';
import '../theme/colors.dart';

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.score, this.radius = 8});

  final int score;
  final double radius;

  Color get _color {
    if (score >= 85) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) =>
      CircleAvatar(radius: radius, backgroundColor: _color);
}
