import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/services/data_sync_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import '../helpers/secure_storage_mock.dart';
import '../coach/implementation_flows_test.dart' show seed, provider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
  });
  test('legacy switches never opt new coach material into sync', () {
    final old=SyncSettings.fromJson(const {'method':'webdav','syncPrivatePrepData':true,'syncFullPracticeText':true});
    expect(old.syncCoachPrivateMaterials,false);
    expect(old.syncCoachOriginalAnswers,false);
    final enabled=old.copyWith(syncCoachPrivateMaterials:true,syncCoachOriginalAnswers:true);
    expect(SyncSettings.fromJson(enabled.toJson()).syncCoachOriginalAnswers,true);
  });

  test(
    'automatic sync includes isolated coach data and honors interval and privacy',
    () async {
      final storage = StorageService();
      await storage.saveSyncSettings(
        const SyncSettings(
          method: 'webdav',
          webDavUrl: 'https://sync.example/data',
          webDavUsername: 'test',
          webDavPassword: 'synthetic',
          autoSyncEnabled: true,
          syncPrivatePrepData: true,
          syncFullPracticeText: true,
        ),
      );
      final store = InMemoryCoachStore();
      await seed(store);
      await provider(store).load();
      final service = DataSyncService(storage);
      var imports = 0;
      service.attachCoach(
        store,
        canImport: () => true,
        onImported: () async {
          imports++;
        },
      );
      final uploads = <String, String>{};
      final result = await http.runWithClient(
        () => service.syncIfNeeded(force: true),
        () => MockClient((r) async {
          expect(r.followRedirects, false);
          if (r.method == 'GET') return http.Response('', 404);
          uploads[r.url.path] = r.body;
          return http.Response('', 201);
        }),
      );
      expect(result.success, true);
      expect(
        uploads.keys,
        containsAll(['/data/sync-state.json', '/data/coach-state-v2.json']),
      );
      final coach = uploads['/data/coach-state-v2.json']!;
      expect(jsonDecode(coach)['kind'], 'coach-backup');
      expect(coach, isNot(contains('Understand concurrency')));
      expect(imports, 1);
      await http.runWithClient(
        () => service.syncIfNeeded(),
        () => MockClient(
          (_) async => throw StateError('interval must defer requests'),
        ),
      );
      expect(imports, 1);
    },
  );
  test(
    'a reply started during upload prevents restore until the next idle sync',
    () async {
      final storage = StorageService();
      await storage.saveSyncSettings(
        const SyncSettings(
          method: 'webdav',
          webDavUrl: 'https://sync.example/data',
          webDavUsername: 'test',
          webDavPassword: 'synthetic',
        ),
      );
      final store = InMemoryCoachStore();
      await seed(store);
      await provider(store).load();
      final service = DataSyncService(storage);
      var busy = false, imported = false;
      service.attachCoach(
        store,
        canImport: () => !busy,
        onImported: () async {
          imported = true;
        },
      );
      final result = await http.runWithClient(
        () => service.syncCoach(store),
        () => MockClient((r) async {
          if (r.method == 'GET') return http.Response('', 404);
          busy = true;
          return http.Response('', 201);
        }),
      );
      expect(result.l10nKey, 'coach_sync_busy');
      expect(imported, false);
      expect(
        (await store.getGoal('g'))!.originalText,
        'Understand concurrency',
      );
    },
  );
}
