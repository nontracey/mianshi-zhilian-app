/// 教练运行时骨架（§7.3 单轮执行与中断恢复）。
///
/// 首版只实现“可恢复状态机 + 串行执行 + 取消屏蔽 + 检查点”的确定性部分；
/// 模型调用作为注入函数存在，由 P2 接入 [ModelGateway]。不依赖 Flutter。
///
/// 运行时通过 [CoachStore] 持久化会话/消息/检查点，支持崩溃恢复与多档案隔离。
library;

import '../domain/common.dart';
import '../domain/evidence.dart';
import '../domain/session.dart';
import '../persistence/coach_store.dart';
import '../persistence/extension_records.dart';

/// 单轮运行句柄。用 runId 屏蔽迟到响应，防止旧请求覆盖刚切换的目标/模型（§7.3）。
class RunHandle {
  RunHandle(this.runId, this.sessionId);
  final String runId;
  final SessionId sessionId;
  bool cancelled = false;
}

/// 运行时异常：并发/版本竞争。
class RuntimeConflictException implements Exception {
  RuntimeConflictException(this.message);
  final String message;
  @override
  String toString() => 'RuntimeConflictException: $message';
}

/// 可恢复教练运行时。管理会话状态、消息顺序号、期望版本与取消屏蔽。
class CoachRuntime {
  CoachRuntime({CoachStore? store, IdGenerator? idGen, Clock? clock})
    : store = store ?? InMemoryCoachStore(),
      idGen = idGen ?? IdGenerator(),
      clock = clock ?? const SystemClock();

  final CoachStore store;
  final IdGenerator idGen;
  final Clock clock;

  /// 每个会话的当前运行句柄；用于取消与迟到响应屏蔽。
  final Map<SessionId, RunHandle?> _activeRuns = {};

  /// 会话内已教学过的考点（教学污染检查，§9.4：刚教学不算闭卷首答）。
  final Map<SessionId, Set<ReviewPointId>> _taughtInSession = {};

  /// 开始一个新会话（idle）。
  Future<CoachSession> startSession({
    required ProfileId profileId,
    required SessionMode mode,
    GoalId? goalId,
    int? goalRevision,
    ResumeId? resumeId,
    int? resumeRevision,
    List<ProjectId> projectIds = const [],
    KnowledgeItemId? knowledgeItemId,
    ReviewPointId? reviewPointId,
    SessionCoverageSnapshot? coverageSnapshot,
    int? durationMinutes,
    String? interviewStyle,
  }) async {
    final session = CoachSession(
      id: idGen.next(),
      profileId: profileId,
      mode: mode,
      createdAt: clock.now(),
      status: RuntimeStatus.idle,
      goalId: goalId,
      goalRevision: goalRevision,
      resumeId: resumeId,
      resumeRevision: resumeRevision,
      projectIds: projectIds,
      knowledgeItemId: knowledgeItemId,
      reviewPointId: reviewPointId,
      coverageSnapshot: coverageSnapshot,
      interviewDurationMinutes: durationMinutes,
      interviewStyle: interviewStyle,
      startedAt: clock.now(),
    );
    await store.putSession(session);
    return session;
  }

  /// 用户发送消息：保存原答、自增轮次、进入 waiting_user（§7.3 步骤1-2）。
  Future<CoachMessage> appendUserMessage({
    required SessionId sessionId,
    required String content,
    List<String> references = const [],
    bool isAnswerShown = false,
  }) => store.transaction(() async {
    final session = await _requireSession(sessionId);
    if (session.status == RuntimeStatus.completed ||
        session.status == RuntimeStatus.generating ||
        session.status == RuntimeStatus.toolRunning) {
      throw RuntimeConflictException(
        "Session cannot accept a new answer in this state",
      );
    }
    final turnId = idGen.next();
    final sequence = session.turnSequence + 1;
    final message = CoachMessage(
      id: idGen.next(),
      sessionId: sessionId,
      profileId: session.profileId,
      role: 'user',
      content: content,
      turnId: turnId,
      sequence: sequence,
      createdAt: clock.now(),
      references: references,
      isAnswerShown: isAnswerShown,
    );
    await store.putMessage(message);
    await store.putSession(
      session.copyWith(
        turnSequence: sequence,
        status: RuntimeStatus.waitingUser,
      ),
    );
    return message;
  });

