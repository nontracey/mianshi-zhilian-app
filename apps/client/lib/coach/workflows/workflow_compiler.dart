/// 训练安排编译器：模板 → 每日计划（§9.7）。
///
/// `WorkflowTemplate → WorkflowCompiler → DailyPlan → CoachRuntime`。
/// 编译器读取当前 JD / 简历版本、依赖知识与到期池，用**同一个** [PlanService]
/// 实例化具体任务；模板里的“下一到期项”不是永远锁定一个知识 ID。
///
/// 校验档案归属、引用有效性、时间总量、卡片数、分支次数；同一考点的教学污染检查
/// 在运行期由 `CoachRuntime` 再次执行（这里不重复）。
///
/// 本文件是纯 Dart，不依赖 Flutter。
library;

import '../application/plan_service.dart';
import '../domain/common.dart';
import '../domain/evidence.dart';
import '../domain/plan.dart';
import 'workflow_template.dart';

/// 编译问题码（协议值，非 UI 文案）。
abstract final class WorkflowIssueCode {
  static const String emptyTemplate = 'empty_template';
  static const String tooManyCards = 'too_many_cards';
  static const String overTimeBudget = 'over_time_budget';
  static const String unknownGoalReference = 'unknown_goal_reference';
  static const String unknownResumeReference = 'unknown_resume_reference';
  static const String unknownProjectReference = 'unknown_project_reference';
  static const String unknownKnowledgeReference = 'unknown_knowledge_reference';
  static const String overWeakBranchBudget = 'over_weak_branch_budget';
}

/// 卡片被跳过的原因（l10n key，由 UI 翻译）。
abstract final class WorkflowSkipReasonKeys {
  static const String nothingDue = 'coach_workflow_skip_nothing_due';
  static const String notNeeded = 'coach_workflow_skip_not_needed';
  static const String timeShort = 'coach_workflow_skip_time_short';
  static const String sourceDeleted = 'coach_workflow_skip_source_deleted';
}

/// 卡片来源已删除时展示的提示 key。删除后**不**自动绑定到名字相似的新实体。
const String workflowSourceDeletedKey = 'coach_workflow_card_source_removed';

/// 编译问题。
class WorkflowIssue {
  const WorkflowIssue({required this.code, required this.detail, this.cardId});

  final String code;
  final String detail;
  final String? cardId;

  Map<String, Object?> toJson() => {
    'code': code,
    'detail': detail,
    if (cardId != null) 'cardId': cardId,
  };
}

/// 编译请求。
class WorkflowCompileRequest {
  const WorkflowCompileRequest({
    required this.profileId,
    required this.date,
    required this.timezone,
    required this.template,
    required this.idGen,
    required this.clock,
    this.duePool = const [],
    this.learnable = const [],
    this.minutesBudget = 25,
    this.knownGoalIds,
    this.knownResumeIds,
    this.knownProjectIds,
    this.knownKnowledgeIds,
    this.manualOverrideCardIds = const {},
    this.rotationCursor,
  });

  final ProfileId profileId;
  final String date;
  final String timezone;
  final WorkflowTemplate template;
  final IdGenerator idGen;
  final Clock clock;

  final List<ReviewState> duePool;

  /// 可学习项，按优先级排列；编译器只取“还没被本条模板用掉”的。
  final List<LearnableKnowledgeRef> learnable;

  final int minutesBudget;

  /// 可校验的档案事实。传 `null` 表示该维度无法校验（不假装通过）。
  final Set<GoalId>? knownGoalIds;
  final Set<ResumeId>? knownResumeIds;
  final Set<ProjectId>? knownProjectIds;
  final Set<KnowledgeItemId>? knownKnowledgeIds;

  /// 用户已固定的卡片：生成的任务带 `manualOverride`，自动重排不得覆盖。
  final Set<String> manualOverrideCardIds;

  final String? rotationCursor;
}

/// `KnowledgeItem` 的最小投影，避免编译层强耦合领域对象。
class LearnableKnowledgeRef {
  const LearnableKnowledgeRef({required this.id, required this.title});

  final KnowledgeItemId id;
  final String title;
}

/// 编译结果。
class WorkflowCompileResult {
  const WorkflowCompileResult({
    required this.plan,
    required this.issues,
    required this.skippedCardIds,
    required this.skippedReasonKeys,
    required this.conditionAppliedCardIds,
    required this.needsExtensionAsk,
    required this.totalMinutes,
    required this.cardCount,
  });

