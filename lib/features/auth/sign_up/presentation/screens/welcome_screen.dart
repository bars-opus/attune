import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/path_preview_sheet.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

/// WL1 · Welcome (`/welcome`, Spec 1 §3.1): the three ways in and every
/// gate before anyone types. Replaces IntroScreen under flow_signin_v2.
/// Nothing is preselected and nothing here touches the network.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

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
  /// should return somewhere other than Welcome.
  static String signUpLocation(String entry, {String? back}) =>
      Uri(
        path: RouteNames.signUp,
        queryParameters: {'entry': entry, if (back != null) 'back': back},
      ).toString();

  void _preview(BuildContext context, WidgetRef ref, PathPreviewKind kind) {
    ref.read(metricCounterProvider).bump(switch (kind) {
      PathPreviewKind.relationship =>
        ClientMetricKey.welcomePreviewRelationship,
      PathPreviewKind.dating => ClientMetricKey.welcomePreviewDating,
      PathPreviewKind.justMe => ClientMetricKey.welcomePreviewJustMe,
    });
    showPathPreview(
      context,
      kind: kind,
      onGetStarted: () => leave(context, ref, signUpLocation('new')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FlowFrame(
      title: loc.flow_welcomeTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PathCard(
            title: loc.flow_pathRelationshipTitle,
            line: loc.flow_pathRelationshipLine,
            onTap: () => _preview(context, ref, PathPreviewKind.relationship),
          ),
          Gap(Spacing.sm.h),
          _PathCard(
            title: loc.flow_pathDatingTitle,
            line: loc.flow_pathDatingLine,
            onTap: () => _preview(context, ref, PathPreviewKind.dating),
          ),
          Gap(Spacing.sm.h),
          _PathCard(
            title: loc.flow_pathJustMeTitle,
            line: loc.flow_pathJustMeLine,
            onTap: () => _preview(context, ref, PathPreviewKind.justMe),
          ),
          Gap(Spacing.lg.h),
          FlowPrimaryButton(
            label: loc.flow_welcomeGetStarted,
            onPressed: () => leave(context, ref, signUpLocation('new')),
          ),
          Gap(Spacing.sm.h),
          FlowSecondaryButton(
            label: loc.flow_welcomeHaveAccount,
            onPressed: () => leave(context, ref, signUpLocation('returning')),
          ),
          Gap(Spacing.sm.h),
          FlowSecondaryButton(
            label: loc.flow_welcomeHaveInvite,
            onPressed: () => leave(context, ref, RouteNames.invite),
          ),
          FlowTextLink(
            label: loc.flow_welcomeReadOpinions,
            onPressed: () => leave(context, ref, RouteNames.guestAge),
          ),
          Gap(Spacing.md.h),
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
        ],
      ),
    );
  }
}

/// One of the three equal cards: a button that opens the path's preview.
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
