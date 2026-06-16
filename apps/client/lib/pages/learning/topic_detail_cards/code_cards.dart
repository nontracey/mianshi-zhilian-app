part of '../topic_detail_cards.dart';

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
      children: [
        HighlightedCode(
          code: parsed.code,
          language: parsed.language,
          highlights: card.highlights,
        ),
      ],
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
  const HighlightedCode({
    required this.code,
    this.language = 'java',
    this.highlights = const [],
  });

  final String code;
  final String language;
  final List<Map<String, dynamic>> highlights;

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

  Map<int, String> _highlightNotes() {
    final notes = <int, String>{};
    for (final highlight in highlights) {
      final line = (highlight['line'] as num?)?.toInt();
      final startLine =
          (highlight['startLine'] as num?)?.toInt() ??
          (highlight['start'] as num?)?.toInt() ??
          line;
      final endLine =
          (highlight['endLine'] as num?)?.toInt() ??
          (highlight['end'] as num?)?.toInt() ??
          startLine;
      if (startLine == null || endLine == null) continue;
      final note =
          (highlight['note'] ?? highlight['label'] ?? highlight['title'] ?? '')
              .toString()
              .trim();
      for (var current = startLine; current <= endLine; current += 1) {
        notes[current] = note;
      }
    }
    return notes;
  }

  Widget _buildCodeLine(
    BuildContext context,
    String line,
    int lineNumber,
    Map<int, String> notes,
  ) {
    final note = notes[lineNumber];
    final isHighlighted = note != null;
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppColors.warning.withValues(alpha: 0.13)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12,
                height: 1.6,
                color: isHighlighted
                    ? AppColors.warning
                    : AppColors.syntaxComment.withValues(alpha: 0.75),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SelectableText.rich(
            TextSpan(
              children: _tokenize(line.isEmpty ? ' ' : line)
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
        ],
      ),
    );

    if (!isHighlighted || note.isEmpty) return row;
    return Tooltip(message: note, child: row);
  }

  @override
  Widget build(BuildContext context) {
    final notes = _highlightNotes();
    final lines = code.split('\n');

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
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i += 1)
                    _buildCodeLine(context, lines[i], i + 1, notes),
                ],
              ),
            ),
          ),
          if (notes.entries.any((entry) => entry.value.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in notes.entries)
                  if (entry.value.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        'L${entry.key}: ${entry.value}',
                        style: const TextStyle(
                          fontSize: 12,
                          // 代码卡背景始终为深色，固定用浅色文字，
                          // 不能跟随主题 onSurface（浅色主题下会变黑字看不见）
                          color: AppColors.syntaxDefault,
                        ),
                      ),
                    ),
              ],
            ),
          ],
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
