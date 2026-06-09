import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/domain.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';

enum MasterySort { scoreAsc, scoreDesc }

enum MasteryFilter { all, skilled, familiar, unfamiliar }

class MasteryPage extends StatefulWidget {
  const MasteryPage({
    super.key,
    required this.onDomainChanged,
    this.onStartTopicPractice,
    this.onStartPractice,
  });

  final ValueChanged<String> onDomainChanged;
  final ValueChanged<String>? onStartTopicPractice;
  final VoidCallback? onStartPractice;

  @override
  State<MasteryPage> createState() => _MasteryPageState();
}

class _MasteryPageState extends State<MasteryPage> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  MasterySort _sort = MasterySort.scoreAsc;
  MasteryFilter _filter = MasteryFilter.all;
  String? _diagnosticFilter; // null / 'longUnreviewed' / 'regressed'
  final _storage = StorageService();
  List<String> _disabledIds = [];

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

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final contentProvider = context.watch<ContentProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final scope = context.watch<LearningScopeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final currentDomainId = settingsProvider.settings.currentDomain;
    final allDomains = contentProvider.domains;
    final domains = _filterDomains(allDomains);
    final isCrossDomain = scope.isCrossDomain;
    final currentDomain = allDomains
        .where((d) => d.id == currentDomainId)
        .firstOrNull;
    if (currentDomain == null && !isCrossDomain) {
      return _buildDomainPrompt(context, contentProvider, domains, isDark);
    }

    // 路线范围 topic 解析（通过 LearningScopeProvider 统一入口）
    final scopedTopics = scope.resolveScopedTopics(contentProvider);
    final domainProgress = scope.isRouteMode
        ? (masteryPercent: _calcMasteryPercent(scopedTopics, progressProvider), topicCount: scopedTopics.length)
        : progressProvider.getDomainProgress(
            currentDomainId,
            contentProvider.topics.values.toList(),
          );
    final masteryPercent = domainProgress.masteryPercent;
    final dueCount = progressProvider.getTodayReviewTopics(scopedTopics).length;
    final readiness = progressProvider.readinessScore(scopedTopics);
    final highFrequencyWeak = scopedTopics.where((topic) {
      final score = progressProvider.getTopicProgress(topic.id)?.score ?? 0;
      return topic.highFrequency && score < 85;
    }).length;
    final longUnreviewedIds = progressProvider.getLongUnreviewedTopicIds(
      scopedTopics,
    );
    final regressedIds = progressProvider.getRegressedTopicIds(scopedTopics);

    var filteredTopics = _applyFilter(
      scopedTopics,
      progressProvider,
      settingsProvider.settings.contentEnv,
    );
    // 诊断筛选叠加
    if (_diagnosticFilter == 'longUnreviewed') {
      filteredTopics = filteredTopics
          .where((t) => longUnreviewedIds.contains(t.id))
          .toList();
    } else if (_diagnosticFilter == 'regressed') {
      filteredTopics = filteredTopics
          .where((t) => regressedIds.contains(t.id))
          .toList();
    }
    final sortedTopics = _applySort(filteredTopics, progressProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCrossDomain && scope.isRouteMode)
            _buildCrossDomainOverview(context, scopedTopics, progressProvider, domains, contentProvider, isDark)
          else
            _buildCompactHeader(
              context,
              currentDomain,
              masteryPercent,
              domains,
              contentProvider,
              isDark,
              currentDomainId,
            ),
          const SizedBox(height: 12),

          _buildDiagnosticCards(
            context,
            readiness,
            dueCount,
            highFrequencyWeak,
            longUnreviewedIds.length,
            regressedIds.length,
            isDark,
          ),
          const SizedBox(height: 12),

          _buildFilterSortBar(context, isDark),
          const SizedBox(height: 12),

          Expanded(
            child: sortedTopics.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bar_chart_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          l10n.get('temporary_no_data'),
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: sortedTopics.length,
                    itemBuilder: (context, index) {
                      return _buildTopicItem(
                        context,
                        sortedTopics[index],
                        progressProvider,
                        isDark,
                      );
                    },
                  ),
          ),
         ],
      ),
    );
  }

  Widget _buildCrossDomainOverview(
    BuildContext context,
    List<Topic> scopedTopics,
    ProgressProvider progressProvider,
    List<Domain> domains,
    ContentProvider contentProvider,
    bool isDark,
  ) {
    final l10n = context.watch<LocalizationProvider>();
    final scope = context.watch<LearningScopeProvider>();
    final routeDomainIds = scope.scopeDomainIds;

    int mastered = 0;
    int learning = 0;
    int unfamiliar = 0;
    for (final t in scopedTopics) {
      final s = progressProvider.getTopicProgress(t.id)?.score ?? 0;
      if (s >= 85) {
        mastered++;
      } else if (s >= 60) {
        learning++;
      } else {
        unfamiliar++;
      }
    }
    final total = scopedTopics.length;
    final pct = total > 0 ? (mastered * 100 ~/ total) : 0;

    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(Icons.route, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                l10n.get('route_mastery_overview'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        minHeight: 8,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 16,
                      children: [
                        _buildStatChip(AppColors.success, l10n.get('skilled_training'), '$mastered'),
                        _buildStatChip(AppColors.warning, l10n.get('not_skilled_training'), '$learning'),
                        _buildStatChip(AppColors.danger, l10n.get('un_mastery'), '$unfamiliar'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: routeDomainIds.map((did) {
                final d = domains.where((dd) => dd.id == did).firstOrNull;
                final dTopics = scopedTopics.where((t) => t.domainId == did).toList();
                int dMastered = 0;
                for (final t in dTopics) {
                  if ((progressProvider.getTopicProgress(t.id)?.score ?? 0) >= 85) dMastered++;
                }
                final dPct = dTopics.isNotEmpty ? (dMastered * 100 ~/ dTopics.length) : 0;
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (d?.color ?? AppColors.accent).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: (d?.color ?? AppColors.accent).withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d?.title ?? did,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: d?.color ?? AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dPct% ($dMastered/${dTopics.length})',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(Color color, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$value $label', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildDomainPrompt(BuildContext context, ContentProvider contentProvider, List<Domain> domains, bool isDark) {
    final l10n = context.watch<LocalizationProvider>();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.explore_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(l10n.get('please_select_one_domain'), style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: domains.take(6).map((d) => ActionChip(
              label: Text(d.title),
              avatar: Icon(Icons.arrow_forward, size: 14),
              onPressed: () {
                widget.onDomainChanged(d.id);
                if (contentProvider.getLoadedTopicCount(d.id) == 0) {
                  contentProvider.loadDomainTopics(d.id);
                }
              },
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader(
    BuildContext context,
    Domain? domain,
    int masteryPercent,
    List<Domain> domains,
    ContentProvider contentProvider,
    bool isDark,
    String currentDomainId,
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
          final isWide = constraints.maxWidth > 400;
          if (isWide) {
            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentDomainId,
                      isDense: true,
                      items: domains
                          .map(
                            (d) => DropdownMenuItem(
                              value: d.id,
                              child: Text(
                                d.title,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$masteryPercent%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: masteryPercent / 100,
                          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          color: Theme.of(context).colorScheme.primary,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
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
                    items: domains
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              d.title,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '$masteryPercent%',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: masteryPercent / 100,
                        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        color: Theme.of(context).colorScheme.primary,
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

Widget _buildDiagnosticCards(
    BuildContext context,
    int readiness,
    int dueCount,
    int highFrequencyWeak,
    int longUnreviewedCount,
    int regressedCount,
    bool isDark,
  ) {
    final cards = [
      _buildDiagnosticCard(
        l10n.get('readiness'),
        '$readiness',
        AppColors.accent,
        isDark,
      ),
      _buildDiagnosticCard(
        l10n.get('pending_review'),
        '$dueCount',
        AppColors.warning,
        isDark,
      ),
      _buildDiagnosticCard(
        l10n.get('un_review'),
        '$longUnreviewedCount',
        AppColors.accent,
        isDark,
        filterKey: 'longUnreviewed',
      ),
      _buildDiagnosticCard(
        l10n.get('regression_step'),
        '$regressedCount',
        AppColors.danger,
        isDark,
        filterKey: 'regressed',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 480) {
          return Row(
            children: cards
                .expand((c) => [Expanded(child: c), const SizedBox(width: 8)])
                .toList()
              ..removeLast(),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cards
              .map((c) => SizedBox(
                    width: (constraints.maxWidth - 8) / 2,
                    child: c,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildDiagnosticCard(
    String label,
    String value,
    Color color,
    bool isDark, {
    String? filterKey,
  }) {
    final isActive = filterKey != null && _diagnosticFilter == filterKey;
    return GestureDetector(
      onTap: filterKey != null
          ? () =>
                setState(() => _diagnosticFilter = isActive ? null : filterKey)
          : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.12)
              : (isDark ? const Color(0xFF161B22) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? color
                : (isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8)),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSortBar(BuildContext context, bool isDark) {
    return Row(
      children: [
        // 筛选
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(l10n.get('all'), MasteryFilter.all, isDark),
                _buildFilterChip(
                  l10n.get('skilled_training'),
                  MasteryFilter.skilled,
                  isDark,
                ),
                _buildFilterChip(
                  l10n.get('not_skilled_training'),
                  MasteryFilter.familiar,
                  isDark,
                ),
                _buildFilterChip(
                  l10n.get('un_mastery'),
                  MasteryFilter.unfamiliar,
                  isDark,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 排序
        _buildSortChip(l10n.get('low_high'), MasterySort.scoreAsc, isDark),
        const SizedBox(width: 8),
        _buildSortChip(l10n.get('high_low'), MasterySort.scoreDesc, isDark),
      ],
    );
  }

  Widget _buildFilterChip(String label, MasteryFilter filter, bool isDark) {
    final isSelected = _filter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  Widget _buildSortChip(String label, MasterySort sort, bool isDark) {
    final isSelected = _sort == sort;
    return GestureDetector(
      onTap: () => setState(() => _sort = sort),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    );
  }

  Widget _buildTopicItem(
    BuildContext context,
    Topic topic,
    ProgressProvider progressProvider,
    bool isDark,
  ) {
    final progress = progressProvider.getTopicProgress(topic.id);
    final score = progress?.score ?? 0;
    final scoreColor = score >= 85
        ? AppColors.success
        : score >= 60
        ? AppColors.warning
        : AppColors.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Row(
        children: [
          // 分数
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scoreColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (topic.highFrequency)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
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
                            fontSize: 10,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    Text(
                      '${topic.domain} · ${topic.difficultyLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 操作
          TextButton(
            onPressed: () {
              if (widget.onStartTopicPractice != null) {
                widget.onStartTopicPractice!(topic.id);
              } else {
                widget.onStartPractice?.call();
              }
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: Text(
              l10n.get('start_practice'),
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  List<Topic> _applyFilter(
    List<Topic> topics,
    ProgressProvider progress,
    ContentEnv contentEnv,
  ) {
    // 首先按内容阶段过滤
    var filteredTopics = topics;
    if (contentEnv == ContentEnv.production) {
      // 发布阶段只显示 production 状态的内容
      filteredTopics = topics
          .where((t) => t.status == null || t.status == 'production')
          .toList();
    } else if (contentEnv == ContentEnv.staging) {
      // 测试阶段显示 production 和 staging 状态的内容；兼容旧 test 值
      filteredTopics = topics
          .where((t) => t.isProductionStatus || t.isStagingStatus)
          .toList();
    }
    // draft 阶段显示所有内容

    // 然后按掌握度过滤
    switch (_filter) {
      case MasteryFilter.skilled:
        return filteredTopics
            .where((t) => (progress.getTopicProgress(t.id)?.score ?? 0) >= 85)
            .toList();
      case MasteryFilter.familiar:
        return filteredTopics.where((t) {
          final score = progress.getTopicProgress(t.id)?.score ?? 0;
          return score >= 60 && score < 85;
        }).toList();
      case MasteryFilter.unfamiliar:
        return filteredTopics
            .where((t) => (progress.getTopicProgress(t.id)?.score ?? 0) < 60)
            .toList();
      case MasteryFilter.all:
        return filteredTopics;
    }
  }

  List<Topic> _applySort(List<Topic> topics, ProgressProvider progress) {
    final sorted = List<Topic>.from(topics);
    switch (_sort) {
      case MasterySort.scoreAsc:
        sorted.sort(
          (a, b) => (progress.getTopicProgress(a.id)?.score ?? 0).compareTo(
            progress.getTopicProgress(b.id)?.score ?? 0,
          ),
        );
      case MasterySort.scoreDesc:
        sorted.sort(
          (a, b) => (progress.getTopicProgress(b.id)?.score ?? 0).compareTo(
            progress.getTopicProgress(a.id)?.score ?? 0,
          ),
        );
    }
    return sorted;
  }

  static int _calcMasteryPercent(List<Topic> topics, ProgressProvider progress) {
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
}

extension on Topic {
  String difficultyLabel(LocalizationProvider l10n) => switch (difficulty) {
    1 => l10n.get('beginner'),
    2 => l10n.get('basic'),
    3 => l10n.get('medium'),
    4 => l10n.get('compare_difficult'),
    5 => l10n.get('hard'),
    _ => '',
  };
}
