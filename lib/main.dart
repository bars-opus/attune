import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:attune/app/app.dart';
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart'
    hide preferencesServiceProvider;
import 'package:attune/features/auth/providers/auth_provider.dart'
    show SignOutHooks, signOutHooksProvider;
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/couple_map/widget/presentation/widget_deep_link.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart'
    show coupleMapEnabledProvider;
import 'package:attune/features/planning/presentation/planning_providers.dart'
    as planning
    show currentRelationshipIdProvider;
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart'
    show PlanningHomeTab;
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/material.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The couple map (spec 2026-10-16 §6.3). Token from the environment,
  // restricted to the app's bundle IDs in the Mapbox console.
  if (Environment.mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(Environment.mapboxAccessToken);
  }

  await _initializeSupabase();
  _initializeDeepLinks();
  final chatCache = ChatCacheService();
  // init() recovers from a corrupt or locked store itself and bounds the
  // keystore read; this outer bound is the last line: a cache can never
  // hold the first frame (Spec 16). If it fires, init() keeps running in
  // the background; until it finishes, cache reads miss.
  try {
    await chatCache.init().timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('[startup] chat cache unavailable: ${error.runtimeType}');
  }

  final prefs = await SharedPreferences.getInstance();
  final routingNotifier = RoutingNotifier(
    prefs: prefs,
    isFirstLaunch: PreferencesService(prefs).isFirstLaunch,
  );
  final appRouter = createAppRouter(routingNotifier);
  final safetyLockSeed = await _safetyLockSeed();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => routingNotifier),
        appRouterProvider.overrideWithValue(appRouter),
        safetyLockSeedProvider.overrideWithValue(safetyLockSeed),
        chatCacheServiceProvider.overrideWithValue(chatCache),
        notificationConfigProvider.overrideWithValue(
          buildNanoEmbryoNotificationConfig(),
        ),
        // Chat review #18: every sign-out releases this phone's push
        // subscription (the auth layer never imports the push plugin).
        signOutHooksProvider.overrideWith(
          (ref) => SignOutHooks(
            beforeSignOut: () =>
                ref.read(oneSignalServiceProvider).beforeSignOut(),
            signOutFailed: () =>
                ref.read(oneSignalServiceProvider).cancelRelease(),
          ),
        ),
      ],
      child: const App(),
    ),
  );
}

/// The lock decision before the first frame (Spec 2, review I5): the common
/// unlocked path mounts the Router at once; a locked phone never shows a
/// frame of the app. Null (decide asynchronously) if the keystore can't be
/// read.
/// A hung keystore (seen on some Samsung phones) must not hold the splash:
/// after 3 s the gate decides asynchronously, still fail-closed (review M-1).
Future<SafetyLockState?> _safetyLockSeed() async {
  try {
    return await computeLockSeed(
      quickExitFlag: QuickExitService.requiresSafetyUnlock,
      clearQuickExitFlag: QuickExitService.clearSafetyUnlockRequired,
      pins: SafetyPinStore.instance,
      signedIn: Supabase.instance.client.auth.currentUser != null,
    ).timeout(const Duration(seconds: 3));
  } catch (_) {
    return null;
  }
}

Future<void> _initializeSupabase() async {
  final hasSupabaseConfig =
      Environment.supabaseUrl.isNotEmpty &&
      Environment.supabaseAnonKey.isNotEmpty;

  if (!hasSupabaseConfig) {
    debugPrint('[startup] Supabase config missing; auth/backend disabled.');
    return;
  }

  try {
    await Supabase.initialize(
      url: Environment.supabaseUrl,
      publishableKey: Environment.supabaseAnonKey,
      debug: Environment.isDebug,
    ).timeout(const Duration(seconds: 30));
    debugPrint('[startup] Supabase initialized.');
  } catch (error) {
    debugPrint(
      '[startup] Supabase initialization failed: ${error.runtimeType}',
    );
  }
}

void _initializeDeepLinks() {
  final appLinks = AppLinks();

  unawaited(
    appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) _handleDeepLink(uri);
        })
        .catchError((error) {
          debugPrint('[deep-link] initial link failed: ${error.runtimeType}');
        }),
  );

  appLinks.uriLinkStream.listen(
    _handleDeepLink,
    onError: (Object error) {
      debugPrint('[deep-link] stream error: ${error.runtimeType}');
    },
  );
}

void _handleDeepLink(Uri uri) {
  debugPrint('[deep-link] received ${_redactUri(uri)}');

  if (_isAuthCallback(uri)) {
    debugPrint('[deep-link] auth callback detected.');
    unawaited(_handleAuthCallback(uri));
    return;
  }

  final planningTab = planningTabFromLink(uri);
  if (planningTab != null) {
    debugPrint('[deep-link] planning link detected.');
    unawaited(_openPlanningWhenReady(planningTab));
    return;
  }

  final inviteCode = _extractInviteCode(uri);
  if (inviteCode != null) {
    debugPrint('[deep-link] invite detected.');
    unawaited(_storePendingInviteCode(inviteCode));
  }
}

