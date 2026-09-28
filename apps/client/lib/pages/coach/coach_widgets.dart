/// 教练页面公共小组件。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/goal_provider.dart';
import '../../providers/localization_provider.dart';
import '../../theme/colors.dart';
import '../../widgets/work_panel.dart';

/// 教练页面统一骨架：标题 + 可滚动内容 + 可选右侧动作。
class CoachPageScaffold extends StatelessWidget {
  const CoachPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...actions,
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.read<LocalizationProvider>().get('settings'),
            onPressed: () => context.push('/profile'),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.white60 : AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 空状态提示块。
class CoachEmptyHint extends StatelessWidget {
  const CoachEmptyHint({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDark ? Colors.white38 : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? Colors.white60 : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 中性提示条（用于「模型未配置」「数据未确认」等诚实告知）。
class CoachNoticeBanner extends StatelessWidget {
  const CoachNoticeBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.tone = CoachNoticeTone.info,
    this.action,
  });

  final String message;
  final IconData icon;
  final CoachNoticeTone tone;

  /// 可选的补救入口（如「重试」）。提示条本身不承载业务判断。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (tone) {
      CoachNoticeTone.info => AppColors.info,
      CoachNoticeTone.warning => AppColors.warning,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: isDark ? Colors.white70 : AppColors.textPrimary,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action!,
          ],
        ],
      ),
    );
  }
}

enum CoachNoticeTone { info, warning }

/// 便捷：把一组子项塞进一个 [WorkPanel]。
WorkPanel coachPanel({
  required String title,
  required List<Widget> children,
  IconData? icon,
  Widget? trailing,
}) =>
    WorkPanel(title: title, icon: icon, trailing: trailing, children: children);

/// 把 [ImportOutcome] 渲染成本地化文案。
///
/// provider 只回传 l10n key；翻译集中在这一处，避免各页面各自拼装。
/// [diagnostics] 同样是 key（解析/网络失败原因由纯 Dart 层以 key 抛出）。
/// `L10n.get` 对未知 key 原样返回，所以偶发的原始调试文本也能安全显示。
String coachOutcomeText(LocalizationProvider l10n, ImportOutcome outcome) {
  final parts = <String>[
    l10n.getp(outcome.messageKey, outcome.messageParams),
    ...outcome.noteKeys.map(l10n.get),
    ...outcome.diagnostics.map(l10n.get),
  ];
  return parts.where((s) => s.trim().isNotEmpty).join('\n');
}

/// 弹窗里的输入控制器统一在**下一帧**释放。
///
/// `await showDialog` 返回时弹窗路由的关闭动画可能尚未结束，TextField 仍持有
/// controller；此刻 dispose 会让 focus scope 在错误的 build scope 里重建，
/// 表现为 "Tried to build dirty widget in the wrong build scope"。
void disposeControllersNextFrame(List<TextEditingController> controllers) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final controller in controllers) {
      controller.dispose();
    }
  });
}
