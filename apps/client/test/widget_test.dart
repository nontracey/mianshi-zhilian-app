import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/main.dart';
import 'package:mianshi_zhilian/services/content_api_service.dart';
import 'package:mianshi_zhilian/services/ai_service.dart';
import 'package:mianshi_zhilian/services/data_sync_service.dart';
import 'package:mianshi_zhilian/services/analytics_service.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';

/// 测试环境把 NetworkImage 拦截掉，统一返回 1x1 透明 PNG，
/// 否则 widget tree 里的 DiceBear 头像会让 pumpAndSettle 失败。
class _StubHttpOverrides extends HttpOverrides {
  static final Uint8List _png1x1 = Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
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
    return Stream<List<int>>.fromIterable(
      [_StubHttpOverrides._png1x1],
    ).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _StubHttpOverrides();

  testWidgets('renders learning workspace', (tester) async {
    final storage = StorageService();
    final contentApi = ContentApiService();
    final aiService = AiService();
    final dataSyncService = DataSyncService(storage);
    final analyticsService = AnalyticsService(storage);
    final updateService = UpdateService();

    await tester.pumpWidget(
      MianshiZhilianApp(
        storage: storage,
        dataSyncService: dataSyncService,
        contentApi: contentApi,
        aiService: aiService,
        analyticsService: analyticsService,
        updateService: updateService,
        initialLanguage: 'zh',
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(MianshiZhilianApp), findsOneWidget);
  });
}
