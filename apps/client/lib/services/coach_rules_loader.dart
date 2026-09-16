/// 教练规则文件加载器（Flutter 侧）。
///
/// 从 `assets/coach/*.md` 读取中性规则文本，供 [CoachPromptBuilder] 组装系统提示词。
/// 读取失败（缺文件 / 平台不支持 asset）时不抛出，返回可得的部分；核心段缺失时
/// 由 [CoachPromptBuilder] 用内置兜底补齐，保证「不编造 / 不越权」始终生效。
///
/// 本文件是 **Flutter 依赖**（`rootBundle`）；纯 Dart 测试请直接向
/// [CoachPromptBuilder] 传字符串，不要 import 本文件。
library;

import 'package:flutter/services.dart' show rootBundle;

import '../coach/application/prompt_builder.dart';

class CoachRulesLoader {
  CoachRulesLoader({Map<CoachRuleSection, String>? overrides})
    : _overrides = overrides ?? const {};

  /// 测试/定制注入：命中则不读 asset。
  final Map<CoachRuleSection, String> _overrides;

  Map<CoachRuleSection, String>? _cache;

  /// asset 路径：`assets/coach/<fileName>.md`。
  static String assetPathOf(CoachRuleSection section) =>
      'assets/coach/${section.fileName}.md';

  /// 加载全部分区（带进程内缓存）。
  Future<Map<CoachRuleSection, String>> load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final result = <CoachRuleSection, String>{};
    for (final section in CoachRuleSection.values) {
      final override = _overrides[section];
      if (override != null) {
        result[section] = override;
        continue;
      }
      final text = await _tryLoadAsset(assetPathOf(section));
      if (text != null && text.trim().isNotEmpty) {
        result[section] = text;
      }
    }
    _cache = result;
    return result;
  }

  Future<String?> _tryLoadAsset(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      // 缺文件或平台不支持 asset：静默跳过，交由 prompt builder 兜底。
      return null;
    }
  }

  /// 清空缓存（热重载/规则更新后调用）。
  void invalidate() {
    _cache = null;
  }
}
