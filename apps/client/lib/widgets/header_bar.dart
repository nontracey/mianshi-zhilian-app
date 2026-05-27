import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/content_provider.dart';

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
      _searchResults = allTopics.where((topic) {
        return topic.title.toLowerCase().contains(lowerQuery) ||
            topic.tags.any((tag) => tag.toLowerCase().contains(lowerQuery)) ||
            topic.summary.toLowerCase().contains(lowerQuery);
      }).take(8).toList();
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
              children: _searchResults.map((topic) => ListTile(
                dense: true,
                leading: const Icon(Icons.menu_book_outlined, size: 20),
                title: Text(
                  topic.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                  label: Text(topic.domain, style: const TextStyle(fontSize: 10)),
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
                  // 导航到知识点详情
                  if (widget.onTopicTap != null) {
                    widget.onTopicTap!(topic.id);
                  }
                },
              )).toList(),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            SizedBox(
              width: 280,
              child: SearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: '搜索知识点、标签、面试题',
                leading: const Icon(Icons.search),
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
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: widget.onProfile,
              icon: const Icon(Icons.person_outline),
            ),
          ],
        ),
      ),
    );
  }
}
