part of '../topic_detail_cards.dart';

/// SVG 内中文字体族名（pubspec.yaml 中注册的 AppSans 子集字体）。
/// 仅用于 SVG 文本改写，不注入 ThemeData，避免全局滚动卡顿。
const String _kSvgFontFamily = 'AppSans';

// ── 图解全屏查看 ─────────────────────────────────────────────

/// 在图解区域右上角叠加全屏按钮，点击后以全屏模式查看图解（支持缩放拖拽）。
/// [child] 是内联显示的视图（不带 InteractiveViewer）。
/// [fullscreenContent] 是全屏专用的原始图解内容（不含 InteractiveViewer，由全屏页自行包裹）。
/// [fullscreenBuilder] 延迟构建全屏内容——仅在用户点击全屏时才调用，避免每次 build 都
/// 创建两份 SvgPicture.string（省去未打开全屏时的无用解析开销）。
class DiagramWithFullscreen extends StatelessWidget {
  const DiagramWithFullscreen({
    super.key,
    required this.child,
    this.fullscreenContent,
    this.fullscreenBuilder,
    this.title,
  }) : assert(
          fullscreenContent != null || fullscreenBuilder != null,
          'Either fullscreenContent or fullscreenBuilder must be provided',
        );
  final Widget child;
  final Widget? fullscreenContent;
  final Widget Function(BuildContext)? fullscreenBuilder;
  final String? title;

