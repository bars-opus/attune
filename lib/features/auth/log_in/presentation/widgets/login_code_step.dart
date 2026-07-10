import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/verification_code_countdown.dart';

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
          Gap(Spacing.lg.h),
          AppTextFormField(
            controller: controller,
            label: 'Verification code',
            hintText: '123456',
            prefixIcon: Icons.lock_outline,
            keyboardType: TextInputType.number,
            focusNode: focusNode,
            enabled: enabled,
            autofillHints: const [AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: onSubmitted,
          ),
          SemanticContainerWidget(
            title: 'Enter your code',
            content:
                phoneNumber.isEmpty
                    ? 'Request a verification code first.'
                    : 'We sent a code to $phoneNumber. It expires in 60 seconds.',
            icon: Icons.sms_outlined,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
            borderColor: colorScheme.primary,
            iconColor: colorScheme.primary,
            textTheme: textTheme,
          ),
          Gap(Spacing.xxl.h),
          if (resendSecondsRemaining > 0)
            VerificationCodeCountdown(
              secondsRemaining: resendSecondsRemaining,
            )
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
