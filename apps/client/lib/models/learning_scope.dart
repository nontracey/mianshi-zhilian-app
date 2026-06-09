/// 学习范围（study scope）—— 统一「单领域 / 全部领域 / 目标路线」的单一事实源。
///
/// 历史上「当前在学什么」分散在两处：`SettingsProvider.currentDomain`（单领域）
/// 与 `LearningShell` 本地的路线状态（多领域）。`LearningScope` 把它们收敛为一个值，
/// 由 [LearningScopeProvider] 持有并持久化。
enum ScopeKind {
  /// 全部领域：不限定领域，跨全部已加载知识点。
  allDomains,

  /// 单领域：只看 [LearningScope.domainId] 指向的领域。
  singleDomain,

  /// 路线：跟随 [LearningScope.routeId] 指向的学习路线（可能跨多个领域）。
  route,
}

class LearningScope {
  final ScopeKind kind;

  /// 仅当 [kind] == [ScopeKind.singleDomain] 时有效。
  final String? domainId;

  /// 仅当 [kind] == [ScopeKind.route] 时有效。
  final String? routeId;

  const LearningScope({required this.kind, this.domainId, this.routeId});

  const LearningScope.allDomains() : kind = ScopeKind.allDomains, domainId = null, routeId = null;

  const LearningScope.singleDomain(String domain)
      : kind = ScopeKind.singleDomain,
        domainId = domain,
        routeId = null;

  const LearningScope.route(String route)
      : kind = ScopeKind.route,
        domainId = null,
        routeId = route;

  bool get isRouteMode => kind == ScopeKind.route;
  bool get isSingleDomain => kind == ScopeKind.singleDomain;
  bool get isAllDomains => kind == ScopeKind.allDomains;

  LearningScope copyWith({ScopeKind? kind, String? domainId, String? routeId}) =>
      LearningScope(
        kind: kind ?? this.kind,
        domainId: domainId ?? this.domainId,
        routeId: routeId ?? this.routeId,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (domainId != null) 'domainId': domainId,
        if (routeId != null) 'routeId': routeId,
      };

  factory LearningScope.fromJson(Map<String, dynamic> json) {
    final kind = ScopeKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ScopeKind.allDomains,
    );
    return LearningScope(
      kind: kind,
      domainId: json['domainId'] as String?,
      routeId: json['routeId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LearningScope &&
      other.kind == kind &&
      other.domainId == domainId &&
      other.routeId == routeId;

  @override
  int get hashCode => Object.hash(kind, domainId, routeId);

  @override
  String toString() => 'LearningScope($kind, domain=$domainId, route=$routeId)';
}
