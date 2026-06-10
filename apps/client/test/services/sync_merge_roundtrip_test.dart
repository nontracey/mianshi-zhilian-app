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
}
