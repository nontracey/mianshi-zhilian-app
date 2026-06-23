part of '../topic_detail_cards.dart';

// Mermaid 5 色板 classDef → AppColors 映射
// ok/warn/fail 复用 categoryGreen/Amber/Red（色值精确匹配 #10B981/#F59E0B/#EF4444）
// async/highlight 是 AppColors 新增字段
const Map<String, Color> kMermaidClassColors = {
  'ok': AppColors.categoryGreen,
  'warn': AppColors.categoryAmber,
  'fail': AppColors.categoryRed,
  'async': AppColors.asyncState,
  'highlight': AppColors.highlight,
};

// ── SVG 渲染辅助（Web/CanvasKit 中文修复）──────────────────────
//
// flutter_svg 渲染 <text> 时不读取 ThemeData 字体，CanvasKit 默认字体无中文字形，
// 内容图解几乎全是中文 <text> → 中文变 tofu/空白，且不会抛错，导致降级链卡在空白 SVG。
// 修复：渲染前把 SVG 内所有 font-family 改写为打包字体 [kAppFontFamily]（含中文字形）。
// 另外这些 SVG 根节点用 width="100%"（相对尺寸），flutter_svg 量算会塌缩为 0 → 整图空白，
// 故去掉根节点 width/height，改由外层按 viewBox 宽高比布局。
String prepareDiagramSvg(String raw) {
  var svg = raw;

  // 1) 剥离 <marker> 定义与 marker-* 引用：flutter_svg/vector_graphics 不支持，
  //    含 marker 的 SVG 会渲染异常。剥掉只丢失箭头尖，连接线仍在。
  svg = svg.replaceAll(RegExp(r'<marker\b[^>]*>[\s\S]*?</marker>'), '');
  svg = svg.replaceAll(RegExp(r'\s*marker-(?:start|mid|end)\s*=\s*"[^"]*"'), '');
  svg = svg.replaceAll('context-stroke', 'currentColor');
  svg = svg.replaceAll('context-fill', 'currentColor');

  // 2) 把 <style> 里的 .class 规则内联成元素行内属性。
  //    flutter_svg 不支持 CSS class 选择器：很多图解把 fill/stroke/font 全放在
  //    `.section{fill:#fff}` 这类 class 里，不内联则元素拿不到填充 → 整图空白。
  final styleMatch = RegExp(r'<style[^>]*>([\s\S]*?)</style>').firstMatch(svg);
  if (styleMatch != null) {
    final rules = <String, String>{};
    for (final m in RegExp(r'\.([A-Za-z0-9_-]+)\s*\{([^}]*)\}')
        .allMatches(styleMatch.group(1)!)) {
      rules[m.group(1)!] = _cssDeclsToSvgAttrs(m.group(2)!);
    }
    svg = svg.replaceFirst(styleMatch.group(0)!, '');
    svg = svg.replaceAllMapped(RegExp(r'\sclass="([^"]*)"'), (m) {
      final attrs = <String>[];
      for (final name in m.group(1)!.split(RegExp(r'\s+'))) {
        final a = rules[name];
        if (a != null && a.isNotEmpty) attrs.add(a);
      }
      return attrs.isEmpty ? '' : ' ${attrs.join(' ')}';
    });
  }

  // 3) 行内 font-family → 打包字体（含中文字形），否则 CanvasKit 默认字体中文变 tofu
  svg = svg.replaceAll(
    RegExp(r'font-family\s*=\s*"[^"]*"'),
    'font-family="$kAppFontFamily"',
  );

  // 4) 根 <svg> 未声明 font-family 时注入默认值，覆盖未显式声明的 <text>
  final svgTagMatch = RegExp(r'<svg\b[^>]*>').firstMatch(svg);
  if (svgTagMatch != null && !svgTagMatch.group(0)!.contains('font-family')) {
    svg = svg.replaceFirst('<svg', '<svg font-family="$kAppFontFamily"');
  }
  return svg;
}

