import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

class PersonalReadyStep extends StatelessWidget {
  const PersonalReadyStep({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepFrame(
      title: 'Personal mode is ready',
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
