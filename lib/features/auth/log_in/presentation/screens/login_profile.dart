import 'package:attune/features/settings/utility/settings_exports.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';

class LoginProfile extends StatefulWidget {
  const LoginProfile({super.key});

  @override
  State<LoginProfile> createState() => _LoginProfileState();
}

class _LoginProfileState extends State<LoginProfile> {
  late ScrollController _scrollController;
  List<DocumentationModule> modules = [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    DocumentationRegistry.initialize();
    modules = DocumentationRegistry.getAllModules();
    // Schedule the scroll after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && modules.length > 1) {
        // Get the screen width
        final screenWidth = MediaQuery.of(context).size.width;
        final itemWidth = _getItemWidth();

        // Calculate offset to center the second item (index 1)
        // Formula: (itemWidth * index) - (screenWidth/2) + (itemWidth/2)
        final offset = (itemWidth * 1) - (screenWidth / 2) + (itemWidth / 2);

        // Ensure offset is not negative (for first items)
        final clampedOffset = offset.clamp(0.0, double.infinity);

        _scrollController.jumpTo(clampedOffset);
      }
    });

    // A returning couplesPending user (app restart, re-navigation) has no
    // locally-held invite — `_invite` only ever lived in this State object,
    // never persisted. ATTUNE_MASTER_SPEC.md: "Invite codes are reusable
    // until accepted or expired," and create-relationship-invite already
    // returns the existing live invite instead of minting a new one, so
    // silently re-fetching here re-displays the same code rather than
    // creating a duplicate. onInviteSent() is NOT called from this path —
    // the user is already on the couplesPending track, so there is nothing
    // new for the app shell to persist.
  }

  double _getItemWidth() {
    return 250.w; // Your item width
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context)!;

    final overview = loc.authGuestOverview(AppConstants.appName);

    return Material(
      color: colorScheme.neutral,
      child: CustomScrollView(
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
                          padding: 0,
                          backgroundColor: colorScheme.neutral,
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

                    // Gap(Spacing.xl.h),
                    Gap(Spacing.xxl.h),
                    SizedBox(
                      height: 250.h,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: modules.length,
                        itemBuilder: (context, index) {
                          final module = modules[index];
                          return SizedBox(
                            width: 250.w, // Make sure items have fixed width
                            child: IntroGuideWidget(module: module),
                          );
                        },
                      ),
                    ),
                    Gap(Spacing.xxl.h),
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          BottomSheetUtils.showDocumentationBottomSheet(
                            maxHeight: MediaQuery.of(context).size.height * 0.7,
                            context: context,
                            widget: AllLegalDocumentationsScreen(),
                          );
                        },
                        child: Text(
                          loc.authReadLegalities,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    Gap(Spacing.xxl.h * 3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
