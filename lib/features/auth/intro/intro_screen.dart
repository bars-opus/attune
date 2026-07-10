import 'package:attune/app/documentations/legal_documentation/widgets/all_legal_documentations_screen.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/widgets/animated_circle.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final PageController pageController = PageController();
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
  }

  double _getItemWidth() {
    return 250.w; // Your item width
  }

  // void _startAutoAdvanceTimer() {
  //   autoAdvanceTimer = Timer.periodic(Duration(seconds: 30), (timer) {
  //     if (pageController.hasClients && modules.length > 1) {
  //       final currentPage = pageController.page?.toInt() ?? 0;
  //       final isLastPage = currentPage == modules.length - 1;

  //       if (isLastPage) {
  //         pageController.jumpToPage(0);
  //       } else {
  //         final nextPage = currentPage + 1;
  //         pageController.animateToPage(
  //           nextPage,
  //           duration: Duration(milliseconds: 500),
  //           curve: Curves.easeInOut,
  //         );
  //       }
  //     }
  //   });
  // }

  @override
  void dispose() {
    pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: colorScheme.primary,

      // theme.appColors.appColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top Section with Title and Subtitle
            Padding(
              padding: EdgeInsets.all(20.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Gap(Spacing.xxl.h),
                  AnimatedCircle(
                    size: 50,
                    stroke: 2,
                    animateSize: true,
                    animateShape: true,
                    firstColor: colorScheme.background,
                    secondColor: colorScheme.background,
                  ),
                  Gap(Spacing.md.h),
                  SizedBox(
                    width: 200.w,
                    child: AppButton(
                      height: 45.h,
                      label: loc.introGetStarted,
                      onPressed: () async {
                        await ref
                            .read(preferencesServiceProvider)
                            .setFirstLaunchCompleted();

                        // Bypass the 100ms debounce so the router sees
                        // isFirstLaunch=false before context.go fires,
                        // preventing a bounce back to /intro.
                        ref.read(routingNotifierProvider).completeFirstLaunch();

                        if (context.mounted) {
                          context.go(RouteNames.home);
                        }
                      },

                      borderRadius: BorderRadiusTokens.xlAll,
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      width: double.infinity,
                      outlineColor: colorScheme.background,
                      textColor: colorScheme.background,
                    ),
                  ),
                  Gap(Spacing.xxl.h),

                  // Main Title
                  Text(
                    loc.authIntroTitle(AppConstants.appName),
                    style: textTheme.displayLarge?.copyWith(
                      fontSize: 30.sp,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.background,
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Gap(Spacing.md.h),
                  // attune_logo_white
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.md,
                      ),
                      child: Image.asset(
                        'assets/images/attune_launcher_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // Icon(
                  //   FontAwesomeIcons.heart,
                  //   color: colorScheme.primary,
                  //   size: 40.h,
                  // ),
                ],
              ),
            ),

            // Horizontal Modules List
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
                ],
              ),
            ),
            Gap(Spacing.md.h),
            GestureDetector(
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
            Gap(Spacing.md.h),
            // Bottom Section with Legal Text and Button
          ],
        ),
      ),
    );
  }
}
