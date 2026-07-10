import 'package:attune/features/auth/utility/auth_exports.dart';


class LoginScreenOptions extends ConsumerWidget {
  final String from;
  const LoginScreenOptions({super.key, this.from = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;

    Widget _buildAuthButtons() {
      final loc = AppLocalizations.of(context)!;
      final authButtons = getAuthButtons(loc, from, ref); // Add ref here

      return Column(
        children:
            authButtons
                .mapIndexed(
                  (index, button) => Padding(
                    padding: EdgeInsets.only(
                      bottom: index < authButtons.length - 1 ? Spacing.sm.h : 0,
                    ),
                    child: AppButton(
                      center: false,
                      elevation: 0,
                      prefixIcon: button.prefixIcon,
                      label: button.label,
                      onPressed:
                          () =>
                              button.onPressed?.call(context), // Use safe call
                      iconData: button.icon,
                      borderRadius: BorderRadiusTokens.xlAll,
                      size: ButtonSize.small,
                      width: double.infinity,
                      padding: Spacing.horizontalMd,
                      height: 50.h,
                      textColor: colorScheme.onBackground.withOpacity(.7),
                      customColor: colorScheme.background,
                    ),
                  ),
                )
                .toList(),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          if (from != 'Register')
            AppIconButton(
              iconColor: colorScheme.background,
              icon: Icons.rocket_launch,
              onPressed: () async {
               
                BottomSheetUtils.showDocumentationBottomSheet(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                  context: context,
                  widget: AllLegalDocumentationsScreen(),
                );
              },
            ),

          // Icon(Icons.rocket_launch, size: 30.h, color: colorScheme.background),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: Spacing.horizontalLG,
          child: // Use it
              ListView(
            children: [
              Gap(Spacing.xxl.h),
              Gap(Spacing.xxl.h),

              Gap(Spacing.xxl.h),
              Center(
                child: Text(
                  from == 'Register' ? loc.createAccount : loc.signInTitle,
                  style: textTheme.displayLarge?.copyWith(
                    fontSize: from == 'Register' ? 30.sp : 40.sp,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.background,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              Gap(Spacing.md.h),
              Column(children: [Gap(Spacing.xs.h), _buildAuthButtons()]),
              Gap(Spacing.sm.h),
              if (from != 'Register')
                AppButton(
                  height: 45.h,
                  label: loc.createAccount,
                  onPressed: () {
                    BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      document: LegalDocumentationData.eula(context),
                      onAgree: () {
                        context.goNamed('loginOptions', extra: 'Register');
                      },
                      onDecline: () {
                        Navigator.pop(context);
                      },
                      agreeButtonText: loc.commonAccept,
                      declineButtonText: loc.commonReject,
                    );
                  },
                  borderRadius: BorderRadiusTokens.xlAll,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  width: double.infinity,
                  outlineColor: colorScheme.background,
                  textColor: colorScheme.background,
                ),
              if (from == 'Register') Gap(Spacing.md.h),
              if (from == 'Register')
                HighlightedText(
                  highlightFontColor: colorScheme.background,
                  baseFontColor: colorScheme.background,
                  baseFontSize: 11.sp,
                  fullText:
                      '${loc.legalConsentPart1}${loc.legalConsentPart2}${loc.legalConsentPart3(AppConstants.appName)}',
                  highlightedParts: [
                    HighlightedPart(
                      text: loc.legalConsentPart2,
                      onTap: () {
                        BottomSheetUtils.showDocumentationBottomSheet(
                          maxHeight: MediaQuery.of(context).size.height * 0.7,
                          context: context,
                          widget: AllLegalDocumentationsScreen(),
                        );
                      },
                    ),
                  ],
                  textAlign: TextAlign.center,
                ),

              Gap(Spacing.xxl.h + 30.h),
            ],
          ),
        ),
      ),
    );
  }
}
