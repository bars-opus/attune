// lib/features/settings/widgets/delete_account_action.dart
import 'package:attune/features/couple_map/data/couple_map_device_data.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/settings/data/account_deletion_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared account-deletion confirmation + teardown flow, mirroring
/// LogoutAction and EndRelationshipAction so this — the most irreversible
/// action in the app — goes through the same confirmation-dialog pattern
/// as every other destructive one.
///
/// Implements ATTUNE_MASTER_SPEC.md §10's "User can delete account and all
/// data at any time". The erasure itself is entirely server-side (the
/// `delete-account` edge function); this handles confirmation and the
/// local teardown that must follow it.
class DeleteAccountAction {
  static void confirmAndDelete(BuildContext context) {
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 400.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        // `warning` (not `info`): this is destructive and unrecoverable,
        // matching EndRelationshipAction rather than LogoutAction.
        type: ConfirmationType.warning,
        title: 'Delete your account?',
        confirmText: 'Delete permanently',
        // States plainly what survives and why. §10 retains anonymised
        // shared analysis and safety records, so promising "everything is
        // erased" would be untrue — and a deletion notice is the one place
        // that has to be exact.
        message:
            'This permanently deletes your account, messages, photos, quiz '
            'answers and insights. It cannot be undone.\n\n'
            // Spec 3b (R3b-7): what deletion does to a shared space.
            "If you're in a shared space, it ends; your messages, photos and "
            'game answers are removed from it. Shared history such as Pulse stays with the '
            'space until it is deleted, 12 months after it closes. Safety '
            'records are kept in anonymised form only, as the law requires.',
        onConfirm: () async {
          final ref = ProviderScope.containerOf(context, listen: false);
          try {
            await AccountDeletionService().deleteAccount();

            // The auth user no longer exists, so the retained session now
            // points at a deleted identity. The same teardown LogoutAction
            // performs is required here — skipping it would leave the app
            // holding an encrypted chat cache and user-scoped preferences
            // for an account that is gone.
            await ref.read(authOperationsProvider).signOut();
            // Together's card, lock-screen plan and calendar copy go too —
            // before clearUserData(), which wipes the copy's calendar id.
            await clearTogetherDeviceSurfaces();
            // The map's home area, pin choice, tile cache and pin faces too, so
            // the next account on this phone inherits none of them.
            await clearCoupleMapDeviceData().catchError((Object _) {});
            await ref.read(preferencesServiceProvider).clearUserData();
            ref.read(routingNotifierProvider).clearUser();

            if (!context.mounted) return;
            context.showSuccessSnackbar('Your account has been deleted.');
            context.go(RouteNames.intro);
          } catch (error) {
            if (!context.mounted) return;
            final message = error is AccountDeletionException
                ? error.message
                : 'Could not delete your account. Please try again.';
            context.showErrorSnackbar(message);
          }
        },
      ),
    );
  }
}
