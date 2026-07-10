import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

class ProfileSetupStep extends StatelessWidget {
  const ProfileSetupStep({
    super.key,
    required this.controller,
    required this.onNext,
  });

  final TextEditingController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepFrame(
      title: 'What should Attune call you?',
      subtitle: 'Use the name you want to see in chat and insights.',
      child: Column(
        children: [
          AppTextFormField(
            controller: controller,
            label: 'Display name',
            hintText: 'Jordan',
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(context),
          ),
          const Spacer(),
          AppButton(
            label: 'Continue',
            onPressed: () => _submit(context),
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
  }

  void _submit(BuildContext context) {
    if (controller.text.trim().isEmpty) {
      context.showErrorSnackbar('Add a display name to continue.');
      return;
    }
    onNext();
  }
}
