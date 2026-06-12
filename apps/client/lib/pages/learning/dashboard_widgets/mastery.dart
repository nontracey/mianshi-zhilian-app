part of '../dashboard_widgets.dart';


class DomainDropdown extends StatelessWidget {
  const DomainDropdown({
    super.key,
    required this.currentDomainId,
    required this.domains,
    required this.onChanged,
  });

  final String currentDomainId;
  final List<Domain> domains;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.borderMidnightSubtle
            : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? AppColors.borderMidnight : const Color(0xFFE0E0E0),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentDomainId,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: isDark ? Colors.white54 : AppColors.textTertiary,
          ),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : AppColors.textSecondary,
          ),
          items: domains
              .map((d) => DropdownMenuItem(value: d.id, child: Text(d.title)))
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

// ── 掌握度概览组件 ──

class MasteryOverview extends StatelessWidget {
  const MasteryOverview({
    super.key,
    required this.masteryPercent,
    required this.masteredPercent,
    required this.learningPercent,
    required this.newPercent,
  });

  final int masteryPercent;
  final int masteredPercent;
  final int learningPercent;
  final int newPercent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // 环形图
        SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: masteryPercent / 100,
                  strokeWidth: 8,
                  backgroundColor: AppColors.success.withValues(alpha: 0.1),
                  color: AppColors.success,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$masteryPercent',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    l10n.get('mastery'),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // 掌握程度百分比
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MasteryStatItem(
                label: l10n.get('skilled_training'),
                value: '$masteredPercent%',
                color: AppColors.success,
              ),
              const SizedBox(height: 8),
              MasteryStatItem(
                label: l10n.get('study_in'),
                value: '$learningPercent%',
                color: AppColors.accent,
              ),
              const SizedBox(height: 8),
              MasteryStatItem(
                label: l10n.get('un_mastery'),
                value: '$newPercent%',
                color: AppColors.warning,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CategoryMastery {
  final String name;
  final int masteryPercent;

  const CategoryMastery({required this.name, required this.masteryPercent});
}

class MasteryStatItem extends StatelessWidget {
  const MasteryStatItem({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── 掌握度统计组件 ──

class MasteryStats extends StatelessWidget {
  const MasteryStats({super.key, required this.categories});

  final List<CategoryMastery> categories;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    if (categories.isEmpty) {
      return Center(
        child: Text(
          l10n.get('temporary_no_score_category_data'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: categories.take(4).map((cat) {
            final color = cat.masteryPercent >= 85
                ? AppColors.success
                : cat.masteryPercent >= 60
                ? AppColors.accent
                : cat.masteryPercent > 0
                ? AppColors.warning
                : Colors.grey;
            return SizedBox(
              width: cardWidth,
              child: MasteryStatCard(
                title: cat.name,
                value: '${cat.masteryPercent}%',
                color: color,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class MasteryStatCard extends StatelessWidget {
  const MasteryStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 领域知识卡片组件 ──
