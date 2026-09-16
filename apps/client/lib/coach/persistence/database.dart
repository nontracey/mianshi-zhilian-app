/// Drift 持久化数据库（§9.2，免 build_runner codegen）。
///
/// 由于 drift 的 `GeneratedDatabase.allTables` 需要 codegen 生成的 `TableInfo`，
/// 本层改为：`allTables` 返回空、在 [CoachDatabase.beforeOpen] 中执行手写 DDL
/// （`CREATE TABLE IF NOT EXISTS`）建表；所有读写走原始 SQL（见 drift_store.dart）。
///
/// 约定：
/// - 日期以 ISO-8601 字符串存 TEXT；枚举以 `.name` 存 TEXT；列表/JSON 存 TEXT。
/// - 列名即 Dart 字段名（camelCase）。避免 SQL 关键字：`index`→`chunkIndex`、
///   `references`→`refs`。
library;

import 'package:drift/drift.dart';

/// 手写建表 DDL。列类型：TEXT（字符串/日期/枚举/JSON）、INTEGER（整数/布尔）、REAL（小数）。
const List<String> coachSchemaStatements = [
  '''CREATE TABLE IF NOT EXISTS profiles (
    id TEXT PRIMARY KEY,
    displayName TEXT,
    dailyMinutesBudget INTEGER NOT NULL DEFAULT 25,
    baseLevel TEXT,
    teachingPreference TEXT,
    defaultWorkflowTemplateId TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS goals (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    title TEXT NOT NULL,
    originalText TEXT NOT NULL,
    originalUrl TEXT,
    canonicalUrl TEXT,
    platform TEXT,
    externalJobId TEXT,
    company TEXT,
    location TEXT,
    salaryText TEXT,
    description TEXT,
    postedAt TEXT,
    expiresAt TEXT,
    extractionStatus TEXT NOT NULL DEFAULT 'pending',
    contentHash TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS goalRequirements (
    id TEXT PRIMARY KEY,
    goalId TEXT NOT NULL,
    profileId TEXT NOT NULL,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    summary TEXT,
    jdSourceSpan TEXT,
    importance TEXT NOT NULL DEFAULT 'medium',
    suggestedDepth TEXT,
    prerequisiteRequirementIds TEXT,
    inferred INTEGER NOT NULL DEFAULT 0,
    inferenceRationale TEXT,
    createdAt TEXT
  )''',
  '''CREATE TABLE IF NOT EXISTS goalRevisions (
    id TEXT PRIMARY KEY,
    goalId TEXT NOT NULL,
    profileId TEXT NOT NULL,
    revisionNumber INTEGER NOT NULL,
    contentHash TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    note TEXT
  )''',
  '''CREATE TABLE IF NOT EXISTS knowledgeItems (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    title TEXT NOT NULL,
    aliases TEXT,
    contentStatus TEXT NOT NULL DEFAULT 'ai-draft-unverified',
    version INTEGER NOT NULL DEFAULT 1,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS goalKnowledgeLinks (
    goalId TEXT NOT NULL,
    knowledgeItemId TEXT NOT NULL,
    profileId TEXT NOT NULL,
    requirementIds TEXT,
    createdAt TEXT NOT NULL,
    PRIMARY KEY (goalId, knowledgeItemId)
  )''',
  '''CREATE TABLE IF NOT EXISTS resumes (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    versionLabel TEXT NOT NULL,
    originalText TEXT NOT NULL,
    fileName TEXT,
    parsedAt TEXT,
    createdAt TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1
  )''',
  '''CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    resumeId TEXT NOT NULL,
    name TEXT NOT NULL,
    originalSpan TEXT,
    goal TEXT,
    responsibilities TEXT,
    techStack TEXT,
    metrics TEXT,
    timeRange TEXT
  )''',
  '''CREATE TABLE IF NOT EXISTS resumeClaims (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    resumeId TEXT NOT NULL,
    projectId TEXT,
    statement TEXT NOT NULL,
    originalSpan TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    confidence REAL
  )''',
  '''CREATE TABLE IF NOT EXISTS goalResumeLinks (
    goalId TEXT NOT NULL,
    resumeId TEXT NOT NULL,
    profileId TEXT NOT NULL,
    isDefault INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL,
    PRIMARY KEY (goalId, resumeId)
  )''',
  '''CREATE TABLE IF NOT EXISTS claimRequirementLinks (
    claimId TEXT NOT NULL,
    requirementId TEXT NOT NULL,
    profileId TEXT NOT NULL,
    mappingType TEXT NOT NULL,
    rationale TEXT,
    PRIMARY KEY (claimId, requirementId)
  )''',
  '''CREATE TABLE IF NOT EXISTS sources (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    title TEXT NOT NULL,
    type TEXT NOT NULL,
    contentHash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    url TEXT,
    revision INTEGER NOT NULL DEFAULT 1,
    content TEXT,
    fetchedAt TEXT,
    createdAt TEXT
  )''',
  '''CREATE TABLE IF NOT EXISTS sourceChunks (
    id TEXT PRIMARY KEY,
    sourceId TEXT NOT NULL,
    sourceRevision INTEGER NOT NULL,
    chunkIndex INTEGER NOT NULL,
    content TEXT NOT NULL,
    titlePath TEXT,
    sourceLocation TEXT,
    hash TEXT,
    knowledgeItemId TEXT,
    embeddingProfileId TEXT
  )''',
  '''CREATE TABLE IF NOT EXISTS ingestionJobs (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    sourceId TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    error TEXT,
    createdAt TEXT NOT NULL,
    completedAt TEXT
  )''',
  '''CREATE TABLE IF NOT EXISTS reviewPoints (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    knowledgeItemId TEXT NOT NULL,
    label TEXT NOT NULL,
    aliases TEXT,
    createdAt TEXT
  )''',
  '''CREATE TABLE IF NOT EXISTS reviewStates (
    reviewPointId TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    knowledgeItemId TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'unseen',
    firstDueAt TEXT,
    nextDueAt TEXT,
    lastAssessedAt TEXT,
    lastTaughtAt TEXT,
    consecutiveIndependentPasses INTEGER NOT NULL DEFAULT 0,
    consecutiveWeaknesses INTEGER NOT NULL DEFAULT 0,
    intervalStep INTEGER NOT NULL DEFAULT 0,
    pendingDispute INTEGER NOT NULL DEFAULT 0
  )''',
  '''CREATE TABLE IF NOT EXISTS assessmentEvents (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    sessionId TEXT NOT NULL,
    turnGroupId TEXT NOT NULL,
    knowledgeItemId TEXT NOT NULL,
    reviewPointId TEXT NOT NULL,
    questionMessageId TEXT NOT NULL,
    answerMessageIds TEXT,
    assessmentMode TEXT NOT NULL,
    askedDimensions TEXT,
    result TEXT NOT NULL DEFAULT 'needsReinforcement',
    hintLevel TEXT NOT NULL DEFAULT 'none',
    independentEligible INTEGER NOT NULL DEFAULT 0,
    isSpacedEligible INTEGER NOT NULL DEFAULT 0,
    validity TEXT NOT NULL DEFAULT 'accepted',
    sourceRevisionIds TEXT,
    rubricVersion TEXT,
    rulesVersion TEXT,
    providerConfigId TEXT,
    createdAt TEXT NOT NULL,
    assessmentRevision INTEGER NOT NULL DEFAULT 1
  )''',
  '''CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    mode TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'idle',
    goalId TEXT,
    goalRevision INTEGER,
    resumeId TEXT,
    resumeRevision INTEGER,
    projectIds TEXT,
    knowledgeItemId TEXT,
    reviewPointId TEXT,
    turnSequence INTEGER NOT NULL DEFAULT 0,
    expectedRevision INTEGER NOT NULL DEFAULT 1,
    interviewDurationMinutes INTEGER,
    startedAt TEXT,
    endedAt TEXT,
    coverageSnapshot TEXT,
    askedQuestionCount INTEGER NOT NULL DEFAULT 0,
    stopReason TEXT,
    partial INTEGER NOT NULL DEFAULT 0,
    interviewStyle TEXT
  )''',
  '''CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    profileId TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    turnId TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    createdAt TEXT NOT NULL,
    refs TEXT,
    isAnswerShown INTEGER NOT NULL DEFAULT 0
  )''',
  '''CREATE TABLE IF NOT EXISTS checkpoints (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    profileId TEXT NOT NULL,
    knowledgeItemId TEXT NOT NULL,
    taughtScope TEXT NOT NULL,
    openQuestions TEXT,
    nextPosition TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
  )''',
  '''CREATE TABLE IF NOT EXISTS dailyPlans (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    date TEXT NOT NULL,
    timezone TEXT NOT NULL,
    planItems TEXT,
    baseMinutes INTEGER NOT NULL,
    version INTEGER NOT NULL,
    frozenAt TEXT,
    revisionNote TEXT,
    isExtra INTEGER NOT NULL DEFAULT 0
  )''',
  '''CREATE TABLE IF NOT EXISTS coachExtensions (
    profileId TEXT NOT NULL,
    kind TEXT NOT NULL,
    id TEXT NOT NULL,
    revision INTEGER NOT NULL,
    valueJson TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    PRIMARY KEY (profileId, kind, id)
  )''',
  '''CREATE TABLE IF NOT EXISTS coachTombstones (
    profileId TEXT NOT NULL,
    entityType TEXT NOT NULL,
    entityId TEXT NOT NULL,
    generation INTEGER NOT NULL,
    deletedAt TEXT NOT NULL,
    operationId TEXT NOT NULL,
    PRIMARY KEY (profileId, entityType, entityId, generation)
  )''',
  '''CREATE TABLE IF NOT EXISTS coachCleanupTasks (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    type TEXT NOT NULL,
    operationId TEXT NOT NULL,
    status TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT,
    error TEXT
  )''',
];

