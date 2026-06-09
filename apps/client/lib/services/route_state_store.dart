import 'storage_service.dart';
import 'route_resolver.dart';

class EndpointStateStore {
  EndpointStateStore(this._storage);

  final StorageService _storage;

  static const _stateKey = '_routeState';
  static const _modeKey = '_routeMode';
  static const _downloadSourceModeKey = '_downloadSourceMode';

  Future<EndpointMode> loadMode(EndpointService service) async {
    final data = await _storage.loadJsonObject(_modeKey);
    final raw = data?[service.name] as String?;
    return EndpointMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => EndpointMode.auto,
    );
  }

  Future<void> saveMode(EndpointService service, EndpointMode mode) async {
    final data = await _storage.loadJsonObject(_modeKey) ?? {};
    data[service.name] = mode.name;
    await _storage.saveJsonObject(_modeKey, data);
  }

  Future<EndpointLane?> loadActiveLane(EndpointService service) async {
    final data = await _storage.loadJsonObject(_stateKey);
    final item = data?[service.name];
    if (item is! Map) return null;

    final expiresAtRaw = item['expiresAt'] as String?;
    final expiresAt = expiresAtRaw == null
        ? null
        : DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null || expiresAt.isBefore(DateTime.now())) return null;

    final active = item['active'] as String?;
    return EndpointLane.values.firstWhere(
      (lane) => lane.name == active,
      orElse: () => EndpointLane.primary,
    );
  }

  Future<void> rememberActiveLane(
    EndpointService service,
    EndpointLane lane, {
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
