import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/route_composer.dart';
import 'package:mianshi_zhilian/widgets/skeleton_loader.dart';
import 'package:mianshi_zhilian/widgets/scope_selector_dialog.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.onDomainChanged,
    required this.onTopicLearn,
    required this.onTopicPractice,
  });

  final ValueChanged<String> onDomainChanged;
  final ValueChanged<String> onTopicLearn;
  final ValueChanged<String> onTopicPractice;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final _storage = StorageService();
  List<String> _disabledIds = [];
  bool _routeScopeOnly = true;

  @override
  void initState() {
    super.initState();
    _loadDisabled();
  }

  Future<void> _loadDisabled() async {
    final ids = await _storage.loadDisabledDomains();
    if (mounted) setState(() => _disabledIds = ids);
  }

  List<Domain> _filterDomains(List<Domain> all) {
    return all.where((d) => !_disabledIds.contains(d.id)).toList();
  }

  bool _roadmapView = true;
  final Set<String> _collapsedPhases = {};
  String _searchQuery = '';
  final Set<int> _difficultyFilters = {};
  bool _highFrequencyOnly = false;
  bool _hasCodeOnly = false;
  bool _hasLeetcodeOnly = false;
  final Set<String> _statusFilters = {};
  final Set<String> _collapsedRoadmapSections = {};
  String _sortBy = 'order';
  bool _showFilters = false;
  bool _crossDomainAllSelected = true;

  List<Topic> _applyFilters(List<Topic> topics, ProgressProvider progress) {
    var result = topics;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where(
            (t) =>
                t.title.toLowerCase().contains(q) ||
                t.summary.toLowerCase().contains(q) ||
                t.tags.any((tag) => tag.toLowerCase().contains(q)),
          )
          .toList();
    }
    if (_difficultyFilters.isNotEmpty) {
      result = result
          .where((t) => _difficultyFilters.contains(t.difficulty))
          .toList();
    }
    if (_highFrequencyOnly) {
      result = result.where((t) => t.highFrequency).toList();
    }
    if (_hasCodeOnly) {
      result = result
          .where((t) => t.recallPrompts.any((p) => p.mode == 'code'))
          .toList();
    }
    if (_hasLeetcodeOnly) {
      result = result
          .where((t) => t.leetcodeUrl != null && t.leetcodeUrl!.isNotEmpty)
          .toList();
    }
    if (_statusFilters.isNotEmpty) {
      result = result.where((t) {
        final score = progress.getTopicProgress(t.id)?.score ?? 0;
        final status = score >= 85
            ? 'skilled'
            : score > 0
            ? 'familiar'
            : 'unfamiliar';
        return _statusFilters.contains(status);
      }).toList();
    }
    return result;
  }

  List<Topic> _sortTopics(List<Topic> topics, ProgressProvider progress) {
    final sorted = List<Topic>.from(topics);
    switch (_sortBy) {
      case 'difficulty':
        sorted.sort((a, b) => a.difficulty.compareTo(b.difficulty));
      case 'score':
        sorted.sort((a, b) {
          final scoreA = progress.getTopicProgress(a.id)?.score ?? 0;
          final scoreB = progress.getTopicProgress(b.id)?.score ?? 0;
          return scoreA.compareTo(scoreB);
        });
      case 'reviewTime':
        sorted.sort((a, b) {
          final nextA = progress.getTopicProgress(a.id)?.nextReviewAt;
          final nextB = progress.getTopicProgress(b.id)?.nextReviewAt;
          if (nextA == null && nextB == null) return 0;
          if (nextA == null) return 1;
          if (nextB == null) return -1;
          return nextA.compareTo(nextB);
        });
      default:
        sorted.sort((a, b) => a.order.compareTo(b.order));
    }
    return sorted;
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _difficultyFilters.isNotEmpty ||
      _highFrequencyOnly ||
      _hasCodeOnly ||
      _hasLeetcodeOnly ||
      _statusFilters.isNotEmpty;

  bool _isCrossDomainRouteMode(LearningScopeProvider scope) =>
      scope.isRouteMode && _routeScopeOnly && scope.isCrossDomain;

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _difficultyFilters.clear();
      _highFrequencyOnly = false;
      _hasCodeOnly = false;
      _hasLeetcodeOnly = false;
      _statusFilters.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final scope = context.watch<LearningScopeProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentDomainId = settingsProvider.settings.currentDomain;

    final allDomains = contentProvider.domains;
    final domains = _filterDomains(allDomains);
    final currentDomain = allDomains
        .where((d) => d.id == currentDomainId)
        .firstOrNull;
    final isCrossDomainRouteMode = _isCrossDomainRouteMode(scope);
    if (currentDomain == null && !isCrossDomainRouteMode) {
      return Center(child: Text(l10n.get('please_select_one_domain')));
    }

    final isRouteScoped = scope.isRouteMode && _routeScopeOnly;
    final isCrossDomain = scope.isCrossDomain;
    final routeTopicIds = Set<String>.from(scope.scopeTopicIds);

    List<Topic> domainTopics;
    if (isRouteScoped && isCrossDomain && routeTopicIds.isNotEmpty) {
      if (_crossDomainAllSelected) {
        domainTopics = routeTopicIds
            .map((id) => contentProvider.findTopic(id))
            .whereType<Topic>()
            .toList();
      } else {
        domainTopics = routeTopicIds
            .map((id) => contentProvider.findTopic(id))
            .whereType<Topic>()
            .where((t) => t.domainId == currentDomainId)
            .toList();
      }
    } else if (isRouteScoped) {
      final domainTopicsRaw = contentProvider.getTopicsByDomain(
        currentDomainId,
      );
      domainTopics = domainTopicsRaw
          .where((t) => routeTopicIds.contains(t.id))
          .toList();
    } else {
      domainTopics = contentProvider.getTopicsByDomain(currentDomainId);
    }

    final routeProgressTopics = isRouteScoped
        ? domainTopics
        : contentProvider.topics.values.toList();
    final domainProgress = isRouteScoped && isCrossDomain
        ? (
            masteryPercent: _calcMasteryPercent(domainTopics, progressProvider),
            topicCount: domainTopics.length,
          )
        : progressProvider.getDomainProgress(
            currentDomainId,
            routeProgressTopics,
          );
    final masteryPercent = domainProgress.masteryPercent;
    final totalTopics = isRouteScoped
        ? domainTopics.length
        : (currentDomain?.topicCount ?? domainTopics.length);

    final filteredTopics = _applyFilters(domainTopics, progressProvider);
    final sortedTopics = _sortTopics(filteredTopics, progressProvider);
    // 单领域路线视图仍使用领域 learningPath；只有跨领域「全部」视图需要串联 route phases。
    final useCrossDomainRoutePhases =
        isRouteScoped &&
        isCrossDomain &&
        _crossDomainAllSelected &&
        _roadmapView &&
        scope.scopePhases != null &&
        scope.scopePhases!.isNotEmpty;

    if (contentProvider.isLoadingTopics) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: List.generate(
            6,
            (_) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SkeletonTopicRow(),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCrossDomainRouteMode)
            _buildCrossDomainHeader(
              context,
              domains,
              contentProvider,
              isDark,
              masteryPercent,
              totalTopics,
              scope,
              currentDomainId,
            )
          else
            _buildCompactHeader(
              context,
              currentDomain,
              masteryPercent,
              totalTopics,
              domains,
              contentProvider,
              isDark,
              currentDomainId,
              scope,
            ),
          const SizedBox(height: 12),

          if (scope.isRouteMode) _buildRouteBanner(context, isDark, scope),
          if (scope.isRouteMode) const SizedBox(height: 12),

          if (_showFilters) ...[
            _buildFilterBar(context, isDark),
            const SizedBox(height: 12),
          ],

          Expanded(
            child: RefreshIndicator(
              onRefresh: () {
                // 跨域路线模式下刷新所有路线领域
                if (isCrossDomainRouteMode && scope.scopeDomainIds.isNotEmpty) {
                  return contentProvider.ensureTopicsLoaded(
                    scope.scopeDomainIds,
                  );
                }
                return contentProvider.loadDomainTopics(currentDomainId);
              },
              child: sortedTopics.isEmpty
                  ? _buildEmptyState(context)
                  : (useCrossDomainRoutePhases
                        ? _buildPhasedTopicList(
                            context,
                            currentDomain ??
                                domains.firstOrNull ??
                                Domain(id: '', title: '', description: ''),
                            sortedTopics,
                            progressProvider,
                            isDark,
                          )
                        : _buildTopicList(
                            context,
                            currentDomain ??
                                domains.firstOrNull ??
                                Domain(id: '', title: '', description: ''),
                            sortedTopics,
                            progressProvider,
                            isDark,
                          )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader(
    BuildContext context,
    Domain? domain,
    int masteryPercent,
    int totalTopics,
    List<Domain> domains,
    ContentProvider contentProvider,
    bool isDark,
    String currentDomainId,
    LearningScopeProvider scope,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 640;

          if (isWide) {
            return Column(
              children: [
                Row(
                  children: [
                    _buildDomainDropdown(
                      domains,
                      contentProvider,
                      scope,
                      currentDomainId,
                    ),
                    const SizedBox(width: 8),
                    ScopeSelectorChip(),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSearchField(scope)),
                    const SizedBox(width: 8),
                    _buildFilterButton(),
                    const SizedBox(width: 4),
                    _buildViewToggle(),
                  ],
                ),
                const SizedBox(height: 8),
                _buildProgressRow(totalTopics, masteryPercent, isDark),
              ],
            );
          } else {
            return Column(
              children: [
                Row(
                  children: [
                    _buildDomainDropdown(
                      domains,
                      contentProvider,
                      scope,
                      currentDomainId,
                    ),
                    const SizedBox(width: 8),
                    ScopeSelectorChip(),
                    const SizedBox(width: 8),
                    Expanded(child: _buildSearchField(scope)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildFilterButton(),
                    const SizedBox(width: 4),
                    _buildViewToggle(),
                    const SizedBox(width: 12),
                    Text(
                      l10n.getp('count_knowledge_point_2', {
                        'count': totalTopics,
                      }),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: masteryPercent / 100,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          color: Theme.of(context).colorScheme.primary,
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$masteryPercent%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildCrossDomainHeader(
    BuildContext context,
    List<Domain> domains,
    ContentProvider contentProvider,
    bool isDark,
    int masteryPercent,
    int totalTopics,
    LearningScopeProvider scope,
    String currentDomainId,
  ) {
    final routeDomains = domains
        .where((d) => scope.scopeDomainIds.contains(d.id))
        .toList();

    // 统计路线内各领域的知识点数量，展示在标签上，让筛选更直观。
    final routeTopics = scope.scopeTopicIds
        .map((id) => contentProvider.findTopic(id))
        .whereType<Topic>()
        .toList();
    final domainCounts = <String, int>{};
    for (final t in routeTopics) {
      domainCounts[t.domainId] = (domainCounts[t.domainId] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildSearchField(scope)),
              const SizedBox(width: 8),
              _buildFilterButton(),
              const SizedBox(width: 4),
              _buildViewToggle(),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDomainTab(
                  label: l10n.get('all_topics'),
                  selected: _crossDomainAllSelected,
                  count: routeTopics.length,
                  onTap: () => setState(() => _crossDomainAllSelected = true),
                  isDark: isDark,
                  isAll: true,
                ),
                const SizedBox(width: 6),
                ...routeDomains.map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildDomainTab(
                      label: d.title,
                      selected:
                          !_crossDomainAllSelected && currentDomainId == d.id,
                      count: domainCounts[d.id] ?? 0,
                      onTap: () {
                        // 再次点击已选领域 → 回到「全部」，让筛选可顺手切回全貌。
                        final backToAll =
                            !_crossDomainAllSelected && currentDomainId == d.id;
                        setState(() => _crossDomainAllSelected = backToAll);
                        if (!backToAll) {
                          widget.onDomainChanged(d.id);
                          if (contentProvider.getLoadedTopicCount(d.id) == 0) {
                            contentProvider.loadDomainTopics(d.id);
                          }
                        }
                      },
                      isDark: isDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildProgressRow(totalTopics, masteryPercent, isDark),
        ],
      ),
    );
  }

  Widget _buildDomainTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
    int? count,
    bool isAll = false,
  }) {
    final fgColor = selected
        ? Colors.white
        : (isDark ? Colors.white70 : Colors.grey.shade700);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : (isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5)),
          borderRadius: BorderRadius.circular(20),
          border: isAll && selected
              ? Border.all(color: AppColors.accent, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAll) ...[
              Icon(
                Icons.route,
                size: 13,
                color: selected ? Colors.white : AppColors.accent,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fgColor,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fgColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDomainDropdown(
    List<Domain> domains,
    ContentProvider contentProvider,
    LearningScopeProvider scope,
    String currentDomainId,
  ) {
    // 路线模式下只显示路线中的领域
    var displayDomains = domains;
    if (scope.isRouteMode && scope.isCrossDomain) {
      final routeSet = scope.scopeDomainIds.toSet();
      displayDomains = domains.where((d) => routeSet.contains(d.id)).toList();
      if (!routeSet.contains(currentDomainId) &&
          domains.any((d) => d.id == currentDomainId)) {
        displayDomains.add(domains.firstWhere((d) => d.id == currentDomainId));
      }
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: currentDomainId,
            isDense: true,
            isExpanded: true,
            selectedItemBuilder: (_) => displayDomains
                .map(
                  (d) => Text(
                    d.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
            items: displayDomains
                .map(
                  (d) => DropdownMenuItem(
                    value: d.id,
                    child: Text(
                      d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                widget.onDomainChanged(value);
                if (contentProvider.getLoadedTopicCount(value) == 0) {
                  contentProvider.loadDomainTopics(value);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField([LearningScopeProvider? scope]) {
    final isCrossRoute = scope != null && _isCrossDomainRouteMode(scope);
    return SizedBox(
      height: 36,
      child: TextField(
        decoration: InputDecoration(
          hintText: isCrossRoute
              ? l10n.get('search_all_route_domains')
              : l10n.get('search_current_domain'),
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () => setState(() => _searchQuery = ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildFilterButton() {
    return IconButton(
      icon: Icon(
        _showFilters ? Icons.filter_list_off : Icons.filter_list,
        size: 20,
        color: _hasActiveFilters ? Theme.of(context).colorScheme.primary : null,
      ),
      onPressed: () => setState(() => _showFilters = !_showFilters),
      tooltip: _showFilters ? l10n.get('hide_filter') : l10n.get('show_filter'),
      style: IconButton.styleFrom(
        backgroundColor: _hasActiveFilters
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : null,
      ),
    );
  }

  Widget _buildViewToggle() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, icon: Icon(Icons.view_list, size: 16)),
        ButtonSegment(value: true, icon: Icon(Icons.account_tree, size: 16)),
      ],
      selected: {_roadmapView},
      onSelectionChanged: (next) => setState(() => _roadmapView = next.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildProgressRow(int totalTopics, int masteryPercent, bool isDark) {
    return Row(
      children: [
        Text(
          l10n.getp('count_knowledge_point_2', {'count': totalTopics}),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: masteryPercent / 100,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              color: Theme.of(context).colorScheme.primary,
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$masteryPercent%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildRouteBanner(
    BuildContext context,
    bool isDark,
    LearningScopeProvider scope,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  scope.isCrossDomain
                      ? l10n.getp('route_mode_cross_domain', {
                          'domainCount': '${scope.scopeDomainIds.length}',
                          'topicCount': '${scope.scopeTopicIds.length}',
                        })
                      : l10n.get('route_mode'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: _routeScopeOnly,
                onChanged: (v) => setState(() => _routeScopeOnly = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.getp('knowledge_points_in_route', {
                  'count': scope.scopeTopicIds.length,
                }),
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 筛选标签
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 难度筛选
              ...([1, 2, 3, 4, 5].map((d) {
                final labels = {
                  1: l10n.get('beginner'),
                  2: l10n.get('basic'),
                  3: l10n.get('medium'),
                  4: l10n.get('compare_difficult'),
                  5: l10n.get('hard'),
                };
                final colors = {
                  1: const Color(0xFF10B981),
                  2: const Color(0xFF00CCF9),
                  3: const Color(0xFFF59E0B),
                  4: const Color(0xFFEF4444),
                  5: const Color(0xFF7C3AED),
                };
                return FilterChip(
                  label: Text(labels[d]!, style: const TextStyle(fontSize: 11)),
                  selected: _difficultyFilters.contains(d),
                  selectedColor: colors[d]!.withValues(alpha: 0.2),
                  checkmarkColor: colors[d],
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _difficultyFilters.add(d);
                      } else {
                        _difficultyFilters.remove(d);
                      }
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              })),

              // 高频筛选
              FilterChip(
                label: Text(
                  l10n.get('high_freq'),
                  style: TextStyle(fontSize: 11),
                ),
                avatar: const Icon(Icons.local_fire_department, size: 14),
                selected: _highFrequencyOnly,
                selectedColor: AppColors.danger.withValues(alpha: 0.15),
                checkmarkColor: AppColors.danger,
                onSelected: (v) => setState(() => _highFrequencyOnly = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),

              // 含代码题
              FilterChip(
                label: Text(
                  l10n.get('code_question_count'),
                  style: TextStyle(fontSize: 11),
                ),
                avatar: const Icon(Icons.code, size: 14),
                selected: _hasCodeOnly,
                selectedColor: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFF8B5CF6),
                onSelected: (v) => setState(() => _hasCodeOnly = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),

              // 含LeetCode
              FilterChip(
                label: Text('LeetCode', style: TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.link, size: 14),
                selected: _hasLeetcodeOnly,
                selectedColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFF10B981),
                onSelected: (v) => setState(() => _hasLeetcodeOnly = v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),

              // 掌握度筛选
              ...({
                'skilled': l10n.get('skilled_training'),
                'familiar': l10n.get('not_skilled_training'),
                'unfamiliar': l10n.get('un_mastery'),
              }.entries.map((e) {
                final colors = {
                  'skilled': AppColors.success,
                  'familiar': AppColors.warning,
                  'unfamiliar': AppColors.danger,
                };
                return FilterChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 11)),
                  selected: _statusFilters.contains(e.key),
                  selectedColor: colors[e.key]!.withValues(alpha: 0.15),
                  checkmarkColor: colors[e.key],
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _statusFilters.add(e.key);
                      } else {
                        _statusFilters.remove(e.key);
                      }
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              })),

              // 清除筛选
              if (_hasActiveFilters)
                ActionChip(
                  label: Text(
                    l10n.get('clear'),
                    style: TextStyle(fontSize: 11),
                  ),
                  avatar: const Icon(Icons.filter_alt_off, size: 14),
                  onPressed: _clearFilters,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),

          // 排序选项
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                l10n.get('sort'),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              _buildSortChip(l10n.get('default'), 'order', isDark),
              _buildSortChip(l10n.get('difficulty'), 'difficulty', isDark),
              _buildSortChip(l10n.get('score'), 'score', isDark),
              _buildSortChip(l10n.get('review_time'), 'reviewTime', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, String value, bool isDark) {
    final isSelected = _sortBy == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _sortBy = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : (isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.grey.shade700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            l10n.get('not_has_find_to_match_assign_knowledge_point'),
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          if (_hasActiveFilters)
            TextButton(
              onPressed: _clearFilters,
              child: Text(l10n.get('clear_filter')),
            ),
        ],
      ),
    );
  }

  Widget _buildTopicList(
    BuildContext context,
    Domain? currentDomain,
    List<Topic> topics,
    ProgressProvider progressProvider,
    bool isDark,
  ) {
    if (_roadmapView && currentDomain != null) {
      return _buildRoadmapView(
        context,
        currentDomain,
        topics,
        progressProvider,
        isDark,
      );
    }

    return ListView.builder(
      itemCount: topics.length,
      itemBuilder: (context, index) {
        return _buildTopicCard(
          context,
          topics[index],
          progressProvider,
          isDark,
        );
      },
    );
  }

  Widget _buildPhasedTopicList(
    BuildContext context,
    Domain? currentDomain,
    List<Topic> topics,
    ProgressProvider progressProvider,
    bool isDark,
  ) {
    final scopeProvider = context.read<LearningScopeProvider>();
    final phases = scopeProvider.scopePhases!;
    final allTopics = context.read<ContentProvider>().topics;
    final isCrossDomain = scopeProvider.isCrossDomain;

    final displayPhases = RouteComposer.filterPhasesByTopicIds(
      phases,
      topics.map((t) => t.id),
    );

    if (displayPhases.isEmpty) {
      return _buildTopicList(
        context,
        currentDomain,
        topics,
        progressProvider,
        isDark,
      );
    }

    final domains = context.read<ContentProvider>().domains;

    int? currentPhaseIndex;
    for (var i = 0; i < displayPhases.length; i++) {
      final p = displayPhases[i];
      var allDone = true;
      for (final tid in p.topicIds) {
        final t = allTopics[tid];
        if (t != null &&
            (progressProvider.getTopicProgress(tid)?.score ?? 0) < 85) {
          allDone = false;
          break;
        }
      }
      if (!allDone) {
        currentPhaseIndex = i;
        break;
      }
    }

    String? lastDomainId;
    return ListView.builder(
      itemCount: displayPhases.length,
      itemBuilder: (context, index) {
        final phase = displayPhases[index];
        final phaseDomainId =
            phase.domainId ??
            (phase.topicIds.isNotEmpty
                ? allTopics[phase.topicIds.first]?.domainId
                : null);
        final phaseTopics = phase.topicIds
            .map((id) => allTopics[id])
            .whereType<Topic>()
            .toList();

        var mastered = 0;
        for (final t in phaseTopics) {
          if ((progressProvider.getTopicProgress(t.id)?.score ?? 0) >= 85) {
            mastered++;
          }
        }
        final total = phase.topicIds.length;
        final allDone = mastered == total && total > 0;
        final inProgress = mastered > 0 && !allDone;
        final isCurrent = currentPhaseIndex == index;
        final isCollapsed = _collapsedPhases.contains(phase.id);

        final showDomainHeader =
            isCrossDomain &&
            phaseDomainId != null &&
            phaseDomainId != lastDomainId;
        lastDomainId = phaseDomainId;

        final domainTitle = phaseDomainId != null
            ? domains.where((d) => d.id == phaseDomainId).firstOrNull?.title ??
                  phaseDomainId
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDomainHeader && domainTitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      domainTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            InkWell(
              onTap: () {
                setState(() {
                  if (isCollapsed) {
                    _collapsedPhases.remove(phase.id);
                  } else {
                    _collapsedPhases.add(phase.id);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.06)
                      : (isDark
                            ? const Color(0xFF1A1D23)
                            : const Color(0xFFF5F5F5)),
                  borderRadius: BorderRadius.circular(8),
                  border: isCurrent
                      ? Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      isCollapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 20,
                      color: isDark ? Colors.white54 : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phase.focus.isNotEmpty
                                ? phase.focus
                                : '${l10n.get('phases_suffix')} ${index + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isCurrent
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: total > 0 ? mastered / total : 0,
                                  minHeight: 3,
                                  backgroundColor: isDark
                                      ? AppColors.borderMidnight
                                      : const Color(0xFFE8E8E8),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$mastered/$total',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white54
                                      : AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: allDone
                            ? AppColors.success.withValues(alpha: 0.12)
                            : inProgress
                            ? AppColors.warning.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        allDone
                            ? l10n.get('skilled_training')
                            : inProgress
                            ? l10n.get('progress_action_in')
                            : '',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: allDone
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isCollapsed)
              ...phaseTopics.map(
                (t) => _buildTopicCard(context, t, progressProvider, isDark),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTopicCard(
    BuildContext context,
    Topic topic,
    ProgressProvider progressProvider,
    bool isDark,
  ) {
    final progress = progressProvider.getTopicProgress(topic.id);
    final score = progress?.score ?? 0;
    final nextReview = progress?.nextReviewAt;

    final difficultyLabel = switch (topic.difficulty) {
      1 => l10n.get('beginner'),
      2 => l10n.get('basic'),
      3 => l10n.get('medium'),
      4 => l10n.get('compare_difficult'),
      5 => l10n.get('hard'),
      _ => '',
    };
    final difficultyColor = switch (topic.difficulty) {
      1 => const Color(0xFF10B981),
      2 => const Color(0xFF00CCF9),
      3 => const Color(0xFFF59E0B),
      4 => const Color(0xFFEF4444),
      5 => const Color(0xFF7C3AED),
      _ => Colors.grey,
    };

    final statusColor = score >= 85
        ? AppColors.success
        : score > 0
        ? AppColors.warning
        : Colors.grey;

    final hasCode = topic.recallPrompts.any((p) => p.mode == 'code');
    final hasLeetcode =
        topic.leetcodeUrl != null && topic.leetcodeUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: InkWell(
        onTap: () => widget.onTopicLearn(topic.id),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 状态指示器
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),

              // 主要信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题行
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            topic.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A1A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (topic.isNonProductionStatus)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: topic.isStagingStatus
                                  ? AppColors.warning.withValues(alpha: 0.1)
                                  : AppColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              topic.isStagingStatus
                                  ? l10n.get('test')
                                  : l10n.get('draft_2'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: topic.isStagingStatus
                                    ? AppColors.warning
                                    : AppColors.info,
                              ),
                            ),
                          ),
                        if (topic.highFrequency)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l10n.get('high_freq'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // 标签行
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Builder(
                          builder: (ctx) {
                            final sp = ctx.read<LearningScopeProvider>();
                            if (!_isCrossDomainRouteMode(sp)) {
                              return const SizedBox.shrink();
                            }
                            final cp = ctx.read<ContentProvider>();
                            final domainName =
                                cp.domains
                                    .where((d) => d.id == topic.domainId)
                                    .firstOrNull
                                    ?.title ??
                                topic.domainId;
                            return _buildMiniTag(
                              domainName,
                              AppColors.accent,
                              isDark,
                            );
                          },
                        ),
                        if (difficultyLabel.isNotEmpty)
                          _buildMiniTag(
                            difficultyLabel,
                            difficultyColor,
                            isDark,
                          ),
                        if (topic.interviewFrequencyLabel != null &&
                            !topic.highFrequency)
                          _buildMiniTag(
                            l10n.get(topic.interviewFrequencyLabel!),
                            AppColors.warning,
                            isDark,
                          ),
                        if (topic.estimatedMinutes > 0)
                          _buildMiniTag(
                            l10n.getp('minutes_min_1_2', {
                              'minutes': topic.estimatedMinutes,
                            }),
                            Colors.grey,
                            isDark,
                          ),
                        if (hasCode)
                          _buildMiniTag(
                            l10n.get('code'),
                            Color(0xFF8B5CF6),
                            isDark,
                          ),
                        if (hasLeetcode)
                          _buildMiniTag(
                            'LeetCode',
                            const Color(0xFF10B981),
                            isDark,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // 右侧信息
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (score > 0)
                    Text(
                      l10n.getp('score_score_1_2', {'score': score}),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  if (nextReview != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatReviewTime(nextReview),
                      style: TextStyle(
                        fontSize: 11,
                        color: nextReview.isBefore(DateTime.now())
                            ? AppColors.danger
                            : (isDark
                                  ? Colors.white38
                                  : const Color(0xFF999999)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        l10n.get('check_read'),
                        AppColors.categoryCyan,
                        () => widget.onTopicLearn(topic.id),
                      ),
                      const SizedBox(width: 6),
                      _buildActionButton(
                        l10n.get('practice'),
                        AppColors.accent,
                        () => widget.onTopicPractice(topic.id),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniTag(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  String _formatReviewTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);

    if (diff.isNegative) {
      final pastDiff = now.difference(time);
      if (pastDiff.inMinutes < 60) {
        return l10n.getp('n_min_ago_2', {'n': pastDiff.inMinutes});
      }
      if (pastDiff.inHours < 24) {
        return l10n.getp('n_hour_ago_2', {'n': pastDiff.inHours});
      }
      return l10n.getp('n_day_ago_2', {'n': pastDiff.inDays});
    }

    if (diff.inMinutes < 60) {
      return l10n.getp('n_min_after_2', {'n': diff.inMinutes});
    }
    if (diff.inHours < 24) {
      return l10n.getp('n_hour_after_2', {'n': diff.inHours});
    }
    return l10n.getp('n_day_after_2', {'n': diff.inDays});
  }

  static int _calcMasteryPercent(
    List<Topic> topics,
    ProgressProvider progress,
  ) {
    if (topics.isEmpty) return 0;
    double totalScore = 0;
    int count = 0;
    for (final topic in topics) {
      final score = progress.getTopicProgress(topic.id)?.score ?? 0;
      if (score > 0) {
        totalScore += score;
        count++;
      }
    }
    if (count == 0) return 0;
    final avgScore = totalScore / count;
    final coverage = count / topics.length;
    return (avgScore * coverage).round();
  }

  Widget _buildRoadmapView(
    BuildContext context,
    Domain currentDomain,
    List<Topic> topics,
    ProgressProvider progressProvider,
    bool isDark,
  ) {
    if (topics.isEmpty) {
      return Center(
        child: Text(
          l10n.get('temporary_no_knowledge_point'),
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    final sections = _buildRoadmapSections(currentDomain, topics);

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        final isLast = index == sections.length - 1;

        return _buildRoadmapPhase(
          context,
          section,
          index,
          progressProvider,
          isDark,
          isLast,
        );
      },
    );
  }

  List<_RoadmapSection> _buildRoadmapSections(
    Domain currentDomain,
    List<Topic> topics,
  ) {
    final categoryById = {
      for (final category in currentDomain.categories) category.id: category,
    };
    final topicsByCategory = <String, List<Topic>>{};
    for (final topic in topics) {
      topicsByCategory.putIfAbsent(topic.categoryId, () => []).add(topic);
    }

    final sections = <_RoadmapSection>[];
    final consumedCategories = <String>{};
    final learningPath = currentDomain.learningPaths.firstOrNull;

    if (learningPath != null && learningPath.steps.isNotEmpty) {
      for (final step in learningPath.steps) {
        final stepTopics = <Topic>[];
        for (final categoryId in step.categoryIds) {
          consumedCategories.add(categoryId);
          stepTopics.addAll(topicsByCategory[categoryId] ?? const []);
        }
        if (stepTopics.isEmpty) continue;
        stepTopics.sort((a, b) => a.order.compareTo(b.order));
        sections.add(
          _RoadmapSection(
            title: step.title,
            description: step.description,
            estimatedHours: step.estimatedHours,
            topics: stepTopics,
          ),
        );
      }
    }

    final remainingCategories =
        currentDomain.categories
            .where(
              (category) =>
                  !consumedCategories.contains(category.id) &&
                  (topicsByCategory[category.id]?.isNotEmpty ?? false),
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));

    for (final category in remainingCategories) {
      final categoryTopics = [...topicsByCategory[category.id]!]
        ..sort((a, b) => a.order.compareTo(b.order));
      sections.add(
        _RoadmapSection(
          title: category.title,
          description: category.description,
          topics: categoryTopics,
        ),
      );
    }

    final uncategorizedTopics =
        topics
            .where((topic) => !categoryById.containsKey(topic.categoryId))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (uncategorizedTopics.isNotEmpty) {
      sections.add(
        _RoadmapSection(
          title: l10n.get('un_score_category'),
          topics: uncategorizedTopics,
        ),
      );
    }

    return sections;
  }

  Widget _buildRoadmapPhase(
    BuildContext context,
    _RoadmapSection section,
    int index,
    ProgressProvider progressProvider,
    bool isDark,
    bool isLast,
  ) {
    const colors = [
      AppColors.categoryGreen,
      AppColors.accent,
      AppColors.categoryAmber,
      AppColors.categoryPurple,
      AppColors.categoryRed,
    ];
    final color = colors[index % colors.length];
    final topics = section.topics;
    final sectionKey = '${section.title}#$index';
    final isCollapsed = _collapsedRoadmapSections.contains(sectionKey);

    // 计算阶段进度
    int mastered = 0;
    int familiar = 0;
    for (final t in topics) {
      final score = progressProvider.getTopicProgress(t.id)?.score ?? 0;
      if (score >= 85) {
        mastered++;
      } else if (score > 0) {
        familiar++;
      }
    }
    final total = topics.length;
    final progressPercent = total > 0
        ? ((mastered + familiar * 0.5) / total * 100).round()
        : 0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧时间线
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // 节点圆点
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: mastered == total && total > 0
                        ? AppColors.success
                        : color,
                    border: Border.all(
                      color: mastered == total && total > 0
                          ? AppColors.success
                          : color,
                      width: 3,
                    ),
                  ),
                  child: mastered == total && total > 0
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
                // 连接线
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 右侧内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 阶段头部：标题 + 进度条 + 统计
                _buildRoadmapPhaseHeader(
                  context,
                  section,
                  color,
                  total,
                  mastered,
                  familiar,
                  progressPercent,
                  isDark,
                  isCollapsed,
                  () => setState(() {
                    if (isCollapsed) {
                      _collapsedRoadmapSections.remove(sectionKey);
                    } else {
                      _collapsedRoadmapSections.add(sectionKey);
                    }
                  }),
                ),
                if (!isCollapsed) const SizedBox(height: 6),
                // 紧凑知识点列表
                if (!isCollapsed)
                  ...topics.map(
                    (topic) => _buildRoadmapTopicRow(
                      context,
                      topic,
                      progressProvider,
                      isDark,
                      color,
                    ),
                  ),
                if (!isLast) const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadmapPhaseHeader(
    BuildContext context,
    _RoadmapSection section,
    Color color,
    int total,
    int mastered,
    int familiar,
    int progressPercent,
    bool isDark,
    bool isCollapsed,
    VoidCallback onToggle,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：阶段名 + 统计
          Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (section.estimatedHours > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${section.estimatedHours}h',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                l10n.getp('mastered_familiar_total', {
                  'mastered': mastered,
                  'familiar': familiar,
                  'total': total,
                }),
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: isCollapsed
                    ? l10n.get('expand')
                    : l10n.get('collapse'),
                onPressed: onToggle,
                icon: Icon(
                  isCollapsed
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  size: 18,
                  color: color,
                ),
              ),
            ],
          ),
          if (section.description != null &&
              section.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              section.description!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isDark ? Colors.white60 : Colors.grey.shade700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          // 第二行：进度条
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progressPercent / 100,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    color: color,
                    minHeight: 5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$progressPercent%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoadmapTopicRow(
    BuildContext context,
    Topic topic,
    ProgressProvider progressProvider,
    bool isDark,
    Color phaseColor,
  ) {
    final progress = progressProvider.getTopicProgress(topic.id);
    final score = progress?.score ?? 0;
    final nextReview = progress?.nextReviewAt;

    final statusColor = score >= 85
        ? AppColors.success
        : score > 0
        ? AppColors.warning
        : Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => widget.onTopicLearn(topic.id),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // 状态圆点
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              // 标题
              Expanded(
                child: Text(
                  topic.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: score >= 85 ? FontWeight.w500 : FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 高频标签
              if (topic.highFrequency) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    l10n.get('high_freq'),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
              // 分数
              if (score > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
              // 复习时间
              if (nextReview != null) ...[
                const SizedBox(width: 6),
                Text(
                  _formatReviewTime(nextReview),
                  style: TextStyle(
                    fontSize: 10,
                    color: nextReview.isBefore(DateTime.now())
                        ? AppColors.danger
                        : (isDark ? Colors.white38 : const Color(0xFF999999)),
                  ),
                ),
              ],
              // 练习按钮
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => widget.onTopicPractice(topic.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.get('practice'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoadmapSection {
  final String title;
  final String? description;
  final int estimatedHours;
  final List<Topic> topics;

  const _RoadmapSection({
    required this.title,
    this.description,
    this.estimatedHours = 0,
    required this.topics,
  });
}
