import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

class PersonalReadyStep extends StatelessWidget {
  const PersonalReadyStep({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OnboardingStepFrame(
      title: 'Personal mode is ready',
      icon: Icons.self_improvement_outlined,
      subtitle:
          'No waiting screen and no partner invite. You can start reflecting immediately.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OnboardingInfoTile(
            icon: Icons.psychology_alt_outlined,
            title: 'Reflection baseline saved',
            subtitle: 'Attune has your first self-reflection context.',
          ),
          const OnboardingInfoTile(
            icon: Icons.edit_note_outlined,
            title: 'Personal anchors saved',
            subtitle: 'These become your first reflection context.',
          ),
          // Fixed gap rather than Spacer: Spacer needs a bounded height, which
          // conflicts with the card.s scroll fallback on short screens.
          Gap(Spacing.xl.h),
          AppButton(
            label: 'Enter Attune',
            onPressed: onFinish,
            textColor: colorScheme.surface,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
  }
}
