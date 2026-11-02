// Spec 1 W4b (§3.8 RI-3, D9): createAppRouter's /join-invite is for a
// signed-in account only, and RI-3's hold refusal enters the v2 gate's H1
// path (held): H1 and the device block even when the read then fails
// (ruling N-2; batch 5 carried item 2).
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/screens/join_invite_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_invites.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

const _uid = 'u-route-join';

/// The accept is refused with account:hold, and from then on every
/// home-state read fails.
class _HeldInvites extends FakeInvites {
  _HeldInvites(this.gateway)
    : super(
        acceptError: inviteAcceptFailure(
          const FunctionException(
            status: 403,
            details: {'error': 'account:hold', 'code': 'account:hold'},
          ),
        ),
      );

  final FakeHomeStateGateway gateway;

  @override
  Future<InviteAcceptance> acceptInvite(String inviteCode) {
    gateway.failAlways = Exception('offline');
    return super.acceptInvite(inviteCode);
  }
}

Future<(GoRouter, RoutingNotifier, FakeInvites)> _pump(
  WidgetTester tester, {
  required bool signedIn,
  bool couplesV2 = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'attune.onboarding.user.$_uid.pending_invite':
        '{"code":"K7P2QM","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}',
  });
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final gateway = FakeHomeStateGateway(
    state: homeJson(path: null, needs: ['path']),
  );
  final invites = _HeldInvites(gateway);
  final auth = FakeHomeAuth(signedIn ? testUser(_uid) : null);
  addTearDown(auth.changes.close);
  final routing = RoutingNotifier(
    flowV2: true,
    currentUserId: () => signedIn ? _uid : null,
  );
  final router = createAppRouter(routing);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => routing),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(),
        ),
        homeAuthProvider.overrideWithValue(auth),
        homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
        invitePartnerServiceProvider.overrideWithValue(invites),
        signInFlowV2Provider.overrideWithValue(true),
        flowPathsV2Provider.overrideWithValue(true),
        flowCouplesV2Provider.overrideWithValue(couplesV2),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
      ),
    ),
  );
  await tester.pump();
  return (router, routing, invites);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('signed out: never RI-3', (tester) async {
    final (router, _, invites) = await _pump(tester, signedIn: false);
    router.go(RouteNames.joinInvite);
    await _settle(tester);
    expect(_at(router), isNot(RouteNames.joinInvite));
    expect(find.byType(JoinInviteScreen), findsNothing);
    expect(invites.previewed, isEmpty);
  });

  // Final review #6: RI-3 is flow_couples_v2's; with it off a typed or
  // deep /join-invite goes home (today's equivalent), never RI-3.
  testWidgets('couples v2 off: /join-invite goes home, never RI-3', (
    tester,
  ) async {
    final (router, _, invites) = await _pump(
      tester,
      signedIn: true,
      couplesV2: false,
    );
    router.go(RouteNames.joinInvite);
    await _settle(tester);
    // Home, which sends this account (no path yet) on to today's gate.
    expect(_at(router), isNot(startsWith(RouteNames.joinInvite)));
    expect(find.byType(JoinInviteScreen), findsNothing);
    expect(invites.previewed, isEmpty);
    // (The account's own stored code then meets today's flag-off gate,
    // spec 2.5: unchanged by this route.)
  });

  testWidgets('RI-3\'s hold refusal: the gate\'s H1 path blocks the phone', (
    tester,
  ) async {
    final (router, routing, invites) = await _pump(tester, signedIn: true);
    router.go(RouteNames.joinInvite);
    await _settle(tester);
    expect(find.text('Join Yaw?'), findsOneWidget);
    await tester.tap(find.text('Join Yaw'));
    await _settle(tester);
    expect(invites.accepted, ['K7P2QM']);
    expect(_at(router), RouteNames.onboarding);
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(routing.underAgeBlocked, isTrue);
  });
}
