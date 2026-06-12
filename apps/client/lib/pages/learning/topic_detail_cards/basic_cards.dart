part of '../topic_detail_cards.dart';

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