  void _openFullscreen(BuildContext context) {
    final content = fullscreenBuilder?.call(context) ?? fullscreenContent!;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => _DiagramFullscreenView(
          content: content,
          title: title,
        ),
        transitionsBuilder: (_, animation, __, page) {
          return FadeTransition(opacity: animation, child: page);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _openFullscreen(context),
          child: child,
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.black.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openFullscreen(context),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 全屏图解查看页。使用独立的 InteractiveViewer，不复用内联 widget 树，
/// 避免嵌套 InteractiveViewer 抢手势。
///
/// 手势设计：内容宽度固定为视口宽度（避免 mermaid 节点 `width:double.infinity`
/// 在无界约束下塌缩/溢出），高度按内容自然展开 → 长图可上下拖动。双击在点击处
/// 放大/复位；boundaryMargin 取有限值，避免图被拖出屏幕后找不回来。
class _DiagramFullscreenView extends StatefulWidget {
  const _DiagramFullscreenView({required this.content, this.title});
  final Widget content;
  final String? title;

  @override
  State<_DiagramFullscreenView> createState() => _DiagramFullscreenViewState();
}

class _DiagramFullscreenViewState extends State<_DiagramFullscreenView> {
  static const double _kMinScale = 0.5;
  static const double _kMaxScale = 8.0;

  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;
  Size _viewport = Size.zero;
  double _scale = 1.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 以视口中心为锚点设置绝对缩放（按钮缩放走这里，跨平台可靠，不与 InteractiveViewer
  /// 的拖动/捏合手势在手势竞技场里抢占）。复位即 scale=1 → 单位矩阵。
  void _applyScale(double scale) {
    final s = scale.clamp(_kMinScale, _kMaxScale);
    final tx = -_viewport.width / 2 * (s - 1);
    final ty = -_viewport.height / 2 * (s - 1);
    setState(() {
      _scale = s;
      _controller.value = Matrix4(
        s, 0, 0, 0, //
        0, s, 0, 0, //
        0, 0, 1, 0, //
        tx, ty, 0, 1, //
      );
    });
  }

  /// 双击：以点击点为中心放大 / 复位（触摸端的便捷手势，桌面端用工具栏按钮）。
  void _handleDoubleTap() {
    if (_controller.value.getMaxScaleOnAxis() > 1.01) {
      _applyScale(1.0);
      return;
    }
    final pos = _doubleTapDetails?.localPosition;
    if (pos == null) {
      _applyScale(2.5);
      return;
    }
    const scale = 2.5;
    final tx = -pos.dx * (scale - 1);
    final ty = -pos.dy * (scale - 1);
    setState(() {
      _scale = scale;
      _controller.value = Matrix4(
        scale, 0, 0, 0, //
        0, scale, 0, 0, //
        0, 0, 1, 0, //
        tx, ty, 0, 1, //
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: widget.title != null
            ? Text(widget.title!, style: const TextStyle(fontSize: 16))
            : null,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: _scale <= _kMinScale + 0.001
                ? null
                : () => _applyScale(_scale / 1.5),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _scale >= _kMaxScale - 0.001
                ? null
                : () => _applyScale(_scale * 1.5),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen_rounded),
            onPressed: _scale == 1.0 ? null : () => _applyScale(1.0),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onDoubleTapDown: (d) => _doubleTapDetails = d,
            onDoubleTap: _handleDoubleTap,
            // web 端：浏览器拦截滚轮事件，InteractiveViewer 收不到缩放信号，
            // 需要 Listener 手动处理。native 端不加，否则触控板/鼠标滚轮会双重缩放。
            child: _buildInteractiveViewer(constraints),
          );
        },
      ),
    );
  }

  Widget _buildInteractiveViewer(BoxConstraints constraints) {
    final viewer = InteractiveViewer(
      transformationController: _controller,
      maxScale: _kMaxScale,
      minScale: _kMinScale,
      constrained: false,
      boundaryMargin: EdgeInsets.symmetric(
        horizontal: constraints.maxWidth,
        vertical: constraints.maxHeight,
      ),
      child: SizedBox(
        width: constraints.maxWidth,
        child: widget.content,
      ),
    );

    // web 端需要 Listener 拦截滚轮事件手动缩放，
    // native 端 InteractiveViewer 自行处理触控板/鼠标滚轮，不加 Listener 避免双重缩放。
    if (kIsWeb) {
      return Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final delta = event.scrollDelta.dy;
            final factor = delta > 0 ? 0.9 : 1.1;
            final newScale =
                (_scale * factor).clamp(_kMinScale, _kMaxScale);
            if (newScale == _scale) return;
            final pos = event.localPosition;
            final focal = MatrixUtils.transformPoint(
              Matrix4.inverted(_controller.value),
              pos,
            );
            final tx = focal.dx * (_scale - newScale);
            final ty = focal.dy * (_scale - newScale);
            final m = _controller.value.clone()
              ..translate(tx, ty)
              ..scale(newScale / _scale);
            setState(() {
              _scale = newScale;
              _controller.value = m;
            });
          }
        },
        child: viewer,
      );
    }
    return viewer;
  }
}

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
// 修复：渲染前把 SVG 内所有 font-family 改写为打包字体 [_kSvgFontFamily]（含中文字形）。
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
    'font-family="$_kSvgFontFamily"',
  );

  // 4) 根 <svg> 未声明 font-family 时注入默认值，覆盖未显式声明的 <text>
  final svgTagMatch = RegExp(r'<svg\b[^>]*>').firstMatch(svg);
  if (svgTagMatch != null && !svgTagMatch.group(0)!.contains('font-family')) {
    svg = svg.replaceFirst('<svg', '<svg font-family="$_kSvgFontFamily"');
  }
  return svg;
}

/// 把一组 CSS 声明（`fill:#fff;stroke:#ccc;font:700 16px X`）转成 SVG 行内
/// presentation 属性串。字体一律改写为打包字体 [_kSvgFontFamily]。
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
        out.add('font-family="$_kSvgFontFamily"');
        break;
      case 'font':
        // shorthand: [weight] [size]px [families…]
        final sz = RegExp(r'(\d+(?:\.\d+)?)px').firstMatch(val);
        final wt = RegExp(r'\b([1-9]00)\b').firstMatch(val);
        if (wt != null) out.add('font-weight="${wt.group(1)}"');
        if (sz != null) out.add('font-size="${sz.group(1)}"');
        out.add('font-family="$_kSvgFontFamily"');
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

/// 已处理好的内联 SVG 渲染（统一供「内联源」与「网络源拉取后」复用）。
/// 内联视图不使用 InteractiveViewer（避免与 ListView 滚动冲突），
/// 全屏按钮提供独立的缩放拖拽能力。
class _PreparedSvgView extends StatelessWidget {
  const _PreparedSvgView({
    required this.svg,
    required this.onError,
    this.fallback,
  });
  final String svg;
  final VoidCallback onError;
  final String? fallback;

