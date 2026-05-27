class TopicProgress {
  final String topicId;
  final int score;
  final String status; // 'mastered', 'learning', 'new'
  final int practiceCount;
  final DateTime? lastPracticeAt;
  final DateTime? nextReviewAt;

  const TopicProgress({
    required this.topicId,
    required this.score,
    required this.status,
    this.practiceCount = 0,
    this.lastPracticeAt,
    this.nextReviewAt,
  });

  TopicProgress copyWith({
    String? topicId,
    int? score,
    String? status,
    int? practiceCount,
    DateTime? lastPracticeAt,
    DateTime? nextReviewAt,
  }) =>
      TopicProgress(
        topicId: topicId ?? this.topicId,
        score: score ?? this.score,
        status: status ?? this.status,
        practiceCount: practiceCount ?? this.practiceCount,
        lastPracticeAt: lastPracticeAt ?? this.lastPracticeAt,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      );

  factory TopicProgress.fromJson(Map<String, dynamic> json) => TopicProgress(
        topicId: json['topicId'] as String,
        score: (json['score'] as num).toInt(),
        status: json['status'] as String,
        practiceCount: (json['practiceCount'] as num?)?.toInt() ?? 0,
        lastPracticeAt: json['lastPracticeAt'] != null
            ? DateTime.parse(json['lastPracticeAt'] as String)
            : null,
        nextReviewAt: json['nextReviewAt'] != null
            ? DateTime.parse(json['nextReviewAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'topicId': topicId,
        'score': score,
        'status': status,
        'practiceCount': practiceCount,
        'lastPracticeAt': lastPracticeAt?.toIso8601String(),
        'nextReviewAt': nextReviewAt?.toIso8601String(),
      };
}

class PracticeSession {
  final String id;
  final String topicId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int score;
  final String? feedback;

  const PracticeSession({
    required this.id,
    required this.topicId,
    required this.startedAt,
    this.completedAt,
    required this.score,
    this.feedback,
  });

  factory PracticeSession.fromJson(Map<String, dynamic> json) => PracticeSession(
        id: json['id'] as String,
        topicId: json['topicId'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        score: (json['score'] as num).toInt(),
        feedback: json['feedback'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topicId': topicId,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'score': score,
        'feedback': feedback,
      };
}
