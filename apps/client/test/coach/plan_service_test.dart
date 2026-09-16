/// 计划服务单测（§9.6、§9.7）。
library;

import 'harness.dart';

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/domain/knowledge.dart';
import 'package:mianshi_zhilian/coach/domain/plan.dart';
import 'package:mianshi_zhilian/coach/application/plan_service.dart';

import 'fixtures/synthetic.dart';

ReviewState dueState(
  String id,
  DateTime due, {
  ReviewStatus status = ReviewStatus.recall,
}) => ReviewState(
  reviewPointId: id,
  profileId: demoProfileId,
  knowledgeItemId: 'k-$id',
  status: status,
  nextDueAt: due,
);

Future<void> main() async {
  final clock = FixedClock(DateTime(2026, 9, 11));
  final idGen = IdGenerator.deterministic();

  group('PlanService - 基础计划生成与冻结', () {
    test('默认 1 学 + 2 回测', () {
      final learnable = [
        buildDemoKnowledge(now: clock.now()),
        KnowledgeItem(
          id: 'k-other',
          profileId: demoProfileId,
          title: '其他知识',
          createdAt: clock.now(),
          updatedAt: clock.now(),
        ),
      ];
      final due = [
        dueState('rp-a', DateTime(2026, 9, 10)),
        dueState('rp-b', DateTime(2026, 9, 9)),
        dueState('rp-c', DateTime(2026, 9, 8)),
      ];
      final plan = const PlanService().generateBasePlan(
        profileId: demoProfileId,
        date: '2026-09-11',
        timezone: 'Asia/Shanghai',
        duePool: due,
        learnable: learnable,
        idGen: idGen,
      );
      expect(
        plan.planItems
            .where((e) => e.type == PlanItemType.learnKnowledge)
            .length,
        1,
      );
      expect(
        plan.planItems
            .where((e) => e.type == PlanItemType.reviewLearned)
            .length,
        2,
      );
    });

    test('无到期项时回测不足不强行凑满', () {
      final plan = const PlanService().generateBasePlan(
        profileId: demoProfileId,
        date: '2026-09-11',
        timezone: 'Asia/Shanghai',
        duePool: const [],
        learnable: [buildDemoKnowledge(now: clock.now())],
        idGen: idGen,
      );
      expect(
        plan.planItems
            .where((e) => e.type == PlanItemType.reviewLearned)
            .length,
        0,
      );
    });

    test('冻结后 frozenAt 设置，且不可被静默改写', () {
      final plan = const PlanService().generateBasePlan(
        profileId: demoProfileId,
        date: '2026-09-11',
        timezone: 'Asia/Shanghai',
        duePool: const [],
        learnable: [buildDemoKnowledge(now: clock.now())],
        idGen: idGen,
      );
      final frozen = const PlanService().freeze(plan, clock: clock);
      expect(frozen.frozenAt, isNotNull);
      // 再次冻结无变化
      expect(
        const PlanService().freeze(frozen, clock: clock).frozenAt,
        frozen.frozenAt,
      );
    });

    test('调整生成新版本，保留原计划项（未完成不冒充完成）', () {
      final plan = const PlanService().generateBasePlan(
        profileId: demoProfileId,
        date: '2026-09-11',
        timezone: 'Asia/Shanghai',
        duePool: const [],
        learnable: [buildDemoKnowledge(now: clock.now())],
        idGen: idGen,
      );
      final items = [
        ...plan.planItems,
        PlanItem(id: 'extra', type: PlanItemType.mockInterview, title: '加一场模拟'),
      ];
      final revised = const PlanService().revise(
        plan,
        revisionNote: '增加模拟',
        newItems: items,
      );
      expect(revised.version, plan.version + 1);
      expect(revised.planItems.length, plan.planItems.length + 1);
    });

    test('基础结束追加额外计划不影响原基础分母', () {
      final plan = const PlanService().generateBasePlan(
        profileId: demoProfileId,
        date: '2026-09-11',
        timezone: 'Asia/Shanghai',
        duePool: [dueState('rp-a', DateTime(2026, 9, 10))],
        learnable: [buildDemoKnowledge(now: clock.now())],
        idGen: idGen,
      );
      final extra = [
        PlanItem(id: 'ex1', type: PlanItemType.learnKnowledge, title: '加学 1 项'),
      ];
      final withExtra = const PlanService().addExtra(
        plan,
        extra: extra,
        idGen: idGen,
      );
      expect(withExtra.isExtra, isTrue);
      expect(withExtra.baseMinutes, plan.baseMinutes);
      // 原基础计划的分母（planItems 数量）作为口径保留
      expect(withExtra.planItems.map((i) => i.id), ['ex1']);
      expect(plan.denominator, 2);
    });
  });

  group('ReviewSelector - 公平轮换与借位（§9.6）', () {
    test('有到期项时优先取最早到期；游标跳过刚用过项', () {
      final pool = [
        dueState('rp-a', DateTime(2026, 9, 8)),
        dueState('rp-b', DateTime(2026, 9, 9)),
        dueState('rp-c', DateTime(2026, 9, 10)),
      ];
      // 无游标：取最早两个
      final first = const ReviewSelector().select(
        pool,
        count: 2,
        now: clock.now(),
      );
      expect(first.map((e) => e.reviewPointId), ['rp-a', 'rp-b']);
      // 游标为 rp-a：跳过它，取 rp-b, rp-c
      final second = const ReviewSelector().select(
        pool,
        count: 2,
        rotationCursor: 'rp-a',
        now: clock.now(),
      );
      expect(second.map((e) => e.reviewPointId), ['rp-b', 'rp-c']);
    });

    test('到期不足时按实际数量结束，不借未到期项', () {
      final pool = [
        dueState('rp-a', DateTime(2026, 9, 10)),
        dueState(
          'rp-b',
          DateTime(2026, 9, 20),
          status: ReviewStatus.recall,
        ), // 未到期但可借
        dueState(
          'rp-c',
          DateTime(2026, 9, 20),
          status: ReviewStatus.unseen,
        ), // 不应借
      ];
      final selected = const ReviewSelector().select(
        pool,
        count: 2,
        now: clock.now(),
      );
      expect(selected.map((e) => e.reviewPointId), ['rp-a']);
    });
  });
}
