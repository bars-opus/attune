import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What [choosePath] did.
enum PathChoiceOutcome {
  /// The server took it (or, with queueOffline, it was queued).
  done,

  /// The person said no to a confirmation; nothing changed.
  cancelled,

  /// No connection; nothing changed.
  offline,

  /// Dating chosen with no connection: never queued (D20).
  datingOffline,

  /// A shared space is open or paused (`path:relationship_open`); the
  /// caller shows how to end or pause it (§3.12).
  relationshipOpen,

  /// `path:needs_signup`: the account isn't ready (a queued A5, an older
  /// EULA); the caller finishes it first (B3 review I#2).
  needsSignUp,

  /// Anything else; nothing changed.
  failed,
}

/// The one way any screen changes the path (A6, J4, the Dating slot,
/// Settings -> How you use Attune; Spec 1 §3.7, §3.12): set_my_path, and on
/// its refusals the confirmation it asks for, then the call again,
/// confirmed. The answer is applied to the home state, so the shell
/// follows. [queueOffline] keeps a Relationship or Just for me choice for
/// the replay (A6 only, §3.14); Dating is never queued (D20).
Future<PathChoiceOutcome> choosePath(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required AppPath path,
  bool confirmed = false,
  bool queueOffline = false,
  String? partnerName,
}) async {
  final service = ref.read(homeStateServiceProvider);
  final notifier = ref.read(homeStateProvider(userId).notifier);
  // Read before the first await: the screen may be gone by the answer.
  final prefs = ref.read(sharedPreferencesProvider);
  var isConfirmed = confirmed;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final state = await service.setPath(path, confirmed: isConfirmed);
      await notifier.apply(state);
      // Spec 1 W5 final review M-4: the server dropped the About us draft
      // with the switch to Dating; this account's queued draft answers go
      // too, so a later replay can't rebuild it.
      if (state.path == AppPath.dating) {
        await clearAboutUsDraftQueue(prefs, userId);
      }
      return PathChoiceOutcome.done;
    } on PathRefused catch (refused) {
      if (!context.mounted) return PathChoiceOutcome.cancelled;
      switch (refused.reason) {
        case PathRefusal.confirmWithdraw:
          if (!await showCancelInviteSheet(context, partnerName: partnerName)) {
            return PathChoiceOutcome.cancelled;
          }
        case PathRefusal.confirmPauseDating:
          if (!await showPauseDatingSheet(context)) {
            return PathChoiceOutcome.cancelled;
          }
        case PathRefusal.relationshipOpen:
          return PathChoiceOutcome.relationshipOpen;
        case PathRefusal.needsSignUp:
          return PathChoiceOutcome.needsSignUp;
        case PathRefusal.invalid:
          return PathChoiceOutcome.failed;
      }
      isConfirmed = true;
    } on HomeOffline {
      if (path == AppPath.dating) return PathChoiceOutcome.datingOffline;
      if (!queueOffline) return PathChoiceOutcome.offline;
      await OnboardingStore(
        prefs,
        scope: '${OnboardingStore.userScopePrefix}.$userId',
      ).savePendingPath(path, confirmed: isConfirmed);
      notifier.reloadLocal();
      return PathChoiceOutcome.done;
    }
  }
  return PathChoiceOutcome.failed;
}

/// §3.12 "Cancel your invite?" (Relationship, pending -> another path).
Future<bool> showCancelInviteSheet(
  BuildContext context, {
  String? partnerName,
}) {
  final loc = AppLocalizations.of(context)!;
  final name = partnerName?.trim();
  return showFlowConfirm(
    context,
    title: loc.flow_cancelInviteTitle,
    body:
        name == null || name.isEmpty
            ? loc.flow_cancelInviteBody
            : loc.flow_cancelInviteBodyNamed(name),
    confirm: loc.flow_cancelInviteConfirm,
    cancel: loc.flow_cancelInviteKeep,
  );
}

/// §3.12 "Inviting a partner pauses Dating" (Dating -> Relationship).
Future<bool> showPauseDatingSheet(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showFlowConfirm(
    context,
    title: loc.flow_pauseDatingTitle,
    body: loc.flow_pauseDatingBody,
    confirm: loc.flow_continue,
    cancel: loc.flow_cancel,
  );
}

/// A two-button confirmation sheet in the flow's style (§2.3: large text,
/// 48 dp targets, a heading). True only for [confirm].
Future<bool> showFlowConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  required String cancel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (sheet) => FlowConfirmSheet(
          title: title,
          body: body,
          confirm: confirm,
          cancel: cancel,
        ),
  );
  return result ?? false;
}

class FlowConfirmSheet extends StatelessWidget {
  const FlowConfirmSheet({
    super.key,
    required this.title,
    required this.body,
    required this.confirm,
    required this.cancel,
  });

  final String title;
  final String body;
  final String confirm;
  final String cancel;

  @override
  Widget build(BuildContext context) => FlowConfirmSheetBody(
    title: title,
    body: body,
    actions: [
      (confirm, () => Navigator.of(context).pop(true)),
      (cancel, () => Navigator.of(context).pop(false)),
    ],
  );
}

/// A sheet with a heading, a body and its buttons: the first is the
/// primary, the rest secondary (§2.3: large text, 48 dp targets).
class FlowConfirmSheetBody extends StatelessWidget {
  const FlowConfirmSheetBody({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AllowLargeText(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: Spacing.sm),
                i == 0
                    ? FlowPrimaryButton(
                      label: actions[i].$1,
                      onPressed: actions[i].$2,
                    )
                    : FlowSecondaryButton(
                      label: actions[i].$1,
                      onPressed: actions[i].$2,
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
