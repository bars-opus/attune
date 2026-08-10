import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/data/eula_acceptance_service.dart';

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
/// sign-in flow, and OnboardingFlow's submission (reached via
/// PasswordlessAuthStep when accepting a partner invite). Keeping the prompt
/// here rather than duplicating it means the two can't drift apart on which
/// version they record or how a decline is handled.
class EulaGate {
  const EulaGate._();

  /// Returns [EulaOutcome.accepted] when the user may proceed — either they
  /// had already accepted the current version, or they accepted it just now.
  ///
  /// See [EulaOutcome] for why declined and unavailable are separate.
  static Future<EulaOutcome> ensureAccepted(
    BuildContext context, {
    EulaAcceptanceService? service,
  }) async {
    final eulaService = service ?? EulaAcceptanceService();

    if (!await eulaService.needsAcceptance()) return EulaOutcome.accepted;
    if (!context.mounted) return EulaOutcome.unavailable;

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
}
