import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// flow_signin_v2 for widgets and listeners (Spec 1 §5.3): the effective
/// value from [flowSignInV2Provider], or off when it can't be read at all
/// (no SharedPreferences in a bare test host). A shared screen that only
/// branches on the flag never throws over it.
final signInFlowV2Provider = Provider<bool>((ref) {
  try {
    return ref.watch(flowSignInV2Provider);
  } catch (_) {
    return false;
  }
});

/// Keeps the router's sign-in flow on the live public config (Spec 1 §5.3,
/// §5.4). App watches it. The boot value comes from the same cache, else
/// the same build default, so the first value never differs and nothing
/// fires while App builds: only a later change reaches GoRouter.
final routingFlowV2SyncProvider = Provider<void>((ref) {
  ref.listen<bool>(
    signInFlowV2Provider,
    (_, next) => ref.read(routingNotifierProvider).setFlowV2(next),
  );
});
