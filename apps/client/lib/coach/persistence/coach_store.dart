/// 教练持久化契约与内存实现（§9.1、§9.2）。
///
/// [CoachStore] 是唯一的持久化接口：所有领域实体都通过 profileId 或父项归属到
/// 某一个本地档案，避免切换档案时混淆经历或成绩。方法统一异步（[Future]），
/// 以便接口在纯内存实现（测试）与原生 Drift 实现（Flutter 运行时）之间无缝替换。
///
/// 本文件**不依赖 Flutter、不依赖 drift**，可在纯 Dart VM 上被单测直接 import。
library;

import 'dart:async';

import '../domain/common.dart';
import '../domain/profile.dart';
import '../domain/goal.dart';
import '../domain/knowledge.dart';
import '../domain/resume.dart';
import '../domain/evidence.dart';
import '../domain/session.dart';
import '../domain/plan.dart';
import '../knowledge/source.dart';
import 'extension_records.dart';

/// Optional storage maintenance; run outside a business transaction after a
/// durable deletion. In-memory stores have no filesystem pages to reclaim.
abstract interface class CoachStoreMaintenance {
  Future<void> compactDeletedData();
}

/// 教练持久化契约。所有方法按 [ProfileId] 隔离数据。
abstract class CoachStore {
  /// Atomic unit of work; errors roll back all writes.
  Future<T> transaction<T>(Future<T> Function() action);

  /// Remove personal entities for one profile; retain credentials metadata and
  /// tombstones so an old device cannot revive a cleared dataset.
  Future<void> clearProfileData(ProfileId profileId);
  // ---- 档案 ----
  Future<void> putProfile(Profile profile);
  Future<Profile?> getProfile(ProfileId id);
  Future<List<Profile>> listProfiles();

  // ---- 目标 JD ----
  Future<void> putGoal(Goal goal);
  Future<Goal?> getGoal(GoalId id);
  Future<List<Goal>> listGoals(ProfileId profileId);
  Future<void> deleteGoal(GoalId id);

  // ---- JD 能力要求 ----
  Future<void> putGoalRequirement(GoalRequirement requirement);
  Future<void> putGoalRequirements(List<GoalRequirement> requirements);
  Future<List<GoalRequirement>> listGoalRequirements(GoalId goalId);
  Future<void> deleteGoalRequirementsForGoal(GoalId goalId);

  // ---- JD 版本修订 ----
  Future<void> putGoalRevision(GoalRevision revision);
  Future<List<GoalRevision>> listGoalRevisions(
    GoalId? goalId, {
    ProfileId? profileId,
  });

  // ---- 知识项 ----
  Future<void> putKnowledgeItem(KnowledgeItem item);
  Future<KnowledgeItem?> getKnowledgeItem(KnowledgeItemId id);
  Future<List<KnowledgeItem>> listKnowledgeItems(ProfileId profileId);
  Future<void> deleteKnowledgeItem(KnowledgeItemId id);
  Future<void> deleteLearningRecordsForKnowledge(KnowledgeItemId id);

  // ---- 知识项 × JD 关联 ----
  Future<void> putGoalKnowledgeLink(GoalKnowledgeLink link);
  Future<List<GoalKnowledgeLink>> listGoalKnowledgeLinks(GoalId goalId);
  Future<void> deleteGoalKnowledgeLinksForGoal(GoalId goalId);

  // ---- 简历 ----
  Future<void> putResume(Resume resume);
  Future<Resume?> getResume(ResumeId id);
  Future<List<Resume>> listResumes(ProfileId profileId);

  // ---- 简历项目 ----
  Future<void> putProject(Project project);
  Future<List<Project>> listProjects(ResumeId resumeId);

  // ---- 简历主张 ----
  Future<void> putResumeClaim(ResumeClaim claim);
  Future<List<ResumeClaim>> listResumeClaims(ResumeId resumeId);

  // ---- 目标 × 简历关联 ----
  Future<void> putGoalResumeLink(GoalResumeLink link);
  Future<List<GoalResumeLink>> listGoalResumeLinks(GoalId goalId);

