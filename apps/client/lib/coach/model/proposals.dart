/// 模型提交的结构化提案模型（§7.5 内部工具契约）。
///
/// 模型只能提交允许的评价/知识字段，不能直接填入全部权威字段
/// （权威字段如是否独立通过、是否跨日由 [EvidenceReducer] 与 [ReviewScheduler] 决定）。
library;

import 'dart:convert';

/// A model turn is returned as one constrained JSON envelope. The assistant
/// text is always preserved, while lesson and assessment proposals are only
/// applied after local validation against the current session and messages.
class CoachTurnProposal {
  CoachTurnProposal({
    required this.assistantText,
    this.lesson,
    this.assessment,
    this.shouldCompleteSession = false,
    this.questionReviewPointId,
  });

  final String assistantText;
  final LessonProgressProposal? lesson;
  final AssessmentProposal? assessment;
  final bool shouldCompleteSession;
  final String? questionReviewPointId;

  static CoachTurnProposal? tryParse(String raw) {
    final payload = _extractJsonObject(raw);
    if (payload == null) return null;
    try {
      final json = jsonDecode(payload);
      if (json is! Map) return null;
      final map = Map<String, dynamic>.from(json);
      final text = (map['assistantText'] ?? map['message'])?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return CoachTurnProposal(
        assistantText: text,
        lesson: map['lesson'] is Map
            ? LessonProgressProposal.fromJson(
                Map<String, dynamic>.from(map['lesson'] as Map),
              )
            : null,
        assessment: map['assessment'] is Map
            ? AssessmentProposal.fromJson(
                Map<String, dynamic>.from(map['assessment'] as Map),
              )
            : null,
        shouldCompleteSession: map['shouldCompleteSession'] == true,
        questionReviewPointId: map['questionReviewPointId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class LessonProgressProposal {
  LessonProgressProposal({
    required this.taughtScope,
    this.openQuestions = const [],
    this.nextPosition,
    this.learningComplete = false,
  });

  final String taughtScope;
  final List<String> openQuestions;
  final String? nextPosition;
  final bool learningComplete;

  factory LessonProgressProposal.fromJson(Map<String, dynamic> json) =>
      LessonProgressProposal(
        taughtScope: json['taughtScope']?.toString().trim() ?? '',
        openQuestions: _stringList(json['openQuestions']),
        nextPosition: json['nextPosition']?.toString(),
        learningComplete: json['learningComplete'] == true,
      );

  List<String> validate() => [
    if (taughtScope.isEmpty) 'taughtScope 为空',
    if (openQuestions.length > 8) 'openQuestions 超过上限',
  ];
}

String? _extractJsonObject(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final fenced = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    ).firstMatch(text);
    if (fenced == null) return null;
    text = fenced.group(1)!.trim();
  }
  if (!text.startsWith('{') || !text.endsWith('}')) return null;
  return text;
}

List<String> _stringList(Object? value) => value is List
    ? value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
    : const [];

/// 评估提案。指向已有问题和原答，提交实际验收维度、结果与理由。
class AssessmentProposal {
  AssessmentProposal({
    required this.reviewPointId,
    required this.questionMessageId,
    required this.answerMessageIds,
    required this.askedDimensions,
    required this.result,
    this.hintLevel = 'none',
    this.rationale,
    this.sourceRevisionIds = const [],
    this.confidence,
  });

  /// 关联的回测考点 ID。
  final String reviewPointId;

  /// 提问消息 ID（App 已保存的原答问题）。
  final String questionMessageId;

  /// 实际原答消息 ID 列表（主答 + 中性追问答）。
  final List<String> answerMessageIds;

  /// 实际问过的维度（mechanism/boundary/example/...）。
  final List<String> askedDimensions;

  /// 结果：'independentPass' / 'needsReinforcement' / 'hintCompleted'。
  final String result;

  /// 提示程度：'none' / 'partial' / 'full'。
  final String hintLevel;

  /// 评价理由（模型填写，需可被用户标记有误）。
  final String? rationale;

  /// 引用的来源 revision ID。
  final List<String> sourceRevisionIds;

  /// 模型自评置信度（0-1），不表示事实正确。
  final double? confidence;

  static const List<String> validResults = [
    'independentPass',
    'needsReinforcement',
    'hintCompleted',
  ];

  static const List<String> validHintLevels = ['none', 'partial', 'full'];

  factory AssessmentProposal.fromJson(Map<String, dynamic> json) =>
      AssessmentProposal(
        reviewPointId: json['reviewPointId']?.toString() ?? '',
        questionMessageId: json['questionMessageId']?.toString() ?? '',
        answerMessageIds: _stringList(json['answerMessageIds']),
        askedDimensions: _stringList(json['askedDimensions']),
        result: json['result']?.toString() ?? '',
        hintLevel: json['hintLevel']?.toString() ?? 'none',
        rationale: json['rationale']?.toString(),
        sourceRevisionIds: _stringList(json['sourceRevisionIds']),
        confidence: json['confidence'] is num
            ? (json['confidence'] as num).toDouble()
            : null,
      );

  /// 基本字段校验，返回错误信息列表（空表示合法）。
  List<String> validate() {
    final errors = <String>[];
    if (!validResults.contains(result)) {
      errors.add('result 非法: $result');
    }
    if (!validHintLevels.contains(hintLevel)) {
      errors.add('hintLevel 非法: $hintLevel');
    }
    if (questionMessageId.isEmpty) errors.add('questionMessageId 为空');
    if (answerMessageIds.isEmpty) errors.add('answerMessageIds 为空');
    if (reviewPointId.isEmpty) errors.add('reviewPointId 为空');
    if (askedDimensions.isEmpty) errors.add('askedDimensions 为空');
    if (askedDimensions.length > 8) errors.add('askedDimensions 超过上限');
    if (confidence != null && (confidence! < 0 || confidence! > 1)) {
      errors.add('confidence 超出 0-1');
    }
    return errors;
  }
}

/// 知识卡片提案。提交带引用的知识草稿，由服务层校验来源后入库。
class KnowledgeCardProposal {
  KnowledgeCardProposal({
    required this.knowledgeItemId,
    required this.title,
    required this.core,
    this.mechanism,
    this.example,
    this.commonMistake,
    this.applicableScope,
    this.reviewPoints = const [],
    this.citations = const [],
  });

  final String knowledgeItemId;
  final String title;

  /// 核心解释。
  final String core;

  /// 机制说明。
  final String? mechanism;

  /// 例子。
  final String? example;

  /// 常见误区。
  final String? commonMistake;

  /// 适用边界。
  final String? applicableScope;

  /// 可独立检验的少量考点。
  final List<String> reviewPoints;

  /// 引用（source/chunk ID），模型只能引用检索器实际返回的 ID。
  final List<String> citations;
}

/// 计划变更提案（§9.6、§9.7）。只允许变更顺序/范围/数量/时间/模式。
class PlanChangeProposal {
  PlanChangeProposal({
    required this.action,
    this.scope,
    this.minutes,
    this.quantity,
    this.rationale,
  });

  /// 'reorder' / 'skip' / 'reduce' / 'add' / 'extend' / 'changeMode'。
  final String action;
  final String? scope;
  final int? minutes;
  final int? quantity;
  final String? rationale;

  static const List<String> validActions = [
    'reorder',
    'skip',
    'reduce',
    'add',
    'extend',
    'changeMode',
  ];

  List<String> validate() {
    final errors = <String>[];
    if (!validActions.contains(action)) errors.add('action 非法: $action');
    return errors;
  }
}