  /// 开始模型轮次：进入 generating，分配 runId（串行，带 expectedRevision 防双窗口竞争）。
  Future<RunHandle> beginModelTurn(SessionId sessionId) =>
      store.transaction(() async {
        final session = await _requireSession(sessionId);
        if (session.status == RuntimeStatus.generating ||
            session.status == RuntimeStatus.toolRunning ||
            session.status == RuntimeStatus.completed) {
          throw RuntimeConflictException('会话正在生成中，不可并发开始新轮次');
        }
        await store.putSession(
          session.copyWith(status: RuntimeStatus.generating),
        );
        final handle = RunHandle(idGen.next(), sessionId);
        await store.putExtension(
          CoachExtensionRecord(
            profileId: session.profileId,
            kind: CoachExtensionKind.runtimeLease,
            id: sessionId,
            revision: session.turnSequence,
            value: {'runId': handle.runId},
            updatedAt: clock.now(),
          ),
        );
        _activeRuns[sessionId] = handle;
        return handle;
      });

  /// 模型轮次结束：回到 waiting_user（或 completed）。
  Future<void> finishModelTurn(
    SessionId sessionId, {
    bool completed = false,
    RunHandle? handle,
  }) => store.transaction(() async {
    if (handle != null) {
      if (handle.sessionId != sessionId) {
        throw RuntimeConflictException("Run belongs to another session");
      }
      await assertPersistedRunValid(handle);
    }
    final session = await _requireSession(sessionId);
    _activeRuns.remove(sessionId)?.cancelled = true;
    await store.putSession(
      session.copyWith(
        status: completed ? RuntimeStatus.completed : RuntimeStatus.waitingUser,
        endedAt: completed ? clock.now() : null,
      ),
    );
  });

  /// Atomically commits the visible assistant response and all deterministic
  /// state derived from a locally validated proposal. If any write fails, the
  /// answer, evidence, checkpoint and projection are rolled back together.
  Future<CoachMessage> commitModelTurn({
    required RunHandle handle,
    required String content,
    List<String> references = const [],
    AssessmentEvent? assessment,
    ReviewState? reviewState,
    List<ReviewState> additionalReviewStates = const [],
    LessonCheckpoint? checkpoint,
    bool completed = false,
    bool questionAsked = false,
    String? stopReason,
    Map<String, Object?>? modelMetadata,
  }) => store.transaction(() async {
    await assertPersistedRunValid(handle);
    final session = await _requireSession(handle.sessionId);
    if (session.status != RuntimeStatus.generating) {
      throw RuntimeConflictException('会话不在生成状态');
    }
    if (assessment != null) {
      if (assessment.sessionId != session.id ||
          assessment.profileId != session.profileId) {
        throw RuntimeConflictException('评估证据与当前会话范围不一致');
      }
      if (reviewState == null ||
          reviewState.reviewPointId != assessment.reviewPointId ||
          reviewState.profileId != session.profileId) {
        throw RuntimeConflictException('评估投影与证据范围不一致');
      }
    }
    if (additionalReviewStates.any(
      (state) => state.profileId != session.profileId,
    )) {
      throw RuntimeConflictException('回测投影与当前会话档案不一致');
    }
    if (checkpoint != null &&
        (checkpoint.sessionId != session.id ||
            checkpoint.profileId != session.profileId)) {
      throw RuntimeConflictException('教学检查点与当前会话范围不一致');
    }
    final sequence = session.turnSequence + 1;
    final message = CoachMessage(
      id: idGen.next(),
      sessionId: session.id,
      profileId: session.profileId,
      role: 'assistant',
      content: content,
      turnId: idGen.next(),
      sequence: sequence,
      createdAt: clock.now(),
      references: references,
    );
    await store.putMessage(message);
    if (modelMetadata != null) {
      await store.putExtension(
        CoachExtensionRecord(
          profileId: session.profileId,
          kind: CoachExtensionKind.modelTurn,
          id: message.id,
          revision: 1,
          value: {
            ...modelMetadata,
            'sessionId': session.id,
            'messageId': message.id,
          },
          updatedAt: clock.now(),
        ),
      );
    }
    if (assessment != null) {
      await store.putAssessmentEvent(assessment);
      await store.putReviewState(reviewState!);
    }
    for (final state in additionalReviewStates) {
      await store.putReviewState(state);
    }
    if (checkpoint != null) await store.putCheckpoint(checkpoint);
    _activeRuns.remove(session.id)?.cancelled = true;
    await store.putSession(
      session.copyWith(
        turnSequence: sequence,
        askedQuestionCount:
            session.askedQuestionCount + (questionAsked ? 1 : 0),
        stopReason: completed ? (stopReason ?? 'completed') : null,
        status: completed ? RuntimeStatus.completed : RuntimeStatus.waitingUser,
        endedAt: completed ? clock.now() : null,
      ),
    );
    return message;
  });

