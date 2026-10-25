import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// The three ways in, as Welcome shows them (Spec 1 §3.1).
enum PathPreviewKind { relationship, dating, justMe }

/// Opens a path's preview: static, bundled, no network. In 300 ms, out
/// 200 ms; with reduce motion a 150 ms fade each way (spec §3.1 WL1).
Future<void> showPathPreview(
  BuildContext context, {
  required PathPreviewKind kind,
  required VoidCallback onGetStarted,
}) {
  final loc = AppLocalizations.of(context)!;
  return Navigator.of(context).push(
    _PreviewRoute(
      reduceMotion: reduceMotionOf(context),
      barrierLabel: loc.flow_close,
      builder: (_) => PathPreviewSheet(kind: kind, onGetStarted: onGetStarted),
    ),
  );
}

class _PreviewRoute extends PopupRoute<void> {
  _PreviewRoute({
    required this.reduceMotion,
    required this.barrierLabel,
    required this.builder,
  });

  final bool reduceMotion;
  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? kReducedMotionFade : const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? kReducedMotionFade : const Duration(milliseconds: 200);

  // Preserve: the platform's reduce-motion switch, which picks the 150 ms
  // fade, would otherwise also run it 20 times faster (review M-2).
  @override
  AnimationController createAnimationController() => AnimationController(
    duration: transitionDuration,
    reverseDuration: reverseTransitionDuration,
    debugLabel: debugLabel,
    vsync: navigator!,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion) return FadeTransition(opacity: animation, child: child);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Easing.emphasizedAccelerate,
    );
    return SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }
}

class PathPreviewSheet extends ConsumerWidget {
  const PathPreviewSheet({
    super.key,
    required this.kind,
    required this.onGetStarted,
  });

  final PathPreviewKind kind;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final openCountries = ref.watch(datingOpenCountriesProvider);
    final (title, lines, icon) = switch (kind) {
      PathPreviewKind.relationship => (
        loc.flow_previewRelationshipTitle,
        [
          loc.flow_previewRelationshipLine1,
          loc.flow_previewRelationshipLine2,
          loc.flow_previewRelationshipLine3,
        ],
        Icons.favorite_outline,
      ),
      PathPreviewKind.dating => (
        loc.flow_previewDatingTitle,
        [
          loc.flow_previewDatingLine1,
          loc.flow_previewDatingLine2,
          loc.flow_previewDatingLine3,
          // Left out when the list is empty or has never been read (D15).
          if (openCountries.isNotEmpty)
            loc.flow_previewDatingCountries(
              formatCountryList(
                openCountries,
                nameOf:
                    (iso) => countryNameFor(
                      iso,
                      special: {
                        'GB': loc.flow_countryUk,
                        'US': loc.flow_countryUs,
                      },
                    ),
                pair: loc.flow_listTwo,
              ),
            ),
        ],
        Icons.people_outline,
      ),
      PathPreviewKind.justMe => (
        loc.flow_previewJustMeTitle,
        [
          loc.flow_previewJustMeLine1,
          loc.flow_previewJustMeLine2,
          loc.flow_previewJustMeLine3,
          loc.flow_previewJustMeLine4,
        ],
        Icons.menu_book_outlined,
      ),
    };

    return AllowLargeText(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ContentWidth.sheet,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          // Names the sheet for a screen reader when it opens, as a modal
          // bottom sheet does (review M-4).
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: Material(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(BorderRadiusTokens.xl),
              ),
              child: SafeArea(
                top: false,
                // The lines scroll; the two buttons stay at the bottom at any
                // text size, as on FlowFrame (review M-5).
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          Spacing.lg.w,
                          Spacing.lg.h,
                          Spacing.lg.w,
                          Spacing.sm.h,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Decorative: the lines below are the readable
                            // content.
                            ExcludeSemantics(
                              child: Center(
                                child: CircleAvatar(
                                  radius: 36,
                                  backgroundColor: colorScheme.primaryContainer,
                                  child: Icon(
                                    icon,
                                    size: IconSizes.lg,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                            Gap(Spacing.md.h),
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Gap(Spacing.md.h),
                            for (var i = 0; i < lines.length; i++) ...[
                              if (i > 0) Gap(Spacing.sm.h),
                              Text(
                                lines[i],
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        Spacing.lg.w,
                        Spacing.md.h,
                        Spacing.lg.w,
                        Spacing.md.h,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FlowPrimaryButton(
                            label: loc.flow_welcomeGetStarted,
                            onPressed: () {
                              Navigator.of(context).pop();
                              onGetStarted();
                            },
                          ),
                          Gap(Spacing.sm.h),
                          FlowSecondaryButton(
                            label: loc.flow_close,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
