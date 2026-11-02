// Batch-5 review I-1 (D9, D8): while the signed-in flags are unknown (a
// fresh install, no cache) nothing accepts a stored invite: HomeScreen's
// legacy branch waits and OnboardingEntry builds neither gate. Unknown is
// not off. Once the flags arrive: couples v2 opens RI-3; off runs today's
// accept, once. The code is kept meanwhile.
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
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate.dart';
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

Future<void> _settle(WidgetTester tester, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(_PendingFlags, FakeInvites, HomeHarness)> _pumpHome(
  WidgetTester tester, {
  bool signInV2 = true,
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
    server: homeJson(path: 'just_me'),
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

  // Task 6 re-review R-1: with flow_signin_v2 off (today's production) the
  // signed-in flags can't turn anything on, so they are known at once:
  // today's legacy accept runs with no flags answer at all.
  testWidgets('HomeScreen, sign-in v2 off, no flags answer: today\'s accept', (
    tester,
  ) async {
    final (flags, invites, h) = await _pumpHome(tester, signInV2: false);
    expect(flags.answer.isCompleted, isFalse);
    expect(invites.accepted, ['K7P2QM']);
    expect(_code(h.prefs), isNull);
  });

  group('OnboardingEntry', () {
    Future<(_PendingFlags, FakeInvites, RoutingNotifier)> pumpEntry(
      WidgetTester tester, {
      bool signInV2 = true,
      int settleSteps = 10,
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
              FakePublicConfigGateway(),
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

    testWidgets('flags unknown: neither gate, nothing accepted', (
      tester,
    ) async {
      final (_, invites, _) = await pumpEntry(tester);
      expect(find.byType(OnboardingGate), findsNothing);
      expect(find.byType(OnboardingGateV2), findsNothing);
      expect(
        find.bySemanticsLabel('Checking your account\u2026'),
        findsOneWidget,
      );
      expect(invites.accepted, isEmpty);
    });

    testWidgets('sign-in v2 off, no flags answer: today\'s gate at once', (
      tester,
    ) async {
      // The first frame: the legacy gate (its own services, so it is not
      // driven further here; HomeScreen's case above shows the accept).
      final (flags, _, _) = await pumpEntry(
        tester,
        signInV2: false,
        settleSteps: 0,
      );
      expect(flags.answer.isCompleted, isFalse);
      expect(find.byType(OnboardingGate), findsOneWidget);
      expect(find.byType(OnboardingGateV2), findsNothing);
      expect(
        find.bySemanticsLabel('Checking your account\u2026'),
        findsNothing,
      );
      expect(find.text("We couldn't check your account"), findsNothing);
    });

    testWidgets('the flags read fails: the offline step; Try again reads '
        'them, then the v2 gate opens RI-3', (tester) async {
      final (flags, invites, _) = await pumpEntry(tester);
      flags.answer.completeError(Exception('offline'));
      await _settle(tester);
      expect(find.text("We couldn't check your account"), findsOneWidget);
      expect(find.byType(OnboardingGate), findsNothing);
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
