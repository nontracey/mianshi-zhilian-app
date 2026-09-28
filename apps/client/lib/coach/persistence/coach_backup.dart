/// 教练库备份导出与恢复（§9.1：备份应明确范围，恢复可校验）。
///
/// 设计：
/// - 导出覆盖 [CoachStore] 全部业务实体，按稳定字段顺序编码，带实体计数与
///   内容指纹，恢复前先校验结构；
/// - 恢复是**合并式 upsert**：按 id 覆盖同名实体，不删除备份之后新增的数据
///   （删除合并不在本版范围，UI 必须如实说明这一点）；
/// - 不包含 AI 凭证等敏感信息（本就不在教练库里）。
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../domain/common.dart';

import '../domain/evidence.dart';
import '../domain/goal.dart';
import '../domain/knowledge.dart';
import '../domain/plan.dart';
import '../domain/profile.dart';
import '../domain/resume.dart';
import '../domain/session.dart';
import '../knowledge/source.dart';
import 'coach_store.dart';
import 'extension_records.dart';

const int coachBackupSchemaVersion = 2;

class CoachBackupRestoreResult {
  const CoachBackupRestoreResult({
    required this.restoredEntities,
    required this.contentHashMatched,
  });

  final int restoredEntities;
  final bool contentHashMatched;
}

/// 逐类拉取整库快照。只使用 [CoachStore] 的列表接口，天然兼容两种实现。
Future<Map<String, Object?>> exportCoachBackup(CoachStore store) =>
    store.transaction(() => _exportSnapshot(store));