  // ---- 主张 × JD 要求映射 ----
  Future<void> putClaimRequirementLink(ClaimRequirementLink link);
  Future<List<ClaimRequirementLink>> listClaimRequirementLinks(ClaimId claimId);

  // ---- 资料来源 ----
  Future<void> putSource(Source source);
  Future<Source?> getSource(SourceId id);
  Future<List<Source>> listSources(ProfileId profileId);

  /// 删除一条来源及其分块与入库任务。
  ///
  /// 原文快照属于用户私人资料，删除资料后不得残留（否则备份包里仍然带全文）。
  Future<void> deleteSource(SourceId id);

  /// 列出与某知识点关联的来源 ID。
  Future<List<SourceId>> sourceIdsForKnowledge(KnowledgeItemId knowledgeItemId);

  // ---- 资料分块 ----
  Future<void> putSourceChunk(SourceChunk chunk);
  Future<void> putSourceChunks(List<SourceChunk> chunks);
  Future<List<SourceChunk>> listSourceChunks(SourceId sourceId);
  Future<void> deleteSourceChunksForKnowledge(KnowledgeItemId knowledgeItemId);

  // ---- 入库任务 ----
  Future<void> putIngestionJob(IngestionJob job);
  Future<IngestionJob?> getIngestionJob(String id);
  Future<List<IngestionJob>> listIngestionJobs(SourceId sourceId);

  // ---- 回测考点 ----
  Future<void> putReviewPoint(ReviewPoint point);
  Future<List<ReviewPoint>> listReviewPoints(KnowledgeItemId knowledgeItemId);

  // ---- 回测状态投影 ----
  Future<void> putReviewState(ReviewState state);
  Future<ReviewState?> getReviewState(ReviewPointId reviewPointId);
  Future<List<ReviewState>> listReviewStates(ProfileId profileId);
  Future<List<ReviewState>> listReviewStatesForKnowledge(
    KnowledgeItemId knowledgeItemId,
  );

  // ---- 评估事件（作答证据） ----
  Future<void> putAssessmentEvent(AssessmentEvent event);
  Future<List<AssessmentEvent>> listAssessmentEvents(SessionId sessionId);
  Future<List<AssessmentEvent>> listAssessmentEventsForReviewPoint(
    ReviewPointId reviewPointId,
  );

  // ---- 会话 ----
  Future<void> putSession(CoachSession session);
  Future<CoachSession?> getSession(SessionId id);
  Future<List<CoachSession>> listSessions(ProfileId profileId);

  // ---- 会话消息 ----
  Future<void> putMessage(CoachMessage message);
  Future<List<CoachMessage>> messagesOf(SessionId sessionId);

  // ---- 教学检查点 ----
  Future<void> putCheckpoint(LessonCheckpoint checkpoint);
  Future<LessonCheckpoint?> checkpointOf(String id);
  Future<List<LessonCheckpoint>> listCheckpoints(SessionId sessionId);

  // ---- 每日计划 ----
  Future<void> putDailyPlan(DailyPlan plan);
  Future<DailyPlan?> getDailyPlan(DailyPlanId id);
  Future<List<DailyPlan>> listDailyPlans(ProfileId profileId, {String? date});

  // ---- Versioned feature data / lifecycle ----
  Future<void> putExtension(CoachExtensionRecord record);
  Future<CoachExtensionRecord?> getExtension(
    ProfileId profileId,
    CoachExtensionKind kind,
    String id,
  );
  Future<List<CoachExtensionRecord>> listExtensions(
    ProfileId profileId,
    CoachExtensionKind kind,
  );
  Future<void> deleteExtension(
    ProfileId profileId,
    CoachExtensionKind kind,
    String id,
  );
  Future<void> putTombstone(CoachTombstone tombstone);
  Future<List<CoachTombstone>> listTombstones(ProfileId profileId);

