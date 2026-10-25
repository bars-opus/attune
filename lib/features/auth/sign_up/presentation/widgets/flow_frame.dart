import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// The shared layout of every Spec 1 sign-in screen: an optional back
/// button, a title read out as a heading, an optional hint, the screen's
/// own body (scrolls at large text), then its actions pinned at the bottom.
/// Large text is let through (AllowLargeText, §2.3); on an iPad the column
/// is form-width.
class FlowFrame extends StatelessWidget {
  const FlowFrame({
    super.key,
    required this.title,
    required this.body,
    this.hint,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? hint;
  final Widget body;

  /// Bottom of the screen, top to bottom, spaced by [Spacing.sm].
  final List<Widget> actions;

  /// Shows a back button when set.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    return AllowLargeText(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: AppContentWidth(
            maxWidth: ContentWidth.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 48,
                  child:
                      onBack == null
                          ? null
                          : Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: IconButton(
                              onPressed: onBack,
                              tooltip: loc.flow_back,
                              icon: const BackButtonIcon(),
                            ),
                          ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: Spacing.lg.w,
                      vertical: Spacing.sm.h,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (hint != null) ...[
                          Gap(Spacing.sm.h),
                          Text(
                            hint!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        Gap(Spacing.lg.h),
                        body,
                      ],
                    ),
                  ),
                ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      Spacing.lg.w,
                      Spacing.sm.h,
                      Spacing.lg.w,
                      Spacing.md.h,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) Gap(Spacing.sm.h),
                          actions[i],
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
