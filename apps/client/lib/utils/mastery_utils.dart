import 'package:flutter/material.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

enum MasteryLevel { mastered, learning, unknown }

MasteryLevel getMasteryLevel(int score) {
  if (score >= 85) return MasteryLevel.mastered;
  if (score >= 60) return MasteryLevel.learning;
  return MasteryLevel.unknown;
}

Color getMasteryColor(int score) {
  switch (getMasteryLevel(score)) {
    case MasteryLevel.mastered:
      return AppColors.success;
    case MasteryLevel.learning:
      return AppColors.warning;
    case MasteryLevel.unknown:
      return const Color(0xFF64748B);
  }
}

String getMasteryLabel(int score) {
  switch (getMasteryLevel(score)) {
    case MasteryLevel.mastered:
      return '熟练';
    case MasteryLevel.learning:
      return '不熟练';
    case MasteryLevel.unknown:
      return '未掌握';
  }
}
