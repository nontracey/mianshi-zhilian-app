/// 每日计划生成、冻结与可追溯调整（§9.6、§9.7）。
///
/// 模型只建议优先级与解释；[PlanService] 按时间预算和真实到期池生成任务。
/// 基础计划首次开始训练时冻结，减少/改变目标/主动改计划都生成新版本，不悄悄把未完成项当完成。
library;

import '../domain/common.dart';
import '../domain/evidence.dart';
import '../domain/plan.dart';
import '../domain/knowledge.dart';

/// 仅选择真实到期且今天未教/未测的项；游标轮换不会引入未到期项。
class ReviewSelector {
  const ReviewSelector();
  List<ReviewState> select(
    List<ReviewState> pool, {
    required int count,
    String? rotationCursor,
    DateTime? now,
  }) {
    if (count <= 0) return [];
    final reference = now ?? DateTime.now();
    final due = pool.where((e) => e.canReview(reference)).toList()
      ..sort((a, b) {
        final order = a.nextDueAt!.compareTo(b.nextDueAt!);
        return order != 0 ? order : a.reviewPointId.compareTo(b.reviewPointId);
      });
    final cursor = due.indexWhere((e) => e.reviewPointId == rotationCursor);
    final rotated = cursor < 0
        ? due
        : [...due.skip(cursor + 1), ...due.take(cursor + 1)];
    return rotated.take(count).toList();
  }
}

/// 计划服务。
class PlanService {
  const PlanService();

  /// 生成基础每日计划：默认 1 学 + 2 回测，约 25 分钟（§9.6）。
  DailyPlan generateBasePlan({
    required ProfileId profileId,
    required String date,
    required String timezone,
    required List<ReviewState> duePool,
    required List<KnowledgeItem> learnable,
    required IdGenerator idGen,
    int baseMinutes = 25,
    int reviewCount = 2,
    String? rotationCursor,
  }) {
    var remaining = baseMinutes;
    final items = <PlanItem>[];
    if (learnable.isNotEmpty && remaining >= 8) {
      items.add(
        PlanItem(
          id: idGen.next(),
          type: PlanItemType.learnKnowledge,
          title: '',
          knowledgeItemId: learnable.first.id,
          estimatedMinutes: 8,
        ),
      );
    }
    remaining -= items.isEmpty ? 0 : 8;
    final selected = const ReviewSelector().select(
      duePool,
      count: reviewCount,
      rotationCursor: rotationCursor,
      now: DateTime.parse(date),
    );
    for (final r in selected) {
      if (remaining < 6) break;
      remaining -= 6;
      items.add(
        PlanItem(
          id: idGen.next(),
          type: PlanItemType.reviewLearned,
          title: '',
          knowledgeItemId: r.knowledgeItemId,
          reviewPointIds: [r.reviewPointId],
          estimatedMinutes: 6,
        ),
      );
    }
    return DailyPlan(
      id: idGen.next(),
      profileId: profileId,
      date: date,
      timezone: timezone,
      planItems: items,
      baseMinutes: baseMinutes,
      version: 1,
    );
  }

  /// 按显式卡片序列物化每日计划（§9.7 训练安排编译器复用同一套计划语义）。
  ///
  /// 编译出的卡片最终仍是普通 [PlanItem]：证据、回测与完成事实继续落在原有
  /// session / plan 表里，不另造一套任务看板。
  DailyPlan instantiate({
    required ProfileId profileId,
    required String date,
    required String timezone,
    required List<PlanItem> planItems,
    required int baseMinutes,
    required IdGenerator idGen,
    int version = 1,
    String? revisionNote,
    DateTime? frozenAt,
  }) {
    return DailyPlan(
      id: idGen.next(),
      profileId: profileId,
      date: date,
      timezone: timezone,
      planItems: planItems,
      baseMinutes: baseMinutes,
      version: version,
      revisionNote: revisionNote,
      frozenAt: frozenAt,
    );
  }

  /// 冻结：设置 frozenAt，不可被静默改写（§9.6）。
  DailyPlan freeze(DailyPlan plan, {required Clock clock}) {
    if (plan.frozenAt != null) return plan;
    return DailyPlan(
      id: plan.id,
      profileId: plan.profileId,
      date: plan.date,
      timezone: plan.timezone,
      planItems: plan.planItems,
      baseMinutes: plan.baseMinutes,
      version: plan.version,
      frozenAt: clock.now(),
      revisionNote: plan.revisionNote,
      isExtra: plan.isExtra,
    );
  }

  /// 调整：生成新版本，保留原计划。未完成项不冒充完成（§9.6）。
  DailyPlan revise(
    DailyPlan plan, {
    required String revisionNote,
    List<PlanItem>? newItems,
  }) {
    return DailyPlan(
      id: plan.isExtra ? plan.id : IdGenerator().next(),
      profileId: plan.profileId,
      date: plan.date,
      timezone: plan.timezone,
      planItems: newItems ?? plan.planItems,
      baseMinutes: plan.baseMinutes,
      version: plan.version + 1,
      frozenAt: plan.frozenAt,
      revisionNote: revisionNote,
      isExtra: plan.isExtra,
    );
  }

  /// 基础结束后追加额外计划，不影响原基础分母（§9.6）。
  /// 加学默认 1 项、加练默认 2 个到期项，两者分开。
  DailyPlan addExtra(
    DailyPlan base, {
    required List<PlanItem> extra,
    required IdGenerator idGen,
  }) {
    return DailyPlan(
      id: idGen.next(),
      profileId: base.profileId,
      date: base.date,
      timezone: base.timezone,
      planItems: extra,
      baseMinutes: base.baseMinutes,
      version: base.version + 1,
      frozenAt: base.frozenAt,
      revisionNote: '基础结束后追加额外计划',
      isExtra: true,
    );
  }
}
