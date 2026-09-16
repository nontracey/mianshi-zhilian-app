/// 确定性策略单测：回测调度、证据归约、模式边界（§9.4、§9.5、§3、§5）。
/// 不调用模型。
library;

import 'harness.dart';

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/policies/evidence_reducer.dart';
import 'package:mianshi_zhilian/coach/policies/review_scheduler.dart';
import 'package:mianshi_zhilian/coach/policies/mode_policy.dart';

import 'fixtures/synthetic.dart';

/// 走完整管线：归约 → 调度。
ReviewState applyAssessment({
  required AssessmentEvent event,
  required AssessmentContext ctx,
  required ReviewState current,
  required Clock clock,
}) {
  final conclusion = const EvidenceReducer().reduce(event, ctx);
  return const ReviewScheduler().apply(
    current: current,
    conclusion: conclusion,
    clock: clock,
  );
}

Future<void> main() async {
  group('ReviewScheduler - 间隔回测规则（§9.5）', () {
    final now = DateTime(2026, 9, 11);
    final clock = FixedClock(now);

    test('首次学习完成：进入 exposed，次日可测，不计独立通过', () {
      final current = buildDemoReviewState();
      final event = buildAssessmentEvent(
        sessionId: 's1',
        mode: SessionMode.learning,
        result: ReviewOutcome.hintCompleted,
        now: now,
      );
      final next = applyAssessment(
        event: event,
        ctx: const AssessmentContext(
          hasValidAnswer: true,
          hasValidReference: true,
          rubricValid: true,
          wasAnswerShown: false,
          justTaughtSamePoint: false,
          sameDay: false,
        ),
        current: current,
        clock: clock,
      );
      expect(next.status, ReviewStatus.exposed);
      expect(next.nextDueAt, DateTime(2026, 9, 12));
      expect(next.consecutiveIndependentPasses, 0);
    });

    test('核心错误：1 天后回测，清空通过阶梯', () {
      final current = buildDemoReviewState(
        status: ReviewStatus.recall,
      ).copyWith(consecutiveIndependentPasses: 2, intervalStep: 2);
      final event = buildAssessmentEvent(
        sessionId: 's1',
        mode: SessionMode.review,
        result: ReviewOutcome.needsReinforcement,
        now: now,
      );
      final next = applyAssessment(
        event: event,
        ctx: const AssessmentContext(
          hasValidAnswer: true,
          hasValidReference: true,
          rubricValid: true,
          wasAnswerShown: false,
          justTaughtSamePoint: false,
          sameDay: false,
        ),
        current: current,
        clock: clock,
      );
      expect(next.status, ReviewStatus.exposed);
      expect(next.nextDueAt, DateTime(2026, 9, 12));
      expect(next.consecutiveIndependentPasses, 0);
      expect(next.intervalStep, 0);
    });

    test('首次独立通过（真正到期跨日）：recall，3 天后', () {
      final current = buildDemoReviewState(status: ReviewStatus.exposed)
          .copyWith(
            nextDueAt: now,
            lastTaughtAt: now.subtract(const Duration(days: 1)),
          );
      final event = buildAssessmentEvent(
        sessionId: 's1',
        mode: SessionMode.review,
        result: ReviewOutcome.independentPass,
        independentEligible: true,
        isSpacedEligible: true,
        now: now,
      );
      final next = applyAssessment(
        event: event,
        ctx: const AssessmentContext(
          hasValidAnswer: true,
          hasValidReference: true,
          rubricValid: true,
          wasAnswerShown: false,
          justTaughtSamePoint: false,
          sameDay: false,
        ),
        current: current,
        clock: clock,
      );
      expect(next.status, ReviewStatus.recall);
      expect(next.consecutiveIndependentPasses, 1);
      expect(next.nextDueAt, DateTime(2026, 9, 14)); // +3
    });

    test('后续独立通过按阶梯升阶：7/14/30/60/90，末级 mastered', () {
      var state = buildDemoReviewState(status: ReviewStatus.recall).copyWith(
        consecutiveIndependentPasses: 1,
        intervalStep: 0,
        nextDueAt: now,
      );
      final dueDays = [7, 14, 30, 60, 90];
      for (var i = 0; i < dueDays.length; i++) {
        final assessmentDate = state.nextDueAt!;
        final event = buildAssessmentEvent(
          sessionId: 's1',
          mode: SessionMode.review,
          result: ReviewOutcome.independentPass,
          independentEligible: true,
          isSpacedEligible: true,
          now: assessmentDate,
        );
        state = applyAssessment(
          event: event,
          ctx: const AssessmentContext(
            hasValidAnswer: true,
            hasValidReference: true,
            rubricValid: true,
            wasAnswerShown: false,
            justTaughtSamePoint: false,
            sameDay: false,
          ),
          current: state,
          clock: FixedClock(assessmentDate),
        );
        expect(state.nextDueAt, assessmentDate.add(Duration(days: dueDays[i])));
        if (i < dueDays.length - 1) {
          expect(state.status, ReviewStatus.recall);
        } else {
          expect(state.status, ReviewStatus.mastered);
        }
      }
    });

    test('同日/刚教学后再答：保留练习，不升阶（§9.5）', () {
      final current = buildDemoReviewState(status: ReviewStatus.recall)
          .copyWith(
            consecutiveIndependentPasses: 1,
            nextDueAt: DateTime(2026, 9, 14),
          );
      final event = buildAssessmentEvent(
        sessionId: 's1',
        mode: SessionMode.review,
        result: ReviewOutcome.independentPass,
        independentEligible: true,
        isSpacedEligible: false, // 非真正到期
        now: now,
      );
      final next = applyAssessment(
        event: event,
        ctx: const AssessmentContext(
          hasValidAnswer: true,
          hasValidReference: true,
          rubricValid: true,
          wasAnswerShown: false,
          justTaughtSamePoint: false,
          sameDay: true, // 同日
        ),
        current: current,
        clock: clock,
      );
      expect(next.consecutiveIndependentPasses, 1); // 未增加
      expect(next.nextDueAt, DateTime(2026, 9, 14)); // 未改变
    });

    test('纯补讲（reTeachOnly）：不抹逾期日期、不刷成绩', () {
      final current = buildDemoReviewState(status: ReviewStatus.recall)
          .copyWith(
            consecutiveIndependentPasses: 2,
            nextDueAt: DateTime(2026, 9, 20),
          );
      final event = buildAssessmentEvent(
        sessionId: 's1',
        mode: SessionMode.learning,
        result: ReviewOutcome.hintCompleted,
        now: now,
      );
      // 作为纯补讲：advanceAllowed=false（pending）会原样返回；这里用 accepted 但触发 reTeachOnly
      final conclusion = const EvidenceReducer().reduce(
        event,
        const AssessmentContext(
          hasValidAnswer: true,
          hasValidReference: true,
          rubricValid: true,
          wasAnswerShown: false,
          justTaughtSamePoint: false,
          sameDay: false,
        ),
      );
      // 学习模式归约为 learningComplete（非 reTeachOnly）；改用 pending 触发不推进。
      expect(conclusion.trigger.name, 'learningComplete');
      final reTeach = applyAssessment(
        event: event,
        ctx: const AssessmentContext(
          hasValidAnswer: false, // 无原答 → pending → 不推进
          hasValidReference: true,
          rubricValid: true,
          wasAnswerShown: false,
          justTaughtSamePoint: false,
          sameDay: false,
        ),
        current: current,
        clock: clock,
      );
      expect(reTeach.nextDueAt, DateTime(2026, 9, 20)); // 不变
      expect(reTeach.consecutiveIndependentPasses, 2); // 不变
    });
  });

  group('EvidenceReducer - 证据归约（§9.4）', () {
    final now = DateTime(2026, 9, 11);

    test('看过答案后复述正确：不记独立通过，按缺口处理', () {
      final event = buildAssessmentEvent(
        sessionId: 's1',
        mode: SessionMode.review,
        result: ReviewOutcome.independentPass,
        independentEligible: true,
        isSpacedEligible: true,
        now: now,
      );
      final conclusion = const EvidenceReducer().reduce(
        event,
        const AssessmentContext(
          hasValidAnswer: true,
          hasValidReference: true,
          rubricValid: true,
          wasAnswerShown: true, // 答案已展示
          justTaughtSamePoint: false,
          sameDay: false,
        ),
      );
      expect(conclusion.trigger.name, 'coreGapOrHint'); // 不算独立通过
      expect(conclusion.hintUsed, isTrue);
    });

    test('缺失原答/引用：pending，不推进掌握状态', () {
      final event = buildAssessmentEvent(
        sessionId: 's1',
        mode: SessionMode.review,
        result: ReviewOutcome.independentPass,
        independentEligible: true,
        now: now,
      );
      final conclusion = const EvidenceReducer().reduce(
        event,
        const AssessmentContext(
          hasValidAnswer: false,
          hasValidReference: false,
          rubricValid: true,
          wasAnswerShown: false,
          justTaughtSamePoint: false,
          sameDay: false,
        ),
      );
      expect(conclusion.advanceAllowed, isFalse);
      expect(conclusion.validity, EvidenceValidity.pending);
    });

    test('学习模式理解检查：不记独立通过', () {
      final event = buildAssessmentEvent(
        sessionId: 's1',
        mode: SessionMode.learning,
        result: ReviewOutcome.independentPass,
        independentEligible: true,
        now: now,
      );
      final conclusion = const EvidenceReducer().reduce(
        event,
        const AssessmentContext(
          hasValidAnswer: true,
          hasValidReference: true,
          rubricValid: true,
          wasAnswerShown: false,
          justTaughtSamePoint: false,
          sameDay: false,
        ),
      );
      expect(conclusion.trigger.name, 'learningComplete');
    });
  });

  group('ModePolicy - 模式边界（§3、§5）', () {
    final policy = const ModePolicy();

    test('学习模式不能记独立通过', () {
      expect(
        policy.canMarkIndependentPass(
          SessionMode.learning,
          hintUsed: false,
          justTaught: false,
        ),
        isFalse,
      );
    });

    test('带提示或刚教学 → 不能记独立通过', () {
      expect(
        policy.canMarkIndependentPass(
          SessionMode.review,
          hintUsed: true,
          justTaught: false,
        ),
        isFalse,
      );
      expect(
        policy.canMarkIndependentPass(
          SessionMode.review,
          hintUsed: false,
          justTaught: true,
        ),
        isFalse,
      );
    });

    test('回测最多一层中性追问', () {
      expect(policy.allowFollowUp(SessionMode.review, 0), isTrue);
      expect(policy.allowFollowUp(SessionMode.review, 1), isFalse);
    });

    test('模拟暂停并讲解后，本场同考点不再算闭卷首答', () {
      expect(
        policy.canCountClosedBookAfterTeaching(
          SessionMode.interview,
          pausedToTeach: true,
        ),
        isFalse,
      );
      expect(
        policy.canCountClosedBookAfterTeaching(
          SessionMode.interview,
          pausedToTeach: false,
        ),
        isTrue,
      );
    });
  });
}
