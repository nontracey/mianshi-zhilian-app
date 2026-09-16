/// 间隔回测调度（§9.5 回测调度规则）。
///
/// 纯 Dart、可注入时钟。把 [EvidenceReducer] 的结论应用到 [ReviewState]，
/// 计算下次到期日与状态投影。不调用模型。
library;

import '../domain/common.dart';
import '../domain/evidence.dart';
import 'evidence_reducer.dart';

/// 间隔回测调度器。
class ReviewScheduler {
  const ReviewScheduler();

  /// 应用一次评估结论，返回新的回测状态（原对象不可变）。
  /// 若 `conclusion.advanceAllowed == false`（pending/disputed），原样返回，不推进。
  ReviewState apply({
    required ReviewState current,
    required EvidenceConclusion conclusion,
    required Clock clock,
  }) {
    if (!conclusion.advanceAllowed) return current;

    final now = _startOfDay(clock.now());

    switch (conclusion.trigger) {
      case SchedulerTrigger.reTeachOnly:
        // 纯补讲：不抹掉已存在的逾期日期，不刷成绩（§9.5）。
        return current;

      case SchedulerTrigger.learningComplete:
        // 首次学习完成：建首次待测，默认次日开始可测；不记独立通过（§9.5）。
        if (current.status == ReviewStatus.unseen ||
            current.status == ReviewStatus.stale) {
          final due = _addDays(now, 1);
          return current.copyWith(
            status: ReviewStatus.exposed,
            firstDueAt: current.firstDueAt ?? due,
            nextDueAt: due,
            lastTaughtAt: now,
          );
        }
        return current.copyWith(lastTaughtAt: now);

      case SchedulerTrigger.coreError:
        // 核心错误：1 天后回测，清空该考点连续通过阶梯（§9.5）。
        return current.copyWith(
          status: ReviewStatus.exposed,
          consecutiveIndependentPasses: 0,
          intervalStep: 0,
          consecutiveWeaknesses: current.consecutiveWeaknesses + 1,
          nextDueAt: _addDays(now, 1),
          lastAssessedAt: now,
        );

      case SchedulerTrigger.coreGapOrHint:
        // 核心缺口或提示后完成：1–2 天后；清空连续通过阶梯（§9.5，取 1 天默认）。
        return current.copyWith(
          status: ReviewStatus.exposed,
          intervalStep: 0,
          consecutiveWeaknesses: current.consecutiveWeaknesses + 1,
          consecutiveIndependentPasses: 0,
          nextDueAt: _addDays(now, 1),
          lastAssessedAt: now,
        );

      case SchedulerTrigger.independentPass:
        if (!conclusion.spaced || !current.canReview(clock.now())) {
          return current;
        }
        final passes = current.consecutiveIndependentPasses + 1;
        if (passes == 1) {
          return current.copyWith(
            status: ReviewStatus.recall,
            consecutiveIndependentPasses: passes,
            consecutiveWeaknesses: 0,
            nextDueAt: _addDays(now, spacedLadderDays[0]),
            lastAssessedAt: now,
          );
        }
        final step = (current.intervalStep + 1).clamp(
          0,
          spacedLadderDays.length - 1,
        );
        final mastered =
            step == spacedLadderDays.length - 1 &&
            passes >= 2 &&
            !current.pendingDispute;
        return current.copyWith(
          status: mastered ? ReviewStatus.mastered : ReviewStatus.recall,
          consecutiveIndependentPasses: passes,
          consecutiveWeaknesses: 0,
          intervalStep: step,
          nextDueAt: _addDays(now, spacedLadderDays[step]),
          lastAssessedAt: now,
        );

      case SchedulerTrigger.sameDayPractice:
        // 同日重复作答或刚教学后再答：保留练习，不算 spaced，也不提前升阶（§9.5）。
        return current.copyWith(lastAssessedAt: now);
    }
  }

  /// 把知识标记有过期范围待学（§6.6）。
  ReviewState markStale(ReviewState current) =>
      current.copyWith(status: ReviewStatus.stale);

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);
}
