import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // 主色调
  static const Color primary = Color(0xFF1A2B4A);
  static const Color accent = Color(0xFF3078F0);
  
  // 状态颜色
  static const Color success = Color(0xFF00A860);
  static const Color warning = Color(0xFFF5A623);
  static const Color danger = Color(0xFFE5484D);
  static const Color info = Color(0xFF3B82F6);
  
  // 浅色主题背景
  static const Color bgLight = Color(0xFFFAFBFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  
  // 质感黑主题（默认深色）- 偏纯黑，有质感
  static const Color bgDark = Color(0xFF0A0A0A);        // 主背景：质感黑
  static const Color surfaceDark = Color(0xFF111111);    // 表面：稍浅黑
  static const Color surfaceDarkHigh = Color(0xFF1A1A1A); // 高级表面：卡片背景
  static const Color surfaceDarkHighest = Color(0xFF222222); // 最高级表面：弹窗
  static const Color borderDark = Color(0xFF2A2A2A);     // 主边框
  static const Color borderDarkSubtle = Color(0xFF1E1E1E); // 次要边框
  
  // 午夜蓝主题 - 偏蓝色调
  static const Color bgMidnight = Color(0xFF0D1117);     // 主背景：深蓝黑
  static const Color surfaceMidnight = Color(0xFF161B22); // 表面
  static const Color surfaceMidnightHigh = Color(0xFF1C2333); // 高级表面
  static const Color surfaceMidnightHighest = Color(0xFF21283B); // 最高级表面
  static const Color borderMidnight = Color(0xFF30363D);  // 主边框
  static const Color borderMidnightSubtle = Color(0xFF21262D); // 次要边框
  
  // 文字颜色
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textTertiary = Color(0xFF999999);
  
  // 浅色边框
  static const Color borderLight = Color(0xFFE8E8E8);
  static const Color borderLighter = Color(0xFFF0F0F0);

  // 分类/标签色板
  static const Color categoryPurple = Color(0xFF8B5CF6);
  static const Color categoryGreen = Color(0xFF10B981);
  static const Color categoryAmber = Color(0xFFF59E0B);
  static const Color categoryRed = Color(0xFFEF4444);
  static const Color categoryCyan = Color(0xFF00CCF9);
  static const Color categoryDeepBlue = Color(0xFF0F3460);

  // Mermaid 5 色板 classDef（asyncState 避 Dart 关键字 async）
  static const Color asyncState = Color(0xFF6366F1);
  static const Color highlight = Color(0xFFEC4899);

  // 代码块背景
  static const Color codeBgDark = Color(0xFF07182A);
  static const Color codeBgDarker = Color(0xFF0B1220);
  static const Color codeBgNavy = Color(0xFF0F172A);
  static const Color codeBgSlate = Color(0xFF14263A);

  // 代码语法高亮
  static const Color syntaxKeyword = Color(0xFFC792EA);  // 紫色
  static const Color syntaxString = Color(0xFFC3E88D);   // 绿色
  static const Color syntaxComment = Color(0xFF546E7A);  // 灰色
  static const Color syntaxNumber = Color(0xFFF78C6C);   // 橙色
  static const Color syntaxType = Color(0xFF82AAFF);     // 蓝色
  static const Color syntaxFunction = Color(0xFFEEFFFF); // 白色
  static const Color syntaxDefault = Color(0xFFE7EEF8);  // 默认色

  // 卡片阴影
  static const Color cardShadow = Color(0x0A000000);
  static const Color cardShadowDark = Color(0x1A000000);
}
