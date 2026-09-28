/// 教练运行时状态（今天 / 模拟面试 / 学习 · 回测）。
///
/// 职责：
/// - 持有本地档案与 [CoachStore]，维护「今天」的计划、当前会话与消息；
/// - 调用 [PlanService] / [CoachRuntime] / [ReviewScheduler] 等确定性组件；
/// - **不**直接决定内容真伪，也**不**把模型回答当作事实写入。
///
/// 目标与资料（JD / 简历 / 文档）的导入由 `GoalProvider` 负责；两者共享同一个
/// [CoachStore]，导入完成后由 `GoalProvider.onDataChanged` 触发本 provider 重载。
library;

import 'package:flutter/foundation.dart';

import '../coach/application/coach_runtime.dart';
import '../coach/application/session_scope_service.dart';
import '../coach/tools/remote_tools.dart';
import '../coach/persistence/extension_records.dart';
import '../coach/lifecycle/deletion_executor.dart';
import '../coach/lifecycle/deletion_planner.dart';
import '../coach/application/coach_agent.dart';
import '../coach/application/plan_service.dart';
import '../coach/application/prompt_builder.dart';
import '../coach/domain/common.dart';
import '../coach/domain/evidence.dart';
import '../coach/domain/goal.dart';
import '../coach/domain/knowledge.dart';
import '../coach/domain/plan.dart';
import '../coach/domain/profile.dart';
import '../coach/domain/resume.dart';
import '../coach/domain/session.dart';
import '../coach/knowledge/source.dart';
import '../coach/knowledge/index.dart';
import '../coach/knowledge/embedding.dart';
import '../coach/knowledge/retriever.dart';
import '../coach/workflows/workflows.dart';
import '../coach/application/assessment_review.dart';
import 'dart:convert';

import '../coach/persistence/coach_backup.dart';
import '../coach/persistence/coach_store.dart';
import '../coach/persistence/workflow_repository.dart';
import '../coach/policies/evidence_reducer.dart';
import '../coach/policies/review_scheduler.dart';

/// 单机首版默认档案 ID。保留档案边界，便于未来多档案切换。
const String kDefaultProfileId = 'local-default';

class CoachProvider extends ChangeNotifier {
  CoachProvider({
    required CoachStore store,
    Clock? clock,
    IdGenerator? idGen,
    PlanService? planService,
    CoachModelBindingProvider? modelBindingProvider,
    CoachRulesProvider? rulesProvider,
    KnowledgeRetriever? retriever,
    CoachRemoteToolsProvider? remoteToolsProvider,
    this.profileId = kDefaultProfileId,
  }) : _store = store,
       _clock = clock ?? const SystemClock(),
       _idGen = idGen ?? IdGenerator(),
       _planService = planService ?? const PlanService(),
       _modelBindingProvider = modelBindingProvider {
    _runtime = CoachRuntime(store: store, idGen: _idGen, clock: _clock);
    _workflowRepo = WorkflowRepository(store);
    _retriever = retriever ?? KnowledgeRetriever(index: InMemoryIndex());
    _agent = CoachAgent(
      store: store,
      runtime: _runtime,
      modelBindingProvider: modelBindingProvider ?? () => null,
      rulesProvider:
          rulesProvider ?? () async => const <CoachRuleSection, String>{},
      retriever: _retriever,
      remoteToolsProvider: remoteToolsProvider,
    );
  }

  final CoachStore _store;
  final Clock _clock;
  final IdGenerator _idGen;
  final PlanService _planService;
  final CoachModelBindingProvider? _modelBindingProvider;
  late final CoachRuntime _runtime;
  late final KnowledgeRetriever _retriever;
  late final CoachAgent _agent;
  late final WorkflowRepository _workflowRepo;

  void setEmbeddingProvider(EmbeddingProvider? provider) {
    _retriever.embedding = provider;
    notifyListeners();
  }

  bool get embeddingDegraded => _retriever.embeddingDegraded;

  /// 当前档案 ID。
  final String profileId;

  CoachStore get store => _store;
  CoachRuntime get runtime => _runtime;
  Clock get clock => _clock;

  /// ID 生成器（计划/课程等本地实体 ID 一律由 App 分配，模型只能建议命名）。
  IdGenerator get idGen => _idGen;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _isGenerating = false;
  bool _reviewingAssessment = false;
  bool get isGenerating => _isGenerating || _reviewingAssessment;

  Future<void> reviewAssessment(
    AssessmentEvent event, {
    bool reassess = false,
  }) async {
    if (isGenerating) throw StateError('Wait for the current reply');
    _reviewingAssessment = true;
    notifyListeners();
    try {
      final service = AssessmentReviewService(
        store: _store,
        profileId: profileId,
        binding: _modelBindingProvider ?? () => null,
        clock: _clock,
      );
      if (reassess) {
        await service.reassess(event);
      } else {
        await service.dispute(event);
      }
      await reload();
    } finally {
      _reviewingAssessment = false;
      notifyListeners();
    }
  }

  Object? _lastGenerationError;
  Object? get lastGenerationError => _lastGenerationError;
  bool get modelConfigured => _modelBindingProvider?.call() != null;

  Profile? _profile;
  Profile? get profile => _profile;

  SessionMode _mode = SessionMode.learning;
  SessionMode get mode => _mode;

  /// 今天（或最近一天）的计划。
  DailyPlan? _todayPlan;
  DailyPlan? get todayPlan => _todayPlan?.date == todayKey ? _todayPlan : null;
  List<DailyPlan> _extraPlans = [];
  List<DailyPlan> get extraPlans =>
      List.unmodifiable(_extraPlans.where((p) => p.date == todayKey));

  CoachSession? _activeSession;
  CoachSession? get activeSession => _activeSession;

  List<CoachSession> _sessions = const [];
  List<CoachSession> get sessions => List.unmodifiable(_sessions);
  List<CoachMessage> _messages = const [];
  List<CoachMessage> get messages => List.unmodifiable(_messages);

  List<Goal> _goals = const [];
  List<Goal> get goals => List.unmodifiable(_goals);

  GoalId? _activeGoalId;
  GoalId? get activeGoalId => _activeGoalId;

  Goal? get activeGoal {
    final id = _activeGoalId;
    if (id == null) return null;
    return _goals.where((g) => g.id == id).firstOrNull;
  }

  List<GoalRequirement> _activeRequirements = const [];
  List<GoalRequirement> get activeRequirements =>
      List.unmodifiable(_activeRequirements);

  List<Resume> _resumes = const [];
  List<Resume> get resumes => List.unmodifiable(_resumes);

