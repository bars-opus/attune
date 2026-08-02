// lib/features/relationships/presentation/widgets/end_relationship_action.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
            // Update the same local OnboardingStore HomeScreen reads,
            // directly, rather than waiting for the next
            // background->resume cycle — the ending user (unlike their
            // now-notified ex-partner) already knows what just happened
            // and shouldn't have to background the app to stop seeing a
            // stale Chat tab underneath the Healing Mode screen this
            // pushes to next. Mirrors HomeScreen._loadStore's own
            // scope-derivation exactly (final HomeScreen.mode reconciler
            // still runs on next resume regardless, as a safety net if
            // this write or the read that follows it doesn't land before
            // the user navigates back).
            final userId = Supabase.instance.client.auth.currentUser?.id;
            if (userId != null && userId.isNotEmpty) {
              final prefs = await SharedPreferences.getInstance();
              final store = OnboardingStore(
                prefs,
                scope: '${OnboardingStore.userScopePrefix}.$userId',
              );
              await store.syncModeFromServer(OnboardingMode.personal);
            }
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
