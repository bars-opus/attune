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
            // Force HomeScreen's existing _syncRelationshipMode to run
            // immediately rather than waiting for the next
            // background->resume cycle — the ending user (unlike their
            // now-notified ex-partner) already knows what just happened
            // and shouldn't have to background the app to stop seeing a
            // stale Chat tab underneath the Healing Mode screen this
            // pushes to next. A plain SharedPreferences write alone is
            // NOT sufficient here: HomeScreen's build() reads _gateData, a
            // plain field that only changes via setState, so it doesn't
            // re-derive anything just because this route stack pops back
            // to it — an explicit signal is required, not just shared
            // storage (see relationshipModeResyncSignal's doc in
            // home_screen.dart). _syncRelationshipMode re-derives mode
            // from the server itself, so no local write happens here.
            relationshipModeResyncSignal.value++;
            if (!context.mounted) return;
            context.showSuccessSnackbar('Relationship ended.');
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
