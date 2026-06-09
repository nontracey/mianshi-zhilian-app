import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/learning_route.dart';
import '../models/learning_scope.dart';
import '../models/topic.dart';
import '../providers/content_provider.dart';
import '../services/storage_service.dart';

/// 学习范围的持久化存储辅助，封装所有 key 管理与旧键迁移。
class _LearningScopeStore {
  static const String _scopeKey = 'learning_scope';

  // 被迁移的旧键（只读，迁移后写入新键并删除旧键）
  static const String _legacySelectedRouteId = 'selected_route_id';
  static const String _legacyRouteModeDisabled = 'route_mode_disabled';

  final StorageService _storage;
  _LearningScopeStore(this._storage);

  Future<LearningScope?> loadScope() async {
    final data = await _storage.load(_scopeKey);
    if (data == null) return null;
    try {
      final map = data is String ? jsonDecode(data) as Map<String, dynamic> : data as Map<String, dynamic>;
      return LearningScope.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveScope(LearningScope scope) async {
    await _storage.save(_scopeKey, scope.toJson());
  }

  Future<List<LearningRoute>> loadCustomRoutes() async {
    final raw = await _storage.loadCustomRoutes();
    return raw.map((e) => LearningRoute.fromJson(e)).toList();
  }

  Future<void> saveCustomRoutes(List<LearningRoute> routes) async {
    await _storage.saveCustomRoutes(routes.map((r) => r.toJson()).toList());
  }

  /// 从旧键迁移到新 scope 键（幂等）。
  /// 返回迁移出来的 scope（若旧键存在），否则返回 null。
  Future<LearningScope?> migrateFromLegacy(String? fallbackDomainId) async {
    // 已有新键 → 不需要迁移
    final existing = await _storage.load(_scopeKey);
    if (existing != null) return null;

    final selectedRouteId = await _storage.load(_legacySelectedRouteId) as String?;
    final routeModeDisabled = await _storage.load(_legacyRouteModeDisabled) as bool?;

    LearningScope migrated;

    if (selectedRouteId != null && routeModeDisabled != true) {
      // 旧状态：路线模式启用
      migrated = LearningScope.route(selectedRouteId);
    } else if (fallbackDomainId != null && fallbackDomainId.isNotEmpty) {
      // 旧状态：单领域
      migrated = LearningScope.singleDomain(fallbackDomainId);
    } else {
      migrated = const LearningScope.allDomains();
    }

    await saveScope(migrated);
    return migrated;
  }
}

/// 学习范围单一事实源。
///
/// 取代分散在 `LearningShell` 本地字段（`_routeTopicIds`、`_routeDomainIds` 等）
/// 以及 `SettingsProvider.settings.currentDomain` 这两套并行状态。
///
/// **用法**：
/// ```dart
/// final scope = context.watch<LearningScopeProvider>();
/// final topics = scope.resolveScopedTopics(context.read<ContentProvider>());
/// ```
class LearningScopeProvider extends ChangeNotifier {
  final StorageService _storage;
  late final _LearningScopeStore _store;

  LearningScope _scope = const LearningScope.allDomains();
  List<LearningRoute> _customRoutes = [];
  bool _loaded = false;

  LearningScopeProvider(this._storage) {
    _store = _LearningScopeStore(_storage);
  }

  // ── 只读派生 ────────────────────────────────────────────────────────

  LearningScope get scope => _scope;
  List<LearningRoute> get customRoutes => List.unmodifiable(_customRoutes);
  bool get loaded => _loaded;

  bool get isRouteMode => _scope.isRouteMode;
  bool get isSingleDomain => _scope.isSingleDomain;
  bool get isAllDomains => _scope.isAllDomains;

  /// 活动路线对象（路线模式下返回路线，否则 null）。
  LearningRoute? get activeRoute {
    if (!_scope.isRouteMode || _scope.routeId == null) return null;
    try {
      return _customRoutes.firstWhere((r) => r.id == _scope.routeId);
    } catch (_) {
      return null;
    }
  }

  /// 当前范围涉及的领域 ID 列表。
  List<String> get scopeDomainIds {
    switch (_scope.kind) {
      case ScopeKind.singleDomain:
        return _scope.domainId != null ? [_scope.domainId!] : [];
      case ScopeKind.route:
        return activeRoute?.domainIds ?? [];
      case ScopeKind.allDomains:
        return [];
    }
  }

  /// 当前范围的阶段列表（仅路线模式）。
  List<RoutePhase>? get scopePhases => activeRoute?.phases;

  /// 路线内全部 topicId（去重）；仅路线模式下有值。
  List<String> get scopeTopicIds => activeRoute?.allTopicIds ?? [];

  /// 是否跨多个领域（路线模式且涵盖 >1 个领域）。
  bool get isCrossDomain => _scope.isRouteMode && scopeDomainIds.length > 1;

  /// 用于 UI 展示的范围名称。
  String displayName(Map<String, String> domainTitles) {
    switch (_scope.kind) {
      case ScopeKind.allDomains:
        return '全部领域';
      case ScopeKind.singleDomain:
        final id = _scope.domainId;
        if (id == null) return '单领域';
        return domainTitles[id] ?? id;
      case ScopeKind.route:
        return activeRoute?.name ?? '学习路线';
    }
  }

  // ── 核心：统一 topic 解析 ──────────────────────────────────────────

  /// 根据当前范围解析出 topic 列表（「该练哪些 topic」的唯一入口）。
  ///
  /// 实现以 mastery_page 的 findTopic 路径为蓝本：路线模式下逐 topicId
  /// 通过 [ContentProvider.findTopic] 查找，保证跨域 topic 全部命中。
  /// 单领域模式退回 [ContentProvider.getTopicsByDomain]。
  /// 全部领域模式返回所有已加载 topic（[ContentProvider.topics]）。
  ///
  /// 路线模式下若解析结果为空（领域 topic 尚未加载），返回当前已加载的范围
  /// 领域 topic 作为降级，避免空页面——调用方通常同步调一次
  /// [ensureScopeLoaded] 再调本方法。
  List<Topic> resolveScopedTopics(ContentProvider content) {
    switch (_scope.kind) {
      case ScopeKind.allDomains:
        return content.topics.values.toList();

      case ScopeKind.singleDomain:
        final domainId = _scope.domainId;
        if (domainId == null) return content.topics.values.toList();
        return content.getTopicsByDomain(domainId);

      case ScopeKind.route:
        final topicIds = scopeTopicIds;
        if (topicIds.isEmpty) {
          // 路线无 phases（官方路线），退回领域全量
          final domains = scopeDomainIds;
          if (domains.isEmpty) return content.topics.values.toList();
          return domains.expand((d) => content.getTopicsByDomain(d)).toList();
        }
        // 精确查找每个 topicId（跨域安全）
        final resolved = <Topic>[];
        for (final id in topicIds) {
          final t = content.findTopic(id);
          if (t != null) resolved.add(t);
        }
        if (resolved.isNotEmpty) return resolved;
        // 降级：topic 未加载时返回范围领域全量
        return scopeDomainIds.expand((d) => content.getTopicsByDomain(d)).toList();
    }
  }

  /// 确保当前范围需要的领域 topic 已加载（并行）。
  Future<void> ensureScopeLoaded(ContentProvider content) async {
    final domains = scopeDomainIds;
    if (domains.isEmpty) return;
    await Future.wait(domains.map((d) => content.loadDomainTopics(d)));
  }

  // ── 状态变更 ──────────────────────────────────────────────────────

  Future<void> setScope(LearningScope scope) async {
    _scope = scope;
    await _store.saveScope(scope);
    notifyListeners();
  }

  Future<void> setSingleDomain(String domainId) =>
      setScope(LearningScope.singleDomain(domainId));

  Future<void> setAllDomains() => setScope(const LearningScope.allDomains());

  Future<void> setRoute(String routeId) =>
      setScope(LearningScope.route(routeId));

  /// 添加或更新路线，并可选择立即切换到该路线。
  Future<void> upsertRoute(LearningRoute route, {bool activate = false}) async {
    final idx = _customRoutes.indexWhere((r) => r.id == route.id);
    if (idx >= 0) {
      _customRoutes[idx] = route;
    } else {
      _customRoutes = [..._customRoutes, route];
    }
    await _store.saveCustomRoutes(_customRoutes);
    if (activate) {
      await setRoute(route.id);
    } else {
      notifyListeners();
    }
  }

  /// 删除路线；若当前正在使用该路线则自动退回全部领域。
  Future<void> deleteRoute(String routeId) async {
    _customRoutes = _customRoutes.where((r) => r.id != routeId).toList();
    await _store.saveCustomRoutes(_customRoutes);
    if (_scope.isRouteMode && _scope.routeId == routeId) {
      await setScope(const LearningScope.allDomains());
    } else {
      notifyListeners();
    }
  }

  // ── 初始化与迁移 ──────────────────────────────────────────────────

  /// 加载持久化状态（含旧键迁移）。在 main.dart 注册时通过 `..load()` 调用。
  ///
  /// [legacyDomainId]：来自 `AppSettings.currentDomain` 的旧值，
  /// 仅在没有新键也没有旧路线键时作为单领域范围使用。
  Future<LearningScopeProvider> load({String? legacyDomainId}) async {
    _customRoutes = await _store.loadCustomRoutes();

    // 尝试加载新键
    final saved = await _store.loadScope();
    if (saved != null) {
      // 若路线模式但路线已被删除，退回全部领域
      if (saved.isRouteMode &&
          saved.routeId != null &&
          !_customRoutes.any((r) => r.id == saved.routeId)) {
        _scope = const LearningScope.allDomains();
        await _store.saveScope(_scope);
      } else {
        _scope = saved;
      }
    } else {
      // 没有新键 → 尝试从旧键迁移
      final migrated = await _store.migrateFromLegacy(legacyDomainId);
      if (migrated != null) {
        // 同样校验路线合法性
        if (migrated.isRouteMode &&
            migrated.routeId != null &&
            !_customRoutes.any((r) => r.id == migrated.routeId)) {
          _scope = legacyDomainId != null
              ? LearningScope.singleDomain(legacyDomainId)
              : const LearningScope.allDomains();
          await _store.saveScope(_scope);
        } else {
          _scope = migrated;
        }
      } else {
        _scope = legacyDomainId != null
            ? LearningScope.singleDomain(legacyDomainId)
            : const LearningScope.allDomains();
      }
    }

    _loaded = true;
    notifyListeners();
    return this;
  }

  /// 外部数据导入后重新加载（对应 `dataSyncService.onDataImported`）。
  Future<void> reload({String? legacyDomainId}) async {
    _loaded = false;
    await load(legacyDomainId: legacyDomainId);
  }
}
