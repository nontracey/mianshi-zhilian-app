import 'storage_service.dart';
import 'route_resolver.dart';

class RouteStateStore {
  RouteStateStore(this._storage);

  final StorageService _storage;

  static const _stateKey = '_routeState';
  static const _modeKey = '_routeMode';
  static const _downloadSourceModeKey = '_downloadSourceMode';

  Future<RouteMode> loadMode(RouteService service) async {
    final data = await _storage.loadJsonObject(_modeKey);
    final raw = data?[service.name] as String?;
    return RouteMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => RouteMode.auto,
    );
  }

  Future<void> saveMode(RouteService service, RouteMode mode) async {
    final data = await _storage.loadJsonObject(_modeKey) ?? {};
    data[service.name] = mode.name;
    await _storage.saveJsonObject(_modeKey, data);
  }

  Future<RouteLane?> loadActiveLane(RouteService service) async {
    final data = await _storage.loadJsonObject(_stateKey);
    final item = data?[service.name];
    if (item is! Map) return null;

    final expiresAtRaw = item['expiresAt'] as String?;
    final expiresAt = expiresAtRaw == null
        ? null
        : DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null || expiresAt.isBefore(DateTime.now())) return null;

    final active = item['active'] as String?;
    return RouteLane.values.firstWhere(
      (lane) => lane.name == active,
      orElse: () => RouteLane.primary,
    );
  }

  Future<void> rememberActiveLane(
    RouteService service,
    RouteLane lane, {
    Duration ttl = const Duration(minutes: 30),
  }) async {
    final data = await _storage.loadJsonObject(_stateKey) ?? {};
    data[service.name] = {
      'active': lane.name,
      'expiresAt': DateTime.now().add(ttl).toIso8601String(),
    };
    await _storage.saveJsonObject(_stateKey, data);
  }

  Future<DownloadSourceMode> loadDownloadSourceMode() async {
    final data = await _storage.loadJsonObject(_downloadSourceModeKey);
    final raw = data?['mode'] as String?;
    return DownloadSourceMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => DownloadSourceMode.auto,
    );
  }

  Future<void> saveDownloadSourceMode(DownloadSourceMode mode) async {
    await _storage.saveJsonObject(_downloadSourceModeKey, {'mode': mode.name});
  }
}
