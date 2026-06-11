import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/topic.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'package:mianshi_zhilian/theme/colors.dart';

// ── 核心概念卡片（Markdown 渲染）──────────────────────────────

class ExplainCard extends StatelessWidget {
  const ExplainCard({required this.card});
  final LearningCard card;

  String _formatContent(String content) {
    String formatted = content;

    formatted = formatted.replaceAll('\\n', '\n');

    final lines = formatted.split('\n');
    final buffer = StringBuffer();
    bool inFencedCodeBlock = false;
    bool inBareCodeBlock = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        if (inFencedCodeBlock) {
          buffer.writeln(line);
          inFencedCodeBlock = false;
        } else {
          if (inBareCodeBlock) {
            buffer.writeln('```');
            inBareCodeBlock = false;
          }
          buffer.writeln(line);
          inFencedCodeBlock = true;
        }
        continue;
      }

      if (inFencedCodeBlock) {
        buffer.writeln(line);
        continue;
      }

      if (trimmed.isEmpty) {
        if (inBareCodeBlock) {
          buffer.writeln('```');
          buffer.writeln();
          inBareCodeBlock = false;
        }
        buffer.writeln(line);
        continue;
      }

      if (_isMarkdownLine(trimmed)) {
        if (inBareCodeBlock) {
          buffer.writeln('```');
          buffer.writeln();
          inBareCodeBlock = false;
        }
        buffer.writeln(line);
        continue;
      }

      if (_isCodeLine(trimmed)) {
        if (!inBareCodeBlock) {
          buffer.writeln('```java');
          inBareCodeBlock = true;
        }
        buffer.writeln(line);
        continue;
      }

      if (inBareCodeBlock) {
        buffer.writeln('```');
        buffer.writeln();
        inBareCodeBlock = false;
      }
      buffer.writeln(line);
    }

    if (inBareCodeBlock) {
      buffer.writeln('```');
    }

    return buffer.toString();
  }

  bool _isMarkdownLine(String trimmed) {
    if (trimmed.isEmpty) return false;

    if (RegExp(r'^#{1,6}\s').hasMatch(trimmed)) return true;

    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) return true;

    if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) return true;

    if (trimmed.startsWith('>')) return true;

    if (trimmed.startsWith('|') &&
        trimmed.endsWith('|') &&
        trimmed.length > 2) {
      return true;
    }

    if (RegExp(r'^\|[\s\-:|]+\|$').hasMatch(trimmed)) {
      return true;
    }

    if (RegExp(r'^[-*_]{3,}\s*$').hasMatch(trimmed)) {
      return true;
    }

    if (trimmed.startsWith('**') && trimmed.contains('**')) {
      return true;
    }

    if (trimmed.startsWith('*') &&
        !trimmed.startsWith('* ') &&
        trimmed.endsWith('*') &&
        trimmed.length > 2) {
      return true;
    }

    if (RegExp(r'^\[.*\]\(.*\)').hasMatch(trimmed)) {
      return true;
    }

    if (trimmed.startsWith('![')) {
      return true;
    }

    return false;
  }

  bool _isCodeLine(String trimmed) {
    if (trimmed.isEmpty) return false;

    if (trimmed.startsWith('//')) return true;

    if (trimmed.startsWith('/*') ||
        (trimmed.startsWith('*') && trimmed.endsWith('*/'))) {
      return true;
    }

    if (RegExp(
      r'^(?:public|private|protected|static|final|abstract|class|interface|enum|import|package)\s',
    ).hasMatch(trimmed)) {
      return true;
    }

    if (RegExp(
      r'^(?:if|else|for|while|try|catch|finally|switch|case|default|return|throw|throws|new|assert)\b',
    ).hasMatch(trimmed)) {
      return true;
    }

    if (RegExp(
      r'^(?:void|int|long|double|float|boolean|char|byte|short|String|Object|List|Map|Set)\s+\w+',
    ).hasMatch(trimmed)) {
      return true;
    }

    if (trimmed.endsWith(';') && !trimmed.startsWith('|')) {
      return true;
    }

    if (trimmed == '{' || trimmed == '}' || trimmed == '};') {
      return true;
    }

    if (RegExp(r'^\w+\s+\w+\s*=\s*').hasMatch(trimmed) &&
        trimmed.endsWith(';')) {
      return true;
    }

    if (RegExp(r'^\w+[\.\[]\w+.*\)\s*;?\s*$').hasMatch(trimmed) &&
        !trimmed.startsWith('|')) {
      return true;
    }

    if (RegExp(r'^\w+\s+\w+\s*=\s*new\s').hasMatch(trimmed)) return true;

    if (trimmed.startsWith('@')) return true;

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final formattedContent = _formatContent(card.content);

    return WorkPanel(
      title: card.title,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: MarkdownContent(data: formattedContent),
        ),
      ],
    );
  }
}

