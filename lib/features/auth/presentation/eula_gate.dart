import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/data/eula_acceptance_service.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The outcome of a consent check.
///
/// Distinguishing these matters because the caller's response differs
/// sharply: only [declined] is a real "this person said no" that justifies
/// ending their session. [unavailable] means the prompt never got a genuine
/// answer (the context was torn down mid-sheet, or the acceptance write
/// failed) — signing out there destroys a valid, freshly-verified session
/// over something the user never did. These used to collapse into one
/// `false`, which is exactly how a navigation race mid-sheet turned into a
/// spurious sign-out immediately after a successful OTP verification.
enum EulaOutcome {
  accepted,
  declined,
  unavailable;

  bool get mayProceed => this == EulaOutcome.accepted;
}

/// Presents the EULA once per user and records the acceptance.
///
/// Shared by the two paths that can create a real account: LoginScreen's
/// sign-in flow, and OnboardingFlow's final submission. Keeping the prompt
/// here rather than duplicating it means the two can't drift apart on which
/// version they record or how a decline is handled.
class EulaGate {
  const EulaGate._();

  /// Spec 1 W2b (§5.2): EULA v2 under flow_signin_v2, v1 otherwise.
  static String versionFor(BuildContext context) {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      return container.read(signInFlowV2Provider)
          ? EulaAcceptanceService.v2Version
          : EulaAcceptanceService.currentVersion;
    } catch (_) {
      return EulaAcceptanceService.currentVersion;
    }
  }

  /// The check [ensureAccepted] runs when no service is passed: the version
  /// from [versionFor] (review M-5).
  static EulaAcceptanceService serviceFor(BuildContext context) =>
      EulaAcceptanceService(version: versionFor(context));

  /// Returns [EulaOutcome.accepted] when the user may proceed — either they
  /// had already accepted the current version, or they accepted it just now.
  ///
  /// See [EulaOutcome] for why declined and unavailable are separate.
  static Future<EulaOutcome> ensureAccepted(
    BuildContext context, {
    EulaAcceptanceService? service,
  }) async {
    final eulaService = service ?? serviceFor(context);

    if (!await eulaService.needsAcceptance()) return EulaOutcome.accepted;
    if (!context.mounted) return EulaOutcome.unavailable;

    // Spec 1 W2b (batch 3 M-6): under flow_signin_v2 consent is A5's or
    // A5c's, never this sheet, which shows the v1 text; and recording here
    // could create an account with no date of birth (D8).
    final flowV2 = _flowV2Scope(context);
    if (flowV2 != null) return _toSignUp(context, flowV2);

    final loc = AppLocalizations.of(context)!;

    final accepted = await BottomSheetUtils.showDocumentationBottomSheet<bool>(
      context: context,
      document: LegalDocumentationData.eula(context),
      // A swipe-away would return null and read as a decline — make
      // Accept/Reject the only ways out of this sheet.
      isDismissible: false,
      enableDrag: false,
      onAgree: () => Navigator.pop(context, true),
      onDecline: () => Navigator.pop(context, false),
      agreeButtonText: loc.commonAccept,
      declineButtonText: loc.commonReject,
    );

    // An explicit Reject tap is the only false. A null means the sheet went
    // away without either button being pressed — with isDismissible and
    // enableDrag both off, the user cannot cause that, so it is always a
    // teardown (the route stack changed underneath it), never a decision.
    if (accepted == false) return EulaOutcome.declined;
    if (accepted == null) return EulaOutcome.unavailable;

    try {
      await eulaService.recordAcceptance();
      return EulaOutcome.accepted;
    } catch (_) {
      if (context.mounted) {
        context.showErrorSnackbar(
          'We could not save your acceptance. Please try again.',
        );
      }
      return EulaOutcome.unavailable;
    }
  }

  /// The provider scope when flow_signin_v2 is on, else null.
  static ProviderContainer? _flowV2Scope(BuildContext context) {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      return container.read(signInFlowV2Provider) ? container : null;
    } catch (_) {
      return null;
    }
  }

  /// Under flow_signin_v2, nothing is asked or recorded here: no account
  /// yet goes to A5 (`/signup`, which takes the name and date of birth
  /// first), an account on an older EULA to A5c (`/signup?entry=returning`),
  /// and one whose consent the server already holds carries on. Unreadable
  /// (offline): it stays where it is.
  static Future<EulaOutcome> _toSignUp(
    BuildContext context,
    ProviderContainer container,
  ) async {
    final HomeState state;
    try {
      state = await container.read(accountServiceProvider).homeState();
    } catch (error) {
      debugPrint('[eula] v2 consent route unread: ${error.runtimeType}');
      // Never a silent Finish (review B5 M-4).
      if (context.mounted) {
        context.showErrorSnackbar(
          AppLocalizations.of(context)!.flow_saveFailed,
        );
      }
      return EulaOutcome.unavailable;
    }
    if (state.hasAccount && !state.needs.contains(HomeNeed.consent)) {
      return EulaOutcome.accepted;
    }
    if (!context.mounted) return EulaOutcome.unavailable;
    GoRouter.of(context).go(
      state.hasAccount
          ? '${RouteNames.signUp}?entry=${SignUpEntry.returning.wire}'
          : RouteNames.signUp,
    );
    return EulaOutcome.unavailable;
  }
}