  /// 修剪墓碑：同一实体的旧代次记录在同步判定里本来就是冗余（消费方只取
  /// 每个 key 的最大 generation 与 `profile_reset` 的最大 generation），
  /// 不修剪会让墓碑表随清除次数单调膨胀并整体进入备份包。
  ///
  /// 返回删除的条数。`profile_reset` 墓碑始终保留。
  Future<int> pruneTombstones(
    ProfileId profileId, {
    int keepPerEntity = 1,
    int maxEntityTombstones = 500,
  });
  Future<void> putCleanupTask(CoachCleanupTask task);
  Future<List<CoachCleanupTask>> listCleanupTasks(
    ProfileId profileId, {
    CleanupTaskStatus? status,
  });
}

/// 轻量内存实现，供单测与运行时兜底使用。所有数据仅在进程内存中。
/// 内存实现。实现 [CoachStoreMaintenance]（空操作）：内存数据在实例销毁时
/// 自然释放，没有 WAL/VACUUM 概念；实现该接口是为了让 `clearPersonalMaterials`
/// 的清理分支在测试（默认用内存实现）里也被真实走到，而不是被类型判断静默跳过。
class InMemoryCoachStore implements CoachStore, CoachStoreMaintenance {
  final Map<ProfileId, Profile> _profiles = {};
  final Map<GoalId, Goal> _goals = {};
  final List<GoalRequirement> _requirements = [];
  final List<GoalRevision> _revisions = [];
  final Map<KnowledgeItemId, KnowledgeItem> _knowledgeItems = {};
  final List<GoalKnowledgeLink> _goalKnowledgeLinks = [];
  final Map<ResumeId, Resume> _resumes = {};
  final List<Project> _projects = [];
  final List<ResumeClaim> _claims = [];
  final List<GoalResumeLink> _goalResumeLinks = [];
  final List<ClaimRequirementLink> _claimRequirementLinks = [];
  final Map<SourceId, Source> _sources = {};
  final List<SourceChunk> _chunks = [];
  final Map<String, IngestionJob> _ingestionJobs = {};
  final List<ReviewPoint> _reviewPoints = [];
  final Map<ReviewPointId, ReviewState> _reviewStates = {};
  final List<AssessmentEvent> _assessmentEvents = [];
  final Map<SessionId, CoachSession> _sessions = {};
  final Map<SessionId, List<CoachMessage>> _messages = {};
  final Map<String, LessonCheckpoint> _checkpoints = {};
  final Map<DailyPlanId, DailyPlan> _dailyPlans = {};
  final Map<String, CoachExtensionRecord> _extensions = {};
  final Map<String, CoachTombstone> _tombstones = {};
  final Map<String, CoachCleanupTask> _cleanupTasks = {};

  @override
  Future<void> clearProfileData(ProfileId profileId) => transaction(() async {
    final sourceIds = _sources.values
        .where((s) => s.profileId == profileId)
        .map((s) => s.id)
        .toSet();
    final sessionIds = _sessions.values
        .where((s) => s.profileId == profileId)
        .map((s) => s.id)
        .toSet();
    _chunks.removeWhere((c) => sourceIds.contains(c.sourceId));
    _messages.removeWhere((id, _) => sessionIds.contains(id));
    _goals.removeWhere((_, e) => e.profileId == profileId);
    _knowledgeItems.removeWhere((_, e) => e.profileId == profileId);
    _resumes.removeWhere((_, e) => e.profileId == profileId);
    _sources.removeWhere((_, e) => e.profileId == profileId);
    _ingestionJobs.removeWhere((_, e) => e.profileId == profileId);
    _reviewStates.removeWhere((_, e) => e.profileId == profileId);
    _sessions.removeWhere((_, e) => e.profileId == profileId);
    _checkpoints.removeWhere((_, e) => e.profileId == profileId);
    _dailyPlans.removeWhere((_, e) => e.profileId == profileId);
    _cleanupTasks.removeWhere((_, e) => e.profileId == profileId);
    _requirements.removeWhere((e) => e.profileId == profileId);
    _revisions.removeWhere((e) => e.profileId == profileId);
    _goalKnowledgeLinks.removeWhere((e) => e.profileId == profileId);
    _projects.removeWhere((e) => e.profileId == profileId);
    _claims.removeWhere((e) => e.profileId == profileId);
    _goalResumeLinks.removeWhere((e) => e.profileId == profileId);
    _claimRequirementLinks.removeWhere((e) => e.profileId == profileId);
    _reviewPoints.removeWhere((e) => e.profileId == profileId);
    _assessmentEvents.removeWhere((e) => e.profileId == profileId);
    _extensions.removeWhere(
      (_, e) =>
          e.profileId == profileId &&
          !{
            CoachExtensionKind.mcpConfigMetadata,
            CoachExtensionKind.embeddingConfigMetadata,
            CoachExtensionKind.providerConfigMetadata,
          }.contains(e.kind),
    );
  });

