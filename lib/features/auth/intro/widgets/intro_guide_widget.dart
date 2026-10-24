import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/widgets/documentation_tab_view.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

class IntroGuideWidget extends StatelessWidget {
  final DocumentationModule module;

  /// The card's square side, before ScreenUtil scaling. The intro and login
  /// screens use the default; the empty chat uses a smaller card so the row
  /// still fits above the message bar with the keyboard open.
  final double size;

  const IntroGuideWidget({super.key, required this.module, this.size = 250});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    // A smaller card (the empty chat's) keeps its text room by trimming
    // the padding and the icon; the default 250 card is unchanged.
    final compact = size < 250;
    final iconBox = compact ? 44.0 : 60.0;

    return Container(
      width: size.w,
      height: size.h,
      margin: EdgeInsets.only(right: Spacing.sm.w),
      child: CardInkWell(
        onTap: () {
          BottomSheetUtils.showDocumentationBottomSheet(
            context: context,
            showButtons: false,
            widget: DocumentationTabView(
              module: module,
              showDocumentationFirst: true,
            ),
          );
        },
        padding: EdgeInsets.all((compact ? Spacing.md : Spacing.xl).h),
        // color: colorScheme.background,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: iconBox.w,
              height: iconBox.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.onBackground.withOpacity(.5),
                ),
              ),
              child: Icon(
                module.icon,
                size: (compact ? IconSizes.md : IconSizes.lg).h,
                color: colorScheme.onBackground.withOpacity(.5),
              ),
            ),
            Gap(Spacing.md.h),
            // Title
            Text(
              module.getTitle(context),
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
                fontSize: 14.sp,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Gap(Spacing.xs.h),
            Expanded(
              child: Text(
                module.getSubtitle(context),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onBackground.withOpacity(0.8),
                  fontSize: 12.sp,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
