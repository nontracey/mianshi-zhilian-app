enum RouteService { appApi, content }

enum RouteLane { primary, backup }

enum RouteMode { auto, primaryFirst, backupFirst, primaryOnly, backupOnly }

/// 下载源模式
///
/// 控制更新包下载时各来源的优先级顺序。
enum DownloadSourceMode {
  /// 并发探测下载源，优先使用响应最快的可达来源（默认）
  auto,

  /// GitHub 官方 → 用户自定义镜像 → ghfast.top → manifest 中的其他镜像
  githubFirst,

  /// 用户自定义镜像 → GitHub 官方 → ghfast.top → 其他镜像
  mirrorFirst,

  /// 仅使用官方 GitHub 下载
  githubOnly,
}

class RouteEndpoint {
  const RouteEndpoint({
    required this.service,
    required this.lane,
    required this.baseUrl,
  });

  final RouteService service;
  final RouteLane lane;
  final String baseUrl;
}

class RouteCandidate {
  const RouteCandidate({required this.endpoint, required this.url});

  final RouteEndpoint endpoint;
  final Uri url;
}

class RouteResolver {
  static const appApiPrimary = 'https://mianshizhilian-api.nontracey.de5.net';
  static const appApiBackup = 'https://mianshi-zhilian-api.pages.dev';
  static const contentPrimary = 'https://mianshizhilian-content.nontracey.de5.net';
  static const contentBackup = 'https://mianshi-zhilian-content.pages.dev';

  const RouteResolver();

  List<RouteCandidate> resolveCandidates(
    RouteService service,
    String path, {
    RouteMode mode = RouteMode.auto,
    RouteLane? activeLane,
  }) {
    final endpoints = _orderedEndpoints(
      service,
      mode: mode,
      activeLane: activeLane,
    );
    return endpoints
        .map(
          (endpoint) => RouteCandidate(
            endpoint: endpoint,
            url: Uri.parse('${endpoint.baseUrl}${_normalizePath(path)}'),
          ),
        )
        .toList();
  }

  List<RouteEndpoint> _orderedEndpoints(
    RouteService service, {
    required RouteMode mode,
    RouteLane? activeLane,
  }) {
    final primary = _endpoint(service, RouteLane.primary);
    final backup = _endpoint(service, RouteLane.backup);

    switch (mode) {
      case RouteMode.primaryOnly:
        return [primary];
      case RouteMode.backupOnly:
        return [backup];
      case RouteMode.primaryFirst:
        return [primary, backup];
      case RouteMode.backupFirst:
        return [backup, primary];
      case RouteMode.auto:
        final preferred = activeLane ?? _laneFromEntranceHost();
        return preferred == RouteLane.backup
            ? [backup, primary]
            : [primary, backup];
    }
  }

  RouteEndpoint _endpoint(RouteService service, RouteLane lane) {
    final baseUrl = switch ((service, lane)) {
      (RouteService.appApi, RouteLane.primary) => appApiPrimary,
      (RouteService.appApi, RouteLane.backup) => appApiBackup,
      (RouteService.content, RouteLane.primary) => contentPrimary,
      (RouteService.content, RouteLane.backup) => contentBackup,
    };
    return RouteEndpoint(service: service, lane: lane, baseUrl: baseUrl);
  }

  static RouteLane? laneFromUrl(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host == null) return null;
    if (host.endsWith('nontracey.de5.net')) return RouteLane.primary;
    if (host.endsWith('pages.dev')) return RouteLane.backup;
    return null;
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    return path.startsWith('/') ? path : '/$path';
  }

  static RouteLane? _laneFromEntranceHost() {
    final host = Uri.base.host;
    if (host.endsWith('nontracey.de5.net')) return RouteLane.primary;
    if (host.endsWith('pages.dev')) return RouteLane.backup;
    return null;
  }
}
