import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/circular_loading_indicator.dart';
import 'package:attune/core/widgets/feedback/error_state.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

/// Loading indicator types for different contexts
enum LoadingStateType {
  page, // Full page loading (with background)
  inline, // Inline loading within content
  button, // Button loading state
  list, // List item loading (skeleton)
  overlay, // Overlay loading on existing content
  custom, // Custom configuration
}

class LoadingStateWidget extends ConsumerWidget {
  final LoadingStateType type;
  final String? message;
  final bool showMessage;
  final Color? backgroundColor;
  final Color? indicatorColor;
  final double? size;
  final bool compact;

  const LoadingStateWidget({
    super.key,
    this.type = LoadingStateType.page,
    this.message,
    this.showMessage = true,
    this.backgroundColor,
    this.indicatorColor,
    this.size,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (type) {
      case LoadingStateType.page:
        return _buildPageLoader(context, colorScheme);
      case LoadingStateType.inline:
        return _buildInlineLoader(context, colorScheme);
      case LoadingStateType.button:
        return _buildButtonLoader(context, colorScheme);
      case LoadingStateType.list:
        return _buildListLoader(context, colorScheme);
      case LoadingStateType.overlay:
        return _buildOverlayLoader(context, colorScheme);
      case LoadingStateType.custom:
        return _buildCustomLoader(context, colorScheme);
    }
  }

  Widget _buildPageLoader(BuildContext context, ColorScheme colorScheme) {
    return Container(
      color: backgroundColor ?? colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildIndicator(context, colorScheme, size: compact ? 32.h : 48.h),
            if (showMessage && message != null) ...[
              SizedBox(height: compact ? Spacing.md.h : Spacing.lg.h),
              _buildMessage(context, colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlineLoader(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Spacing.xl.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildIndicator(context, colorScheme, size: compact ? 20.h : 24.h),
          if (showMessage && message != null) ...[
            SizedBox(width: Spacing.md.w),
            _buildMessage(context, colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildButtonLoader(BuildContext context, ColorScheme colorScheme) {
    return CircularLoadingIndicator();
  }

  Widget _buildListLoader(BuildContext context, ColorScheme colorScheme) {
    // Skeleton loader for list items
    return Column(
      children: List.generate(
        compact ? 3 : 5,
        (index) => _buildSkeletonItem(context, colorScheme),
      ),
    );
  }

  Widget _buildOverlayLoader(BuildContext context, ColorScheme colorScheme) {
    return Container(
      color: backgroundColor ?? Colors.black.withOpacity(0.5),
      child: Center(
        child: Container(
          padding: EdgeInsets.all(Spacing.lg.w),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIndicator(context, colorScheme, size: 32.h),
              if (showMessage && message != null) ...[
                SizedBox(height: Spacing.md.h),
                _buildMessage(context, colorScheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomLoader(BuildContext context, ColorScheme colorScheme) {
    return _buildIndicator(context, colorScheme, size: size);
  }

  Widget _buildIndicator(
    BuildContext context,
    ColorScheme colorScheme, {
    double? size,
  }) {
    return CircularLoadingIndicator();
  }

  Widget _buildMessage(BuildContext context, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;

    return Text(
      message ?? _getDefaultMessage(context),
      style:
          compact
              ? textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              )
              : textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
      textAlign: TextAlign.center,
    );
  }

  String _getDefaultMessage(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return loc?.loadingDefaultMessage ?? 'Loading...';
  }

  Widget _buildSkeletonItem(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: Spacing.sm.h,
        horizontal: Spacing.md.w,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar skeleton
          Container(
            width: 40.h,
            height: 40.h,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(20.r),
            ),
          ),
          SizedBox(width: Spacing.md.w),
          // Text skeletons
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 12.h,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                ),
                SizedBox(height: Spacing.xs.h),
                Container(
                  width: MediaQuery.of(context).size.width * 0.4,
                  height: 10.h,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Riverpod Helper: Loading State Provider Pattern
final loadingStateProvider = StateProvider<bool>((ref) => false);

// Riverpod Helper: AsyncValue wrapper for loading states
class LoadingWrapper<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) dataBuilder;
  final Widget Function(Object error, StackTrace stackTrace)? errorBuilder;
  final Widget Function()? loadingBuilder;
  final bool skipLoadingOnRefresh;

  const LoadingWrapper({
    super.key,
    required this.value,
    required this.dataBuilder,
    this.errorBuilder,
    this.loadingBuilder,
    this.skipLoadingOnRefresh = false,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: dataBuilder,
      error:
          errorBuilder ??
          (error, stack) => ErrorStateWidget(
            type: ErrorStateType.genericError,
            errorDetails: error.toString(),
            showDetails: true,
            onPrimaryAction: () {},
            // => value.refresh(),
          ),
      loading:
          loadingBuilder ??
          () => LoadingStateWidget(type: LoadingStateType.page),
      skipLoadingOnRefresh: skipLoadingOnRefresh,
    );
  }
}
