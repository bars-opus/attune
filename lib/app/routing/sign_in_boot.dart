import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart'
    hide preferencesServiceProvider;
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// main.dart's router state at boot (Spec 1 §5.3, W2a): synchronous reads
/// only, so nothing here holds the first frame.
RoutingNotifier bootRoutingNotifier(
  SharedPreferences prefs, {
  DateTime Function() now = DateTime.now,
}) => RoutingNotifier(
  prefs: prefs,
  isFirstLaunch: PreferencesService(prefs).isFirstLaunch,
  // The last public config this phone read, else the build default; App
  // keeps it current once the config has been fetched.
  flowV2:
      PublicAppConfigCache(prefs).read()?.flowSignInV2 ??
      Environment.flowV2Default,
  guestAgeOk: AgeGateStore.readGuestOk(prefs),
  underAgeBlocked: AgeGateStore.readBlocked(prefs, now()),
  now: now,
);

/// main.dart's invite link, once the router has settled (spec §5.2, R3):
/// clears first launch the way IntroScreen's "Get started" does, so the
/// redirect doesn't swallow the visit, then opens RI-1 for a signed-out
/// invitee under flow_signin_v2 and today's /onboarding otherwise.
Future<void> openInviteLanding(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(preferencesServiceProvider).setFirstLaunchCompleted();
  if (!context.mounted) return;
  final routing = container.read(routingNotifierProvider);
  routing.completeFirstLaunch();
  final target = inviteLinkLocation(routing);
  // A fresh key for RI-1/RI-2 on every link (review M-6): a link that lands
  // while RI-2 is asking for a code rebuilds it with the code just stored.
  // The flag-off /onboarding visit stays exactly as today.
  GoRouter.of(
    context,
  ).go(target, extra: target == RouteNames.invite ? ++_inviteLinks : null);
}

/// Counts invite links this run; JSON-encodable, so route restoration keeps
/// it.
int _inviteLinks = 0;
