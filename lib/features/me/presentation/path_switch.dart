import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/relationships/presentation/widgets/end_relationship_action.dart';
import 'package:attune/features/relationships/presentation/widgets/pause_relationship_action.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A switch to another path from inside the app (Spec 1 §3.12): J4's
/// "More ways to use Attune", the Dating slot's "Not ready?", and Settings
/// -> How you use Attune. Every switch is silent to everyone else.
///   * to Relationship: R1, where creating the invite is the switch
///     (`/invite-partner?switch=1`; a Dating pause is confirmed there if
///     the server asks for it);
///   * Dating -> Just for me: "Use Attune just for you?" first, unless
///     [oneTap] and nothing is enrolled (a wrong first choice, §3.12);
///   * a refusal that needs a confirmation (a pending invite) asks it.
/// [home] is the state the screen shows (else the provider's). Errors are
/// shown in a snackbar; the home follows the new state.
Future<PathChoiceOutcome> switchPath(
  BuildContext context,
  WidgetRef ref, {
  required AppPath to,
  bool oneTap = false,
  HomeSnapshot? home,
}) async {
  final userId = ref.read(homeAuthProvider).currentUser?.id;
  if (userId == null) return PathChoiceOutcome.failed;
  final HomeSnapshot state = home ?? ref.read(homeStateProvider(userId));
  if (to == AppPath.relationship) {
    await context.push('${RouteNames.invitePartner}?switch=1');
    return PathChoiceOutcome.done;
  }
  final enrolled = state.dating?.enrolled ?? false;
  if (state.path == AppPath.dating &&
      to == AppPath.justMe &&
      (!oneTap || enrolled)) {
    if (!await showJustForMeSheet(context)) return PathChoiceOutcome.cancelled;
    if (!context.mounted) return PathChoiceOutcome.cancelled;
  }
  final outcome = await choosePath(
    context,
    ref,
    userId: userId,
    path: to,
    partnerName: state.linkDetail.partnerFirstName,
  );
  if (!context.mounted) return outcome;
  final loc = AppLocalizations.of(context)!;
  final message = switch (outcome) {
    PathChoiceOutcome.datingOffline => loc.flow_pathDatingOffline,
    PathChoiceOutcome.offline => loc.flow_switchOffline,
    // An account not ready for a switch is told, never left silent.
    PathChoiceOutcome.failed ||
    PathChoiceOutcome.needsSignUp => loc.flow_saveFailed,
    _ => null,
  };
  if (message != null) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
  return outcome;
}

/// §3.12 "Use Attune just for you?" (Dating -> Just for me).
Future<bool> showJustForMeSheet(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showFlowConfirm(
    context,
    title: loc.flow_justMeSheetTitle,
    body: loc.flow_justMeSheetBody,
    confirm: loc.flow_justMeSheetSwitch,
    cancel: loc.flow_cancel,
  );
}

/// §3.12: "You're in a shared space with {name}. To use Attune another way,
/// end it first. Pausing keeps it, read-only, for up to 30 days." with the
/// existing Spec 3a actions (no pause while already paused). Shared by
/// Settings -> How you use Attune, J4 and the Dating slot (P-18).
Future<void> showSharedSpaceSheet(BuildContext context, HomeSnapshot home) {
  final loc = AppLocalizations.of(context)!;
  final relationshipId = home.linkDetail.relationshipId;
  final name = home.linkDetail.partnerFirstName;
  final canPause = home.link != LinkState.paused && relationshipId != null;
  // The destructive End is never the filled button (B7 review M-7): with
  // no Pause to offer, "Not now" leads.
  (String, VoidCallback)? endIn(BuildContext sheet) =>
      relationshipId == null
          ? null
          : (
            loc.flow_sharedEnd,
            () {
              Navigator.of(sheet).pop();
              EndRelationshipAction.confirmAndEnd(
                context,
                relationshipId: relationshipId,
              );
            },
          );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) {
      final end = endIn(sheet);
      final notNow = (loc.flow_notNow, () => Navigator.of(sheet).pop());
      return FlowConfirmSheetBody(
        title: loc.flow_sharedOpenTitle(
          name == null || name.isEmpty ? loc.flow_yourPartner : name,
        ),
        body: loc.flow_sharedOpenBody,
        actions: [
          if (canPause) ...[
            (
              loc.flow_sharedPause,
              () {
                Navigator.of(sheet).pop();
                PauseRelationshipAction.confirmAndPause(
                  context,
                  relationshipId: relationshipId,
                );
              },
            ),
            if (end != null) end,
            notNow,
          ] else ...[
            notNow,
            if (end != null) end,
          ],
        ],
      );
    },
  );
}

/// A switch the server refused with `path:relationship_open` (B4 review
/// M-2): the screen's home was stale, so it is read again and the shared
/// space sheet shows the fresh link. Never a snackbar in [switchPath]
/// (Settings would say it twice).
///
/// The fresh home can turn Tab 2 from Me into Chat, which disposes the
/// caller (J4, the Dating slot), so the sheet and its Pause and End run
/// from the root navigator, which outlives it (B7 review M-1).
Future<void> showSharedSpaceSheetAfterRefusal(
  BuildContext context,
  HomeSnapshot shown,
) async {
  final host = Navigator.of(context, rootNavigator: true).context;
  final container = ProviderScope.containerOf(context, listen: false);
  final userId = container.read(homeAuthProvider).currentUser?.id;
  if (userId != null) {
    await container.read(homeStateProvider(userId).notifier).refresh();
  }
  if (!host.mounted) return;
  final fresh =
      userId == null ? shown : container.read(homeStateProvider(userId));
  await showSharedSpaceSheet(host, fresh);
}
