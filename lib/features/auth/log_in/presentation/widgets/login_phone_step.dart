import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_number_field.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPhoneStep extends StatelessWidget {
  const LoginPhoneStep({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.country,
    required this.enabled,
    required this.authConfigured,
    required this.otpChannel,
    required this.onCountryChanged,
    required this.onOtpChannelChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PhoneCountry country;
  final bool enabled;
  final bool authConfigured;
  final OtpChannel otpChannel;
  final ValueChanged<PhoneCountry> onCountryChanged;
  final ValueChanged<OtpChannel> onOtpChannelChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gap(Spacing.md.h),
          PhoneNumberField(
            controller: controller,
            focusNode: focusNode,
            country: country,
            enabled: enabled,
            onCountryChanged: onCountryChanged,
            onSubmitted: onSubmitted,
          ),
          Gap(Spacing.lg.h),
          Row(
            children: [
              Icon(
                FontAwesomeIcons.whatsapp,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              Gap(Spacing.sm.w),
              Expanded(
                child: Text(
                  'Send verification code via WhatsApp.\nAttune uses phone OTP at launch to keep relationship and community actions accountable.',
                  style: textTheme.bodySmall,
                ),
              ),
              AppToggleSwitch(
                toggleValue: otpChannel == OtpChannel.whatsapp,
                onToggleChanged: (useWhatsapp) {
                  onOtpChannelChanged(
                    useWhatsapp ? OtpChannel.whatsapp : OtpChannel.sms,
                  );
                },
              ),
            ],
          ),

        ],
      ),
    );
  }
}
