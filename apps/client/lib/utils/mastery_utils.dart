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

String getMasteryLabelKey(int score) {
  switch (getMasteryLevel(score)) {
    case MasteryLevel.mastered:
      return 'mastery_skilled';
    case MasteryLevel.learning:
      return 'mastery_learning';
    case MasteryLevel.unknown:
      return 'un_mastery';
  }
}