Future<Map<String, Object?>> _exportSnapshot(CoachStore store) async {
  final profiles = await store.listProfiles();
  final data = <String, Object?>{};

  final goals = <Goal>[];
  for (final profile in profiles) {
    goals.addAll(await store.listGoals(profile.id));
  }
  final knowledgeItems = <KnowledgeItem>[];
  for (final profile in profiles) {
    knowledgeItems.addAll(await store.listKnowledgeItems(profile.id));
  }
  final resumes = <Resume>[];
  for (final profile in profiles) {
    resumes.addAll(await store.listResumes(profile.id));
  }
  final sources = <Source>[];
  for (final profile in profiles) {
    sources.addAll(await store.listSources(profile.id));
  }
  final reviewStates = <ReviewState>[];
  for (final profile in profiles) {
    reviewStates.addAll(await store.listReviewStates(profile.id));
  }
  final sessions = <CoachSession>[];
  for (final profile in profiles) {
    sessions.addAll(await store.listSessions(profile.id));
  }
  final dailyPlans = <DailyPlan>[];
  for (final profile in profiles) {
    dailyPlans.addAll(await store.listDailyPlans(profile.id));
  }
  final tombstones = <CoachTombstone>[];
  for (final profile in profiles) {
    tombstones.addAll(await store.listTombstones(profile.id));
  }
  final extensions = <CoachExtensionRecord>[];
  for (final profile in profiles) {
    for (final kind in CoachExtensionKind.values.where(
      (k) => k != CoachExtensionKind.runtimeLease,
    )) {
      extensions.addAll(await store.listExtensions(profile.id, kind));
    }
  }

  final requirements = <GoalRequirement>[];
  final revisions = <GoalRevision>[];
  final cleanupTasks = <CoachCleanupTask>[];
  for (final profile in profiles) {
    revisions.addAll(
      await store.listGoalRevisions(null, profileId: profile.id),
    );
    cleanupTasks.addAll(await store.listCleanupTasks(profile.id));
  }
  final goalLinks = <GoalKnowledgeLink>[];
  final goalResumeLinks = <GoalResumeLink>[];
  for (final goal in goals) {
    requirements.addAll(await store.listGoalRequirements(goal.id));
    goalLinks.addAll(await store.listGoalKnowledgeLinks(goal.id));
    goalResumeLinks.addAll(await store.listGoalResumeLinks(goal.id));
  }

  final projects = <Project>[];
  final claims = <ResumeClaim>[];
  for (final resume in resumes) {
    projects.addAll(await store.listProjects(resume.id));
    claims.addAll(await store.listResumeClaims(resume.id));
  }

  final claimLinks = <ClaimRequirementLink>[];
  for (final claim in claims) {
    claimLinks.addAll(await store.listClaimRequirementLinks(claim.id));
  }

  final chunks = <SourceChunk>[];
  final jobs = <IngestionJob>[];
  for (final source in sources) {
    chunks.addAll(await store.listSourceChunks(source.id));
    jobs.addAll(await store.listIngestionJobs(source.id));
  }

  final reviewPoints = <ReviewPoint>[];
  for (final item in knowledgeItems) {
    reviewPoints.addAll(await store.listReviewPoints(item.id));
  }

  final messages = <CoachMessage>[];
  final checkpoints = <LessonCheckpoint>[];
  final events = <AssessmentEvent>[];
  for (final session in sessions) {
    messages.addAll(await store.messagesOf(session.id));
    checkpoints.addAll(await store.listCheckpoints(session.id));
    events.addAll(await store.listAssessmentEvents(session.id));
  }

  data['profiles'] = profiles.map((e) => e.toJson()).toList();
  data['goals'] = goals.map((e) => e.toJson()).toList();
  data['goalRequirements'] = requirements.map((e) => e.toJson()).toList();
  data['goalRevisions'] = revisions.map((e) => e.toJson()).toList();
  data['goalKnowledgeLinks'] = goalLinks.map((e) => e.toJson()).toList();
  data['goalResumeLinks'] = goalResumeLinks.map((e) => e.toJson()).toList();
  data['knowledgeItems'] = knowledgeItems.map((e) => e.toJson()).toList();
  data['reviewPoints'] = reviewPoints.map((e) => e.toJson()).toList();
  data['resumes'] = resumes.map((e) => e.toJson()).toList();
  data['projects'] = projects.map((e) => e.toJson()).toList();
  data['resumeClaims'] = claims.map((e) => e.toJson()).toList();
  data['claimRequirementLinks'] = claimLinks.map((e) => e.toJson()).toList();
  data['sources'] = sources.map((e) => e.toJson()).toList();
  data['sourceChunks'] = chunks.map((e) => e.toJson()).toList();
  data['ingestionJobs'] = jobs.map((e) => e.toJson()).toList();
  data['reviewStates'] = reviewStates.map((e) => e.toJson()).toList();
  data['assessmentEvents'] = events.map((e) => e.toJson()).toList();
  data['sessions'] = sessions.map((e) => e.toJson()).toList();
  data['messages'] = messages.map((e) => e.toJson()).toList();
  data['checkpoints'] = checkpoints.map((e) => e.toJson()).toList();
  data['dailyPlans'] = dailyPlans.map((e) => e.toJson()).toList();
  data['tombstones'] = tombstones.map((e) => e.toJson()).toList();
  data['extensions'] = extensions.map((e) => e.toJson()).toList();
  data['cleanupTasks'] = cleanupTasks.map((e) => e.toJson()).toList();

  final counts = data.map((k, v) => MapEntry(k, (v as List).length));
  return {
    'app': 'mianshi-zhilian',
    'kind': 'coach-backup',
    'schemaVersion': coachBackupSchemaVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'counts': counts,
    'contentHash': _sha256(data),
    'data': data,
  };
}

