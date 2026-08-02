// lib/features/relationships/presentation/widgets/end_relationship_action.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';

/// Shared end-relationship confirmation + action flow, mirroring
/// LogoutAction (lib/features/auth/presentation/widgets/logout_action.dart)
/// so this destructive action goes through the same confirmation-dialog
/// pattern as the rest of this codebase's irreversible actions.
class EndRelationshipAction {
  static void confirmAndEnd(
    BuildContext context, {
    required String relationshipId,
  }) {
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 340.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.warning,
        title: 'End this relationship?',
        confirmText: 'End relationship',
        message:
            'This can\'t be undone. Your chat history will be archived and '
            'no longer accessible from either side.',
        onConfirm: () async {
          try {
            await RelationshipLifecycleService().endRelationship(
              relationshipId: relationshipId,
            );
            if (!context.mounted) return;
            context.showSuccessSnackbar('Relationship ended.');
            // No public API exists on HomeScreen to force its private
            // _syncRelationshipMode to run immediately (it's a private
            // method, and this action is triggered from Settings, a
            // separate route pushed on top of HomeScreen) — pushing to
            // Healing Mode's real entry route (RouteNames.healingJourney,
            // confirmed at app_router.dart:196, HealingJourneyScreen
            // takes no constructor args) offers the next step immediately;
            // HomeScreen's own next resume (when the user eventually
            // navigates back to it) picks up the mode change via the
            // shared reconciliation mechanism (design spec §1) — no
            // separate signal needs to be sent to HomeScreen from here.
            context.push(RouteNames.healingJourney);
          } catch (error) {
            if (!context.mounted) return;
            final message = error is RelationshipLifecycleException
                ? error.message
                : 'Could not end this relationship. Please try again.';
            context.showErrorSnackbar(message);
          }
        },
      ),
    );
  }
}