  ResumeId? _activeResumeId;
  ResumeId? get activeResumeId => _activeResumeId;

  Resume? get activeResume {
    final id = _activeResumeId;
    if (id == null) return null;
    return _resumes.where((r) => r.id == id).firstOrNull;
  }

  List<ResumeClaim> _activeClaims = const [];
  List<ResumeClaim> get activeClaims => List.unmodifiable(_activeClaims);

  List<Source> _sources = const [];
  List<Source> get sources => List.unmodifiable(_sources);

  List<ReviewState> _reviewStates = const [];
  List<ReviewState> get reviewStates => List.unmodifiable(_reviewStates);

  List<KnowledgeItem> _knowledgeItems = const [];
  List<KnowledgeItem> get knowledgeItems => List.unmodifiable(_knowledgeItems);

  /// 到期回测池（用于今天计划）。
  List<ReviewState> get dueReviewStates {
    final now = _clock.now();
    return _reviewStates.where((s) => s.canReview(now)).toList();
  }

  int get dueCount => dueReviewStates.length;

  /// 今天的计划进度（基础项完成数 / 基础项总数）。
  int get completedCount => todayPlan?.completedCount ?? 0;
  int get planDenominator => todayPlan?.denominator ?? 0;

  // ── 加载 ────────────────────────────────────────────────────────────

