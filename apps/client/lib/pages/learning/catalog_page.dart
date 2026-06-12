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

part 'catalog_page/sections.dart';

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

  /// part 文件中的 extension（_CatalogPageSections）不是 State 的子类成员，
  /// 直接调用 protected 的 setState 会触发 invalid_use_of_protected_member，
  /// 统一经由该方法刷新。
  void _refresh(VoidCallback fn) => setState(fn);

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
}
