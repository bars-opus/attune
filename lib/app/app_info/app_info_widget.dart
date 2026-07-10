
import 'package:attune/core/utils/exports/export_screens.dart';

class AppInfoWidget extends StatelessWidget {
  final bool showLogo;
  final bool showVersion;
  final bool showDeveloper;
  final bool showSocialLinks;
  final bool showTechnicalDetails;
  final bool showLegalLinks;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onViewChangelog;
  final VoidCallback? onContactSupport;

  const AppInfoWidget({
    super.key,
    this.showLogo = true,
    this.showVersion = true,
    this.showDeveloper = true,
    this.showSocialLinks = true,
    this.showTechnicalDetails = false,
    this.showLegalLinks = true,
    this.onCheckForUpdates,
    this.onViewChangelog,
    this.onContactSupport,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Gap(Spacing.xl.h),
        // App Logo/Icon
        if (showLogo) ...[
          Container(
            width: 80.w,
            height: 80.h,
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20.r),
              boxShadow: [
                BoxShadow(
                  color:
                      colorScheme.shadow?.withOpacity(0.1) ??
                      Colors.black.withOpacity(0.1),
                  blurRadius: 10.r,
                  offset: Offset(0, 4.h),
                ),
              ],
            ),
            child: Center(
              child: Icon(Icons.apps, size: 40.h, color: colorScheme.primary),
            ),
          ),
          Gap(Spacing.lg.h),
        ],

        // App Name
        Text(
          AppConstants.appName,
          style: textTheme.headlineLarge?.copyWith(
            color: colorScheme.onBackground,
            fontSize: 28.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        Gap(Spacing.xs.h),

        // App Version
        if (showVersion) ...[
          Text(
            '${loc.appInfoVersion} ${AppConstants.appVersion}',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onBackground.withOpacity(OpacityTokens.medium),
              fontSize: 14.sp,
            ),
          ),
          Gap(Spacing.xs.h),
        ],

        // Release Date
        Text(
          '${loc.appInfoReleased} ${AppConstants.appReleaseDate}',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onBackground.withOpacity(0.5),
            fontSize: 12.sp,
          ),
        ),
        Gap(Spacing.xl.h),

        // Technical Details (expandable)
        if (showTechnicalDetails) _buildTechnicalDetailsCard(context),

        // Information Cards
        _buildInfoSection(context),

        Gap(Spacing.xxl.h),

        // Copyright
        Text(
          AppConstants.appCopyright,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onBackground.withOpacity(0.4),
            fontSize: 11.sp,
          ),
        ),
        Gap(Spacing.xxl.h),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;
    return CardInkWell(
      onTap: () {},
      child: Padding(
        padding: Spacing.allLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.appInfoOverview(AppConstants.appName),
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onBackground.withOpacity(
                  OpacityTokens.medium,
                ),
                fontSize: 12.sp,
                height: 1.5,
              ),
            ),
            Gap(Spacing.md.h),

            // Info Grid
            Column(
              children: [
                InfoRowWidget(
                  subtitle: loc.appInfoPackageName,
                  title: AppConstants.appPackageName,
                  icon: Icons.memory,
                  avatarRadius: 25.h,
                  onTap: () {},
                  disableTrailing: true,
                  showAvatar: false,
                  showTrailingArrow: false,
                ),
                InfoRowWidget(
                  subtitle: loc.appInfoDeveloper,
                  title: AppConstants.appDeveloper,
                  icon: Icons.business,
                  avatarRadius: 25.h,
                  onTap: () {},
                  showAvatar: false,
                  showTrailingArrow: false,
                ),

                InfoRowWidget(
                  subtitle: loc.appInfoSupportEmail,
                  title: AppConstants.supportEmail,
                  icon: Icons.email_outlined,
                  avatarRadius: 25.h,
                  onTap: () {},

                  showAvatar: false,
                  showTrailingArrow: false,
                ),
              ],
            ),
            Gap(Spacing.sm.h),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalDetailsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;
    return CardInkWell(
      onTap: () {},
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                loc.appInfoTechnicalDetails,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onBackground,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              '• ${loc.appInfoBundleID}: ${AppConstants.appBundleId}\n'
              '• ${loc.appInfoBuildVersion}: ${AppConstants.appVersion}\n'
              '• ${loc.appInfoBuildNumber}: ${AppConstants.appBuildNumber}\n'
              '• ${loc.appInfoReleaseDate}: ${AppConstants.appReleaseDate}\n'
              '• ${loc.appInfoAppSize}: ${AppConstants.appSize}\n',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onBackground.withOpacity(0.7),
                fontSize: 12.sp,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
