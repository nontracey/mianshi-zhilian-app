/// 资料导入管线（§6.3、§6.4）：提取正文 -> 哈希去重 -> 切块 -> 生成 Source 与 chunks。
library;

import '../domain/common.dart';
import 'chunker.dart';
import 'parser.dart';
import 'source.dart';

/// 一次导入请求。
class ImportRequest {
  ImportRequest({
    required this.text,
    this.title,
    this.type = SourceType.paste,
    this.url,
    required this.profileId,
    this.knowledgeItemId,
  });

  final String text;
  final String? title;
  final SourceType type;
  final String? url;
  final ProfileId profileId;
  final KnowledgeItemId? knowledgeItemId;

  ImportRequest copyWith({String? text}) => ImportRequest(
    text: text ?? this.text,
    title: title,
    type: type,
    url: url,
    profileId: profileId,
    knowledgeItemId: knowledgeItemId,
  );
}

/// 导入结果。
class ImportResult {
  ImportResult({
    required this.source,
    required this.chunks,
    required this.contentHash,
    this.duplicated = false,
  });

  final Source source;
  final List<SourceChunk> chunks;
  final String contentHash;

  /// 内容哈希已存在时由调用方决定如何处理；本结果仅表示本次生成的来源与分块。
  final bool duplicated;
}

/// 文档导入器。组合解析器与切块器，产出可索引的 Source 与分块。
class DocumentImporter {
  DocumentImporter({
    required this.parser,
    required this.chunker,
    required this.idGen,
    required this.clock,
  });

  final DocumentParser parser;
  final Chunker chunker;
  final IdGenerator idGen;
  final Clock clock;

  /// Extract a user supplied file without creating a Source. Resume import
  /// reuses the same parser so PDF/DOCX and pasted text follow one validation
  /// path. An empty extraction is always an error (common for scanned PDFs).
  Future<String> extractText(List<int> bytes, {String? fileName}) async {
    final text = await parser.extractText(bytes, fileName: fileName);
    if (text.trim().isEmpty) {
      throw ParseException('文件没有可提取的文字，可能是扫描件；请粘贴文本或使用 OCR');
    }
    return text;
  }

  /// 从文本导入：哈希 -> 生成 Source -> 切块。
  Future<ImportResult> importText(ImportRequest req) async {
    final hash = computeContentHash(req.text);
    final title = req.title ?? '导入资料 ${hash.substring(0, 6)}';
    final now = clock.now();
    final source = Source(
      id: idGen.next(),
      profileId: req.profileId,
      title: title,
      type: req.type,
      contentHash: hash,
      status: IngestionStatus.ready,
      url: req.url,
      content: req.text,
      fetchedAt: now,
      createdAt: now,
    );
    final chunks = _buildChunks(req.text, source, req.knowledgeItemId);
    return ImportResult(source: source, chunks: chunks, contentHash: hash);
  }

  /// Create the next immutable chunk set for an existing source. Old chunk IDs
  /// remain available for historical citations but cannot enter the live index.
  ImportResult reviseText(
    Source current,
    String text, {
    KnowledgeItemId? knowledgeItemId,
  }) {
    if (text.trim().isEmpty) throw ParseException('empty source update');
    final revised = Source(
      id: current.id,
      profileId: current.profileId,
      title: current.title,
      type: current.type,
      contentHash: computeContentHash(text),
      status: IngestionStatus.ready,
      url: current.url,
      revision: current.revision + 1,
      content: text,
      fetchedAt: clock.now(),
      createdAt: current.createdAt,
    );
    return ImportResult(
      source: revised,
      chunks: _buildChunks(text, revised, knowledgeItemId),
      contentHash: revised.contentHash,
    );
  }

  /// 从字节导入：先解析为文本，再走 [importText]。
  Future<ImportResult> importBytes(List<int> bytes, ImportRequest req) async {
    final text = await extractText(bytes, fileName: req.title);
    return importText(req.copyWith(text: text));
  }

  List<SourceChunk> _buildChunks(
    String text,
    Source source,
    KnowledgeItemId? knowledgeItemId,
  ) {
    final raw = chunker.chunk(text, baseTitlePath: source.title);
    return raw
        .map(
          (c) => SourceChunk(
            id: idGen.next(),
            sourceId: source.id,
            sourceRevision: source.revision,
            index: c.index,
            content: c.content,
            titlePath: c.titlePath,
            hash: computeContentHash(c.content),
            knowledgeItemId: knowledgeItemId,
          ),
        )
        .toList();
  }
}
