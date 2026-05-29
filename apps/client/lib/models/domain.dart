import 'package:flutter/material.dart';

class Domain {
  final String id;
  final String title;
  final String description;
  final String? icon;
  final String? themeColor;
  final String? accentColor;
  final List<Category> categories;
  final int topicCount;
  final String? updatedAt;
  final Color color;

  const Domain({
    required this.id,
    required this.title,
    required this.description,
    this.icon,
    this.themeColor,
    this.accentColor,
    this.categories = const [],
    this.topicCount = 0,
    this.updatedAt,
    this.color = const Color(0xFF0A2540),
  });

  factory Domain.fromJson(Map<String, dynamic> json) {
    // 从 manifest 的 domains 数组中读取
    final id = json['id'] as String? ?? '';
    return Domain(
      id: id,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String?,
      themeColor: json['themeColor'] as String?,
      accentColor: json['accentColor'] as String?,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => Category.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      topicCount: (json['topicCount'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] as String?,
      color: _domainColor(id, json['themeColor'] as String?),
    );
  }

  /// 解析主题色：优先使用数据中的 themeColor，否则按领域 ID 兜底
  static Color _domainColor(String id, String? themeColorHex) {
    if (themeColorHex != null && themeColorHex.isNotEmpty) {
      final hex = themeColorHex.replaceFirst('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    }
    return switch (id) {
      'java' => const Color(0xFF0A2540),
      'agent' => const Color(0xFF00A6C8),
      'algorithm' => const Color(0xFF10B981),
      _ => const Color(0xFF0A2540),
    };
  }
}

class Category {
  final String id;
  final String title;
  final String? description;
  final int order;
  final List<String> topics; // 路径列表，如 "topics/java/jvm-runtime-data-area.json"
  final List<String> prerequisites;

  const Category({
    required this.id,
    required this.title,
    this.description,
    this.order = 0,
    this.topics = const [],
    this.prerequisites = const [],
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        order: (json['order'] as num?)?.toInt() ?? 0,
        topics: (json['topics'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        prerequisites: (json['prerequisites'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}
