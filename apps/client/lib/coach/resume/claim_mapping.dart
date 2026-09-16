/// 简历主张与 JD 要求的映射（§6.9）：三类出题依据。
///
/// - jdAndResume：JD 要求 × 简历主张，优先从“岗位要求且本人经历”切入。
/// - jdOnly：JD 必需但简历无覆盖，作为能力补强或假设设计题。
/// - resumeOnly：简历强主张或用户指定项目，可用于该简历的防守。
///
/// App 校验关联 ID 的归属与版本；模型评测检查语义是否真的相关。
library;

import '../domain/common.dart';
import '../domain/goal.dart';

/// 主张与要求的关联草稿。
class ClaimRequirementLinkDraft {
  ClaimRequirementLinkDraft({
    required this.claimIndex,
    required this.requirementId,
    required this.mappingType,
    this.rationale,
    this.score,
  });

  /// 在解析结果 claims 列表中的下标（构建时转为 claimId）。
  final int claimIndex;
  final RequirementId requirementId;
  final String mappingType;
  final String? rationale;
  final double? score;
}

/// 主张-要求语义匹配器（可注入模型实现；默认提供确定性关键词版本）。
abstract class ClaimMatcher {
  Future<List<ClaimRequirementLinkDraft>> match({
    required List<String> claimStatements,
    required List<GoalRequirement> requirements,
  });
}

/// 确定性关键词匹配器：用集合重叠给分，不依赖模型，可单测。
class KeywordClaimMatcher implements ClaimMatcher {
  KeywordClaimMatcher({this.threshold = 0.15});

  /// 重叠相似度阈值，超过即认为主张覆盖该要求。
  final double threshold;

  @override
  Future<List<ClaimRequirementLinkDraft>> match({
    required List<String> claimStatements,
    required List<GoalRequirement> requirements,
  }) async {
    final claimTokens = claimStatements.map(_tokenize).toList();
    final links = <ClaimRequirementLinkDraft>[];
    final linkedClaims = <int>{};

    for (var ri = 0; ri < requirements.length; ri++) {
      final reqTokens = _tokenize(requirements[ri].title);
      if (reqTokens.isEmpty) continue;
      var best = -1;
      var bestScore = 0.0;
      for (var ci = 0; ci < claimTokens.length; ci++) {
        final score = _overlap(reqTokens, claimTokens[ci]);
        if (score > bestScore) {
          bestScore = score;
          best = ci;
        }
      }
      if (best >= 0 && bestScore >= threshold) {
        links.add(
          ClaimRequirementLinkDraft(
            claimIndex: best,
            requirementId: requirements[ri].id,
            mappingType: 'jdAndResume',
            rationale: '关键词重叠相似度 ${bestScore.toStringAsFixed(2)}',
            score: bestScore,
          ),
        );
        linkedClaims.add(best);
      } else {
        // JD 必需但简历无覆盖。
        links.add(
          ClaimRequirementLinkDraft(
            claimIndex: -1,
            requirementId: requirements[ri].id,
            mappingType: 'jdOnly',
            rationale: '简历未覆盖该要求',
          ),
        );
      }
    }

    // 未被任何要求覆盖的主张：简历强主张 / 用户指定项目，可用于防守。
    for (var ci = 0; ci < claimStatements.length; ci++) {
      if (!linkedClaims.contains(ci)) {
        links.add(
          ClaimRequirementLinkDraft(
            claimIndex: ci,
            requirementId: '',
            mappingType: 'resumeOnly',
            rationale: '主张未匹配到 JD 要求，可作为本人经历防守',
          ),
        );
      }
    }
    return links;
  }

  double _overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    return inter / a.length;
  }

  static Set<String> _tokenize(String text) {
    final out = <String>{};
    final buffer = StringBuffer();
    for (final ch in text.runes.map((r) => String.fromCharCode(r))) {
      final code = ch.codeUnitAt(0);
      final isCjk = code >= 0x4e00 && code <= 0x9fff;
      final isLatin =
          (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
      if (isCjk) {
        if (buffer.isNotEmpty) {
          out.add(buffer.toString().toLowerCase());
          buffer.clear();
        }
        out.add(ch);
        // 二元组提升中文召回。
        // （单字已足够做重叠估算，二元组略去以降低噪音）
      } else if (isLatin) {
        buffer.write(ch);
      } else {
        if (buffer.isNotEmpty) {
          out.add(buffer.toString().toLowerCase());
          buffer.clear();
        }
      }
    }
    if (buffer.isNotEmpty) out.add(buffer.toString().toLowerCase());
    // 去掉停用词级别的单字符，减少误匹配。
    out.removeWhere((t) => t.length <= 1 && !_isCjkChar(t));
    return out;
  }

  static bool _isCjkChar(String s) =>
      s.isNotEmpty && s.codeUnitAt(0) >= 0x4e00 && s.codeUnitAt(0) <= 0x9fff;
}
