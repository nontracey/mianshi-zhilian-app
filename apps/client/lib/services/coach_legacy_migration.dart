/// 把旧版 SharedPreferences 里的练习原答迁移进教练库（§9、审计项 5）。
///
/// 这是 Flutter 侧装配：读取旧存储的typed模型，转成纯 JSON 交给
/// 纯 Dart 的 [LegacyPracticeMigrator]。迁移失败只记日志、不阻塞启动——
/// 旧数据仍在原处，下次启动可再次尝试（迁移器本身可重入）。
library;

import 'package:flutter/foundation.dart';

import '../coach/persistence/coach_store.dart';
import '../coach/persistence/legacy_migration.dart';
import '../coach/persistence/legacy_material_migration.dart';
import 'storage_service.dart';
import '../providers/coach_provider.dart' show kDefaultProfileId;

/// 迁移旧练习原答。返回 null 表示本次未执行（如读取失败）。
Future<LegacyMigrationReport?> migrateLegacyPracticeData({
  required StorageService storage,
  required CoachStore store,
  String profileId = kDefaultProfileId,
}) async {
  try {
    if ((await store.listTombstones(
      profileId,
    )).any((t) => t.entityType == 'profile_reset'))
      return null;
    final active = await storage.loadPracticeAttempts();
    final archived = await storage.loadArchivedPracticeAttempts();
    final attempts = {
      for (final a in [...archived, ...active]) a.id: a,
    }.values.toList();
    final progress = await storage.loadProgressMap();
    final snapshot = <String, Object?>{
      for (final key in [
        'prep_plan',
        'project_library',
        'project_dig_projects',
        'mock_interview_sessions',
      ])
        key: await storage.load(key),
      'practice_attempts': attempts.map((a) => a.toJson()).toList(),
      'progress': progress.map((k, v) => MapEntry(k, v.toJson())),
    };
    return await migrateLegacyUpgradeAtomic(
      store: store,
      profileId: profileId,
      snapshot: snapshot,
      practice: LegacyPracticeInput(
        attempts: attempts.map((a) => a.toJson()).toList(),
        progressEntries: progress.map((k, v) => MapEntry(k, v.toJson())),
      ),
    );
  } catch (e) {
    debugPrint('Legacy coach migration skipped: $e');
    return null;
  }
}

/// Both legacy import phases commit together. A failed practice write must not
/// leave the material snapshot marked imported on the next launch.
Future<LegacyMigrationReport> migrateLegacyUpgradeAtomic({
  required CoachStore store,
  required String profileId,
  required Map<String, Object?> snapshot,
  required LegacyPracticeInput practice,
}) => store.transaction(() async {
  await LegacyMaterialMigrator(
    store: store,
    profileId: profileId,
  ).migrate(snapshot);
  return LegacyPracticeMigrator(
    store: store,
    profileId: profileId,
  ).migrate(practice);
});
