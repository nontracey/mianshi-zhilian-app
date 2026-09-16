import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mianshi_zhilian/coach/jobs/models.dart';
import 'package:mianshi_zhilian/coach/jobs/local_demo_search.dart';
import 'package:mianshi_zhilian/coach/mcp/mcp_client.dart';
import 'package:mianshi_zhilian/coach/model/http_client.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/services/coach_legacy_migration.dart';
import 'package:mianshi_zhilian/services/job_search_config.dart';
import 'package:mianshi_zhilian/services/job_search_transport.dart';
import 'package:mianshi_zhilian/services/mcp_config_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import '../helpers/secure_storage_mock.dart';

class _PendingHttp implements HttpClient {
  CancelToken? token;
  @override
  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    required String body,
    CancelToken? cancel,
  }) {
    token = cancel;
    return Completer<HttpResponse>().future;
  }

  @override
  Stream<String> postStreaming(
    String url, {
    Map<String, String>? headers,
    required String body,
    CancelToken? cancel,
  }) => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
  });

  test(
    'optional demo follows the query and has no invented dates or salary',
    () {
      const transport = LocalDemoJobSearchTransport();
      final query = SearchQuery(keywords: '界面设计');
      final first = transport.buildDemoJobs(query);
      final second = transport.buildDemoJobs(query);
      expect(first.map((j) => j.externalId), second.map((j) => j.externalId));
      for (final job in first) {
        expect(job.location, isNull);
        expect(job.salary, isNull);
        expect(job.postedAt, isNull);
        expect(job.snippet, contains('界面设计'));
        expect(job.snippet, isNot(contains('Java')));
      }
    },
  );

  test(
    'search credentials clear immediately and never follow an endpoint change',
    () async {
      final config = JobSearchConfigController(storage: StorageService());
      addTearDown(config.dispose);
      await config.configure(
        mode: JobSearchMode.custom,
        endpoint: 'https://one.test',
        apiKey: 'first',
      );
      expect(await config.hasStoredApiKey(), isTrue);
      await config.configure(
        mode: JobSearchMode.custom,
        endpoint: 'https://two.test',
      );
      expect(await config.hasStoredApiKey(), isFalse);
      await config.configure(
        mode: JobSearchMode.custom,
        endpoint: 'https://one.test',
        apiKey: '',
      );
      expect(await config.hasStoredApiKey(), isFalse);
      await config.configure(
        mode: JobSearchMode.custom,
        endpoint: 'https://one.test',
        apiKey: 'again',
      );
      await config.configure(mode: JobSearchMode.off);
      expect(await config.hasStoredApiKey(), isFalse);
    },
  );
  test('search timeout actually aborts the transport', () async {
    final http = _PendingHttp();
    final transport = HttpJobSearchTransport(
      http: http,
      endpoint: 'https://one.test',
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(
      transport.fetch(SearchQuery(keywords: 'role')),
      throwsA(isA<TimeoutException>()),
    );
    expect(http.token!.isCancelled, isTrue);
  });
  test('MCP credentials are isolated by profile and endpoint', () async {
    final store = InMemoryCoachStore();
    final storage = StorageService();
    final a = McpConfigService(store: store, storage: storage, profileId: 'a');
    final b = McpConfigService(store: store, storage: storage, profileId: 'b');
    const first = McpServerConfig(
      id: 'same',
      name: 'first',
      url: 'https://one.test',
    );
    const changed = McpServerConfig(
      id: 'same',
      name: 'changed',
      url: 'https://two.test',
    );
    await a.save(first, token: 'first-token');
    await b.save(first, token: 'second-token');
    expect((await a.list()).single.token, 'first-token');
    expect((await b.list()).single.token, 'second-token');
    await a.save(changed);
    expect((await a.list()).single.token, isNull);
  });
  test(
    'failed credential writes do not save MCP metadata; failed deletes are reported',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'unavailable'),
          );
      final store = InMemoryCoachStore();
      final storage = StorageService();
      final service = McpConfigService(store: store, storage: storage);
      expect(
        await service.save(
          const McpServerConfig(id: 'm', name: 'name', url: 'https://one.test'),
          token: 'token',
        ),
        isFalse,
      );
      expect(await service.list(), isEmpty);
      expect(await storage.writeSecret('test', ''), isFalse);
      await expectLater(
        storage.deleteSecret('test'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  test(
    'migration reads archived answers, deduplicates active records and preserves legacy scores',
    () async {
      Map<String, dynamic> attempt(String id) => {
        'id': id,
        'topicId': 'old-topic',
        'question': 'question',
        'answer': 'answer-$id',
        'mode': 'recall',
        'score': 73,
        'createdAt': '2026-01-01T12:00:00',
      };
      SharedPreferences.setMockInitialValues({
        'practice_attempts': jsonEncode([attempt('active')]),
        'practice_attempts_archive': jsonEncode([
          attempt('archived'),
          attempt('active'),
        ]),
      });
      final store = InMemoryCoachStore();
      final report = await migrateLegacyPracticeData(
        storage: StorageService(),
        store: store,
      );
      expect(report!.importedSessions, 2);
      expect(await store.listSessions('local-default'), hasLength(2));
      expect(await store.listReviewStates('local-default'), isEmpty);
    },
  );
  test('unconfigured custom search is not advertised as configured', () async {
    final config = JobSearchConfigController(storage: StorageService());
    addTearDown(config.dispose);
    await config.sync(const AppSettings(jobSearchMode: JobSearchMode.custom));
    expect(config.state.configured, isFalse);
  });
}
