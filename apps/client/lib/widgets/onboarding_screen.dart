import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/localization_provider.dart';
import '../providers/settings_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    final steps = _buildSteps(l10n);
    final isLast = _index == steps.length - 1;
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 720;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, compact ? 12 : 24, 24, 24),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    l10n.get('app_name'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _complete,
                    child: Text(l10n.get('onboarding_skip')),
                  ),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: steps.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) =>
                      _OnboardingPage(step: steps[index], compact: compact),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _PageDots(count: steps.length, activeIndex: _index),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: isLast ? _complete : _next,
                    icon: Icon(
                      isLast ? Icons.check_circle_outline : Icons.arrow_forward,
                    ),
                    label: Text(
                      isLast
                          ? l10n.get('onboarding_start')
                          : l10n.get('onboarding_next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_OnboardingStep> _buildSteps(LocalizationProvider l10n) => [
    _OnboardingStep(
      icon: Icons.route_outlined,
      color: const Color(0xFF3078F0),
      title: l10n.get('onboarding_route_title'),
      body: l10n.get('onboarding_route_body'),
      bullets: [
        l10n.get('onboarding_route_bullet_1'),
        l10n.get('onboarding_route_bullet_2'),
        l10n.get('onboarding_route_bullet_3'),
      ],
    ),
    _OnboardingStep(
      icon: Icons.record_voice_over_outlined,
      color: const Color(0xFF10B981),
      title: l10n.get('onboarding_recall_title'),
      body: l10n.get('onboarding_recall_body'),
      bullets: [
        l10n.get('onboarding_recall_bullet_1'),
        l10n.get('onboarding_recall_bullet_2'),
        l10n.get('onboarding_recall_bullet_3'),
      ],
    ),
    _OnboardingStep(
      icon: Icons.query_stats_outlined,
      color: const Color(0xFFF59E0B),
      title: l10n.get('onboarding_mastery_title'),
      body: l10n.get('onboarding_mastery_body'),
      bullets: [
        l10n.get('onboarding_mastery_bullet_1'),
        l10n.get('onboarding_mastery_bullet_2'),
        l10n.get('onboarding_mastery_bullet_3'),
      ],
    ),
    _OnboardingStep(
      icon: Icons.privacy_tip_outlined,
      color: const Color(0xFF6366F1),
      title: l10n.get('onboarding_privacy_title'),
      body: l10n.get('onboarding_privacy_body'),
      bullets: [
        l10n.get('onboarding_privacy_bullet_1'),
        l10n.get('onboarding_privacy_bullet_2'),
        l10n.get('onboarding_privacy_bullet_3'),
      ],
    ),
  ];

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _complete() async {
    await context.read<SettingsProvider>().completeOnboarding();
    if (mounted) {
      context.go('/');
    }
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.bullets,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final List<String> bullets;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.step, required this.compact});

  final _OnboardingStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconSize = compact ? 74.0 : 88.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: step.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                step.icon,
                size: compact ? 38 : 46,
                color: step.color,
              ),
            ),
            SizedBox(height: compact ? 24 : 36),
            Text(
              step.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              step.body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.7,
              ),
            ),
            SizedBox(height: compact ? 20 : 28),
            ...step.bullets.map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: step.color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      children: List.generate(count, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(right: 8),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
