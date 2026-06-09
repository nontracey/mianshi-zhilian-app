import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mianshi_zhilian/services/app_version_service.dart';
import 'package:mianshi_zhilian/services/endpoint_fallback_client.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueuedClient extends http.BaseClient {
  _QueuedClient(this.responses);

  final List<http.Response> responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (responses.isEmpty) {
      throw http.ClientException('no response queued', request.url);
    }
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'download candidates start with GitHub URL, then custom mirror, ghfast.top, manifest mirrors',
    () {
      const update = PlatformUpdate(
        url:
            'https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.3/mianshi-zhilian-v0.1.3-android.apk',
        assetPath:
            '/releases/latest/download/mianshi-zhilian-v0.1.3-android.apk',
        mirrors: ['https://mirror.example.test/android.apk'],
        sha256: 'abc',
        size: 42,
      );
      final service = UpdateService(
        customMirrorPrefix: 'https://mirror.local',
        downloadSourceMode: DownloadSourceMode.githubFirst,
      );

      final urls = service.buildDownloadUrlsForTest(update);

      expect(urls.first, update.url);
      expect(urls, contains(update.url));
      expect(urls, contains('https://mirror.local/${update.url}'));
      expect(urls, contains('https://ghfast.top/${update.url}'));
      expect(urls, contains('https://mirror.example.test/android.apk'));
      // 不应包含 Pages CDN 域名
      expect(
        urls.any((u) => u.startsWith('https://mianshi-zhilian-app.pages.dev')),
        isFalse,
      );
      expect(
        urls.any((u) => u.startsWith('https://mianshizhilian-app.nontracey.de5.net')),
        isFalse,
      );
    },
  );

  test('URL pointing directly to any host is used as-is in the list', () {
    const update = PlatformUpdate(
      url:
          'https://mianshizhilian-app.nontracey.de5.net/releases/latest/download/mianshi-zhilian-v0.1.3-macos.dmg',
      sha256: 'abc',
      size: 42,
    );
    final service = UpdateService();

    final urls = service.buildDownloadUrlsForTest(update);

    // url 字段直接原样加入列表（不再做 Pages CDN 解析）
    expect(urls.first, update.url);
  });

  test(
    'auto mode is the default and includes every candidate before probing',
    () {
      const update = PlatformUpdate(
        url:
            'https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.3/mianshi-zhilian-v0.1.3-android.apk',
        mirrors: ['https://mirror.example.test/android.apk'],
        sha256: 'abc',
        size: 42,
      );
      final service = UpdateService(customMirrorPrefix: 'https://mirror.local');

      final urls = service.buildDownloadUrlsForTest(update);

      expect(urls.first, update.url);
      expect(urls, contains('https://mirror.local/${update.url}'));
      expect(urls, contains('https://ghfast.top/${update.url}'));
      expect(urls, contains('https://mirror.example.test/android.apk'));
    },
  );

  test('higher remote build number is treated as an update', () async {
    final client = _QueuedClient([
      http.Response('''
{
  "version": "0.1.4",
  "buildNumber": 137,
  "releaseDate": "2026-06-05",
  "minimumRequiredVersion": "0.1.0",
  "notes": [],
  "platforms": {}
}
''', 200),
    ]);
    final routeClient = EndpointFallbackClient(
      stateStore: EndpointStateStore(StorageService()),
      httpClient: client,
    );
    final service = UpdateService(routeClient: routeClient);

    final result = await service.checkForUpdate(
      const AppBuildInfo(version: '0.1.4', buildNumber: 136),
    );

    expect(result.hasUpdate, isTrue);
    expect(result.localVersion?.fullVersion, '0.1.4+136');
    expect(result.remoteFullVersion, '0.1.4+137');
  });
}
