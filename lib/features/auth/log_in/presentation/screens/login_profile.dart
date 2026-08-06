import 'package:attune/features/settings/utility/settings_exports.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

class LoginProfile extends StatelessWidget {
  const LoginProfile({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context)!;

    final overview = loc.authGuestOverview(AppConstants.appName);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: AppIconButton(
                      icon: Icons.menu,
                      onPressed: () => context.push('/settings'),
                    ),
                  ),
                  Gap(Spacing.lg.h),
                  Center(
                    child: Text(
                      loc.authGuestHello,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        fontSize: FontSizeTokens.xxl.sp,
                      ),
                    ),
                  ),

                  Gap(Spacing.md.h),
                  GestureDetector(
                    onTap: () {
                      BottomSheetUtils.showDocumentationBottomSheet(
                        context: context,
                        widget: ReadAll(body: overview),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          overview,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            height: TextHeightTokens.relaxed,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          loc.commonLearnMore,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: FontSizeTokens.xs.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap(Spacing.md.h),

                  AppButton(
                    center: false,
                    elevation: 0,
                    prefixIconColor: colorScheme.surface,
                    label: 'Continue with phone number',
                    // The EULA is NOT shown here. Whether someone is new or
                    // returning is only knowable after OTP verification, so
                    // prompting first meant returning users re-accepted on
                    // every sign-in (and nothing was ever recorded). Consent
                    // now happens once, post-verification, in LoginScreen —
                    // see EulaAcceptanceService.
                    onPressed: () {
                      BottomSheetUtils.showDocumentationBottomSheet(
                        context: context,
                        widget: LoginScreen(),
                      );
                    },
                    iconData: Icons.phone_android_outlined,
                    borderRadius: BorderRadiusTokens.xlAll,
                    size: ButtonSize.small,
                    width: double.infinity,
                    padding: Spacing.horizontalMd,
                    height: OnboardingTokens.actionButtonHeight.h,

                    textColor: colorScheme.surface,
                    customColor: colorScheme.primary,
                  ),
                  Gap(Spacing.md.h - 3),

                  AppButton(
                    height: OnboardingTokens.actionButtonHeight.h,
                    label: 'Invite a friend',
                    onPressed: () {
                      // Debug-only UI preview; release builds keep the real share action.
                      if (kDebugMode) {
                        context.push(RouteNames.onboarding, extra: true);
                        return;
                      }

                      Share.share(
                        'I found ${AppConstants.appName}. It helps people understand relationship patterns and grow with more clarity. ${AppConstants.websiteUrl}',
                        subject: 'Try ${AppConstants.appName}',
                      );
                    },
                    borderRadius: BorderRadiusTokens.xlAll,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    width: double.infinity,
                    outlineColor: colorScheme.onSurface,
                    textColor: colorScheme.onSurface,
                  ),

                  Gap(Spacing.xl.h),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