  /// Records a failed model turn without fabricating an assistant answer or
  /// assessment. The saved user answer remains available for retry.
  Future<void> failModelTurn(RunHandle handle) => store.transaction(() async {
    await assertPersistedRunValid(handle);
    final session = await _requireSession(handle.sessionId);
    _activeRuns.remove(session.id)?.cancelled = true;
    await store.putSession(session.copyWith(status: RuntimeStatus.failed));
  });

  /// 取消：用 runId 屏蔽迟到响应（§7.3）。返回是否成功取消当前运行。
  Future<bool> cancel(RunHandle handle) => store.transaction(() async {
    if (_activeRuns[handle.sessionId]?.runId != handle.runId) {
      // 已过期的运行句柄，忽略。
      return false;
    }
    try {
      await assertPersistedRunValid(handle);
    } on RuntimeConflictException {
      return false;
    }
    handle.cancelled = true;
    _activeRuns[handle.sessionId] = null;
    final session = await _requireSession(handle.sessionId);
    await store.putSession(session.copyWith(status: RuntimeStatus.paused));
    return true;
  });

  /// 校验模型响应是否仍有效：runId 必须匹配且未取消（防止旧响应覆盖新目标/模型）。
  void assertRunValid(RunHandle handle) {
    if (handle.cancelled) {
      throw RuntimeConflictException('该运行已被取消，迟到响应被屏蔽');
    }
    if (_activeRuns[handle.sessionId]?.runId != handle.runId) {
      throw RuntimeConflictException('运行句柄已过期，迟到响应被屏蔽');
    }
  }

  /// A second window may have recovered the same session and started a newer
  /// run. An in-memory handle alone cannot protect that database boundary.
  Future<void> assertPersistedRunValid(RunHandle handle) async {
    assertRunValid(handle);
    final session = await _requireSession(handle.sessionId);
    final lease = await store.getExtension(
      session.profileId,
      CoachExtensionKind.runtimeLease,
      session.id,
    );
    if (lease?.value['runId'] != handle.runId) {
      throw RuntimeConflictException('A newer window owns this model turn');
    }
  }

  /// 保存教学检查点：中断恢复时查看最后提交的 checkpoint，不重放已成功写入（§7.3）。
  Future<LessonCheckpoint> saveCheckpoint({
    required SessionId sessionId,
    required KnowledgeItemId knowledgeItemId,
    required String taughtScope,
    List<String> openQuestions = const [],
    String? nextPosition,
  }) async {
    final session = await _requireSession(sessionId);
    final cp = LessonCheckpoint(
      id: idGen.next(),
      sessionId: sessionId,
      profileId: session.profileId,
      knowledgeItemId: knowledgeItemId,
      taughtScope: taughtScope,
      openQuestions: openQuestions,
      nextPosition: nextPosition,
      createdAt: clock.now(),
      updatedAt: clock.now(),
    );
    await store.putCheckpoint(cp);
    return cp;
  }

  Future<CoachSession> _requireSession(SessionId id) async {
    final s = await store.getSession(id);
    if (s == null) throw StateError('会话不存在: $id');
    return s;
  }

  /// 记录本会话已教学过的考点（用于教学污染检查）。
  void recordTaught(SessionId sessionId, ReviewPointId reviewPointId) {
    (_taughtInSession[sessionId] ??= {}).add(reviewPointId);
  }

  /// 该考点是否在本会话中刚被教学过（刚教学再答不算闭卷首答）。
  bool wasTaughtThisSession(SessionId sessionId, ReviewPointId reviewPointId) =>
      _taughtInSession[sessionId]?.contains(reviewPointId) ?? false;
}
