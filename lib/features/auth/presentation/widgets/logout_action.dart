// lib/features/auth/presentation/widgets/logout_action.dart

import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared logout confirmation + sign-out flow, so every entry point (Settings,
/// the Opinions tab menu, etc.) goes through the same confirmation copy and
/// the same signOut()/clearUserData()/clearUser() sequence rather than each
/// call site re-implementing it and risking drift.
class LogoutAction {
  static void confirmAndSignOut(BuildContext context) {
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 320.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.info,
        title: 'Are you sure you want to logout',
        confirmText: 'Log out',
        message:
            'You would have to log in again to access your account and data',
        onConfirm: () async {
          try {
            final ref = ProviderScope.containerOf(context, listen: false);

            // signOut() clears the Supabase session + encrypted chat cache.
            await ref.read(authOperationsProvider).signOut();

            // Clear user-specific SharedPrefs (keeps theme/language).
            await ref.read(preferencesServiceProvider).clearUserData();

            // Bypass the 100ms debounce so the router sees null user
            // immediately when context.go fires below.
            ref.read(routingNotifierProvider).clearUser();

            if (context.mounted) {
              context.showSuccessSnackbar('Signed out successfully');
              context.go(RouteNames.intro);
            }
          } catch (e) {
            if (context.mounted) {
              context.showErrorSnackbar('Sign out failed: $e');
            }
          }
        },
      ),
    );
  }
}
