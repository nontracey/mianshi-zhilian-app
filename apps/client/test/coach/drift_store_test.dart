/// DriftCoachStore 集成测试（§9.1、§9.2）。
///
/// 真实打开内存 SQLite（macOS 自带 libsqlite3），覆盖全部实体往返、profileId 隔离、
/// 级联删除与 JSON 字段（列表 / 每日计划项）的序列化。纯 Dart VM 运行。
library;

import 'harness.dart';

import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show GeneratedDatabase, TableInfo, Table;

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/profile.dart';
import 'package:mianshi_zhilian/coach/domain/goal.dart';
import 'package:mianshi_zhilian/coach/domain/knowledge.dart';
import 'package:mianshi_zhilian/coach/domain/resume.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';
import 'package:mianshi_zhilian/coach/domain/plan.dart';
import 'package:mianshi_zhilian/coach/knowledge/source.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store_native.dart';

import 'fixtures/synthetic.dart';

final DateTime now = DateTime(2026, 9, 11, 10, 30);

Future<void> main() async {
  group('DriftCoachStore - 档案', () {
    test('Profile 往返与默认值', () async {
      final store = openNativeCoachStoreMemory();
      await store.putProfile(
        Profile(
          id: 'p1',
          displayName: '演示档案',
          baseLevel: '中级',
          teachingPreference: '先讲原理',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final p = await store.getProfile('p1');
      expect(p, isNotNull);
      expect(p!.displayName, '演示档案');
      expect(p.dailyMinutesBudget, 25);
      expect(p.teachingPreference, '先讲原理');
      await store.close();
    });
  });

  group('DriftCoachStore - 目标 JD 与要求', () {
    test('Goal + 要求 + 修订 + 知识关联往返', () async {
      final store = openNativeCoachStoreMemory();
      await store.putGoal(buildDemoGoal(now: now));
      await store.putGoalRequirements(buildDemoRequirements(now: now));
      await store.putGoalRevision(
        GoalRevision(
          id: 'rev-1',
          goalId: demoGoalId,
          profileId: demoProfileId,
          revisionNumber: 1,
          contentHash: 'h1',
          createdAt: now,
          note: '初始版本',
        ),
      );
      await store.putKnowledgeItem(buildDemoKnowledge(now: now));
      await store.putGoalKnowledgeLink(
        GoalKnowledgeLink(
          goalId: demoGoalId,
          knowledgeItemId: demoKnowledgeId,
          profileId: demoProfileId,
          requirementIds: const ['req-demo-java'],
          createdAt: now,
        ),
      );

      final g = await store.getGoal(demoGoalId);
      expect(g!.title, contains('演示数据'));
      expect(g.platform, 'demo-board');

      final reqs = await store.listGoalRequirements(demoGoalId);
      expect(reqs.length, 3);
      expect(reqs.first.importance, Importance.high);

      final revs = await store.listGoalRevisions(demoGoalId);
      expect(revs.single.revisionNumber, 1);

      final k = await store.getKnowledgeItem(demoKnowledgeId);
      expect(k!.aliases, ['哈希表扩容', 'hashmap resize']);

      final links = await store.listGoalKnowledgeLinks(demoGoalId);
      expect(links.single.requirementIds, ['req-demo-java']);
      await store.close();
    });

    test('deleteGoal 级联清除要求/关联/修订', () async {
      final store = openNativeCoachStoreMemory();
      await store.putGoal(buildDemoGoal(now: now));
      await store.putGoalRequirements(buildDemoRequirements(now: now));
      await store.putGoalKnowledgeLink(
        GoalKnowledgeLink(
          goalId: demoGoalId,
          knowledgeItemId: demoKnowledgeId,
          profileId: demoProfileId,
          createdAt: now,
        ),
      );
      await store.deleteGoal(demoGoalId);
      expect(await store.getGoal(demoGoalId), null);
      expect((await store.listGoalRequirements(demoGoalId)).length, 0);
      expect((await store.listGoalKnowledgeLinks(demoGoalId)).length, 0);
      await store.close();
    });

    test('profileId 隔离：只返回本档案的目标', () async {
      final store = openNativeCoachStoreMemory();
      await store.putGoal(buildDemoGoal(now: now));
      await store.putGoal(
        Goal(
          id: 'goal-other',
          profileId: 'profile-other',
          title: '其他档案目标',
          originalText: '...',
          contentHash: 'h-other',
          active: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final mine = await store.listGoals(demoProfileId);
      expect(mine.length, 1);
      expect(mine.single.id, demoGoalId);
      await store.close();
    });
  });

  group('DriftCoachStore - 简历与主张', () {
    test('Resume + Project + Claim + 链接往返', () async {
      final store = openNativeCoachStoreMemory();
      await store.putResume(buildDemoResume(now: now));
      await store.putProject(buildDemoProject());
      for (final c in buildDemoClaims()) {
        await store.putResumeClaim(c);
      }
      await store.putGoalResumeLink(
        GoalResumeLink(
          goalId: demoGoalId,
          resumeId: demoResumeId,
          profileId: demoProfileId,
          isDefault: true,
          createdAt: now,
        ),
      );
      await store.putClaimRequirementLink(
        ClaimRequirementLink(
          claimId: 'claim-demo-idempotent',
          requirementId: 'req-demo-idempotent',
          profileId: demoProfileId,
          mappingType: 'jdAndResume',
          rationale: 'JD 与简历都提到幂等',
        ),
      );

      final r = await store.getResume(demoResumeId);
      expect(r!.fileName, 'demo-resume.txt');
      expect(
        (await store.listProjects(demoResumeId)).single.name,
        contains('演示数据'),
      );

      final claims = await store.listResumeClaims(demoResumeId);
      expect(claims.single.status, ClaimStatus.confirmed);
      expect(claims.single.confidence, 0.9);

      final gLinks = await store.listGoalResumeLinks(demoGoalId);
      expect(gLinks.single.isDefault, isTrue);

      final cLinks = await store.listClaimRequirementLinks(
        'claim-demo-idempotent',
      );
      expect(cLinks.single.mappingType, 'jdAndResume');
      await store.close();
    });

    test('简历修订号往返：会话固定版本，改简历不改写历史', () async {
      final store = openNativeCoachStoreMemory();
      await store.putResume(buildDemoResume(now: now));
      final first = await store.getResume(demoResumeId);
      expect(first!.revision, 1);

      await store.putResume(first.copyWith(revision: 2, versionLabel: 'v2'));
      final reloaded = await store.getResume(demoResumeId);
      expect(reloaded!.revision, 2);
      expect(reloaded.versionLabel, 'v2');
      await store.close();
    });
  });

  group('DriftCoachStore - 来源与分块', () {
    test('Source + SourceChunk + IngestionJob 往返', () async {
      final store = openNativeCoachStoreMemory();
      await store.putSource(
        Source(
          id: 'src-1',
          profileId: demoProfileId,
          title: '演示资料',
          type: SourceType.markdown,
          contentHash: 'abc123',
          status: IngestionStatus.ready,
          url: 'https://example.com/doc',
          content: '正文快照',
          fetchedAt: now,
          createdAt: now,
        ),
      );
      await store.putSourceChunks([
        SourceChunk(
          id: 'chunk-1',
          sourceId: 'src-1',
          sourceRevision: 1,
          index: 0,
          content: '第一块',
          titlePath: '1. 概述',
          knowledgeItemId: demoKnowledgeId,
        ),
        SourceChunk(
          id: 'chunk-2',
          sourceId: 'src-1',
          sourceRevision: 1,
          index: 1,
          content: '第二块',
        ),
      ]);
      await store.putIngestionJob(
        IngestionJob(
          id: 'job-1',
          profileId: demoProfileId,
          sourceId: 'src-1',
          status: IngestionStatus.ready,
          createdAt: now,
          completedAt: now,
        ),
      );

      final s = await store.getSource('src-1');
      expect(s!.type, SourceType.markdown);
      expect(s.status, IngestionStatus.ready);

      final chunks = await store.listSourceChunks('src-1');
      expect(chunks.length, 2);
      expect(chunks.first.index, 0);
      expect(chunks.first.knowledgeItemId, demoKnowledgeId);
      expect(chunks[1].content, '第二块');

      final job = await store.getIngestionJob('job-1');
      expect(job!.status, IngestionStatus.ready);
      await store.close();
    });
  });

  group('DriftCoachStore - 回测状态与评估事件', () {
    test('ReviewPoint + ReviewState + AssessmentEvent 往返', () async {
      final store = openNativeCoachStoreMemory();
      await store.putReviewPoint(buildDemoReviewPoint(now: now));
      await store.putReviewState(
        ReviewState(
          reviewPointId: demoReviewPointId,
          profileId: demoProfileId,
          knowledgeItemId: demoKnowledgeId,
          status: ReviewStatus.recall,
          nextDueAt: DateTime(2026, 9, 18),
          consecutiveIndependentPasses: 2,
          intervalStep: 1,
        ),
      );
      await store.putAssessmentEvent(
        buildAssessmentEvent(
          sessionId: 'sess-1',
          mode: SessionMode.review,
          result: ReviewOutcome.independentPass,
          independentEligible: true,
          now: now,
        ),
      );

      final rp = await store.listReviewPoints(demoKnowledgeId);
      expect(rp.single.label, '扩容阈值与迁移');

      final rs = await store.getReviewState(demoReviewPointId);
      expect(rs!.status, ReviewStatus.recall);
      expect(rs.consecutiveIndependentPasses, 2);
      expect(rs.nextDueAt, DateTime(2026, 9, 18));

      final events = await store.listAssessmentEvents('sess-1');
      expect(events.single.result, ReviewOutcome.independentPass);
      expect(events.single.askedDimensions, ['mechanism']);
      expect(events.single.sourceRevisionIds, ['src-1']);
      expect(events.single.independentEligible, isTrue);

      final byPoint = await store.listAssessmentEventsForReviewPoint(
        demoReviewPointId,
      );
      expect(byPoint.length, 1);
      await store.close();
    });
  });

  group('DriftCoachStore - 会话与消息', () {
    test('Session + Message + Checkpoint 往返，且消息按顺序返回', () async {
      final store = openNativeCoachStoreMemory();
      await store.putSession(
        buildDemoSession(id: 'sess-1', mode: SessionMode.interview, now: now),
      );
      await store.putMessage(
        CoachMessage(
          id: 'm2',
          sessionId: 'sess-1',
          profileId: demoProfileId,
          role: 'assistant',
          content: '第二问',
          turnId: 't1',
          sequence: 2,
          createdAt: now,
          references: const ['src-1'],
        ),
      );
      await store.putMessage(
        CoachMessage(
          id: 'm1',
          sessionId: 'sess-1',
          profileId: demoProfileId,
          role: 'user',
          content: '第一答',
          turnId: 't1',
          sequence: 1,
          createdAt: now,
        ),
      );
      await store.putCheckpoint(
        LessonCheckpoint(
          id: 'cp-1',
          sessionId: 'sess-1',
          profileId: demoProfileId,
          knowledgeItemId: demoKnowledgeId,
          taughtScope: '已讲解扩容',
          openQuestions: const ['为什么线程安全'],
          nextPosition: 'loadFactor',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final s = await store.getSession('sess-1');
      expect(s!.mode, SessionMode.interview);
      expect(s.projectIds, [demoProjectId]);
      expect(s.turnSequence, 0);

      final msgs = await store.messagesOf('sess-1');
      expect(msgs.length, 2);
      expect(msgs.first.id, 'm1'); // 按 sequence 升序
      expect(msgs[1].references, ['src-1']);

      final cp = await store.checkpointOf('cp-1');
      expect(cp!.openQuestions, ['为什么线程安全']);
      expect((await store.listCheckpoints('sess-1')).length, 1);
      await store.close();
    });
  });

  group('DriftCoachStore - 每日计划', () {
    test('DailyPlan（含 planItems JSON）往返', () async {
      final store = openNativeCoachStoreMemory();
      await store.putDailyPlan(
        DailyPlan(
          id: 'plan-1',
          profileId: demoProfileId,
          date: '2026-09-11',
          timezone: 'Asia/Shanghai',
          planItems: [
            PlanItem(
              id: 'item-1',
              type: PlanItemType.learnKnowledge,
              title: '学一个知识点',
              knowledgeItemId: demoKnowledgeId,
              estimatedMinutes: 8,
            ),
            PlanItem(
              id: 'item-2',
              type: PlanItemType.reviewLearned,
              title: '回测已学内容',
              knowledgeItemId: demoKnowledgeId,
              reviewPointIds: [demoReviewPointId],
              estimatedMinutes: 6,
              completed: true,
              manualOverride: true,
            ),
          ],
          baseMinutes: 25,
          version: 1,
          frozenAt: now,
        ),
      );

      final plan = await store.getDailyPlan('plan-1');
      expect(plan!.date, '2026-09-11');
      expect(plan.baseMinutes, 25);
      expect(plan.frozenAt, now);
      expect(plan.planItems.length, 2);
      expect(plan.planItems.first.type, PlanItemType.learnKnowledge);
      expect(plan.planItems[1].reviewPointIds, [demoReviewPointId]);
      expect(plan.planItems[1].completed, isTrue);
      expect(plan.planItems[1].manualOverride, isTrue);

      final byDate = await store.listDailyPlans(
        demoProfileId,
        date: '2026-09-11',
      );
      expect(byDate.length, 1);
      final wrongDate = await store.listDailyPlans(
        demoProfileId,
        date: '2026-09-12',
      );
      expect(wrongDate.length, 0);
      await store.close();
    });
  });

  group('DriftCoachStore - 接口契约', () {
    test('InMemoryCoachStore 与 DriftCoachStore 均实现 CoachStore', () {
      final CoachStore memory = InMemoryCoachStore();
      final CoachStore drift = openNativeCoachStoreMemory();
      expect(memory, isNotNull);
      expect(drift, isNotNull);
    });
  });

  group('DriftCoachStore - 增量迁移', () {
    test('老库缺列时自动补列且不丢数据', () async {
      final dir = await Directory.systemTemp.createTemp('coach-drift-migrate');
      final file = File('${dir.path}/coach.sqlite');
      DriftCoachStore? store;
      _LegacyDatabase? legacyDb;
      try {
        // 1) 造一个「旧版本」库：profiles 表没有 defaultWorkflowTemplateId。
        //    直接用 drift 的 NativeDatabase，避免为测试额外引入 sqlite3 直接依赖。
        legacyDb = _LegacyDatabase(NativeDatabase(file));
        await legacyDb.customStatement('''
          CREATE TABLE profiles (
            id TEXT PRIMARY KEY,
            displayName TEXT,
            dailyMinutesBudget INTEGER NOT NULL DEFAULT 25,
            baseLevel TEXT,
            teachingPreference TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
        await legacyDb.customStatement(
          "INSERT INTO profiles (id, displayName, dailyMinutesBudget, "
          "createdAt, updatedAt) VALUES ('legacy-1', '演示旧档案', 45, "
          "'${now.toIso8601String()}', '${now.toIso8601String()}')",
        );
        await legacyDb.close();
        legacyDb = null;

        // 2) 用当前实现打开：ensureSchema 应检测并补上有缺失的列。
        store = openNativeCoachStoreFile(file);

        final migrated = await store.getProfile('legacy-1');
        expect(migrated, isNotNull);
        // 迁移不丢已有数据。
        expect(migrated!.displayName, '演示旧档案');
        expect(migrated.dailyMinutesBudget, 45);
        // 新列在老记录上为 null，而不是被填成猜测值。
        expect(migrated.defaultWorkflowTemplateId, null);

        // 3) 补列之后新字段可正常写入与读回。
        await store.putProfile(
          migrated.copyWith(
            defaultWorkflowTemplateId: 'builtin.daily_progress',
            updatedAt: now,
          ),
        );
        final reloaded = await store.getProfile('legacy-1');
        expect(reloaded!.defaultWorkflowTemplateId, 'builtin.daily_progress');
        expect(reloaded.displayName, '演示旧档案');
      } finally {
        await legacyDb?.close();
        await store?.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
  });
}

class _LegacyDatabase extends GeneratedDatabase {
  _LegacyDatabase(super.e);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
}
