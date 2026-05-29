import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';
import 'package:mianshi_zhilian/providers/ai_provider.dart';

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
    
    // 获取当前使用的AI模型名称
    final currentModelName = aiProvider.configs.isNotEmpty
        ? aiProvider.configs.first.name
        : '未配置 AI 模型';

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF15202E) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF263238) : const Color(0xFFE8E8E8),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // 内容阶段切换
            _ContentStageSelector(isDark: isDark),
            const SizedBox(width: 24),

            // AI 模型选择
            _AiModelSelector(
              modelName: currentModelName,
              capabilities: const ['文本', '图片', '语音'],
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
                  leading: const Icon(Icons.search, size: 20),
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
                    isDark ? const Color(0xFF1A2332) : const Color(0xFFF5F5F5),
                  ),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // 通知图标
            IconButton(
              icon: Badge(
                label: const Text('3', style: TextStyle(fontSize: 10)),
                child: Icon(
                  Icons.notifications_outlined,
                  color: isDark ? Colors.white70 : const Color(0xFF666666),
                ),
              ),
              onPressed: () {},
            ),
            const SizedBox(width: 8),
            
            // 用户头像
            IconButton.filledTonal(
              onPressed: widget.onProfile,
              icon: const Icon(Icons.person_outline, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: isDark 
                    ? const Color(0xFF1A2332) 
                    : const Color(0xFFF0F2F5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// AI 模型选择器
class _AiModelSelector extends StatelessWidget {
  const _AiModelSelector({
    required this.modelName,
    required this.capabilities,
    required this.isDark,
  });

  final String modelName;
  final List<String> capabilities;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '当前 AI 模型',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : const Color(0xFF999999),
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 14,
                  color: const Color(0xFF3078F0),
                ),
                const SizedBox(width: 4),
                Text(
                  modelName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: isDark ? Colors.white54 : const Color(0xFF999999),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(width: 12),
        // 能力标签
        ...capabilities.map((cap) => Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF3078F0).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              cap,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3078F0),
              ),
            ),
          ),
        )),
      ],
    );
  }
}

// 内容阶段选择器
class _ContentStageSelector extends StatelessWidget {
  const _ContentStageSelector({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('published', '发布'),
      ('testing', '测试'),
      ('draft', '草稿'),
    ];

    return Row(
      children: [
        Text(
          '内容阶段',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : const Color(0xFF666666),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A2332) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            children: stages.map((stage) {
              // 默认选中第一个（发布）
              final isSelected = stage.$1 == 'published';
              return GestureDetector(
                onTap: () {
                  // TODO: 实现阶段切换逻辑
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF3078F0)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    stage.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white70 : const Color(0xFF666666)),
                    ),
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
