import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

class CouplesJoinedStep extends StatelessWidget {
  const CouplesJoinedStep({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepFrame(
      title: 'You are connected',
      subtitle:
          'Your partner invite has been accepted. Finish onboarding and Attune will open the shared experience.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OnboardingInfoTile(
            icon: Icons.check_circle_outline,
            title: 'Partner link confirmed',
            subtitle: 'This account is now attached to the relationship.',
          ),
          const OnboardingInfoTile(
            icon: Icons.edit_note_outlined,
            title: 'Your context is ready',
            subtitle:
                'Your reflections and anchors can now support shared context.',
          ),
          const Spacer(),
          AppButton(
            label: 'Enter Attune',
            onPressed: onFinish,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
  }
}
