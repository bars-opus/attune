// Batch-5 review I-1 (D9, D8): while the signed-in flags are unknown (a
// fresh install, no cache) nothing accepts a stored invite: HomeScreen
// waits and OnboardingEntry builds no gate. Unknown is not off. Once the
// flags arrive: couples v2 opens RI-3; off runs the accept, once, for a
// complete account only. The code is kept meanwhile. Entry gates fix 4
// (2026-11-27): the v2 gate is the only one, and with flow_signin_v2 off
// the flags are known only once the public config has been read.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
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

const _uid = 'u-flags-unknown';
const _slot = 'attune.onboarding.user.$_uid.pending_invite';

String _stored() =>
    '{"code":"K7P2QM","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}';

/// The signed-in flags, answered when the test says (or failing).
class _PendingFlags implements FlowFlagsGateway {
  Completer<SignedInFlowFlags> answer = Completer();
  int fetches = 0;

  @override
  Future<SignedInFlowFlags> fetch() {
    fetches++;
    return answer.future;
  }
}

/// The public config, answered when the test says.
class _PendingConfig implements PublicAppConfigGateway {
  _PendingConfig(this.answer);

  final Completer<Map<String, dynamic>> answer;

  @override
  Future<Map<String, dynamic>> fetch() => answer.future;
}