  /// 编译出的计划；有阻断性问题时为 null。
  final DailyPlan? plan;
  final List<WorkflowIssue> issues;
  final List<String> skippedCardIds;
  final List<String> skippedReasonKeys;

  /// 条件实际生效的卡片（如确实存在薄弱项才补讲）。
  final List<String> conditionAppliedCardIds;

  /// 时间不足，需要询问用户是否延长或顺延；**不**自动扩容。
  final bool needsExtensionAsk;

  final int totalMinutes;

  /// 实际进入计划的卡片数（不含被跳过）。
  final int cardCount;

  bool get ok => plan != null;

  Map<String, Object?> toJson() => {
    'ok': ok,
    'issues': issues.map((i) => i.toJson()).toList(),
    'skippedCardIds': skippedCardIds,
    'skippedReasonKeys': skippedReasonKeys,
    'conditionAppliedCardIds': conditionAppliedCardIds,
    'needsExtensionAsk': needsExtensionAsk,
    'totalMinutes': totalMinutes,
    'cardCount': cardCount,
  };
}

/// 编译器。
class WorkflowCompiler {
  const WorkflowCompiler({this.planService = const PlanService()});

  final PlanService planService;

  WorkflowCompileResult compile(WorkflowCompileRequest request) {
    final template = request.template;
    final issues = <WorkflowIssue>[];

    if (template.cards.isEmpty) {
      issues.add(
        const WorkflowIssue(
          code: WorkflowIssueCode.emptyTemplate,
          detail: 'template has no cards',
        ),
      );
      return _blocked(issues);
    }

    if (template.cards.length > maxWorkflowCards) {
      issues.add(
        WorkflowIssue(
          code: WorkflowIssueCode.tooManyCards,
          detail:
              'template has ${template.cards.length} cards, limit is '
              '$maxWorkflowCards to avoid endless task chains',
        ),
      );
      return _blocked(issues);
    }

    final scope = template.scope;
    for (final check in [
      (
        scope.goalId,
        request.knownGoalIds,
        WorkflowIssueCode.unknownGoalReference,
      ),
      (
        scope.resumeId,
        request.knownResumeIds,
        WorkflowIssueCode.unknownResumeReference,
      ),
    ]) {
      if (check.$1 != null && check.$2 != null && !check.$2!.contains(check.$1))
        issues.add(
          WorkflowIssue(
            code: check.$3,
            detail: 'Template scope source is unavailable',
          ),
        );
    }
    // ── 引用归属校验 ──────────────────────────────────────────────────
    for (final card in template.cards) {
      final goalId = card.goalId;
      if (goalId != null &&
          request.knownGoalIds != null &&
          !request.knownGoalIds!.contains(goalId)) {
        issues.add(
          WorkflowIssue(
            code: WorkflowIssueCode.unknownGoalReference,
            detail: 'goal $goalId does not belong to this profile',
            cardId: card.id,
          ),
        );
      }
      final resumeId = card.resumeId;
      if (resumeId != null &&
          request.knownResumeIds != null &&
          !request.knownResumeIds!.contains(resumeId)) {
        issues.add(
          WorkflowIssue(
            code: WorkflowIssueCode.unknownResumeReference,
            detail: 'resume $resumeId does not belong to this profile',
            cardId: card.id,
          ),
        );
      }
      final projectId = card.projectId;
      if (projectId != null &&
          request.knownProjectIds != null &&
          !request.knownProjectIds!.contains(projectId)) {
        issues.add(
          WorkflowIssue(
            code: WorkflowIssueCode.unknownProjectReference,
            detail: 'project $projectId does not belong to this profile',
            cardId: card.id,
          ),
        );
      }
      final knowledgeItemId = card.knowledgeItemId;
      if (knowledgeItemId != null &&
          request.knownKnowledgeIds != null &&
          !request.knownKnowledgeIds!.contains(knowledgeItemId)) {
        issues.add(
          WorkflowIssue(
            code: WorkflowIssueCode.unknownKnowledgeReference,
            detail:
                'knowledge $knowledgeItemId does not belong to this profile',
            cardId: card.id,
          ),
        );
      }
    }

    final blockers = issues
        .where((i) => i.cardId == null || _isBlocking(i))
        .toList();
    if (blockers.isNotEmpty) {
      return _blocked(issues, blockers: blockers);
    }

    // ── 逐卡编译 ──────────────────────────────────────────────────────
    final now = request.clock.now();
    final items = <PlanItem>[];
    final skippedCardIds = <String>[];
    final skippedReasonKeys = <String>[];
    final conditionApplied = <String>[];
    final usedKnowledge = <KnowledgeItemId>{};
    var needsExtensionAsk = false;
    var usedMinutes = 0;
    var weakBranchUsed = false;

    for (final card in template.cards) {
      final minutes = card.estimatedMinutes ?? _defaultMinutes(card.type);

      // 条件：无到期项则跳过回测。
      if (card.condition == WorkflowCondition.skipReviewWhenNothingDue &&
          card.type == PlanItemType.reviewLearned &&
          _dueCount(request.duePool, now) == 0) {
        skippedCardIds.add(card.id);
        skippedReasonKeys.add(WorkflowSkipReasonKeys.nothingDue);
        continue;
      }

      // 条件：同一考点连续薄弱则补讲一次；无薄弱项即不需要该卡。
      // 分支不能循环，也不能递归加新流程 —— 因此这里最多“保留或跳过”。
      if (card.condition == WorkflowCondition.reteachOnceWhenWeak) {
        final weak = _hasWeakPoint(request.duePool, card.knowledgeItemId);
        if (!weak) {
          skippedCardIds.add(card.id);
          skippedReasonKeys.add(WorkflowSkipReasonKeys.notNeeded);
          continue;
        }
        if (weakBranchUsed) {
          issues.add(
            WorkflowIssue(
              code: WorkflowIssueCode.overWeakBranchBudget,
              detail: 'reteach branch may run at most once per plan',
              cardId: card.id,
            ),
          );
          skippedCardIds.add(card.id);
          skippedReasonKeys.add(WorkflowSkipReasonKeys.notNeeded);
          continue;
        }
      }

      // 时间预算：不悄悄扩容。
      if (usedMinutes + minutes > request.minutesBudget) {
        needsExtensionAsk = true;
        skippedCardIds.add(card.id);
        skippedReasonKeys.add(WorkflowSkipReasonKeys.timeShort);
        if (card.condition != WorkflowCondition.askExtendWhenTimeShort) {
          // 未声明该条件的卡片超预算属于模板问题，如实报告。
          issues.add(
            WorkflowIssue(
              code: WorkflowIssueCode.overTimeBudget,
              detail:
                  'card needs $minutes min but only '
                  '${request.minutesBudget - usedMinutes} min left',
              cardId: card.id,
            ),
          );
        }
        continue;
      }

      final item = _buildItem(
        card: card,
        request: request,
        now: now,
        usedKnowledge: usedKnowledge,
      );
      if (item == null) {
        // 无法选出可执行的题目范围（例如没有任何到期项或可学项）。
        skippedCardIds.add(card.id);
        skippedReasonKeys.add(
          card.type == PlanItemType.reviewLearned
              ? WorkflowSkipReasonKeys.nothingDue
              : WorkflowSkipReasonKeys.notNeeded,
        );
        continue;
      }

      items.add(
        item.copyWith(
          maxQuestions: card.maxQuestions,
          projectMode: card.projectMode?.name ?? 'assess',
          workflowCardId: card.id,
          goalId: item.goalId ?? template.scope.goalId,
          resumeId: item.resumeId ?? template.scope.resumeId,
        ),
      );
      if (card.condition == WorkflowCondition.reteachOnceWhenWeak) {
        weakBranchUsed = true;
        conditionApplied.add(card.id);
      }
      usedMinutes += minutes;
      if (card.knowledgeItemId != null) {
        usedKnowledge.add(card.knowledgeItemId!);
      } else if (item.knowledgeItemId != null) {
        usedKnowledge.add(item.knowledgeItemId!);
      }
    }

    final plan = planService.instantiate(
      profileId: request.profileId,
      date: request.date,
      timezone: request.timezone,
      planItems: items,
      baseMinutes: request.minutesBudget,
      idGen: request.idGen,
      revisionNote: 'workflow:${template.id}@v${template.version}',
    );

    return WorkflowCompileResult(
      plan: plan,
      issues: issues,
      skippedCardIds: skippedCardIds,
      skippedReasonKeys: skippedReasonKeys,
      conditionAppliedCardIds: conditionApplied,
      needsExtensionAsk: needsExtensionAsk,
      totalMinutes: usedMinutes,
      cardCount: items.length,
    );
  }