  /// 加载档案、目标、简历、资料与今日计划。
  Future<void> load() async {
    final now = _clock.now();
    await retryCleanup();
    var profile = await _store.getProfile(profileId);
    if (profile == null) {
      profile = Profile(
        id: profileId,
        displayName: '本机档案',
        createdAt: now,
        updatedAt: now,
      );
      await _store.putProfile(profile);
    }
    _profile = profile;

    _goals = await _store.listGoals(profileId);
    _resumes = await _store.listResumes(profileId);
    _sources = await _store.listSources(profileId);
    _knowledgeItems = (await _store.listKnowledgeItems(
      profileId,
    )).where((k) => k.contentStatus != 'removed').toList();
    _reviewStates = await _store.listReviewStates(profileId);
    // Rehydrate the local retrieval index from durable sources. Importers may
    // update the store while this provider is alive; addChunk replaces by id.
    _retriever.index.clearProfile(profileId);
    for (final source in _sources) {
      _retriever.index.addSource(source);
      for (final chunk in await _store.listSourceChunks(source.id)) {
        _retriever.index.addChunk(
          IndexedChunk(
            chunk,
            profileId,
            knowledgeItemId: chunk.knowledgeItemId,
          ),
        );
      }
    }

    // 目标/简历选择：沿用已有选择，否则取第一个可用项。
    if (!_goals.any((g) => g.id == _activeGoalId)) _activeGoalId = null;
    if (_activeGoalId == null && _goals.isNotEmpty) {
      _activeGoalId = _goals
          .firstWhere((g) => g.active, orElse: () => _goals.first)
          .id;
    }
    await _reloadActiveRequirements();

    if (!_resumes.any((r) => r.id == _activeResumeId)) _activeResumeId = null;
    if (_activeResumeId == null && _resumes.isNotEmpty) {
      _activeResumeId = _resumes.first.id;
    }
    await _reloadActiveClaims();

    await _loadTodayPlan();
    _sessions = await _store.listSessions(profileId);
    _sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final adjustments = await _workflowRepo.listAdjustments(profileId);
    final undoable = adjustments.where(
      (a) =>
          a.undoAllowed &&
          a.after.id == todayPlan?.id &&
          a.after.version == todayPlan?.version &&
          a.after.date == todayKey,
    );
    _lastAdjustmentId = undoable.isEmpty ? null : undoable.first.id;
    if (_activeSession != null) {
      _activeSession = await _store.getSession(_activeSession!.id);
      _messages = _activeSession == null
          ? const []
          : await _store.messagesOf(_activeSession!.id);
    }
    if (_activeSession == null) {
      final unfinished =
          (await _store.listSessions(
              profileId,
            )).where((s) => s.status != RuntimeStatus.completed).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (unfinished.isNotEmpty) {
        var session = unfinished.first;
        if (session.status == RuntimeStatus.generating ||
            session.status == RuntimeStatus.toolRunning) {
          session = session.copyWith(status: RuntimeStatus.paused);
          await _store.putSession(session);
        }
        _activeSession = session;
        _mode = session.mode;
        _messages = await _store.messagesOf(session.id);
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// 外部数据变更后重载（GoalProvider 导入完成时调用）。
  Future<void> reload() => load();

  Future<void> _reloadActiveRequirements() async {
    final id = _activeGoalId;
    if (id == null) {
      _activeRequirements = const [];
      return;
    }
    _activeRequirements = await _store.listGoalRequirements(id);
  }

  Future<void> _reloadActiveClaims() async {
    final id = _activeResumeId;
    if (id == null) {
      _activeClaims = const [];
      return;
    }
    _activeClaims = await _store.listResumeClaims(id);
  }

  // ── 模式与选择 ──────────────────────────────────────────────────────

  void setMode(SessionMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  Future<void> selectGoal(GoalId? goalId) async {
    if (goalId != null && !_goals.any((g) => g.id == goalId)) {
      throw StateError("Unknown goal in profile");
    }
    _activeGoalId = goalId;
    await _reloadActiveRequirements();
    notifyListeners();
  }

  Future<void> selectResume(ResumeId? resumeId) async {
    if (resumeId != null && !_resumes.any((r) => r.id == resumeId)) {
      throw StateError("Unknown resume in profile");
    }
    _activeResumeId = resumeId;
    await _reloadActiveClaims();
    notifyListeners();
  }

  // ── 今天计划 ────────────────────────────────────────────────────────

  String get todayKey => _dateKey(_clock.now());

  Future<void> _loadTodayPlan() async {
    final plans = await _store.listDailyPlans(profileId, date: todayKey);
    // 优先取基础计划（非 isExtra），其次取最新一份。
    _extraPlans = plans.where((p) => p.isExtra).toList();
    plans.removeWhere((p) => p.isExtra);
    if (plans.isEmpty) {
      _todayPlan = null;
      return;
    }
    plans.sort((a, b) => b.version.compareTo(a.version));
    _todayPlan = plans.firstWhere((p) => !p.isExtra, orElse: () => plans.first);
  }

  /// 计划候选范围：当前目标关联的知识点集合，以及其中「 scoped、未学、未失效」的可学项。
  ///
  /// 基础计划与顺延卡片必须共用同一份候选池，否则顺延卡片会跨出当前目标范围、
  /// 或把已学过的知识点重新当作新知识排进今天（§9.7）。
  Future<({Set<String> scope, List<KnowledgeItem> learnable})>
  _planCandidates() async {
    final links = _activeGoalId == null
        ? <GoalKnowledgeLink>[]
        : await _store.listGoalKnowledgeLinks(_activeGoalId!);
    final scope = _activeGoalId == null
        ? _knowledgeItems.map((k) => k.id).toSet()
        : links.map((l) => l.knowledgeItemId).toSet();
    final learned = _reviewStates
        .where((s) => s.status != ReviewStatus.unseen)
        .map((s) => s.knowledgeItemId)
        .toSet();
    final learnable = _knowledgeItems
        .where(
          (k) =>
              scope.contains(k.id) &&
              !learned.contains(k.id) &&
              k.contentStatus != 'stale',
        )
        .toList();
    return (scope: scope, learnable: learnable);
  }

  /// 装配一次工作流编译请求。三处调用点（基础计划 / 顺延卡片 / 训练安排预览）
  /// 必须走这里，避免参数各自手抄后产生行为分歧。
  Future<WorkflowCompileRequest> _buildCompileRequest({
    required WorkflowTemplate template,
    required int minutesBudget,
    String? rotationCursor,
  }) async {
    final candidates = await _planCandidates();
    final projectIds = <ProjectId>{};
    for (final resume in _resumes) {
      projectIds.addAll((await _store.listProjects(resume.id)).map((p) => p.id));
    }
    return WorkflowCompileRequest(
      profileId: profileId,
      date: todayKey,
      timezone: _clock.now().timeZoneName,
      template: template,
      idGen: _idGen,
      clock: _clock,
      minutesBudget: minutesBudget,
      duePool: _reviewStates
          .where((r) => candidates.scope.contains(r.knowledgeItemId))
          .toList(),
      learnable: candidates.learnable
          .map((k) => LearnableKnowledgeRef(id: k.id, title: k.title))
          .toList(),
      knownGoalIds: _goals.map((g) => g.id).toSet(),
      knownResumeIds: _resumes.map((r) => r.id).toSet(),
      knownProjectIds: projectIds,
      knownKnowledgeIds: _knowledgeItems.map((k) => k.id).toSet(),
      rotationCursor: rotationCursor,
    );
  }

  /// 确保今天有基础计划；没有则按到期池与可学项生成并冻结（§9.6）。
  Future<DailyPlan> ensureTodayPlan() => _store.transaction(() async {
    await _loadTodayPlan();
    final existing = todayPlan;
    if (existing != null) {
      await _materializeDeferredWorkflowCards();
      return existing;
    }

    final budget = _profile?.dailyMinutesBudget ?? 25;
    final cursorRecord = await _store.getExtension(
      profileId,
      CoachExtensionKind.syncMetadata,
      'review_rotation',
    );
    final cursor = cursorRecord?.value['reviewPointId'] as String?;
    WorkflowTemplate? template;
    final templateId = _profile?.defaultWorkflowTemplateId;
    if (templateId != null) {
      final candidates = [
        ...BuiltInWorkflows.all,
        ...await _workflowRepo.listTemplates(profileId),
      ];
      template = candidates.where((t) => t.id == templateId).firstOrNull;
      if (template == null) throw StateError('Default workflow source removed');
    }
    final compiled = template == null
        ? null
        : const WorkflowCompiler().compile(
            await _buildCompileRequest(
              template: template,
              minutesBudget: budget,
              rotationCursor: cursor,
            ),
          );
    if (compiled != null && !compiled.ok) {
      throw StateError('Default workflow needs source selection');
    }
    final candidates = await _planCandidates();
    final plan =
        compiled?.plan ??
        _planService.generateBasePlan(
          profileId: profileId,
          date: todayKey,
          timezone: _clock.now().timeZoneName,
          duePool: _reviewStates
              .where((s) => candidates.scope.contains(s.knowledgeItemId))
              .toList(),
          learnable: candidates.learnable,
          idGen: _idGen,
          baseMinutes: budget,
          rotationCursor: cursor,
        );
    final frozen = _planService.freeze(
      DailyPlan(
        id: plan.id,
        profileId: plan.profileId,
        date: plan.date,
        timezone: plan.timezone,
        planItems: plan.planItems
            .map(
              (i) => i.copyWith(
                goalId: i.goalId ?? _activeGoalId,
                resumeId: i.resumeId ?? _activeResumeId,
              ),
            )
            .toList(),
        baseMinutes: plan.baseMinutes,
        version: plan.version,
        revisionNote: plan.revisionNote,
      ),
      clock: _clock,
    );
    await _store.putDailyPlan(frozen);
    final selectedPoints = frozen.planItems
        .expand((p) => p.reviewPointIds)
        .toList();
    if (selectedPoints.isNotEmpty) {
      await _store.putExtension(
        CoachExtensionRecord(
          profileId: profileId,
          kind: CoachExtensionKind.syncMetadata,
          id: 'review_rotation',
          revision: (cursorRecord?.revision ?? 0) + 1,
          updatedAt: _clock.now(),
          value: {'reviewPointId': selectedPoints.last},
        ),
      );
    }
    _todayPlan = frozen;
    await _materializeDeferredWorkflowCards();
    notifyListeners();
    return frozen;
  });

  /// Deferred cards are resolved against tomorrow's actual knowledge/review
  /// state, once, as extras. They never change the frozen base denominator.
  Future<void> _materializeDeferredWorkflowCards() async {
    final records = await _store.listExtensions(
      profileId,
      CoachExtensionKind.workflowPlanSnapshot,
    );
    for (final record in records) {
      if (record.value['deferredToDate'] != todayKey ||
          record.value['deferredConsumed'] == true) {
        continue;
      }
      final raw = record.value['template'];
      final ids = (record.value['deferredCardIds'] as List? ?? const [])
          .whereType<String>()
          .toSet();
      if (raw is! Map || ids.isEmpty) continue;
      final template = WorkflowTemplate.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      final cards = template.cards
          .where((card) => ids.contains(card.id))
          .toList();
      if (cards.isEmpty) continue;
      final deferredTemplate = template.copyWith(cards: cards);
      final requiredMinutes = cards.fold<int>(
        0,
        (sum, card) =>
            sum + (card.estimatedMinutes ?? card.type.defaultMinutes),
      );
      final compiled = const WorkflowCompiler().compile(
        await _buildCompileRequest(
          template: deferredTemplate,
          minutesBudget: requiredMinutes,
        ),
      );
      if (!compiled.ok) continue;
      final plan = compiled.plan!;
      if (plan.planItems.isNotEmpty) {
        final extra = DailyPlan(
          id: _idGen.next(),
          profileId: profileId,
          date: todayKey,
          timezone: plan.timezone,
          planItems: plan.planItems,
          baseMinutes: 0,
          version: 1,
          frozenAt: _clock.now(),
          isExtra: true,
          revisionNote: 'deferred_from:${record.id}',
        );
        await _store.putDailyPlan(extra);
      }
      await _store.putExtension(
        CoachExtensionRecord(
          profileId: profileId,
          kind: CoachExtensionKind.workflowPlanSnapshot,
          id: record.id,
          revision: record.revision + 1,
          value: {
            ...record.value,
            'deferredConsumed': true,
            'deferredGeneratedCount': plan.planItems.length,
            'deferredSkippedCardIds': compiled.skippedCardIds,
          },
          updatedAt: _clock.now(),
        ),
      );
      await _loadTodayPlan();
    }
  }

  /// 勾选/取消勾选某个计划项（只改完成标记，不改分母，§9.6）。
  Future<void> togglePlanItem(String planItemId) async {
    final candidates = [?todayPlan, ...extraPlans];
    final matching = candidates.where(
      (p) => p.planItems.any((i) => i.id == planItemId),
    );
    if (matching.isEmpty) return;
    final plan = matching.first;
    final items = plan.planItems
        .map(
          (i) => i.id == planItemId ? i.copyWith(completed: !i.completed) : i,
        )
        .toList();
    final revised = _planService.revise(
      plan,
      revisionNote: '用户手动更新完成状态',
      newItems: items,
    );
    await _store.putDailyPlan(revised);
    if (revised.isExtra) {
      _extraPlans = _extraPlans
          .map((p) => p.id == plan.id ? revised : p)
          .toList();
    } else {
      _todayPlan = revised;
    }
    notifyListeners();
  }

  /// 基础结束后追加额外计划（不计入基础分母，§9.6）。
  Future<void> addExtraPlan() async {
    final plan = await ensureTodayPlan();
    if (plan.completedCount != plan.denominator) return;
    final assigned = [
      ...plan.planItems,
      ...extraPlans.expand((p) => p.planItems),
    ].expand((p) => p.reviewPointIds).toSet();
    final scope = _activeGoalId == null
        ? _knowledgeItems.map((k) => k.id).toSet()
        : (await _store.listGoalKnowledgeLinks(
            _activeGoalId!,
          )).map((l) => l.knowledgeItemId).toSet();
    final extra = <PlanItem>[];
    final borrow = const ReviewSelector().select(
      _reviewStates
          .where(
            (s) =>
                scope.contains(s.knowledgeItemId) &&
                !assigned.contains(s.reviewPointId),
          )
          .toList(),
      count: 2,
      now: _clock.now(),
    );
    for (final r in borrow) {
      extra.add(
        PlanItem(
          id: _idGen.next(),
          type: PlanItemType.reviewLearned,
          // 标题由 UI 按类型本地化；这里不放用户可见文案。
          title: '',
          knowledgeItemId: r.knowledgeItemId,
          reviewPointIds: [r.reviewPointId],
          estimatedMinutes: 6,
          goalId: _activeGoalId,
          resumeId: _activeResumeId,
        ),
      );
    }
    final assignedKnowledge = [
      ...plan.planItems,
      ...extraPlans.expand((p) => p.planItems),
    ].map((p) => p.knowledgeItemId).toSet();
    for (final knowledge in _knowledgeItems.where(
      (k) => scope.contains(k.id) && !assignedKnowledge.contains(k.id),
    )) {
      if (extra.length >= 2) break;
      final points = _reviewStates
          .where(
            (s) =>
                s.knowledgeItemId == knowledge.id &&
                s.status == ReviewStatus.unseen,
          )
          .toList();
      if (points.isEmpty) continue;
      extra.add(
        PlanItem(
          id: _idGen.next(),
          type: PlanItemType.learnKnowledge,
          title: '',
          knowledgeItemId: knowledge.id,
          reviewPointIds: points.map((s) => s.reviewPointId).toList(),
          estimatedMinutes: 8,
          goalId: _activeGoalId,
          resumeId: _activeResumeId,
        ),
      );
    }
    if (extra.isEmpty) return;
    final extended = _planService.addExtra(plan, extra: extra, idGen: _idGen);
    await _store.putDailyPlan(extended);
    _extraPlans = [..._extraPlans, extended];
    notifyListeners();
  }

  // ── 知识点与考点 ────────────────────────────────────────────────────

  /// 新建知识点并为其生成考点（每个知识点最多 8 个，§9.4）。
  Future<KnowledgeItem> addKnowledgeItem(
    String title, {
    List<String> reviewPointLabels = const [],
    List<String> aliases = const [],
  }) async {
    final now = _clock.now();
    final item = KnowledgeItem(
      id: _idGen.next(),
      profileId: profileId,
      title: title,
      aliases: aliases,
      createdAt: now,
      updatedAt: now,
    );
    await _store.putKnowledgeItem(item);

    final labels = reviewPointLabels.take(maxReviewPointsPerKnowledge);
    for (final label in labels) {
      final point = ReviewPoint(
        id: _idGen.next(),
        profileId: profileId,
        knowledgeItemId: item.id,
        label: label,
        createdAt: now,
      );
      await _store.putReviewPoint(point);
      await _store.putReviewState(
        ReviewState(
          reviewPointId: point.id,
          profileId: profileId,
          knowledgeItemId: item.id,
        ),
      );
    }
    _knowledgeItems = (await _store.listKnowledgeItems(
      profileId,
    )).where((k) => k.contentStatus != 'removed').toList();
    _reviewStates = await _store.listReviewStates(profileId);
    notifyListeners();
    return item;
  }

  /// 标记知识点已学完：为各考点建首次待测（不记独立通过，§9.5）。
  Future<void> markKnowledgeLearned(KnowledgeItemId knowledgeItemId) async {
    const scheduler = ReviewScheduler();
    final points = await _store.listReviewPoints(knowledgeItemId);
    for (final p in points) {
      final current =
          await _store.getReviewState(p.id) ??
          ReviewState(
            reviewPointId: p.id,
            profileId: profileId,
            knowledgeItemId: knowledgeItemId,
          );
      final next = scheduler.apply(
        current: current,
        conclusion: const EvidenceConclusion(
          trigger: SchedulerTrigger.learningComplete,
          spaced: false,
          hintUsed: false,
          validity: EvidenceValidity.accepted,
          advanceAllowed: true,
          outcome: ReviewOutcome.hintCompleted,
        ),
        clock: _clock,
      );
      await _store.putReviewState(next);
    }
    _reviewStates = await _store.listReviewStates(profileId);
    notifyListeners();
  }

  /// 会话内教学记录（教学污染检查）。
  void recordTaught(SessionId sessionId, ReviewPointId reviewPointId) {
    _runtime.recordTaught(sessionId, reviewPointId);
  }

  // ── 会话 ────────────────────────────────────────────────────────────

  /// 开始一个新会话，并设为当前会话。
  Future<CoachSession> startSession({
    SessionMode? mode,
    KnowledgeItemId? knowledgeItemId,
    ReviewPointId? reviewPointId,
    List<ProjectId> projectIds = const [],
    bool generateOpening = false,
    GoalId? goalId,
    ResumeId? resumeId,
    List<ReviewPointId> reviewPointIds = const [],
    int? durationMinutes,
    int? maxQuestions,
    String? interviewStyle,
    String? planItemId,
    String? parentSessionId,
  }) async {
    if (isGenerating) {
      throw StateError('Wait for the current turn or cancel it');
    }
    final selectedGoal = goalId ?? _activeGoalId;
    final selectedResume = resumeId ?? _activeResumeId;
    if (durationMinutes != null &&
        (durationMinutes < 1 || durationMinutes > 120)) {
      throw ArgumentError.value(durationMinutes, 'durationMinutes');
    }
    final coverage = await SessionScopeService(_store).capture(
      profileId: profileId,
      goalId: selectedGoal,
      resumeId: selectedResume,
      projectIds: projectIds,
      knowledgeItemId: knowledgeItemId,
      reviewPointIds: reviewPointIds.isEmpty && reviewPointId != null
          ? [reviewPointId]
          : reviewPointIds,
      maxQuestions: maxQuestions,
      planItemId: planItemId,
      parentSessionId: parentSessionId,
    );
    int? goalRevision;
    if (selectedGoal != null) {
      final revisions = await _store.listGoalRevisions(selectedGoal);
      if (revisions.isNotEmpty) {
        revisions.sort((a, b) => b.revisionNumber.compareTo(a.revisionNumber));
        goalRevision = revisions.first.revisionNumber;
      }
    }
    final session = await _runtime.startSession(
      profileId: profileId,
      mode: mode ?? _mode,
      goalId: selectedGoal,
      goalRevision: goalRevision ?? (selectedGoal == null ? null : 1),
      resumeId: selectedResume,
      // 固定当前简历修订号：之后改简历不会改写本场已保存的原答。
      resumeRevision: selectedResume == null
          ? null
          : (await _store.getResume(selectedResume))?.revision,
      projectIds: projectIds,
      knowledgeItemId: knowledgeItemId,
      reviewPointId: reviewPointId,
      coverageSnapshot: coverage,
      durationMinutes:
          durationMinutes ??
          ((mode ?? _mode) == SessionMode.interview ? 20 : null),
      interviewStyle: interviewStyle,
    );
    if (_activeSession != null &&
        _activeSession!.status != RuntimeStatus.completed) {
      await _store.putSession(
        _activeSession!.copyWith(status: RuntimeStatus.paused),
      );
    }
    _activeSession = session;
    _mode = session.mode;
    _sessions = [session, ..._sessions];
    _messages = const [];
    await ensureTodayPlan();
    notifyListeners();
    if (generateOpening && modelConfigured) {
      await generateCurrentReply();
    }
    return session;
  }

  /// 追加用户原答（保存原答，自增轮次，§7.3）。
  Future<CoachMessage> sendUserMessage(
    String content, {
    List<String> references = const [],
    bool isAnswerShown = false,
  }) async {
    var session = _activeSession ?? await startSession();
    if (session.mode != SessionMode.learning &&
        RegExp(
          r'^(继续学习|切换到学习|先讲解|我想继续学习|switch to learning|continue learning)[。.!！\s]*$',
          caseSensitive: false,
        ).hasMatch(content.trim())) {
      await _runtime.appendUserMessage(sessionId: session.id, content: content);
      _activeSession = await _store.getSession(session.id);
      final previous = session;
      final pointId =
          previous.reviewPointId ??
          previous.coverageSnapshot?.reviewPointIds.firstOrNull;
      final knowledgeId =
          previous.knowledgeItemId ??
          previous.coverageSnapshot?.knowledgeItemIds.firstOrNull;
      session = await startSession(
        mode: SessionMode.learning,
        goalId: previous.goalId,
        resumeId: previous.resumeId,
        projectIds: previous.projectIds,
        knowledgeItemId: knowledgeId,
        reviewPointId: pointId,
        parentSessionId: previous.id,
      );
    }
    final msg = await _runtime.appendUserMessage(
      sessionId: session.id,
      content: content,
      references: references,
      isAnswerShown: isAnswerShown,
    );
    _activeSession = await _store.getSession(session.id);
    _messages = await _store.messagesOf(session.id);
    notifyListeners();
    if (modelConfigured) {
      try {
        await generateCurrentReply();
      } catch (_) {
        // The original answer is already durable. The page exposes the error
        // and a retry action; an AI failure never deletes or scores the answer.
      }
    }
    return msg;
  }

  /// Generate the next coach turn from the current durable session. This is
  /// also the retry path after network/auth/format failures.
  Future<CoachTurnResult> generateCurrentReply() async {
    final session = _activeSession;
    if (session == null) throw StateError('No active session');
    if (!modelConfigured) throw const CoachModelUnavailableException();
    _isGenerating = true;
    _lastGenerationError = null;
    notifyListeners();
    try {
      final result = await _agent.run(session.id);
      _activeSession = await _store.getSession(session.id);
      _messages = await _store.messagesOf(session.id);
      _reviewStates = await _store.listReviewStates(profileId);
      if (_activeSession?.status == RuntimeStatus.completed) {
        await _completeLinkedPlanItem();
      }
      _sessions = await _store.listSessions(profileId);
      _sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return result;
    } catch (error) {
      _lastGenerationError = error;
      _activeSession = await _store.getSession(session.id);
      _messages = await _store.messagesOf(session.id);
      rethrow;
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<bool> cancelGeneration() async {
    final session = _activeSession;
    if (session == null) return false;
    final cancelled = await _agent.cancel(session.id);
    if (cancelled) {
      _activeSession = await _store.getSession(session.id);
      _isGenerating = false;
      notifyListeners();
    }
    return cancelled;
  }

  /// 载入某个历史会话与其消息。
  Future<void> openSession(SessionId sessionId) async {
    final session = await _store.getSession(sessionId);
    if (session == null) return;
    if (session.profileId != profileId) {
      throw StateError("Session belongs to another profile");
    }
    _activeSession = session;
    _mode = session.mode;
    _messages = await _store.messagesOf(sessionId);
    notifyListeners();
  }

  /// 结束当前会话。
  Future<void> endSession() async {
    final session = _activeSession;
    if (session == null) return;
    await cancelGeneration();
    await _runtime.finishModelTurn(session.id, completed: true);
    final ended = (await _store.getSession(session.id))!;
    await _store.putSession(
      ended.copyWith(stopReason: 'user_ended', partial: true),
    );
    _activeSession = await _store.getSession(session.id);
    notifyListeners();
  }

  /// Execute the frozen item scope. Reopening resumes its durable session.
  Future<CoachSession> startPlanItem(String itemId) async {
    final plans = await _store.listDailyPlans(profileId, date: todayKey);
    plans.sort((a, b) => b.version.compareTo(a.version));
    final plan = plans
        .where((p) => p.planItems.any((i) => i.id == itemId))
        .first;
    final item = plan.planItems.firstWhere((i) => i.id == itemId);
    final previous = (await _store.listSessions(profileId)).where(
      (s) =>
          s.coverageSnapshot?.planItemId == itemId &&
          s.status != RuntimeStatus.completed,
    );
    if (previous.isNotEmpty) {
      await openSession(previous.first.id);
      return _activeSession!;
    }
    final mode = switch (item.type) {
      PlanItemType.learnKnowledge => SessionMode.learning,
      PlanItemType.reviewLearned => SessionMode.review,
      PlanItemType.projectTraining =>
        item.projectMode == 'explain'
            ? SessionMode.learning
            : SessionMode.interview,
      PlanItemType.mockInterview => SessionMode.interview,
    };
    final session = await startSession(
      mode: mode,
      goalId: item.goalId,
      resumeId: item.resumeId,
      knowledgeItemId: item.knowledgeItemId,
      reviewPointId: item.reviewPointIds.length == 1
          ? item.reviewPointIds.first
          : null,
      reviewPointIds: item.reviewPointIds,
      projectIds: [?item.projectId],
      durationMinutes: item.estimatedMinutes,
      maxQuestions: item.maxQuestions,
      planItemId: item.id,
    );
    final runs = await _workflowRepo.listRuns(profileId);
    final existing = runs.where((r) => r.planId == plan.id);
    final templateMatch = RegExp(
      r'^workflow:(.+)@v(\d+)$',
    ).firstMatch(plan.revisionNote ?? '');
    final run = existing.isEmpty
        ? WorkflowRun(
            id: _idGen.next(),
            profileId: profileId,
            templateId: templateMatch?.group(1) ?? 'daily',
            templateVersion:
                int.tryParse(templateMatch?.group(2) ?? '') ?? plan.version,
            cardIds: plan.planItems.map((i) => i.id).toList(),
            completedIds: plan.planItems
                .where((i) => i.completed)
                .map((i) => i.id)
                .toSet(),
            planId: plan.id,
            currentIndex: plan.planItems.indexWhere((i) => i.id == itemId),
            status: RuntimeStatus.waitingUser,
          )
        : existing.first.copyWith(
            currentIndex: plan.planItems.indexWhere((i) => i.id == itemId),
            status: RuntimeStatus.waitingUser,
          );
    await _workflowRepo.putRun(run, updatedAt: _clock.now());
    notifyListeners();
    return session;
  }

  Future<void> _completeLinkedPlanItem() => _store.transaction(() async {
    final itemId = _activeSession?.coverageSnapshot?.planItemId;
    if (itemId == null) return;
    await _loadTodayPlan();
    final matching = [
      ?todayPlan,
      ...extraPlans,
    ].where((p) => p.planItems.any((i) => i.id == itemId));
    if (matching.isEmpty) return;
    final plan = matching.first;
    if (!plan.planItems.firstWhere((i) => i.id == itemId).completed) {
      await togglePlanItem(itemId);
    }
    for (final run in await _workflowRepo.listRuns(profileId)) {
      if (run.planId == plan.id && run.currentCardId == itemId) {
        await _workflowRepo.putRun(run.advance(), updatedAt: _clock.now());
      }
    }
    await _applyWeakWorkflowBranch(plan);
  });

  Future<void> _applyWeakWorkflowBranch(DailyPlan plan) async {
    final snapshot = await _store.getExtension(
      profileId,
      CoachExtensionKind.workflowPlanSnapshot,
      plan.id,
    );
    if (snapshot == null || snapshot.value['weakBranchApplied'] == true) return;
    final raw = snapshot.value['template'];
    if (raw is! Map) return;
    final template = WorkflowTemplate.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
    final cards = template.cards.where(
      (card) =>
          card.condition == WorkflowCondition.reteachOnceWhenWeak &&
          card.type == PlanItemType.learnKnowledge,
    );
    if (cards.isEmpty) return;
    final states = await _store.listReviewStates(profileId);
    for (final card in cards) {
      final weak = states.where(
        (state) =>
            state.consecutiveWeaknesses >= 2 &&
            (card.knowledgeItemId == null ||
                card.knowledgeItemId == state.knowledgeItemId),
      );
      if (weak.isEmpty) continue;
      final knowledgeId = weak.first.knowledgeItemId;
      if (plan.planItems.any((item) => item.workflowCardId == card.id)) break;
      final knowledge = await _store.getKnowledgeItem(knowledgeId);
      if (knowledge == null ||
          knowledge.profileId != profileId ||
          knowledge.contentStatus == 'stale') {
        continue;
      }
      final extra = DailyPlan(
        id: _idGen.next(),
        profileId: profileId,
        date: plan.date,
        timezone: plan.timezone,
        baseMinutes: 0,
        version: 1,
        frozenAt: _clock.now(),
        isExtra: true,
        revisionNote: 'workflow_weak_branch:${plan.id}',
        planItems: [
          PlanItem(
            id: _idGen.next(),
            type: PlanItemType.learnKnowledge,
            title: '',
            knowledgeItemId: knowledgeId,
            goalId: card.goalId ?? template.scope.goalId,
            estimatedMinutes: card.estimatedMinutes ?? 8,
            workflowCardId: card.id,
          ),
        ],
      );
      await _store.putDailyPlan(extra);
      await _store.putExtension(
        CoachExtensionRecord(
          profileId: profileId,
          kind: CoachExtensionKind.workflowPlanSnapshot,
          id: plan.id,
          revision: snapshot.revision + 1,
          value: {
            ...snapshot.value,
            'weakBranchApplied': true,
            'weakBranchPlanId': extra.id,
          },
          updatedAt: _clock.now(),
        ),
      );
      await _loadTodayPlan();
      break;
    }
  }

  // ── 训练安排（§9.7） ────────────────────────────────────────────────

  /// 用编译器产出的计划替换今天的计划，并落库。
  ///
  /// 应用前会把旧计划记成一条可审计的 [PlanAdjustment]（含差异），用于撤销。
  /// 没有旧计划（今天第一次安排）时撤销不可用，这是如实行为而非缺陷。
  Future<void> applyPlan(
    DailyPlan plan, {
    WorkflowTemplate? workflowTemplate,
    List<String> deferredCardIds = const [],
  }) => _store.transaction(() async {
    if (plan.profileId != profileId || plan.date != todayKey) {
      throw StateError('Plan scope mismatch');
    }
    await _loadTodayPlan();
    final before = todayPlan;
    final startedIds = (await _store.listSessions(
      profileId,
    )).map((s) => s.coverageSnapshot?.planItemId).whereType<String>().toSet();
    final protected =
        before?.planItems
            .where(
              (i) =>
                  i.completed || i.manualOverride || startedIds.contains(i.id),
            )
            .toList() ??
        <PlanItem>[];
    final keptIds = protected.map((i) => i.id).toSet();
    final applied = DailyPlan(
      id: plan.id,
      profileId: profileId,
      date: todayKey,
      timezone: plan.timezone,
      planItems: [
        ...protected,
        ...plan.planItems.where((i) => !keptIds.contains(i.id)),
      ],
      baseMinutes: plan.baseMinutes,
      version: (before?.version ?? 0) + 1,
      frozenAt: before?.frozenAt ?? plan.frozenAt,
      revisionNote: plan.revisionNote,
    );
    if (before != null) {
      final adjustment = PlanAdjustment(
        id: 'adjust.${_idGen.next()}',
        profileId: profileId,
        planId: applied.id,
        before: before,
        after: applied,
        diff: _planDiffTokens(before, applied),
        createdAt: _clock.now(),
      );
      await _workflowRepo.putAdjustment(adjustment);
      _lastAdjustmentId = adjustment.id;
    } else {
      _lastAdjustmentId = null;
    }
    await _store.putDailyPlan(applied);
    if (workflowTemplate != null) {
      final previousSnapshot = await _store.getExtension(
        profileId,
        CoachExtensionKind.workflowPlanSnapshot,
        applied.id,
      );
      await _store.putExtension(
        CoachExtensionRecord(
          profileId: profileId,
          kind: CoachExtensionKind.workflowPlanSnapshot,
          id: applied.id,
          revision: (previousSnapshot?.revision ?? 0) + 1,
          value: {
            'template': workflowTemplate.toJson(),
            'deferredCardIds': deferredCardIds,
            'deferredToDate': deferredCardIds.isEmpty
                ? null
                : _clock
                      .now()
                      .add(const Duration(days: 1))
                      .toIso8601String()
                      .substring(0, 10),
            'weakBranchApplied': false,
          },
          updatedAt: _clock.now(),
        ),
      );
    }
    _todayPlan = applied;
    notifyListeners();
  });

  /// 撤销最近一次「应用计划」：恢复旧计划快照。
  ///
  /// 只有当计划自应用后**没有被再次改动**（版本号一致）且该调整未被撤销过时
  /// 才允许；否则返回 false，UI 不显示撤销入口或提示已失效。
  Future<bool> undoPlanApply() => _store.transaction(() async {
    final id = _lastAdjustmentId;
    if (id == null) return false;
    final adjustments = await _workflowRepo.listAdjustments(profileId);
    final adjustment = adjustments.where((a) => a.id == id).firstOrNull;
    if (adjustment == null || !adjustment.undoAllowed) return false;
    await _loadTodayPlan();
    if (todayPlan == null ||
        todayPlan!.id != adjustment.after.id ||
        todayPlan!.version != adjustment.after.version ||
        adjustment.after.date != todayKey) {
      return false;
    }
    final restored = DailyPlan(
      id: _idGen.next(),
      profileId: adjustment.before.profileId,
      date: adjustment.before.date,
      timezone: adjustment.before.timezone,
      planItems: adjustment.before.planItems,
      baseMinutes: adjustment.before.baseMinutes,
      version: adjustment.after.version + 1,
      frozenAt: adjustment.before.frozenAt,
      revisionNote: adjustment.before.revisionNote,
    );
    await _workflowRepo.putAdjustment(
      PlanAdjustment(
        id: adjustment.id,
        profileId: adjustment.profileId,
        planId: adjustment.planId,
        before: adjustment.before,
        after: adjustment.after,
        diff: adjustment.diff,
        createdAt: adjustment.createdAt,
        undoAllowed: false,
        undoReason: 'already_undone',
      ),
    );
    final appliedSnapshot = await _store.getExtension(
      profileId,
      CoachExtensionKind.workflowPlanSnapshot,
      adjustment.after.id,
    );
    if (appliedSnapshot != null) {
      await _store.putExtension(
        CoachExtensionRecord(
          profileId: profileId,
          kind: CoachExtensionKind.workflowPlanSnapshot,
          id: appliedSnapshot.id,
          revision: appliedSnapshot.revision + 1,
          value: {
            ...appliedSnapshot.value,
            'deferredConsumed': true,
            'cancelledByUndo': true,
          },
          updatedAt: _clock.now(),
        ),
      );
    }
    await _store.putDailyPlan(restored);
    _todayPlan = restored;
    _lastAdjustmentId = null;
    notifyListeners();
    return true;
  });

  /// 是否存在可撤销的上次应用（供 UI 决定是否显示撤销入口）。
  bool get canUndoPlanApply => _lastAdjustmentId != null;
  String? _lastAdjustmentId;

  /// 计划差异的协议化记号（非 UI 文案）：数量与分钟级变化，撤销审计用。
  List<String> _planDiffTokens(DailyPlan before, DailyPlan after) {
    final tokens = <String>[];
    final added = after.planItems.length - before.planItems.length;
    if (added != 0) tokens.add('items:${added > 0 ? '+' : ''}$added');
    final minutes = after.baseMinutes - before.baseMinutes;
    if (minutes != 0) {
      tokens.add('minutes:${minutes > 0 ? '+' : ''}$minutes');
    }
    tokens.add('version:${before.version}->${after.version}');
    return tokens;
  }

  // ── 备份导出与恢复（§9.1） ──────────────────────────────────────────

  /// 导出教练库完整备份（含所有档案实体与扩展记录，不含 AI 凭证）。
  Future<String> exportCoachBackupJson() async {
    final backup = await exportCoachBackup(_store);
    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  /// 从备份 JSON 恢复（合并式 upsert，不删除备份后新增的数据）。
  /// 返回恢复的实体数；结构或完整性校验失败时抛 [FormatException]。
  Future<int> importCoachBackupJson(String content) async {
    if (isGenerating) {
      throw StateError('Cannot restore during model generation');
    }
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('backup must be a json object');
    }
    final result = await restoreCoachBackup(
      _store,
      decoded.map((k, v) => MapEntry(k.toString(), v)),
    );
    _activeSession = null;
    _messages = const [];
    await load();
    return result.restoredEntities;
  }

  // ── 训练安排模板持久化（§9.7） ────────────────────────────────────────

  /// 用户另存的模板列表（内置模板不入库，由 [BuiltInWorkflows] 提供）。
  Future<List<WorkflowTemplate>> listUserWorkflowTemplates() =>
      _workflowRepo.listTemplates(profileId);

  /// 另存/更新一份用户模板。
  ///
  /// - [fromTemplate] 非空时以它为底（内置模板 fork 成用户模板）；
  /// - 同名用户模板已存在时**更新**它（版本 +1），不产生重名副本。
  Future<WorkflowTemplate> saveWorkflowTemplate({
    required String name,
    required List<WorkflowCard> cards,
    WorkflowScope? scope,
    WorkflowTemplate? fromTemplate,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'template name is empty');
    }
    final existing = await _workflowRepo.listTemplates(profileId);
    final same = existing.where((t) => t.name == trimmed).firstOrNull;
    final now = _clock.now();
    if (same != null) {
      final updated = same.copyWith(
        cards: cards,
        scope: scope ?? same.scope,
        version: same.version + 1,
      );
      await _workflowRepo.putTemplate(
        updated,
        profileId: profileId,
        updatedAt: now,
      );
      return updated;
    }
    final base = fromTemplate;
    final created = base == null
        ? WorkflowTemplate(
            id: 'user.${_idGen.next()}',
            name: trimmed,
            cards: cards,
            scope: scope ?? const WorkflowScope(),
          )
        : base
              .fork(newId: 'user.${_idGen.next()}', newName: trimmed)
              .copyWith(cards: cards);
    final withScope = scope == null ? created : created.copyWith(scope: scope);
    await _workflowRepo.putTemplate(
      withScope,
      profileId: profileId,
      updatedAt: now,
    );
    return withScope;
  }

  /// 删除一份用户模板；内置模板（id 不以 `user.` 开头）拒绝删除。
  Future<bool> deleteWorkflowTemplate(String id) async {
    if (!id.startsWith('user.')) return false;
    final existing = await _workflowRepo.listTemplates(profileId);
    if (!existing.any((t) => t.id == id)) return false;
    final current = _profile;
    if (current != null && current.defaultWorkflowTemplateId == id) {
      final cleared = current.copyWith(
        clearDefaultWorkflowTemplateId: true,
        updatedAt: _clock.now(),
      );
      await _store.putProfile(cleared);
      _profile = cleared;
    }
    await _workflowRepo.deleteTemplate(profileId, id);
    notifyListeners();
    return true;
  }

  /// 记下「今后默认」使用的训练安排模板 id（§9.7）。
  ///
  /// 只写入非空 id；清除默认值需要额外语义，本版未提供入口，避免误清。
  Future<void> setDefaultWorkflowTemplate(String templateId) async {
    final current = _profile;
    if (current == null || templateId.isEmpty) return;
    final next = current.copyWith(
      defaultWorkflowTemplateId: templateId,
      updatedAt: _clock.now(),
    );
    await _store.putProfile(next);
    _profile = next;
    notifyListeners();
  }

  /// 调整每天可用时间预算（分钟），影响后续计划生成的基准时长。
  Future<void> setDailyMinutesBudget(int minutes) async {
    final current = _profile;
    if (current == null || minutes <= 0) return;
    final next = current.copyWith(
      dailyMinutesBudget: minutes,
      updatedAt: _clock.now(),
    );
    await _store.putProfile(next);
    _profile = next;
    notifyListeners();
  }

  Future<void> retryCleanup() => DeletionExecutor(store: _store, clock: _clock)
      .runPendingCleanupForProfile(
        profileId,
        externalCleaner: (task, ids) async {
          switch (task.type) {
            case CleanupTaskIds.knowledgeCards:
            case CleanupTaskIds.embeddings:
            case CleanupTaskIds.sourceChunks:
              _retriever.index.clearProfile(profileId);
              final embedding = _retriever.embedding;
              if (embedding is EmbeddingCache) {
                (embedding as EmbeddingCache).clearCache();
              }
            default:
              throw StateError('Unknown cleanup task');
          }
        },
      );

  Future<void> clearPersonalMaterials() async {
    await cancelGeneration();
    await _store.transaction(() async {
      final markers = await _store.listTombstones(profileId);
      final generation =
          markers.fold<int>(0, (v, t) => t.generation > v ? t.generation : v) +
          1;
      await _store.clearProfileData(profileId);
      await _store.putTombstone(
        CoachTombstone(
          profileId: profileId,
          entityType: 'profile_reset',
          entityId: profileId,
          generation: generation,
          deletedAt: _clock.now(),
          operationId: _idGen.next(),
        ),
      );
      // 墓碑只增不减会让墓碑表随清除次数单调膨胀、并整体进入备份包；
      // 同步判定只需要每个实体的最新代次与 profile_reset 的最大代次，旧的可以修剪。
      await _store.pruneTombstones(profileId);
      if (_profile != null) {
        await _store.putProfile(
          _profile!.copyWith(
            clearDefaultWorkflowTemplateId: true,
            updatedAt: _clock.now(),
          ),
        );
      }
    });
    _retriever.index.clearProfile(profileId);
    final embedding = _retriever.embedding;
    if (embedding is EmbeddingCache) (embedding as EmbeddingCache).clearCache();
    final storage = _store;
    if (storage is CoachStoreMaintenance) {
      await (storage as CoachStoreMaintenance).compactDeletedData();
    }
    _activeSession = null;
    _messages = const [];
    _sessions = const [];
    _todayPlan = null;
    _extraPlans = [];
    await load();
  }

  // ── 工具 ────────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
