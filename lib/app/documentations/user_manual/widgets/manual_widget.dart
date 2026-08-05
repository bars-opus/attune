// lib/features/documentation/presentation/widgets/documentation_widget.dart
import 'package:attune/core/utils/exports/export_screens.dart';

class ManualWidget extends StatelessWidget {
  final List<ManualSection> sections;
  final bool showSectionDividers;
  final bool useAppColors;
  final double lineWidth;
  final double contentIndent;

  const ManualWidget({
    super.key,
    required this.sections,
    this.showSectionDividers = true,
    this.useAppColors = true,
    this.lineWidth = 2.0,

    this.contentIndent = 32.0, // How much to indent content from line
  });

  @override
  Widget build(BuildContext context) {
    final appColors =
        useAppColors
            ? Theme.of(context).appColors
            : AppColors(Theme.of(context).brightness == Brightness.dark);

    final textTheme = Theme.of(context).textTheme;
    final effectiveLineColor = appColors.divider.withOpacity(0.3);

    return ListView.builder(
      itemCount: sections.length,
      itemBuilder: (context, sectionIndex) {
        final section = sections[sectionIndex];
        return _buildSection(
          context,
          section,
          appColors,
          textTheme,
          effectiveLineColor,
          isLast: sectionIndex == sections.length - 1,
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    ManualSection section,
    AppColors appColors,
    TextTheme textTheme,
    Color lineColor, {
    required bool isLast,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header (no timeline connection)
        Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Gap(Spacing.xxl.h + Spacing.lg.h),
              Icon(
                section.icon,
                size: IconSizes.xxl.h,
                color: appColors.primary,
              ),
              Gap(Spacing.xxl.h),
              Text(
                section.title,
                style: textTheme.titleLarge?.copyWith(
                  color: appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 22.sp,
                ),
                textAlign: TextAlign.center,
              ),
              Gap(Spacing.sm.h),
              if (section.subtitle != null) ...[
                Gap(Spacing.xs.h),
                Text(
                  section.subtitle!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: appColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),

        // Timeline Content Items
        Stack(
          children: [
            // Vertical Line (behind content)
            Positioned(
              left: (contentIndent / 2 - lineWidth / 2).w, // Center the line
              top: 0,
              bottom: 0,
              child: Container(
                width: lineWidth.w,
                decoration: BoxDecoration(
                  color: lineColor,
                  borderRadius: BorderRadius.circular(lineWidth.w),
                ),
              ),
            ),

            // Content Items
            Column(
              children:
                  section.contents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final content = entry.value;
                    final isLastContent = index == section.contents.length - 1;

                    return _buildTimelineContentItem(
                      context,
                      content,
                      index,
                      section.contents.length,
                      appColors,
                      textTheme,
                      lineColor,
                      isLastContent: isLastContent,
                    );
                  }).toList(),
            ),
          ],
        ),

        // Divider between sections
        if (showSectionDividers && !isLast) ...[
          Gap(Spacing.xxl.h),
          AppDivider(),
          // Gap(Spacing.xxl.h),
          // Gap(Spacing.xxl.h),

          // AppDivider(),
          // Gap(Spacing.xl.h),
        ],
      ],
    );
  }

  Widget _buildTimelineContentItem(
    BuildContext context,
    ManualContent content,
    int index,
    int totalItems,
    AppColors appColors,
    TextTheme textTheme,
    Color lineColor, {
    required bool isLastContent,
  }) {
    final hasNumber =
        content.numberPrefix != null &&
        content.numberPrefix!.isNotEmpty &&
        content.numberPrefix != '0';

    return Container(
      margin: EdgeInsets.only(
        bottom: isLastContent ? Spacing.md.h : Spacing.sm.h,
        top: hasNumber ? Spacing.xxl.h : Spacing.sm.h,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Node Column
          Container(
            width: contentIndent.w,
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Vertical line extension for non-last items
                // Only show line if this item has a number prefix
                if (!isLastContent && hasNumber)
                  Positioned(
                    top: 28.r, // Start below the circle
                    bottom: -Spacing.xl.h, // Extend to next item
                    child: Container(width: lineWidth.w, color: lineColor),
                  ),

                // Circle with number/icon (ONLY if hasNumber is true)
                if (hasNumber)
                  Container(
                    width: 28.r,
                    height: 28.r,
                    decoration: BoxDecoration(
                      color: appColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(
                        color: appColors.primary.withOpacity(0.3),
                        width: 2.0,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        content.numberPrefix!,
                        style: textTheme.labelLarge?.copyWith(
                          color: content.numberColor ?? appColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Content Column
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: Spacing.md.w, // Only indent if has number
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title (if exists)
                  if (content.title.isNotEmpty) ...[
                    Text(
                      content.title,
                      style: textTheme.titleMedium?.copyWith(
                        color:
                            hasNumber
                                ? appColors.primary
                                : appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: hasNumber ? 16.sp : 14.sp,
                      ),
                    ),
                    Gap(Spacing.sm.h),
                  ],

                  // Content based on type
                  _buildContentByType(context, content, appColors, textTheme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletList(
    ManualContent content,
    AppColors appColors,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (content.content.isNotEmpty) ...[
          Text(
            content.content,
            style: textTheme.bodyMedium?.copyWith(
              color: appColors.textPrimary,
              height: 1.6,
            ),
          ),
          Gap(Spacing.md.h),
        ],
        if (content.bulletPoints != null) ...[
          ...content.bulletPoints!.map((point) {
            return Padding(
              padding: EdgeInsets.only(
                left: Spacing.md.w,
                bottom: Spacing.sm.h,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 6.h, right: Spacing.sm.w),
                    child: Container(
                      width: 8.r,
                      height: 8.r,
                      decoration: BoxDecoration(
                        color: appColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      point,
                      style: textTheme.bodyMedium?.copyWith(
                        color: appColors.textPrimary,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildContentByType(
    BuildContext context,
    ManualContent content,
    AppColors appColors,
    TextTheme textTheme,
  ) {
    switch (content.type) {
      case ManualContentType.bulletList:
        return _buildBulletList(content, appColors, textTheme);
      case ManualContentType.warning:
        return SemanticContainerWidget(
          content: content.content,
          icon: Icons.warning_amber,
          title: 'Warning',
          backgroundColor: appColors.warning.withOpacity(0.1),
          borderColor: appColors.warning,
          iconColor: appColors.warning,
          textTheme: textTheme,
        );
      case ManualContentType.tip:
        return SemanticContainerWidget(
          content: content.content,
          icon: Icons.lightbulb_outline,
          title: 'Pro Tip',
          backgroundColor: appColors.success.withOpacity(0.1),
          borderColor: appColors.success,
          iconColor: appColors.success,
          textTheme: textTheme,
        );
      case ManualContentType.important:
        return SemanticContainerWidget(
          content: content.content,
          icon: Icons.error_outline,
          title: 'Important',
          backgroundColor: appColors.error.withOpacity(0.1),
          borderColor: appColors.error,
          iconColor: appColors.error,
          textTheme: textTheme,
        );
      case ManualContentType.code:
        return _buildCodeSnippet(content, appColors, textTheme);
      case ManualContentType.image:
        return _buildImage(content, appColors, textTheme);
      default: // text
        return Text(
          content.content,
          style: textTheme.bodyMedium?.copyWith(color: appColors.textPrimary),
        );
    }
  }

  Widget _buildCodeSnippet(
    ManualContent content,
    AppColors appColors,
    TextTheme textTheme,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Spacing.md.r),
      decoration: BoxDecoration(
        color: appColors.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
      ),
      child: Text(
        content.codeSnippet ?? '',
        style: textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          fontSize: 12.sp,
          color: appColors.textSecondary,
        ),
      ),
    );
  }

  // In _buildImage method:
  Widget _buildImage(
    ManualContent content,
    AppColors appColors,
    TextTheme textTheme,
  ) {
    if (content.imageUrl == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Use CachedNetworkImage for network images
        ClipRRect(
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          child: CachedNetworkImage(
            imageUrl: content.imageUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 200.h, // Fixed height or use aspect ratio
            placeholder:
                (context, url) => Container(
                  color: appColors.surface,
                  child: Center(child: CircularLoadingIndicator()),
                ),
            errorWidget:
                (context, url, error) => Container(
                  color: appColors.surface,
                  child: Center(
                    child: Icon(Icons.broken_image, color: appColors.error),
                  ),
                ),
          ),
        ),

        if (content.content.isNotEmpty) ...[
          Gap(Spacing.sm.h),
          Text(
            content.content,
            style: textTheme.bodySmall?.copyWith(
              color: appColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
