import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/data/attachment_quiz_docs.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

/// The first screen of Ask 2 — the one place in the whole app allowed to
/// introduce "AI/analysis/insight" vocabulary (ATTUNE_MASTER_SPEC.md
/// decision 29's Ask-1 invite rules only restrict Ask 1). Explains why the
/// quiz + anchors are showing up now, anchored to a positive observation
/// rather than a deficit, before asking the couple to continue.
class IntelligenceIntroStep extends StatelessWidget {
  const IntelligenceIntroStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OnboardingStepFrame(
      title: 'A closer look',
      icon: Icons.auto_awesome_outlined,
      subtitle:
          'You two have a real rhythm going. This is optional, and skipping it costs you nothing.',
      child: Column(
        children: [
          Gap(Spacing.xl.h),
          Text(
            'A short quiz and three questions help Attune understand how '
            'you both communicate — so what it shows you actually fits '
            'your relationship, not a generic average.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Gap(Spacing.xl.h),
          AppButton(
            textColor: colorScheme.surface,
            label: 'Continue',
            onPressed: onNext,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
  }
}
