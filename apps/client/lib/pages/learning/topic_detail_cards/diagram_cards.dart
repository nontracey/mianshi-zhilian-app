part of '../topic_detail_cards.dart';

// ── 图解卡片（自动识别布局）─────────────────────────────────

class DiagramCard extends StatelessWidget {
  const DiagramCard({required this.card});
  final LearningCard card;

  bool _isMermaidCard() {
    final format = card.format?.trim().toLowerCase();
    if (format == 'mermaid') return true;

    final source = MermaidDiagramData.cleanSource(card.content);
    if (source.isEmpty) return false;

    final firstLine = source
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');

    return RegExp(
      r'^(flowchart|graph)\s+(TB|TD|BT|LR|RL)\b',
      caseSensitive: false,
    ).hasMatch(firstLine);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final svgUrl = card.svgPath ?? card.asset;
    final isMermaid = _isMermaidCard();

    return WorkPanel(
      title: card.title,
      children: [
        if (isMermaid)
          MermaidDiagramView(card: card)
        else if (svgUrl != null && svgUrl.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.codeBgDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.32),
              ),
            ),
            child: svgUrl.endsWith('.svg')
                ? SvgPicture.network(
                    svgUrl,
                    width: double.infinity,
                    placeholderBuilder: (_) => Container(
                      height: 120,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorBuilder: (ctx, err, stack) => Text(
                      card.fallback ?? l10n.get('svg_loading_fail'),
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  )
                : Image.network(
                    svgUrl,
                    width: double.infinity,
                    errorBuilder: (ctx, err, stack) => Text(
                      card.fallback ?? l10n.get('image_picture_loading_fail'),
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
          )
        else
          SmartDiagram(card: card),
        if (!isMermaid && card.content.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(card.content, style: const TextStyle(height: 1.6)),
        ],
        if (!isMermaid && card.caption != null && card.caption!.isNotEmpty)
          _DiagramCaption(text: card.caption!),
      ],
    );
  }
}

// ── Mermaid 图解卡片 ────────────────────────────────────────

class MermaidDiagramView extends StatelessWidget {
  const MermaidDiagramView({super.key, required this.card});
  final LearningCard card;

  @override
  Widget build(BuildContext context) {
    final data = MermaidDiagramData.parse(card.content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.codeBgDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
          ),
          child: data.isRenderable
              ? _MermaidFlowDiagram(data: data)
              : AsciiDiagramView(content: data.source),
        ),
        if (card.caption != null && card.caption!.isNotEmpty)
          _DiagramCaption(text: card.caption!),
        if (card.fallback != null && card.fallback!.isNotEmpty) ...[
          const SizedBox(height: 10),
          _DiagramFallback(text: card.fallback!),
        ],
      ],
    );
  }
}

class MermaidDiagramData {
  const MermaidDiagramData({
    required this.source,
    required this.direction,
    required this.edges,
  });

  final String source;
  final String direction;
  final List<MermaidEdge> edges;

  bool get isRenderable => edges.isNotEmpty;
  bool get isHorizontal => direction == 'LR' || direction == 'RL';

  static String cleanSource(String content) {
    var source = content.replaceAll(r'\n', '\n').trim();
    if (!source.startsWith('```')) return source;

    final lines = source.split('\n');
    if (lines.isEmpty) return '';

    final body = lines.skip(1).toList();
    if (body.isNotEmpty && body.last.trim() == '```') {
      body.removeLast();
    }
    return body.join('\n').trim();
  }