/// 把一组 CSS 声明（`fill:#fff;stroke:#ccc;font:700 16px X`）转成 SVG 行内
/// presentation 属性串。字体一律改写为打包字体 [kAppFontFamily]。
String _cssDeclsToSvgAttrs(String css) {
  final out = <String>[];
  for (final decl in css.split(';')) {
    final i = decl.indexOf(':');
    if (i < 0) continue;
    final key = decl.substring(0, i).trim();
    final val = decl.substring(i + 1).trim();
    if (val.isEmpty) continue;
    switch (key) {
      case 'fill':
      case 'stroke':
      case 'opacity':
      case 'fill-opacity':
      case 'stroke-opacity':
      case 'stroke-width':
      case 'stroke-dasharray':
      case 'stroke-linecap':
      case 'stroke-linejoin':
      case 'text-anchor':
      case 'letter-spacing':
      case 'dominant-baseline':
        out.add('$key="$val"');
        break;
      case 'font-size':
        out.add('font-size="${val.replaceAll('px', '')}"');
        break;
      case 'font-weight':
        out.add('font-weight="$val"');
        break;
      case 'font-style':
        out.add('font-style="$val"');
        break;
      case 'font-family':
        out.add('font-family="$kAppFontFamily"');
        break;
      case 'font':
        // shorthand: [weight] [size]px [families…]
        final sz = RegExp(r'(\d+(?:\.\d+)?)px').firstMatch(val);
        final wt = RegExp(r'\b([1-9]00)\b').firstMatch(val);
        if (wt != null) out.add('font-weight="${wt.group(1)}"');
        if (sz != null) out.add('font-size="${sz.group(1)}"');
        out.add('font-family="$kAppFontFamily"');
        break;
    }
  }
  return out.join(' ');
}

/// 解析 viewBox 得到宽高比（用于按卡片宽度等比布局，避免相对尺寸塌缩）
double? svgViewBoxAspect(String svg) {
  final m = RegExp(
    r'viewBox\s*=\s*"\s*[\d.eE+-]+[\s,]+[\d.eE+-]+[\s,]+([\d.eE+-]+)[\s,]+([\d.eE+-]+)',
  ).firstMatch(svg);
  if (m == null) return null;
  final w = double.tryParse(m.group(1)!);
  final h = double.tryParse(m.group(2)!);
  if (w == null || h == null || h <= 0 || w <= 0) return null;
  return w / h;
}

/// 已处理好的内联 SVG 渲染（统一供「内联源」与「网络源拉取后」复用）
class _PreparedSvgView extends StatelessWidget {
  const _PreparedSvgView({
    required this.svg,
    required this.onError,
    this.fallback,
  });
  final String svg;
  final VoidCallback onError;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final aspect = svgViewBoxAspect(svg) ?? (16 / 9);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.codeBgDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: AspectRatio(
        aspectRatio: aspect,
        child: SvgPicture.string(
          svg,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => Container(
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          errorBuilder: (ctx, err, stack) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onError());
            return Text(
              fallback ?? l10n.get('svg_loading_fail'),
              style: TextStyle(color: AppColors.warning, fontSize: 13),
            );
          },
        ),
      ),
    );
  }
}

/// 网络 SVG：先拉取文本 → UTF-8 解码 → 改写字体/尺寸 → SvgPicture.string 渲染。
/// 不直接用 SvgPicture.network，因为需要在渲染前改写 SVG 文本（修中文）。
class _CjkNetworkSvg extends StatefulWidget {
  const _CjkNetworkSvg({
    required this.url,
    required this.onError,
    this.fallback,
  });
  final String url;
  final VoidCallback onError;
  final String? fallback;

  @override
  State<_CjkNetworkSvg> createState() => _CjkNetworkSvgState();
}

