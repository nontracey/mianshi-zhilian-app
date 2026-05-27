class Topic {
  final String id;
  final String domain;
  final String category;
  final String? group;
  final String title;
  final String summary;
  final List<String> tags;
  final int difficulty;
  final int estimatedMinutes;
  final int order;
  final int recommendWeight;
  final List<LearningCard> learningCards;
  final List<String> recallPrompts;
  final Rubric? rubric;
  final String? updatedAt;

  const Topic({
    required this.id,
    required this.domain,
    required this.category,
    this.group,
    required this.title,
    required this.summary,
    this.tags = const [],
    this.difficulty = 1,
    this.estimatedMinutes = 15,
    this.order = 0,
    this.recommendWeight = 50,
    this.learningCards = const [],
    this.recallPrompts = const [],
    this.rubric,
    this.updatedAt,
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
        id: json['id'] as String? ?? '',
        domain: json['domain'] as String? ?? '',
        category: json['category'] as String? ?? '',
        group: json['group'] as String?,
        title: json['title'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
        estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 15,
        order: (json['order'] as num?)?.toInt() ?? 0,
        recommendWeight: (json['recommendWeight'] as num?)?.toInt() ?? 50,
        learningCards: (json['learningCards'] as List<dynamic>?)
                ?.map((e) => LearningCard.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        recallPrompts: (json['recallPrompts'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        rubric: json['rubric'] != null
            ? Rubric.fromJson(json['rubric'] as Map<String, dynamic>)
            : null,
        updatedAt: json['updatedAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'domain': domain,
        'category': category,
        if (group != null) 'group': group,
        'title': title,
        'summary': summary,
        'tags': tags,
        'difficulty': difficulty,
        'estimatedMinutes': estimatedMinutes,
        'order': order,
        'recommendWeight': recommendWeight,
        'learningCards': learningCards.map((e) => e.toJson()).toList(),
        'recallPrompts': recallPrompts,
        if (rubric != null) 'rubric': rubric!.toJson(),
        'updatedAt': updatedAt,
      };

  String get topicPath {
    // id like "java.jvm.runtime-data-area" → "java/jvm-runtime-data-area"
    return '$domain/${id.replaceFirst('$domain.', '')}';
  }

  /// Alias getters for compatibility
  String get domainId => domain;
  String get categoryId => category;
  bool get highFrequency => recommendWeight >= 80;
}

class LearningCard {
  final String type; // explain, code, animation, table, interview
  final String title;
  final String content;
  final String? asset;
  final String? fallback;

  const LearningCard({
    required this.type,
    required this.title,
    required this.content,
    this.asset,
    this.fallback,
  });

  factory LearningCard.fromJson(Map<String, dynamic> json) => LearningCard(
        type: json['type'] as String? ?? 'explain',
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        asset: json['asset'] as String?,
        fallback: json['fallback'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'content': content,
        if (asset != null) 'asset': asset,
        if (fallback != null) 'fallback': fallback,
      };
}

class Rubric {
  final List<String> mustHave;
  final List<String> commonMistakes;

  const Rubric({
    this.mustHave = const [],
    this.commonMistakes = const [],
  });

  factory Rubric.fromJson(Map<String, dynamic> json) => Rubric(
        mustHave: (json['mustHave'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        commonMistakes: (json['commonMistakes'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'mustHave': mustHave,
        'commonMistakes': commonMistakes,
      };
}
