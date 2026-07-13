import 'dart:async';
import 'dart:io';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ErrorStateType {
  networkError,
  serverError,
  clientError,
  parsingError,
  permissionError,
  genericError,
  custom,
}

/// Classifies an arbitrary thrown object into a safe, user-facing category.
///
/// Surfaces must never render a raw exception: a PostgrestException stringifies
/// to internal table names and SQL detail, and an AuthException can echo the
/// submitted phone number. (Same rule the auth engine spec states: "No UI error
/// should expose stack traces, project refs, internal table names, or raw
/// provider payloads.")
ErrorStateType classifyErrorState(Object? error) {
  if (error is TimeoutException || error is SocketException) {
    return ErrorStateType.networkError;
  }
  if (error is AuthException) return ErrorStateType.permissionError;
  if (error is FormatException) return ErrorStateType.parsingError;

  if (error is PostgrestException) {
    final code = error.code ?? '';
    // 42501 insufficient_privilege / PGRST301 JWT issues -> permission.
    if (code == '42501' || code.startsWith('PGRST3')) {
      return ErrorStateType.permissionError;
    }
    // 22xxx/23xxx = bad data or constraint violation -> the request was wrong.
    if (code.startsWith('22') || code.startsWith('23')) {
      return ErrorStateType.clientError;
    }
    return ErrorStateType.serverError;
  }

  final text = error?.toString().toLowerCase() ?? '';
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('timed out')) {
    return ErrorStateType.networkError;
  }

  return ErrorStateType.genericError;
}

class ErrorStateWidget extends StatelessWidget {
  final ErrorStateType type;
  final String? title;
  final String? subtitle;
  final String? errorDetails;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final bool showDetails;
  final bool compact;

  const ErrorStateWidget({
    super.key,
    this.type = ErrorStateType.genericError,
    this.title,
    this.subtitle,
    this.errorDetails = '',
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.showDetails = false,
    this.compact = true,
  });

  /// Safe drop-in for `Text('Error: $error')`.
  ///
  /// Classifies [error] into a friendly category and renders the shared error
  /// state with a retry. The raw exception text is attached ONLY in debug
  /// builds, and even then it stays collapsed behind "Show details" — it is
  /// never surfaced to a release user.
  factory ErrorStateWidget.from(
    Object? error, {
    Key? key,
    VoidCallback? onRetry,
    bool compact = true,
  }) {
    return ErrorStateWidget(
      key: key,
      type: classifyErrorState(error),
      errorDetails: kDebugMode ? error?.toString() : null,
      showDetails: kDebugMode,
      onPrimaryAction: onRetry,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final config = _getConfiguration(context);

    final effectiveTitle = title ?? config.$2;
    final effectiveSubtitle = subtitle ?? config.$3;

    return Padding(
      padding:
          compact
              ? EdgeInsets.all(Spacing.lg.r)
              : EdgeInsets.symmetric(
                vertical: Spacing.xxl.h,
                horizontal: Spacing.xl.w,
              ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            config.$1,
            size: compact ? 48.r : 60.r,
            color: colorScheme.error,
          ),

          Gap(Spacing.md.h),

          Padding(
            padding: EdgeInsets.only(bottom: Spacing.sm.h),
            child: Text(
              effectiveTitle,
              style:
                  compact
                      ? textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      )
                      : textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
              textAlign: TextAlign.center,
            ),
          ),

          Padding(
            padding: EdgeInsets.only(bottom: compact ? 0 : Spacing.xxl.h),
            child: Text(
              effectiveSubtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          if (errorDetails != null && errorDetails!.isNotEmpty && showDetails)
            _ErrorDetails(
              details: errorDetails!,
              colorScheme: colorScheme,
              compact: compact,
            ),

          Gap(compact ? Spacing.sm.h : Spacing.xxl.h),

          if (onPrimaryAction != null)
            Center(
              child: AppTextButton(
                alignment: Alignment.center,
                text: primaryActionLabel ?? config.$4 ?? 'Retry',
                onPressed: onPrimaryAction,
              ),
            ),
        ],
      ),
    );
  }

  (IconData, String, String, String?) _getConfiguration(BuildContext context) {
    final loc = AppLocalizations.of(context);

    switch (type) {
      case ErrorStateType.networkError:
        return (
          Icons.wifi_off_outlined,
          loc?.errorNetworkTitle ?? 'Connection Error',
          loc?.errorNetworkSubtitle ??
              'Unable to connect to the server. Check your internet connection.',
          loc?.errorRetry ?? 'Try again',
        );
      case ErrorStateType.serverError:
        return (
          Icons.cloud_off_outlined,
          loc?.errorServerTitle ?? 'Server Error',
          loc?.errorServerSubtitle ??
              'Something went wrong on our end. Please try again later.',
          loc?.errorRetry ?? 'Try again',
        );
      case ErrorStateType.clientError:
        return (
          Icons.error_outline_outlined,
          loc?.errorClientTitle ?? 'Request Error',
          loc?.errorClientSubtitle ??
              'There was a problem with your request. Please check and try again.',
          loc?.errorRetry ?? 'Try again',
        );
      case ErrorStateType.parsingError:
        return (
          Icons.data_object_outlined,
          loc?.errorParsingTitle ?? 'Data Error',
          loc?.errorParsingSubtitle('data') ??
              'Unable to process the data. This might be a temporary issue.',
          loc?.errorRetry ?? 'Try again',
        );
      case ErrorStateType.permissionError:
        return (
          Icons.lock_outline,
          loc?.errorPermissionTitle ?? 'Access Denied',
          loc?.errorPermissionSubtitle('data') ??
              'You don\'t have permission to access this content.',
          loc?.errorRequestAccess ?? 'Request access',
        );
      case ErrorStateType.genericError:
        return (
          Icons.error_outline_outlined,
          loc?.errorGenericTitle ?? 'Something went wrong',
          loc?.errorGenericSubtitle('data') ??
              'An unexpected error occurred. Please try again.',
          loc?.errorRetry ?? 'Try again',
        );
      case ErrorStateType.custom:
        return (
          Icons.error_outline_outlined,
          'Error',
          'An error occurred.',
          'Retry',
        );
    }
  }
}

class _ErrorDetails extends StatefulWidget {
  final String details;
  final ColorScheme colorScheme;
  final bool compact;

  const _ErrorDetails({
    required this.details,
    required this.colorScheme,
    required this.compact,
  });

  @override
  State<_ErrorDetails> createState() => _ErrorDetailsState();
}

class _ErrorDetailsState extends State<_ErrorDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _expanded ? 'Hide details' : 'Show details',
                style: TextStyle(
                  color: widget.colorScheme.primary,
                  fontSize: widget.compact ? 12.sp : 14.sp,
                ),
              ),
              Gap(Spacing.xs.w),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: widget.compact ? 16.r : 20.r,
                color: widget.colorScheme.primary,
              ),
            ],
          ),
        ),

        if (_expanded) ...[
          Gap(Spacing.md.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(Spacing.md.w),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: SelectableText(
              widget.details,
              style: TextStyle(
                color: widget.colorScheme.onSurfaceVariant,
                fontSize: widget.compact ? 11.sp : 12.sp,
                fontFamily: 'Monospace',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
