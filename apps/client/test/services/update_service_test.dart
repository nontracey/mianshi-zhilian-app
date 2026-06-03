import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';
import 'package:mianshi_zhilian/services/update_service.dart';

void main() {
  test('download candidates start with official app web primary and backup', () {
    const update = PlatformUpdate(
      url:
          'https://github.com/nontracey/mianshi-zhilian-app/releases/download/v0.1.3/mianshi-zhilian-v0.1.3-android.apk',
      assetPath: '/releases/latest/download/mianshi-zhilian-v0.1.3-android.apk',
      mirrors: ['https://mirror.example.test/android.apk'],
      sha256: 'abc',
      size: 42,
    );
    final service = UpdateService(customMirrorPrefix: 'https://mirror.local');

    final urls = service.buildDownloadUrlsForTest(update);

    expect(urls.take(2), [
      '${RouteResolver.appWebPrimary}/releases/latest/download/mianshi-zhilian-v0.1.3-android.apk',
      '${RouteResolver.appWebBackup}/releases/latest/download/mianshi-zhilian-v0.1.3-android.apk',
    ]);
    expect(urls, contains(update.url));
    expect(urls, contains('https://mirror.local/${update.url}'));
    expect(urls, contains('https://ghproxy.com/${update.url}'));
    expect(urls, contains('https://mirror.example.test/android.apk'));
  });

  test('app web URLs can still provide a normalized official asset path', () {
    const update = PlatformUpdate(
      url:
          '${RouteResolver.appWebBackup}/releases/latest/download/mianshi-zhilian-v0.1.3-macos.dmg',
      sha256: 'abc',
      size: 42,
    );
    final service = UpdateService();

    final urls = service.buildDownloadUrlsForTest(update);

    expect(
      urls.first,
      '${RouteResolver.appWebPrimary}/releases/latest/download/mianshi-zhilian-v0.1.3-macos.dmg',
    );
    expect(
      urls[1],
      '${RouteResolver.appWebBackup}/releases/latest/download/mianshi-zhilian-v0.1.3-macos.dmg',
    );
  });
}
