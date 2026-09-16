/// 删除影响预览 / 保护清理（§6.8）与训练安排（§9.7）单测。
///
/// 全部纯 Dart、不连数据库、不调用模型。
library;

import 'harness.dart';

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/domain/goal.dart';
import 'package:mianshi_zhilian/coach/domain/plan.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';
import 'package:mianshi_zhilian/coach/lifecycle/lifecycle.dart';
import 'package:mianshi_zhilian/coach/tools/tool_contract.dart';
import 'package:mianshi_zhilian/coach/workflows/workflows.dart';

Future<void> main() async {
  const planner = DeletionPlanner();
  const compiler = WorkflowCompiler();
  final clock = FixedClock(DateTime(2026, 9, 11, 9));
  var idSeed = 0;
  IdGenerator ids() => IdGenerator(factory: () => 'id-${idSeed++}');

  Goal goal(String id, {bool archived = false, String hash = 'hash-1'}) => Goal(
    id: id,
    profileId: 'p1',
    title: 'JD $id',
    originalText: 'body $id',
    contentHash: hash,
    active: !archived,
    archived: archived,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );

  GoalKnowledgeLinkRef link(String goalId, String knowledgeId) =>
      GoalKnowledgeLinkRef(goalId: goalId, knowledgeItemId: knowledgeId);

  KnowledgeItemRef knowledge(
    String id, {
    String status = 'verified',
    bool displayed = true,
  }) => KnowledgeItemRef(
    id: id,
    title: 'K $id',
    contentStatus: status,
    displayedToUser: displayed,
  );

  DeletionSnapshot snap({
    required List<Goal> goals,
    required Map<String, List<GoalKnowledgeLinkRef>> links,
    required List<KnowledgeItemRef> knowledgeItems,
    Map<String, LearningRecordSummary> records = const {},
    List<OtherUseProtection> protections = const [],
    List<DailyPlan> plans = const [],
    List<CoachSession> sessions = const [],
  }) => DeletionSnapshot(
    profileId: 'p1',
    goals: goals,
    linksByGoal: links,
    knowledgeItems: knowledgeItems,
    recordsByKnowledge: records,
    otherUseProtections: protections,
    openPlans: plans,
    affectedSessions: sessions,
  );

  DeletionPreview previewOf(
    DeletionSnapshot snapshot,
    List<String> goalIds, {
    IdGenerator? idGen,
  }) => planner.preview(
    snapshot: snapshot,
    goalIds: goalIds,
    idGen: idGen ?? ids(),
    clock: clock,
  );

  ConfirmationToken tokenFor(DeletionPreview preview) => ConfirmationToken(
    operationId: preview.operationId,
    issuedAt: clock.now(),
    subject: preview.goalIds.join(','),
    expectedRevisions: preview.expectedRevisions,
  );

  // ── §6.8 删除影响 ──────────────────────────────────────────────────

  group('删除影响归类（§6.8）', () {
    test('其他 JD 仍引用的知识一律保留，不进清理候选', () {
      final snapshot = snap(
        goals: [goal('g1'), goal('g2'), goal('g3', archived: true)],
        links: {
          'g1': [link('g1', 'k1'), link('g1', 'k2')],
          'g2': [link('g2', 'k1')],
          'g3': [link('g3', 'k1')],
        },
        knowledgeItems: [knowledge('k1'), knowledge('k2')],
      );
      final preview = previewOf(snapshot, ['g1']);
      expect(preview.totalLinkedKnowledge, 2);
      expect(preview.stillReferenced.map((i) => i.knowledgeItemId), ['k1']);
      // 归档 JD 也算引用，不会被当作可清理。
      expect(preview.stillReferenced.single.referencingGoalIds, ['g2', 'g3']);
      expect(preview.unreferencedUnlearned.map((i) => i.knowledgeItemId), [
        'k2',
      ]);
    });

    test('同一 JD 与同一知识关联多次只计一个引用', () {
      final snapshot = snap(
        goals: [goal('g1'), goal('g2')],
        links: {
          'g1': [link('g1', 'k1')],
          'g2': [link('g2', 'k1'), link('g2', 'k1'), link('g2', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
      );
      final preview = previewOf(snapshot, ['g1']);
      expect(preview.stillReferenced.single.referencingGoalIds, ['g2']);
    });

    test('无引用但已有学习记录 → 必须逐项明确选择', () {
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1'), link('g1', 'k2')],
        },
        knowledgeItems: [knowledge('k1'), knowledge('k2')],
        records: {
          'k1': const LearningRecordSummary(hasLessonCheckpoint: true),
          'k2': LearningRecordSummary.none,
        },
      );
      final preview = previewOf(snapshot, ['g1']);
      expect(preview.unreferencedLearned.map((i) => i.knowledgeItemId), ['k1']);
      expect(preview.unreferencedUnlearned.map((i) => i.knowledgeItemId), [
        'k2',
      ]);
      expect(preview.requiresLearnedDecision, isTrue);
      expect(preview.unreferencedLearned.single.requiresExplicitChoice, isTrue);
      expect(preview.unreferencedUnlearned.single.selectableForCleanup, isTrue);
    });

    test('原答/评估任一存在都算已学', () {
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
        records: {'k1': const LearningRecordSummary(answerCount: 1)},
      );
      final preview = previewOf(snapshot, ['g1']);
      expect(preview.unreferencedLearned.length, 1);
    });

    test('旧记录无法分类时按已学保护', () {
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
        records: {'k1': const LearningRecordSummary(uncertain: true)},
      );
      final preview = previewOf(snapshot, ['g1']);
      expect(preview.unreferencedLearned.length, 1);
      expect(preview.unreferencedUnlearned, isEmpty);
    });

    test('未展示的 AI 草稿且无记录 → 不算用户已学', () {
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [
          knowledge('k1', status: 'ai-draft-unverified', displayed: false),
        ],
      );
      final preview = previewOf(snapshot, ['g1']);
      expect(preview.unreferencedUnlearned.length, 1);
      expect(preview.unreferencedLearned, isEmpty);
    });

    test('其他用途保护默认不纳入清理候选', () {
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
        records: {'k1': const LearningRecordSummary(hasLessonCheckpoint: true)},
        protections: const [
          OtherUseProtection(
            knowledgeItemId: 'k1',
            kind: OtherUseKind.inProgressSession,
          ),
        ],
      );
      final preview = previewOf(snapshot, ['g1']);
      expect(preview.protectedByOtherUse.length, 1);
      expect(preview.unreferencedLearned, isEmpty);
      expect(preview.unreferencedUnlearned, isEmpty);
      expect(preview.protectedByOtherUse.single.isProtected, isTrue);
    });

    test('不存在的 JD 如实列在 unknownGoalIds，不参与删除', () {
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
      );
      final preview = previewOf(snapshot, ['g1', 'g-missing']);
      expect(preview.goalIds, ['g1']);
      expect(preview.unknownGoalIds, ['g-missing']);
    });

    test('待执行计划与暂停场次计入影响', () {
      final plan = DailyPlan(
        id: 'plan-1',
        profileId: 'p1',
        date: '2026-09-11',
        timezone: 'CST',
        baseMinutes: 25,
        version: 1,
        planItems: [
          PlanItem(
            id: 'pi-1',
            type: PlanItemType.learnKnowledge,
            title: '',
            knowledgeItemId: 'k1',
            goalId: 'g1',
          ),
          PlanItem(
            id: 'pi-2',
            type: PlanItemType.reviewLearned,
            title: '',
            knowledgeItemId: 'k1',
            completed: true,
          ),
        ],
      );
      final session = CoachSession(
        id: 's1',
        profileId: 'p1',
        mode: SessionMode.interview,
        createdAt: DateTime(2026, 9, 10),
        status: RuntimeStatus.paused,
        goalId: 'g1',
      );
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
        plans: [plan],
        sessions: [session],
      );
      final preview = previewOf(snapshot, ['g1']);
      // 已完成项不算“待执行”。
      expect(preview.affectedPlanItems, 1);
      expect(preview.affectedSessions, 1);
      expect(
        preview.historicalSnapshotNotes.contains(
          DeletionNotes.historySnapshotsRetained,
        ),
        isTrue,
      );
    });
  });

  group('删除提交：令牌、过期与范围（§6.8）', () {
    DeletionSnapshot twoKnowledgeSnapshot() => snap(
      goals: [goal('g1'), goal('g2')],
      links: {
        'g1': [link('g1', 'k1'), link('g1', 'k2')],
        'g2': [link('g2', 'k2')],
      },
      knowledgeItems: [knowledge('k1'), knowledge('k2')],
    );

    test('默认只删 JD：不勾选时知识全部保留', () {
      final snapshot = twoKnowledgeSnapshot();
      final preview = previewOf(snapshot, ['g1']);
      final result = planner.commit(
        preview: preview,
        selection: DeletionSelection.none,
        token: tokenFor(preview),
        freshSnapshot: snapshot,
      );
      expect(result.deletedGoalIds, ['g1']);
      expect(result.removedKnowledgeIds, isEmpty);
      expect(result.retainedKnowledgeIds.length, 2);
      expect(result.tombstones, ['goal:g1']);
    });

    test('令牌 operationId 不匹配 → 拒绝', () {
      final snapshot = twoKnowledgeSnapshot();
      final preview = previewOf(snapshot, ['g1']);
      expect(
        () => planner.commit(
          preview: preview,
          selection: DeletionSelection.none,
          token: ConfirmationToken(
            operationId: 'op-other',
            issuedAt: clock.now(),
            subject: 'g1',
          ),
          freshSnapshot: snapshot,
        ),
        throwsA(isA<DeletionConflictException>()),
      );
    });

    test('勾选超出预览范围（选了被其他 JD 引用的知识）→ 越权拒绝', () {
      final snapshot = twoKnowledgeSnapshot();
      final preview = previewOf(snapshot, ['g1']);
      expect(
        () => planner.commit(
          preview: preview,
          selection: const DeletionSelection(cleanupKnowledgeIds: ['k2']),
          token: tokenFor(preview),
          freshSnapshot: snapshot,
        ),
        throwsA(isA<DeletionScopeException>()),
      );
    });

    test('已学知识不选清理时保留，选了才移除', () {
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
        records: {'k1': const LearningRecordSummary(hasLessonCheckpoint: true)},
      );
      final preview = previewOf(snapshot, ['g1']);

      final kept = planner.commit(
        preview: preview,
        selection: DeletionSelection.none,
        token: tokenFor(preview),
        freshSnapshot: snapshot,
      );
      expect(kept.removedKnowledgeIds, isEmpty);

      final removed = planner.commit(
        preview: preview,
        selection: const DeletionSelection(
          learnedActions: {'k1': CleanupAction.removeKnowledgeAndRecords},
        ),
        token: tokenFor(preview),
        freshSnapshot: snapshot,
      );
      expect(removed.removedKnowledgeIds, ['k1']);
      expect(removed.tombstones.contains('knowledge:k1'), isTrue);
      expect(removed.cleanupTasks.isEmpty, isFalse);
      expect(
        removed.learnedActionsApplied['k1'],
        CleanupAction.removeKnowledgeAndRecords,
      );
    });

    test('“移除知识保留历史”也退出检索，但不删原答', () {
      final snapshot = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
        records: {
          'k1': const LearningRecordSummary(acceptedAssessmentCount: 2),
        },
      );
      final preview = previewOf(snapshot, ['g1']);
      final result = planner.commit(
        preview: preview,
        selection: const DeletionSelection(
          learnedActions: {'k1': CleanupAction.removeKnowledgeKeepHistory},
        ),
        token: tokenFor(preview),
        freshSnapshot: snapshot,
      );
      expect(result.removedKnowledgeIds, ['k1']);
      expect(
        result.learnedActionsApplied['k1'],
        CleanupAction.removeKnowledgeKeepHistory,
      );
      expect(
        result.retainedKnowledgeIds.contains('k1'),
        isFalse,
        reason: '已退出检索与训练',
      );
    });

    test('预览后新增其他 JD 引用 → 拒绝并刷新预览', () {
      final before = twoKnowledgeSnapshot();
      final preview = previewOf(before, ['g1']);
      // 预览时 k1 无其他引用；之后另一份 JD 也引用了 k1。
      final after = snap(
        goals: [goal('g1'), goal('g2'), goal('g4')],
        links: {
          'g1': [link('g1', 'k1'), link('g1', 'k2')],
          'g2': [link('g2', 'k2')],
          'g4': [link('g4', 'k1')],
        },
        knowledgeItems: [knowledge('k1'), knowledge('k2')],
      );

      var conflict = false;
      var refreshedKind = '';
      try {
        planner.commit(
          preview: preview,
          selection: const DeletionSelection(cleanupKnowledgeIds: ['k1']),
          token: tokenFor(preview),
          freshSnapshot: after,
        );
      } on DeletionConflictException catch (e) {
        conflict = true;
        refreshedKind = e.refreshedPreview.stillReferenced
            .firstWhere((i) => i.knowledgeItemId == 'k1')
            .kind
            .name;
      }
      expect(conflict, isTrue);
      expect(refreshedKind, 'referencedByOtherGoals');
    });

    test('预览后新增学习记录 → 拒绝（不按旧计数删除）', () {
      final before = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
      );
      final preview = previewOf(before, ['g1']);

      final after = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
        records: {'k1': const LearningRecordSummary(answerCount: 3)},
      );

      expect(
        () => planner.commit(
          preview: preview,
          selection: const DeletionSelection(cleanupKnowledgeIds: ['k1']),
          token: tokenFor(preview),
          freshSnapshot: after,
        ),
        throwsA(isA<DeletionConflictException>()),
      );
    });

    test('JD 内容变化也会让预览过期', () {
      final before = snap(
        goals: [goal('g1')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
      );
      final preview = previewOf(before, ['g1']);
      final after = snap(
        goals: [goal('g1', hash: 'hash-2')],
        links: {
          'g1': [link('g1', 'k1')],
        },
        knowledgeItems: [knowledge('k1')],
      );
      expect(
        () => planner.commit(
          preview: preview,
          selection: DeletionSelection.none,
          token: tokenFor(preview),
          freshSnapshot: after,
        ),
        throwsA(isA<DeletionConflictException>()),
      );
    });
  });

  // ── §9.7 训练安排 ──────────────────────────────────────────────────

  group('训练安排模板（§9.7）', () {
    test('三份中性内置模板，均不超过 6 张卡', () {
      expect(BuiltInWorkflows.all.length, 3);
      for (final template in BuiltInWorkflows.all) {
        expect(template.isBuiltIn, isTrue);
        expect(template.cards.length <= maxWorkflowCards, isTrue);
        expect(template.cards.isEmpty, isFalse);
      }
    });

    test('模板只含数据，不含可执行脚本字段', () {
      final json = BuiltInWorkflows.dailyProgress.toJson();
      const allowed = {
        'schemaVersion',
        'id',
        'nameKey',
        'descriptionKey',
        'version',
        'isBuiltIn',
        'scope',
        'cards',
      };
      for (final key in json.keys) {
        expect(allowed.contains(key), isTrue, reason: 'unexpected key $key');
      }
      for (final key in ['script', 'code', 'nodes', 'http', 'exec']) {
        expect(json.containsKey(key), isFalse);
      }
    });

    test('模板 JSON 往返保持一致', () {
      final original = BuiltInWorkflows.projectDeepDive;
      final restored = WorkflowTemplate.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.cards.length, original.cards.length);
      expect(restored.isBuiltIn, isTrue);
      expect(restored.estimatedMinutes, original.estimatedMinutes);
    });

    test('拒绝来自更高结构的模板（未知 schema）', () {
      final json = BuiltInWorkflows.dailyProgress.toJson();
      json['schemaVersion'] = workflowTemplateSchemaVersion + 1;
      expect(
        () => WorkflowTemplate.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('内置模板不原地改，复制后另存', () {
      final fork = BuiltInWorkflows.dailyProgress.fork(
        newId: 'user-1',
        newNameKey: 'coach_workflow_tpl_custom',
      );
      expect(fork.isBuiltIn, isFalse);
      expect(fork.id, 'user-1');
      expect(
        BuiltInWorkflows.dailyProgress.id,
        BuiltInWorkflows.dailyProgressId,
      );
    });
  });

  group('训练安排编译（§9.7）', () {
    WorkflowCompileRequest request({
      required WorkflowTemplate template,
      List<ReviewState> duePool = const [],
      List<LearnableKnowledgeRef> learnable = const [],
      int minutesBudget = 25,
      Set<String>? knownGoalIds,
      Set<String>? knownResumeIds,
      Set<String>? knownProjectIds,
      Set<String>? knownKnowledgeIds,
      Set<String> manualOverrideCardIds = const {},
    }) => WorkflowCompileRequest(
      profileId: 'p1',
      date: '2026-09-11',
      timezone: 'CST',
      template: template,
      idGen: ids(),
      clock: clock,
      duePool: duePool,
      learnable: learnable,
      minutesBudget: minutesBudget,
      knownGoalIds: knownGoalIds,
      knownResumeIds: knownResumeIds,
      knownProjectIds: knownProjectIds,
      knownKnowledgeIds: knownKnowledgeIds,
      manualOverrideCardIds: manualOverrideCardIds,
    );

    ReviewState dueState(String id) => ReviewState(
      reviewPointId: 'rp-$id',
      profileId: 'p1',
      knowledgeItemId: id,
      status: ReviewStatus.exposed,
      nextDueAt: DateTime(2026, 9, 10),
    );

    test('超过 6 张卡直接阻断（避免无限任务链）', () {
      final template = WorkflowTemplate(
        id: 't',
        nameKey: 'k',
        cards: [
          for (var i = 0; i < maxWorkflowCards + 1; i++)
            WorkflowCard(id: 'c$i', type: PlanItemType.learnKnowledge),
        ],
      );
      final result = compiler.compile(request(template: template));
      expect(result.ok, isFalse);
      expect(result.issues.first.code, WorkflowIssueCode.tooManyCards);
    });

    test('空模板阻断', () {
      final result = compiler.compile(
        request(
          template: const WorkflowTemplate(id: 't', nameKey: 'k', cards: []),
        ),
      );
      expect(result.issues.first.code, WorkflowIssueCode.emptyTemplate);
    });

    test('引用不属于本档案 → 阻断，不假装通过', () {
      final template = WorkflowTemplate(
        id: 't',
        nameKey: 'k',
        cards: const [
          WorkflowCard(
            id: 'c1',
            type: PlanItemType.projectTraining,
            projectId: 'proj-alien',
          ),
        ],
      );
      final result = compiler.compile(
        request(template: template, knownProjectIds: {'proj-mine'}),
      );
      expect(result.ok, isFalse);
      expect(
        result.issues.first.code,
        WorkflowIssueCode.unknownProjectReference,
      );
    });

    test('不传已知集合时该维度不校验（不假装通过也不误杀）', () {
      final template = WorkflowTemplate(
        id: 't',
        nameKey: 'k',
        cards: const [
          WorkflowCard(
            id: 'c1',
            type: PlanItemType.projectTraining,
            projectId: 'proj-x',
            estimatedMinutes: 5,
          ),
        ],
      );
      final result = compiler.compile(request(template: template));
      expect(result.ok, isTrue);
      expect(result.plan!.planItems.length, 1);
    });

    test('无到期项 → 回测卡片被跳过并给出原因', () {
      final result = compiler.compile(
        request(
          template: BuiltInWorkflows.dailyProgress,
          duePool: const [],
          learnable: const [LearnableKnowledgeRef(id: 'k1', title: 'K1')],
        ),
      );
      expect(result.ok, isTrue);
      expect(result.skippedCardIds.contains('daily.review'), isTrue);
      expect(
        result.skippedReasonKeys.contains(WorkflowSkipReasonKeys.nothingDue),
        isTrue,
      );
      expect(result.plan!.planItems.length, 1);
      expect(result.plan!.planItems.single.type, PlanItemType.learnKnowledge);
    });

    test('有到期项时回测卡片正常生成', () {
      final result = compiler.compile(
        request(
          template: BuiltInWorkflows.dailyProgress,
          duePool: [dueState('k1')],
          learnable: const [],
        ),
      );
      expect(result.plan!.planItems.length, 1);
      expect(result.plan!.planItems.single.type, PlanItemType.reviewLearned);
    });

    test('无薄弱项 → “必要时补讲”卡片被跳过', () {
      final result = compiler.compile(
        request(
          template: BuiltInWorkflows.projectDeepDive,
          duePool: [dueState('k1')],
        ),
      );
      expect(
        result.skippedReasonKeys.contains(WorkflowSkipReasonKeys.notNeeded),
        isTrue,
      );
      expect(result.conditionAppliedCardIds.isEmpty, isTrue);
    });

    test('有薄弱项 → 补讲条件生效，且最多一次', () {
      final weak = ReviewState(
        reviewPointId: 'rp-weak',
        profileId: 'p1',
        knowledgeItemId: 'k-weak',
        status: ReviewStatus.stale,
        consecutiveWeaknesses: 2,
        nextDueAt: DateTime(2026, 9, 10),
      );
      final result = compiler.compile(
        request(template: BuiltInWorkflows.projectDeepDive, duePool: [weak]),
      );
      expect(
        result.conditionAppliedCardIds.contains('project.reteach'),
        isTrue,
      );
      expect(
        result.plan!.planItems
            .firstWhere((item) => item.workflowCardId == 'project.reteach')
            .knowledgeItemId,
        'k-weak',
      );
    });

    test('时间不足时不悄悄扩容，改为询问延长或顺延', () {
      final result = compiler.compile(
        request(
          template: BuiltInWorkflows.beforeInterview,
          duePool: [dueState('k1')],
          minutesBudget: 10,
        ),
      );
      expect(result.needsExtensionAsk, isTrue);
      expect(result.totalMinutes <= 10, isTrue);
    });

    test('未声明延长条件的卡片超预算会如实报问题', () {
      final template = WorkflowTemplate(
        id: 't',
        nameKey: 'k',
        cards: [
          const WorkflowCard(
            id: 'c1',
            type: PlanItemType.projectTraining,
            projectId: 'proj-1',
            estimatedMinutes: 30,
          ),
        ],
      );
      final result = compiler.compile(
        request(template: template, minutesBudget: 20),
      );
      expect(
        result.issues.any((i) => i.code == WorkflowIssueCode.overTimeBudget),
        isTrue,
      );
    });

    test('用户固定的卡片带 manualOverride，自动生成不覆盖标记', () {
      final template = WorkflowTemplate(
        id: 't',
        nameKey: 'k',
        cards: const [
          WorkflowCard(
            id: 'c1',
            type: PlanItemType.learnKnowledge,
            knowledgeItemId: 'k1',
            estimatedMinutes: 5,
          ),
        ],
      );
      final result = compiler.compile(
        request(template: template, manualOverrideCardIds: const {'c1'}),
      );
      expect(result.plan!.planItems.single.manualOverride, isTrue);
    });

    test('自动选知识不会在同一模板里重复', () {
      final template = WorkflowTemplate(
        id: 't',
        nameKey: 'k',
        cards: const [
          WorkflowCard(
            id: 'c1',
            type: PlanItemType.learnKnowledge,
            estimatedMinutes: 5,
          ),
          WorkflowCard(
            id: 'c2',
            type: PlanItemType.learnKnowledge,
            estimatedMinutes: 5,
          ),
        ],
      );
      final result = compiler.compile(
        request(
          template: template,
          learnable: const [
            LearnableKnowledgeRef(id: 'k1', title: 'K1'),
            LearnableKnowledgeRef(id: 'k2', title: 'K2'),
          ],
        ),
      );
      final picked = result.plan!.planItems
          .map((i) => i.knowledgeItemId)
          .toList();
      expect(picked, ['k1', 'k2']);
    });
  });

  group('计划差异与撤销（§9.7）', () {
    DailyPlan planWith(String id, List<PlanItem> items) => DailyPlan(
      id: id,
      profileId: 'p1',
      date: '2026-09-11',
      timezone: 'CST',
      baseMinutes: 25,
      version: 1,
      planItems: items,
    );

    test('差异报告新增、暂停与分母变化', () {
      final before = planWith('p1', [
        PlanItem(
          id: 'a',
          type: PlanItemType.learnKnowledge,
          title: '',
          estimatedMinutes: 8,
        ),
        PlanItem(
          id: 'b',
          type: PlanItemType.reviewLearned,
          title: '',
          estimatedMinutes: 6,
        ),
      ]);
      final after = planWith('p2', [
        PlanItem(
          id: 'a',
          type: PlanItemType.learnKnowledge,
          title: '',
          estimatedMinutes: 8,
          completed: true,
        ),
        PlanItem(
          id: 'c',
          type: PlanItemType.projectTraining,
          title: '',
          estimatedMinutes: 10,
        ),
      ]);

      final diff = diffPlans(before, after);
      expect(diff.addedTypes, [PlanItemType.projectTraining]);
      expect(diff.pausedItemIds, ['b']);
      expect(diff.movedToFutureCount, 1);
      expect(diff.denominatorBefore, 2);
      expect(diff.denominatorAfter, 2);
      expect(diff.minutesBefore, 14);
      expect(diff.minutesAfter, 18);
      expect(diff.isEmpty, isFalse);
    });

    test('原样撤销只在未产生新证据时可用', () {
      final before = planWith('p1', const []);
      final after = planWith('p2', const []);
      final event = PlanChangeEvent(
        id: 'e1',
        planId: 'p2',
        at: clock.now(),
        diff: diffPlans(before, after),
        before: before,
        after: after,
        evidenceCountAfter: 3,
      );
      expect(canUndoNatively(event, currentEvidenceCount: 3), isTrue);
      // 产生新证据后不能再原样撤销，只能走新的计划修订。
      expect(canUndoNatively(event, currentEvidenceCount: 4), isFalse);
    });

    test('运行中编辑当前卡片 → 先保存问答并暂停', () {
      final run = WorkflowRun(
        id: 'run-1',
        profileId: 'p1',
        templateId: BuiltInWorkflows.projectDeepDiveId,
        templateVersion: 1,
        cardIds: const ['c1', 'c2', 'c3'],
        currentIndex: 1,
      );
      final decision = planRuntimeEdit(run, {'c2'});
      expect(decision.mustPauseFirst, isTrue);
      expect(decision.pauseReasonKey, workflowEditPausedKey);
      expect(decision.applyToCardIds, isEmpty);
    });

    test('运行中编辑只影响未开始卡片，已完成卡片不被改写', () {
      final run = WorkflowRun(
        id: 'run-1',
        profileId: 'p1',
        templateId: 't',
        templateVersion: 1,
        cardIds: const ['c1', 'c2', 'c3'],
        currentIndex: 1,
      );
      final decision = planRuntimeEdit(run, {'c1', 'c3'});
      expect(decision.applyToCardIds, ['c3']);
      expect(decision.ignoredCompletedCardIds, ['c1']);
      expect(decision.mustPauseFirst, isFalse);
    });

    test(
      'jumping to a later card or skipping does not credit untouched cards',
      () {
        var run = const WorkflowRun(
          id: 'r',
          profileId: 'p',
          templateId: 't',
          templateVersion: 1,
          cardIds: ['c1', 'c2', 'c3'],
          currentIndex: 2,
          completedIds: {},
        );
        expect(run.completedCardIds, isEmpty);
        expect(run.notStartedCardIds, ['c1', 'c2']);
        run = run.skipCurrent();
        expect(run.completedCardIds, isEmpty);
        expect(run.skippedCardIds, contains('c3'));
        expect(run.currentCardId, 'c1');
        expect(run.finished, false);
        final restored = WorkflowRun.fromJson(run.toJson());
        expect(restored.completedCardIds, isEmpty);
      },
    );

    test('运行实例推进与结束', () {
      var run = WorkflowRun(
        id: 'run-1',
        profileId: 'p1',
        templateId: 't',
        templateVersion: 1,
        cardIds: const ['c1', 'c2'],
      );
      expect(run.currentCardId, 'c1');
      run = run.advance();
      expect(run.currentCardId, 'c2');
      expect(run.completedCardIds, ['c1']);
      run = run.advance();
      expect(run.finished, isTrue);
      expect(run.status, RuntimeStatus.completed);
    });

    test('模板里的来源被删除后，相关卡片被标记', () {
      final affected = markCardsWithDeletedSource(
        BuiltInWorkflows.projectDeepDive,
        deletedEntityIds: {'c-not-a-card-id'}.union({'project-none'}),
      );
      expect(affected, isEmpty);

      final template = WorkflowTemplate(
        id: 't',
        nameKey: 'k',
        cards: const [
          WorkflowCard(
            id: 'c1',
            type: PlanItemType.projectTraining,
            projectId: 'proj-1',
          ),
          WorkflowCard(
            id: 'c2',
            type: PlanItemType.learnKnowledge,
            knowledgeItemId: 'k1',
          ),
        ],
      );
      final marked = markCardsWithDeletedSource(
        template,
        deletedEntityIds: {'proj-1'},
      );
      expect(marked, ['c1']);
    });
  });
}
