// Spec 1 W4b carried items on the gate (batch 5): under flow_couples_v2 a
// code typed in the gate and R1's "My partner already invited me" open
// RI-3 (D9), never an accept; RI-3's hold goes to the gate's H1 path
// (held), which shows H1 and blocks the phone even when the read fails
// (ruling N-2, batch-3 review #4); /join-invite is for a signed-in account.
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/fake_share_actions.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-route-carried';

class _Gate {
  _Gate(this.router, this.gateway, this.prefs, this.invites, this.routing);
  final GoRouter router;
  final FakeHomeStateGateway gateway;
  final SharedPreferences prefs;
  final FakeInvites invites;
  final RoutingNotifier routing;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  OnboardingStore get store => OnboardingStore(prefs, scope: 'user.$_uid');
}

Future<_Gate> _pumpGate(
  WidgetTester tester, {
  required Map<String, dynamic> server,
  bool held = false,
  Object? failAlways,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final gateway = FakeHomeStateGateway(state: server)..failAlways = failAlways;
  final service = HomeStateService(gateway);
  final invites = FakeInvites();
  final auth = FakeHomeAuth(testUser(_uid));
  addTearDown(auth.changes.close);
  final routing = RoutingNotifier(flowV2: true);
  final router = GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => OnboardingGateV2(held: held),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: '/join-invite',
        builder: (_, __) => const Scaffold(body: Text('RI-3')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeAuthProvider.overrideWithValue(auth),
        homeStateServiceProvider.overrideWithValue(service),
        onboardingSyncServiceProvider.overrideWithValue(
          OnboardingSyncService(homeStateService: service),
        ),
        invitePartnerServiceProvider.overrideWithValue(invites),
        inviteShareActionsProvider.overrideWithValue(
          FakeShareActions(whatsApp: true),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(openCountries: const ['GB', 'GH']),
        ),
        routingNotifierProvider.overrideWith((ref) => routing),
        flowCouplesV2Provider.overrideWithValue(true),
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
  await _settle(tester);
  return _Gate(router, gateway, prefs, invites, routing);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets('couples v2: a code typed in the gate opens RI-3, no accept', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
    );
    await tester.ensureVisible(find.text('My partner already invited me'));
    await tester.tap(find.text('My partner already invited me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'k7p 2qm');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(g.location, '/join-invite');
    expect(g.invites.accepted, isEmpty);
    expect(g.store.pendingInviteCode, 'K7P2QM');
  });

  testWidgets('couples v2: R1\'s "My partner already invited me" opens RI-3', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
    );
    g.gateway.onSetPath =
        (p) => g.gateway.state = homeJson(path: 'relationship');
    await tester.tap(find.text('In a relationship'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    final already = find.text('My partner already invited me');
    await tester.ensureVisible(already);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(already);
    await _settle(tester);
    expect(g.location, '/join-invite');
    expect(g.invites.accepted, isEmpty);
  });

  testWidgets('held (from RI-3), the read fails: H1 and the device block', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: 'just_me'),
      held: true,
      failAlways: Exception('offline'),
    );
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(g.routing.underAgeBlocked, isTrue);
    expect(g.location, '/onboarding');
  });

  testWidgets('held (from RI-3), the server holds: H1 and the device block', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: 'just_me', hold: true),
      held: true,
    );
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(g.routing.underAgeBlocked, isTrue);
  });

  testWidgets('held, but the read says no hold: the server decides', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: 'just_me'),
      held: true,
    );
    expect(g.location, '/home');
    expect(g.routing.underAgeBlocked, isFalse);
  });
}
