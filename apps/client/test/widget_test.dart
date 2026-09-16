import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/main.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/ai_service.dart';
import 'package:mianshi_zhilian/services/data_sync_service.dart';
import 'package:mianshi_zhilian/services/analytics_service.dart';
import 'package:mianshi_zhilian/services/endpoint_fallback_client.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
import 'package:mianshi_zhilian/providers/theme_provider.dart';
import 'package:mianshi_zhilian/providers/connectivity_provider.dart';
import 'package:mianshi_zhilian/providers/coach_provider.dart';
import 'package:mianshi_zhilian/providers/goal_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/services/coach_model_binding.dart';
import 'package:mianshi_zhilian/services/job_search_config.dart';
import 'package:mianshi_zhilian/services/mcp_config_service.dart';
import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/jobs/jd_import_service.dart';
import 'package:mianshi_zhilian/coach/knowledge/chunker.dart';
import 'package:mianshi_zhilian/coach/knowledge/importer.dart';
import 'package:mianshi_zhilian/coach/knowledge/parser.dart';
// 只取 CancelToken / HttpCanceledException：coach 的 HttpClient 与 dart:io 同名，
// 必须 hide 掉，否则 test 里的 HttpOverrides 会解析成错的类型。
import 'package:mianshi_zhilian/coach/model/http_client.dart'
    hide HttpClient, HttpResponse;
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/resume/claim_mapping.dart';
import 'package:mianshi_zhilian/coach/resume/resume_parse.dart';
import 'package:mianshi_zhilian/services/coach_store_factory.dart';

/// 测试环境把 NetworkImage 拦截掉，统一返回 1x1 透明 PNG，
/// 否则 widget tree 里的 DiceBear 头像会让 pumpAndSettle 失败。
class _StubHttpOverrides extends HttpOverrides {
  static final Uint8List _png1x1 = Uint8List.fromList(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x62,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  @override
  HttpClient createHttpClient(SecurityContext? context) => _StubHttpClient();
}

class _StubHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _StubRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StubRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _StubResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubResponse implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _StubHttpOverrides._png1x1.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_StubHttpOverrides._png1x1]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _StubHttpOverrides();

  testWidgets('renders learning workspace', (tester) async {
    final storage = StorageService();
    final routeClient = EndpointFallbackClient(
      stateStore: EndpointStateStore(storage),
    );
    final contentApi = ContentApiService(routeClient: routeClient);
    final aiService = AiService();
    final dataSyncService = DataSyncService(storage);
    final analyticsService = AnalyticsService(storage);
    final updateService = UpdateService();

    // 教练模块：测试里用内存实现，避免依赖 sqlite / 文件系统。
    final coachStore = InMemoryCoachStore();
    final coachProvider = CoachProvider(store: coachStore);
    final goalProvider = GoalProvider(
      store: coachStore,
      documents: DocumentImporter(
        parser: const BuiltInDocumentParser(),
        chunker: Chunker(),
        idGen: IdGenerator(),
        clock: const SystemClock(),
      ),
      resumeImport: ResumeImportService(
        parser: const RuleBasedResumeParser(),
        idGen: IdGenerator(),
        clock: const SystemClock(),
        matcher: KeywordClaimMatcher(),
      ),
      jdImport: JdImportService(
        fetcher: _UnsupportedJdFetcher(),
        parser: const HeuristicJdParser(),
        idGen: IdGenerator(),
        clock: const SystemClock(),
      ),
    );

    await tester.pumpWidget(
      MianshiZhilianApp(
        storage: storage,
        dataSyncService: dataSyncService,
        contentApi: contentApi,
        aiService: aiService,
        analyticsService: analyticsService,
        updateService: updateService,
        routeClient: routeClient,
        initialLanguage: 'zh',
        themeProvider: ThemeProvider(),
        connectivityProvider: ConnectivityProvider(),
        coachStoreHandle: CoachStoreHandle(coachStore, () async {}),
        coachProvider: coachProvider,
        goalProvider: goalProvider,
        coachModels: CoachModelBindingFactory(selector: () => null),
        jobSearchConfig: JobSearchConfigController(storage: storage),
        mcpConfigService: McpConfigService(store: coachStore, storage: storage),
        aiProvider: AiProvider(aiService, storage),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(MianshiZhilianApp), findsOneWidget);
  });
}

/// 测试用 JD 抓取器：不联网，调用即失败（导入链路会返回明确失败状态）。
class _UnsupportedJdFetcher implements JdFetcher {
  @override
  Future<String> fetchText(String url, {CancelToken? cancel}) async {
    throw HttpCanceledException();
  }
}