  bool _isBlocking(WorkflowIssue issue) =>
      issue.code == WorkflowIssueCode.tooManyCards ||
      issue.code == WorkflowIssueCode.emptyTemplate ||
      issue.code == WorkflowIssueCode.unknownGoalReference ||
      issue.code == WorkflowIssueCode.unknownResumeReference ||
      issue.code == WorkflowIssueCode.unknownProjectReference ||
      issue.code == WorkflowIssueCode.unknownKnowledgeReference;

  WorkflowCompileResult _blocked(
    List<WorkflowIssue> issues, {
    List<WorkflowIssue>? blockers,
  }) {
    final blocking = blockers ?? issues;
    return WorkflowCompileResult(
      plan: null,
      issues: List.unmodifiable(blocking),
      skippedCardIds: const [],
      skippedReasonKeys: const [],
      conditionAppliedCardIds: const [],
      needsExtensionAsk: false,
      totalMinutes: 0,
      cardCount: 0,
    );
  }

  PlanItem? _buildItem({
    required WorkflowCard card,
    required WorkflowCompileRequest request,
    required DateTime now,
    required Set<KnowledgeItemId> usedKnowledge,
  }) {
    switch (card.type) {
      case PlanItemType.reviewLearned:
        final selected = const ReviewSelector()
            .select(
              request.duePool
                  .where(
                    (s) =>
                        !usedKnowledge.contains(s.knowledgeItemId) &&
                        (card.knowledgeItemId == null ||
                            s.knowledgeItemId == card.knowledgeItemId),
                  )
                  .toList(),
              count: card.maxQuestions ?? 1,
              rotationCursor: request.rotationCursor,
              now: now,
            )
            .where((s) => !usedKnowledge.contains(s.knowledgeItemId))
            .toList();
        if (selected.isEmpty) return null;
        return PlanItem(
          id: request.idGen.next(),
          type: PlanItemType.reviewLearned,
          title: '',
          knowledgeItemId: selected.first.knowledgeItemId,
          reviewPointIds: selected.map((s) => s.reviewPointId).toList(),
          estimatedMinutes: card.estimatedMinutes ?? _defaultMinutes(card.type),
          manualOverride: request.manualOverrideCardIds.contains(card.id),
        );

      case PlanItemType.learnKnowledge:
        if (card.condition == WorkflowCondition.reteachOnceWhenWeak) {
          final weak = request.duePool
              .where(
                (state) =>
                    state.consecutiveWeaknesses >= 2 &&
                    (card.knowledgeItemId == null ||
                        card.knowledgeItemId == state.knowledgeItemId),
              )
              .firstOrNull;
          if (weak == null) return null;
          return PlanItem(
            id: request.idGen.next(),
            type: PlanItemType.learnKnowledge,
            title: '',
            knowledgeItemId: weak.knowledgeItemId,
            goalId: card.goalId,
            estimatedMinutes:
                card.estimatedMinutes ?? _defaultMinutes(card.type),
            manualOverride: request.manualOverrideCardIds.contains(card.id),
          );
        }
        final explicit = card.knowledgeItemId;
        if (explicit != null) {
          return PlanItem(
            id: request.idGen.next(),
            type: PlanItemType.learnKnowledge,
            title: '',
            knowledgeItemId: explicit,
            goalId: card.goalId,
            estimatedMinutes:
                card.estimatedMinutes ?? _defaultMinutes(card.type),
            manualOverride: request.manualOverrideCardIds.contains(card.id),
          );
        }
        // 按当前目标缺口自动选择，且不与本条模板里其它卡片重复。
        for (final candidate in request.learnable) {
          if (usedKnowledge.contains(candidate.id)) continue;
          return PlanItem(
            id: request.idGen.next(),
            type: PlanItemType.learnKnowledge,
            title: '',
            knowledgeItemId: candidate.id,
            goalId: card.goalId,
            estimatedMinutes:
                card.estimatedMinutes ?? _defaultMinutes(card.type),
            manualOverride: request.manualOverrideCardIds.contains(card.id),
          );
        }
        return null;

      case PlanItemType.projectTraining:
        final projectId = card.projectId;
        if (projectId == null) return null;
        return PlanItem(
          id: request.idGen.next(),
          type: PlanItemType.projectTraining,
          title: '',
          projectId: projectId,
          goalId: card.goalId,
          resumeId: card.resumeId,
          estimatedMinutes: card.estimatedMinutes ?? _defaultMinutes(card.type),
          manualOverride: request.manualOverrideCardIds.contains(card.id),
        );

      case PlanItemType.mockInterview:
        return PlanItem(
          id: request.idGen.next(),
          type: PlanItemType.mockInterview,
          title: '',
          goalId: card.goalId,
          resumeId: card.resumeId,
          projectId: card.projectId,
          estimatedMinutes: card.estimatedMinutes ?? _defaultMinutes(card.type),
          manualOverride: request.manualOverrideCardIds.contains(card.id),
        );
    }
  }

