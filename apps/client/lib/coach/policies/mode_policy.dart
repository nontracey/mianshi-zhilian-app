/// 模式边界策略（§3、§5、§7 模式迁移校验）。
///
/// 学习/回测/模拟共用对话界面，但规则不同：一题一问、提示后不升级、
/// 不会时教学不记 fail、模拟“暂停并讲解”后本场同考点不再算闭卷首答。
library;

import '../domain/common.dart';

/// 模式策略。所有方法纯函数，便于单测。
class ModePolicy {
  const ModePolicy();

  /// 是否可记“独立通过”。
  /// - 学习模式不记独立通过（“明白了”只保存覆盖）。
  /// - 带提示或刚教学过同一考点，不算独立通过（§9.4）。
  bool canMarkIndependentPass(
    SessionMode mode, {
    required bool hintUsed,
    required bool justTaught,
  }) {
    if (mode == SessionMode.learning) return false;
    if (hintUsed || justTaught) return false;
    return true;
  }

  /// 是否允许继续追问。
  /// - 回测：最多一层中性追问（§3.4）。
  /// - 模拟：可连续追问，但一次一问（§3.5）。
  /// - 学习：答疑不打断，但不在回测/模拟的“追问”语义内。
  bool allowFollowUp(SessionMode mode, int currentFollowUps) {
    switch (mode) {
      case SessionMode.review:
        return currentFollowUps < 1;
      case SessionMode.interview:
        return true;
      case SessionMode.learning:
        return false;
    }
  }

  /// 模拟“暂停并讲解”后，本场该考点后续回答不能再算闭卷首答（§3.5）。
  bool canCountClosedBookAfterTeaching(
    SessionMode mode, {
    required bool pausedToTeach,
  }) {
    if (mode == SessionMode.interview && pausedToTeach) return false;
    return true;
  }

  /// 学习模式用户说“不会”：继续讲解，不给未学过内容记 fail（§3.3）。
  /// 返回 true 表示应进入补讲而非记录失败。
  bool shouldReTeachOnDontKnow(SessionMode mode) =>
      mode == SessionMode.learning;

  /// 回测必须明确标注“回测”，且每次只针对一个已学具体考点（§3.4）。
  bool isReviewScoped(SessionMode mode, {required bool hasLearnedScope}) =>
      mode != SessionMode.review || hasLearnedScope;
}
