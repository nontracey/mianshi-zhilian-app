import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/services/data_sync_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';

/// 同步合并端到端：列表集合的 LWW + 删除墓碑（B-0 / A-2）。
/// 验证「删除可跨设备传播、远端陈旧副本不复活、有意重建可恢复」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataSyncService sync;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sync = DataSyncService(StorageService());
  });

  Map<String, dynamic> route(String id, String updatedAt) => {
        'id': id,
        'name': id,
        'domainIds': const ['java'],
        'phases': const [],
        'source': 'custom',
        'createdAt': updatedAt,
        'updatedAt': updatedAt,
      };

  Map<String, dynamic> pkg({
    List<Map<String, dynamic>> customRoutes = const [],
    Map<String, String> deletions = const {},
  }) =>
      {
        'schemaVersion': 1,
        'data': {
          'custom_routes': customRoutes,
          if (deletions.isNotEmpty) 'deletions': deletions,
        },
      };

  List<String> mergedRouteIds(Map<String, dynamic> merged) {
    final list = (merged['data'] as Map)['custom_routes'] as List? ?? [];
    return list.map((e) => (e as Map)['id'].toString()).toList();
  }

  group('列表合并 LWW + 墓碑', () {
    test('远端独有项被保留（无墓碑时是并集）', () {
      final merged = sync.mergePackagesForTest(
        pkg(customRoutes: [route('A', '2026-01-01T00:00:00.000')]),
        pkg(customRoutes: [
          route('A', '2026-01-01T00:00:00.000'),
          route('C', '2026-01-01T00:00:00.000'),
        ]),
      );
      expect(mergedRouteIds(merged), containsAll(['A', 'C']));
    });

    test('本地删除（墓碑）+ 远端陈旧副本 → 不复活（删除传播）', () {
      // 本地已删 C：本地列表无 C，但带墓碑 deletedAt 晚于远端 C 的 updatedAt
      final merged = sync.mergePackagesForTest(
        pkg(
          customRoutes: [route('A', '2026-01-01T00:00:00.000')],
          deletions: {'custom_routes:C': '2026-06-01T00:00:00.000'},
        ),
        pkg(customRoutes: [
          route('A', '2026-01-01T00:00:00.000'),
          route('C', '2026-01-01T00:00:00.000'), // 远端仍有旧的 C
        ]),
      );
      expect(mergedRouteIds(merged), ['A']);
      expect(mergedRouteIds(merged), isNot(contains('C')));
      // 墓碑随包保留，继续向其它设备传播
      expect((merged['data'] as Map)['deletions'], contains('custom_routes:C'));
    });

    test('删除后有意重建（updatedAt 晚于墓碑）→ 正常恢复', () {
      final merged = sync.mergePackagesForTest(
        pkg(
          customRoutes: [
            route('A', '2026-01-01T00:00:00.000'),
            route('C', '2026-07-01T00:00:00.000'), // 本地重建的新 C
          ],
          deletions: {'custom_routes:C': '2026-06-01T00:00:00.000'},
        ),
        pkg(customRoutes: [route('A', '2026-01-01T00:00:00.000')]),
      );
      expect(mergedRouteIds(merged), containsAll(['A', 'C']));
    });

    test('同 id 取 updatedAt 较新者（LWW）', () {
      final merged = sync.mergePackagesForTest(
        pkg(customRoutes: [route('A', '2026-07-01T00:00:00.000')]), // 本地较新
        pkg(customRoutes: [route('A', '2026-01-01T00:00:00.000')]), // 远端较旧
      );
      final a = ((merged['data'] as Map)['custom_routes'] as List).single as Map;
      expect(a['updatedAt'], '2026-07-01T00:00:00.000');
    });
  });

  group('导出 → 合并 round-trip（删除经 export 传播）', () {
    test('本地删除一条路线后导出，与仍持有它的远端合并 → 被剔除', () async {
      final storage = StorageService();
      // 本地起初有 A、B 两条
      await storage.saveCustomRoutes([
        route('A', '2026-01-01T00:00:00.000'),
        route('B', '2026-01-01T00:00:00.000'),
      ]);
      // 删除 B：移除并写墓碑（与 LearningScopeProvider.deleteRoute 行为一致）
      await storage.saveCustomRoutes([route('A', '2026-01-01T00:00:00.000')]);
      await storage.recordDeletion('custom_routes', 'B');

      final localExport =
          await storage.exportSyncPackage(const SyncSettings(method: 'webdav'));
      // 远端仍持有 A、B
      final remote = pkg(customRoutes: [
        route('A', '2026-01-01T00:00:00.000'),
        route('B', '2026-01-01T00:00:00.000'),
      ]);

      final merged =
          DataSyncService(storage).mergePackagesForTest(localExport, remote);
      expect(mergedRouteIds(merged), ['A'], reason: 'B 已删，墓碑应让远端副本也消失');
    });
  });

  group('progress_map 清空墓碑（P0-3）', () {
    Map<String, dynamic> prog(String id, String lastAt) => {
          'topicId': id,
          'score': 80,
          'status': 'learning',
          'practiceCount': 2,
          'lastPracticeAt': lastAt,
        };

    test('清空墓碑 + 远端旧进度 → 不复活', () {
      final merged = DataSyncService.mergeProgressMaps(
        {'java.a': prog('java.a', '2026-01-01T00:00:00.000')},
        <String, dynamic>{}, // 本地已清空
        {'progress_map:java.a': '2026-06-01T00:00:00.000'},
      );
      expect(merged.containsKey('java.a'), isFalse);
    });

    test('删除后重新练习（lastPracticeAt 晚于墓碑）→ 恢复', () {
      final merged = DataSyncService.mergeProgressMaps(
        <String, dynamic>{},
        {'java.a': prog('java.a', '2026-07-01T00:00:00.000')},
        {'progress_map:java.a': '2026-06-01T00:00:00.000'},
      );
      expect(merged.containsKey('java.a'), isTrue);
    });

    test('无墓碑 → 正常合并保留', () {
      final merged = DataSyncService.mergeProgressMaps(
        {'java.a': prog('java.a', '2026-01-01T00:00:00.000')},
        <String, dynamic>{},
      );
      expect(merged.containsKey('java.a'), isTrue);
    });
  });

  group('practice_attempts 删除墓碑（P0-3）', () {
    Map<String, dynamic> attempt(String id) => {
          'id': id,
          'topicId': 'java.a',
          'mode': 'recall',
          'question': 'q',
          'answer': 'a',
          'createdAt': '2026-01-01T00:00:00.000',
        };

    test('删除墓碑 → 远端副本不复活', () {
      final merged = sync.mergePackagesForTest(
        {
          'schemaVersion': 1,
          'data': {
            'practice_attempts': <Map<String, dynamic>>[],
            'deletions': {'practice_attempts:at1': '2026-06-01T00:00:00.000'},
          },
        },
        {
          'schemaVersion': 1,
          'data': {
            'practice_attempts': [attempt('at1')],
          },
        },
      );
      final list =
          (merged['data'] as Map)['practice_attempts'] as List? ?? [];
      expect(list, isEmpty);
    });
  });

  group('单例键 LWW（P1-6）', () {
    Map<String, dynamic> singletonPkg(String key, dynamic value) => {
          'schemaVersion': 1,
          'data': {key: value},
        };

    dynamic mergedSingleton(Map<String, dynamic> m, String key) =>
        (m['data'] as Map)[key];

    test('prep_plan 取 updatedAt 较新者（远端更新 → 远端胜）', () {
      final merged = sync.mergePackagesForTest(
        singletonPkg('prep_plan',
            {'targetRole': '本地旧', 'updatedAt': '2026-01-01T00:00:00.000'}),
        singletonPkg('prep_plan',
            {'targetRole': '远端新', 'updatedAt': '2026-06-01T00:00:00.000'}),
      );
      expect((mergedSingleton(merged, 'prep_plan') as Map)['targetRole'], '远端新');
    });

    test('local_profile 取 updatedAt 较新者（本地更新 → 本地胜）', () {
      final merged = sync.mergePackagesForTest(
        singletonPkg('local_profile',
            {'nickname': '本地新', 'updatedAt': '2026-06-01T00:00:00.000'}),
        singletonPkg('local_profile',
            {'nickname': '远端旧', 'updatedAt': '2026-01-01T00:00:00.000'}),
      );
      expect(
          (mergedSingleton(merged, 'local_profile') as Map)['nickname'], '本地新');
    });

    test('一侧缺失时保留另一侧', () {
      final merged = sync.mergePackagesForTest(
        {'schemaVersion': 1, 'data': <String, dynamic>{}},
        singletonPkg('prep_plan',
            {'targetRole': '远端独有', 'updatedAt': '2026-06-01T00:00:00.000'}),
      );
      expect(
          (mergedSingleton(merged, 'prep_plan') as Map)['targetRole'], '远端独有');
    });
  });

  group('clearPracticeData 端到端（P0-3）', () {
    test('清空写墓碑 → 与持有旧数据的远端合并后不复活', () async {
      final storage = StorageService();
      await storage.savePracticeAttempts([
        PracticeAttempt(
          id: 'at1',
          topicId: 'java.a',
          mode: 'recall',
          question: 'q',
          answer: 'a',
          createdAt: DateTime.parse('2026-01-01T00:00:00.000'),
        ),
      ]);
      await storage.saveProgressMap({
        'java.a': TopicProgress(
          topicId: 'java.a',
          score: 80,
          status: 'learning',
          practiceCount: 1,
          lastPracticeAt: DateTime.parse('2026-01-01T00:00:00.000'),
        ),
      });

      await storage.clearPracticeData();

      final localExport =
          await storage.exportSyncPackage(const SyncSettings(method: 'webdav'));
      final remote = {
        'schemaVersion': 1,
        'data': {
          'practice_attempts': [
            {
              'id': 'at1',
              'topicId': 'java.a',
              'mode': 'recall',
              'question': 'q',
              'answer': 'a',
              'createdAt': '2026-01-01T00:00:00.000',
            },
          ],
          'progress_map': {
            'java.a': {
              'topicId': 'java.a',
              'score': 80,
              'status': 'learning',
              'practiceCount': 1,
              'lastPracticeAt': '2026-01-01T00:00:00.000',
            },
          },
        },
      };

      final merged =
          DataSyncService(storage).mergePackagesForTest(localExport, remote);
      final attempts =
          (merged['data'] as Map)['practice_attempts'] as List? ?? [];
      final progressMap =
          (merged['data'] as Map)['progress_map'] as Map? ?? {};
      expect(attempts, isEmpty, reason: '清空后练习记录不应复活');
      expect(progressMap.containsKey('java.a'), isFalse,
          reason: '清空后进度不应复活');
    });
  });
}
