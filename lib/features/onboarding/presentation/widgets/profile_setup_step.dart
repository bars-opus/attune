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
    final colorScheme = Theme.of(context).colorScheme;

    return OnboardingStepFrame(
      title: 'What should Attune call you?',
      icon: Icons.badge_outlined,
      subtitle:
          'Use the name you want to see in chat. Opinions and forums stay anonymous.',
      child: Column(
        children: [
          AppTextFormField(
            controller: controller,
            label: 'Display name',
            hintText: 'Harold',
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(context),
            // The keyboard should already be up when this screen appears —
            // typing a name is the only thing to do here.
            autofocus: true,
          ),
          // Fixed gap rather than Spacer: Spacer needs a bounded height, which
          // conflicts with the card.s scroll fallback on short screens.
          Gap(Spacing.xl.h),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return AppButton(
                label: 'Continue',
                textColor: colorScheme.surface,
                // Disabled until a real name is forming — at least two
                // letters typed, so stray whitespace/digits/a single
                // keystroke can't submit.
                onPressed: _hasValidName ? () => _submit(context) : null,
                size: ButtonSize.small,
                height: OnboardingTokens.actionButtonHeight.h,
              );
            },
          ),
        ],
      ),
    );
  }

  bool get _hasValidName =>
      RegExp('[a-zA-Z]').allMatches(controller.text).length >= 2;

  void _submit(BuildContext context) {
    if (!_hasValidName) {
      context.showErrorSnackbar('Add a display name to continue.');
      return;
    }
    onNext();
  }
}