  Widget _buildSvgContent(
    BuildContext context, {
    required bool forFullscreen,
    required LocalizationProvider l10n,
  }) {
    final aspect = svgViewBoxAspect(svg) ?? (16 / 9);
    final svgWidget = AspectRatio(
      aspectRatio: aspect,
      child: SvgPicture.string(
        svg,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Container(
          alignment: Alignment.center,
          child: Icon(
            Icons.image_outlined,
            size: 24,
            color: AppColors.accent.withValues(alpha: 0.3),
          ),
        ),
        errorBuilder: (ctx, err, stack) {
          if (!forFullscreen) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onError());
          }
          return Text(
            fallback ?? l10n.get('svg_loading_fail'),
            style: TextStyle(
              color: forFullscreen ? Colors.white : AppColors.warning,
              fontSize: 13,
            ),
          );
        },
      ),
    );

    if (forFullscreen) {
      return svgWidget;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.codeBgDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: svgWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return DiagramWithFullscreen(
      child: _buildSvgContent(context, forFullscreen: false, l10n: l10n),
      fullscreenBuilder: (ctx) {
        // fullscreenBuilder 在点击事件中调用（非 build 阶段），必须 listen: false
        final fsL10n = Provider.of<LocalizationProvider>(ctx, listen: false);
        return _buildSvgContent(ctx, forFullscreen: true, l10n: fsL10n);
      },
    );
  }
}

/// 轻量 LRU 缓存：按条目数（可选再按总权重 [maxWeight]）淘汰最久未使用项，
/// 避免会话期内浏览大量图片/SVG 时内存无上限增长。
/// 重载 [] / []= 以便与原 Map 用法保持一致；读命中会把该项刷新为最近使用。
class _LruCache<V> {
  _LruCache({required this.maxEntries, this.maxWeight, this.weigh});

  final int maxEntries;
  final int? maxWeight;
  final int Function(V value)? weigh;

  // map 字面量即 LinkedHashMap，按插入顺序遍历，keys.first 即最久未使用。
  final Map<String, V> _store = {};
  int _weight = 0;

  V? operator [](String key) {
    final v = _store.remove(key);
    if (v != null) _store[key] = v; // 移到末尾 = 最近使用
    return v;
  }

  void operator []=(String key, V value) {
    final old = _store.remove(key);
    if (old != null) _weight -= weigh?.call(old) ?? 0;
    _store[key] = value;
    _weight += weigh?.call(value) ?? 0;
    while (_store.isNotEmpty &&
        (_store.length > maxEntries ||
            (maxWeight != null && _weight > maxWeight!))) {
      final removed = _store.remove(_store.keys.first);
      if (removed != null) _weight -= weigh?.call(removed) ?? 0;
    }
  }

  void clear() {
    _store.clear();
    _weight = 0;
  }
}

/// 把上面两个进程内缓存的清理注册进 [ContentAssetCache]，使其与磁盘缓存、
/// topic 缓存一起被清（内容版本变更 / 用户主动清缓存时图也换/清）。
/// 幂等：首个 SVG/位图开始加载前调用一次即可。
bool _assetMemCacheRegistered = false;
void _ensureAssetMemCacheRegistered() {
  if (_assetMemCacheRegistered) return;
  _assetMemCacheRegistered = true;
  ContentAssetCache.instance.registerMemoryCacheClearer(() {
    _preparedNetworkSvgStringCache.clear();
    _networkImageByteCache.clear();
  });
}

/// 已拉取并改写好的网络 SVG 字符串缓存（按 URL → 已解码 SVG 文本）。
/// 滚动导致 widget 被 dispose 再重建时直接命中缓存，不再触发网络请求。
final _LruCache<String> _preparedNetworkSvgStringCache = _LruCache(
  maxEntries: 64,
);

