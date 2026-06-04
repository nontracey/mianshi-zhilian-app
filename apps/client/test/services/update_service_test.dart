import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/update_service.dart';

void main() {
  test('download candidates start with GitHub URL, then custom mirror, ghfast.top, manifest mirrors', () {
    const update = PlatformUpdate(
      url:
          'https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.3/mianshi-zhilian-v0.1.3-android.apk',
      assetPath: '/releases/latest/download/mianshi-zhilian-v0.1.3-android.apk',
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
    expect(urls.any((u) => u.startsWith(RouteResolver.appWebPrimary)), isFalse);
    expect(urls.any((u) => u.startsWith(RouteResolver.appWebBackup)), isFalse);
  });

  test('URL pointing directly to any host is used as-is in the list', () {
    const update = PlatformUpdate(
      url:
          '${RouteResolver.appWebBackup}/releases/latest/download/mianshi-zhilian-v0.1.3-macos.dmg',
      sha256: 'abc',
      size: 42,
    );
    final service = UpdateService();

    final urls = service.buildDownloadUrlsForTest(update);

    // url 字段直接原样加入列表（不再做 Pages CDN 解析）
    expect(urls.first, update.url);
  });

  test('auto mode is the default and includes every candidate before probing', () {
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
  });
}
