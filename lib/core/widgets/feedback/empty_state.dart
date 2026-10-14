import 'package:attune/core/utils/exports/export_screens.dart';

/// The kinds of empty screen Attune shows. Each has its own icon and
/// wording (translated); [custom] takes the caller's.
enum EmptyStateType {
  /// A list or screen with nothing in it yet.
  noData,

  /// A search or filter that matched nothing.
  noResults,

  /// No connection.
  noInternet,

  /// A conversation with no messages yet.
  noMessages,

  /// The caller's own icon and wording.
  custom,
}

class EmptyStateWidget extends StatelessWidget {
  final EmptyStateType type;
  final String? title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final Widget? customIllustration;
  final bool compact;

  const EmptyStateWidget({
    super.key,
    this.type = EmptyStateType.noData,
    this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.customIllustration,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final config = _getConfiguration(context);

    final effectiveTitle =
        (title != null && title!.isNotEmpty) ? title : config.$2;

    return Padding(
      padding:
          compact
              ? EdgeInsets.all(Spacing.xl.r)
              : EdgeInsets.symmetric(
                vertical: Spacing.xxl.h,
                horizontal: Spacing.xl.w,
              ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (customIllustration != null) ...[
            customIllustration!,
            Gap(compact ? Spacing.lg.h : Spacing.xxl.h),
          ] else if ((icon ?? config.$1) != null) ...[
            // A caller's icon shows for any type, custom included.
            Icon(
              icon ?? config.$1,
              size: compact ? 30.r : 50.r,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            Gap(compact ? Spacing.md.h : Spacing.lg.h),
          ],

          if (effectiveTitle != null)
            Padding(
              padding: EdgeInsets.only(bottom: Spacing.sm.h),
              child: Text(
                effectiveTitle,
                style:
                    compact
                        ? textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        )
                        : textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                textAlign: TextAlign.center,
              ),
            ),

          if (config.$3 != null || subtitle != null)
            Padding(
              padding: EdgeInsets.only(
                bottom: compact ? Spacing.lg.h : Spacing.xxl.h,
              ),
              child: Text(
                subtitle ?? config.$3!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
                maxLines: compact ? 3 : 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          if (onAction != null)
            AppButton(
              height: 40.h,
              label: actionLabel ?? config.$4 ?? 'Retry',
              onPressed: onAction,
              padding: Spacing.horizontalMd,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              outlineColor: Colors.transparent,
              width: double.infinity,
            ),
        ],
      ),
    );
  }

  (IconData?, String?, String?, String?) _getConfiguration(
    BuildContext context,
  ) {
    final loc = AppLocalizations.of(context);
    switch (type) {
      case EmptyStateType.noData:
        return (
          Icons.inbox_outlined,
          loc?.emptyStateNoDataTitle ?? 'Nothing here yet',
          loc?.emptyStateNoDataSubtitle ??
              "When there's something to show, it'll appear here.",
          loc?.emptyStateRefresh ?? 'Refresh',
        );
      case EmptyStateType.noResults:
        return (
          Icons.search_off_outlined,
          loc?.emptyStateNoResultsTitle ?? 'No matches',
          loc?.emptyStateNoResultsSubtitle ?? 'Try a different word or filter.',
          loc?.emptyStateClearFilters ?? 'Clear filters',
        );
      case EmptyStateType.noInternet:
        return (
          Icons.wifi_off_outlined,
          loc?.emptyStateNoInternetTitle ?? "You're offline",
          loc?.emptyStateNoInternetSubtitle ??
              'Check your connection and try again.',
          loc?.emptyStateRetry ?? 'Try again',
        );
      case EmptyStateType.noMessages:
        return (
          Icons.forum_outlined,
          loc?.emptyStateNoMessagesTitle ?? 'No messages yet',
          loc?.emptyStateNoMessagesSubtitle ??
              'Say hello to start your conversation.',
          loc?.emptyStateStartChat ?? 'Say hello',
        );
      case EmptyStateType.custom:
        return (null, null, null, null);
    }
  }
}
