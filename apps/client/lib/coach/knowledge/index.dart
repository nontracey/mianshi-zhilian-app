/// 内存全文索引（§6.5）。关键词召回 + 可选向量召回的候选来源。
///
/// 纯 Dart、无外部依赖；关键词采用“英文/数字整词 + 中文单字与二元组”混合，
/// 中文召回质量需按 §6.5 单独验收，本实现只保证可用闭环。向量为可选增强。
library;

import 'dart:math' as math;

import '../domain/common.dart';
import 'source.dart';

/// 已索引的分块（含归属，便于范围过滤）。
class IndexedChunk {
  IndexedChunk(this.chunk, this.profileId, {this.knowledgeItemId});
  final SourceChunk chunk;
  final ProfileId profileId;
  final KnowledgeItemId? knowledgeItemId;
}

class InMemoryIndex {
  final Map<String, IndexedChunk> _chunks = {};
  final Map<String, Set<String>> _tokenToChunks = {};
  final Map<String, Source> _sources = {};

  /// chunkId -> (embeddingProfileId -> 向量)
  final Map<String, Map<String, List<double>>> _vectors = {};

  void clearProfile(ProfileId profileId) {
    for (final id
        in _chunks.entries
            .where((e) => e.value.profileId == profileId)
            .map((e) => e.key)
            .toList()) {
      removeChunk(id);
    }
    _sources.removeWhere((_, source) => source.profileId == profileId);
  }

  void addSource(Source source) => _sources[source.id] = source;

  Source? sourceById(String id) => _sources[id];

  void addChunk(IndexedChunk chunk) {
    removeChunk(chunk.chunk.id);
    _chunks[chunk.chunk.id] = chunk;
    for (final tok in _tokenize(chunk.chunk.content)) {
      (_tokenToChunks[tok] ??= {}).add(chunk.chunk.id);
    }
  }

  void removeChunk(String id) {
    _chunks.remove(id);
    _vectors.remove(id);
    for (final ids in _tokenToChunks.values) {
      ids.remove(id);
    }
    _tokenToChunks.removeWhere((_, ids) => ids.isEmpty);
  }

  Set<String> scopedIds({
    required ProfileId profileId,
    List<SourceId>? sourceIds,
    KnowledgeItemId? knowledgeItemId,
  }) => {
    for (final entry in _chunks.entries)
      if (entry.value.profileId == profileId &&
          _sources[entry.value.chunk.sourceId]?.profileId == profileId &&
          _sources[entry.value.chunk.sourceId]?.status ==
              IngestionStatus.ready &&
          _sources[entry.value.chunk.sourceId]?.revision ==
              entry.value.chunk.sourceRevision &&
          (sourceIds == null ||
              sourceIds.contains(entry.value.chunk.sourceId)) &&
          (knowledgeItemId == null ||
              (entry.value.knowledgeItemId ??
                      entry.value.chunk.knowledgeItemId) ==
                  knowledgeItemId))
        entry.key,
  };

  bool hasEmbedding(String chunkId, String profileId) =>
      _vectors[chunkId]?.containsKey(profileId) ?? false;

  void addEmbedding(String chunkId, String profileId, List<double> vector) {
    (_vectors[chunkId] ??= {})[profileId] = vector;
  }

  IndexedChunk? chunkById(String id) => _chunks[id];

  /// 关键词召回：返回 chunkId -> 命中词数（粗略倒排得分）。
  Map<String, int> keywordRecall(String query, {int maxHits = 200}) {
    final scores = <String, int>{};
    for (final tok in _tokenize(query)) {
      final ids = _tokenToChunks[tok];
      if (ids == null) continue;
      for (final id in ids) {
        scores[id] = (scores[id] ?? 0) + 1;
      }
    }
    return scores;
  }

  /// 余弦相似度 top-K（仅匹配相同 embedding profile）。
  List<(String, double)> cosineTopK(
    List<double> queryVec,
    String profileId, {
    int k = 50,
    Set<String>? allowedIds,
  }) {
    final normQ = _norm(queryVec);
    final scored = <(String, double)>[];
    for (final entry in _vectors.entries) {
      if (allowedIds != null && !allowedIds.contains(entry.key)) continue;
      final vec = entry.value[profileId];
      if (vec == null || vec.length != queryVec.length) continue;
      final sim = _cosine(queryVec, normQ, vec);
      if (sim > 0 && sim.isFinite) scored.add((entry.key, sim));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(k).toList();
  }

  static double _cosine(List<double> a, double normA, List<double> b) {
    if (normA == 0) return 0;
    final normB = _norm(b);
    if (normB == 0) return 0;
    var dot = 0.0;
    final n = math.min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
    }
    return dot / (normA * normB);
  }

  static double _norm(List<double> v) {
    var s = 0.0;
    for (final x in v) {
      s += x * x;
    }
    return math.sqrt(s);
  }

  /// 混合分词：英文/数字整词（小写）；CJK 单字 + 二元组；其他分隔符作为边界。
  static Iterable<String> _tokenize(String text) sync* {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      final code = ch.codeUnitAt(0);
      final isCjk = code >= 0x4e00 && code <= 0x9fff;
      final isLatin =
          (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
      final isDigit = code >= 0x30 && code <= 0x39;
      if (isCjk) {
        if (buffer.isNotEmpty) {
          yield buffer.toString().toLowerCase();
          buffer.clear();
        }
        yield ch;
        if (i + 1 < text.length) {
          final nx = text.codeUnitAt(i + 1);
          if (nx >= 0x4e00 && nx <= 0x9fff) yield ch + text[i + 1];
        }
      } else if (isLatin || isDigit) {
        buffer.write(ch);
      } else {
        if (buffer.isNotEmpty) {
          yield buffer.toString().toLowerCase();
          buffer.clear();
        }
      }
    }
    if (buffer.isNotEmpty) yield buffer.toString().toLowerCase();
  }
}
