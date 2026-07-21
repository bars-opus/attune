import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_choice_button.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

class OnboardingModeStep extends StatelessWidget {
  const OnboardingModeStep({
    super.key,
    required this.selectedMode,
    required this.onSelect,
  });

  final OnboardingMode? selectedMode;
  final ValueChanged<OnboardingMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepFrame(
      title: 'Are you single or in a relationship?',
      icon: Icons.favorite,
      subtitle: 'This first choice routes your entire Attune experience.',
      child: Column(
        children: [
          OnboardingChoiceButton(
            title: 'Single',
            subtitle: 'Build self-understanding and relationship patterns.',
            selected: selectedMode == OnboardingMode.personal,
            onTap: () => onSelect(OnboardingMode.personal),
          ),
          Gap(Spacing.smMd.h),
          OnboardingChoiceButton(
            title: 'In a relationship',
            // Decision 29: nothing a couples user sees before chat unlocks may
            // hint at analysis/insights — sell only the private shared space.
            subtitle:
                'Invite your partner into a private space for just the two of you.',
            selected: selectedMode == OnboardingMode.couples,
            onTap: () => onSelect(OnboardingMode.couples),
          ),
        ],
      ),
    );
  }
}
