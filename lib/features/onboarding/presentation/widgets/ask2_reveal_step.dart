import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

/// Terminal screen of Ask 2. Per the design doc's scope boundary, this is a
/// minimal reveal, not a redesigned compatibility-preview experience — the
/// existing attachment_compatibility_cache RPC/provider already handle the
/// actual computation and read path (lib/features/quiz/presentation/
/// providers/quiz_providers.dart); this screen only confirms completion.
class Ask2RevealStep extends StatelessWidget {
  const Ask2RevealStep({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OnboardingStepFrame(
      title: "You're both in",
      icon: Icons.favorite_outline,
      subtitle:
          'Your compatibility preview is coming together — check back in your profile shortly.',
      child: Column(
        children: [
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
