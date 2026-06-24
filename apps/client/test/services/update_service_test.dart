import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mianshi_zhilian/services/app_version_service.dart';
import 'package:mianshi_zhilian/services/endpoint_fallback_client.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/route_state_store.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/services/update_service.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.temporaryPath);

  final String temporaryPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
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
        urls.any(
          (u) => u.startsWith('https://mianshizhilian-app.nontracey.de5.net'),
        ),
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

  test(
    'mirror-first: update.json mirrors come before built-in mirrors',
    () {
      const update = PlatformUpdate(
        url:
            'https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.3/mianshi-zhilian-v0.1.3-android.apk',
        mirrors: ['https://mirror.example.test/android.apk'],
        sha256: 'abc',
        size: 42,
      );
      final service = UpdateService(
        downloadSourceMode: DownloadSourceMode.mirrorFirst,
      );

      final urls = service.buildDownloadUrlsForTest(update);

      expect(urls.first, 'https://mirror.example.test/android.apk');
      expect(urls[1], 'https://ghfast.top/${update.url}');
      expect(urls.last, update.url);
    },
  );

  test(
    'mirror-first: built-in mirrors used when no update.json mirrors',
    () {
      const update = PlatformUpdate(
        url:
            'https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.3/mianshi-zhilian-v0.1.3-android.apk',
        sha256: 'abc',
        size: 42,
      );
      final service = UpdateService(
        downloadSourceMode: DownloadSourceMode.mirrorFirst,
      );

      final urls = service.buildDownloadUrlsForTest(update);

      expect(urls.first, 'https://ghfast.top/${update.url}');
      expect(urls.last, update.url);
    },
  );

  test('formatSpeed switches from KB/s to MB/s', () {
    expect(UpdateService.formatSpeed(0), '0 KB/s');
    expect(UpdateService.formatSpeed(8 * 1024), '8.0 KB/s');
    expect(UpdateService.formatSpeed(2.5 * 1024 * 1024), '2.5 MB/s');
  });

  test(
    'temporary route switch keeps partial installer and resumes with Range',
    () async {
      final originalPathProvider = PathProviderPlatform.instance;
      final tempDir = await Directory.systemTemp.createTemp(
        'update_resume_test',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = List<int>.generate(64 * 1024, (index) => index % 251);
      final partialLength = 12 * 1024;
      final mirrorRanges = <String?>[];

      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
      unawaited(
        _serveUpdateBytes(
          server: server,
          bytes: bytes,
          partialLength: partialLength,
          mirrorRanges: mirrorRanges,
        ),
      );

      try {
        final baseUrl = 'http://${server.address.host}:${server.port}';
        final update = PlatformUpdate(
          url: '$baseUrl/installer.bin',
          sha256: sha256.convert(bytes).toString(),
          size: bytes.length,
        );

        final firstToken = DownloadCancelToken();
        var cancelledAfterPartial = false;
        final githubService = UpdateService(
          downloadSourceMode: DownloadSourceMode.githubOnly,
        );
        final firstResult = await githubService.downloadUpdate(
          platformUpdate: update,
          version: '9.9.9',
          cancelToken: firstToken,
          onProgress: (progress) {
            if (!cancelledAfterPartial &&
                progress.received >= partialLength &&
                progress.received < bytes.length) {
              cancelledAfterPartial = true;
              firstToken.cancel(keepPartialDownload: true);
            }
          },
        );

        expect(firstResult.$2, DownloadResult.cancelled);
        final partialFiles = (await tempDir.list().toList())
            .whereType<File>()
            .toList();
        expect(partialFiles, hasLength(1));
        expect(await partialFiles.single.length(), partialLength);

        final mirrorService = UpdateService(
          customMirrorPrefix: '$baseUrl/mirror',
          downloadSourceMode: DownloadSourceMode.mirrorFirst,
        );
        final resumedResult = await mirrorService.downloadUpdate(
          platformUpdate: update,
          version: '9.9.9',
        );

        expect(resumedResult.$2, DownloadResult.success);
        expect(mirrorRanges, contains('bytes=$partialLength-'));
        expect(await File(resumedResult.$1!).readAsBytes(), bytes);
      } finally {
        PathProviderPlatform.instance = originalPathProvider;
        await server.close(force: true);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
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

Future<void> _serveUpdateBytes({
  required HttpServer server,
  required List<int> bytes,
  required int partialLength,
  required List<String?> mirrorRanges,
}) async {
  await for (final request in server) {
    try {
      if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        continue;
      }

      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        continue;
      }

      if (request.uri.path.startsWith('/mirror/')) {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        mirrorRanges.add(range);
        final start = _rangeStart(range) ?? 0;
        if (start > 0) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${bytes.length - 1}/${bytes.length}',
          );
        } else {
          request.response.statusCode = HttpStatus.ok;
        }
        request.response.headers.contentLength = bytes.length - start;
        request.response.add(bytes.sublist(start));
        await request.response.close();
        continue;
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentLength = bytes.length;
      request.response.add(bytes.sublist(0, partialLength));
      await request.response.flush();
      await Future<void>.delayed(const Duration(seconds: 2));
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}

int? _rangeStart(String? rangeHeader) {
  if (rangeHeader == null) return null;
  final match = RegExp(r'^bytes=(\d+)-$').firstMatch(rangeHeader);
  return int.tryParse(match?.group(1) ?? '');
}
