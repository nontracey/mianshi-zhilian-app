import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/models/app_settings.dart';
import 'package:mianshi_zhilian/models/user.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/pages/profile/ai_config_page.dart';

LocalizationProvider l10nOf(BuildContext context) =>
    context.watch<LocalizationProvider>();

class AiModelIconButton extends StatelessWidget {
  const AiModelIconButton({required this.hasConfig, required this.isDark});

  final bool hasConfig;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AiConfigPage()));
      },
      icon: Icon(
        Icons.smart_toy_outlined,
        size: 20,
        color: hasConfig
            ? const Color(0xFF3078F0)
            : (isDark ? Colors.white38 : Colors.grey),
      ),
      tooltip: hasConfig
          ? l10nOf(context).get('ai_model')
          : l10nOf(context).get('ai_not_config'),
      style: IconButton.styleFrom(
        backgroundColor: hasConfig
            ? const Color(0xFF3078F0).withValues(alpha: 0.1)
            : (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04)),
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class AiModelSelector extends StatelessWidget {
  const AiModelSelector({
    required this.modelName,
    required this.hasConfig,
    required this.isDark,
  });

  final String modelName;
  final bool hasConfig;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return InkWell(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AiConfigPage()));
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 16,
              color: hasConfig
                  ? const Color(0xFF3078F0)
                  : (isDark ? Colors.white38 : Colors.grey),
            ),
            const SizedBox(width: 6),
            Text(
              hasConfig ? modelName : l10n.get('ai_not_config'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: hasConfig
                    ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                    : (isDark ? Colors.white38 : Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContentStageSelector extends StatefulWidget {
  const ContentStageSelector({
    required this.isDark,
    required this.currentEnv,
    this.userRole = UserRole.guest,
    this.onStageChanged,
  });

  final bool isDark;
  final ContentEnv currentEnv;
  final UserRole userRole;
  final ValueChanged<ContentEnv>? onStageChanged;

  @override
  State<ContentStageSelector> createState() => ContentStageSelectorState();
}

class ContentStageSelectorState extends State<ContentStageSelector> {
  LocalizationProvider get l10n => context.watch<LocalizationProvider>();

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final allowedEnvs = widget.userRole.allowedContentEnvs;
    final stages = [
      (
        ContentEnv.production,
        l10n.get('content_published'),
        allowedEnvs.contains(ContentEnv.production.key),
      ),
      (
        ContentEnv.staging,
        l10n.get('content_testing'),
        ContentEnv.staging.isAllowedBy(allowedEnvs),
      ),
      (
        ContentEnv.draft,
        l10n.get('content_draft'),
        allowedEnvs.contains(ContentEnv.draft.key),
      ),
    ];
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 600;

    if (isWide) {
      return Row(
        children: [
          Text(
            l10n.get('content_label'),
            style: TextStyle(
              fontSize: 12,
              color: widget.isDark ? Colors.white54 : const Color(0xFF666666),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: widget.isDark
                  ? const Color(0xFF21262D)
                  : const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(2),
            child: Row(
              children: stages.map((stage) {
                final isSelected = stage.$1 == widget.currentEnv;
                final isEnabled = stage.$3;

                return GestureDetector(
                  onTap: isEnabled
                      ? () {
                          widget.onStageChanged?.call(stage.$1);
                        }
                      : () {
                          final message = widget.userRole == UserRole.guest
                              ? l10n.get('login_for_testing')
                              : l10n.get('admin_for_draft');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(message),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          stage.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : isEnabled
                                    ? (widget.isDark
                                        ? Colors.white70
                                        : const Color(0xFF666666))
                                    : (widget.isDark
                                        ? Colors.white30
                                        : Colors.grey.shade400),
                          ),
                        ),
                        if (!isEnabled) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.lock_outline,
                            size: 10,
                            color: widget.isDark
                                ? Colors.white30
                                : Colors.grey.shade400,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    return PopupMenuButton<ContentEnv>(
      offset: const Offset(0, 40),
      onSelected: (stage) {
        widget.onStageChanged?.call(stage);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.isDark
              ? const Color(0xFF21262D)
              : const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              stages.firstWhere((s) => s.$1 == widget.currentEnv).$2,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: widget.isDark ? Colors.white70 : const Color(0xFF666666),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: widget.isDark ? Colors.white70 : const Color(0xFF666666),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => stages.map((stage) {
        final isEnabled = stage.$3;
        return PopupMenuItem<ContentEnv>(
          enabled: isEnabled,
          value: stage.$1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stage.$2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: stage.$1 == widget.currentEnv
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: !isEnabled
                      ? (widget.isDark ? Colors.white30 : Colors.grey.shade400)
                      : null,
                ),
              ),
              if (!isEnabled) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.lock_outline,
                  size: 12,
                  color: widget.isDark ? Colors.white30 : Colors.grey.shade400,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
