import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';

class CountryCodeButton extends StatelessWidget {
  const CountryCodeButton({
    super.key,
    required this.country,
    required this.enabled,
    required this.onSelected,
    this.height,
    this.isSmall = false,
  });

  final PhoneCountry country;
  final bool enabled;
  final ValueChanged<PhoneCountry> onSelected;
  final double? height;
  final bool isSmall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = colorScheme.outline.withValues(
      alpha:
          enabled
              ? FormTokens.fieldBorderOpacity
              : FormTokens.disabledFieldBorderOpacity,
    );

    return Padding(
      padding: EdgeInsets.only(top: Spacing.xs.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            country.flag,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
              fontSize: FontSizeTokens.sm.sp,
            ),
          ),
          Gap(Spacing.xs.h),
          InkWell(
            onTap: enabled ? () => _showCountryPicker(context) : null,
            borderRadius: BorderRadius.circular(
              FormTokens.defaultFieldRadius.r,
            ),
            child: Container(
              height: _calculateHeight(),
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              decoration: BoxDecoration(
                color:
                    isDark
                        ? colorScheme.surface.withValues(
                          alpha: FormTokens.darkFieldFillOpacity,
                        )
                        : colorScheme.surface,
                borderRadius: BorderRadius.circular(
                  FormTokens.defaultFieldRadius.r,
                ),
                border: Border.all(
                  color: borderColor,
                  width: FormTokens.defaultFieldBorderWidth,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    country.dialCode,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Gap(Spacing.xs.w),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: IconSizes.sm.r,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateHeight() {
    if (height != null) return height!;
    return isSmall
        ? FormTokens.compactFieldHeight.h - Spacing.sm.h
        : FormTokens.defaultFieldHeight.h;
  }

  Future<void> _showCountryPicker(BuildContext context) async {
    await BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      padding: 0,
      widget: PhoneCountryPickerSheet(
        selectedCountry: country,
        onCountrySelected: onSelected,
      ),
    );
  }
}