/// 校验并恢复备份（合并式 upsert）。结构或指纹不符时抛 [FormatException]。
Future<CoachBackupRestoreResult> restoreCoachBackup(
  CoachStore store,
  Map<String, Object?> backup,
) async {
  if (backup['app'] != 'mianshi-zhilian' || backup['kind'] != 'coach-backup') {
    throw const FormatException('not a coach backup file');
  }
  final schemaVersion = backup['schemaVersion'];
  if (schemaVersion is! int ||
      schemaVersion < 1 ||
      schemaVersion > coachBackupSchemaVersion) {
    throw FormatException('unsupported backup schema: $schemaVersion');
  }
  final data = backup['data'];
  if (data is! Map) throw const FormatException('backup data missing');
  final normalized = data.map((k, v) => MapEntry(k.toString(), v));
  final expected = backup['contentHash'];
  if (expected is! String) {
    throw const FormatException('backup content hash missing');
  }
  final hashMatched =
      (schemaVersion == 1 ? _contentHash(normalized) : _sha256(normalized)) ==
      expected;
  if (!hashMatched) {
    // 指纹不符：文件被改过或截断。宁可拒绝恢复，也不恢复半份数据。
    throw const FormatException('backup content hash mismatch');
  }

  final counts = backup['counts'];
  if (counts is! Map) throw const FormatException('backup counts missing');
  final keys = {..._backupKeys, if (schemaVersion >= 2) 'cleanupTasks'};
  if (normalized.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(normalized.keys.toSet()).isNotEmpty ||
      counts.keys.toSet().difference(keys).isNotEmpty) {
    throw const FormatException('backup tables do not match schema');
  }
  final tables = <String, List<Map<String, Object?>>>{};
  for (final key in keys) {
    final rows = normalized[key];
    if (rows is! List ||
        rows.any((e) => e is! Map) ||
        counts[key] != rows.length) {
      throw FormatException('invalid backup table or count: $key');
    }
    tables[key] = rows.map((e) => Map<String, Object?>.from(e as Map)).toList();
  }
  List<Map<String, Object?>> listOf(String key) => tables[key] ?? const [];
  final profiles = listOf('profiles').map((p) => p['id']).toSet();
  for (final table in tables.entries) {
    final ids = <String>{};
    for (final row in table.value) {
      if (table.key != 'profiles' &&
          table.key != 'sourceChunks' &&
          !profiles.contains(row['profileId'])) {
        throw FormatException('missing profile in ${table.key}');
      }
      if (!ids.add(_rowId(table.key, row))) {
        throw FormatException('duplicate backup entity in ${table.key}');
      }
    }
  }

  _validateReferences(tables);

  var restored = 0;

  await store.transaction(() async {
    final current = (await _exportSnapshot(store))['data'] as Map;
    final localMarkers = (current['tombstones'] as List)
        .map((r) => CoachTombstone.fromJson(Map<String, Object?>.from(r)))
        .toList();
    final incomingMarkers = listOf(
      'tombstones',
    ).map(CoachTombstone.fromJson).toList();
    for (final profile in profiles.cast<String>()) {
      int generation(List<CoachTombstone> markers) => markers
          .where(
            (t) => t.profileId == profile && t.entityType == 'profile_reset',
          )
          .fold(0, (value, t) => t.generation > value ? t.generation : value);
      final localGeneration = generation(localMarkers);
      final incomingGeneration = generation(incomingMarkers);
      if (incomingGeneration < localGeneration) {
        throw const FormatException('Backup predates personal data reset');
      }
      if (incomingGeneration > localGeneration) {
        await store.clearProfileData(profile);
      }
    }
    for (final marker in [...localMarkers, ...incomingMarkers]) {
      final table = switch (marker.entityType) {
        'goal' => 'goals',
        'knowledge' => 'knowledgeItems',
        _ => null,
      };
      if (table == null) continue;
      if (listOf(table).any(
        (r) =>
            r['profileId'] == marker.profileId &&
            r['id'] == marker.entityId &&
            r['contentStatus'] != 'removed',
      )) {
        throw const FormatException('Backup would restore deleted material');
      }
    }

    for (final table in tables.entries) {
      final existing = {
        for (final row in current[table.key] as List? ?? const [])
          _rowId(table.key, Map<String, Object?>.from(row as Map)): row,
      };
      for (final row in table.value) {
        final old = existing[_rowId(table.key, row)];
        if (old != null &&
            (old['profileId'] != row['profileId'] ||
                (table.key == 'sourceChunks' &&
                    old['sourceId'] != row['sourceId']))) {
          throw const FormatException('backup would overwrite another profile');
        }
        if (old != null &&
            table.key == 'messages' &&
            _sha256(Map<String, Object?>.from(old)) != _sha256(row)) {
          throw const FormatException(
            'backup conflicts with a saved original message',
          );
        }
      }
    }
    for (final json in listOf('profiles')) {
      await store.putProfile(Profile.fromJson(json));
      restored++;
    }
    for (final json in listOf('goals')) {
      await store.putGoal(Goal.fromJson(json));
      restored++;
    }
    for (final json in listOf('goalRequirements')) {
      await store.putGoalRequirement(GoalRequirement.fromJson(json));
      restored++;
    }
    for (final json in listOf('goalRevisions')) {
      await store.putGoalRevision(GoalRevision.fromJson(json));
      restored++;
    }
    for (final json in listOf('goalKnowledgeLinks')) {
      await store.putGoalKnowledgeLink(GoalKnowledgeLink.fromJson(json));
      restored++;
    }
    for (final json in listOf('goalResumeLinks')) {
      await store.putGoalResumeLink(GoalResumeLink.fromJson(json));
      restored++;
    }
    for (final json in listOf('knowledgeItems')) {
      await store.putKnowledgeItem(KnowledgeItem.fromJson(json));
      restored++;
    }
    for (final json in listOf('reviewPoints')) {
      await store.putReviewPoint(ReviewPoint.fromJson(json));
      restored++;
    }
    for (final json in listOf('resumes')) {
      await store.putResume(Resume.fromJson(json));
      restored++;
    }
    for (final json in listOf('projects')) {
      await store.putProject(Project.fromJson(json));
      restored++;
    }
    for (final json in listOf('resumeClaims')) {
      await store.putResumeClaim(ResumeClaim.fromJson(json));
      restored++;
    }
    for (final json in listOf('claimRequirementLinks')) {
      await store.putClaimRequirementLink(ClaimRequirementLink.fromJson(json));
      restored++;
    }
    for (final json in listOf('sources')) {
      await store.putSource(Source.fromJson(json));
      restored++;
    }
    for (final json in listOf('sourceChunks')) {
      await store.putSourceChunk(SourceChunk.fromJson(json));
      restored++;
    }
    for (final json in listOf('ingestionJobs')) {
      await store.putIngestionJob(IngestionJob.fromJson(json));
      restored++;
    }
    for (final json in listOf('reviewStates')) {
      await store.putReviewState(ReviewState.fromJson(json));
      restored++;
    }
    for (final json in listOf('assessmentEvents')) {
      await store.putAssessmentEvent(AssessmentEvent.fromJson(json));
      restored++;
    }
    for (final json in listOf('sessions')) {
      var session = CoachSession.fromJson(json);
      final local = await store.getSession(session.id);
      if (local != null && local.turnSequence > session.turnSequence) {
        session = local;
      }
      if (session.status == RuntimeStatus.generating ||
          session.status == RuntimeStatus.toolRunning) {
        session = session.copyWith(status: RuntimeStatus.paused);
      }
      await store.putSession(session);
      restored++;
    }
    for (final json in listOf('messages')) {
      await store.putMessage(CoachMessage.fromJson(json));
      restored++;
    }
    for (final json in listOf('checkpoints')) {
      await store.putCheckpoint(LessonCheckpoint.fromJson(json));
      restored++;
    }
    for (final json in listOf('dailyPlans')) {
      await store.putDailyPlan(DailyPlan.fromJson(json));
      restored++;
    }
    for (final json in listOf('tombstones')) {
      final marker = CoachTombstone.fromJson(json);
      if (marker.entityType == 'goal') {
        final goal = await store.getGoal(marker.entityId);
        if (goal != null && goal.profileId != marker.profileId) {
          throw const FormatException('Cross-profile deletion marker');
        }
        await store.deleteGoal(marker.entityId);
      }
      if (marker.entityType == 'knowledge') {
        final knowledge = await store.getKnowledgeItem(marker.entityId);
        if (knowledge != null && knowledge.profileId != marker.profileId) {
          throw const FormatException('Cross-profile deletion marker');
        }
        if (knowledge != null && knowledge.contentStatus != 'removed') {
          await store.putKnowledgeItem(
            knowledge.copyWith(
              contentStatus: 'removed',
              version: knowledge.version + 1,
              updatedAt: marker.deletedAt,
            ),
          );
        }
        await store.deleteSourceChunksForKnowledge(marker.entityId);
      }
      await store.putTombstone(marker);
      restored++;
    }
    for (final json in listOf('cleanupTasks')) {
      await store.putCleanupTask(CoachCleanupTask.fromJson(json));
      restored++;
    }
    for (final json in listOf('extensions')) {
      await store.putExtension(CoachExtensionRecord.fromJson(json));
      restored++;
    }
  });

  return CoachBackupRestoreResult(
    restoredEntities: restored,
    contentHashMatched: hashMatched,
  );
}

