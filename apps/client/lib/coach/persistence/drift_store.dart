/// Drift 实现 [CoachStore]（§9.2）。
///
/// 使用免 codegen 的原始 SQL（customSelect/customInsert/customUpdate/customDelete）
/// + 手动映射。日期以 ISO 字符串、枚举以 .name、列表以 JSON 字符串持久化。
/// 仅在原生平台（Flutter 运行）使用；纯 Dart VM 单测使用 [InMemoryCoachStore]。
library;

import 'dart:convert';
import 'package:drift/drift.dart';

import '../domain/common.dart';
import '../domain/profile.dart';
import '../domain/goal.dart';
import '../domain/knowledge.dart';
import '../domain/resume.dart';
import '../domain/evidence.dart';
import '../domain/session.dart';
import '../domain/plan.dart';
import '../knowledge/source.dart';
import 'coach_store.dart';
import 'database.dart';
import 'extension_records.dart';

/// 基于 Drift 原生 SQLite 的 CoachStore 实现。
class DriftCoachStore implements CoachStore, CoachStoreMaintenance {
  DriftCoachStore(this.db);

  final CoachDatabase db;

  @override
  Future<void> clearProfileData(ProfileId profileId) => transaction(() async {
    await _delete(
      'DELETE FROM sourceChunks WHERE sourceId IN (SELECT id FROM sources WHERE profileId = ?)',
      [profileId],
    );
    await _delete('DELETE FROM messages WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM checkpoints WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM assessmentEvents WHERE profileId = ?', [
      profileId,
    ]);
    await _delete('DELETE FROM reviewStates WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM reviewPoints WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM ingestionJobs WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM sources WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM claimRequirementLinks WHERE profileId = ?', [
      profileId,
    ]);
    await _delete('DELETE FROM goalResumeLinks WHERE profileId = ?', [
      profileId,
    ]);
    await _delete('DELETE FROM resumeClaims WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM projects WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM resumes WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM goalKnowledgeLinks WHERE profileId = ?', [
      profileId,
    ]);
    await _delete('DELETE FROM goalRequirements WHERE profileId = ?', [
      profileId,
    ]);
    await _delete('DELETE FROM goalRevisions WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM goals WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM knowledgeItems WHERE profileId = ?', [
      profileId,
    ]);
    await _delete('DELETE FROM sessions WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM dailyPlans WHERE profileId = ?', [profileId]);
    await _delete('DELETE FROM coachCleanupTasks WHERE profileId = ?', [
      profileId,
    ]);
    await _delete(
      'DELETE FROM coachExtensions WHERE profileId = ? AND kind NOT IN (?, ?, ?)',
      [
        profileId,
        CoachExtensionKind.mcpConfigMetadata.name,
        CoachExtensionKind.embeddingConfigMetadata.name,
        CoachExtensionKind.providerConfigMetadata.name,
      ],
    );
  });

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    await db.ensureSchema();
    return db.transaction(action);
  }

  @override
  Future<void> compactDeletedData() async {
    await db.ensureSchema();
    final checkpoint = await db
        .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
        .get();
    if (checkpoint.isNotEmpty &&
        (checkpoint.first.data['busy'] as int? ?? 0) != 0) {
      throw StateError('Storage is in use; retry cleanup');
    }
    await db.customStatement('VACUUM');
    await db.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
  }

  Future<void> close() => db.close();

  /// schema 就绪只需要确认一次：连接打开时 drift 已跑过版本化 migration，
  /// 这里的心跳只是防御性确认，不能每条业务 SQL 都重复执行（负载直接翻倍）。
  Future<void>? _schemaReady;

  Future<void> _ensureSchemaOnce() =>
      _schemaReady ??= db.ensureSchema();

  // ---- 通用 SQL 助手 ----
  List<Variable<Object>> _vars(List<Object?> values) =>
      values.map((v) => Variable<Object>(v)).toList();

  Future<List<QueryRow>> _select(
    String sql, [
    List<Object?> values = const [],
  ]) async {
    await _ensureSchemaOnce();
    return db.customSelect(sql, variables: _vars(values)).get();
  }

  Future<void> _exec(String sql, [List<Object?> values = const []]) async {
    await _ensureSchemaOnce();
    await db.customInsert(sql, variables: _vars(values));
  }

  Future<void> _delete(String sql, [List<Object?> values = const []]) async {
    await _ensureSchemaOnce();
    await db.customUpdate(sql, variables: _vars(values));
  }

  DateTime? _dt(QueryRow r, String col) {
    final s = r.read<String?>(col);
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _iso(DateTime? dt) => dt?.toIso8601String() ?? '';

  List<String> _list(QueryRow r, String col) {
    final s = r.read<String?>(col);
    if (s == null || s.isEmpty) return const [];
    final decoded = jsonDecode(s);
    return (decoded as List).map((e) => e as String).toList();
  }

  String _json(Object? value) => jsonEncode(value);

  bool _bool(QueryRow r, String col) => (r.read<int?>(col) ?? 0) == 1;

  T _enumOr<T extends Enum>(
    QueryRow r,
    String col,
    List<T> values,
    T fallback,
  ) {
    final s = r.read<String?>(col);
    if (s == null) return fallback;
    for (final v in values) {
      if (v.name == s) return v;
    }
    return fallback;
  }

  // ---- Profile ----
  @override
  Future<void> putProfile(Profile p) => _exec(
    'INSERT OR REPLACE INTO profiles '
    '(id, displayName, dailyMinutesBudget, baseLevel, teachingPreference, '
    'defaultWorkflowTemplateId, createdAt, updatedAt) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      p.id,
      p.displayName,
      p.dailyMinutesBudget,
      p.baseLevel,
      p.teachingPreference,
      p.defaultWorkflowTemplateId,
      _iso(p.createdAt),
      _iso(p.updatedAt),
    ],
  );

  @override
  Future<Profile?> getProfile(ProfileId id) async {
    final rows = await _select('SELECT * FROM profiles WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _profileFromRow(rows.first);
  }

  @override
  Future<List<Profile>> listProfiles() async {
    final rows = await _select('SELECT * FROM profiles');
    return rows.map(_profileFromRow).toList();
  }

  Profile _profileFromRow(QueryRow r) => Profile(
    id: r.read<String>('id'),
    displayName: r.read<String?>('displayName'),
    dailyMinutesBudget: r.read<int>('dailyMinutesBudget'),
    baseLevel: r.read<String?>('baseLevel'),
    teachingPreference: r.read<String?>('teachingPreference'),
    defaultWorkflowTemplateId: r.read<String?>('defaultWorkflowTemplateId'),
    createdAt: _dt(r, 'createdAt')!,
    updatedAt: _dt(r, 'updatedAt')!,
  );

  // ---- Goal ----
  @override
  Future<void> putGoal(Goal g) => _exec(
    'INSERT OR REPLACE INTO goals '
    '(id, profileId, title, originalText, originalUrl, canonicalUrl, platform, '
    'externalJobId, company, location, salaryText, description, postedAt, expiresAt, '
    'extractionStatus, contentHash, active, archived, createdAt, updatedAt) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      g.id,
      g.profileId,
      g.title,
      g.originalText,
      g.originalUrl,
      g.canonicalUrl,
      g.platform,
      g.externalJobId,
      g.company,
      g.location,
      g.salaryText,
      g.description,
      _iso(g.postedAt),
      _iso(g.expiresAt),
      g.extractionStatus,
      g.contentHash,
      g.active ? 1 : 0,
      g.archived ? 1 : 0,
      _iso(g.createdAt),
      _iso(g.updatedAt),
    ],
  );

  @override
  Future<Goal?> getGoal(GoalId id) async {
    final rows = await _select('SELECT * FROM goals WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _goalFromRow(rows.first);
  }

  @override
  Future<List<Goal>> listGoals(ProfileId profileId) async {
    final rows = await _select('SELECT * FROM goals WHERE profileId = ?', [
      profileId,
    ]);
    return rows.map(_goalFromRow).toList();
  }

  @override
  Future<void> deleteGoal(GoalId id) => transaction(() async {
    await _delete(
      'DELETE FROM claimRequirementLinks WHERE requirementId IN '
      '(SELECT id FROM goalRequirements WHERE goalId = ?)',
      [id],
    );
    await _delete('DELETE FROM goals WHERE id = ?', [id]);
    await _delete('DELETE FROM goalRequirements WHERE goalId = ?', [id]);
    await _delete('DELETE FROM goalKnowledgeLinks WHERE goalId = ?', [id]);
    await _delete('DELETE FROM goalResumeLinks WHERE goalId = ?', [id]);
    // Version snapshots remain available to historical sessions.
  });

  Goal _goalFromRow(QueryRow r) => Goal(
    id: r.read<String>('id'),
    profileId: r.read<String>('profileId'),
    title: r.read<String>('title'),
    originalText: r.read<String>('originalText'),
    originalUrl: r.read<String?>('originalUrl'),
    canonicalUrl: r.read<String?>('canonicalUrl'),
    platform: r.read<String?>('platform'),
    externalJobId: r.read<String?>('externalJobId'),
    company: r.read<String?>('company'),
    location: r.read<String?>('location'),
    salaryText: r.read<String?>('salaryText'),
    description: r.read<String?>('description'),
    postedAt: _dt(r, 'postedAt'),
    expiresAt: _dt(r, 'expiresAt'),
    extractionStatus: r.read<String>('extractionStatus'),
    contentHash: r.read<String>('contentHash'),
    active: _bool(r, 'active'),
    archived: _bool(r, 'archived'),
    createdAt: _dt(r, 'createdAt')!,
    updatedAt: _dt(r, 'updatedAt')!,
  );

  // ---- GoalRequirement ----
  @override
  Future<void> putGoalRequirement(GoalRequirement req) => _exec(
    'INSERT OR REPLACE INTO goalRequirements '
    '(id, goalId, profileId, type, title, summary, jdSourceSpan, importance, '
    'suggestedDepth, prerequisiteRequirementIds, inferred, inferenceRationale, createdAt) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      req.id,
      req.goalId,
      req.profileId,
      req.type.name,
      req.title,
      req.summary,
      req.jdSourceSpan,
      req.importance.name,
      req.suggestedDepth,
      _json(req.prerequisiteRequirementIds),
      req.inferred ? 1 : 0,
      req.inferenceRationale,
      _iso(req.createdAt),
    ],
  );

  @override
  Future<void> putGoalRequirements(List<GoalRequirement> reqs) async {
    for (final req in reqs) {
      await putGoalRequirement(req);
    }
  }

  @override
  Future<List<GoalRequirement>> listGoalRequirements(GoalId goalId) async {
    final rows = await _select(
      'SELECT * FROM goalRequirements WHERE goalId = ?',
      [goalId],
    );
    return rows.map(_requirementFromRow).toList();
  }

  @override
  Future<void> deleteGoalRequirementsForGoal(GoalId goalId) =>
      _delete('DELETE FROM goalRequirements WHERE goalId = ?', [goalId]);

  GoalRequirement _requirementFromRow(QueryRow r) => GoalRequirement(
    id: r.read<String>('id'),
    goalId: r.read<String>('goalId'),
    profileId: r.read<String>('profileId'),
    type: _enumOr(
      r,
      'type',
      RequirementType.values,
      RequirementType.responsibility,
    ),
    title: r.read<String>('title'),
    summary: r.read<String?>('summary'),
    jdSourceSpan: r.read<String?>('jdSourceSpan'),
    importance: _enumOr(r, 'importance', Importance.values, Importance.medium),
    suggestedDepth: r.read<String?>('suggestedDepth'),
    prerequisiteRequirementIds: _list(r, 'prerequisiteRequirementIds'),
    inferred: _bool(r, 'inferred'),
    inferenceRationale: r.read<String?>('inferenceRationale'),
    createdAt: _dt(r, 'createdAt'),
  );

  // ---- GoalRevision ----
  @override
  Future<void> putGoalRevision(GoalRevision rev) => _exec(
    'INSERT OR REPLACE INTO goalRevisions '
    '(id, goalId, profileId, revisionNumber, contentHash, createdAt, note) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      rev.id,
      rev.goalId,
      rev.profileId,
      rev.revisionNumber,
      rev.contentHash,
      _iso(rev.createdAt),
      rev.note,
    ],
  );

  @override
  Future<List<GoalRevision>> listGoalRevisions(
    GoalId? goalId, {
    ProfileId? profileId,
  }) async {
    final rows = await _select(
      'SELECT * FROM goalRevisions WHERE (? IS NULL OR goalId = ?) '
      'AND (? IS NULL OR profileId = ?)',
      [goalId, goalId, profileId, profileId],
    );
    return rows
        .map(
          (r) => GoalRevision(
            id: r.read<String>('id'),
            goalId: r.read<String>('goalId'),
            profileId: r.read<String>('profileId'),
            revisionNumber: r.read<int>('revisionNumber'),
            contentHash: r.read<String>('contentHash'),
            createdAt: _dt(r, 'createdAt')!,
            note: r.read<String?>('note'),
          ),
        )
        .toList();
  }

  // ---- KnowledgeItem ----
  @override
  Future<void> putKnowledgeItem(KnowledgeItem k) => _exec(
    'INSERT OR REPLACE INTO knowledgeItems '
    '(id, profileId, title, aliases, contentStatus, version, createdAt, updatedAt) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      k.id,
      k.profileId,
      k.title,
      _json(k.aliases),
      k.contentStatus,
      k.version,
      _iso(k.createdAt),
      _iso(k.updatedAt),
    ],
  );

  @override
  Future<KnowledgeItem?> getKnowledgeItem(KnowledgeItemId id) async {
    final rows = await _select('SELECT * FROM knowledgeItems WHERE id = ?', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return _knowledgeFromRow(rows.first);
  }

  @override
  Future<List<KnowledgeItem>> listKnowledgeItems(ProfileId profileId) async {
    final rows = await _select(
      'SELECT * FROM knowledgeItems WHERE profileId = ?',
      [profileId],
    );
    return rows.map(_knowledgeFromRow).toList();
  }

  @override
  Future<void> deleteKnowledgeItem(KnowledgeItemId id) => transaction(() async {
    await _delete('DELETE FROM goalKnowledgeLinks WHERE knowledgeItemId = ?', [
      id,
    ]);
    await _delete('DELETE FROM knowledgeItems WHERE id = ?', [id]);
  });

  @override
  Future<void> deleteLearningRecordsForKnowledge(
    KnowledgeItemId id,
  ) => transaction(() async {
    await _delete('DELETE FROM assessmentEvents WHERE knowledgeItemId = ?', [
      id,
    ]);
    await _delete('DELETE FROM checkpoints WHERE knowledgeItemId = ?', [id]);
    await _delete('DELETE FROM reviewStates WHERE knowledgeItemId = ?', [id]);
    await _delete('DELETE FROM reviewPoints WHERE knowledgeItemId = ?', [id]);
    await _delete(
      'DELETE FROM messages WHERE sessionId IN '
      '(SELECT id FROM sessions WHERE knowledgeItemId = ?)',
      [id],
    );
    await _delete('DELETE FROM sessions WHERE knowledgeItemId = ?', [id]);
  });

  KnowledgeItem _knowledgeFromRow(QueryRow r) => KnowledgeItem(
    id: r.read<String>('id'),
    profileId: r.read<String>('profileId'),
    title: r.read<String>('title'),
    aliases: _list(r, 'aliases'),
    contentStatus: r.read<String>('contentStatus'),
    version: r.read<int>('version'),
    createdAt: _dt(r, 'createdAt')!,
    updatedAt: _dt(r, 'updatedAt')!,
  );

  // ---- GoalKnowledgeLink ----
  @override
  Future<void> putGoalKnowledgeLink(GoalKnowledgeLink l) => _exec(
    'INSERT OR REPLACE INTO goalKnowledgeLinks '
    '(goalId, knowledgeItemId, profileId, requirementIds, createdAt) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      l.goalId,
      l.knowledgeItemId,
      l.profileId,
      _json(l.requirementIds),
      _iso(l.createdAt),
    ],
  );

  @override
  Future<List<GoalKnowledgeLink>> listGoalKnowledgeLinks(GoalId goalId) async {
    final rows = await _select(
      'SELECT * FROM goalKnowledgeLinks WHERE goalId = ?',
      [goalId],
    );
    return rows
        .map(
          (r) => GoalKnowledgeLink(
            goalId: r.read<String>('goalId'),
            knowledgeItemId: r.read<String>('knowledgeItemId'),
            profileId: r.read<String>('profileId'),
            requirementIds: _list(r, 'requirementIds'),
            createdAt: _dt(r, 'createdAt')!,
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteGoalKnowledgeLinksForGoal(GoalId goalId) =>
      _delete('DELETE FROM goalKnowledgeLinks WHERE goalId = ?', [goalId]);

  // ---- Resume ----
  @override
  Future<void> putResume(Resume r) => _exec(
    'INSERT OR REPLACE INTO resumes '
    '(id, profileId, versionLabel, originalText, fileName, parsedAt, createdAt, '
    'revision) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      r.id,
      r.profileId,
      r.versionLabel,
      r.originalText,
      r.fileName,
      _iso(r.parsedAt),
      _iso(r.createdAt),
      r.revision,
    ],
  );

  @override
  Future<Resume?> getResume(ResumeId id) async {
    final rows = await _select('SELECT * FROM resumes WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _resumeFromRow(rows.first);
  }

  @override
  Future<List<Resume>> listResumes(ProfileId profileId) async {
    final rows = await _select('SELECT * FROM resumes WHERE profileId = ?', [
      profileId,
    ]);
    return rows.map(_resumeFromRow).toList();
  }

  Resume _resumeFromRow(QueryRow r) => Resume(
    id: r.read<String>('id'),
    profileId: r.read<String>('profileId'),
    versionLabel: r.read<String>('versionLabel'),
    originalText: r.read<String>('originalText'),
    fileName: r.read<String?>('fileName'),
    parsedAt: _dt(r, 'parsedAt'),
    createdAt: _dt(r, 'createdAt')!,
    revision: r.read<int?>('revision') ?? 1,
  );

  // ---- Project ----
  @override
  Future<void> putProject(Project p) => _exec(
    'INSERT OR REPLACE INTO projects '
    '(id, profileId, resumeId, name, originalSpan, goal, responsibilities, '
    'techStack, metrics, timeRange) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      p.id,
      p.profileId,
      p.resumeId,
      p.name,
      p.originalSpan,
      p.goal,
      p.responsibilities,
      p.techStack,
      p.metrics,
      p.timeRange,
    ],
  );

  @override
  Future<List<Project>> listProjects(ResumeId resumeId) async {
    final rows = await _select('SELECT * FROM projects WHERE resumeId = ?', [
      resumeId,
    ]);
    return rows
        .map(
          (r) => Project(
            id: r.read<String>('id'),
            profileId: r.read<String>('profileId'),
            resumeId: r.read<String>('resumeId'),
            name: r.read<String>('name'),
            originalSpan: r.read<String?>('originalSpan'),
            goal: r.read<String?>('goal'),
            responsibilities: r.read<String?>('responsibilities'),
            techStack: r.read<String?>('techStack'),
            metrics: r.read<String?>('metrics'),
            timeRange: r.read<String?>('timeRange'),
          ),
        )
        .toList();
  }

  // ---- ResumeClaim ----
  @override
  Future<void> putResumeClaim(ResumeClaim c) => _exec(
    'INSERT OR REPLACE INTO resumeClaims '
    '(id, profileId, resumeId, projectId, statement, originalSpan, status, confidence) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      c.id,
      c.profileId,
      c.resumeId,
      c.projectId,
      c.statement,
      c.originalSpan,
      c.status.name,
      c.confidence,
    ],
  );

  @override
  Future<List<ResumeClaim>> listResumeClaims(ResumeId resumeId) async {
    final rows = await _select(
      'SELECT * FROM resumeClaims WHERE resumeId = ?',
      [resumeId],
    );
    return rows
        .map(
          (r) => ResumeClaim(
            id: r.read<String>('id'),
            profileId: r.read<String>('profileId'),
            resumeId: r.read<String>('resumeId'),
            projectId: r.read<String?>('projectId'),
            statement: r.read<String>('statement'),
            originalSpan: r.read<String?>('originalSpan'),
            status: _enumOr(
              r,
              'status',
              ClaimStatus.values,
              ClaimStatus.pending,
            ),
            confidence: r.read<double?>('confidence'),
          ),
        )
        .toList();
  }

  // ---- GoalResumeLink ----
  @override
  Future<void> putGoalResumeLink(GoalResumeLink l) => _exec(
    'INSERT OR REPLACE INTO goalResumeLinks '
    '(goalId, resumeId, profileId, isDefault, createdAt) VALUES (?, ?, ?, ?, ?)',
    [l.goalId, l.resumeId, l.profileId, l.isDefault ? 1 : 0, _iso(l.createdAt)],
  );

  @override
  Future<List<GoalResumeLink>> listGoalResumeLinks(GoalId goalId) async {
    final rows = await _select(
      'SELECT * FROM goalResumeLinks WHERE goalId = ?',
      [goalId],
    );
    return rows
        .map(
          (r) => GoalResumeLink(
            goalId: r.read<String>('goalId'),
            resumeId: r.read<String>('resumeId'),
            profileId: r.read<String>('profileId'),
            isDefault: _bool(r, 'isDefault'),
            createdAt: _dt(r, 'createdAt')!,
          ),
        )
        .toList();
  }

  // ---- ClaimRequirementLink ----
  @override
  Future<void> putClaimRequirementLink(ClaimRequirementLink l) => _exec(
    'INSERT OR REPLACE INTO claimRequirementLinks '
    '(claimId, requirementId, profileId, mappingType, rationale) '
    'VALUES (?, ?, ?, ?, ?)',
    [l.claimId, l.requirementId, l.profileId, l.mappingType, l.rationale],
  );

  @override
  Future<List<ClaimRequirementLink>> listClaimRequirementLinks(
    ClaimId claimId,
  ) async {
    final rows = await _select(
      'SELECT * FROM claimRequirementLinks WHERE claimId = ?',
      [claimId],
    );
    return rows
        .map(
          (r) => ClaimRequirementLink(
            claimId: r.read<String>('claimId'),
            requirementId: r.read<String>('requirementId'),
            profileId: r.read<String>('profileId'),
            mappingType: r.read<String>('mappingType'),
            rationale: r.read<String?>('rationale'),
          ),
        )
        .toList();
  }

  // ---- Source ----
  @override
  Future<void> putSource(Source s) => _exec(
    'INSERT OR REPLACE INTO sources '
    '(id, profileId, title, type, contentHash, status, url, revision, content, '
    'fetchedAt, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      s.id,
      s.profileId,
      s.title,
      s.type.name,
      s.contentHash,
      s.status.name,
      s.url,
      s.revision,
      s.content,
      _iso(s.fetchedAt),
      _iso(s.createdAt),
    ],
  );

  @override
  Future<Source?> getSource(SourceId id) async {
    final rows = await _select('SELECT * FROM sources WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _sourceFromRow(rows.first);
  }

  @override
  Future<List<Source>> listSources(ProfileId profileId) async {
    final rows = await _select('SELECT * FROM sources WHERE profileId = ?', [
      profileId,
    ]);
    return rows.map(_sourceFromRow).toList();
  }

  Source _sourceFromRow(QueryRow r) => Source(
    id: r.read<String>('id'),
    profileId: r.read<String>('profileId'),
    title: r.read<String>('title'),
    type: _enumOr(r, 'type', SourceType.values, SourceType.txt),
    contentHash: r.read<String>('contentHash'),
    status: _enumOr(
      r,
      'status',
      IngestionStatus.values,
      IngestionStatus.pending,
    ),
    url: r.read<String?>('url'),
    revision: r.read<int>('revision'),
    content: r.read<String?>('content'),
    fetchedAt: _dt(r, 'fetchedAt'),
    createdAt: _dt(r, 'createdAt'),
  );

  // ---- SourceChunk ----
  @override
  Future<void> putSourceChunk(SourceChunk c) => _exec(
    'INSERT OR REPLACE INTO sourceChunks '
    '(id, sourceId, sourceRevision, chunkIndex, content, titlePath, sourceLocation, '
    'hash, knowledgeItemId, embeddingProfileId) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      c.id,
      c.sourceId,
      c.sourceRevision,
      c.index,
      c.content,
      c.titlePath,
      c.sourceLocation,
      c.hash,
      c.knowledgeItemId,
      c.embeddingProfileId,
    ],
  );

  @override
  Future<void> putSourceChunks(List<SourceChunk> chunks) async {
    for (final c in chunks) {
      await putSourceChunk(c);
    }
  }

  @override
  Future<List<SourceChunk>> listSourceChunks(SourceId sourceId) async {
    final rows = await _select(
      'SELECT * FROM sourceChunks WHERE sourceId = ? ORDER BY chunkIndex ASC',
      [sourceId],
    );
    return rows
        .map(
          (r) => SourceChunk(
            id: r.read<String>('id'),
            sourceId: r.read<String>('sourceId'),
            sourceRevision: r.read<int>('sourceRevision'),
            index: r.read<int>('chunkIndex'),
            content: r.read<String>('content'),
            titlePath: r.read<String?>('titlePath'),
            sourceLocation: r.read<String?>('sourceLocation'),
            hash: r.read<String?>('hash'),
            knowledgeItemId: r.read<String?>('knowledgeItemId'),
            embeddingProfileId: r.read<String?>('embeddingProfileId'),
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteSourceChunksForKnowledge(
    KnowledgeItemId knowledgeItemId,
  ) => _delete('DELETE FROM sourceChunks WHERE knowledgeItemId = ?', [
    knowledgeItemId,
  ]);

  @override
  Future<List<SourceId>> sourceIdsForKnowledge(
    KnowledgeItemId knowledgeItemId,
  ) async {
    final rows = await _select(
      'SELECT DISTINCT sourceId FROM sourceChunks WHERE knowledgeItemId = ?',
      [knowledgeItemId],
    );
    return rows.map((row) => row.read<String>('sourceId')).toList();
  }

  @override
  Future<void> deleteSource(SourceId id) async {
    // drift 的 customUpdate 一次只接受一条语句，分条执行。
    await _delete('DELETE FROM sourceChunks WHERE sourceId = ?', [id]);
    await _delete('DELETE FROM ingestionJobs WHERE sourceId = ?', [id]);
    await _delete('DELETE FROM sources WHERE id = ?', [id]);
  }

  // ---- IngestionJob ----
  @override
  Future<void> putIngestionJob(IngestionJob j) => _exec(
    'INSERT OR REPLACE INTO ingestionJobs '
    '(id, profileId, sourceId, status, error, createdAt, completedAt) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      j.id,
      j.profileId,
      j.sourceId,
      j.status.name,
      j.error,
      _iso(j.createdAt),
      _iso(j.completedAt),
    ],
  );

  @override
  Future<IngestionJob?> getIngestionJob(String id) async {
    final rows = await _select('SELECT * FROM ingestionJobs WHERE id = ?', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return _ingestionJobFromRow(rows.first);
  }

  @override
  Future<List<IngestionJob>> listIngestionJobs(SourceId sourceId) async {
    final rows = await _select(
      'SELECT * FROM ingestionJobs WHERE sourceId = ?',
      [sourceId],
    );
    return rows.map(_ingestionJobFromRow).toList();
  }

  IngestionJob _ingestionJobFromRow(QueryRow r) => IngestionJob(
    id: r.read<String>('id'),
    profileId: r.read<String>('profileId'),
    sourceId: r.read<String>('sourceId'),
    status: _enumOr(
      r,
      'status',
      IngestionStatus.values,
      IngestionStatus.pending,
    ),
    error: r.read<String?>('error'),
    createdAt: _dt(r, 'createdAt')!,
    completedAt: _dt(r, 'completedAt'),
  );

  // ---- ReviewPoint ----
  @override
  Future<void> putReviewPoint(ReviewPoint p) => _exec(
    'INSERT OR REPLACE INTO reviewPoints '
    '(id, profileId, knowledgeItemId, label, aliases, createdAt) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [
      p.id,
      p.profileId,
      p.knowledgeItemId,
      p.label,
      _json(p.aliases),
      _iso(p.createdAt),
    ],
  );

  @override
  Future<List<ReviewPoint>> listReviewPoints(
    KnowledgeItemId knowledgeItemId,
  ) async {
    final rows = await _select(
      'SELECT * FROM reviewPoints WHERE knowledgeItemId = ?',
      [knowledgeItemId],
    );
    return rows
        .map(
          (r) => ReviewPoint(
            id: r.read<String>('id'),
            profileId: r.read<String>('profileId'),
            knowledgeItemId: r.read<String>('knowledgeItemId'),
            label: r.read<String>('label'),
            aliases: _list(r, 'aliases'),
            createdAt: _dt(r, 'createdAt'),
          ),
        )
        .toList();
  }

  // ---- ReviewState ----
  @override
  Future<void> putReviewState(ReviewState s) => _exec(
    'INSERT OR REPLACE INTO reviewStates '
    '(reviewPointId, profileId, knowledgeItemId, status, firstDueAt, nextDueAt, '
    'lastAssessedAt, lastTaughtAt, consecutiveIndependentPasses, '
    'consecutiveWeaknesses, intervalStep, pendingDispute) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      s.reviewPointId,
      s.profileId,
      s.knowledgeItemId,
      s.status.name,
      _iso(s.firstDueAt),
      _iso(s.nextDueAt),
      _iso(s.lastAssessedAt),
      _iso(s.lastTaughtAt),
      s.consecutiveIndependentPasses,
      s.consecutiveWeaknesses,
      s.intervalStep,
      s.pendingDispute ? 1 : 0,
    ],
  );

  @override
  Future<ReviewState?> getReviewState(ReviewPointId reviewPointId) async {
    final rows = await _select(
      'SELECT * FROM reviewStates WHERE reviewPointId = ?',
      [reviewPointId],
    );
    if (rows.isEmpty) return null;
    return _reviewStateFromRow(rows.first);
  }

  @override
  Future<List<ReviewState>> listReviewStates(ProfileId profileId) async {
    final rows = await _select(
      'SELECT * FROM reviewStates WHERE profileId = ?',
      [profileId],
    );
    return rows.map(_reviewStateFromRow).toList();
  }

  @override
  Future<List<ReviewState>> listReviewStatesForKnowledge(
    KnowledgeItemId knowledgeItemId,
  ) async {
    final rows = await _select(
      'SELECT * FROM reviewStates WHERE knowledgeItemId = ?',
      [knowledgeItemId],
    );
    return rows.map(_reviewStateFromRow).toList();
  }

  ReviewState _reviewStateFromRow(QueryRow r) => ReviewState(
    reviewPointId: r.read<String>('reviewPointId'),
    profileId: r.read<String>('profileId'),
    knowledgeItemId: r.read<String>('knowledgeItemId'),
    status: _enumOr(r, 'status', ReviewStatus.values, ReviewStatus.unseen),
    firstDueAt: _dt(r, 'firstDueAt'),
    nextDueAt: _dt(r, 'nextDueAt'),
    lastAssessedAt: _dt(r, 'lastAssessedAt'),
    lastTaughtAt: _dt(r, 'lastTaughtAt'),
    consecutiveIndependentPasses: r.read<int>('consecutiveIndependentPasses'),
    consecutiveWeaknesses: r.read<int>('consecutiveWeaknesses'),
    intervalStep: r.read<int>('intervalStep'),
    pendingDispute: _bool(r, 'pendingDispute'),
  );

  // ---- AssessmentEvent ----
  @override
  Future<void> putAssessmentEvent(AssessmentEvent e) => _exec(
    'INSERT OR REPLACE INTO assessmentEvents '
    '(id, profileId, sessionId, turnGroupId, knowledgeItemId, reviewPointId, '
    'questionMessageId, answerMessageIds, assessmentMode, askedDimensions, '
    'result, hintLevel, independentEligible, isSpacedEligible, validity, '
    'sourceRevisionIds, rubricVersion, rulesVersion, providerConfigId, '
    'createdAt, assessmentRevision, rationale) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      e.id,
      e.profileId,
      e.sessionId,
      e.turnGroupId,
      e.knowledgeItemId,
      e.reviewPointId,
      e.questionMessageId,
      _json(e.answerMessageIds),
      e.assessmentMode.name,
      _json(e.askedDimensions),
      e.result.name,
      e.hintLevel,
      e.independentEligible ? 1 : 0,
      e.isSpacedEligible ? 1 : 0,
      e.validity.name,
      _json(e.sourceRevisionIds),
      e.rubricVersion,
      e.rulesVersion,
      e.providerConfigId,
      _iso(e.createdAt),
      e.assessmentRevision,
      e.rationale,
    ],
  );

  @override
  Future<List<AssessmentEvent>> listAssessmentEvents(
    SessionId sessionId,
  ) async {
    final rows = await _select(
      'SELECT * FROM assessmentEvents WHERE sessionId = ?',
      [sessionId],
    );
    return rows.map(_assessmentFromRow).toList();
  }

  @override
  Future<List<AssessmentEvent>> listAssessmentEventsForReviewPoint(
    ReviewPointId reviewPointId,
  ) async {
    final rows = await _select(
      'SELECT * FROM assessmentEvents WHERE reviewPointId = ?',
      [reviewPointId],
    );
    return rows.map(_assessmentFromRow).toList();
  }

  AssessmentEvent _assessmentFromRow(QueryRow r) => AssessmentEvent(
    id: r.read<String>('id'),
    profileId: r.read<String>('profileId'),
    sessionId: r.read<String>('sessionId'),
    turnGroupId: r.read<String>('turnGroupId'),
    knowledgeItemId: r.read<String>('knowledgeItemId'),
    reviewPointId: r.read<String>('reviewPointId'),
    questionMessageId: r.read<String>('questionMessageId'),
    answerMessageIds: _list(r, 'answerMessageIds'),
    assessmentMode: _enumOr(
      r,
      'assessmentMode',
      SessionMode.values,
      SessionMode.review,
    ),
    askedDimensions: _list(r, 'askedDimensions'),
    result: _enumOr(
      r,
      'result',
      ReviewOutcome.values,
      ReviewOutcome.needsReinforcement,
    ),
    hintLevel: r.read<String>('hintLevel'),
    independentEligible: _bool(r, 'independentEligible'),
    isSpacedEligible: _bool(r, 'isSpacedEligible'),
    validity: _enumOr(
      r,
      'validity',
      EvidenceValidity.values,
      EvidenceValidity.accepted,
    ),
    sourceRevisionIds: _list(r, 'sourceRevisionIds'),
    rubricVersion: r.read<String?>('rubricVersion'),
    rulesVersion: r.read<String?>('rulesVersion'),
    providerConfigId: r.read<String?>('providerConfigId'),
    createdAt: _dt(r, 'createdAt')!,
    assessmentRevision: r.read<int>('assessmentRevision'),
    rationale: r.read<String?>('rationale'),
  );

  // ---- Session ----
  @override
  Future<void> putSession(CoachSession s) => _exec(
    'INSERT OR REPLACE INTO sessions '
    '(id, profileId, mode, createdAt, status, goalId, goalRevision, resumeId, '
    'resumeRevision, projectIds, knowledgeItemId, reviewPointId, turnSequence, '
    'expectedRevision, interviewDurationMinutes, startedAt, endedAt, coverageSnapshot, '
    'askedQuestionCount, stopReason, partial, interviewStyle) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      s.id,
      s.profileId,
      s.mode.name,
      _iso(s.createdAt),
      s.status.name,
      s.goalId,
      s.goalRevision,
      s.resumeId,
      s.resumeRevision,
      _json(s.projectIds),
      s.knowledgeItemId,
      s.reviewPointId,
      s.turnSequence,
      s.expectedRevision,
      s.interviewDurationMinutes,
      _iso(s.startedAt),
      _iso(s.endedAt),
      s.coverageSnapshot == null ? null : _json(s.coverageSnapshot!.toJson()),
      s.askedQuestionCount,
      s.stopReason,
      s.partial ? 1 : 0,
      s.interviewStyle,
    ],
  );

  @override
  Future<CoachSession?> getSession(SessionId id) async {
    final rows = await _select('SELECT * FROM sessions WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  @override
  Future<List<CoachSession>> listSessions(ProfileId profileId) async {
    final rows = await _select('SELECT * FROM sessions WHERE profileId = ?', [
      profileId,
    ]);
    return rows.map(_sessionFromRow).toList();
  }

  CoachSession _sessionFromRow(QueryRow r) => CoachSession(
    id: r.read<String>('id'),
    profileId: r.read<String>('profileId'),
    mode: _enumOr(r, 'mode', SessionMode.values, SessionMode.learning),
    createdAt: _dt(r, 'createdAt')!,
    status: _enumOr(r, 'status', RuntimeStatus.values, RuntimeStatus.idle),
    goalId: r.read<String?>('goalId'),
    goalRevision: r.read<int?>('goalRevision'),
    resumeId: r.read<String?>('resumeId'),
    resumeRevision: r.read<int?>('resumeRevision'),
    projectIds: _list(r, 'projectIds'),
    knowledgeItemId: r.read<String?>('knowledgeItemId'),
    reviewPointId: r.read<String?>('reviewPointId'),
    turnSequence: r.read<int>('turnSequence'),
    expectedRevision: r.read<int>('expectedRevision'),
    interviewDurationMinutes: r.read<int?>('interviewDurationMinutes'),
    startedAt: _dt(r, 'startedAt'),
    endedAt: _dt(r, 'endedAt'),
    coverageSnapshot: _coverageSnapshot(r),
    askedQuestionCount: r.read<int?>('askedQuestionCount') ?? 0,
    stopReason: r.read<String?>('stopReason'),
    partial: _bool(r, 'partial'),
    interviewStyle: r.read<String?>('interviewStyle'),
  );

  SessionCoverageSnapshot? _coverageSnapshot(QueryRow row) {
    final encoded = row.read<String?>('coverageSnapshot');
    if (encoded == null || encoded.isEmpty) return null;
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return null;
    return SessionCoverageSnapshot.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  // ---- Message ----
  @override
  Future<void> putMessage(CoachMessage m) => _exec(
    'INSERT OR REPLACE INTO messages '
    '(id, sessionId, profileId, role, content, turnId, sequence, createdAt, '
    'refs, isAnswerShown) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      m.id,
      m.sessionId,
      m.profileId,
      m.role,
      m.content,
      m.turnId,
      m.sequence,
      _iso(m.createdAt),
      _json(m.references),
      m.isAnswerShown ? 1 : 0,
    ],
  );

  @override
  Future<List<CoachMessage>> messagesOf(SessionId sessionId) async {
    final rows = await _select(
      'SELECT * FROM messages WHERE sessionId = ? ORDER BY sequence ASC',
      [sessionId],
    );
    return rows.map(_messageFromRow).toList();
  }

  CoachMessage _messageFromRow(QueryRow r) => CoachMessage(
    id: r.read<String>('id'),
    sessionId: r.read<String>('sessionId'),
    profileId: r.read<String>('profileId'),
    role: r.read<String>('role'),
    content: r.read<String>('content'),
    turnId: r.read<String>('turnId'),
    sequence: r.read<int>('sequence'),
    createdAt: _dt(r, 'createdAt')!,
    references: _list(r, 'refs'),
    isAnswerShown: _bool(r, 'isAnswerShown'),
  );

  // ---- Checkpoint ----
  @override
  Future<void> putCheckpoint(LessonCheckpoint c) => _exec(
    'INSERT OR REPLACE INTO checkpoints '
    '(id, sessionId, profileId, knowledgeItemId, taughtScope, openQuestions, '
    'nextPosition, createdAt, updatedAt) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      c.id,
      c.sessionId,
      c.profileId,
      c.knowledgeItemId,
      c.taughtScope,
      _json(c.openQuestions),
      c.nextPosition,
      _iso(c.createdAt),
      _iso(c.updatedAt),
    ],
  );

  @override
  Future<LessonCheckpoint?> checkpointOf(String id) async {
    final rows = await _select('SELECT * FROM checkpoints WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _checkpointFromRow(rows.first);
  }

  @override
  Future<List<LessonCheckpoint>> listCheckpoints(SessionId sessionId) async {
    final rows = await _select(
      'SELECT * FROM checkpoints WHERE sessionId = ?',
      [sessionId],
    );
    return rows.map(_checkpointFromRow).toList();
  }

  LessonCheckpoint _checkpointFromRow(QueryRow r) => LessonCheckpoint(
    id: r.read<String>('id'),
    sessionId: r.read<String>('sessionId'),
    profileId: r.read<String>('profileId'),
    knowledgeItemId: r.read<String>('knowledgeItemId'),
    taughtScope: r.read<String>('taughtScope'),
    openQuestions: _list(r, 'openQuestions'),
    nextPosition: r.read<String?>('nextPosition'),
    createdAt: _dt(r, 'createdAt')!,
    updatedAt: _dt(r, 'updatedAt')!,
  );

  // ---- DailyPlan ----
  @override
  Future<void> putDailyPlan(DailyPlan p) => _exec(
    'INSERT OR REPLACE INTO dailyPlans '
    '(id, profileId, date, timezone, planItems, baseMinutes, version, '
    'frozenAt, revisionNote, isExtra) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      p.id,
      p.profileId,
      p.date,
      p.timezone,
      _json(p.planItems.map(_planItemToJson).toList()),
      p.baseMinutes,
      p.version,
      _iso(p.frozenAt),
      p.revisionNote,
      p.isExtra ? 1 : 0,
    ],
  );

  @override
  Future<DailyPlan?> getDailyPlan(DailyPlanId id) async {
    final rows = await _select('SELECT * FROM dailyPlans WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _dailyPlanFromRow(rows.first);
  }

  @override
  Future<List<DailyPlan>> listDailyPlans(
    ProfileId profileId, {
    String? date,
  }) async => _select(
    date == null
        ? 'SELECT * FROM dailyPlans WHERE profileId = ?'
        : 'SELECT * FROM dailyPlans WHERE profileId = ? AND date = ?',
    date == null ? [profileId] : [profileId, date],
  ).then((rows) => rows.map(_dailyPlanFromRow).toList());

  DailyPlan _dailyPlanFromRow(QueryRow r) {
    final s = r.read<String?>('planItems');
    List<PlanItem> items = const [];
    if (s != null && s.isNotEmpty) {
      final decoded = jsonDecode(s) as List;
      items = decoded
          .map((e) => _planItemFromJson(e as Map<String, dynamic>))
          .toList();
    }
    return DailyPlan(
      id: r.read<String>('id'),
      profileId: r.read<String>('profileId'),
      date: r.read<String>('date'),
      timezone: r.read<String>('timezone'),
      planItems: items,
      baseMinutes: r.read<int>('baseMinutes'),
      version: r.read<int>('version'),
      frozenAt: _dt(r, 'frozenAt'),
      revisionNote: r.read<String?>('revisionNote'),
      isExtra: _bool(r, 'isExtra'),
    );
  }

  Map<String, dynamic> _planItemToJson(PlanItem p) => {
    'id': p.id,
    'type': p.type.name,
    'title': p.title,
    'knowledgeItemId': p.knowledgeItemId,
    'reviewPointIds': p.reviewPointIds,
    'projectId': p.projectId,
    'goalId': p.goalId,
    'resumeId': p.resumeId,
    'estimatedMinutes': p.estimatedMinutes,
    'manualOverride': p.manualOverride,
    'completed': p.completed,
  };

  PlanItem _planItemFromJson(Map<String, dynamic> j) => PlanItem(
    id: j['id'] as String,
    type: _planItemType(j['type'] as String?),
    title: j['title'] as String,
    knowledgeItemId: j['knowledgeItemId'] as String?,
    reviewPointIds: (j['reviewPointIds'] as List? ?? [])
        .map((e) => e as String)
        .toList(),
    projectId: j['projectId'] as String?,
    goalId: j['goalId'] as String?,
    resumeId: j['resumeId'] as String?,
    estimatedMinutes: j['estimatedMinutes'] as int? ?? 8,
    manualOverride: j['manualOverride'] as bool? ?? false,
    completed: j['completed'] as bool? ?? false,
  );

  PlanItemType _planItemType(String? name) {
    for (final t in PlanItemType.values) {
      if (t.name == name) return t;
    }
    return PlanItemType.learnKnowledge;
  }

  // ---- Profile-scoped extension records / lifecycle ----
  @override
  Future<void> putExtension(CoachExtensionRecord record) => _exec(
    'INSERT OR REPLACE INTO coachExtensions '
    '(profileId, kind, id, revision, valueJson, updatedAt) VALUES (?, ?, ?, ?, ?, ?)',
    [
      record.profileId,
      record.kind.name,
      record.id,
      record.revision,
      _json(record.value),
      _iso(record.updatedAt),
    ],
  );

  @override
  Future<CoachExtensionRecord?> getExtension(
    ProfileId profileId,
    CoachExtensionKind kind,
    String id,
  ) async {
    final rows = await _select(
      'SELECT * FROM coachExtensions WHERE profileId = ? AND kind = ? AND id = ?',
      [profileId, kind.name, id],
    );
    return rows.isEmpty ? null : _extensionFromRow(rows.first);
  }

  @override
  Future<List<CoachExtensionRecord>> listExtensions(
    ProfileId profileId,
    CoachExtensionKind kind,
  ) async {
    final rows = await _select(
      'SELECT * FROM coachExtensions WHERE profileId = ? AND kind = ? ORDER BY updatedAt ASC',
      [profileId, kind.name],
    );
    return rows.map(_extensionFromRow).toList();
  }

  /// 清理任务状态宽容解码。
  ///
  /// `listCleanupTasks` 的 SQL 不按 status 过滤（过滤在调用方），数据库里可能
  /// 存有更高版本写入的新状态名；此时按 pending 处理而不是抛 ArgumentError
  /// 导致整个档案打不开。清理任务本身是幂等的，重跑是安全的最坏情况。
  CleanupTaskStatus _cleanupStatusOrPending(QueryRow row, String col) {
    final s = row.read<String?>(col);
    for (final v in CleanupTaskStatus.values) {
      if (v.name == s) return v;
    }
    return CleanupTaskStatus.pending;
  }

  CoachExtensionRecord _extensionFromRow(QueryRow row) {
    final decoded = jsonDecode(row.read<String>('valueJson'));
    if (decoded is! Map) throw const FormatException('invalid extension JSON');
    // kind 的 byName 是安全的：查询条件里就是当前版本的 kind.name，
    // 其他版本写入的 kind 行根本不会被这条 SQL 读出来。
    return CoachExtensionRecord(
      profileId: row.read<String>('profileId'),
      kind: CoachExtensionKind.values.byName(row.read<String>('kind')),
      id: row.read<String>('id'),
      revision: row.read<int>('revision'),
      value: decoded.map((key, value) => MapEntry(key.toString(), value)),
      updatedAt: _dt(row, 'updatedAt')!,
    );
  }

  @override
  Future<void> deleteExtension(
    ProfileId profileId,
    CoachExtensionKind kind,
    String id,
  ) => _delete(
    'DELETE FROM coachExtensions WHERE profileId = ? AND kind = ? AND id = ?',
    [profileId, kind.name, id],
  );

  @override
  Future<void> putTombstone(CoachTombstone tombstone) => _exec(
    'INSERT OR REPLACE INTO coachTombstones '
    '(profileId, entityType, entityId, generation, deletedAt, operationId) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    [
      tombstone.profileId,
      tombstone.entityType,
      tombstone.entityId,
      tombstone.generation,
      _iso(tombstone.deletedAt),
      tombstone.operationId,
    ],
  );

  @override
  Future<List<CoachTombstone>> listTombstones(ProfileId profileId) async {
    final rows = await _select(
      'SELECT * FROM coachTombstones WHERE profileId = ? ORDER BY deletedAt ASC',
      [profileId],
    );
    return rows
        .map(
          (row) => CoachTombstone(
            profileId: row.read<String>('profileId'),
            entityType: row.read<String>('entityType'),
            entityId: row.read<String>('entityId'),
            generation: row.read<int>('generation'),
            deletedAt: _dt(row, 'deletedAt')!,
            operationId: row.read<String>('operationId'),
          ),
        )
        .toList();
  }

  @override
  Future<int> pruneTombstones(
    ProfileId profileId, {
    int keepPerEntity = 1,
    int maxEntityTombstones = 500,
  }) async {
    // 同一实体只保留最新代次；profile_reset 墓碑是同步代次判定的依据，全部保留。
    final staleRows = await db.customUpdate(
      "DELETE FROM coachTombstones WHERE profileId = ? "
      "AND entityType != 'profile_reset' AND generation < ("
      "  SELECT MAX(generation) FROM coachTombstones t2"
      "  WHERE t2.profileId = coachTombstones.profileId"
      "    AND t2.entityType = coachTombstones.entityType"
      "    AND t2.entityId = coachTombstones.entityId);",
      variables: [Variable.withString(profileId)],
    );
    var removed = staleRows;
    // 总量上限：仍超限时按删除时间从旧到新逐条淘汰。
    final rows = await _select(
      "SELECT entityType, entityId, generation FROM coachTombstones "
      "WHERE profileId = ? AND entityType != 'profile_reset' "
      'ORDER BY deletedAt ASC',
      [profileId],
    );
    var excess = (rows.length - maxEntityTombstones).clamp(0, rows.length);
    for (final row in rows) {
      if (excess == 0) break;
      removed += await db.customUpdate(
        'DELETE FROM coachTombstones WHERE profileId = ? '
        'AND entityType = ? AND entityId = ? AND generation = ?',
        variables: [
          Variable.withString(profileId),
          Variable.withString(row.read<String>('entityType')),
          Variable.withString(row.read<String>('entityId')),
          Variable.withInt(row.read<int>('generation')),
        ],
      );
      excess--;
    }
    return removed;
  }

  @override
  Future<void> putCleanupTask(CoachCleanupTask task) => _exec(
    'INSERT OR REPLACE INTO coachCleanupTasks '
    '(id, profileId, type, operationId, status, createdAt, updatedAt, error) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      task.id,
      task.profileId,
      task.type,
      task.operationId,
      task.status.name,
      _iso(task.createdAt),
      _iso(task.updatedAt),
      task.error,
    ],
  );

  @override
  Future<List<CoachCleanupTask>> listCleanupTasks(
    ProfileId profileId, {
    CleanupTaskStatus? status,
  }) async {
    final rows = await _select(
      status == null
          ? 'SELECT * FROM coachCleanupTasks WHERE profileId = ? ORDER BY createdAt ASC'
          : 'SELECT * FROM coachCleanupTasks WHERE profileId = ? AND status = ? ORDER BY createdAt ASC',
      status == null ? [profileId] : [profileId, status.name],
    );
    return rows
        .map(
          (row) => CoachCleanupTask(
            id: row.read<String>('id'),
            profileId: row.read<String>('profileId'),
            type: row.read<String>('type'),
            operationId: row.read<String>('operationId'),
            status: _cleanupStatusOrPending(row, 'status'),
            createdAt: _dt(row, 'createdAt')!,
            updatedAt: _dt(row, 'updatedAt'),
            error: row.read<String?>('error'),
          ),
        )
        .toList();
  }
}
