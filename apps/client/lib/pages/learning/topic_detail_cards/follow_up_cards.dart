part of '../topic_detail_cards.dart';

// ── 追问区域（可折叠）────────────────────────────────────────

class FollowUpSection extends StatelessWidget {
  const FollowUpSection({required this.followUps});
  final List<FollowUpQuestion> followUps;

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return WorkPanel(
      title: l10n.get('common_follow_up'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.categoryPurple.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          l10n.getp('count_question_count_2', {'count': followUps.length}),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.categoryPurple,
          ),
        ),
      ),
      children: [
        ...followUps.asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FollowUpCard(index: entry.key + 1, question: entry.value),
          ),
        ),
      ],
    );
  }
}

class FollowUpCard extends StatefulWidget {
  const FollowUpCard({required this.index, required this.question});
  final int index;
  final FollowUpQuestion question;

  @override
  State<FollowUpCard> createState() => FollowUpCardState();
}

class FollowUpCardState extends State<FollowUpCard>
    with AutomaticKeepAliveClientMixin {
  bool _expanded = false;

  // 知识列表已虚拟化，展开后即使滚出视口也保活，避免回到此卡时展开态丢失。
  @override
  bool get wantKeepAlive => _expanded;

  Color get _difficultyColor {
    return switch (widget.question.difficulty) {
      1 => AppColors.success,
      2 => AppColors.accent,
      3 => AppColors.warning,
      4 || 5 => AppColors.danger,
      _ => Colors.grey,
    };
  }

  String get _difficultyLabel {
    final l10n = context.watch<LocalizationProvider>();
    return switch (widget.question.difficulty) {
      1 => l10n.get('beginner'),
      2 => l10n.get('basic'),
      3 => l10n.get('medium'),
      4 => l10n.get('compare_difficult'),
      5 => l10n.get('hard'),
      _ => '',
    };
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final l10n = context.watch<LocalizationProvider>();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _expanded
            ? AppColors.categoryPurple.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _expanded
              ? AppColors.categoryPurple.withValues(alpha: 0.3)
              : Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.categoryPurple.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.categoryPurple,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.question.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (_difficultyLabel.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _difficultyColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _difficultyLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _difficultyColor,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: AppColors.categoryPurple.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  if (widget.question.hints.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.question.hints
                          .map(
                            (hint) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                hint,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.codeBgDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.categoryPurple.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: AppColors.categoryPurple,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.get('reference_answer'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.categoryPurple,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: widget.question.answer),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      l10n.get(
                                        'already_review_control_to_clip_clipboard_board',
                                      ),
                                    ),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DefaultTextStyle(
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 13,
                            height: 1.6,
                          ),
                          child: MarkdownContent(data: widget.question.answer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
