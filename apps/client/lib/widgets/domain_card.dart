import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/localization_provider.dart';
import '../models/domain.dart';
import '../theme/colors.dart';

class DomainCard extends StatelessWidget {
  const DomainCard({
    super.key,
    required this.domain,
    required this.masteryPercent,
    required this.selected,
    required this.onTap,
  });

  final Domain domain;
  final int masteryPercent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return SizedBox(
      width: 330,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                domain.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(domain.description),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: masteryPercent / 100,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.accent,
              ),
              const SizedBox(height: 8),
              Text(l10n.getp('domain_mastery_tap_switch', {'percent': '$masteryPercent'})),
            ],
          ),
        ),
      ),
    );
  }
}
