import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/app_version_service.dart';

void main() {
  test('normalizes Android split APK ABI versionCode offset', () {
    final buildNumber = AppVersionService.normalizePackageBuildNumber(
      packageVersion: '0.1.4',
      packageBuildNumber: 2138,
      compileTime: const AppBuildInfo(version: '0.1.4', buildNumber: 138),
      isAndroid: true,
    );

    expect(buildNumber, 138);
  });

  test('keeps non-Android package build number unchanged', () {
    final buildNumber = AppVersionService.normalizePackageBuildNumber(
      packageVersion: '0.1.4',
      packageBuildNumber: 2138,
      compileTime: const AppBuildInfo(version: '0.1.4', buildNumber: 138),
      isAndroid: false,
    );

    expect(buildNumber, 2138);
  });

  test(
    'keeps Android build number when version does not match compile time',
    () {
      final buildNumber = AppVersionService.normalizePackageBuildNumber(
        packageVersion: '0.1.5',
        packageBuildNumber: 2138,
        compileTime: const AppBuildInfo(version: '0.1.4', buildNumber: 138),
        isAndroid: true,
      );

      expect(buildNumber, 2138);
    },
  );
}