/// 网络 SVG：先拉取文本 → UTF-8 解码 → 改写字体/尺寸 → SvgPicture.string 渲染。
/// 不直接用 SvgPicture.network，因为需要在渲染前改写 SVG 文本（修中文）。
class _CjkNetworkSvg extends StatefulWidget {
  const _CjkNetworkSvg({
    required this.urls,
    required this.onError,
    this.fallback,
  });
  final List<String> urls;
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
    _ensureAssetMemCacheRegistered();
    _future = _load();
  }

  @override
  void didUpdateWidget(_CjkNetworkSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    // urls 每次 build 都是新 List 实例，必须按内容比较，
    // 否则已缓存的图也会被重新 _load()，FutureBuilder 闪一帧占位图。
    if (!listEquals(oldWidget.urls, widget.urls)) {
      _future = _load();
    }
  }

  Future<String> _load() {
    final cacheKey = widget.urls.first;
    // 1. 命中内存缓存 → 同步返回，不发网络请求
    final cached = _preparedNetworkSvgStringCache[cacheKey];
    if (cached != null) return Future.value(cached);

    // 2. 文件缓存 → 网络
    return _loadFromCacheOrNetwork(cacheKey);
  }

  Future<String> _loadFromCacheOrNetwork(String cacheKey) async {
    final fileCached = await ContentAssetCache.instance.readString(cacheKey);
    if (fileCached != null) {
      _preparedNetworkSvgStringCache[cacheKey] = fileCached;
      return fileCached;
    }
    final v = await _fetchAndPrepare(widget.urls);
    _preparedNetworkSvgStringCache[cacheKey] = v;
    await ContentAssetCache.instance.writeString(cacheKey, v);
    return v;
  }

  static Future<String> _fetchAndPrepare(List<String> urls) async {
    final first = urls.first;
    if (first.startsWith('data:')) {
      return prepareDiagramSvg(utf8.decode(UriData.parse(first).contentAsBytes()));
    }
    Object? lastError;
    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        final resp = await http.get(uri).timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) {
          lastError = http.ClientException('HTTP ${resp.statusCode}', uri);
          continue;
        }
        return prepareDiagramSvg(utf8.decode(resp.bodyBytes));
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? http.ClientException('All SVG URLs failed: $urls');
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
            child: Icon(
              Icons.image_outlined,
              size: 28,
              color: AppColors.accent.withValues(alpha: 0.4),
            ),
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

  List<String> _assetUrls(BuildContext context, String path) {
    return context.read<ContentProvider>().resolveContentUrls(path);
  }

  @override
  Widget build(BuildContext context) {
    final sources = card.toSources();
    Widget content;
    try {
      content = _SourceChainView(
        card: card,
        sources: sources,
        assetUrls: (path) => _assetUrls(context, path),
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
    required this.assetUrls,
    required this.isMermaidSource,
  });

  final LearningCard card;
  final List<CardSource> sources;
  final List<String> Function(String path) assetUrls;
  final bool Function(CardSource source) isMermaidSource;

  @override
  State<_SourceChainView> createState() => _SourceChainViewState();
}

class _SourceChainViewState extends State<_SourceChainView> {
  int index = 0;
  // 缓存已处理的 SVG 文本，避免每次 build 重复解析
  String? _cachedRawSvg;
  String? _cachedPreparedSvg;

  void _next() {
    if (!mounted) return;
    if (index + 1 < widget.sources.length) {
      setState(() => index += 1);
    }
  }