  int _defaultMinutes(PlanItemType type) {
    switch (type) {
      case PlanItemType.learnKnowledge:
        return 8;
      case PlanItemType.reviewLearned:
        return 6;
      case PlanItemType.projectTraining:
        return 10;
      case PlanItemType.mockInterview:
        return 15;
    }
  }

  int _dueCount(List<ReviewState> pool, DateTime now) =>
      pool.where((s) => s.status != ReviewStatus.unseen && s.isDue(now)).length;

  bool _hasWeakPoint(List<ReviewState> pool, KnowledgeItemId? knowledgeId) =>
      pool.any(
        (s) =>
            s.consecutiveWeaknesses >= 2 &&
            (knowledgeId == null || knowledgeId == s.knowledgeItemId),
      );
}

/// 计划变更差异（§9.7）。只回传结构化事实，文案由 UI 按 l10n 渲染。
class PlanChangeDiff {
  const PlanChangeDiff({
    required this.addedTypes,
    required this.pausedItemIds,
    required this.movedToFutureCount,
    required this.denominatorBefore,
    required this.denominatorAfter,
    required this.minutesBefore,
    required this.minutesAfter,
  });

  final List<PlanItemType> addedTypes;
  final List<String> pausedItemIds;
  final int movedToFutureCount;
  final int denominatorBefore;
  final int denominatorAfter;
  final int minutesBefore;
  final int minutesAfter;

