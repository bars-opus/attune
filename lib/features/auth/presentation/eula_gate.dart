import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/data/eula_acceptance_service.dart';

/// Presents the EULA once per user and records the acceptance.
///
/// Shared by the two paths that can create a real account: LoginScreen's
/// sign-in flow, and OnboardingFlow's submission (reached via
/// PasswordlessAuthStep when accepting a partner invite). Keeping the prompt
/// here rather than duplicating it means the two can't drift apart on which
/// version they record or how a decline is handled.
class EulaGate {
  const EulaGate._();

  /// Returns true when the user may proceed — either they had already accepted
  /// the current version, or they accepted it just now.
  ///
  /// Returns false when consent was declined or could not be recorded; the
  /// caller must not advance in that case.
  static Future<bool> ensureAccepted(
    BuildContext context, {
    EulaAcceptanceService? service,
  }) async {
    final eulaService = service ?? EulaAcceptanceService();

    if (!await eulaService.needsAcceptance()) return true;
    if (!context.mounted) return false;

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

    if (accepted != true) return false;

    try {
      await eulaService.recordAcceptance();
      return true;
    } catch (_) {
      if (context.mounted) {
        context.showErrorSnackbar(
          'We could not save your acceptance. Please try again.',
        );
      }
      return false;
    }
  }
}