class _CjkNetworkSvgState extends State<_CjkNetworkSvg> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_CjkNetworkSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = _load();
    }
  }

  Future<String> _load() async {
    final uri = Uri.parse(widget.url);
    // 加超时：请求挂死时及时失败 → 触发 onError 降级到 mermaid/文本，而非一直转圈
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw http.ClientException('HTTP ${resp.statusCode}', uri);
    }
    // 响应头无 charset，必须显式按 UTF-8 解码，否则中文按 latin1 解出会变乱码
    return prepareDiagramSvg(utf8.decode(resp.bodyBytes));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onError());
          return Text(
            widget.fallback ?? l10n.get('svg_loading_fail'),
            style: TextStyle(color: AppColors.warning, fontSize: 13),
          );
        }
        if (!snap.hasData) {
          return Container(
            width: double.infinity,
            height: 140,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.codeBgDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
            ),
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return _PreparedSvgView(
          svg: snap.data!,
          onError: widget.onError,
          fallback: widget.fallback,
        );
      },
    );
  }
}

// ── 图解卡片（自动识别布局）─────────────────────────────────

class DiagramCard extends StatelessWidget {
  const DiagramCard({required this.card});
  final LearningCard card;

  bool _isMermaidSource(CardSource source) => source.kind == 'mermaid';

  String _assetUrl(BuildContext context, String path) {
    final uri = Uri.tryParse(path);
    if (uri?.hasScheme == true) return path;
    final base = context.read<ContentProvider>().contentBaseUrl.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    return '$base/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  @override
  Widget build(BuildContext context) {
    final sources = card.toSources();
    Widget content;
    try {
      content = _SourceChainView(
        card: card,
        sources: sources,
        assetUrl: (path) => _assetUrl(context, path),
        isMermaidSource: _isMermaidSource,
      );
    } catch (_) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.content.isNotEmpty)
            Text(card.content, style: const TextStyle(height: 1.6)),
          if (card.fallback != null && card.fallback!.isNotEmpty)
            _DiagramFallback(text: card.fallback!),
        ],
      );
    }
    return WorkPanel(
      title: card.title,
      children: [
        content,
        if (card.caption != null && card.caption!.isNotEmpty)
          _DiagramCaption(text: card.caption!),
      ],
    );
  }
}

class _SourceChainView extends StatefulWidget {
  const _SourceChainView({
    required this.card,
    required this.sources,
    required this.assetUrl,
    required this.isMermaidSource,
  });

  final LearningCard card;
  final List<CardSource> sources;
  final String Function(String path) assetUrl;
  final bool Function(CardSource source) isMermaidSource;

  @override
  State<_SourceChainView> createState() => _SourceChainViewState();
}

class _SourceChainViewState extends State<_SourceChainView> {
  int index = 0;

  void _next() {
    if (!mounted) return;
    if (index + 1 < widget.sources.length) {
      setState(() => index += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources.isEmpty) return SmartDiagram(card: widget.card);
    return _buildSource(widget.sources[index], allowErrorAdvance: true);
  }

  Widget _buildSource(CardSource source, {required bool allowErrorAdvance}) {
    if (widget.isMermaidSource(source)) {
      return MermaidDiagramView(
        card: widget.card,
        content: source.content ?? '',
      );
    }
    if (source.kind == 'text') {
      return Text(
        source.content ?? widget.card.fallback ?? '',
        style: const TextStyle(height: 1.6),
      );
    }
    if (source.kind == 'svg') {
      final onError = allowErrorAdvance ? _next : () {};
      final inline = source.content?.trim();
      if (inline != null && inline.isNotEmpty) {
        if (inline.startsWith('<svg')) {
          // 内联 SVG：同样改写字体后渲染（修中文）
          return _PreparedSvgView(
            svg: prepareDiagramSvg(inline),
            fallback: widget.card.fallback,
            onError: onError,
          );
        }
        return _buildAsset(widget.assetUrl(inline), onError);
      }
      if (source.path != null) {
        return _buildAsset(widget.assetUrl(source.path!), onError);
      }
    }
    if (allowErrorAdvance)
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
    return Text(
      widget.card.fallback ?? '',
      style: TextStyle(color: AppColors.warning, fontSize: 13),
    );
  }

  /// 资源 URL 分流：.svg 走「拉取→改字体→渲染」管线（修中文）；其余按位图加载
  Widget _buildAsset(String url, VoidCallback onError) {
    if (url.toLowerCase().endsWith('.svg')) {
      return _CjkNetworkSvg(
        url: url,
        fallback: widget.card.fallback,
        onError: onError,
      );
    }
    return _AssetImageView(
      url: url,
      fallback: widget.card.fallback,
      onError: onError,
    );
  }
}

/// 位图资源（png/jpg 等）加载，SVG 不走这里
class _AssetImageView extends StatelessWidget {
  const _AssetImageView({
    required this.url,
    required this.onError,
    this.fallback,
  });
  final String url;
  final VoidCallback onError;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.codeBgDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: Image.network(
        url,
        width: double.infinity,
        errorBuilder: (ctx, err, stack) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onError());
          return Text(
            fallback ?? l10n.get('image_picture_loading_fail'),
            style: TextStyle(color: AppColors.warning, fontSize: 13),
          );
        },
      ),
    );
  }
}

