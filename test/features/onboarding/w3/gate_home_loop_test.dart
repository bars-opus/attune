// Spec 1 W3a (batch-2 review Info #6, review focus 1): with flow_paths_v2
// on, HomeScreen's latch and the v2 gate agree, so an account is never
// bounced between /home and /onboarding: it goes to /onboarding once, stays
// on what it lacks, and goes home once that is done.
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/user_timezone_reporter.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/home/home_screen.dart';
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

const _uid = 'u-loop';

class _App {
  _App(this.router, this.gateway, this.visits, this.prefs, this.invites);
  final GoRouter router;
  final FakeHomeStateGateway gateway;
  final SharedPreferences prefs;
  final FakeInvites invites;

  /// Every location the router moved to, in order (repeats collapsed).
  final List<String> visits;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

Future<_App> _pumpApp(
  WidgetTester tester, {
  required Map<String, dynamic> server,
  Map<String, Object> prefsValues = const {},
  FakeInvites? invites,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefsValues);
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final gateway = FakeHomeStateGateway(state: server);
  final service = HomeStateService(gateway);
  final auth = FakeHomeAuth(testUser(_uid));
  final fakeInvites = invites ?? FakeInvites();
  addTearDown(auth.changes.close);
  final router = GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder:
            (_, state) => HomeScreen(
              tabRequest:
                  state.uri.queryParameters.containsKey('tab')
                      ? state.uri.query
                      : null,
            ),
      ),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingEntry()),
      GoRoute(
        path: '/signup',
        builder: (_, s) => Scaffold(body: Text('SIGNUP ${s.uri.query}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final visits = <String>[];
  void record() {
    final at = router.routerDelegate.currentConfiguration.uri.toString();
    if (visits.isEmpty || visits.last != at) visits.add(at);
  }

  router.routerDelegate.addListener(record);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeAuthProvider.overrideWithValue(auth),
        homeStateServiceProvider.overrideWithValue(service),
        flowPathsV2Provider.overrideWithValue(true),
        signInFlowV2Provider.overrideWithValue(true),
        homeOpinionsTabProvider.overrideWithValue(const Text('OPINIONS')),
        homeTabTwoBuilderProvider.overrideWithValue(
          (tab, home, _) => TabTwoProbe(tab: tab, home: home),
        ),
        userTimezoneReporterProvider.overrideWithValue(
          UserTimezoneReporter(
            deviceTimezone: () async => '',
            send: (_) async {},
          ),
        ),
        onboardingSyncServiceProvider.overrideWithValue(
          OnboardingSyncService(homeStateService: service),
        ),
        invitePartnerServiceProvider.overrideWithValue(fakeInvites),
        catchUpSignOutProvider.overrideWithValue(() async {}),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(),
        ),
        routingNotifierProvider.overrideWith(
          (ref) => RoutingNotifier(flowV2: true),
        ),
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
  record();
  return _App(router, gateway, visits, prefs, fakeInvites);
}

/// Long enough for several bounces, were there any: each takes a frame
/// plus waitForRouterSettled's 100 ms poll.
Future<void> _run(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

const _legacyComplete = {'attune.onboarding.user.$_uid.completed': true};

void main() {
  testWidgets(
    'legacy account, needs [birth_date]: home, /onboarding once, then home '
    'once it is given (review focus 1)',
    (tester) async {
      final app = await _pumpApp(
        tester,
        server: homeJson(needs: ['birth_date']),
        prefsValues: _legacyComplete,
      );
      // The first frame is the shell (the legacy flag stands in, P-6): no
      // flash of /onboarding before the server has answered.
      expect(app.location, '/home');
      expect(find.textContaining('TAB2'), findsOneWidget);

      await _run(tester);
      expect(app.visits, ['/home', '/onboarding']);
      expect(find.text('Add your date of birth'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Day of birth'), '8');
      await tester.enterText(find.bySemanticsLabel('Month of birth'), '11');
      await tester.enterText(find.bySemanticsLabel('Year of birth'), '1991');
      await tester.pump(const Duration(milliseconds: 300));
      app.gateway.state = homeJson();
      await tester.tap(find.text('Continue'));
      await _run(tester);
      expect(app.visits, ['/home', '/onboarding', '/home']);
      expect(find.textContaining('TAB2'), findsOneWidget);
    },
  );

  for (final (name, server, screen) in [
    (
      'needs [consent]',
      homeJson(needs: ['consent']),
      "We've updated our terms",
    ),
    ('a hold', homeJson(hold: true), 'We need to check your account'),
    (
      'an unknown need',
      homeJson(needs: ['from_a_later_wave']),
      'Update Attune to continue',
    ),
    (
      'needs [path]',
      homeJson(path: null, needs: ['path']),
      'What brings you to Attune?',
    ),
  ]) {
    testWidgets('$name: /onboarding once, and it stays there', (tester) async {
      final app = await _pumpApp(
        tester,
        server: server,
        prefsValues: _legacyComplete,
      );
      await _run(tester);
      await _run(tester);
      expect(app.visits, ['/home', '/onboarding']);
      expect(find.text(screen), findsOneWidget);
    });
  }

  testWidgets('M-3, the next launch: straight to A5c, no shell first', (
    tester,
  ) async {
    var app = await _pumpApp(
      tester,
      server: homeJson(needs: ['consent']),
      prefsValues: _legacyComplete,
    );
    await _run(tester);
    expect(find.text("We've updated our terms"), findsOneWidget);
    // Killed at A5c; the phone keeps the answer's needs for the next launch.
    final kept = {
      for (final key in app.prefs.getKeys()) key: app.prefs.get(key)!,
    };
    app = await _pumpApp(
      tester,
      server: homeJson(needs: ['consent']),
      prefsValues: kept,
    );
    expect(find.textContaining('TAB2'), findsNothing);
    await _run(tester);
    expect(app.visits, ['/home', '/onboarding']);
    expect(find.text("We've updated our terms"), findsOneWidget);
  });

  testWidgets('no account: /onboarding, then sign-up, never home (M-5)', (
    tester,
  ) async {
    final app = await _pumpApp(
      tester,
      server: homeJson(
        hasAccount: false,
        path: null,
        needs: ['consent', 'birth_date', 'name', 'path'],
      ),
      prefsValues: _legacyComplete,
    );
    await _run(tester);
    await _run(tester);
    expect(app.visits, ['/home', '/onboarding', '/signup?entry=returning']);
  });

  testWidgets('HomeScreen never accepts a stored invite before the name '
      '(D9, §5.2)', (tester) async {
    final app = await _pumpApp(
      tester,
      server: homeJson(path: null, needs: ['name', 'path']),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
    );
    await _run(tester);
    expect(app.visits, ['/home', '/onboarding']);
    expect(app.invites.accepted, isEmpty, reason: 'not before the name');
    expect(find.text('What should we call you?'), findsOneWidget);

    app.gateway.state = homeJson(path: null, needs: ['path']);
    app.gateway.onSetPath =
        (_) =>
            app.gateway.state = homeJson(path: 'relationship', link: 'linked');
    await tester.enterText(find.byType(TextField), 'Akosua');
    await tester.tap(find.text('Continue'));
    await _run(tester);
    expect(app.invites.accepted, ['K7P2QM']);
  });

  testWidgets('a complete account: HomeScreen still accepts a stored invite', (
    tester,
  ) async {
    final app = await _pumpApp(
      tester,
      server: homeJson(),
      prefsValues: {
        ..._legacyComplete,
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
    );
    await _run(tester);
    expect(app.visits, ['/home']);
    expect(app.invites.accepted, ['K7P2QM']);
  });

  testWidgets('a complete account stays home', (tester) async {
    final app = await _pumpApp(
      tester,
      server: homeJson(),
      prefsValues: _legacyComplete,
    );
    await _run(tester);
    expect(app.visits, ['/home']);
  });

  for (final pathsV2 in [false, true]) {
    testWidgets('/onboarding with flow_paths_v2 ${pathsV2 ? 'on' : 'off'}: '
        '${pathsV2 ? 'the v2 gate' : "today's gate"}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        navigatorKey: appNavigatorKey,
        initialLocation: '/onboarding',
        routes: [
          GoRoute(
            path: '/onboarding',
            builder: (_, __) => const OnboardingEntry(),
          ),
          GoRoute(
            path: '/login',
            builder: (_, __) => const Scaffold(body: Text('LOGIN')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            homeAuthProvider.overrideWithValue(FakeHomeAuth(null)),
            flowPathsV2Provider.overrideWithValue(pathsV2),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(OnboardingGate), findsNWidgets(pathsV2 ? 0 : 1));
      expect(find.byType(OnboardingGateV2), findsNWidgets(pathsV2 ? 1 : 0));
      // Signed out, both send the person to sign-in.
      await _run(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
    });
  }
}