  static MermaidDiagramData parse(String content) {
    final source = cleanSource(content);
    final statements = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('%%'))
        .expand((line) => line.split(';'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    var direction = 'TD';
    var startIndex = 0;
    if (statements.isNotEmpty) {
      final header = RegExp(
        r'^(?:flowchart|graph)\s+([A-Za-z]{2})\b',
        caseSensitive: false,
      ).firstMatch(statements.first);
      if (header != null) {
        direction = header.group(1)!.toUpperCase();
        startIndex = 1;
      }
    }

    final edges = <MermaidEdge>[];
    for (final statement in statements.skip(startIndex)) {
      final edge = _parseEdge(statement);
      if (edge != null) edges.add(edge);
    }

    // 收集所有已知的 node id → label 映射（label ≠ id 才算有效 label）
    final labelMap = <String, String>{};
    for (final edge in edges) {
      _collectLabel(edge.source, labelMap);
      _collectLabel(edge.target, labelMap);
    }

    // 回填：跨行引用只写 ID 不带 label 的节点，用已知 label 补上
    final filled = edges.map((edge) {
      return MermaidEdge(
        source: _fillLabel(edge.source, labelMap),
        target: _fillLabel(edge.target, labelMap),
        label: edge.label,
      );
    }).toList();

    return MermaidDiagramData(
      source: source,
      direction: direction,
      edges: filled,
    );
  }

  static void _collectLabel(MermaidNode node, Map<String, String> map) {
    if (node.label != node.id) {
      map[node.id] = node.label;
    }
  }

  static MermaidNode _fillLabel(MermaidNode node, Map<String, String> map) {
    final known = map[node.id];
    if (known != null && node.label == node.id) {
      return MermaidNode(id: node.id, label: known);
    }
    return node;
  }

  static MermaidEdge? _parseEdge(String statement) {
    final cleaned = statement
        .replaceAll(RegExp(r'\s+:::.*$'), '')
        .replaceAll(RegExp(r'\s+classDef\s+.*$'), '')
        .trim();

    final labeled = RegExp(
      r'(.+?)\s*--\s*([^>-]+?)\s*--?>\s*(.+)',
    ).firstMatch(cleaned);
    if (labeled != null) {
      return MermaidEdge(
        source: MermaidNode.parse(labeled.group(1)!),
        target: MermaidNode.parse(labeled.group(3)!),
        label: labeled.group(2)!.trim(),
      );
    }

    final match = RegExp(
      r'(.+?)\s*(-\.->|==>|-->|---)\s*(.+)',
    ).firstMatch(cleaned);
    if (match == null) return null;

    var targetToken = match.group(3)!.trim();
    String? label;
    final pipeLabel = RegExp(r'^\|(.+?)\|\s*(.+)$').firstMatch(targetToken);
    if (pipeLabel != null) {
      label = pipeLabel.group(1)!.trim();
      targetToken = pipeLabel.group(2)!.trim();
    }

    return MermaidEdge(
      source: MermaidNode.parse(match.group(1)!),
      target: MermaidNode.parse(targetToken),
      label: label,
    );
  }
}

class MermaidNode {
  const MermaidNode({required this.id, required this.label});

  final String id;
  final String label;

  static MermaidNode parse(String token) {
    var cleaned = token
        .trim()
        .replaceAll(RegExp(r'\s+:::.*$'), '')
        .replaceAll(RegExp(r'\s+$'), '');

    final match = RegExp(
      r'^([A-Za-z0-9_.:-]+)\s*(?:\[\s*"?(.+?)"?\s*\]|\(\s*"?(.+?)"?\s*\)|\{\s*"?(.+?)"?\s*\})?$',
    ).firstMatch(cleaned);

    if (match == null) {
      return MermaidNode(id: cleaned, label: _stripQuotes(cleaned));
    }

    final id = match.group(1)!;
    final label = match.group(2) ?? match.group(3) ?? match.group(4) ?? id;
    return MermaidNode(id: id, label: _stripQuotes(label));
  }

  static String _stripQuotes(String value) {
    var cleaned = value.trim();
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    return cleaned.trim();
  }
}

class MermaidEdge {
  const MermaidEdge({required this.source, required this.target, this.label});

  final MermaidNode source;
  final MermaidNode target;
  final String? label;
}

class _MermaidFlowDiagram extends StatelessWidget {
  const _MermaidFlowDiagram({required this.data});

  final MermaidDiagramData data;

