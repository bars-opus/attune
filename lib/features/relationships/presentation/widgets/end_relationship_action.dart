// lib/features/relationships/presentation/widgets/end_relationship_action.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';

/// Shared end-relationship confirmation + action flow, mirroring
/// LogoutAction (lib/features/auth/presentation/widgets/logout_action.dart)
/// so this destructive action goes through the same confirmation-dialog
/// pattern as the rest of this codebase's irreversible actions.
class EndRelationshipAction {
  static void confirmAndEnd(
    BuildContext context, {
    required String relationshipId,
    RelationshipLifecycleService? service,
    VoidCallback? onEnded,
  }) {
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 420.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.warning,
        // Spec 3a (F1 (1), (2)): no one is notified, and the chat stays
        // readable for both for 30 days. Stories close at once (Wave 5
        // copy, owner ruling 4).
        title: 'End your shared space?',
        confirmText: 'End',
        message:
            "You'll both be able to read your chat for 30 days, then it closes. "
            'Stories close for both of you now. You can download yours from '
            'Download my data in those 30 days, and delete them there any time. '
            'If you seal your side, that ends at once: download first if you '
            'want a copy. '
            'Closed chats are deleted after 12 months. '
            "Your partner won't get a notification; they'll see it the next "
            'time they open Attune.',
        onConfirm: () async {
          try {
            await (service ?? RelationshipLifecycleService()).endRelationship(
              relationshipId: relationshipId,
            );
            onEnded?.call();
            // The couple's plans leave this phone's home screen, lock
            // screen and calendar (Together Phase 8). Never throws.
            await clearTogetherDeviceSurfaces();
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
