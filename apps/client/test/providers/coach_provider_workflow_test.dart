// CoachProvider 训练安排闭环测试：模板持久化 + 计划应用/撤销。
//
// 覆盖 §9.7 的三件事：
// 1. 另存模板 → 列表可见；同名更新（版本 +1），不产生重名副本；
// 2. 删除用户模板；删除默认模板时同步清掉「今后默认」；内置模板不可删；
// 3. applyPlan 应用后可撤销一次（恢复旧计划），撤销后不可重复撤销。
import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/plan.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/workflows/workflows.dart';
import 'package:mianshi_zhilian/providers/coach_provider.dart';

void main() {
  late InMemoryCoachStore store;
  late CoachProvider provider;

  setUp(() {
    store = InMemoryCoachStore();
    provider = CoachProvider(
      store: store,
      clock: FixedClock(DateTime(2026, 9, 12, 9)),
      idGen: IdGenerator(
        factory: (() {
          var i = 0;
          return () => 'id-${i++}';
        })(),
      ),
    );
  });

  DailyPlan planOf(String id, List<PlanItem> items, {int version = 1}) =>
      DailyPlan(
        id: id,
        profileId: provider.profileId,
        date: provider.todayKey,
        timezone: 'CST',
        planItems: items,
        baseMinutes: items.fold(0, (s, i) => s + i.estimatedMinutes),
        version: version,
      );

  group('训练安排模板持久化', () {
    test('另存模板后可列出，同名更新版本 +1 且不产生副本', () async {
      final first = await provider.saveWorkflowTemplate(
        name: '早上冲刺',
        cards: const [
          WorkflowCard(
            id: 'c1',
            type: PlanItemType.reviewLearned,
            estimatedMinutes: 6,
          ),
        ],
      );
      expect(first.id, startsWith('user.'));
      expect(first.name, '早上冲刺');
      expect(first.isBuiltIn, isFalse);

      var listed = await provider.listUserWorkflowTemplates();
      expect(listed, hasLength(1));

      final second = await provider.saveWorkflowTemplate(
        name: '早上冲刺',
        cards: const [
          WorkflowCard(
            id: 'c1',
            type: PlanItemType.reviewLearned,
            estimatedMinutes: 6,
          ),
          WorkflowCard(
            id: 'c2',
            type: PlanItemType.learnKnowledge,
            estimatedMinutes: 8,
          ),
        ],
      );
      expect(second.id, first.id, reason: '同名应更新原模板');
      expect(second.version, first.version + 1);
      expect(second.cards, hasLength(2));

      listed = await provider.listUserWorkflowTemplates();
      expect(listed, hasLength(1));
      expect(listed.single.cards, hasLength(2));
    });

    test(
      'fork preserves edited cards instead of original template cards',
      () async {
        final base = BuiltInWorkflows.all.first;
        final saved = await provider.saveWorkflowTemplate(
          name: 'Custom',
          fromTemplate: base,
          cards: const [
            WorkflowCard(
              id: 'edited',
              type: PlanItemType.learnKnowledge,
              estimatedMinutes: 11,
            ),
          ],
        );
        expect(saved.cards.single.id, 'edited');
        expect(
          (await provider.listUserWorkflowTemplates())
              .single
              .cards
              .single
              .estimatedMinutes,
          11,
        );
      },
    );

    test('空名字拒绝保存', () async {
      await expectLater(
        provider.saveWorkflowTemplate(name: '   ', cards: const []),
        throwsArgumentError,
      );
    });

    test('删除用户模板；删除默认模板时清掉「今后默认」；内置不可删', () async {
      final t = await provider.saveWorkflowTemplate(
        name: '面试前夜',
        cards: const [
          WorkflowCard(
            id: 'c1',
            type: PlanItemType.mockInterview,
            estimatedMinutes: 15,
          ),
        ],
      );
      await provider.load();
      await provider.setDefaultWorkflowTemplate(t.id);
      expect(provider.profile?.defaultWorkflowTemplateId, t.id);

      // 内置模板拒绝删除。
      expect(
        await provider.deleteWorkflowTemplate(BuiltInWorkflows.dailyProgressId),
        isFalse,
      );
      // 不存在的 id 返回 false，而不是静默成功。
      expect(await provider.deleteWorkflowTemplate('user.nope'), isFalse);

      expect(await provider.deleteWorkflowTemplate(t.id), isTrue);
      expect(await provider.listUserWorkflowTemplates(), isEmpty);
      expect(
        provider.profile?.defaultWorkflowTemplateId,
        isNull,
        reason: '删掉的模板不能再被当作今后默认',
      );
    });
  });

  group('计划应用与撤销', () {
    test('首次应用没有旧计划，不提供撤销；再次应用后可撤销一次', () async {
      // 第一次应用：今天还没有计划。
      final first = planOf('plan-a', [
        PlanItem(id: 'i1', type: PlanItemType.learnKnowledge, title: '学习'),
      ]);
      await provider.applyPlan(first);
      expect(provider.canUndoPlanApply, isFalse);
      expect(await provider.undoPlanApply(), isFalse);

      // 第二次应用：旧计划被记为可撤销快照。
      final second = planOf('plan-b', [
        PlanItem(id: 'i2', type: PlanItemType.reviewLearned, title: '回测'),
        PlanItem(id: 'i3', type: PlanItemType.mockInterview, title: '模拟'),
      ]);
      await provider.applyPlan(second);
      expect(provider.canUndoPlanApply, isTrue);
      expect(provider.todayPlan?.id, 'plan-b');

      await provider.reload();
      expect(provider.canUndoPlanApply, isTrue);
      expect(await provider.undoPlanApply(), isTrue);
      expect(provider.todayPlan?.planItems.single.id, 'i1');
      expect(provider.todayPlan?.version, 3, reason: '撤销另存新版本，保留历史');
      await provider.reload();
      expect(provider.todayPlan?.planItems.single.id, 'i1');
      expect(provider.todayPlan?.version, 3);

      // 撤销后不可重复撤销（该调整已标记 already_undone）。
      expect(await provider.undoPlanApply(), isFalse);
      expect(provider.canUndoPlanApply, isFalse);
    });

    test('应用后计划又被改动时撤销失效，不覆盖中间改动', () async {
      final first = planOf('plan-a', [
        PlanItem(id: 'i1', type: PlanItemType.learnKnowledge, title: '学习'),
      ]);
      final second = planOf('plan-b', [
        PlanItem(id: 'i2', type: PlanItemType.reviewLearned, title: '回测'),
      ]);
      await provider.applyPlan(first);
      await provider.applyPlan(second);

      // 模拟中间改动：完成一张卡片（版本 +1）。
      final mutated = DailyPlan(
        id: 'plan-b',
        profileId: provider.profileId,
        date: provider.todayKey,
        timezone: 'CST',
        planItems: [
          PlanItem(
            id: 'i2',
            type: PlanItemType.reviewLearned,
            title: '回测',
            completed: true,
          ),
        ],
        baseMinutes: 6,
        version: 3,
      );
      await store.putDailyPlan(mutated);
      await provider.reload();

      // 版本不一致 → 撤销拒绝，保留用户已完成的状态。
      expect(await provider.undoPlanApply(), isFalse);
      expect(provider.todayPlan?.version, 3);
    });
  });
}
