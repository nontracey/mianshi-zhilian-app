import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/pages/profile/ai_config_page.dart';

class HeaderBar extends StatefulWidget {
  const HeaderBar({
    super.key,
    required this.title,
    required this.onProfile,
    this.onTopicTap,
  });

  final String title;
  final VoidCallback onProfile;
  final ValueChanged<String>? onTopicTap;

  @override
  State<HeaderBar> createState() => _HeaderBarState();
}

class _HeaderBarState extends State<HeaderBar> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Topic> _searchResults = [];
  bool _isSearching = false;
  OverlayEntry? _overlayEntry;

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

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: size.height + 4,
        left: size.width - 360,
        width: 340,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              children: _searchResults
                  .map(
                    (topic) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.menu_book_outlined, size: 20),
                      title: Text(
                        topic.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        topic.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Chip(
                        label: Text(
                          topic.domain,
                          style: const TextStyle(fontSize: 10),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
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
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aiProvider = context.watch<AiProvider>();
    final authProvider = context.watch<AuthProvider>();
    
    // 获取当前使用的AI模型名称
    final currentModelName = aiProvider.configs.isNotEmpty
        ? aiProvider.configs.first.name
        : '未配置 AI 模型';

    final surfaceColor = Theme.of(context).colorScheme.surface;
    final borderColor = Theme.of(context).colorScheme.outline;

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: surfaceColor,
          border: Border(
            bottom: BorderSide(
              color: borderColor,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // 内容阶段切换
            _ContentStageSelector(
              isDark: isDark,
              isLoggedIn: authProvider.isLoggedIn,
            ),
            const SizedBox(width: 24),

            // AI 模型选择
            _AiModelSelector(
              modelName: currentModelName,
              hasConfig: aiProvider.configs.isNotEmpty,
              isDark: isDark,
            ),
            const SizedBox(width: 24),

            // 搜索框
            Expanded(
              child: SizedBox(
                width: 300,
                child: SearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  hintText: '搜索知识点、题目、路线',
                  leading: Icon(Icons.search, size: 20, color: isDark ? Colors.white54 : Colors.grey),
                  trailing: _isSearching
                      ? [
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _removeOverlay();
                              setState(() {
                                _isSearching = false;
                                _searchResults = [];
                              });
                            },
                          ),
                        ]
                      : null,
                  onChanged: _onSearchChanged,
                  elevation: WidgetStateProperty.all(0),
                  backgroundColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // 用户头像
            _buildUserAvatar(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar(BuildContext context, bool isDark) {
    // 这里可以后续接入用户头像
    return IconButton.filledTonal(
      onPressed: widget.onProfile,
      icon: Icon(Icons.person_outline, size: 20, color: isDark ? Colors.white70 : Colors.grey.shade700),
      style: IconButton.styleFrom(
        backgroundColor: isDark 
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.05),
      ),
    );
  }
}

// AI 模型选择器
class _AiModelSelector extends StatelessWidget {
  const _AiModelSelector({
    required this.modelName,
    required this.hasConfig,
    required this.isDark,
  });

  final String modelName;
  final bool hasConfig;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AiConfigPage()),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 16,
              color: hasConfig 
                  ? const Color(0xFF3078F0)
                  : (isDark ? Colors.white38 : Colors.grey),
            ),
            const SizedBox(width: 6),
            Text(
              hasConfig ? modelName : '未配置 AI',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: hasConfig
                    ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                    : (isDark ? Colors.white38 : Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 内容阶段选择器
class _ContentStageSelector extends StatelessWidget {
  const _ContentStageSelector({required this.isDark, this.isLoggedIn = false});

  final bool isDark;
  final bool isLoggedIn;

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('published', '发布', true),   // 所有用户可用
      ('testing', '测试', isLoggedIn), // 仅登录用户
      ('draft', '草稿', isLoggedIn),   // 仅登录用户
    ];

    return Row(
      children: [
        Text(
          '内容',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : const Color(0xFF666666),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF21262D) : const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            children: stages.map((stage) {
              final isSelected = stage.$1 == 'published';
              final isEnabled = stage.$3;
              
              return GestureDetector(
                onTap: isEnabled
                    ? () {
                        // TODO: 实现阶段切换逻辑
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('登录后可查看测试版和草稿内容'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stage.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : isEnabled
                                  ? (isDark ? Colors.white70 : const Color(0xFF666666))
                                  : (isDark ? Colors.white30 : Colors.grey.shade400),
                        ),
                      ),
                      if (!isEnabled) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.lock_outline,
                          size: 10,
                          color: isDark ? Colors.white30 : Colors.grey.shade400,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
