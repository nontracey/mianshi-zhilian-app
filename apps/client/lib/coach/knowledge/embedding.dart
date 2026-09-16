/// 可选向量检索的抽象（§6.5）。首版向量为可选项，不要求每位用户提供第二把 Key。
///
/// 配置 Embedding 后，[KnowledgeRetriever] 会在关键词召回之外并行做语义召回并融合。
library;

/// 向量化提供者。把文本映射为定长向量；维度与模型由具体实现决定。
abstract class EmbeddingProvider {
  /// 当前模型维度，用于一致性校验。
  int get dimension;

  /// 向量 profile 标识（同一空间才能计算相似度）。
  String get profileId;

  Future<List<double>> embed(String text);
}

abstract class BatchEmbeddingProvider implements EmbeddingProvider {
  Future<List<List<double>>> embedBatch(List<String> texts);
}

abstract interface class EmbeddingCache {
  void clearCache();
}
