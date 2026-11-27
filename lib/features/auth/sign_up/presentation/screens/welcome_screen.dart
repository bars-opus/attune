import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

/// WL1 · Welcome (`/welcome`, Spec 1 §3.1; owner 2026-11-26): "What brings
/// you to Attune?". Pushed by the intro's Get started; a tap on one of the
/// three paths starts sign-up for it (A1), and the account is made on that
/// path, never asked again (A6). Nothing is preselected and nothing here
/// touches the network. Back returns to the intro, or to [backTo].
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.backTo});

  /// Where A1's Back goes (passed on as sign-up's `back`), and Welcome's
  /// own when nothing is under it: the guest tab opens Welcome with its
  /// own (fix round I-2). Null: Welcome, and the intro.
  final String? backTo;

  /// Any button marks first launch done, exactly as IntroScreen does, so
  /// the router doesn't bounce the next route back here. Both providers are
  /// read before the write, so Welcome closing meanwhile (an invite link,
  /// the flag going off) still completes it (review M-1).
  static Future<void> leave(
    BuildContext context,
    WidgetRef ref,
    String location,
  ) async {
    final preferences = ref.read(preferencesServiceProvider);
    final routing = ref.read(routingNotifierProvider);
    await preferences.setFirstLaunchCompleted();
    routing.completeFirstLaunch();
    if (context.mounted) context.go(location);
  }

  /// `/signup?entry=…`, with `back` when the first step's back button
  /// should return somewhere other than Welcome, and `path` (its enum name)
  /// for the path chosen here.
  static String signUpLocation(String entry, {String? back, AppPath? path}) =>
      Uri(
        path: RouteNames.signUp,
        queryParameters: {
          'entry': entry,
          if (back != null) 'back': back,
          if (path != null) 'path': path.name,
        },
      ).toString();

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  /// A card (or the invite link) was tapped: a second tap does nothing
  /// (fix round M-3), so one path is counted and opened.
  bool _leaving = false;

  /// A path card: counted (the keys keep their server names), then A1 for
  /// that path.
  void _choose(AppPath path) {
    if (_leaving) return;
    _leaving = true;
    ref.read(metricCounterProvider).bump(switch (path) {
      AppPath.relationship => ClientMetricKey.welcomePreviewRelationship,
      AppPath.dating => ClientMetricKey.welcomePreviewDating,
      AppPath.justMe => ClientMetricKey.welcomePreviewJustMe,
    });
    WelcomeScreen.leave(
      context,
      ref,
      WelcomeScreen.signUpLocation('new', back: widget.backTo, path: path),
    );
  }

  /// "I have an invite": RI-2 (`/invite`), first launch marked done as a
  /// card does. No path is chosen, so nothing is counted.
  void _invite() {
    if (_leaving) return;
    _leaving = true;
    WelcomeScreen.leave(context, ref, RouteNames.invite);
  }

  /// Back to what pushed Welcome (the intro, the guest tab); reached any
  /// other way (A1's back), [WelcomeScreen.backTo] or the intro opens in
  /// its place.
  void _back() {
    final router = GoRouter.of(context);
    router.canPop()
        ? router.pop()
        : router.go(widget.backTo ?? RouteNames.start);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final canPop = GoRouter.of(context).canPop();

    return PopScope(
      // System back as the back button: the intro under Welcome, or the
      // intro in its place.
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: FlowFrame(
        title: loc.flow_pathTitle,
        onBack: _back,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PathCard(
              title: loc.flow_pathRelationshipTitle,
              line: loc.flow_pathRelationshipLine,
              onTap: () => _choose(AppPath.relationship),
            ),
            Gap(Spacing.sm.h),
            _PathCard(
              title: loc.flow_pathDatingTitle,
              line: loc.flow_pathDatingLine,
              onTap: () => _choose(AppPath.dating),
            ),
            Gap(Spacing.sm.h),
            _PathCard(
              title: loc.flow_pathJustMeTitle,
              line: loc.flow_pathJustMeLine,
              onTap: () => _choose(AppPath.justMe),
            ),
            Gap(Spacing.lg.h),
            Text(
              loc.flow_welcomeFooter,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                // Ruling C6: the shared read-only legal sheets.
                FlowTextLink(
                  label: loc.flow_linkTerms,
                  onPressed: () => showTermsSheet(context),
                ),
                FlowTextLink(
                  label: loc.flow_linkPrivacy,
                  onPressed: () => showPrivacySheet(context),
                ),
              ],
            ),
            // Entry gates (b, owner 2026-11-27): RI-2, quietly, for a code
            // from an invite message (an iOS install loses the link).
            FlowTextLink(label: loc.flow_welcomeHaveInvite, onPressed: _invite),
          ],
        ),
      ),
    );
  }
}

/// One of the three equal cards: a button that starts sign-up on its path.
class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.title,
    required this.line,
    required this.onTap,
  });

  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: loc.flow_welcomeCardSemantics(title, line),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadiusTokens.lgAll,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: EdgeInsets.all(Spacing.md.w),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Gap(Spacing.xs.h),
                        Text(
                          line,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