  String _prepareSvg(String raw) {
    if (raw == _cachedRawSvg && _cachedPreparedSvg != null) {
      return _cachedPreparedSvg!;
    }
    _cachedRawSvg = raw;
    _cachedPreparedSvg = prepareDiagramSvg(raw);
    return _cachedPreparedSvg!;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources.isEmpty) return SmartDiagram(card: widget.card);
    return _buildSource(widget.sources[index], allowErrorAdvance: true);
  }

  Widget _buildSource(CardSource source, {required bool allowErrorAdvance}) {
    if (widget.isMermaidSource(source)) {
      return RepaintBoundary(
        child: MermaidDiagramView(
          card: widget.card,
          content: source.content ?? '',
        ),
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
          return RepaintBoundary(
            child: _PreparedSvgView(
              svg: _prepareSvg(inline),
              fallback: widget.card.fallback,
              onError: onError,
            ),
          );
        }
        return _buildAsset(widget.assetUrls(inline), onError);
      }
      if (source.path != null) {
        return _buildAsset(widget.assetUrls(source.path!), onError);
      }
    }
    if (allowErrorAdvance)
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
    return Text(
      widget.card.fallback ?? '',
      style: TextStyle(color: AppColors.warning, fontSize: 13),
    );
  }

  /// 资源 URL 分流：
  /// - `data:` 内嵌资源（base64 图片/SVG）必须就地解码——native 端（Android/桌面）
  ///   不能把 data URI 丢给 http.get/Image.network（会抛 "No host specified in URI"），
  ///   只有 web 浏览器底层能直接吃 data URI。
  /// - `.svg` 网络地址走「拉取→改字体→渲染」管线（修中文）；其余按位图加载。
  /// - [urls] 是按优先级排列的候选 URL 列表（primary + backup CDN），逐个尝试直到成功。
  Widget _buildAsset(List<String> urls, VoidCallback onError) {
    final url = urls.first;
    if (url.startsWith('data:')) {
      if (_isSvgDataUri(url)) {
        try {
          final svg = utf8.decode(UriData.parse(url).contentAsBytes());
          return RepaintBoundary(
            child: _PreparedSvgView(
              svg: _prepareSvg(svg),
              fallback: widget.card.fallback,
              onError: onError,
            ),
          );
        } catch (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onError());
          return Text(
            widget.card.fallback ?? '',
            style: TextStyle(color: AppColors.warning, fontSize: 13),
          );
        }
      }
      return _AssetImageView(
        urls: urls,
        fallback: widget.card.fallback,
        onError: onError,
      );
    }
    if (url.toLowerCase().endsWith('.svg')) {
      return _CjkNetworkSvg(
        urls: urls,
        fallback: widget.card.fallback,
        onError: onError,
      );
    }
    return _AssetImageView(
      urls: urls,
      fallback: widget.card.fallback,
      onError: onError,
    );
  }
}

/// data: URI 的 mime 是否是 SVG（`data:image/svg+xml...`）
bool _isSvgDataUri(String url) {
  final comma = url.indexOf(',');
  final head = (comma < 0 ? url : url.substring(0, comma)).toLowerCase();
  return head.contains('svg');
}

/// 网络位图字节缓存（按首个 URL → 字节），避免滚动重建时重复网络请求。
/// 位图单张可能较大，额外按总字节数（24MB）设上限，防止内存无上限增长。
final _LruCache<Uint8List> _networkImageByteCache = _LruCache(
  maxEntries: 64,
  maxWeight: 24 * 1024 * 1024,
  weigh: (bytes) => bytes.lengthInBytes,
);

/// 位图资源（png/jpg 等）加载，SVG 不走这里。
/// [urls] 是按优先级排列的候选 URL 列表（primary + backup CDN），逐个尝试直到成功。
class _AssetImageView extends StatefulWidget {
  const _AssetImageView({
    required this.urls,
    required this.onError,
    this.fallback,
  });
  final List<String> urls;
  final VoidCallback onError;
  final String? fallback;

  @override
  State<_AssetImageView> createState() => _AssetImageViewState();
}

class _AssetImageViewState extends State<_AssetImageView> {
  Future<Uint8List>? _future;

  @override
  void initState() {
    super.initState();
    _ensureAssetMemCacheRegistered();
    _future = _load();
  }

  @override
  void didUpdateWidget(_AssetImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // urls 每次 build 都是新 List 实例，必须按内容比较，
    // 否则已缓存的图也会被重新 _load()，FutureBuilder 闪一帧占位图。
    if (!listEquals(oldWidget.urls, widget.urls)) {
      _future = _load();
    }
  }

  Future<Uint8List> _load() {
    final first = widget.urls.first;
    if (first.startsWith('data:')) {
      try {
        return Future.value(UriData.parse(first).contentAsBytes());
      } catch (e) {
        return Future.error(e);
      }
    }
    final cacheKey = first;
    // 1. 内存缓存
    final cached = _networkImageByteCache[cacheKey];
    if (cached != null) return Future.value(cached);

    // 2. 文件缓存 → 网络
    return _loadFromCacheOrNetwork(cacheKey);
  }

  Future<Uint8List> _loadFromCacheOrNetwork(String cacheKey) async {
    final fileCached = await ContentAssetCache.instance.readBytes(cacheKey);
    if (fileCached != null) {
      _networkImageByteCache[cacheKey] = fileCached;
      return fileCached;
    }
    final bytes = await _fetchBytes(widget.urls);
    _networkImageByteCache[cacheKey] = bytes;
    await ContentAssetCache.instance.writeBytes(cacheKey, bytes);
    return bytes;
  }

