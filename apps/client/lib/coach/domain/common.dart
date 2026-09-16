/// coach 领域公共类型与枚举。
///
/// 设计约束（来自改造计划 §9、§11）：
/// - 所有业务实体都通过 [ProfileId] 或父项归属到某一个本地档案，
///   单用户首版也保留该边界，避免未来切换档案时混淆经历或成绩。
/// - 本文件不依赖 Flutter 渲染，纯 Dart，便于无模型环境下单元测试。
library;

import 'package:uuid/uuid.dart';

/// 本地档案 ID。每个用户/设备档案相互独立，个人事实与作答不跨档案复用。
typedef ProfileId = String;

/// 目标 JD ID。
typedef GoalId = String;

/// 能力要求 ID。
typedef RequirementId = String;

/// 知识项 ID（App 分配的稳定 UUID，模型只能建议命名/别名）。
typedef KnowledgeItemId = String;

/// 简历版本 ID。
typedef ResumeId = String;

/// 简历主张 ID。
typedef ClaimId = String;

/// 项目 ID。
typedef ProjectId = String;

/// 会话 ID。
typedef SessionId = String;

/// 消息 ID。
typedef MessageId = String;

/// 回测考点 ID。
typedef ReviewPointId = String;

/// 评估事件 ID。
typedef AssessmentEventId = String;

/// 计划 ID。
typedef DailyPlanId = String;

/// 来源/分块 ID（RAG 用，首版仅占位，检索增强后续接入）。
typedef SourceId = String;
typedef ChunkId = String;

/// 可注入的时钟，便于测试固定“当前时间”。
abstract class Clock {
  DateTime now();
}

/// 系统时钟，生产环境使用。
class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

/// 固定时钟，测试用。
class FixedClock implements Clock {
  final DateTime _fixed;
  const FixedClock(this._fixed);
  @override
  DateTime now() => _fixed;
}

/// ID 生成工厂。默认使用 uuid；测试可注入确定性实现。
typedef IdFactory = String Function();

class IdGenerator {
  IdGenerator({IdFactory? factory})
    : _factory = factory ?? (() => const Uuid().v4());
  final IdFactory _factory;

  String next() => _factory();

  /// 确定性实现，用于测试，避免依赖随机 uuid。
  factory IdGenerator.deterministic() {
    var counter = 0;
    return IdGenerator(
      factory: () => 'id-${(counter++).toString().padLeft(8, '0')}',
    );
  }
}

/// 教练模式。三种模式共用一个对话与记录界面（§1、§5）。
enum SessionMode {
  /// 学习：先讲解，允许打断答疑；"不会"补讲不记 fail。
  learning,

  /// 回测：短问题、真实原答、最多一层中性追问；结果用描述而非精确分数。
  review,

  /// 模拟：一轮问答后再决定下一问；评分与教学默认结束后展示。
  interview,
}

extension SessionModeX on SessionMode {
  /// l10n key。文案由 UI 层翻译（纯 Dart 层不持有用户可见文案）。
  String get l10nKey {
    switch (this) {
      case SessionMode.learning:
        return 'coach_mode_learning';
      case SessionMode.review:
        return 'coach_mode_review';
      case SessionMode.interview:
        return 'coach_mode_interview';
    }
  }

  /// l10n key：该模式的说明文案。
  String get descriptionL10nKey {
    switch (this) {
      case SessionMode.learning:
        return 'coach_mode_learning_desc';
      case SessionMode.review:
        return 'coach_mode_review_desc';
      case SessionMode.interview:
        return 'coach_mode_interview_desc';
    }
  }

  /// 用于提示词内部的英文标识（非 UI 文案）。
  String get promptToken => name;
}

/// JD 要求类型（§6.2）。
enum RequirementType { responsibility, hardRequirement, niceToHave, capability }

/// 要求重要度（1-3，3 最高）。
enum Importance { low, medium, high }

/// 简历主张确认状态（§6.9）。
enum ClaimStatus {
  /// 信息未写明，待用户确认，不能从 JD 补成已做事实。
  pending,
  confirmed,
  disputed,
}

/// 回测考点状态（§9.4）。
/// UI 用“未学/已学待回测/能独立回答/能应用/稳定掌握”解释。
enum ReviewStatus {
  unseen,
  exposed,
  recall,
  applied,
  mastered,

  /// 知识发生实质变化，标记待重新学习。
  stale,
}

extension ReviewStatusX on ReviewStatus {
  /// l10n key。UI 用「未学/已学待回测/能独立回答/能应用/稳定掌握」解释。
  String get l10nKey {
    switch (this) {
      case ReviewStatus.unseen:
        return 'coach_review_status_unseen';
      case ReviewStatus.exposed:
        return 'coach_review_status_exposed';
      case ReviewStatus.recall:
        return 'coach_review_status_recall';
      case ReviewStatus.applied:
        return 'coach_review_status_applied';
      case ReviewStatus.mastered:
        return 'coach_review_status_mastered';
      case ReviewStatus.stale:
        return 'coach_review_status_stale';
    }
  }
}

/// 评估/证据有效性（§9.3、§9.4）。
enum EvidenceValidity {
  /// 已接受为有效证据。
  accepted,

  /// 原答缺失/引用无效/标准存疑/结构错误，不推进掌握状态。
  pending,

  /// 用户标记评价有误，需重新评估。
  disputed,
}

/// 回测结果类别（§9.4，用描述而非精确分数）。
enum ReviewOutcome {
  /// 独立答对。
  independentPass,

  /// 需要补强。
  needsReinforcement,

  /// 提示后完成（不积累独立通过）。
  hintCompleted,
}

/// 内部运行状态（§7.3）。
enum RuntimeStatus {
  idle,
  generating,
  toolRunning,
  waitingUser,
  paused,
  failed,
  completed,
}

/// 回测阶梯（天）。首个独立通过 3 天，后续依次 7/14/30/60/90（§9.5）。
const List<int> spacedLadderDays = [3, 7, 14, 30, 60, 90];

/// 每个知识点最多 8 个回测考点（§9.4）。
const int maxReviewPointsPerKnowledge = 8;

/// 单轮最多 6 次工具调用（§7.3）。
const int maxToolCallsPerTurn = 6;

/// Compare calendar dates in the device's current timezone.
bool sameLocalDay(DateTime? a, DateTime b) {
  if (a == null) return false;
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