/// Coach 数据库：手写 DDL 建表，CRUD 走原始 SQL。
class CoachDatabase extends GeneratedDatabase {
  CoachDatabase(super.e);

  /// drift 需要该 getter；本层不使用 codegen 表，返回空，改由 [ensureSchema] 建表。
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const <TableInfo<Table, dynamic>>[];

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(_createSchema),
    onUpgrade: (_, from, to) async {
      if (from > to) throw StateError('Unsupported newer coach schema: $from');
      await transaction(_createSchema);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA secure_delete = ON');
      if ((details.versionBefore ?? schemaVersion) > schemaVersion) {
        throw StateError('Unsupported newer coach schema');
      }
    },
  );

  /// Opening the connection invokes the versioned migration before any business SQL.
  Future<void> ensureSchema() async {
    await customSelect('SELECT 1').get();
  }

  Future<void> _createSchema() async {
    for (final statement in coachSchemaStatements) {
      await customStatement(statement);
    }
    // 增量迁移：老库存在但没有新列时补列（不改动已有数据）。
    await _addColumnIfMissing('profiles', 'defaultWorkflowTemplateId', 'TEXT');
    await _addColumnIfMissing(
      'resumes',
      'revision',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      'sessions',
      'interviewDurationMinutes',
      'INTEGER',
    );
    await _addColumnIfMissing('sessions', 'startedAt', 'TEXT');
    await _addColumnIfMissing('sessions', 'endedAt', 'TEXT');
    await _addColumnIfMissing('sessions', 'coverageSnapshot', 'TEXT');
    await _addColumnIfMissing(
      'sessions',
      'askedQuestionCount',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing('sessions', 'stopReason', 'TEXT');
    await _addColumnIfMissing(
      'sessions',
      'partial',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing('sessions', 'interviewStyle', 'TEXT');
    await _addColumnIfMissing('assessmentEvents', 'rationale', 'TEXT');
  }

  /// 表中缺列时才 `ADD COLUMN`。
  ///
  /// SQLite 的 `ADD COLUMN` 对已存在的列会直接报错，因此先用 `PRAGMA table_info`
  /// 判断；这里**不**用「吞异常」的方式兜底，避免把真实迁移失败也一并咽掉。
  Future<void> _addColumnIfMissing(
    String table,
    String column,
    String type,
  ) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    final exists = rows.any((r) => r.read<String?>('name') == column);
    if (exists) return;
    await customStatement('ALTER TABLE $table ADD COLUMN $column $type');
  }
}
