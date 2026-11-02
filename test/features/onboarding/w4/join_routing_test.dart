// Spec 1 W4b (D9, §5.5, §7.4 "Accept before RI-3 in OnboardingGate"):
// under flow_couples_v2 no screen accepts a stored invite by itself: the
// v2 gate and HomeScreen both open RI-3 (/join-invite) instead. With the
// flag off, today's accept after the name stays (spec 2.5).
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
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
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-route';
const _slot = 'attune.onboarding.user.$_uid.pending_invite';

String _stored() =>
    '{"code":"K7P2QM","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}';

Future<(GoRouter, FakeInvites)> _pumpGate(
  WidgetTester tester, {
  required Map<String, dynamic> server,
  required bool couplesV2,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({_slot: _stored()});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = HomeStateService(FakeHomeStateGateway(state: server));
  final invites = FakeInvites();
  final auth = FakeHomeAuth(testUser(_uid));
  addTearDown(auth.changes.close);
  final router = GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingGateV2(),
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
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(openCountries: const ['GB', 'GH']),
        ),
        routingNotifierProvider.overrideWith(
          (ref) => RoutingNotifier(flowV2: true),
        ),
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
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  return (router, invites);
}

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('gate, couples v2, A6 owed: RI-3, nothing accepted (D9)', (
    tester,
  ) async {
    final (router, invites) = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
      couplesV2: true,
    );
    expect(_at(router), '/join-invite');
    expect(invites.accepted, isEmpty);
  });

  testWidgets('gate, couples v2, nothing owed: RI-3, not home', (tester) async {
    final (router, invites) = await _pumpGate(
      tester,
      server: homeJson(path: 'just_me'),
      couplesV2: true,
    );
    expect(_at(router), '/join-invite');
    expect(invites.accepted, isEmpty);
  });

  testWidgets('gate, flag off: today\'s accept after the name (spec 2.5)', (
    tester,
  ) async {
    final (_, invites) = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
      couplesV2: false,
    );
    expect(invites.accepted, ['K7P2QM']);
  });

  testWidgets('HomeScreen, couples v2: opens RI-3, never accepts (D9)', (
    tester,
  ) async {
    final invites = FakeInvites();
    await pumpHome(
      tester,
      userId: _uid,
      prefsValues: {
        _slot: _stored(),
        'attune.onboarding.user.$_uid.completed': true,
      },
      server: homeJson(path: 'just_me'),
      overrides: [
        invitePartnerServiceProvider.overrideWithValue(invites),
        flowCouplesV2Provider.overrideWithValue(true),
      ],
      extraRoutes: [
        GoRoute(
          path: '/join-invite',
          builder: (_, __) => const Scaffold(body: Text('RI-3')),
        ),
      ],
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(invites.accepted, isEmpty);
    expect(find.text('RI-3'), findsOneWidget);
  });

  testWidgets('HomeScreen, flag off: today\'s accept stays', (tester) async {
    final invites = FakeInvites();
    await pumpHome(
      tester,
      userId: _uid,
      prefsValues: {
        _slot: _stored(),
        'attune.onboarding.user.$_uid.completed': true,
      },
      server: homeJson(path: 'just_me'),
      overrides: [
        invitePartnerServiceProvider.overrideWithValue(invites),
        flowCouplesV2Provider.overrideWithValue(false),
      ],
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(invites.accepted, ['K7P2QM']);
  });
}
