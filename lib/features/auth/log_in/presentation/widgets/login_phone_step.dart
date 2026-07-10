import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_number_field.dart';
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
          Gap(Spacing.md.h),
          SegmentedButton<OtpChannel>(
            segments: const [
              ButtonSegment(
                value: OtpChannel.sms,
                label: Text('SMS'),
                icon: Icon(Icons.sms_outlined),
              ),
              ButtonSegment(
                value: OtpChannel.whatsapp,
                label: Text('WhatsApp'),
                icon: Icon(Icons.chat_outlined),
              ),
            ],
            selected: {otpChannel},
            onSelectionChanged: (values) => onOtpChannelChanged(values.first),
          ),
          Gap(Spacing.sm.h),
          Text(
            'WhatsApp can avoid SMS carrier issues, but it still needs WhatsApp support in Twilio and opt-in on the recipient side.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Gap(Spacing.md.h),
          SemanticContainerWidget(
            title: 'Phone verification',
            content:
                'Attune uses phone OTP at launch to keep relationship and community actions accountable.',
            icon: Icons.verified_user_outlined,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
            borderColor: colorScheme.primary,
            iconColor: colorScheme.primary,
            textTheme: textTheme,
          ),
          if (!authConfigured) ...[
            Gap(Spacing.sm.h),
            SemanticContainerWidget(
              title: 'Local setup needed',
              content:
                  'Add the Attune Supabase URL and anon key to enable phone verification.',
              icon: Icons.info_outline,
              backgroundColor: colorScheme.error.withValues(alpha: 0.1),
              borderColor: colorScheme.error,
              iconColor: colorScheme.error,
              textTheme: textTheme,
            ),
          ],
        ],
      ),
    );
  }
}