// ── 面试回答模板卡片（深色背景）──────────────────────────────

class InterviewAnswerCard extends StatelessWidget {
  const InterviewAnswerCard({required this.card});
  final LearningCard card;

  String _formatInterviewContent(String content) {
    String formatted = content;

    formatted = formatted.replaceAll('\\n', '\n');

    final lines = formatted.split('\n');
    final buffer = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        if (RegExp(r'^\d+\.\s').hasMatch(line)) {
          buffer.writeln(line);
        } else if (line.startsWith('- ') || line.startsWith('* ')) {
          buffer.writeln(line);
        } else {
          buffer.writeln(line);
        }
      } else {
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final formattedContent = _formatInterviewContent(card.content);

    return WorkPanel(
      title: card.title,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.codeBgNavy,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.get('interview_answer_framework'),
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DefaultTextStyle(
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 14,
                  height: 1.7,
                ),
                child: MarkdownContent(data: formattedContent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Checklist 卡片（勾选项）────────────────────────────────────

class ChecklistCard extends StatelessWidget {
  const ChecklistCard({required this.card});
  final LearningCard card;

  @override
  Widget build(BuildContext context) {
    final items = card.items.isNotEmpty ? card.items : [card.content];
    return WorkPanel(
      title: card.title,
      children: [
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.accent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 12,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item, style: const TextStyle(height: 1.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 代码卡片（深色代码块 + 语法高亮）─────────────────────────

class CodeCard extends StatelessWidget {
  const CodeCard({required this.card});
  final LearningCard card;

  ({String language, String code, bool isDiagram}) _parseCodeContent(
    String content,
  ) {
    String cleaned = content.trim();
    String language = card.language ?? 'java';

    if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline != -1) {
        final langCandidate = cleaned.substring(0, firstNewline).trim();
        if (langCandidate.isNotEmpty &&
            !langCandidate.contains(' ') &&
            card.language == null) {
          language = langCandidate;
        }
        cleaned = cleaned.substring(firstNewline + 1);
      }
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }

    cleaned = cleaned.trim();

    final isDiagram = _isAsciiDiagram(cleaned);

    if (!isDiagram &&
        card.language == null &&
        language == 'java' &&
        !cleaned.contains('class ') &&
        !cleaned.contains('public ')) {
      if (cleaned.contains('def ') ||
          (cleaned.contains('import ') && cleaned.contains('self'))) {
        language = 'python';
      } else if (cleaned.contains('function ') ||
          cleaned.contains('const ') ||
          cleaned.contains('let ')) {
        language = 'javascript';
      } else if (cleaned.contains('fn ') || cleaned.contains('let mut ')) {
        language = 'rust';
      }
    }

    return (language: language, code: cleaned, isDiagram: isDiagram);
  }

  bool _isAsciiDiagram(String content) {
    if (content.isEmpty) return false;

    final lines = content.split('\n');
    int diagramScore = 0;

    for (final line in lines) {
      if (line.contains('→') ||
          line.contains('←') ||
          line.contains('↑') ||
          line.contains('↓') ||
          line.contains('->') ||
          line.contains('<-') ||
          line.contains('=>') ||
          line.contains('<=') ||
          line.contains('┌') ||
          line.contains('┐') ||
          line.contains('└') ||
          line.contains('┘') ||
          line.contains('│') ||
          line.contains('─') ||
          line.contains('├') ||
          line.contains('┤')) {
        diagramScore += 2;
      }

      final leadingSpaces = line.length - line.trimLeft().length;
      if (leadingSpaces > 4 && line.trim().isNotEmpty) {
        diagramScore += 1;
      }

      if (RegExp(r'[╔╗╚╝║═╠╣╦╩╬]').hasMatch(line)) {
        diagramScore += 3;
      }

      if (line.contains('+--') ||
          line.contains('| ') ||
          line.contains('+-+') ||
          line.contains('[->') ||
          line.contains(']--') ||
          line.contains('-->')) {
        diagramScore += 2;
      }
    }

    return diagramScore >= lines.length * 0.5 || diagramScore >= 4;
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseCodeContent(card.content);

    if (parsed.isDiagram) {
      return WorkPanel(
        title: card.title,
        children: [AsciiDiagramView(content: parsed.code)],
      );
    }

    return WorkPanel(
      title: card.title,
      children: [HighlightedCode(code: parsed.code, language: parsed.language)],
    );
  }
}

// ── ASCII 图形视图 ──────────────────────────────────────────

class AsciiDiagramView extends StatelessWidget {
  const AsciiDiagramView({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.codeBgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 14,
            height: 1.6,
            color: AppColors.syntaxDefault,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── 语法高亮代码组件 ─────────────────────────────────────────

class HighlightedCode extends StatelessWidget {
  const HighlightedCode({required this.code, this.language = 'java'});

  final String code;
  final String language;

  static const _keywordColor = AppColors.syntaxKeyword;
  static const _stringColor = AppColors.syntaxString;
  static const _commentColor = AppColors.syntaxComment;
  static const _numberColor = AppColors.syntaxNumber;
  static const _typeColor = AppColors.syntaxType;
  static const _functionColor = AppColors.syntaxFunction;
  static const _defaultColor = AppColors.syntaxDefault;

  List<CodeToken> _tokenize(String code) {
    final tokens = <CodeToken>[];
    final keywords = {
      'abstract',
      'assert',
      'boolean',
      'break',
      'byte',
      'case',
      'catch',
      'char',
      'class',
      'const',
      'continue',
      'default',
      'do',
      'double',
      'else',
      'enum',
      'extends',
      'final',
      'finally',
      'float',
      'for',
      'goto',
      'if',
      'implements',
      'import',
      'instanceof',
      'int',
      'interface',
      'long',
      'native',
      'new',
      'package',
      'private',
      'protected',
      'public',
      'return',
      'short',
      'static',
      'strictfp',
      'super',
      'switch',
      'synchronized',
      'this',
      'throw',
      'throws',
      'transient',
      'try',
      'void',
      'volatile',
      'while',
      'true',
      'false',
      'null',
      'var',
      'record',
      'sealed',
      'permits',
      'yield',
      'with',
    };

    final typeKeywords = {
      'String',
      'Object',
      'List',
      'Map',
      'Set',
      'Collection',
      'Iterator',
      'Integer',
      'Long',
      'Double',
      'Float',
      'Boolean',
      'Character',
      'Byte',
      'Short',
      'Number',
      'Comparable',
      'Iterable',
      'Stream',
      'Optional',
      'ArrayList',
      'HashMap',
      'HashSet',
      'LinkedList',
      'TreeMap',
      'TreeSet',
      'ConcurrentHashMap',
      'CopyOnWriteArrayList',
      'ThreadPoolExecutor',
      'ExecutorService',
      'Future',
      'CompletableFuture',
      'Thread',
      'Runnable',
    };

    final buffer = StringBuffer();
    var i = 0;

    while (i < code.length) {
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '/') {
        if (buffer.isNotEmpty) {
          tokens.add(CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final start = i;
        while (i < code.length && code[i] != '\n') {
          i++;
        }
        tokens.add(CodeToken(code.substring(start, i), _commentColor));
        continue;
      }

      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
        if (buffer.isNotEmpty) {
          tokens.add(CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final start = i;
        i += 2;
        while (i + 1 < code.length && !(code[i] == '*' && code[i + 1] == '/')) {
          i++;
        }
        i += 2;
        tokens.add(CodeToken(code.substring(start, i), _commentColor));
        continue;
      }

      if (code[i] == '"' || code[i] == '\'') {
        if (buffer.isNotEmpty) {
          tokens.add(CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final quote = code[i];
        final start = i;
        i++;
        while (i < code.length && code[i] != quote) {
          if (code[i] == '\\') i++;
          i++;
        }
        i++;
        tokens.add(CodeToken(code.substring(start, i), _stringColor));
        continue;
      }

      if (RegExp(r'[0-9]').hasMatch(code[i])) {
        if (buffer.isNotEmpty) {
          tokens.add(CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final start = i;
        while (i < code.length && RegExp(r'[0-9.xXa-fA-F]').hasMatch(code[i])) {
          i++;
        }
        tokens.add(CodeToken(code.substring(start, i), _numberColor));
        continue;
      }

      if (RegExp(r'[a-zA-Z_$]').hasMatch(code[i])) {
        if (buffer.isNotEmpty) {
          tokens.add(CodeToken(buffer.toString(), _defaultColor));
          buffer.clear();
        }
        final start = i;
        while (i < code.length && RegExp(r'[a-zA-Z0-9_$]').hasMatch(code[i])) {
          i++;
        }
        final word = code.substring(start, i);
        Color color;
        if (keywords.contains(word)) {
          color = _keywordColor;
        } else if (typeKeywords.contains(word)) {
          color = _typeColor;
        } else if (i < code.length && code[i] == '(') {
          color = _functionColor;
        } else {
          color = _defaultColor;
        }
        tokens.add(CodeToken(word, color));
        continue;
      }

      buffer.write(code[i]);
      i++;
    }

    if (buffer.isNotEmpty) {
      tokens.add(CodeToken(buffer.toString(), _defaultColor));
    }

    return tokens;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokenize(code);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.codeBgDarker,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              language.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText.rich(
              TextSpan(
                children: tokens
                    .map(
                      (token) => TextSpan(
                        text: token.text,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 13,
                          height: 1.6,
                          color: token.color,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CodeToken {
  final String text;
  final Color color;
  CodeToken(this.text, this.color);
}

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

    return MermaidDiagramData(
      source: source,
      direction: direction,
      edges: edges,
    );
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

// ── 追问区域（可折叠）────────────────────────────────────────

class FollowUpSection extends StatelessWidget {
  const FollowUpSection({required this.followUps});
  final List<FollowUpQuestion> followUps;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('common_follow_up'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.categoryPurple.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          l10n.getp('count_question_count_2', {'count': followUps.length}),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.categoryPurple,
          ),
        ),
      ),
      children: [
        ...followUps.asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FollowUpCard(index: entry.key + 1, question: entry.value),
          ),
        ),
      ],
    );
  }
}

class FollowUpCard extends StatefulWidget {
  const FollowUpCard({required this.index, required this.question});
  final int index;
  final FollowUpQuestion question;

  @override
  State<FollowUpCard> createState() => FollowUpCardState();
}

class FollowUpCardState extends State<FollowUpCard> {
  bool _expanded = false;

  Color get _difficultyColor {
    return switch (widget.question.difficulty) {
      1 => AppColors.success,
      2 => AppColors.accent,
      3 => AppColors.warning,
      4 || 5 => AppColors.danger,
      _ => Colors.grey,
    };
  }

  String get _difficultyLabel {
    final l10n = context.watch<LocalizationProvider>();
    return switch (widget.question.difficulty) {
      1 => l10n.get('beginner'),
      2 => l10n.get('basic'),
      3 => l10n.get('medium'),
      4 => l10n.get('compare_difficult'),
      5 => l10n.get('hard'),
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _expanded
            ? AppColors.categoryPurple.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _expanded
              ? AppColors.categoryPurple.withValues(alpha: 0.3)
              : Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.categoryPurple.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.categoryPurple,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.question.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (_difficultyLabel.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _difficultyColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _difficultyLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _difficultyColor,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: AppColors.categoryPurple.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  if (widget.question.hints.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.question.hints
                          .map(
                            (hint) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                hint,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.codeBgDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.categoryPurple.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: AppColors.categoryPurple,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.get('reference_answer'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.categoryPurple,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: widget.question.answer),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      l10n.get(
                                        'already_review_control_to_clip_clipboard_board',
                                      ),
                                    ),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DefaultTextStyle(
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 13,
                            height: 1.6,
                          ),
                          child: MarkdownContent(data: widget.question.answer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ── 表格卡片 ─────────────────────────────────────────────────

class TableCard extends StatelessWidget {
  const TableCard({required this.card});
  final LearningCard card;

  String _formatTableContent(String content) {
    String formatted = content;

    formatted = formatted.replaceAll('\\n', '\n');

    final lines = formatted.split('\n');
    final buffer = StringBuffer();
    bool isFirstLine = true;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        if (line.startsWith('|') && line.endsWith('|')) {
          buffer.writeln(line);

          if (isFirstLine && !line.contains('---')) {
            final columns = line
                .split('|')
                .where((c) => c.trim().isNotEmpty)
                .length;
            buffer.writeln('| ${'--- | ' * (columns - 1)}--- |');
            isFirstLine = false;
          }
        } else {
          buffer.writeln(line);
        }
      } else {
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  String _buildMarkdownFromStructured() {
    if (card.columns.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('| ${card.columns.join(' | ')} |');
    buffer.writeln('| ${card.columns.map((_) => '---').join(' | ')} |');
    for (final row in card.rows) {
      buffer.writeln('| ${row.join(' | ')} |');
    }
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final formattedContent = card.columns.isNotEmpty
        ? _buildMarkdownFromStructured()
        : _formatTableContent(card.content);

    return WorkPanel(
      title: card.title,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 600),
            child: MarkdownContent(data: formattedContent),
          ),
        ),
      ],
    );
  }
}

// ── 通用卡片 ─────────────────────────────────────────────────

class GenericCard extends StatelessWidget {
  const GenericCard({required this.card});
  final LearningCard card;

  bool _shouldUseMarkdown(String content) {
    final trimmed = content.trim();

    if (trimmed.contains('# ') ||
        trimmed.contains('## ') ||
        trimmed.contains('### ') ||
        trimmed.contains('**') ||
        trimmed.contains('```') ||
        trimmed.contains('- ') ||
        trimmed.contains('* ') ||
        trimmed.contains('> ') ||
        RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
      return true;
    }

    if (trimmed.contains('| ') && trimmed.contains(' |')) {
      return true;
    }

    if (RegExp(r'\[.*\]\(.*\)').hasMatch(trimmed)) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WorkPanel(
      title: card.title,
      children: [
        if (_shouldUseMarkdown(card.content))
          MarkdownContent(data: card.content)
        else
          SelectableText(card.content, style: const TextStyle(height: 1.7)),
      ],
    );
  }
}

// ── Markdown 渲染组件 ────────────────────────────────────────

class MarkdownContent extends StatelessWidget {
  const MarkdownContent({required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;

    return MarkdownBody(
      data: data,
      selectable: true,
      syntaxHighlighter: CodeSyntaxHighlighter(),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: baseStyle.copyWith(height: 1.7),
        h1: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 22,
        ),
        h2: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
        h3: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
        code: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 13,
          color: AppColors.syntaxDefault,
          backgroundColor: AppColors.codeBgSlate.withValues(alpha: 0.6),
        ),
        codeblockDecoration: BoxDecoration(
          color: AppColors.codeBgDarker,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        codeblockPadding: const EdgeInsets.all(16),
        listBullet: baseStyle.copyWith(height: 1.7),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppColors.accent.withValues(alpha: 0.5),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 16),
      ),
    );
  }
}

// ── 代码语法高亮器 ─────────────────────────────────────────

class CodeSyntaxHighlighter extends SyntaxHighlighter {
  static const _keywordColor = AppColors.syntaxKeyword;
  static const _stringColor = AppColors.syntaxString;
  static const _commentColor = AppColors.syntaxComment;
  static const _numberColor = AppColors.syntaxNumber;
  static const _typeColor = AppColors.syntaxType;
  static const _functionColor = AppColors.syntaxFunction;
  static const _defaultColor = AppColors.syntaxDefault;

  static const _keywords = {
    'abstract',
    'assert',
    'boolean',
    'break',
    'byte',
    'case',
    'catch',
    'char',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'double',
    'else',
    'enum',
    'extends',
    'final',
    'finally',
    'float',
    'for',
    'goto',
    'if',
    'implements',
    'import',
    'instanceof',
    'int',
    'interface',
    'long',
    'native',
    'new',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'short',
    'static',
    'strictfp',
    'super',
    'switch',
    'synchronized',
    'this',
    'throw',
    'throws',
    'transient',
    'try',
    'void',
    'volatile',
    'while',
    'true',
    'false',
    'null',
    'var',
    'record',
    'sealed',
    'permits',
    'yield',
    'with',
    'def',
    'fn',
    'let',
    'async',
    'await',
  };

  static const _typeKeywords = {
    'String',
    'Object',
    'List',
    'Map',
    'Set',
    'Collection',
    'Iterator',
    'Integer',
    'Long',
    'Double',
    'Float',
    'Boolean',
    'Character',
    'Byte',
    'Short',
    'Number',
    'Comparable',
    'Iterable',
    'Stream',
    'Optional',
    'ArrayList',
    'HashMap',
    'HashSet',
    'LinkedList',
    'TreeMap',
    'TreeSet',
  };

  @override
  TextSpan format(String source) {
    final tokens = _tokenize(source);
    return TextSpan(children: tokens);
  }

  List<TextSpan> _tokenize(String code) {
    final tokens = <TextSpan>[];
    final buffer = StringBuffer();
    var i = 0;

    while (i < code.length) {
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '/') {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final start = i;
        while (i < code.length && code[i] != '\n') {
          i++;
        }
        tokens.add(
          TextSpan(
            text: code.substring(start, i),
            style: TextStyle(
              color: _commentColor,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final start = i;
        i += 2;
        while (i + 1 < code.length && !(code[i] == '*' && code[i + 1] == '/')) {
          i++;
        }
        i += 2;
        tokens.add(
          TextSpan(
            text: code.substring(start, i),
            style: TextStyle(
              color: _commentColor,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      if (code[i] == '"' || code[i] == '\'') {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final quote = code[i];
        final start = i;
        i++;
        while (i < code.length && code[i] != quote) {
          if (code[i] == '\\') i++;
          i++;
        }
        i++;
        tokens.add(
          TextSpan(
            text: code.substring(start, i),
            style: TextStyle(
              color: _stringColor,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      if (RegExp(r'[0-9]').hasMatch(code[i])) {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final start = i;
        while (i < code.length && RegExp(r'[0-9.xXa-fA-F]').hasMatch(code[i])) {
          i++;
        }
        tokens.add(
          TextSpan(
            text: code.substring(start, i),
            style: TextStyle(
              color: _numberColor,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      if (RegExp(r'[a-zA-Z_$]').hasMatch(code[i])) {
        if (buffer.isNotEmpty) {
          tokens.add(
            TextSpan(
              text: buffer.toString(),
              style: TextStyle(
                color: _defaultColor,
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          );
          buffer.clear();
        }
        final start = i;
        while (i < code.length && RegExp(r'[a-zA-Z0-9_$]').hasMatch(code[i])) {
          i++;
        }
        final word = code.substring(start, i);
        Color color;
        if (_keywords.contains(word)) {
          color = _keywordColor;
        } else if (_typeKeywords.contains(word)) {
          color = _typeColor;
        } else if (i < code.length && code[i] == '(') {
          color = _functionColor;
        } else {
          color = _defaultColor;
        }
        tokens.add(
          TextSpan(
            text: word,
            style: TextStyle(
              color: color,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
              height: 1.6,
            ),
          ),
        );
        continue;
      }

      buffer.write(code[i]);
      i++;
    }

    if (buffer.isNotEmpty) {
      tokens.add(
        TextSpan(
          text: buffer.toString(),
          style: TextStyle(
            color: _defaultColor,
            fontFamily: 'JetBrainsMono',
            fontSize: 13,
            height: 1.6,
          ),
        ),
      );
    }

    return tokens;
  }
}
