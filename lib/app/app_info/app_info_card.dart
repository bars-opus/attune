import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

class AppInfoCard extends StatelessWidget {
  final VoidCallback? onTap;
  final bool showVersion;
  final bool showChevron;

  const AppInfoCard({
    super.key,
    this.onTap,
    this.showVersion = true,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return CardInkWell(
      onTap: onTap??(){},
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.h,
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Center(
              child: Icon(
                Icons.apps,
                size: 24.h,
                color: colorScheme.primary,
              ),
            ),
          ),
          Gap(Spacing.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onBackground,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (showVersion) ...[
                  Gap(Spacing.xs.h),
                  Text(
                    'Version ${AppConstants.appVersion}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onBackground.withOpacity(0.6),
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showChevron) ...[
            Gap(Spacing.md.w),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onBackground.withOpacity(0.3),
              size: IconSizes.lg.h,
            ),
          ],
        ],
      ),
    );
  }
}
