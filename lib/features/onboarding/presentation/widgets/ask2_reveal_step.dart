import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

/// Terminal screen of Ask 2 (Spec 5; research 06 §3 F9 (1)): the person's
/// own first two anchors reflected back -- what they admire, what they hope
/// for more of -- and "something for tonight". Never a pairing or a type
/// statement about the couple. The third anchor (a past pattern) is personal
/// and stays off a celebratory screen.
class Ask2RevealStep extends StatelessWidget {
  const Ask2RevealStep({
    super.key,
    required this.anchors,
    required this.onDone,
    required this.onLoveMap,
    required this.onThisOrThat,
  });

  final List<String> anchors;
  final VoidCallback onDone;
  final VoidCallback onLoveMap;
  final VoidCallback onThisOrThat;

  String? _anchor(int i) {
    if (i >= anchors.length) return null;
    final a = anchors[i].trim();
    return a.isEmpty ? null : a;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final admire = _anchor(0);
    final hope = _anchor(1);

    Widget reflected(String label, String value) => Padding(
      padding: EdgeInsets.only(bottom: Spacing.md.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant)),
          Gap(Spacing.xs.h),
          Text('“$value”', style: text.titleMedium),
        ],
      ),
    );

    return OnboardingStepFrame(
      title: "You're both in",
      icon: Icons.favorite_outline,
      subtitle: 'Here is what you said matters to you.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap(Spacing.lg.h),
          if (admire != null) reflected('You admire', admire),
          if (hope != null) reflected('You hope for more of', hope),
          Gap(Spacing.md.h),
          Text('Something for tonight', style: text.titleSmall),
          Gap(Spacing.sm.h),
          OutlinedButton(onPressed: onLoveMap, child: const Text('A Love map round')),
          Gap(Spacing.sm.h),
          OutlinedButton(onPressed: onThisOrThat, child: const Text('This or That')),
          Gap(Spacing.xl.h),
          AppButton(
            textColor: colorScheme.surface,
            label: 'Done',
            onPressed: onDone,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
  }
}
