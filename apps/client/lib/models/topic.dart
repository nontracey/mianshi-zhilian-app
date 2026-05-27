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
  final List<RecallPrompt> recallPrompts;
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
    tags:
        (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
        [],
    difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
    estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 15,
    order: (json['order'] as num?)?.toInt() ?? 0,
    recommendWeight: (json['recommendWeight'] as num?)?.toInt() ?? 50,
    learningCards:
        (json['learningCards'] as List<dynamic>?)
            ?.map((e) => LearningCard.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    recallPrompts: _parseRecallPrompts(json['recallPrompts']),
    rubric: json['rubric'] != null
        ? Rubric.fromJson(json['rubric'] as Map<String, dynamic>)
        : null,
    updatedAt: json['updatedAt'] as String?,
  );

  /// 兼容处理：recallPrompts 可能是 String[] 或 Object[]
  static List<RecallPrompt> _parseRecallPrompts(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    return raw.map((e) {
      if (e is String) {
        return RecallPrompt(id: '', prompt: e, mode: 'text');
      }
      if (e is Map<String, dynamic>) {
        return RecallPrompt.fromJson(e);
      }
      return RecallPrompt(id: '', prompt: e.toString(), mode: 'text');
    }).toList();
  }

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
    'recallPrompts': recallPrompts.map((e) => e.toJson()).toList(),
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

class RecallPrompt {
  final String id;
  final String prompt;
  final String mode; // text, code, voice
  final int? expectedMinutes;
  final int? difficulty;

  const RecallPrompt({
    required this.id,
    required this.prompt,
    this.mode = 'text',
    this.expectedMinutes,
    this.difficulty,
  });

  factory RecallPrompt.fromJson(Map<String, dynamic> json) => RecallPrompt(
    id: json['id'] as String? ?? '',
    prompt: json['prompt'] as String? ?? '',
    mode: json['mode'] as String? ?? 'text',
    expectedMinutes: (json['expectedMinutes'] as num?)?.toInt(),
    difficulty: (json['difficulty'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'mode': mode,
    if (expectedMinutes != null) 'expectedMinutes': expectedMinutes,
    if (difficulty != null) 'difficulty': difficulty,
  };
}

class LearningCard {
  final String
  type; // explain, code, animation, diagram, table, interview, checklist, interviewAnswer
  final String title;
  final String content;
  final String? asset;
  final String? fallback;
  final List<String> items; // for checklist type

  const LearningCard({
    required this.type,
    required this.title,
    required this.content,
    this.asset,
    this.fallback,
    this.items = const [],
  });

  factory LearningCard.fromJson(Map<String, dynamic> json) => LearningCard(
    type: json['type'] as String? ?? 'explain',
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    asset: json['asset'] as String?,
    fallback: json['fallback'] as String?,
    items:
        (json['items'] as List<dynamic>?)?.map((e) => e as String).toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'content': content,
    if (asset != null) 'asset': asset,
    if (fallback != null) 'fallback': fallback,
    if (items.isNotEmpty) 'items': items,
  };
}

class Rubric {
  final List<String> mustHave;
  final List<String> goodToHave;
  final List<String> commonMistakes;
  final Map<String, int>? scoreWeights;

  const Rubric({
    this.mustHave = const [],
    this.goodToHave = const [],
    this.commonMistakes = const [],
    this.scoreWeights,
  });

  factory Rubric.fromJson(Map<String, dynamic> json) => Rubric(
    mustHave:
        (json['mustHave'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    goodToHave:
        (json['goodToHave'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    commonMistakes:
        (json['commonMistakes'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    scoreWeights: (json['scoreWeights'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    ),
  );

  Map<String, dynamic> toJson() => {
    'mustHave': mustHave,
    'goodToHave': goodToHave,
    'commonMistakes': commonMistakes,
    if (scoreWeights != null) 'scoreWeights': scoreWeights,
  };
}
