/// 旧数据迁移与教练库备份的持久化层测试（§9 存储改造、审计项 5）。
///
/// 全部纯 Dart：InMemoryCoachStore + 合成演示数据。
/// - 迁移：可重入（重复执行不产生副本）、跳过无原答记录、旧进度如实计数不迁移；
/// - 备份：导出 → 恢复为等价库；指纹不符拒绝恢复。
library;

import 'dart:convert';

import 'harness.dart';

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/profile.dart';
import 'package:mianshi_zhilian/coach/domain/resume.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_backup.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/legacy_migration.dart';

final DateTime now = DateTime(2026, 9, 12, 10);

Map<String, dynamic> legacyAttempt(
  String id, {
  String question = '讲一下 HashMap 的底层结构？',
  String answer = '数组加链表，JDK8 引入红黑树。',
  String mode = 'recall',
  String? createdAt = '2026-08-01T10:00:00.000',
}) => {
  'id': id,
  'topicId': 'hashmap',
  'promptId': 'p1',
  'mode': mode,
  'question': question,
  'answer': answer,
  'createdAt': createdAt,
  'score': 80,
  'aiEvaluated': true,
  'localOnly': true,
  'analysisStatus': 'success',
};

void main() {
  group('旧练习数据迁移', () {
    test('首次迁移：为每条有原答的记录建会话与消息', () async {
      final store = InMemoryCoachStore();
      final migrator = LegacyPracticeMigrator(
        store: store,
        profileId: 'local-default',
        clock: FixedClock(now),
      );

      final report = await migrator.migrate(
        LegacyPracticeInput(
          attempts: [
            legacyAttempt('a1'),
            legacyAttempt('a2', mode: 'mockInterview'),
          ],
          progressEntries: {'hashmap': {}, 'spring': {}},
        ),
      );

      expect(report.importedSessions, 2);
      expect(report.skippedExisting, 0);
      expect(report.skippedProgressEntries, 2, reason: '旧进度如实计数，不迁移');

      final sessions = await store.listSessions('local-default');
      expect(sessions, hasLength(2));
      final review = sessions.firstWhere((s) => s.mode == SessionMode.review);
      final interview = sessions.firstWhere(
        (s) => s.mode == SessionMode.interview,
      );
      expect(review.status, RuntimeStatus.completed);
      expect(interview.status, RuntimeStatus.completed);

      final messages = await store.messagesOf(review.id);
      expect(messages, hasLength(2));
      expect(messages[0].role, 'assistant');
      expect(messages[0].content, contains('HashMap'));
      expect(messages[1].role, 'user');
      expect(messages[1].content, contains('红黑树'));
    });

    test('重复迁移可重入：不产生副本；无原答的记录跳过', () async {
      final store = InMemoryCoachStore();
      final migrator = LegacyPracticeMigrator(
        store: store,
        profileId: 'local-default',
        clock: FixedClock(now),
      );
      final input = LegacyPracticeInput(
        attempts: [
          legacyAttempt('a1'),
          legacyAttempt('a2', answer: ''),
        ],
      );

      final first = await migrator.migrate(input);
      expect(first.importedSessions, 1);
      expect(first.skippedExisting, 1, reason: 'a2 无原答，如实跳过');

      final second = await migrator.migrate(input);
      expect(second.importedSessions, 0, reason: '可重入，不重复导入');
      expect(second.skippedExisting, 2);

      final sessions = await store.listSessions('local-default');
      expect(sessions, hasLength(1));
    });

    test('旧数据新增后再次迁移：只补增量并在记录中标注变化', () async {
      final store = InMemoryCoachStore();
      final migrator = LegacyPracticeMigrator(
        store: store,
        profileId: 'local-default',
        clock: FixedClock(now),
      );

      await migrator.migrate(
        LegacyPracticeInput(attempts: [legacyAttempt('a1')]),
      );
      final second = await migrator.migrate(
        LegacyPracticeInput(
          attempts: [legacyAttempt('a1'), legacyAttempt('a3')],
        ),
      );
      expect(second.changed, isTrue, reason: '旧数据发生了变化');
      expect(second.importedSessions, 1);
    });
  });

  group('教练库备份导出与恢复', () {
    test('导出 → 清空 → 恢复得到等价数据', () async {
      final source = InMemoryCoachStore();
      final now0 = DateTime(2026, 9, 1, 9);
      await source.putProfile(
        Profile(
          id: 'p1',
          displayName: '演示档案',
          createdAt: now0,
          updatedAt: now0,
        ),
      );
      await source.putResume(
        Resume(
          id: 'r1',
          profileId: 'p1',
          versionLabel: 'v1',
          originalText: '五年 Java 后端经验…',
          createdAt: now0,
        ),
      );
      await source.putSession(
        CoachSession(
          id: 's1',
          profileId: 'p1',
          mode: SessionMode.review,
          createdAt: now0,
          status: RuntimeStatus.completed,
        ),
      );
      await source.putMessage(
        CoachMessage(
          id: 'm1',
          sessionId: 's1',
          profileId: 'p1',
          role: 'user',
          content: '原答回复',
          turnId: 't1',
          sequence: 1,
          createdAt: now0,
        ),
      );

      final backup = await exportCoachBackup(source);
      expect(backup['kind'], 'coach-backup');
      expect((backup['counts'] as Map)['messages'], 1);
      // 备份 JSON 必须可无损序列化。
      final encoded = jsonEncode(backup);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      final target = InMemoryCoachStore();
      final result = await restoreCoachBackup(target, decoded);
      expect(result.contentHashMatched, isTrue);
      expect(result.restoredEntities, greaterThan(0));

      final profiles = await target.listProfiles();
      expect(profiles.single.displayName, '演示档案');
      final resumes = await target.listResumes('p1');
      expect(resumes.single.versionLabel, 'v1');
      final messages = await target.messagesOf('s1');
      expect(messages.single.content, '原答回复');
    });

    test('内容被篡改时拒绝恢复', () async {
      final source = InMemoryCoachStore();
      await source.putProfile(
        Profile(
          id: 'p1',
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );
      final backup = await exportCoachBackup(source);
      (backup['data'] as Map)['profiles'] = <Map<String, dynamic>>[];

      await expectThrowsAsync(
        () => restoreCoachBackup(InMemoryCoachStore(), backup),
        isA<FormatException>(),
      );
    });

    test('非备份文件与不支持的 schema 被拒绝', () async {
      await expectThrowsAsync(
        () => restoreCoachBackup(InMemoryCoachStore(), {'app': 'other'}),
        isA<FormatException>(),
      );
      await expectThrowsAsync(
        () => restoreCoachBackup(InMemoryCoachStore(), {
          'app': 'mianshi-zhilian',
          'kind': 'coach-backup',
          'schemaVersion': 99,
          'contentHash': 'x',
          'data': <String, dynamic>{},
        }),
        isA<FormatException>(),
      );
    });
  });
}