  bool get isEmpty =>
      addedTypes.isEmpty &&
      pausedItemIds.isEmpty &&
      movedToFutureCount == 0 &&
      denominatorBefore == denominatorAfter &&
      minutesBefore == minutesAfter;

  Map<String, Object?> toJson() => {
    'addedTypes': addedTypes.map((t) => t.name).toList(),
    'pausedItemIds': pausedItemIds,
    'movedToFutureCount': movedToFutureCount,
    'denominatorBefore': denominatorBefore,
    'denominatorAfter': denominatorAfter,
    'minutesBefore': minutesBefore,
    'minutesAfter': minutesAfter,
  };
}

/// 对比两个计划，产出两三行差异所需的事实。
PlanChangeDiff diffPlans(DailyPlan before, DailyPlan after) {
  final beforeIds = before.planItems.map((i) => i.id).toSet();
  final afterIds = after.planItems.map((i) => i.id).toSet();

  final added = after.planItems
      .where((i) => !beforeIds.contains(i.id))
      .map((i) => i.type)
      .toList();

  // 原计划里未完成、但新计划不再包含的项 = 被暂停 / 顺延。
  final pausedIds = before.planItems
      .where((i) => !i.completed && !afterIds.contains(i.id))
      .map((i) => i.id)
      .toList();

  int minutesOf(DailyPlan p) =>
      p.planItems.fold(0, (sum, i) => sum + i.estimatedMinutes);

  return PlanChangeDiff(
    addedTypes: added,
    pausedItemIds: pausedIds,
    movedToFutureCount: pausedIds.length,
    denominatorBefore: before.denominator,
    denominatorAfter: after.denominator,
    minutesBefore: minutesOf(before),
    minutesAfter: minutesOf(after),
  );
}

/// 一次计划变更事件。
class PlanChangeEvent {
  const PlanChangeEvent({
    required this.id,
    required this.planId,
    required this.at,
    required this.diff,
    required this.before,
    required this.after,
    required this.evidenceCountAfter,
    this.undoable = true,
  });

  final String id;
  final DailyPlanId planId;
  final DateTime at;
  final PlanChangeDiff diff;
  final DailyPlan before;
  final DailyPlan after;

  /// 变更发生时已产生的训练证据数量快照。
  final int evidenceCountAfter;

  final bool undoable;
}

/// 原样撤销只在**未产生新训练证据**时可用；有证据后走新的计划修订恢复未来安排，
/// 保留已完成事实（§9.7）。
bool canUndoNatively(
  PlanChangeEvent event, {
  required int currentEvidenceCount,
}) => event.undoable && currentEvidenceCount <= event.evidenceCountAfter;