  static Future<Uint8List> _fetchBytes(List<String> urls) async {
    Object? lastError;
    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        final resp = await http.get(uri).timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) {
          lastError = http.ClientException('HTTP ${resp.statusCode}', uri);
          continue;
        }
        return resp.bodyBytes;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? http.ClientException('All image URLs failed: $urls');
  }

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
      child: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => widget.onError(),
            );
            return Text(
              widget.fallback ?? l10n.get('image_picture_loading_fail'),
              style: TextStyle(color: AppColors.warning, fontSize: 13),
            );
          }
          if (!snap.hasData) {
            return Container(
              width: double.infinity,
              height: 140,
              alignment: Alignment.center,
              child: Icon(
                Icons.image_outlined,
                size: 28,
                color: AppColors.accent.withValues(alpha: 0.4),
              ),
            );
          }
          return Image.memory(
            snap.data!,
            width: double.infinity,
            errorBuilder: (ctx, err, stack) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => widget.onError(),
              );
              return Text(
                widget.fallback ?? l10n.get('image_picture_loading_fail'),
                style: TextStyle(color: AppColors.warning, fontSize: 13),
              );
            },
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

class MermaidDiagramView extends StatefulWidget {
  const MermaidDiagramView({super.key, required this.card, this.content});
  final LearningCard card;
  final String? content;

  @override
  State<MermaidDiagramView> createState() => _MermaidDiagramViewState();
}

class _MermaidDiagramViewState extends State<MermaidDiagramView> {
  // 解析只在内容变化时做一次，避免每次重建（切 Tab/主题/语言都会触发）重跑正则。
  late MermaidDiagram _diagram;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(MermaidDiagramView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.card.content != widget.card.content) {
      _parse();
    }
  }

  void _parse() {
    _diagram = parseMermaidDiagram(widget.content ?? widget.card.content);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final diagram = _diagram;

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
        DiagramWithFullscreen(
          title: card.title,
          // 内联：无 InteractiveViewer，避免与 ListView 滚动冲突
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.codeBgDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
            ),
            child: diagramWidget,
          ),
          // 全屏：原始图解内容，由 _DiagramFullscreenView 包裹 InteractiveViewer
          fullscreenContent: diagramWidget,
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

class SvgDiagramCard extends StatefulWidget {
  const SvgDiagramCard({required this.card});
  final LearningCard card;

  @override
  State<SvgDiagramCard> createState() => _SvgDiagramCardState();
}

class _SvgDiagramCardState extends State<SvgDiagramCard> {
  String? _cachedRawSvg;
  String? _cachedPreparedSvg;

  String _prepareSvg(String raw) {
    if (raw == _cachedRawSvg && _cachedPreparedSvg != null) {
      return _cachedPreparedSvg!;
    }
    _cachedRawSvg = raw;
    _cachedPreparedSvg = prepareDiagramSvg(raw);
    return _cachedPreparedSvg!;
  }

  List<String> _assetUrls(BuildContext context, String path) {
    return context.read<ContentProvider>().resolveContentUrls(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final svgData = widget.card.svg;
    final svgAsset = widget.card.asset;

    // 与 DiagramCard 走同一套「改写字体 + 受限尺寸」管线，保证中文渲染
    final Widget media;
    if (svgData != null && svgData.isNotEmpty) {
      media = RepaintBoundary(
        child: _PreparedSvgView(
          svg: _prepareSvg(svgData),
          onError: () {},
          fallback: widget.card.fallback,
        ),
      );
    } else if (svgAsset != null && svgAsset.isNotEmpty) {
      media = RepaintBoundary(
        child: _CjkNetworkSvg(
          urls: _assetUrls(context, svgAsset),
          onError: () {},
          fallback: widget.card.fallback,
        ),
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
          widget.card.fallback ?? l10n.get('temporary_no_image_understand_content'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
      );
    }

    return WorkPanel(
      title: widget.card.title,
      children: [
        media,
        if (widget.card.content.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(widget.card.content, style: const TextStyle(height: 1.6)),
        ],
      ],
    );
  }
}
