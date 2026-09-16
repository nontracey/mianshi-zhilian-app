/// 作答证据归约（§9.4 评分与状态规则）。
///
/// 模型只提交允许的评价字段；App 持有“标准答案是否展示、当前会话是否刚教学、
/// 是否跨日”等权威信息，不信任模型自报。归约结果交给 [ReviewScheduler] 应用。
library;

import '../domain/common.dart';
import '../domain/evidence.dart';

/// 调度器触发类型（连接归约结论与间隔规则）。
enum SchedulerTrigger {
  learningComplete,
  reTeachOnly,
  coreError,
  coreGapOrHint,
  independentPass,
  sameDayPractice,
}

/// 归约结论。
class EvidenceConclusion {
  const EvidenceConclusion({
    required this.trigger,
    required this.spaced,
    required this.hintUsed,
    required this.validity,
    required this.advanceAllowed,
    this.outcome,
  });

  final SchedulerTrigger trigger;

  /// 真正到期、跨日、且非刚教学，可作为间隔通过。
  final bool spaced;
  final bool hintUsed;
  final EvidenceValidity validity;

  /// 为 false 时不推进状态（pending/disputed）。
  final bool advanceAllowed;
  final ReviewOutcome? outcome;
}

/// App 持有的权威上下文，模型不可篡改。
class AssessmentContext {
  const AssessmentContext({
    required this.hasValidAnswer,
    required this.hasValidReference,
    required this.rubricValid,
    required this.wasAnswerShown,
    required this.justTaughtSamePoint,
    required this.sameDay,
  });

  /// 原答存在（answerMessageIds 非空）。
  final bool hasValidAnswer;

  /// 引用有效（sourceRevisionIds 非空或规则允许）。
  final bool hasValidReference;

  /// 评分标准版本已知。
  final bool rubricValid;

  /// 标准答案是否展示（App 知道，不信任模型自报）。
  final bool wasAnswerShown;

  /// 同一会话/同一考点刚刚做过教学。
  final bool justTaughtSamePoint;

  /// 与上次教学/评估是否同一本地自然日。
  final bool sameDay;
}

/// 证据归约器：把一次评估事件 + App 权威上下文，归约为调度触发。
class EvidenceReducer {
  const EvidenceReducer();

  EvidenceConclusion reduce(AssessmentEvent event, AssessmentContext ctx) {
    // 缺失原答/引用/标准存疑/结构错误 → pending，不推进掌握状态（§9.4）。
    if (!ctx.hasValidAnswer ||
        !ctx.hasValidReference ||
        !ctx.rubricValid ||
        event.validity == EvidenceValidity.pending ||
        event.validity == EvidenceValidity.disputed) {
      return const EvidenceConclusion(
        trigger: SchedulerTrigger.reTeachOnly,
        spaced: false,
        hintUsed: false,
        validity: EvidenceValidity.pending,
        advanceAllowed: false,
      );
    }

    // 提示程度：答案已展示或 hintLevel 非 none，都视为已提示（§9.4）。
    final hintUsed = event.hintLevel != 'none' || ctx.wasAnswerShown;
    final justTaught = ctx.justTaughtSamePoint;
    final independent = event.independentEligible && !hintUsed && !justTaught;
    final spaced = event.isSpacedEligible && !justTaught && !ctx.sameDay;

    // 学习模式：“明白了/理解检查”只保存覆盖，不记独立通过（§3.3、§9.4）。
    if (event.assessmentMode == SessionMode.learning) {
      return EvidenceConclusion(
        trigger: SchedulerTrigger.learningComplete,
        spaced: false,
        hintUsed: hintUsed,
        validity: EvidenceValidity.accepted,
        advanceAllowed: true,
        outcome: ReviewOutcome.hintCompleted,
      );
    }

    // 回测 / 模拟。
    if (event.result == ReviewOutcome.independentPass && independent) {
      return EvidenceConclusion(
        trigger: spaced
            ? SchedulerTrigger.independentPass
            : SchedulerTrigger.sameDayPractice,
        spaced: spaced,
        hintUsed: false,
        validity: EvidenceValidity.accepted,
        advanceAllowed: true,
        outcome: ReviewOutcome.independentPass,
      );
    }
    // 带提示的“通过”不算独立通过，按缺口处理（§9.4）。
    if (event.result == ReviewOutcome.independentPass && !independent) {
      return EvidenceConclusion(
        trigger: SchedulerTrigger.coreGapOrHint,
        spaced: false,
        hintUsed: true,
        validity: EvidenceValidity.accepted,
        advanceAllowed: true,
        outcome: ReviewOutcome.hintCompleted,
      );
    }
    if (event.result == ReviewOutcome.needsReinforcement) {
      return EvidenceConclusion(
        trigger: SchedulerTrigger.coreError,
        spaced: false,
        hintUsed: hintUsed,
        validity: EvidenceValidity.accepted,
        advanceAllowed: true,
        outcome: ReviewOutcome.needsReinforcement,
      );
    }
    return EvidenceConclusion(
      trigger: SchedulerTrigger.coreGapOrHint,
      spaced: false,
      hintUsed: hintUsed,
      validity: EvidenceValidity.accepted,
      advanceAllowed: true,
      outcome: ReviewOutcome.hintCompleted,
    );
  }
}
