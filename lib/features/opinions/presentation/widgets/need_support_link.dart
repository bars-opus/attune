import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

/// Where "Need support now?" was opened from (its count, Spec 1 §4.8).
enum SupportLinkSource {
  opinions(ClientMetricKey.supportLinkOpenedOpinions),
  journal(ClientMetricKey.supportLinkOpenedJournal);

  const SupportLinkSource(this.metric);

  final ClientMetricKey metric;
}

/// The reason value the report RPCs take (Spec 1 §4.3 W9b).
const atRiskReportReason = 'Someone may be at risk';

/// Opens Support (W7a's screen and route; with support_resources_v2 off,
/// today's Safety resources screen) and counts the tap. Nothing else about
/// it is stored on the phone.
void openSupportNow(
  BuildContext context,
  WidgetRef ref,
  SupportLinkSource source,
) {
  ref.read(metricCounterProvider).bump(source.metric);
  context.push(RouteNames.safetyResources);
}

/// "Need support now?" (Spec 1 §8 W9b): always there, whatever anyone typed.
class NeedSupportLink extends ConsumerWidget {
  const NeedSupportLink({super.key, this.source = SupportLinkSource.opinions});

  final SupportLinkSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AllowLargeText(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: scheme.onSurface,
            padding: Spacing.horizontalSm,
          ),
          onPressed: () => openSupportNow(context, ref, source),
          icon: const Icon(Icons.support_outlined, size: 20),
          label: Text(loc.support_needSupportNow),
        ),
      ),
    );
  }
}

/// After an at-risk report (Spec 1 §8 W9b): never animated (§2.2), large
/// text let through (the shell clamps sheets to 1.0). Sized to its content
/// up to the full height, so at large text "See emergency numbers" is not
/// left below a fold; beyond that it scrolls.
Future<void> showAtRiskReportThanks(BuildContext context, WidgetRef ref) =>
    _showThanks(context, ref.read(metricCounterProvider), GoRouter.of(context));

Future<void> _showThanks(
  BuildContext context,
  MetricCounter counter,
  GoRouter router,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    sheetAnimationStyle: AnimationStyle.noAnimation,
    builder: (sheetContext) {
      final loc = AppLocalizations.of(sheetContext)!;
      final theme = Theme.of(sheetContext);
      return AllowLargeText(
        child: SingleChildScrollView(
          padding: Spacing.allLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  loc.opinions_atRiskThanks,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  // Counted and opened with what was taken when the sheet
                  // opened: the card that sent the report may be gone.
                  counter.bump(SupportLinkSource.opinions.metric);
                  router.push(RouteNames.safetyResources);
                },
                child: Text(loc.opinions_atRiskSeeNumbers),
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: theme.colorScheme.onSurface,
                ),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(loc.opinions_atRiskClose),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// An at-risk report from either list (Spec 1 W9b; PF-C8: one path for the
/// post and the comment list). [send] calls the report RPC with
/// [atRiskReportReason]; when it answers, the reporter is thanked with the
/// emergency numbers; when it fails, they are told and never thanked. The
/// reporter hears back even if the card or screen that sent it is gone by
/// then (batch-6 M-3).
Future<void> sendAtRiskReport(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() send,
) async {
  final reply = _ReportReply(context);
  final counter = ref.read(metricCounterProvider);
  final router = GoRouter.of(context);
  if (!await _send(reply, send)) return;
  final target = reply.target;
  if (target != null && target.mounted) {
    await _showThanks(target, counter, router);
  }
}

/// A report with any other reason, opinions_safety_v1 only (owner ruling
/// (c): every reason reaches the server). The thanks promises only that it
/// was sent: review queue v0 lists only the priority reasons, so no review
/// time is promised.
Future<void> sendReport(
  BuildContext context,
  Future<void> Function() send,
) async {
  final reply = _ReportReply(context);
  if (await _send(reply, send)) {
    _showReportSnackBar(reply, reply.loc.opinions_reportSent, _Snack.sent);
  }
}

/// A report that did not reach the server: announced, an icon beside the
/// words (never colour alone).
void showReportFailed(BuildContext context) =>
    _showFailed(_ReportReply(context));

/// What a report needs once its RPC answers, taken before it is sent: the
/// card or screen that sent it may be gone by then (a feed scrolled on, the
/// thread closed), and the reporter must still hear back (batch-6 M-3).
class _ReportReply {
  _ReportReply(BuildContext context)
    : _origin = context,
      _navigator = Navigator.of(context).overlay!.context,
      messenger = ScaffoldMessenger.of(context),
      loc = AppLocalizations.of(context)!,
      theme = Theme.of(context),
      direction = Directionality.of(context);

  final BuildContext _origin;
  final BuildContext _navigator;
  final ScaffoldMessengerState messenger;
  final AppLocalizations loc;
  final ThemeData theme;
  final TextDirection direction;

  /// Where the thank-you opens: the sender while it is there, else the
  /// navigator it was shown on.
  BuildContext? get target =>
      _origin.mounted ? _origin : (_navigator.mounted ? _navigator : null);
}

/// Sends, saying "Sending your report" if it takes longer than 400 ms
/// (§2.2), and says so if it fails. True when the report reached the server.
Future<bool> _send(_ReportReply reply, Future<void> Function() send) async {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? sending;
  final wait = Timer(const Duration(milliseconds: 400), () {
    sending = _showReportSnackBar(
      reply,
      reply.loc.opinions_reportSending,
      _Snack.sending,
    );
  });
  try {
    await send();
  } catch (_) {
    wait.cancel();
    _showFailed(reply);
    return false;
  }
  wait.cancel();
  sending?.close();
  return true;
}

void _showFailed(_ReportReply reply) {
  final message = reply.loc.opinions_reportFailed;
  SemanticsService.announce(message, reply.direction);
  _showReportSnackBar(reply, message, _Snack.failed);
}

enum _Snack {
  sending(Icons.hourglass_empty_rounded),
  sent(Icons.check_circle_outline),
  failed(Icons.error_outline);

  const _Snack(this.icon);

  final IconData icon;
}

/// The app's snackbar shape (Snackbar.show) in the inverse-surface pair,
/// well over 4.5:1 in both themes (the app's light error/onError pair,
/// which the error snackbar falls back to, is 3.68:1). Large text let
/// through (the shell clamps routes to 1.0).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _showReportSnackBar(
  _ReportReply reply,
  String message,
  _Snack kind,
) {
  final scheme = reply.theme.colorScheme;
  reply.messenger.hideCurrentSnackBar();
  return reply.messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      margin: const EdgeInsets.all(8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      showCloseIcon: kind != _Snack.sending,
      closeIconColor: scheme.onInverseSurface,
      duration: switch (kind) {
        _Snack.sending => const Duration(minutes: 1),
        _Snack.sent => const Duration(seconds: 4),
        _Snack.failed => const Duration(seconds: 6),
      },
      content: AllowLargeText(
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(kind.icon, color: scheme.onInverseSurface, size: 20),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                message,
                style: reply.theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onInverseSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
