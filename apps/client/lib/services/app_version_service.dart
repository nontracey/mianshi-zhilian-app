import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:mianshi_zhilian/generated/app_version.g.dart';

class AppBuildInfo {
  final String version;
  final int buildNumber;

  const AppBuildInfo({required this.version, required this.buildNumber});

  String get fullVersion => '$version+$buildNumber';
  String get displayVersion => version;

  static const compileTime = AppBuildInfo(
    version: String.fromEnvironment(
      'APP_VERSION',
      defaultValue: generatedAppVersion,
    ),
    buildNumber: int.fromEnvironment(
      'APP_BUILD_NUMBER',
      defaultValue: generatedBuildNumber,
    ),
  );
}

class AppVersionService {
  const AppVersionService();

  Future<AppBuildInfo> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final buildNumber = int.tryParse(info.buildNumber.trim());
      if (version.isNotEmpty && buildNumber != null) {
        return AppBuildInfo(
          version: version,
          buildNumber: normalizePackageBuildNumber(
            packageVersion: version,
            packageBuildNumber: buildNumber,
            compileTime: AppBuildInfo.compileTime,
            isAndroid:
                !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
          ),
        );
      }
      if (version.isNotEmpty) {
        return AppBuildInfo(
          version: version,
          buildNumber: AppBuildInfo.compileTime.buildNumber,
        );
      }
    } catch (_) {
      // Package metadata is unavailable in some test/web bootstrap paths.
    }

    return AppBuildInfo.compileTime;
  }

  @visibleForTesting
  static int normalizePackageBuildNumber({
    required String packageVersion,
    required int packageBuildNumber,
    required AppBuildInfo compileTime,
    required bool isAndroid,
  }) {
    if (!isAndroid || packageVersion != compileTime.version) {
      return packageBuildNumber;
    }

    final offset = packageBuildNumber - compileTime.buildNumber;
    if (offset >= 1000 && offset % 1000 == 0) {
      return compileTime.buildNumber;
    }

    return packageBuildNumber;
  }
}
