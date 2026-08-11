import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/verification_code_countdown.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/verification_code_field.dart';

class LoginCodeStep extends StatelessWidget {
  const LoginCodeStep({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.phoneNumber,
    required this.resendSecondsRemaining,
    required this.onSubmitted,
    required this.onResend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String phoneNumber;
  final int resendSecondsRemaining;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gap(Spacing.md.h),

          VerificationCodeField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            // Auto-verifies the instant all six boxes are filled — no
            // separate submit action for the code step.
            onCompleted: onSubmitted,
          ),
          Gap(Spacing.lg.h),
          SemanticContainerWidget(
            isSkeleton: true,
            title: 'Enter your code',
            content:
                phoneNumber.isEmpty
                    ? 'Request a verification code first.'
                    : 'We sent a code to $phoneNumber. It expires in 60 seconds.',
            icon: Icons.sms_outlined,
            backgroundColor: colorScheme.onBackground.withValues(alpha: 0.1),
            borderColor: colorScheme.onBackground,
            iconColor: colorScheme.onBackground,
            textTheme: textTheme,
          ),
          Gap(Spacing.xxl.h),
          if (resendSecondsRemaining > 0)
            VerificationCodeCountdown(
              fontSize: 20.h,
              secondsRemaining: resendSecondsRemaining)
          else if (onResend != null)
            AppTextButton(
              alignment: Alignment.center,
              text: 'Resend verification code',
              onPressed: onResend,
            ),
        ],
      ),
    );
  }
}
