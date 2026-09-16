/// 资料切块（§6.4）。按段落/章节切块，约 400–800 token，重叠 50–100 token。
///
/// 中文没有空白分词，首版用保守字符预算并留余量，不把中文字符数直接当 token 数。
library;

/// 单个分块（切块阶段，尚未分配持久 ID）。
class Chunk {
  Chunk({required this.content, this.titlePath, required this.index});
  final String content;

  /// 标题路径（例如 "3. 事务隔离 / 3.1 隔离级别"），用于展示出处。
  final String? titlePath;
  final int index;
}

/// 切块器。把长文本切成可检索的片段，并保留标题层级与少量重叠。
class Chunker {
  Chunker({
    this.targetChars = 1500, // ≈500 token × 3 字符/token（保守）
    this.overlapChars = 300, // ≈100 token
  });

  final int targetChars;
  final int overlapChars;

  /// 按空行分段，并识别 Markdown 标题维护标题路径。
  List<Chunk> chunk(String text, {String? baseTitlePath}) {
    final paragraphs = _splitParagraphs(text);
    final chunks = <Chunk>[];
    final current = <String>[];
    var currentLen = 0;
    var index = 0;
    String? titlePath = baseTitlePath;

    void flush() {
      if (current.isEmpty) return;
      chunks.add(
        Chunk(
          content: current.join('\n\n'),
          titlePath: titlePath,
          index: index++,
        ),
      );
    }

    for (final raw in paragraphs) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final headingText = _headingText(trimmed);
      if (headingText != null) {
        flush();
        titlePath = _joinPath(baseTitlePath, headingText);
        current.clear();
        currentLen = 0;
        continue;
      }
      final pLen = trimmed.length;
      if (current.isNotEmpty && currentLen + pLen > targetChars) {
        flush();
        // 重叠：保留上一段作为新块开头，避免切断上下文。
        current.clear();
        currentLen = 0;
        if (overlapChars > 0 && chunks.isNotEmpty) {
          final prev = chunks.last.content;
          final lastPara = prev.split('\n\n').last;
          if (lastPara.length <= overlapChars) {
            current.add(lastPara);
            currentLen = lastPara.length;
          }
        }
      }
      current.add(trimmed);
      currentLen += pLen;
    }
    flush();
    return chunks;
  }

  List<String> _splitParagraphs(String text) {
    return text.split(RegExp(r'\n\s*\n')).map((p) => p.trim()).toList();
  }

  String? _headingText(String line) {
    final m = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    return m?.group(2)?.trim();
  }

  String _joinPath(String? base, String heading) =>
      base == null || base.isEmpty ? heading : '$base / $heading';
}
