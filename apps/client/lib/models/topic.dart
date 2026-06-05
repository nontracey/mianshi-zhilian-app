class FollowUpQuestion {
  final String question;
  final String answer;
  final int difficulty;
  final List<String> hints;

  const FollowUpQuestion({
    required this.question,
    required this.answer,
    this.difficulty = 2,
    this.hints = const [],
  });

  factory FollowUpQuestion.fromJson(Map<String, dynamic> json) =>
      FollowUpQuestion(
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        difficulty: (json['difficulty'] as num?)?.toInt() ?? 2,
        hints:
            (json['hints'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
    'question': question,
    'answer': answer,
    'difficulty': difficulty,
    if (hints.isNotEmpty) 'hints': hints,
  };
}

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
  final List<FollowUpQuestion> followUps;
  final List<String> prerequisites;
  final String?
  status; // production / staging / draft; legacy test maps to staging
  final String? interviewFrequency; // high / medium / low
  final String? interviewerFocus;
  final String? phase;
  final String? updatedAt;
  final String? leetcodeUrl;

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
    this.followUps = const [],
    this.prerequisites = const [],
    this.status,
    this.interviewFrequency,
    this.interviewerFocus,
    this.phase,
    this.updatedAt,
    this.leetcodeUrl,
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
    followUps: _parseFollowUps(json),
    prerequisites:
        (json['prerequisites'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    status: json['status'] as String?,
    interviewFrequency: json['interviewFrequency'] as String?,
    interviewerFocus: json['interviewerFocus'] as String?,
    phase: json['phase'] as String?,
    updatedAt: json['updatedAt'] as String?,
    leetcodeUrl: json['leetcodeUrl'] as String?,
  );

  String get normalizedStatus {
    final value = status?.trim().toLowerCase();
    return switch (value) {
      null || '' || 'production' => 'production',
      'test' || 'staging' => 'staging',
      'draft' => 'draft',
      _ => 'draft',
    };
  }

  bool get isProductionStatus => normalizedStatus == 'production';
  bool get isStagingStatus => normalizedStatus == 'staging';
  bool get isNonProductionStatus => status != null && !isProductionStatus;

  /// 解析追问列表：优先取顶层 followUps，否则从 interviewAnswer 卡片中提取 followUpQuestions
  static List<FollowUpQuestion> _parseFollowUps(Map<String, dynamic> json) {
    // 优先取顶层 followUps
    final top = json['followUps'] as List<dynamic>?;
    if (top != null && top.isNotEmpty) {
      return top
          .map((e) => FollowUpQuestion.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // 兜底：从 interviewAnswer 类型的 learningCard 中提取 followUpQuestions
    final cards = json['learningCards'] as List<dynamic>?;
    if (cards == null) return [];
    for (final card in cards) {
      if (card is Map<String, dynamic> &&
          card['type'] == 'interviewAnswer' &&
          card['followUpQuestions'] is List) {
        return (card['followUpQuestions'] as List<dynamic>)
            .map((e) => FollowUpQuestion.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

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
    if (followUps.isNotEmpty)
      'followUps': followUps.map((e) => e.toJson()).toList(),
    if (prerequisites.isNotEmpty) 'prerequisites': prerequisites,
    if (status != null) 'status': status,
    if (interviewFrequency != null) 'interviewFrequency': interviewFrequency,
    if (interviewerFocus != null) 'interviewerFocus': interviewerFocus,
    if (phase != null) 'phase': phase,
    'updatedAt': updatedAt,
    if (leetcodeUrl != null) 'leetcodeUrl': leetcodeUrl,
  };

  String get topicPath {
    // id like "java.jvm.runtime-data-area" → "java/jvm-runtime-data-area"
    return '$domain/${id.replaceFirst('$domain.', '')}';
  }

  /// Alias getters for compatibility
  String get domainId => domain;
  String get categoryId => category;

  /// 面试频率：优先使用 interviewFrequency 字段，回退到 recommendWeight 判断
  bool get highFrequency =>
      interviewFrequency == 'high' || recommendWeight >= 80;

  /// 面试频率标签（返回 l10n key，UI 层使用 l10n.get() 获取显示文本）
  String? get interviewFrequencyLabel {
    if (interviewFrequency == 'high') return 'high_frequency';
    if (interviewFrequency == 'medium') return 'medium_freq';
    if (interviewFrequency == 'low') return 'low_freq';
    if (recommendWeight >= 80) return 'high_frequency';
    return null;
  }
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
  type; // explain, code, animation, diagram, svg, table, interview, checklist, interviewAnswer, compareTable
  final String title;
  final String content;
  final String? asset;
  final String? fallback;
  final String? svg; // 内联 SVG 字符串
  final String? svgPath; // SVG 资源路径
  final String? format; // 图表格式（如 mermaid）
  final String? caption; // 图片/动画说明
  final String? language; // 代码语言
  final List<String> items; // for checklist / diagram type
  final List<Map<String, dynamic>> highlights; // 代码行高亮
  final List<String> columns; // compareTable 表头
  final List<List<String>> rows; // compareTable 行数据

  const LearningCard({
    required this.type,
    required this.title,
    required this.content,
    this.asset,
    this.fallback,
    this.svg,
    this.svgPath,
    this.format,
    this.caption,
    this.language,
    this.items = const [],
    this.highlights = const [],
    this.columns = const [],
    this.rows = const [],
  });

  factory LearningCard.fromJson(Map<String, dynamic> json) => LearningCard(
    type: json['type'] as String? ?? 'explain',
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    asset: json['asset'] as String?,
    fallback: json['fallback'] as String?,
    svg: json['svg'] as String?,
    svgPath: json['svgPath'] as String?,
    format: json['format'] as String?,
    caption: json['caption'] as String?,
    language: json['language'] as String?,
    items:
        (json['items'] as List<dynamic>?)?.map((e) => e as String).toList() ??
        [],
    highlights:
        (json['highlights'] as List<dynamic>?)
            ?.map((e) => (e as Map<String, dynamic>))
            .toList() ??
        [],
    columns:
        (json['columns'] as List<dynamic>?)?.map((e) => e as String).toList() ??
        [],
    rows:
        (json['rows'] as List<dynamic>?)
            ?.map(
              (row) => (row as List<dynamic>).map((e) => e as String).toList(),
            )
            .toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'content': content,
    if (asset != null) 'asset': asset,
    if (fallback != null) 'fallback': fallback,
    if (svg != null) 'svg': svg,
    if (svgPath != null) 'svgPath': svgPath,
    if (format != null) 'format': format,
    if (caption != null) 'caption': caption,
    if (language != null) 'language': language,
    if (items.isNotEmpty) 'items': items,
    if (highlights.isNotEmpty) 'highlights': highlights,
    if (columns.isNotEmpty) 'columns': columns,
    if (rows.isNotEmpty) 'rows': rows,
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
