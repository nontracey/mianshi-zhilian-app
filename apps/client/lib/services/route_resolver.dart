enum RouteService { appApi, appWeb, content, studioApi, studioWeb }

enum RouteLane { primary, backup }

enum RouteMode { auto, primaryFirst, backupFirst, primaryOnly, backupOnly }

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
  static const appApiPrimary = 'https://mianshi-zhilian-api.pages.dev';
  static const appApiBackup = 'https://mianshizhilian-api.nontracey.de5.net';
  static const appWebPrimary = 'https://mianshi-zhilian-app.pages.dev';
  static const appWebBackup = 'https://mianshizhilian-app.nontracey.de5.net';
  static const contentPrimary = 'https://mianshi-zhilian-content.pages.dev';
  static const contentBackup =
      'https://mianshizhilian-content.nontracey.de5.net';
  static const studioApiPrimary =
      'https://mianshi-zhilian-studio-api.pages.dev';
  static const studioApiBackup =
      'https://mianshizhilian-studio-api.nontracey.de5.net';
  static const studioWebPrimary = 'https://mianshi-zhilian-studio.pages.dev';
  static const studioWebBackup =
      'https://mianshizhilian-studio.nontracey.de5.net';

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
      (RouteService.appWeb, RouteLane.primary) => appWebPrimary,
      (RouteService.appWeb, RouteLane.backup) => appWebBackup,
      (RouteService.content, RouteLane.primary) => contentPrimary,
      (RouteService.content, RouteLane.backup) => contentBackup,
      (RouteService.studioApi, RouteLane.primary) => studioApiPrimary,
      (RouteService.studioApi, RouteLane.backup) => studioApiBackup,
      (RouteService.studioWeb, RouteLane.primary) => studioWebPrimary,
      (RouteService.studioWeb, RouteLane.backup) => studioWebBackup,
    };
    return RouteEndpoint(service: service, lane: lane, baseUrl: baseUrl);
  }

  static RouteLane? laneFromUrl(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host == null) return null;
    return host.endsWith('nontracey.de5.net')
        ? RouteLane.backup
        : RouteLane.primary;
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    return path.startsWith('/') ? path : '/$path';
  }

  static RouteLane? _laneFromEntranceHost() {
    final host = Uri.base.host;
    if (host.endsWith('nontracey.de5.net')) return RouteLane.backup;
    if (host.endsWith('pages.dev')) return RouteLane.primary;
    return null;
  }
}
