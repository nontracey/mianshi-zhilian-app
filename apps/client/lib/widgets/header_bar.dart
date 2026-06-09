import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/theme/colors.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/widgets/header_bar_widgets.dart';

class HeaderBar extends StatefulWidget {
  const HeaderBar({
    super.key,
    required this.title,
    required this.onProfile,
    this.onTopicTap,
    this.onContentStageChanged,
    this.sectionIndex = 0,
  });

  final String title;
  final VoidCallback onProfile;
  final ValueChanged<String>? onTopicTap;
  final ValueChanged<ContentEnv>? onContentStageChanged;
  final int sectionIndex;

  @override
  State<HeaderBar> createState() => _HeaderBarState();
}

class _HeaderBarState extends State<HeaderBar> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Topic> _searchResults = [];
  bool _isSearching = false;
  OverlayEntry? _overlayEntry;

  @override
  void didUpdateWidget(HeaderBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectionIndex != widget.sectionIndex &&
        (_isSearching || _overlayEntry != null)) {
      _removeOverlay();
      _searchController.clear();
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      _removeOverlay();
      return;
    }

    final contentProvider = context.read<ContentProvider>();
    final allTopics = contentProvider.topics.values.toList();
    final lowerQuery = query.toLowerCase();

    setState(() {
      _isSearching = true;
      _searchResults = allTopics
          .where((topic) {
            return topic.title.toLowerCase().contains(lowerQuery) ||
                topic.tags.any(
                  (tag) => tag.toLowerCase().contains(lowerQuery),
                ) ||
                topic.summary.toLowerCase().contains(lowerQuery);
          })
          .take(8)
          .toList();
    });

    _showSearchOverlay();
  }

  void _showSearchOverlay() {
    _removeOverlay();

    if (_searchResults.isEmpty || !_isSearching) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _removeOverlay();
                _searchController.clear();
                _searchFocusNode.unfocus();
                setState(() {
                  _isSearching = false;
                  _searchResults = [];
                });
              },
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: size.height + 4,
            right: 0,
            left: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(10),
                  shadowColor: Colors.black.withValues(alpha: 0.15),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 400),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF161B22) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF30363D)
                            : const Color(0xFFE0E0E0),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: [
                              Text(
                                l10n.get('search_results'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white54 : Colors.grey,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                l10n.getp('count_items_2', {
                                  'count': _searchResults.length,
                                }),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: isDark
                              ? const Color(0xFF30363D)
                              : const Color(0xFFF0F0F0),
                        ),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _searchResults.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              indent: 52,
                              color: isDark
                                  ? const Color(0xFF30363D)
                                  : const Color(0xFFF0F0F0),
                            ),
                            itemBuilder: (context, index) {
                              final topic = _searchResults[index];
                              return InkWell(
                                onTap: () {
                                  _removeOverlay();
                                  _searchController.clear();
                                  setState(() {
                                    _isSearching = false;
                                    _searchResults = [];
                                  });
                                  if (widget.onTopicTap != null) {
                                    widget.onTopicTap!(topic.id);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.menu_book_outlined,
                                          size: 18,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
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
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.folder_outlined,
                                                  size: 12,
                                                  color: isDark
                                                      ? Colors.white38
                                                      : Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  topic.domain,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isDark
                                                        ? Colors.white38
                                                        : Colors.grey,
                                                  ),
                                                ),
                                                if (topic.highFrequency) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.warning.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(3),
                                                    ),
                                                    child: Text(
                                                      l10n.get('high_frequency'),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w600,
                                                        color: AppColors.warning,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 14,
                                        color: isDark
                                            ? Colors.white24
                                            : Colors.grey.shade300,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildSearchField(BuildContext context, bool isDark) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: l10n.get('search_topics_hint'),
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.grey.shade400,
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 16,
              color: isDark ? Colors.white38 : Colors.grey,
            ),
            suffixIcon: _isSearching
                ? IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      _searchController.clear();
                      _removeOverlay();
                      setState(() {
                        _isSearching = false;
                        _searchResults = [];
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: isDark
                ? const Color(0xFF21262D)
                : const Color(0xFFF0F2F5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 0,
            ),
            isDense: true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aiProvider = context.watch<AiProvider>();
    final authProvider = context.watch<AuthProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

    // 获取当前使用的AI模型名称
    final currentModelName =
        aiProvider.defaultConfig?.name ??
        aiProvider.enabledConfigs.firstOrNull?.name ??
        l10n.get('ai_not_configured');

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 600;

    final surfaceColor = Theme.of(context).colorScheme.surface;
    final borderColor = Theme.of(context).colorScheme.outline;

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: surfaceColor,
          border: Border(bottom: BorderSide(color: borderColor, width: 1)),
        ),
        child: Row(
          children: [
            // 左侧：内容阶段切换 + AI 模型选择
            ContentStageSelector(
              isDark: isDark,
              currentEnv: settingsProvider.settings.contentEnv,
              userRole: authProvider.userRole,
              onStageChanged: widget.onContentStageChanged,
            ),
            if (isWide) const SizedBox(width: 20),
            if (isWide)
              AiModelSelector(
                modelName: currentModelName,
                hasConfig: aiProvider.configs.isNotEmpty,
                isDark: isDark,
              ),
            if (!isWide) ...[
              const SizedBox(width: 8),
              AiModelIconButton(
                hasConfig: aiProvider.configs.isNotEmpty,
                isDark: isDark,
              ),
            ],

            // 中间弹性空间
            const Spacer(),

            // 右侧：搜索框 + 用户头像
            isWide
                ? _buildSearchField(context, isDark)
                : _buildMobileSearchIcon(context, isDark),
            const SizedBox(width: 12),
            _buildUserAvatar(context, isDark),
          ],
        ),
      ),
    );
  }

  void _showMobileSearchDialog(BuildContext context, bool isDark) {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.get('search_topics_hint'),
          style: TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.get('search_topics_hint'),
              prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(ctx).pop();
                _onSearchChanged(value.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (searchController.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop();
                _onSearchChanged(searchController.text.trim());
              }
            },
            child: Text(l10n.get('search')),
          ),
        ],
      ),
    ).then((_) => searchController.dispose());
  }

  Widget _buildMobileSearchIcon(BuildContext context, bool isDark) {
    return IconButton(
      icon: Icon(
        Icons.search,
        size: 20,
        color: isDark ? Colors.white70 : Colors.grey.shade700,
      ),
      onPressed: () => _showMobileSearchDialog(context, isDark),
      tooltip: l10n.get('search'),
    );
  }

  // 种子头像调色板
  static const List<Color> _seedColors = [
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF673AB7),
    Color(0xFF3F51B5),
    Color(0xFF2196F3),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFFF5722),
    Color(0xFF795548),
    Color(0xFF607D8B),
    Color(0xFFE67E22),
    Color(0xFF2ECC71),
    Color(0xFF3498DB),
    Color(0xFF9B59B6),
    Color(0xFF1ABC9C),
  ];

  Color _seedColor(String seed) {
    final hash = seed.hashCode.abs();
    return _seedColors[hash % _seedColors.length];
  }

  Widget _buildUserAvatar(BuildContext context, bool isDark) {
    final progress = context.watch<ProgressProvider>();
    final profile = progress.localProfile;
    final hasAvatarUrl =
        profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty;
    final hasSeed = profile.avatarSeed.isNotEmpty;
    final seedColor = _seedColor(profile.avatarSeed);

    // 无头像配置时显示默认图标
    if (!hasAvatarUrl && !hasSeed) {
      return IconButton.filledTonal(
        onPressed: widget.onProfile,
        icon: Icon(
          Icons.person_outline,
          size: 20,
          color: isDark ? Colors.white70 : Colors.grey.shade700,
        ),
        style: IconButton.styleFrom(
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      );
    }

    final diceBearUrl = hasSeed && !hasAvatarUrl
        ? 'https://api.dicebear.com/9.x/fun-emoji/png'
              '?seed=${Uri.encodeComponent(profile.avatarSeed)}&backgroundColor=transparent'
        : null;

    return GestureDetector(
      onTap: widget.onProfile,
      child: CircleAvatar(
        radius: 16,
        backgroundColor: hasAvatarUrl
            ? null
            : seedColor.withValues(alpha: 0.15),
        backgroundImage: hasAvatarUrl
            ? NetworkImage(profile.avatarUrl!)
            : diceBearUrl != null
            ? NetworkImage(diceBearUrl)
            : null,
      ),
    );
  }
}


