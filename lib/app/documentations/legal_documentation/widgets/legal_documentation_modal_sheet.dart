import 'package:attune/core/utils/exports/export_screens.dart';

class LegalDocumentationModalSheet extends StatelessWidget {
  final DocumentationItem document;
  final VoidCallback? onAgree;
  final VoidCallback? onDecline;
  final String agreeButtonText;
  final String declineButtonText;
  final bool showButtons;

  const LegalDocumentationModalSheet({
    super.key,
    required this.document,
    this.onAgree,
    this.onDecline,
    this.agreeButtonText = 'I Agree',
    this.declineButtonText = 'Decline',
    this.showButtons = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: ListView(
        // mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          if (!showButtons) AppTextButton(),
          Gap(Spacing.xxl.h + 20.h),
          Icon(
            document.icon,
            color: colorScheme.primary,
            size: IconSizes.xxl.h,
          ),
          Gap(Spacing.xxl.h),
          Center(
            child: Text(
              document.title,
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Gap(Spacing.sm.h),
          // Subtitle
          if (document.subtitle != null)
            Text(
              document.subtitle!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(
                  alpha: OpacityTokens.medium,
                ),
              ),
            ),
          Text(
            'Read More',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Gap(Spacing.xxl.h),
          // Buttons section
          if (showButtons && (onAgree != null || onDecline != null))
            Column(
              children: [
                if (onAgree != null)
                  AppButton(
                    elevation: 0,
                    label: agreeButtonText,
                    onPressed: onAgree,
                    textColor: colorScheme.surface,
                    size: ButtonSize.small,
                    width: double.infinity,
                    padding: Spacing.horizontalMd,
                    height: 40.h,
                  ),
                if (onAgree != null && onDecline != null) Gap(Spacing.sm.h + 5),
                if (onDecline != null)
                  AppButton(
                    height: 40.h,
                    label: declineButtonText,
                    onPressed:
                        onDecline ??
                        () {
                          Navigator.pop(context);
                        },
                    padding: Spacing.horizontalMd,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    width: double.infinity,
                  ),
              ],
            ),
          // Bottom safe area padding
          Gap(Spacing.md.h),
        ],
      ),
    );
  }
}
