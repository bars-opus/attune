import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/couple_map/data/couple_map_device_data.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';
import 'package:attune/features/together/presentation/together_providers.dart'
    show
        togetherWidgetEnabledProvider,
        togetherLiveEnabledProvider,
        togetherMirrorEnabledProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign out to the login screen with no BuildContext (Spec 2: the lock gate
/// sits above the Navigator). The same sequence as LogoutAction, without its
/// confirmation sheet. The caller checks it worked before opening anything
/// (review I1).
Future<void> safetySignOut(Ref ref) async {
  try {
    await ref.read(authOperationsProvider).signOut();
  } catch (_) {
    // AuthOperations refuses while busy; the SDK's own sign-out below always
    // clears the local session first.
  }
  if (ref.read(currentUserProvider) != null) {
    // Chat review #18: this fallback skips AuthOperations, so release the
    // device here too (bounded by its owner; a repeat is a no-op).
    try {
      await ref.read(signOutHooksProvider).beforeSignOut?.call();
    } catch (_) {}
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }
  try {
    await clearTogetherDeviceSurfaces();
    // The map's home area, pin choice, tile cache and pin faces too, so
    // the next account on this phone inherits none of them.
    await clearCoupleMapDeviceData().catchError((Object _) {});
    await ref.read(preferencesServiceProvider).clearUserData();
  } catch (_) {}
  ref.invalidate(togetherWidgetEnabledProvider);
  ref.invalidate(togetherLiveEnabledProvider);
  ref.invalidate(togetherMirrorEnabledProvider);
  ref.read(routingNotifierProvider).clearUser();
  ref.read(appRouterProvider).go(RouteNames.intro);
}