Future<void> _settle(WidgetTester tester, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(_PendingFlags, FakeInvites, HomeHarness)> _pumpHome(
  WidgetTester tester, {
  bool signInV2 = true,
  List<String> needs = const [],
}) async {
  final flags = _PendingFlags();
  final invites = FakeInvites();
  final h = await pumpHome(
    tester,
    userId: _uid,
    realFlags: true,
    signInV2: signInV2,
    prefsValues: {
      _slot: _stored(),
      'attune.onboarding.user.$_uid.completed': true,
    },
    server: homeJson(path: 'just_me', needs: needs),
    overrides: [
      flowFlagsGatewayProvider.overrideWithValue(flags),
      invitePartnerServiceProvider.overrideWithValue(invites),
    ],
    extraRoutes: [
      GoRoute(
        path: '/join-invite',
        builder: (_, __) => const Scaffold(body: Text('RI-3')),
      ),
    ],
  );
  await _settle(tester);
  return (flags, invites, h);
}

String? _code(SharedPreferences prefs) =>
    OnboardingStore(prefs, scope: 'user.$_uid').pendingInviteCode;

void main() {
  testWidgets('HomeScreen, flags unknown: no accept; couples v2: RI-3', (
    tester,
  ) async {
    final (flags, invites, h) = await _pumpHome(tester);
    expect(invites.accepted, isEmpty);
    expect(_code(h.prefs), 'K7P2QM');
    flags.answer.complete(
      const SignedInFlowFlags(pathsV2: true, couplesV2: true),
    );
    await _settle(tester);
    expect(invites.accepted, isEmpty);
    expect(find.text('RI-3'), findsOneWidget);
  });

  testWidgets('HomeScreen, flags arrive off: today\'s accept, exactly once', (
    tester,
  ) async {
    final (flags, invites, h) = await _pumpHome(tester);
    expect(invites.accepted, isEmpty);
    flags.answer.complete(
      const SignedInFlowFlags(pathsV2: false, couplesV2: false),
    );
    await _settle(tester);
    expect(invites.accepted, ['K7P2QM']);
    expect(_code(h.prefs), isNull);
    // A later reconcile (resume) has nothing left to accept.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(invites.accepted, ['K7P2QM']);
  });

  // Task 6 re-review R-1: with flow_signin_v2 off the signed-in flags can't
  // turn anything on, so once the public config is read they are known:
  // the accept (for this complete account) runs with no flags answer.
  testWidgets('HomeScreen, sign-in v2 off, no flags answer: the accept', (
    tester,
  ) async {
    final (flags, invites, h) = await _pumpHome(tester, signInV2: false);
    expect(flags.answer.isCompleted, isFalse);
    expect(invites.accepted, ['K7P2QM']);
    expect(_code(h.prefs), isNull);
  });

  // Entry gates fix 4 (audit: home_screen.dart:428): with the flags off
  // the legacy branch accepted a stored code before consent and the date
  // of birth. Now only a complete account's code is taken; the gate takes
  // anyone else's, after the name.
  for (final need in ['consent', 'birth_date', 'name']) {
    testWidgets('HomeScreen, flags off, the account owes $need: no accept, '
        'the code is kept', (tester) async {
      final (_, invites, h) = await _pumpHome(
        tester,
        signInV2: false,
        needs: [need],
      );
      expect(invites.accepted, isEmpty);
      expect(_code(h.prefs), 'K7P2QM');
      expect(h.onboardingVisits, ['onboarding']);
    });
  }

  group('OnboardingEntry', () {
    Future<(_PendingFlags, FakeInvites, RoutingNotifier)> pumpEntry(
      WidgetTester tester, {
      bool signInV2 = true,
      int settleSteps = 10,
      PublicAppConfigGateway? config,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({_slot: _stored()});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = HomeStateService(
        FakeHomeStateGateway(state: homeJson(path: 'just_me')),
      );
      final flags = _PendingFlags();
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
            builder: (_, __) => const OnboardingEntry(),
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
              config ?? FakePublicConfigGateway(),
            ),
            routingNotifierProvider.overrideWith((ref) => routing),
            signInFlowV2Provider.overrideWithValue(signInV2),
            flowFlagsGatewayProvider.overrideWithValue(flags),
            catchUpSignOutProvider.overrideWithValue(() async {}),
          ],
          child: ScreenUtilConfig.builder(
            builder:
                (_) => MaterialApp.router(
                  theme: AppTheme.lightTheme,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  routerConfig: router,
                ),
          ),
        ),
      );
      await _settle(tester, steps: settleSteps);
      return (flags, invites, routing);
    }

    testWidgets('flags unknown: no gate, nothing accepted', (
      tester,
    ) async {
      final (_, invites, _) = await pumpEntry(tester);
      expect(find.byType(OnboardingGateV2), findsNothing);
      expect(
        find.bySemanticsLabel('Checking your account\u2026'),
        findsOneWidget,
      );
      expect(invites.accepted, isEmpty);
    });

    testWidgets('sign-in v2 off, no flags answer: the v2 gate once the '
        'public config is read (entry gates fix 4)', (tester) async {
      final (flags, _, _) = await pumpEntry(
        tester,
        signInV2: false,
        settleSteps: 1,
      );
      expect(flags.answer.isCompleted, isFalse);
      expect(find.byType(OnboardingGateV2), findsOneWidget);
      expect(find.text("We couldn't check your account"), findsNothing);
      // The complete account then goes home (the gate's own timers run out).
      await _settle(tester, steps: 40);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('sign-in v2 off but the public config unread (a prod build '
        'before its first read): no gate yet, nothing accepted (entry gates '
        'fix 4)', (tester) async {
      final config = Completer<Map<String, dynamic>>();
      final (_, invites, _) = await pumpEntry(
        tester,
        signInV2: false,
        config: _PendingConfig(config),
      );
      expect(find.byType(OnboardingGateV2), findsNothing);
      expect(
        find.bySemanticsLabel('Checking your account\u2026'),
        findsOneWidget,
      );
      expect(invites.accepted, isEmpty);
      config.complete({'flags': {'flow_signin_v2': false}});
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(OnboardingGateV2), findsOneWidget);
      await _settle(tester, steps: 40);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('the flags read fails: the offline step; Try again reads '
        'them, then the v2 gate opens RI-3', (tester) async {
      final (flags, invites, _) = await pumpEntry(tester);
      flags.answer.completeError(Exception('offline'));
      await _settle(tester);
      expect(find.text("We couldn't check your account"), findsOneWidget);
      expect(find.byType(OnboardingGateV2), findsNothing);
      expect(invites.accepted, isEmpty);
      flags.answer =
          Completer()
            ..complete(const SignedInFlowFlags(pathsV2: true, couplesV2: true));
      await tester.tap(find.text('Try again'));
      await _settle(tester, steps: 16);
      expect(flags.fetches, 2);
      expect(find.text('RI-3'), findsOneWidget);
      expect(invites.accepted, isEmpty);
    });
  });
}