  @override
  Widget build(BuildContext context) {
    final chain = _linearChain();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTypeTag(),
        const SizedBox(height: 16),
        if (chain != null)
          data.isHorizontal
              ? _buildHorizontalChain(chain)
              : _buildVerticalChain(chain)
        else
          _buildEdgeList(data.edges),
      ],
    );
  }

  Widget _buildTypeTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree, size: 16, color: AppColors.accent),
          SizedBox(width: 6),
          Text(
            'MERMAID',
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  List<MermaidEdge>? _linearChain() {
    if (data.edges.isEmpty) return null;

    final outgoing = <String, List<MermaidEdge>>{};
    final incoming = <String, int>{};
    for (final edge in data.edges) {
      outgoing.putIfAbsent(edge.source.id, () => []).add(edge);
      incoming[edge.target.id] = (incoming[edge.target.id] ?? 0) + 1;
      incoming.putIfAbsent(edge.source.id, () => incoming[edge.source.id] ?? 0);
    }

    if (outgoing.values.any((edges) => edges.length > 1)) return null;
    if (incoming.values.any((count) => count > 1)) return null;

    final starts = incoming.entries
        .where((entry) => entry.value == 0 && outgoing.containsKey(entry.key))
        .map((entry) => entry.key)
        .toList();
    if (starts.length != 1) return null;

    final ordered = <MermaidEdge>[];
    final visited = <String>{};
    var current = starts.single;
    while (outgoing[current] != null) {
      if (!visited.add(current)) return null;
      final edge = outgoing[current]!.single;
      ordered.add(edge);
      current = edge.target.id;
    }

    return ordered.length == data.edges.length ? ordered : null;
  }

  Widget _buildVerticalChain(List<MermaidEdge> chain) {
    return Column(
      children: [
        _buildNode(chain.first.source, AppColors.accent),
        for (final edge in chain) ...[
          _buildArrow(edge.label, Axis.vertical),
          _buildNode(edge.target, AppColors.success),
        ],
      ],
    );
  }

  Widget _buildHorizontalChain(List<MermaidEdge> chain) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: _buildNode(chain.first.source, AppColors.accent),
          ),
          for (final edge in chain) ...[
            _buildArrow(edge.label, Axis.horizontal),
            SizedBox(
              width: 180,
              child: _buildNode(edge.target, AppColors.success),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEdgeList(List<MermaidEdge> edges) {
    return Column(
      children: [
        for (var i = 0; i < edges.length; i++) ...[
          _buildEdgeRow(edges[i], i),
          if (i < edges.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildEdgeRow(MermaidEdge edge, int index) {
    final color = [
      AppColors.accent,
      AppColors.success,
      AppColors.warning,
      AppColors.categoryPurple,
    ][index % 4];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildNode(edge.source, color, compact: true)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_forward, color: color, size: 20),
                if (edge.label != null && edge.label!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      edge.label!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildNode(edge.target, color, compact: true)),
        ],
      ),
    );
  }

  Widget _buildNode(MermaidNode node, Color color, {bool compact = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        node.label,
        textAlign: TextAlign.center,
        softWrap: true,
        style: const TextStyle(
          color: Colors.white,
          height: 1.35,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildArrow(String? label, Axis axis) {
    final isHorizontal = axis == Axis.horizontal;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isHorizontal ? Icons.arrow_forward : Icons.arrow_downward,
          size: 20,
          color: AppColors.accent.withValues(alpha: 0.72),
        ),
        if (label != null && label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.accent.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isHorizontal ? 10 : 0,
        vertical: isHorizontal ? 0 : 8,
      ),
      child: child,
    );
  }
}

class _DiagramCaption extends StatelessWidget {
  const _DiagramCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(
            context,
          ).textTheme.bodySmall?.color?.withValues(alpha: 0.72),
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }
}

class _DiagramFallback extends StatelessWidget {
  const _DiagramFallback({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.accent.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFBFD6EA),
                height: 1.5,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 智能图解组件（自动识别内容类型）──────────────────────────

enum DiagramType { flow, hierarchy, compare, cycle }

class ContentFeatures {
  final bool isHierarchy;
  final bool isCompare;
  final bool isCycle;
  final bool isSequential;

  ContentFeatures({
    required this.isHierarchy,
    required this.isCompare,
    required this.isCycle,
    required this.isSequential,
  });
}

class HierarchyItem {
  final int level;
  final String text;
  HierarchyItem({required this.level, required this.text});
}

class SmartDiagram extends StatelessWidget {
  const SmartDiagram({required this.card});
  final LearningCard card;

  DiagramType _detectType() {
    final items = card.items;
    if (items.isEmpty) return DiagramType.flow;

    final features = _analyzeFeatures(items);

    if (features.isCycle) return DiagramType.cycle;
    if (features.isHierarchy) return DiagramType.hierarchy;
    if (features.isCompare) return DiagramType.compare;
    return DiagramType.flow;
  }

  ContentFeatures _analyzeFeatures(List<String> items) {
    int colonCount = 0;
    int arrowCount = 0;
    int sequentialCount = 0;
    int compareCount = 0;
    bool hasCycleIndicator = false;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final lower = item.toLowerCase();

      if (item.contains('：') || item.contains(':')) {
        colonCount++;
      }

      if (item.contains('→') || item.contains('->') || item.contains('=>')) {
        arrowCount++;
      }

      if (lower.contains('首先') ||
          lower.contains('然后') ||
          lower.contains('最后') ||
          lower.contains('接着') ||
          lower.contains('步骤') ||
          lower.contains('第') ||
          RegExp(r'^\d+[.、]').hasMatch(item)) {
        sequentialCount++;
      }

      if (lower.contains('vs') ||
          lower.contains('对比') ||
          lower.contains('比较') ||
          lower.contains('区别') ||
          lower.contains('优缺') ||
          lower.contains('利弊')) {
        compareCount++;
      }

      if (i == items.length - 1 && items.length >= 3) {
        final firstParts = items.first.split(RegExp(r'[：:、]'));
        final lastParts = item.split(RegExp(r'[：:、]'));
        if (firstParts.isNotEmpty && lastParts.isNotEmpty) {
          if (firstParts.first.contains(lastParts.first) ||
              lastParts.first.contains(firstParts.first)) {
            hasCycleIndicator = true;
          }
        }
      }
    }

    final totalItems = items.length;
    final colonRatio = colonCount / totalItems;
    final arrowRatio = arrowCount / totalItems;

    return ContentFeatures(
      isHierarchy: colonRatio >= 0.5,
      isCompare:
          compareCount >= 1 ||
          (totalItems >= 2 && totalItems % 2 == 0 && colonRatio >= 0.3),
      isCycle: hasCycleIndicator,
      isSequential: sequentialCount >= 2 || arrowRatio >= 0.3,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final type = _detectType();
    final items = card.items;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.codeBgDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTypeTag(type, l10n),
          const SizedBox(height: 16),
          switch (type) {
            DiagramType.flow => _buildFlowLayout(items),
            DiagramType.hierarchy => _buildHierarchyLayout(items),
            DiagramType.compare => _buildCompareLayout(items, l10n),
            DiagramType.cycle => _buildCycleLayout(items, l10n),
          },
          if (card.fallback != null && card.fallback!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildFallbackHint(),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeTag(DiagramType type, LocalizationProvider l10n) {
    final (icon, label, color) = switch (type) {
      DiagramType.flow => (
        Icons.linear_scale,
        l10n.get('flow_process_image'),
        AppColors.accent,
      ),
      DiagramType.hierarchy => (
        Icons.account_tree,
        l10n.get('structure_image'),
        AppColors.success,
      ),
      DiagramType.compare => (
        Icons.compare_arrows,
        l10n.get('comparison_image'),
        AppColors.warning,
      ),
      DiagramType.cycle => (
        Icons.autorenew,
        l10n.get('cycle_link_image'),
        AppColors.categoryPurple,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowLayout(List<String> items) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _buildFlowStep(i + 1, items[i]),
          if (i < items.length - 1) ...[
            const SizedBox(height: 8),
            Icon(
              Icons.arrow_downward,
              size: 20,
              color: AppColors.accent.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildFlowStep(int index, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.accent,
            child: Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHierarchyLayout(List<String> items) {
    final parsed = _parseHierarchy(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in parsed)
          Padding(
            padding: EdgeInsets.only(left: item.level * 20.0, bottom: 8),
            child: _buildHierarchyNode(item),
          ),
      ],
    );
  }

  List<HierarchyItem> _parseHierarchy(List<String> items) {
    final result = <HierarchyItem>[];

    for (final item in items) {
      int level = 0;
      String text = item;

      if (item.startsWith('定位') ||
          item.startsWith('概述') ||
          item.startsWith('总体')) {
        level = 0;
      } else if (item.startsWith('输入') ||
          item.startsWith('输出') ||
          item.startsWith('机制') ||
          item.startsWith('特点') ||
          item.startsWith('优点') ||
          item.startsWith('缺点')) {
        level = 1;
      } else if (item.startsWith('包含') ||
          item.startsWith('分为') ||
          item.startsWith('组成')) {
        level = 1;
      }

      result.add(HierarchyItem(level: level, text: text));
    }

    return result;
  }

  Widget _buildHierarchyNode(HierarchyItem item) {
    final colors = [
      AppColors.accent,
      AppColors.success,
      AppColors.warning,
      AppColors.categoryPurple,
    ];
    final color = colors[item.level % colors.length];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.level > 0) ...[
            Icon(
              Icons.subdirectory_arrow_right,
              size: 16,
              color: color.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              item.text,
              style: TextStyle(
                color: Colors.white.withValues(
                  alpha: item.level == 0 ? 1.0 : 0.85,
                ),
                fontWeight: item.level == 0 ? FontWeight.w700 : FontWeight.w500,
                fontSize: item.level == 0 ? 14 : 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompareLayout(List<String> items, LocalizationProvider l10n) {
    final half = (items.length / 2).ceil();
    final leftItems = items.sublist(0, half);
    final rightItems = items.sublist(half);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildCompareColumn(
            l10n.get('solution_a'),
            leftItems,
            AppColors.accent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildCompareColumn(
            l10n.get('solution_b'),
            rightItems,
            AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildCompareColumn(String title, List<String> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: color.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCycleLayout(List<String> items, LocalizationProvider l10n) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _buildCycleStep(i + 1, items[i]),
          if (i < items.length - 1) ...[
            const SizedBox(height: 4),
            Icon(
              Icons.arrow_downward,
              size: 18,
              color: AppColors.categoryPurple.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 4),
          ],
        ],
        if (items.length > 2) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.refresh, size: 18, color: AppColors.categoryPurple),
              const SizedBox(width: 8),
              Text(
                l10n.get('cycle_link_execute_action'),
                style: TextStyle(
                  color: AppColors.categoryPurple,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCycleStep(int index, String text) {
    const color = AppColors.categoryPurple;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.accent.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              card.fallback!,
              style: const TextStyle(
                color: Color(0xFFBFD6EA),
                height: 1.5,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── SVG 图解卡片 ─────────────────────────────────────────────

class SvgDiagramCard extends StatelessWidget {
  const SvgDiagramCard({required this.card});
  final LearningCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final svgData = card.svg;
    final svgAsset = card.asset;

    return WorkPanel(
      title: card.title,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.codeBgDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
          ),
          child: Column(
            children: [
              if (svgData != null && svgData.isNotEmpty)
                SvgPicture.string(
                  svgData,
                  width: double.infinity,
                  placeholderBuilder: (_) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (svgAsset != null && svgAsset.isNotEmpty)
                SvgPicture.network(
                  svgAsset,
                  width: double.infinity,
                  placeholderBuilder: (_) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorBuilder: (ctx, err, stack) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.warning,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          card.fallback ?? l10n.get('svg_loading_fail'),
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  height: 120,
                  alignment: Alignment.center,
                  child: Text(
                    card.fallback ??
                        l10n.get('temporary_no_image_understand_content'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (card.content.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(card.content, style: const TextStyle(height: 1.6)),
        ],
      ],
    );
  }
}
