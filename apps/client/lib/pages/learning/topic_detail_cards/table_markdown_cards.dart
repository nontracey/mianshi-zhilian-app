part of '../topic_detail_cards.dart';

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