// ── Mermaid 图解卡片 ────────────────────────────────────────

/// 所有 mermaid 图种的抽象基类：flowchart / stateDiagram / sequenceDiagram
abstract class MermaidDiagram {
  String get source;
  bool get isRenderable;
}

/// 顶层 dispatcher：按首行 header 关键字分派到对应图种 parser
/// flowchart|graph → MermaidDiagramData.parse；stateDiagram/sequenceDiagram 暂走 flowchart parse（edges 空 → ASCII 兜底），Step 5/6 填充真分支
MermaidDiagram parseMermaidDiagram(String content) {
  final source = MermaidDiagramData.cleanSource(content);
  final firstLine = source
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (RegExp(
    r'^stateDiagram(-v2)?\b',
    caseSensitive: false,
  ).hasMatch(firstLine)) {
    return StateDiagramData.parse(content);
  }
  if (RegExp(r'^sequenceDiagram\b', caseSensitive: false).hasMatch(firstLine)) {
    return SequenceDiagramData.parse(content);
  }
  return MermaidDiagramData.parse(content);
}

class MermaidDiagramView extends StatelessWidget {
  const MermaidDiagramView({super.key, required this.card, this.content});
  final LearningCard card;
  final String? content;

  @override
  Widget build(BuildContext context) {
    final source = content ?? card.content;
    final diagram = parseMermaidDiagram(source);

    final Widget diagramWidget;
    if (diagram is MermaidDiagramData) {
      diagramWidget = diagram.isRenderable
          ? _MermaidFlowDiagram(data: diagram)
          : AsciiDiagramView(content: diagram.source);
    } else if (diagram is StateDiagramData) {
      diagramWidget = diagram.isRenderable
          ? _StateDiagramView(data: diagram)
          : AsciiDiagramView(content: diagram.source);
    } else if (diagram is SequenceDiagramData) {
      diagramWidget = diagram.isRenderable
          ? _SequenceDiagramView(data: diagram)
          : AsciiDiagramView(content: diagram.source);
    } else {
      diagramWidget = AsciiDiagramView(content: diagram.source);
    }

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
          child: diagramWidget,
        ),
        if (card.fallback != null && card.fallback!.isNotEmpty) ...[
          const SizedBox(height: 10),
          _DiagramFallback(text: card.fallback!),
        ],
      ],
    );
  }
}

class MermaidDiagramData implements MermaidDiagram {
  const MermaidDiagramData({
    required this.source,
    required this.direction,
    required this.edges,
    this.subgraphs = const [],
  });

  @override
  final String source;
  final String direction;
  final List<MermaidEdge> edges;
  final List<MermaidSubgraph> subgraphs;

  @override
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
    final subgraphStack = <_SubgraphFrame>[];
    final topSubgraphs = <MermaidSubgraph>[];
    final subgraphOpenRe = RegExp(r'^subgraph\s+(\S+)(?:\s+\[([^\]]*)\])?\s*$');
    for (final statement in statements.skip(startIndex)) {
      final subOpen = subgraphOpenRe.firstMatch(statement);
      if (subOpen != null) {
        final id = subOpen.group(1)!;
        final title = subOpen.group(2) ?? id;
        subgraphStack.add(_SubgraphFrame(id: id, title: title));
        continue;
      }
      if (RegExp(r'^end$').hasMatch(statement)) {
        if (subgraphStack.isNotEmpty) {
          final frame = subgraphStack.removeLast();
          final sg = frame.toSubgraph();
          if (subgraphStack.isNotEmpty) {
            subgraphStack.last.children.add(sg);
          } else {
            topSubgraphs.add(sg);
          }
        }
        continue;
      }
      final edge = _parseEdge(statement);
      if (edge != null) {
        edges.add(edge);
        if (subgraphStack.isNotEmpty) {
          subgraphStack.last.nodeIds.add(edge.source.id);
          subgraphStack.last.nodeIds.add(edge.target.id);
        }
      }
    }

