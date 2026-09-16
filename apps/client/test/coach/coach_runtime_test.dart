/// CoachRuntime 单测（§7.3 单轮执行与中断恢复）。
library;

import 'harness.dart';

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/application/coach_runtime.dart';

import 'fixtures/synthetic.dart';

Future<void> main() async {
  final clock = FixedClock(DateTime(2026, 9, 11));

  group('CoachRuntime - 会话与消息', () {
    test('startSession 初始 idle', () async {
      final rt = CoachRuntime(clock: clock, idGen: IdGenerator.deterministic());
      final s = await rt.startSession(
        profileId: demoProfileId,
        mode: SessionMode.learning,
      );
      expect(s.status, RuntimeStatus.idle);
      expect(await rt.store.getSession(s.id), isNotNull);
    });

    test('appendUserMessage 自增轮次并进入 waiting_user', () async {
      final rt = CoachRuntime(clock: clock, idGen: IdGenerator.deterministic());
      final s = await rt.startSession(
        profileId: demoProfileId,
        mode: SessionMode.review,
      );
      final msg = await rt.appendUserMessage(sessionId: s.id, content: '我的回答');
      expect(msg.role, 'user');
      final after = await rt.store.getSession(s.id);
      expect(after!.turnSequence, 1);
      expect(after.status, RuntimeStatus.waitingUser);
      expect((await rt.store.messagesOf(s.id)).length, 1);
    });
  });

  group('CoachRuntime - 并发与取消屏蔽', () {
    test('同一会话不可并发两个模型轮次', () async {
      final rt = CoachRuntime(clock: clock, idGen: IdGenerator.deterministic());
      final s = await rt.startSession(
        profileId: demoProfileId,
        mode: SessionMode.interview,
      );
      await rt.beginModelTurn(s.id);
      await expectThrowsAsync(
        () => rt.beginModelTurn(s.id),
        isA<RuntimeConflictException>(),
      );
    });

    test('取消后用 runId 屏蔽迟到响应', () async {
      final rt = CoachRuntime(clock: clock, idGen: IdGenerator.deterministic());
      final s = await rt.startSession(
        profileId: demoProfileId,
        mode: SessionMode.interview,
      );
      final handle = await rt.beginModelTurn(s.id);
      expect(await rt.cancel(handle), isTrue);
      expect(
        () => rt.assertRunValid(handle),
        throwsA(isA<RuntimeConflictException>()),
      );
      // 会话回到 paused
      expect((await rt.store.getSession(s.id))!.status, RuntimeStatus.paused);
    });

    test('过期 runId 的迟到响应被屏蔽', () async {
      final rt = CoachRuntime(clock: clock, idGen: IdGenerator.deterministic());
      final s = await rt.startSession(
        profileId: demoProfileId,
        mode: SessionMode.interview,
      );
      final h1 = await rt.beginModelTurn(s.id);
      await rt.finishModelTurn(s.id);
      final h2 = await rt.beginModelTurn(s.id); // 新句柄
      // 旧的 h1 已过期
      expect(
        () => rt.assertRunValid(h1),
        throwsA(isA<RuntimeConflictException>()),
      );
      expect(() => rt.assertRunValid(h2), returnsNormally);
    });
  });

  group('CoachRuntime - 检查点与教学污染', () {
    test('保存教学检查点后可在恢复时读取', () async {
      final rt = CoachRuntime(clock: clock, idGen: IdGenerator.deterministic());
      final s = await rt.startSession(
        profileId: demoProfileId,
        mode: SessionMode.learning,
        knowledgeItemId: demoKnowledgeId,
      );
      final cp = await rt.saveCheckpoint(
        sessionId: s.id,
        knowledgeItemId: demoKnowledgeId,
        taughtScope: '已讲解扩容阈值与迁移过程',
        openQuestions: ['为什么线程安全?'],
        nextPosition: '负载因子',
      );
      expect(cp.taughtScope, contains('扩容'));
      expect(await rt.store.checkpointOf(cp.id), isNotNull);
    });

    test('会话内已教学标记用于污染检查：刚教学不算闭卷首答', () async {
      final rt = CoachRuntime(clock: clock, idGen: IdGenerator.deterministic());
      final s = await rt.startSession(
        profileId: demoProfileId,
        mode: SessionMode.interview,
        reviewPointId: demoReviewPointId,
      );
      expect(rt.wasTaughtThisSession(s.id, demoReviewPointId), isFalse);
      rt.recordTaught(s.id, demoReviewPointId);
      expect(rt.wasTaughtThisSession(s.id, demoReviewPointId), isTrue);
    });
  });
}