Future<void> _storePendingInviteCode(String code) async {
  final prefs = await SharedPreferences.getInstance();
  await OnboardingStore(
    prefs,
    scope: OnboardingStore.anonymousScope,
  ).storePendingInviteCode(code);

  // Storing the code alone was previously the entire handler — nothing
  // ever navigated, so scanning the invite QR only did something useful if
  // the user happened to wander into onboarding on their own later. Drive
  // to /onboarding directly (OnboardingGate reads pendingInviteCode back
  // out of the same store and, for an unauthenticated visitor, now routes
  // to /login instead of bouncing to /home — see onboarding_gate.dart).
  //
  // A single addPostFrameCallback only guarantees one frame has been
  // painted — it does NOT guarantee GoRouter's own boot sequence
  // (initialLocation '/_invisible' -> its redirect callback resolving to
  // /intro or /home -> that route's own builder mounting) has fully
  // settled, especially on a cold start where this whole handler is racing
  // that sequence from the very first microtask after runApp. Calling
  // .go() into the middle of that produced a transient "Page not found"
  // GoException that then self-corrected once the boot redirect finished
  // and this retry fired again — waitForRouterSettled below closes that
  // window by polling until the router is actually parked on a real route
  // before this ever calls .go() itself.
  unawaited(_navigateToOnboardingWhenReady());
}

Future<void> _navigateToOnboardingWhenReady() async {
  final context = await waitForRouterSettled();
  if (context == null || !context.mounted) return;

  // A brand-new installer (the most common way to receive an invite —
  // App Store -> first launch) still has isFirstLaunch=true at this
  // point. createAppRouter's redirect unconditionally sends every route
  // except /intro back to /intro while that flag is set, which would
  // silently swallow the .go(onboarding) below and strand the invite —
  // see app_router.dart's redirect callback. Clear it first, the same
  // way IntroScreen's own "Get Started" button does: persist via
  // PreferencesService, then flip RoutingNotifier synchronously so the
  // very next redirect check already sees isFirstLaunch=false.
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(preferencesServiceProvider).setFirstLaunchCompleted();
  if (!context.mounted) return;
  container.read(routingNotifierProvider).completeFirstLaunch();
  GoRouter.of(context).go(RouteNames.onboarding);
}

/// The distance widget's tap (widget spec §6.5): Planning → Map, once the
/// router has settled, for a signed-in, paired person only.
Future<void> _openPlanningWhenReady(PlanningHomeTab tab) async {
  try {
    final context = await waitForRouterSettled();
    if (context == null || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await openPlanningFromLink(
      GoRouter.of(context),
      tab,
      signedIn: () => Supabase.instance.client.auth.currentUser != null,
      // Fresh, not cached: after a sign-out the cached id is the last account's.
      relationshipId:
          () => container.refresh(planning.currentRelationshipIdProvider.future),
      mapEnabled: () => container.read(coupleMapEnabledProvider.future),
    );
  } catch (error) {
    // Quiet, like the auth callback: a link must never crash the app.
    debugPrint('[deep-link] planning link failed: ${error.runtimeType}');
  }
}

Future<void> _handleAuthCallback(Uri uri) async {
  try {
    await Supabase.instance.client.auth
        .getSessionFromUrl(uri)
        .timeout(const Duration(seconds: 30));
    debugPrint('[deep-link] auth session established.');
  } catch (error) {
    debugPrint('[deep-link] auth callback failed: ${error.runtimeType}');
  }
}

bool _isAuthCallback(Uri uri) {
  return uri.scheme == 'attune' &&
      uri.host == 'auth' &&
      uri.path == '/callback';
}

const _inviteLinkHost = 'invite.attune.barsopus.com';

String? _extractInviteCode(Uri uri) {
  // Legacy/companion form: attune://invite?code=<code>. Still handled since
  // anything already holding this raw scheme link (e.g. a prior share) must
  // keep working; new links minted by RelationshipInvite.deepLink use the
  // https path form below instead — see relationship_invite_service.dart.
  if (uri.scheme == 'attune' && uri.host == 'invite') {
    final code = uri.queryParameters['code']?.trim();
    return code == null || code.isEmpty ? null : code;
  }

  // Universal/App Link form: https://invite.attune.barsopus.com/i/<code>.
  if (uri.scheme == 'https' &&
      uri.host == _inviteLinkHost &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'i') {
    final code = uri.pathSegments[1].trim();
    return code.isEmpty ? null : code;
  }

  return null;
}

String _redactUri(Uri uri) {
  // Invite codes live in the query string for the attune:// form but in the
  // path itself for the https://invite.attune.barsopus.com/i/<code> form —
  // redact the path there too, not just the query, so codes never hit logs.
  final isInviteLinkHost = uri.host == _inviteLinkHost;
  final path = isInviteLinkHost ? '/[redacted]' : uri.path;
  final base = '${uri.scheme}://${uri.host}$path';
  return uri.hasQuery ? '$base?[redacted]' : base;
}
