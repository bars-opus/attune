import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/country_code_button.dart';

class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.country,
    required this.enabled,
    required this.onCountryChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PhoneCountry country;
  final bool enabled;
  final ValueChanged<PhoneCountry> onCountryChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CountryCodeButton(
          country: country,
          isSmall: true,
          enabled: enabled,
          onSelected: onCountryChanged,
        ),
        Gap(Spacing.sm.w),
        Expanded(
          child: AppTextFormField(
            borderRadius: BorderRadius.circular(
              FormTokens.defaultFieldRadius.r,
            ),
            controller: controller,
            label: 'Phone number',
            isSmall: true,
            hintText: country.example,
            keyboardType: TextInputType.phone,
            focusNode: focusNode,
            enabled: enabled,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            textInputAction: TextInputAction.done,
            inputFormatters: [ValidationUtils.phoneFormatter],
            onFieldSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}