    // 收集所有已知的 node id → label 映射（label ≠ id 才算有效 label）
    final labelMap = <String, String>{};
    for (final edge in edges) {
      _collectLabel(edge.source, labelMap);
      _collectLabel(edge.target, labelMap);
    }

    // 收集 class 声明：class A,B,C ok 或 class A ok（5 色板 classDef 应用）
    final idToClass = <String, String>{};
    final classDeclRe = RegExp(
      r'^class\s+([A-Za-z0-9_,\s]+?)\s+([A-Za-z0-9_-]+)\s*$',
    );
    for (final statement in statements.skip(startIndex)) {
      final m = classDeclRe.firstMatch(statement);
      if (m != null) {
        final ids = m
            .group(1)!
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        final cls = m.group(2)!;
        for (final id in ids) {
          idToClass[id] = cls;
        }
      }
    }

    // 回填：跨行引用只写 ID 不带 label 的节点，用已知 label 补上；className 同理回填
    final filled = edges.map((edge) {
      return MermaidEdge(
        source: _fillLabel(_fillClass(edge.source, idToClass), labelMap),
        target: _fillLabel(_fillClass(edge.target, idToClass), labelMap),
        label: edge.label,
      );
    }).toList();

    return MermaidDiagramData(
      source: source,
      direction: direction,
      edges: filled,
      subgraphs: topSubgraphs,
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
      return MermaidNode(id: node.id, label: known, className: node.className);
    }
    return node;
  }

  static MermaidNode _fillClass(MermaidNode node, Map<String, String> map) {
    final known = map[node.id];
    if (known != null && node.className == null) {
      return MermaidNode(id: node.id, label: node.label, className: known);
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
  const MermaidNode({required this.id, required this.label, this.className});

  final String id;
  final String label;
  final String? className;

  static MermaidNode parse(String token) {
    var cleaned = token.trim();
    // 提取 :::className（5 色板 classDef 应用）后再 strip
    // mermaid 语法 A:::ok 紧贴，不要求 ::: 前有空白
    String? className;
    final classMatch = RegExp(r':::([A-Za-z0-9_-]+)\s*$').firstMatch(cleaned);
    if (classMatch != null) {
      className = classMatch.group(1);
      cleaned = cleaned.replaceAll(RegExp(r':::[A-Za-z0-9_-]+\s*$'), '');
    }
    cleaned = cleaned.replaceAll(RegExp(r'\s+$'), '');

    final match = RegExp(
      r'^([A-Za-z0-9_.:-]+)\s*(?:\[\s*"?(.+?)"?\s*\]|\(\s*"?(.+?)"?\s*\)|\{\s*"?(.+?)"?\s*\})?$',
    ).firstMatch(cleaned);

    if (match == null) {
      return MermaidNode(
        id: cleaned,
        label: _stripQuotes(cleaned),
        className: className,
      );
    }

    final id = match.group(1)!;
    final label = match.group(2) ?? match.group(3) ?? match.group(4) ?? id;
    return MermaidNode(
      id: id,
      label: _stripQuotes(label),
      className: className,
    );
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

/// flowchart subgraph 分组（支持嵌套≤2层）
class MermaidSubgraph {
  const MermaidSubgraph({
    required this.id,
    required this.title,
    this.nodeIds = const [],
    this.children = const [],
  });

  final String id;
  final String title;
  final List<String> nodeIds;
  final List<MermaidSubgraph> children;
}

/// parse 时使用的可变 subgraph 帧
class _SubgraphFrame {
  _SubgraphFrame({required this.id, required this.title});

  final String id;
  final String title;
  final Set<String> nodeIds = {};
  final List<MermaidSubgraph> children = [];

  MermaidSubgraph toSubgraph() => MermaidSubgraph(
    id: id,
    title: title,
    nodeIds: List.unmodifiable(nodeIds),
    children: List.unmodifiable(children),
  );
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
        if (data.subgraphs.isNotEmpty)
          _buildGroupedLayout()
        else if (chain != null)
          data.isHorizontal
              ? _buildHorizontalChain(chain)
              : _buildVerticalChain(chain)
        else
          _buildEdgeList(data.edges),
      ],
    );
  }

  /// subgraph 分组渲染：每个 subgraph 画带标题边框，组内边归到最小公共组，跨组边在底部平铺
  Widget _buildGroupedLayout() {
    final topGroups = data.subgraphs;

    bool inSubtree(String nodeId, MermaidSubgraph sg) {
      if (sg.nodeIds.contains(nodeId)) return true;
      return sg.children.any((c) => inSubtree(nodeId, c));
    }

    List<MermaidEdge> edgesForSubgraph(MermaidSubgraph sg) {
      return data.edges.where((e) {
        if (!inSubtree(e.source.id, sg) || !inSubtree(e.target.id, sg))
          return false;
        // 不归到 sg 的任何子组（子组优先）
        for (final child in sg.children) {
          if (inSubtree(e.source.id, child) && inSubtree(e.target.id, child)) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    final crossEdges = data.edges.where((e) {
      for (final sg in topGroups) {
        if (inSubtree(e.source.id, sg) && inSubtree(e.target.id, sg))
          return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final sg in topGroups) ...[
          _buildSubgraphBox(sg, edgesForSubgraph),
          const SizedBox(height: 12),
        ],
        if (crossEdges.isNotEmpty) ...[
          for (var i = 0; i < crossEdges.length; i++) ...[
            _buildEdgeRow(crossEdges[i], i),
            if (i < crossEdges.length - 1) const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  Widget _buildSubgraphBox(
    MermaidSubgraph sg,
    List<MermaidEdge> Function(MermaidSubgraph) edgesFor,
  ) {
    final ownEdges = edgesFor(sg);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sg.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          for (final child in sg.children) ...[
            _buildSubgraphBox(child, edgesFor),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < ownEdges.length; i++) ...[
            _buildEdgeRow(ownEdges[i], i),
            if (i < ownEdges.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
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

  Color _resolveNodeColor(MermaidNode node, Color fallback) {
    if (node.className != null &&
        kMermaidClassColors.containsKey(node.className)) {
      return kMermaidClassColors[node.className]!;
    }
    return fallback;
  }

  Widget _buildNode(MermaidNode node, Color color, {bool compact = false}) {
    final resolved = _resolveNodeColor(node, color);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resolved.withValues(alpha: 0.34)),
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

  String _assetUrl(BuildContext context, String path) {
    final uri = Uri.tryParse(path);
    if (uri?.hasScheme == true) return path;
    final base = context.read<ContentProvider>().contentBaseUrl.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    return '$base/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final svgData = card.svg;
    final svgAsset = card.asset;

    // 与 DiagramCard 走同一套「改写字体 + 受限尺寸」管线，保证中文渲染
    final Widget media;
    if (svgData != null && svgData.isNotEmpty) {
      media = _PreparedSvgView(
        svg: prepareDiagramSvg(svgData),
        onError: () {},
        fallback: card.fallback,
      );
    } else if (svgAsset != null && svgAsset.isNotEmpty) {
      media = _CjkNetworkSvg(
        url: _assetUrl(context, svgAsset),
        onError: () {},
        fallback: card.fallback,
      );
    } else {
      media = Container(
        width: double.infinity,
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.codeBgDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
        ),
        child: Text(
          card.fallback ?? l10n.get('temporary_no_image_understand_content'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
      );
    }

    return WorkPanel(
      title: card.title,
      children: [
        media,
        if (card.content.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(card.content, style: const TextStyle(height: 1.6)),
        ],
      ],
    );
  }
}
