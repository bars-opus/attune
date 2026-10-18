import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Pause our shared space" (Spec 3a; research 06 §3 F1 (3)): chat becomes
/// read-only for both, nothing new is shared, and nobody is notified.
class PauseRelationshipAction {
  static void confirmAndPause(
    BuildContext context, {
    required String relationshipId,
    RelationshipLifecycleService? service,
    Future<void> Function()? clearSurfaces,
  }) {
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 460.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.info,
        title: 'Pause your shared space?',
        message:
            'Chat becomes read-only for both of you and nothing new is shared. '
            'Either of you can resume or end it within 30 days. '
            // Paint Ball, Word Hunt and Snakes and Ladders are abandoned by
            // their relationship-change triggers; every other game's writes
            // are refused while paused and pick up again on resume.
            'Paint Ball, Word Hunt and Snakes and Ladders end; other games '
            'wait. '
            "Your partner won't get a notification.",
        confirmText: 'Pause',
        onConfirm: () async {
          try {
            await (service ?? RelationshipLifecycleService()).pause(
              relationshipId,
            );
            await (clearSurfaces ?? clearTogetherDeviceSurfaces)();
            if (context.mounted) {
              try {
                ProviderScope.containerOf(
                  context,
                  listen: false,
                ).invalidate(activeRelationshipIdProvider);
              } catch (_) {}
            }
            relationshipModeResyncSignal.value++;
            if (context.mounted) context.showSuccessSnackbar('Paused.');
          } catch (error) {
            if (!context.mounted) return;
            context.showErrorSnackbar(
              error is RelationshipLifecycleException
                  ? error.message
                  : "Couldn't pause. Please try again.",
            );
          }
        },
      ),
    );
  }
}
