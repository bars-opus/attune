import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

class IncomingInviteStep extends StatelessWidget {
  const IncomingInviteStep({
    super.key,
    required this.inviteCode,
    required this.onNext,
  });

  final String inviteCode;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepFrame(
      title: 'You have a partner invite',
      subtitle:
          'Attune will place you in relationship mode and connect both sides after you verify your account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnboardingInfoTile(
            icon: Icons.favorite_border,
            title: 'Private invite code',
            subtitle: inviteCode,
          ),
          const OnboardingInfoTile(
            icon: Icons.lock_outline,
            title: 'Verification comes next',
            subtitle:
                'Use your phone number to verify the account before the invite is accepted.',
          ),
          // Fixed gap rather than Spacer: Spacer needs a bounded height, which
          // conflicts with the card.s scroll fallback on short screens.
          Gap(Spacing.xl.h),
          AppButton(
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
