import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/services/storage_service.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/learning_scope_provider.dart';

import 'topic_detail_panels.dart';

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.topic,
    required this.onBack,
    this.initialTabIndex = 0,
    this.onRouteTopicTap,
  });

  final Topic topic;
  final VoidCallback onBack;
  final int initialTabIndex;
  final ValueChanged<String>? onRouteTopicTap;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage>
    with SingleTickerProviderStateMixin {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  late TabController _tabController;
  final _answerController = TextEditingController();
  bool _isEvaluating = false;
  bool _isVoiceListening = false;
  Map<String, dynamic>? _evaluationResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
      vsync: this,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopBar(context, topic, isDesktop),
        Builder(builder: (ctx) {
          final scope = ctx.watch<LearningScopeProvider>();
          if (scope.isRouteMode && scope.scopeTopicIds.isNotEmpty) {
            return _buildRouteNav(ctx, scope.scopeTopicIds);
          }
          return const SizedBox.shrink();
        }),
        Expanded(
          child: isDesktop
              ? _buildDesktopLayout(context, topic)
              : _buildMobileLayout(context, topic),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, Topic topic, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, size: 20),
            style: IconButton.styleFrom(padding: const EdgeInsets.all(8)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        topic.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (topic.isNonProductionStatus)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
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
                              ? l10n.get('test_content')
                              : l10n.get('draft_content'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: topic.isStagingStatus
                                ? AppColors.warning
                                : AppColors.info,
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  '${topic.domain} · ${topic.category}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Tab 切换按钮
          _buildTabToggle(context),
        ],
      ),
    );
  }

  Widget _buildRouteNav(BuildContext context, List<String> ids) {
    final l10n = context.watch<LocalizationProvider>();
    final contentProvider = context.read<ContentProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIdx = ids.indexOf(widget.topic.id);
    if (currentIdx < 0) return const SizedBox.shrink();
    final hasPrev = currentIdx > 0;
    final hasNext = currentIdx < ids.length - 1;
    final prevTitle = hasPrev ? contentProvider.findTopic(ids[currentIdx - 1])?.title ?? '' : '';
    final nextTitle = hasNext ? contentProvider.findTopic(ids[currentIdx + 1])?.title ?? '' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.accent.withValues(alpha: 0.06) : AppColors.accent.withValues(alpha: 0.04),
        border: Border(bottom: BorderSide(color: AppColors.accent.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          Icon(Icons.route, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            l10n.getp('route_topic_progress', {
              'current': '${currentIdx + 1}',
              'total': '${ids.length}',
            }),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
          ),
          const Spacer(),
          if (hasPrev)
            _RouteNavButton(
              icon: Icons.navigate_before,
              label: prevTitle,
              accentColor: AppColors.accent,
              onTap: () => widget.onRouteTopicTap?.call(ids[currentIdx - 1]),
            )
          else
            IconButton(
              onPressed: null,
              icon: const Icon(Icons.navigate_before, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          if (hasNext)
            _RouteNavButton(
              icon: Icons.navigate_next,
              label: nextTitle,
              accentColor: AppColors.accent,
              onTap: () => widget.onRouteTopicTap?.call(ids[currentIdx + 1]),
            )
          else
            IconButton(
              onPressed: null,
              icon: const Icon(Icons.navigate_next, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _buildTabToggle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.borderMidnightSubtle
            : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          _buildTabButton(
            context,
            label: l10n.get('knowledge_check_read'),
            icon: Icons.menu_book_outlined,
            isSelected: _tabController.index == 0,
            onTap: () => _tabController.animateTo(0),
          ),
          _buildTabButton(
            context,
            label: l10n.get('review_narrate_practice'),
            icon: Icons.record_voice_over_outlined,
            isSelected: _tabController.index == 1,
            onTap: () => _tabController.animateTo(1),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white54 : Colors.grey),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white54 : Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, Topic topic) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：目录与前置知识
        SizedBox(width: 220, child: LeftSidebar(topic: topic)),
        const VerticalDivider(width: 1),
        // 右侧：Tab 内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              KnowledgeTab(topic: topic),
              RecallTab(
                topic: topic,
                answerController: _answerController,
                isEvaluating: _isEvaluating,
                isVoiceListening: _isVoiceListening,
                evaluationResult: _evaluationResult,
                onEvaluate: _handleEvaluate,
                onVoiceListeningChanged: (listening) {
                  setState(() => _isVoiceListening = listening);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, Topic topic) {
    return Column(
      children: [
        // 标签信息
        TopicHeader(topic: topic),
        // Tab 内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              KnowledgeTab(topic: topic),
              RecallTab(
                topic: topic,
                answerController: _answerController,
                isEvaluating: _isEvaluating,
                isVoiceListening: _isVoiceListening,
                evaluationResult: _evaluationResult,
                onEvaluate: _handleEvaluate,
                onVoiceListeningChanged: (listening) {
                  setState(() => _isVoiceListening = listening);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleEvaluate() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('please_first_input_your_answer'))),
      );
      return;
    }

    final aiProvider = context.read<AiProvider>();

    setState(() => _isEvaluating = true);

    try {
      final topic = widget.topic;
      final result = await aiProvider.evaluateAnswer(
        topicId: topic.id,
        question: topic.recallPrompts.isNotEmpty
            ? topic.recallPrompts.first.prompt
            : topic.title,
        userAnswer: answer,
        rubric: topic.rubric,
      );

      if (mounted) {
        setState(() => _evaluationResult = result);
        final progressProvider = context.read<ProgressProvider>();
        final enabledConfigs = aiProvider.enabledConfigs;
        final aiConfigId =
            aiProvider.defaultConfig?.id ??
            (enabledConfigs.isNotEmpty ? enabledConfigs.first.id : null);
        await progressProvider.addAttempt(
          PracticeAttempt(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            topicId: topic.id,
            promptId: topic.recallPrompts.isNotEmpty
                ? topic.recallPrompts.first.id
                : '',
            mode: 'topicDetailRecall',
            question: topic.recallPrompts.isNotEmpty
                ? topic.recallPrompts.first.prompt
                : topic.title,
            answer: answer,
            createdAt: DateTime.now(),
            score: result['score'] as int?,
            level: result['level'] as String?,
            summary: result['summary'] as String?,
            missedPoints:
                (result['missedPoints'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            wrongPoints:
                ((result['wrongPoints'] ?? result['errorPoints'])
                        as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            improvedAnswer:
                (result['improvedAnswer'] ?? result['optimizedAnswer'])
                    as String?,
            nextAction: result['nextAction'] as String?,
            aiConfigId: aiConfigId,
            aiEvaluated: result['aiUnavailable'] != true,
            localOnly: result['aiUnavailable'] == true,
            analysisStatus: result['aiUnavailable'] == true
                ? 'unanalysed'
                : result['score'] == null
                ? 'unanalysed'
                : 'success',
          ),
        );
        final aiEvaluationSucceeded =
            result['aiUnavailable'] != true && result['score'] is int;
        if (aiEvaluationSucceeded) {
          await progressProvider.updateTopicProgress(
            topic.id,
            score: result['score'] as int,
          );
        }
        final storage = StorageService();
        await storage.recordAnalyticsFeature('ai_eval');
        await storage.recordAnalyticsFeature(
          aiEvaluationSucceeded ? 'ai_eval_success' : 'ai_eval_failed',
        );
      }
    } catch (e) {
      unawaited(StorageService().recordAnalyticsFeature('ai_eval_failed'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.getp('ai_evaluation_fail_error_2', {'error': e}),
            ),
            action: SnackBarAction(
              label: l10n.get('retry'),
              onPressed: _handleEvaluate,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }
}

class _RouteNavButton extends StatelessWidget {
  const _RouteNavButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: accentColor),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