/// 稳定内容指纹：FNV-1a 64 位，对 canonical JSON 计算。
/// 仅用于完整性展示与校验，不作为安全摘要。
String _contentHash(Map<String, Object?> data) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  for (final byte in utf8.encode(jsonEncode(data))) {
    hash = ((hash ^ BigInt.from(byte)) * prime).toUnsigned(64);
  }
  // Schema 1 used a signed Dart VM int. Preserve its exact serialized form,
  // including negative hashes, while allowing dart2js to compile the reader.
  return hash.toSigned(64).toRadixString(16).padLeft(16, '0');
}

const _backupKeys = {
  'profiles',
  'goals',
  'goalRequirements',
  'goalRevisions',
  'goalKnowledgeLinks',
  'goalResumeLinks',
  'knowledgeItems',
  'reviewPoints',
  'resumes',
  'projects',
  'resumeClaims',
  'claimRequirementLinks',
  'sources',
  'sourceChunks',
  'ingestionJobs',
  'reviewStates',
  'assessmentEvents',
  'sessions',
  'messages',
  'checkpoints',
  'dailyPlans',
  'tombstones',
  'extensions',
};

String _rowId(String table, Map<String, Object?> row) {
  final fields = switch (table) {
    'goalKnowledgeLinks' => ['goalId', 'knowledgeItemId'],
    'goalResumeLinks' => ['goalId', 'resumeId'],
    'claimRequirementLinks' => ['claimId', 'requirementId'],
    'reviewStates' => ['reviewPointId'],
    'tombstones' => ['profileId', 'entityType', 'entityId'],
    'extensions' => ['profileId', 'kind', 'id'],
    _ => ['id'],
  };
  if (fields.any((f) => row[f] is! String || (row[f] as String).isEmpty)) {
    throw FormatException('invalid identity in $table');
  }
  return jsonEncode(fields.map((f) => row[f]).toList());
}

