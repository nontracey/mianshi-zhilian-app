/// 定向知识检索（§6.5、§6.6）。范围过滤 + 关键词召回 + 可选向量召回 + RRF 融合。
///
/// 模型只能拿到最多若干片段及其引用 ID，取不到证据时由上层说明缺口，
/// 不自动把弱匹配塞满上下文。
library;

import '../domain/common.dart';
import 'embedding.dart';
import 'index.dart';
import 'source.dart';

/// 一条检索命中。chunk 与来源共同构成可定位引用。
class RetrievalHit {
  RetrievalHit({
    required this.chunk,
    required this.source,
    required this.score,
  });

  final SourceChunk chunk;
  final Source source;

  /// 融合得分（用于排序，不直接等同相似度）。
  final double score;

  /// 模型可用的引用 ID（即 chunkId）。
  String get citationId => chunk.id;
}

/// 知识检索器。聚合索引、可选向量，按范围过滤后返回 top-K 命中。
class KnowledgeRetriever {
  KnowledgeRetriever({required this.index, this.embedding});

  final InMemoryIndex index;
  EmbeddingProvider? embedding;
  bool embeddingDegraded = false;

  /// 检索当前问题相关的资料片段。
  ///
  /// [profileId] 用于隔离不同档案资料；[sourceIds] 可进一步缩小来源范围；
  /// [knowledgeItemId] 用于“仅检索某知识点资料”的定向场景。
  Future<List<RetrievalHit>> retrieve(
    String query, {
    required ProfileId profileId,
    List<SourceId>? sourceIds,
    KnowledgeItemId? knowledgeItemId,
    int topK = 8,
    int maxCitations = 8,
  }) async {
    if (topK <= 0 || maxCitations <= 0 || query.trim().isEmpty) return [];
    final allowed = index.scopedIds(
      profileId: profileId,
      sourceIds: sourceIds,
      knowledgeItemId: knowledgeItemId,
    );
    // 1) 关键词召回
    final kw = index.keywordRecall(query)
      ..removeWhere((id, _) => !allowed.contains(id));
    final kwRanked = _rankByScore(kw);

    // 2) 可选向量召回
    List<String> embRanked = const [];
    final embedder = embedding;
    embeddingDegraded = false;
    if (embedder != null && allowed.isNotEmpty) {
      try {
        final candidates = {...kwRanked, ...allowed}
            .where((id) => !index.hasEmbedding(id, embedder.profileId))
            .take(64)
            .toList();
        final texts = [
          for (final id in candidates) index.chunkById(id)!.chunk.content,
        ];
        final vectors = candidates.isEmpty
            ? <List<double>>[]
            : embedder is BatchEmbeddingProvider
            ? await embedder.embedBatch(texts)
            : await Future.wait(texts.map(embedder.embed));
        if (vectors.length != candidates.length)
          throw StateError('Embedding batch mismatch');
        for (var i = 0; i < candidates.length; i++) {
          index.addEmbedding(candidates[i], embedder.profileId, vectors[i]);
        }
        final vec = await embedder.embed(query);
        embRanked = index
            .cosineTopK(vec, embedder.profileId, k: 50, allowedIds: allowed)
            .map((t) => t.$1)
            .toList();
      } catch (_) {
        // Embeddings enhance retrieval; a failed secondary provider cannot stop teaching.
        embeddingDegraded = true;
      }
    }

    // 3) RRF 融合
    final fused = _reciprocalRankFusion([kwRanked, embRanked]);

    // 4) 范围过滤 + 组装命中
    final hits = <RetrievalHit>[];
    for (final entry in fused.entries) {
      final indexed = index.chunkById(entry.key);
      if (indexed == null) continue;
      if (!allowed.contains(entry.key)) continue;
      if (sourceIds != null && !sourceIds.contains(indexed.chunk.sourceId)) {
        continue;
      }
      if (knowledgeItemId != null &&
          indexed.knowledgeItemId != null &&
          indexed.knowledgeItemId != knowledgeItemId) {
        continue;
      }
      final source = index.sourceById(indexed.chunk.sourceId);
      if (source == null) continue;
      hits.add(
        RetrievalHit(chunk: indexed.chunk, source: source, score: entry.value),
      );
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    final limit = maxCitations < topK ? maxCitations : topK;
    return hits.take(limit).toList();
  }

  /// 把得分 Map 转成有序 ID 列表（高分在前）。
  List<String> _rankByScore(Map<String, int> scores) {
    final entries = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }

  /// 倒数排名融合（Reciprocal Rank Fusion）。
  Map<String, double> _reciprocalRankFusion(
    List<List<String>> rankedLists, {
    int k = 60,
  }) {
    final fused = <String, double>{};
    for (final ranked in rankedLists) {
      for (var i = 0; i < ranked.length; i++) {
        final id = ranked[i];
        fused[id] = (fused[id] ?? 0) + 1.0 / (k + i + 1);
      }
    }
    final sorted = fused.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }
}
