import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_version_service.dart';
import 'endpoint_fallback_client.dart';
import 'route_resolver.dart';
import 'route_state_store.dart';
import 'storage_service.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseDate;
  final String minimumRequiredVersion;
  final List<String> notes;
  final Map<String, PlatformUpdate> platforms;

  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseDate,
    required this.minimumRequiredVersion,
    required this.notes,
    required this.platforms,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final platforms = <String, PlatformUpdate>{};
    final platformsJson = json['platforms'] as Map<String, dynamic>? ?? {};
    for (final entry in platformsJson.entries) {
      platforms[entry.key] = PlatformUpdate.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return UpdateInfo(
      version: json['version'] as String? ?? '',
      buildNumber: json['buildNumber'] as int? ?? 0,
      releaseDate: json['releaseDate'] as String? ?? '',
      minimumRequiredVersion: json['minimumRequiredVersion'] as String? ?? '',
      notes: (json['notes'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      platforms: platforms,
    );
  }
}

class PlatformUpdate {
  final String url;
  final String? assetPath;
  final List<String> mirrors;
  final String sha256;
  final int size;

  const PlatformUpdate({
    required this.url,
    this.assetPath,
    this.mirrors = const [],
    required this.sha256,
    required this.size,
  });

  factory PlatformUpdate.fromJson(Map<String, dynamic> json) {
    return PlatformUpdate(
      url: json['url'] as String? ?? '',
      assetPath: json['assetPath'] as String?,
      mirrors: (json['mirrors'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      sha256: json['sha256'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

class CheckUpdateResult {
  final UpdateInfo? updateInfo;
  final bool isError;
  final AppBuildInfo? localVersion;
  final String? remoteVersion;
  final int? remoteBuildNumber;

  const CheckUpdateResult._(
    this.updateInfo,
    this.isError, {
    this.localVersion,
    this.remoteVersion,
    this.remoteBuildNumber,
  });
  CheckUpdateResult.hasUpdate(UpdateInfo info, {AppBuildInfo? localVersion})
    : this._(
        info,
        false,
        localVersion: localVersion,
        remoteVersion: info.version,
        remoteBuildNumber: info.buildNumber,
      );
  const CheckUpdateResult.noUpdate({
    AppBuildInfo? localVersion,
    String? remoteVersion,
    int? remoteBuildNumber,
  }) : this._(
         null,
         false,
         localVersion: localVersion,
         remoteVersion: remoteVersion,
         remoteBuildNumber: remoteBuildNumber,
       );
  const CheckUpdateResult.error({AppBuildInfo? localVersion})
    : this._(null, true, localVersion: localVersion);

  bool get hasUpdate => updateInfo != null;

  String? get remoteFullVersion {
    final version = remoteVersion;
    final buildNumber = remoteBuildNumber;
    if (version == null || version.isEmpty) return null;
    if (buildNumber == null || buildNumber <= 0) return version;
    return '$version+$buildNumber';
  }
}

enum DownloadResult { success, networkError, verificationFailed, cancelled }

class DownloadAttempt {
  final String url;
  final String sourceLabel;
  final bool reached;
  final int? statusCode;
  final String? errorSummary;

  const DownloadAttempt({
    required this.url,
    required this.sourceLabel,
    required this.reached,
    this.statusCode,
    this.errorSummary,
  });

  String get failureReason {
    if (reached) {
      return statusCode == null ? 'Verification failed' : 'HTTP $statusCode';
    }
    return errorSummary ?? 'Unable to connect';
  }
}

typedef DownloadProgressCallback =
    void Function(int received, int total, String sourceLabel);

class DownloadCancelToken {
  bool _isCancelled = false;
  http.Client? _client;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
    _client?.close();
  }
}

class UpdateService {
  UpdateService({
    this.updateManifestUrl = '',
    this.customMirrorPrefix,
    this.downloadSourceMode = DownloadSourceMode.auto,
    EndpointFallbackClient? routeClient,
  }) : _routeClient =
           routeClient ??
           EndpointFallbackClient(
             stateStore: RouteStateStore(StorageService()),
           );

  final String updateManifestUrl;
  final String? customMirrorPrefix;
  final DownloadSourceMode downloadSourceMode;
  final EndpointFallbackClient _routeClient;
  final List<DownloadAttempt> _lastAttempts = [];

  static const defaultMirrorPrefix = 'https://ghfast.top';

  List<DownloadAttempt> get lastAttempts => List.unmodifiable(_lastAttempts);

  Future<CheckUpdateResult> checkForUpdate(AppBuildInfo currentVersion) async {
    try {
      final response = await _routeClient.request(
        RouteService.appApi,
        'GET',
        '/update.json',
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        return CheckUpdateResult.error(localVersion: currentVersion);
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final remoteVersion = data['version'] as String? ?? '';
      final remoteBuildNumber = data['buildNumber'] as int? ?? 0;
      if (_isNewerVersion(
        remoteVersion: remoteVersion,
        remoteBuildNumber: remoteBuildNumber,
        localVersion: currentVersion.version,
        localBuildNumber: currentVersion.buildNumber,
      )) {
        return CheckUpdateResult.hasUpdate(
          UpdateInfo.fromJson(data),
          localVersion: currentVersion,
        );
      }
      return CheckUpdateResult.noUpdate(
        localVersion: currentVersion,
        remoteVersion: remoteVersion,
        remoteBuildNumber: remoteBuildNumber,
      );
    } catch (_) {
      return CheckUpdateResult.error(localVersion: currentVersion);
    }
  }

  bool isRequiredUpdate(UpdateInfo updateInfo, AppBuildInfo currentVersion) {
    final minimumVersion = updateInfo.minimumRequiredVersion;
    if (minimumVersion.isEmpty) return false;
    return _compareVersion(minimumVersion, currentVersion.version) > 0;
  }

  PlatformUpdate? getPlatformUpdate(UpdateInfo updateInfo) => null;

  List<String> buildDownloadUrlsForTest(PlatformUpdate platformUpdate) {
    final githubUrl = platformUpdate.url.trim();
    final mirrorPrefix = (customMirrorPrefix ?? '').replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final urls = <String>[];
    if (githubUrl.isNotEmpty) urls.add(githubUrl);
    if (mirrorPrefix.isNotEmpty) urls.add('$mirrorPrefix/$githubUrl');
    if (githubUrl.isNotEmpty) urls.add('$defaultMirrorPrefix/$githubUrl');
    for (final mirror in platformUpdate.mirrors) {
      if (mirror.trim().isNotEmpty && !urls.contains(mirror)) {
        urls.add(mirror);
      }
    }
    return switch (downloadSourceMode) {
      DownloadSourceMode.githubOnly => githubUrl.isEmpty ? [] : [githubUrl],
      DownloadSourceMode.mirrorFirst =>
        mirrorPrefix.isEmpty ? urls : [urls[1], urls[0], ...urls.skip(2)],
      _ => urls,
    };
  }

  Future<(String?, DownloadResult)> downloadUpdate({
    required PlatformUpdate platformUpdate,
    required String version,
    DownloadProgressCallback? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    return (null, DownloadResult.networkError);
  }

  Future<bool> openInstaller(String filePath) async => false;

  Future<bool> verifySha256(String filePath, String expectedSha256) async =>
      false;

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  bool _isNewerVersion({
    required String remoteVersion,
    required int remoteBuildNumber,
    required String localVersion,
    required int localBuildNumber,
  }) {
    final versionCompare = _compareVersion(remoteVersion, localVersion);
    if (versionCompare > 0) return true;
    if (versionCompare < 0) return false;
    return remoteBuildNumber > localBuildNumber;
  }

  int _compareVersion(String remote, String local) {
    final remoteParts = remote
        .replaceAll('v', '')
        .split('.')
        .map(int.tryParse)
        .toList();
    final localParts = local
        .replaceAll('v', '')
        .split('.')
        .map(int.tryParse)
        .toList();
    for (var i = 0; i < 3; i++) {
      final r = i < remoteParts.length ? (remoteParts[i] ?? 0) : 0;
      final l = i < localParts.length ? (localParts[i] ?? 0) : 0;
      if (r > l) return 1;
      if (r < l) return -1;
    }
    return 0;
  }
}
