import 'package:flutter/foundation.dart';
import '../models/learning_route.dart';
import 'storage_service.dart';

class RouteService {
  final StorageService _storage;

  RouteService(this._storage);

  /// 获取所有路线（默认 + 自定义）
  Future<List<LearningRoute>> getAllRoutes() async {
    final customRoutes = await _loadCustomRoutes();
    return [...defaultRoutes, ...customRoutes];
  }

  /// 获取自定义路线
  Future<List<LearningRoute>> _loadCustomRoutes() async {
    try {
      final data = await _storage.load('custom_routes');
      if (data != null && data is List) {
        return data.map((e) => LearningRoute.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Failed to load custom routes: $e');
    }
    return [];
  }

  /// 保存自定义路线
  Future<void> saveCustomRoutes(List<LearningRoute> routes) async {
    await _storage.save('custom_routes', routes.map((r) => r.toJson()).toList());
  }

  /// 添加自定义路线
  Future<void> addCustomRoute(LearningRoute route) async {
    final routes = await _loadCustomRoutes();
    routes.add(route);
    await saveCustomRoutes(routes);
  }

  /// 删除自定义路线
  Future<void> deleteCustomRoute(String routeId) async {
    final routes = await _loadCustomRoutes();
    routes.removeWhere((r) => r.id == routeId);
    await saveCustomRoutes(routes);
  }

  /// 获取上次使用的路线 ID
  Future<String?> getLastUsedRouteId() async {
    try {
      final data = await _storage.load('last_used_route');
      return data as String?;
    } catch (e) {
      return null;
    }
  }

  /// 保存上次使用的路线 ID
  Future<void> saveLastUsedRouteId(String routeId) async {
    await _storage.save('last_used_route', routeId);
  }
}
