/// 旧版练习数据 → 教练库的确定性迁移（§9 存储改造、审计项 5）。
///
/// 输入是**旧版 JSON**（`PracticeAttempt.toJson()` 的原始 Map），本文件不 import
/// 任何 Flutter / 旧模型类型，保持纯 Dart 可单测。
///
/// 诚实边界：
/// - 只迁移**用户自己留下的原答与问题文本**，不编造模型点评、不补造分数；
/// - 旧版按内容库 topicId 的进度不迁移（教练知识点体系不同，映射即造假），
///   在迁移记录里如实记为 skipped；
/// - 可重入：按旧记录 id 去重，重复执行不产生副本；数据变化时只补增量。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/common.dart';
import '../domain/profile.dart';
import '../domain/session.dart';
import 'coach_store.dart';
import 'extension_records.dart';

/// 迁移结果摘要（协议值，UI 翻译）。
class LegacyMigrationReport {
  LegacyMigrationReport({
    required this.importedSessions,
    required this.skippedExisting,
    required this.skippedProgressEntries,
    required this.changed,
  });

  final int importedSessions;
  final int skippedExisting;
  final int skippedProgressEntries;

  /// 与上次迁移记录相比，旧数据是否发生了变化（新增/删除）。
  final bool changed;

  Map<String, Object?> toJson() => {
    'importedSessions': importedSessions,
    'skippedExisting': skippedExisting,
    'skippedProgressEntries': skippedProgressEntries,
    'changed': changed,
  };
}

/// 旧版练习记录的原文（已解析的 JSON Map，字段与 `PracticeAttempt.toJson()` 一致）。
class LegacyPracticeInput {
  const LegacyPracticeInput({
    required this.attempts,
    this.progressEntries = const {},
  });

  final List<Map<String, dynamic>> attempts;

  /// 旧版按 topicId 的进度（仅用于如实计数，不迁移）。
  final Map<String, dynamic> progressEntries;
}

SessionMode _modeOf(String legacyMode) => switch (legacyMode) {
  'mockInterview' => SessionMode.interview,
  'recall' || 'review' => SessionMode.review,
  _ => SessionMode.learning,
};

const String _migrationRecordId = 'legacy.practice_attempts.v1';

/// 迁移器。所有写入走 [CoachStore] 的事务，中断不留半截数据。
class LegacyPracticeMigrator {
  const LegacyPracticeMigrator({
    required this.store,
    required this.profileId,
    this.clock = const SystemClock(),
  });

  final CoachStore store;
  final ProfileId profileId;
  final Clock clock;
  String _id(String legacyId, String kind) =>
      'legacy.${sha256.convert(utf8.encode(jsonEncode([profileId, legacyId, kind])))}';

  Future<LegacyMigrationReport> migrate(LegacyPracticeInput input) async {
    return store.transaction(() async {
      // 读取上次迁移记录（可重入依据）。
      final previous = await store.getExtension(
        profileId,
        CoachExtensionKind.legacyMigration,
        _migrationRecordId,
      );
      final previousIds = <String>{};
      final previousAttemptCount = <String, int>{};
      if (previous != null) {
        final ids = previous.value['importedIds'];
        if (ids is List) previousIds.addAll(ids.whereType<String>());
        final perKey = previous.value['attemptKeyCounts'];
        if (perKey is Map) {
          perKey.forEach((k, v) {
            if (v is int) previousAttemptCount[k.toString()] = v;
          });
        }
      }

      // 旧数据指纹：内容或数量变化时在记录中如实标注。
      final keyCounts = <String, int>{};
      for (final a in input.attempts) {
        final key = a['id']?.toString() ?? '';
        if (key.isEmpty) continue;
        keyCounts[key] = (keyCounts[key] ?? 0) + 1;
      }
      final changed = _encode(keyCounts) != _encode(previousAttemptCount);

      var imported = 0;
      var skipped = 0;
      final importedIds = <String>{...previousIds};
      final snapshots = <String, Object?>{
        if (previous?.value['attempts'] case final Map saved)
          ...saved.map((k, v) => MapEntry(k.toString(), v)),
      };
      for (final attempt in input.attempts) {
        final id = attempt['id']?.toString() ?? '';
        if (id.isNotEmpty) snapshots.putIfAbsent(id, () => attempt);
      }

      // 确保档案存在（教练库可能还是空的）。
      final profile = await store.getProfile(profileId);
      if (profile == null) {
        final now = clock.now();
        await store.putProfile(
          Profile(id: profileId, createdAt: now, updatedAt: now),
        );
      }

      for (final attempt in input.attempts) {
        final id = attempt['id']?.toString() ?? '';
        if (id.isEmpty || importedIds.contains(id)) {
          skipped++;
          continue;
        }
        final answer = attempt['answer']?.toString() ?? '';
        if (answer.trim().isEmpty) {
          // 没有原答的记录对教练没有价值，如实跳过而不是造一条空会话。
          skipped++;
          continue;
        }
        final createdAt = _parseDate(attempt['createdAt']) ?? clock.now();
        final question = attempt['question']?.toString() ?? '';
        final session = CoachSession(
          id: _id(id, 'session'),
          profileId: profileId,
          mode: _modeOf(attempt['mode']?.toString() ?? ''),
          createdAt: createdAt,
          status: RuntimeStatus.completed,
          endedAt: createdAt,
          startedAt: createdAt,
          turnSequence: question.trim().isEmpty ? 1 : 2,
        );
        await store.putSession(session);
        if (question.trim().isNotEmpty) {
          await store.putMessage(
            CoachMessage(
              id: _id(id, 'question'),
              sessionId: session.id,
              profileId: profileId,
              role: 'assistant',
              content: question,
              turnId: _id(id, 'turn'),
              sequence: 1,
              createdAt: createdAt,
            ),
          );
        }
        await store.putMessage(
          CoachMessage(
            id: _id(id, 'answer'),
            sessionId: session.id,
            profileId: profileId,
            role: 'user',
            content: answer,
            turnId: _id(id, 'turn'),
            sequence: question.trim().isEmpty ? 1 : 2,
            createdAt: createdAt,
          ),
        );
        importedIds.add(id);
        imported++;
      }

      await store.putExtension(
        CoachExtensionRecord(
          profileId: profileId,
          kind: CoachExtensionKind.legacyMigration,
          id: _migrationRecordId,
          revision: (previous?.revision ?? 0) + 1,
          value: {
            'attempts': snapshots,
            'progressSnapshot': input.progressEntries,
            'snapshotHash': sha256
                .convert(utf8.encode(jsonEncode(snapshots)))
                .toString(),
            'importedIds': importedIds.toList()..sort(),
            'attemptKeyCounts': keyCounts,
            'skippedProgressEntries': input.progressEntries.length,
          },
          updatedAt: clock.now(),
        ),
      );

      return LegacyMigrationReport(
        importedSessions: imported,
        skippedExisting: skipped,
        skippedProgressEntries: input.progressEntries.length,
        changed: changed,
      );
    });
  }

  String _encode(Map<String, int> counts) {
    final keys = counts.keys.toList()..sort();
    return jsonEncode({for (final k in keys) k: counts[k]});
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