  Future<void> _transactionTail = Future.value();
  final Object _transactionKey = Object();

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    if (Zone.current[_transactionKey] == true) return action();
    final previous = _transactionTail;
    final done = Completer<void>();
    _transactionTail = done.future;
    await previous;
    try {
      final savedProfiles = Map.of(_profiles);
      final savedGoals = Map.of(_goals);
      final savedRequirements = [..._requirements];
      final savedRevisions = [..._revisions];
      final savedKnowledgeItems = Map.of(_knowledgeItems);
      final savedGoalKnowledgeLinks = [..._goalKnowledgeLinks];
      final savedResumes = Map.of(_resumes);
      final savedProjects = [..._projects];
      final savedClaims = [..._claims];
      final savedGoalResumeLinks = [..._goalResumeLinks];
      final savedClaimRequirementLinks = [..._claimRequirementLinks];
      final savedSources = Map.of(_sources);
      final savedChunks = [..._chunks];
      final savedIngestionJobs = Map.of(_ingestionJobs);
      final savedReviewPoints = [..._reviewPoints];
      final savedReviewStates = Map.of(_reviewStates);
      final savedAssessmentEvents = [..._assessmentEvents];
      final savedSessions = Map.of(_sessions);
      final savedMessages = _messages.map((k, v) => MapEntry(k, [...v]));
      final savedCheckpoints = Map.of(_checkpoints);
      final savedDailyPlans = Map.of(_dailyPlans);
      final savedExtensions = Map.of(_extensions);
      final savedTombstones = Map.of(_tombstones);
      final savedCleanupTasks = Map.of(_cleanupTasks);
      try {
        return await runZoned(action, zoneValues: {_transactionKey: true});
      } catch (_) {
        _profiles
          ..clear()
          ..addAll(savedProfiles);
        _goals
          ..clear()
          ..addAll(savedGoals);
        _requirements
          ..clear()
          ..addAll(savedRequirements);
        _revisions
          ..clear()
          ..addAll(savedRevisions);
        _knowledgeItems
          ..clear()
          ..addAll(savedKnowledgeItems);
        _goalKnowledgeLinks
          ..clear()
          ..addAll(savedGoalKnowledgeLinks);
        _resumes
          ..clear()
          ..addAll(savedResumes);
        _projects
          ..clear()
          ..addAll(savedProjects);
        _claims
          ..clear()
          ..addAll(savedClaims);
        _goalResumeLinks
          ..clear()
          ..addAll(savedGoalResumeLinks);
        _claimRequirementLinks
          ..clear()
          ..addAll(savedClaimRequirementLinks);
        _sources
          ..clear()
          ..addAll(savedSources);
        _chunks
          ..clear()
          ..addAll(savedChunks);
        _ingestionJobs
          ..clear()
          ..addAll(savedIngestionJobs);
        _reviewPoints
          ..clear()
          ..addAll(savedReviewPoints);
        _reviewStates
          ..clear()
          ..addAll(savedReviewStates);
        _assessmentEvents
          ..clear()
          ..addAll(savedAssessmentEvents);
        _sessions
          ..clear()
          ..addAll(savedSessions);
        _messages
          ..clear()
          ..addAll(savedMessages);
        _checkpoints
          ..clear()
          ..addAll(savedCheckpoints);
        _dailyPlans
          ..clear()
          ..addAll(savedDailyPlans);
        _extensions
          ..clear()
          ..addAll(savedExtensions);
        _tombstones
          ..clear()
          ..addAll(savedTombstones);
        _cleanupTasks
          ..clear()
          ..addAll(savedCleanupTasks);
        rethrow;
      }
    } finally {
      done.complete();
    }
  }

  @override
  Future<void> putProfile(Profile profile) async {
    _profiles[profile.id] = profile;
  }

  @override
  Future<Profile?> getProfile(ProfileId id) async => _profiles[id];

  @override
  Future<List<Profile>> listProfiles() async => [..._profiles.values];

  @override
  Future<void> putGoal(Goal goal) async => _goals[goal.id] = goal;

  @override
  Future<Goal?> getGoal(GoalId id) async => _goals[id];

  @override
  Future<List<Goal>> listGoals(ProfileId profileId) async =>
      _goals.values.where((g) => g.profileId == profileId).toList();

  @override
  Future<void> deleteGoal(GoalId id) async {
    final requirements = _requirements
        .where((r) => r.goalId == id)
        .map((r) => r.id)
        .toSet();
    _claimRequirementLinks.removeWhere(
      (l) => requirements.contains(l.requirementId),
    );
    _goals.remove(id);
    _requirements.removeWhere((r) => r.goalId == id);
    _goalKnowledgeLinks.removeWhere((l) => l.goalId == id);
    _goalResumeLinks.removeWhere((l) => l.goalId == id);
  }

  @override
  Future<void> putGoalRequirement(GoalRequirement requirement) async {
    _requirements.removeWhere(
      (r) => r.goalId == requirement.goalId && r.id == requirement.id,
    );
    _requirements.add(requirement);
  }

  @override
  Future<void> putGoalRequirements(List<GoalRequirement> requirements) async {
    for (final r in requirements) {
      await putGoalRequirement(r);
    }
  }

  @override
  Future<List<GoalRequirement>> listGoalRequirements(GoalId goalId) async =>
      _requirements.where((r) => r.goalId == goalId).toList();

  @override
  Future<void> deleteGoalRequirementsForGoal(GoalId goalId) async {
    _requirements.removeWhere((r) => r.goalId == goalId);
  }

  @override
  Future<void> putGoalRevision(GoalRevision revision) async {
    _revisions.removeWhere(
      (r) => r.goalId == revision.goalId && r.id == revision.id,
    );
    _revisions.add(revision);
  }

  @override
  Future<List<GoalRevision>> listGoalRevisions(
    GoalId? goalId, {
    ProfileId? profileId,
  }) async => _revisions
      .where(
        (r) =>
            (goalId == null || r.goalId == goalId) &&
            (profileId == null || r.profileId == profileId),
      )
      .toList();

  @override
  Future<void> putKnowledgeItem(KnowledgeItem item) async =>
      _knowledgeItems[item.id] = item;

  @override
  Future<KnowledgeItem?> getKnowledgeItem(KnowledgeItemId id) async =>
      _knowledgeItems[id];

  @override
  Future<List<KnowledgeItem>> listKnowledgeItems(ProfileId profileId) async =>
      _knowledgeItems.values.where((k) => k.profileId == profileId).toList();

  @override
  Future<void> deleteKnowledgeItem(KnowledgeItemId id) async {
    _knowledgeItems.remove(id);
    _goalKnowledgeLinks.removeWhere((link) => link.knowledgeItemId == id);
  }

  @override
  Future<void> deleteLearningRecordsForKnowledge(KnowledgeItemId id) async {
    final pointIds = _reviewPoints
        .where((point) => point.knowledgeItemId == id)
        .map((point) => point.id)
        .toSet();
    _reviewPoints.removeWhere((point) => point.knowledgeItemId == id);
    _reviewStates.removeWhere((key, state) => state.knowledgeItemId == id);
    _assessmentEvents.removeWhere((event) => event.knowledgeItemId == id);
    _checkpoints.removeWhere(
      (key, checkpoint) => checkpoint.knowledgeItemId == id,
    );
    final dedicatedSessions = _sessions.values
        .where((session) => session.knowledgeItemId == id)
        .map((session) => session.id)
        .toSet();
    _sessions.removeWhere((key, session) => dedicatedSessions.contains(key));
    _messages.removeWhere((key, value) => dedicatedSessions.contains(key));
    // Keep unrelated mixed sessions, but assessment events above have been
    // removed. `pointIds` intentionally documents that their projections go too.
    for (final pointId in pointIds) {
      _reviewStates.remove(pointId);
    }
  }

  @override
  Future<void> putGoalKnowledgeLink(GoalKnowledgeLink link) async {
    _goalKnowledgeLinks.removeWhere(
      (l) =>
          l.goalId == link.goalId && l.knowledgeItemId == link.knowledgeItemId,
    );
    _goalKnowledgeLinks.add(link);
  }

  @override
  Future<List<GoalKnowledgeLink>> listGoalKnowledgeLinks(GoalId goalId) async =>
      _goalKnowledgeLinks.where((l) => l.goalId == goalId).toList();

  @override
  Future<void> deleteGoalKnowledgeLinksForGoal(GoalId goalId) async {
    _goalKnowledgeLinks.removeWhere((l) => l.goalId == goalId);
  }

  @override
  Future<void> putResume(Resume resume) async => _resumes[resume.id] = resume;

  @override
  Future<Resume?> getResume(ResumeId id) async => _resumes[id];

  @override
  Future<List<Resume>> listResumes(ProfileId profileId) async =>
      _resumes.values.where((r) => r.profileId == profileId).toList();

  @override
  Future<void> putProject(Project project) async {
    _projects.removeWhere(
      (p) => p.resumeId == project.resumeId && p.id == project.id,
    );
    _projects.add(project);
  }

  @override
  Future<List<Project>> listProjects(ResumeId resumeId) async =>
      _projects.where((p) => p.resumeId == resumeId).toList();

  @override
  Future<void> putResumeClaim(ResumeClaim claim) async {
    _claims.removeWhere(
      (c) => c.resumeId == claim.resumeId && c.id == claim.id,
    );
    _claims.add(claim);
  }

  @override
  Future<List<ResumeClaim>> listResumeClaims(ResumeId resumeId) async =>
      _claims.where((c) => c.resumeId == resumeId).toList();

  @override
  Future<void> putGoalResumeLink(GoalResumeLink link) async {
    _goalResumeLinks.removeWhere(
      (l) => l.goalId == link.goalId && l.resumeId == link.resumeId,
    );
    _goalResumeLinks.add(link);
  }

  @override
  Future<List<GoalResumeLink>> listGoalResumeLinks(GoalId goalId) async =>
      _goalResumeLinks.where((l) => l.goalId == goalId).toList();

  @override
  Future<void> putClaimRequirementLink(ClaimRequirementLink link) async {
    _claimRequirementLinks.removeWhere(
      (l) => l.claimId == link.claimId && l.requirementId == link.requirementId,
    );
    _claimRequirementLinks.add(link);
  }

  @override
  Future<List<ClaimRequirementLink>> listClaimRequirementLinks(
    ClaimId claimId,
  ) async => _claimRequirementLinks.where((l) => l.claimId == claimId).toList();

  @override
  Future<void> putSource(Source source) async => _sources[source.id] = source;

  @override
  Future<Source?> getSource(SourceId id) async => _sources[id];

  @override
  Future<List<Source>> listSources(ProfileId profileId) async =>
      _sources.values.where((s) => s.profileId == profileId).toList();

  @override
  Future<void> putSourceChunk(SourceChunk chunk) async {
    _chunks.removeWhere((c) => c.id == chunk.id);
    _chunks.add(chunk);
  }

  @override
  Future<void> putSourceChunks(List<SourceChunk> chunks) async {
    for (final c in chunks) {
      await putSourceChunk(c);
    }
  }

  @override
  Future<List<SourceChunk>> listSourceChunks(SourceId sourceId) async =>
      _chunks.where((c) => c.sourceId == sourceId).toList()
        ..sort((a, b) => a.index.compareTo(b.index));

  @override
  Future<void> deleteSourceChunksForKnowledge(
    KnowledgeItemId knowledgeItemId,
  ) async {
    _chunks.removeWhere((chunk) => chunk.knowledgeItemId == knowledgeItemId);
  }

  @override
  Future<List<SourceId>> sourceIdsForKnowledge(
    KnowledgeItemId knowledgeItemId,
  ) async => _chunks
      .where((chunk) => chunk.knowledgeItemId == knowledgeItemId)
      .map((chunk) => chunk.sourceId)
      .toSet()
      .toList();

  @override
  Future<void> deleteSource(SourceId id) async {
    _sources.remove(id);
    _chunks.removeWhere((chunk) => chunk.sourceId == id);
    _ingestionJobs.removeWhere(
      (_, job) => job.sourceId == id,
    );
  }

  @override
  Future<void> putIngestionJob(IngestionJob job) async =>
      _ingestionJobs[job.id] = job;

  @override
  Future<IngestionJob?> getIngestionJob(String id) async => _ingestionJobs[id];

  @override
  Future<List<IngestionJob>> listIngestionJobs(SourceId sourceId) async =>
      _ingestionJobs.values.where((j) => j.sourceId == sourceId).toList();

  @override
  Future<void> putReviewPoint(ReviewPoint point) async {
    _reviewPoints.removeWhere(
      (p) => p.knowledgeItemId == point.knowledgeItemId && p.id == point.id,
    );
    _reviewPoints.add(point);
  }

  @override
  Future<List<ReviewPoint>> listReviewPoints(
    KnowledgeItemId knowledgeItemId,
  ) async =>
      _reviewPoints.where((p) => p.knowledgeItemId == knowledgeItemId).toList();

  @override
  Future<void> putReviewState(ReviewState state) async =>
      _reviewStates[state.reviewPointId] = state;

  @override
  Future<ReviewState?> getReviewState(ReviewPointId reviewPointId) async =>
      _reviewStates[reviewPointId];

  @override
  Future<List<ReviewState>> listReviewStates(ProfileId profileId) async =>
      _reviewStates.values.where((s) => s.profileId == profileId).toList();

  @override
  Future<List<ReviewState>> listReviewStatesForKnowledge(
    KnowledgeItemId knowledgeItemId,
  ) async => _reviewStates.values
      .where((s) => s.knowledgeItemId == knowledgeItemId)
      .toList();

  @override
  Future<void> putAssessmentEvent(AssessmentEvent event) async {
    _assessmentEvents.removeWhere((e) => e.id == event.id);
    _assessmentEvents.add(event);
  }

  @override
  Future<List<AssessmentEvent>> listAssessmentEvents(
    SessionId sessionId,
  ) async => _assessmentEvents.where((e) => e.sessionId == sessionId).toList();

  @override
  Future<List<AssessmentEvent>> listAssessmentEventsForReviewPoint(
    ReviewPointId reviewPointId,
  ) async =>
      _assessmentEvents.where((e) => e.reviewPointId == reviewPointId).toList();

  @override
  Future<void> putSession(CoachSession session) async =>
      _sessions[session.id] = session;

  @override
  Future<CoachSession?> getSession(SessionId id) async => _sessions[id];

  @override
  Future<List<CoachSession>> listSessions(ProfileId profileId) async =>
      _sessions.values.where((s) => s.profileId == profileId).toList();

  @override
  Future<void> putMessage(CoachMessage message) async {
    final messages = _messages[message.sessionId] ??= [];
    messages.removeWhere((m) => m.id == message.id);
    messages.add(message);
    messages.sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  @override
  Future<List<CoachMessage>> messagesOf(SessionId sessionId) async => [
    ...?_messages[sessionId],
  ];

  @override
  Future<void> putCheckpoint(LessonCheckpoint checkpoint) async =>
      _checkpoints[checkpoint.id] = checkpoint;

  @override
  Future<LessonCheckpoint?> checkpointOf(String id) async => _checkpoints[id];

  @override
  Future<List<LessonCheckpoint>> listCheckpoints(SessionId sessionId) async =>
      _checkpoints.values.where((c) => c.sessionId == sessionId).toList();

  @override
  Future<void> putDailyPlan(DailyPlan plan) async =>
      _dailyPlans[plan.id] = plan;

  @override
  Future<DailyPlan?> getDailyPlan(DailyPlanId id) async => _dailyPlans[id];

  @override
  Future<List<DailyPlan>> listDailyPlans(
    ProfileId profileId, {
    String? date,
  }) async => _dailyPlans.values
      .where(
        (p) => p.profileId == profileId && (date == null || p.date == date),
      )
      .toList();

  String _extensionKey(
    ProfileId profileId,
    CoachExtensionKind kind,
    String id,
  ) => '$profileId:${kind.name}:$id';

  @override
  Future<void> putExtension(CoachExtensionRecord record) async {
    _extensions[_extensionKey(record.profileId, record.kind, record.id)] =
        record;
  }

  @override
  Future<CoachExtensionRecord?> getExtension(
    ProfileId profileId,
    CoachExtensionKind kind,
    String id,
  ) async => _extensions[_extensionKey(profileId, kind, id)];

  @override
  Future<List<CoachExtensionRecord>> listExtensions(
    ProfileId profileId,
    CoachExtensionKind kind,
  ) async {
    final records = _extensions.values
        .where((record) => record.profileId == profileId && record.kind == kind)
        .toList()
      // 与 Drift 实现（ORDER BY updatedAt ASC）保持同一排序契约，
      // 否则依赖顺序的消费方在测试与生产里表现不同。
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return records;
  }

  @override
  Future<void> deleteExtension(
    ProfileId profileId,
    CoachExtensionKind kind,
    String id,
  ) async {
    _extensions.remove(_extensionKey(profileId, kind, id));
  }

  @override
  Future<void> putTombstone(CoachTombstone tombstone) async {
    _tombstones['${tombstone.profileId}:${tombstone.generation}:${tombstone.key}'] =
        tombstone;
  }

  @override
  Future<List<CoachTombstone>> listTombstones(ProfileId profileId) async =>
      _tombstones.values.where((item) => item.profileId == profileId).toList();

  @override
  Future<int> pruneTombstones(
    ProfileId profileId, {
    int keepPerEntity = 1,
    int maxEntityTombstones = 500,
  }) async {
    final mine = _tombstones.entries
        .where((e) => e.value.profileId == profileId)
        .toList();
    // 按实体分组，组内只留最新 keepPerEntity 个代次。
    final byEntity = <String, List<MapEntry<String, CoachTombstone>>>{};
    for (final entry in mine) {
      if (entry.value.entityType == 'profile_reset') continue;
      byEntity.putIfAbsent(entry.value.key, () => []).add(entry);
    }
    var removed = 0;
    for (final group in byEntity.values) {
      group.sort((a, b) => b.value.generation.compareTo(a.value.generation));
      for (final stale in group.skip(keepPerEntity)) {
        _tombstones.remove(stale.key);
        removed++;
      }
    }
    // 总量上限：仍超限时按删除时间从旧到新淘汰，profile_reset 不参与。
    final survivors =
        _tombstones.values
            .where(
              (t) => t.profileId == profileId && t.entityType != 'profile_reset',
            )
            .toList()
          ..sort((a, b) => a.deletedAt.compareTo(b.deletedAt));
    for (final t in survivors.take((survivors.length - maxEntityTombstones)
        .clamp(0, survivors.length))) {
      _tombstones.remove('${t.profileId}:${t.generation}:${t.key}');
      removed++;
    }
    return removed;
  }

  @override
  Future<void> putCleanupTask(CoachCleanupTask task) async {
    _cleanupTasks[task.id] = task;
  }

  @override
  Future<List<CoachCleanupTask>> listCleanupTasks(
    ProfileId profileId, {
    CleanupTaskStatus? status,
  }) async => _cleanupTasks.values
      .where(
        (item) =>
            item.profileId == profileId &&
            (status == null || item.status == status),
      )
      .toList();

  /// 内存实现没有 WAL/VACUUM，无需物理压缩；此方法存在是为了让维护路径
  /// 在测试中不因类型判断被跳过。
  @override
  Future<void> compactDeletedData() async {}
}