String _sha256(Map<String, Object?> data) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(data)))).toString();
}

void _validateReferences(Map<String, List<Map<String, Object?>>> tables) {
  final byId = {
    for (final table in tables.entries)
      table.key: {
        for (final row in table.value)
          if (row['id'] != null) row['id']: row,
      },
  };
  const targets = {
    'goalId': 'goals',
    'resumeId': 'resumes',
    'projectId': 'projects',
    'knowledgeItemId': 'knowledgeItems',
    'reviewPointId': 'reviewPoints',
    'sessionId': 'sessions',
    'sourceId': 'sources',
    'claimId': 'resumeClaims',
    'requirementId': 'goalRequirements',
  };
  for (final table in tables.entries) {
    for (final row in table.value) {
      final source = (byId['sources'] ?? {})[row['sourceId']];
      final profile = table.key == 'sourceChunks'
          ? (source == null ? null : source['profileId'])
          : row['profileId'];
      if (table.key == 'sourceChunks' && profile == null) {
        throw const FormatException('source chunk has no source');
      }
      for (final ref in targets.entries) {
        final id = row[ref.key];
        if (id == null) continue;
        final parent = byId[ref.value]?[id];
        // Deleted goals/knowledge may remain as historical references. A
        // present parent must always belong to the same profile.
        if (parent != null && parent['profileId'] != profile) {
          throw FormatException('cross-profile reference in ${table.key}');
        }
        if (parent == null &&
            table.key == 'messages' &&
            ref.key == 'sessionId') {
          throw const FormatException('message has no session');
        }
      }
    }
  }
}
