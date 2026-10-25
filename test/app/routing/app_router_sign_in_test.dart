// Spec 1 W2a (§5.4): createAppRouter wires appRedirect and the five v2
// sign-in routes; main.dart's boot values and invite link (sign_in_boot.dart)
// land where the spec says. The rule table itself is sign_in_redirect_test.
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_boot.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_account_gateway.dart';
import '../../helpers/fake_sign_up.dart';
import '../../helpers/flow_harness.dart';

Future<(GoRouter, SharedPreferences)> _pumpAppRouter(
  WidgetTester tester,
  RoutingNotifier notifier, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = createAppRouter(notifier);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => notifier),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(),
        ),
        ...overrides,
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
  await tester.pump(const Duration(milliseconds: 500));
  return (router, prefs);
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// Today's rule (HEAD before Spec 1), written out.
String? _today(RoutingNotifier r, String location) {
  if (location == '/_invisible') {
    return r.isFirstLaunch ? RouteNames.intro : RouteNames.home;
  }
  if (r.isFirstLaunch && location != RouteNames.intro) return RouteNames.intro;
  return null;
}

/// Every path the app router registers: a child's path joined to its
/// parent's, each `:param` filled in, as `state.matchedLocation` reads.
List<String> _registeredPaths(List<RouteBase> routes, [String parent = '']) => [
  for (final route in routes)
    if (route is GoRoute) ...[
      _join(parent, route.path),
      ..._registeredPaths(route.routes, _join(parent, route.path)),
    ] else
      ..._registeredPaths(route.routes, parent),
];

String _join(String parent, String path) {
  final joined =
      path.startsWith('/')
          ? path
          : parent.endsWith('/')
          ? '$parent$path'
          : '$parent/$path';
  return joined.replaceAll(RegExp(r':\w+'), 'x');
}

/// The 122 paths the router registered before Spec 1 W2 (HEAD 360db8d1),
/// frozen: none of them may ever become a v2-only route.
const _todayPaths = <String>[
  '/_invisible',
  '/intro',
  '/home',
  '/login',
  '/onboarding',
  '/profile',
  '/anonymousProfile',
  '/commentThread',
  '/editOpinion',
  '/quoteCompose',
  '/opinionEngagement',
  '/tagBrowse',
  '/healingJourney',
  '/reflectionJournal',
  '/journalEntry',
  '/pulse',
  '/timeline',
  '/together',
  '/planning',
  '/planning/entry',
  '/opinionLoader',
  '/couples-calendar/add',
  '/couples-calendar/family',
  '/chatInsights',
  '/chatImport',
  '/weeklyCheckin',
  '/checkinComplete',
  '/logMomentType',
  '/quizEntry',
  '/attachmentQuiz',
  '/attachmentQuizLoading',
  '/attachmentQuizResult',
  '/conflictStyleQuiz',
  '/conflictStyleLoading',
  '/conflictStyleResult',
  '/loveLanguageQuiz',
  '/loveLanguageResult',
  '/communicationStyleQuiz',
  '/communicationStyleLoading',
  '/communicationStyleResult',
  '/partnerQuizResult',
  '/healingStage',
  '/datingConsent',
  '/datingProfile',
  '/datingMatches',
  '/datingGuidedDate',
  '/datingPhotos',
  '/datingVerification',
  '/logMomentDetails',
  '/thirtySixChapterInvitation',
  '/thirtySixChapterIntroduction',
  '/thirtySixQuestion',
  '/thirtySixChapterCompletion',
  '/thirtySixWaiting',
  '/thirtySixReveal',
  '/thirtySixJourneyCompletion',
  '/thirtySixChapterHistory',
  '/truthOrDareGame',
  '/truthOrDareToneSelector',
  '/truthOrDareSessionRouter',
  '/customTruthOrDareList',
  '/customTruthOrDareCreate',
  '/truthOrDareHistory',
  '/truthReveal',
  '/dareReveal',
  '/thirtySixQuestions',
  '/thirtySixJourneyOverview',
  '/communityFeed',
  '/thisOrThatGamesHub',
  '/thisOrThatToneSelector',
  '/thisOrThatSessionRouter',
  '/mirrorGame',
  '/slidingScaleGame',
  '/scenarioGame',
  '/loveMap',
  '/customQuestionList',
  '/customQuestionCreate',
  '/thisOrThatSessionHistory',
  '/thisOrThatSessionDetail',
  '/thisOrThatCustomList',
  '/thisOrThatCustomCreate',
  '/neutralScreen',
  '/notificationInbox',
  '/chatScreen',
  '/chat-channel',
  '/previous-relationships',
  '/starred-messages',
  '/chat-media',
  '/chat-message-search',
  '/image-caption',
  '/video-trim',
  '/ephemeral-camera',
  '/streak-camera',
  '/image-viewer',
  '/video-viewer',
  '/ephemeral-video-viewer',
  '/settings',
  '/language',
  '/theme',
  '/licenses',
  '/safety-resources',
  '/settings/safety-pin',
  '/settings/signed-in-devices',
  '/settings/download-my-data',
  '/support/outside-perspective',
  '/settings/quiet',
  '/settings/hidden-periods',
  '/appreciation-jar',
  '/allLegalDocumentation',
  '/appInfoScreen',
  '/blockedAccountsScreen',
  '/mutedAuthorsScreen',
  '/dating-mode',
  '/games/paint-ball/lobby/x',
  '/games/paint-ball/battle/x',
  '/games/paint-ball/history/x',
  '/games/paint-ball/knockout/x',
  '/games/snakes/x',
  '/games/constellation/prototype',
  '/games/dots-and-boxes/prototype',
  '/games/word-hunt/x',
  '/ask2/x',
];

void main() {
  test('the five v2 sign-in routes are registered', () {
    final notifier = RoutingNotifier();
    final router = createAppRouter(notifier);
    addTearDown(() {
      router.dispose();
      notifier.dispose();
    });
    for (final location in [
      RouteNames.welcome,
      RouteNames.signUp,
      RouteNames.guestAge,
      RouteNames.invite,
      RouteNames.ageStop,
    ]) {
      final match = router.configuration.findMatch(location);
      expect(match.error, isNull, reason: location);
      expect(
        (match.matches.last.route as GoRoute).path,
        location,
        reason: location,
      );
    }
  });

  group('flag off: every route the router registers is today\'s (M-7)', () {
    late List<String> registered;

    setUp(() {
      final notifier = RoutingNotifier();
      final router = createAppRouter(notifier);
      registered = _registeredPaths(router.configuration.routes);
      router.dispose();
      notifier.dispose();
    });

    test('no route that exists today is v2-only', () {
      expect(_todayPaths.toSet().intersection(flowV2OnlyRoutes), isEmpty);
      expect(registered.toSet().containsAll(flowV2OnlyRoutes), isTrue);
      expect(registered, containsAll(_todayPaths));
    });

    test('each one redirects exactly as today, first launch or not, '
        'signed in or not', () {
      final checked = registered.where((p) => !flowV2OnlyRoutes.contains(p));
      expect(checked.length, greaterThanOrEqualTo(_todayPaths.length));
      for (final firstLaunch in [true, false]) {
        for (final signedIn in [true, false]) {
          final r = RoutingNotifier(
            isFirstLaunch: firstLaunch,
            currentUserId: () => signedIn ? 'user-1' : null,
          );
          for (final location in checked) {
            expect(
              appRedirect(r, location),
              _today(r, location),
              reason:
                  '$location (first launch $firstLaunch, '
                  'signed in $signedIn)',
            );
          }
        }
      }
    });
  });

  group(
    'boot values (I-2: main.dart reads them through bootRoutingNotifier)',
    () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
      });

      test(
        'a fresh install: first launch, the build default, no gate, no block',
        () async {
          final r = bootRoutingNotifier(await SharedPreferences.getInstance());
          expect(r.isFirstLaunch, isTrue);
          expect(r.flowV2, Environment.flowV2Default);
          expect(r.guestAgeOk, isFalse);
          expect(r.underAgeBlocked, isFalse);
        },
      );

      test(
        'reads the cached flag, the passed gate and a block in force',
        () async {
          final prefs = await SharedPreferences.getInstance();
          await PreferencesService(prefs).setFirstLaunchCompleted();
          await PublicAppConfigCache(prefs).write(
            PublicAppConfig.fromJson({
              'flags': {'flow_signin_v2': true},
            }),
          );
          await prefs.setBool(AgeGateStore.guestOkKey, true);
          await prefs.setString(
            AgeGateStore.blockUntilKey,
            DateTime.now()
                .toUtc()
                .add(const Duration(days: 3))
                .toIso8601String(),
          );

          final r = bootRoutingNotifier(prefs);
          expect(r.isFirstLaunch, isFalse);
          expect(
            r.flowV2,
            isTrue,
            reason: 'the cached config, not the default',
          );
          expect(r.guestAgeOk, isTrue);
          expect(r.underAgeBlocked, isTrue);

          final later = bootRoutingNotifier(
            prefs,
            now: () => DateTime.now().add(const Duration(days: 4)),
          );
          expect(later.underAgeBlocked, isFalse, reason: 'the block has ended');
        },
      );

      test(
        'a block set after G1: the next launch sends guest /home to G1, then '
        'X1 (ruling N-1)',
        () async {
          final prefs = await SharedPreferences.getInstance();
          await PreferencesService(prefs).setFirstLaunchCompleted();
          await PublicAppConfigCache(prefs).write(
            PublicAppConfig.fromJson({
              'flags': {'flow_signin_v2': true},
            }),
          );
          final store = AgeGateStore(prefs);
          await store.passGuestGate(1990);
          await store.block();

          // Signed out: Supabase isn't initialised in this test.
          final r = bootRoutingNotifier(prefs);
          expect(r.guestAgeOk, isFalse);
          expect(appRedirect(r, RouteNames.home), RouteNames.guestAge);
          expect(appRedirect(r, RouteNames.guestAge), RouteNames.ageStop);
        },
      );
    },
  );

  testWidgets('flag on, first launch: the app router opens Welcome', (
    tester,
  ) async {
    final notifier = RoutingNotifier(
      isFirstLaunch: true,
      flowV2: true,
      currentUserId: () => null,
    );
    final (router, _) = await _pumpAppRouter(tester, notifier);
    expect(_location(router), RouteNames.welcome);
    expect(
      find.text('Love, dating and you, in one calm place.'),
      findsOneWidget,
    );
  });

  testWidgets('cold start: an invite link under v2 opens RI-1 and still '
      'clears first launch (I-2)', (tester) async {
    final notifier = RoutingNotifier(
      isFirstLaunch: true,
      flowV2: true,
      currentUserId: () => null,
    );
    final (router, prefs) = await _pumpAppRouter(tester, notifier);
    expect(PreferencesService(prefs).isFirstLaunch, isTrue);

    // What main.dart's link handler stores for a signed-out phone: the
    // anonymous slot, never an account's.
    await OnboardingStore.storeInviteFromLink(prefs, 'K7P2QM');
    expect(prefs.getKeys().where((k) => k.contains('pending_invite')), [
      'attune.onboarding.anonymous.pending_invite',
    ]);

    await openInviteLanding(appNavigatorKey.currentContext!);
    await tester.pumpAndSettle();
    expect(_location(router), RouteNames.invite);
    expect(find.text("You've been invited to Attune"), findsOneWidget);
    expect(PreferencesService(prefs).isFirstLaunch, isFalse);
    expect(notifier.isFirstLaunch, isFalse);
  });

  for (final (name, flowV2, userId) in [
    ('flag off', false, null),
    ('flag on, signed in', true, 'user-1'),
  ]) {
    testWidgets('an invite link, $name: today\'s /onboarding, first launch '
        'cleared (I-2)', (tester) async {
      final h = await pumpFlowScreen(
        tester,
        () => const Text('start'),
        routing: RoutingNotifier(
          isFirstLaunch: true,
          flowV2: flowV2,
          currentUserId: () => userId,
        ),
      );
      await openInviteLanding(tester.element(find.text('start')));
      await tester.pumpAndSettle();
      expect(h.location, RouteNames.onboarding);
      expect(PreferencesService(h.prefs).isFirstLaunch, isFalse);
      expect(h.routing.isFirstLaunch, isFalse);
    });
  }

  testWidgets('a warm link while RI-2 asks for a code shows RI-1 (M-6)', (
    tester,
  ) async {
    final notifier = RoutingNotifier(
      isFirstLaunch: true,
      flowV2: true,
      currentUserId: () => null,
    );
    final (router, prefs) = await _pumpAppRouter(tester, notifier);
    router.go(RouteNames.invite);
    await tester.pumpAndSettle();
    expect(find.text('Enter your invite code'), findsOneWidget);

    await OnboardingStore.storeInviteFromLink(prefs, 'K7P2QM');
    await openInviteLanding(appNavigatorKey.currentContext!);
    await tester.pumpAndSettle();
    expect(_location(router), RouteNames.invite);
    expect(find.text("You've been invited to Attune"), findsOneWidget);
    expect(find.text('Enter your invite code'), findsNothing);
  });

  testWidgets('W2b: /signup builds SignUpFlow from its entry and back '
      'parameters', (tester) async {
    final notifier = RoutingNotifier(
      flowV2: true,
      guestAgeOk: true,
      currentUserId: () => null,
    );
    final (router, _) = await _pumpAppRouter(
      tester,
      notifier,
      overrides: [
        codeSenderProvider.overrideWithValue(FakeCodeSender()),
        signUpAuthProvider.overrideWithValue(FakeSignUpAuth()),
        accountServiceProvider.overrideWithValue(
          AccountService(FakeAccountGateway()),
        ),
        metricCounterProvider.overrideWithValue(MetricCounter((key) async {})),
        deviceCountryProvider.overrideWith(
          (ref) async => (sim: 'GH', region: null),
        ),
      ],
    );
    router.go('${RouteNames.signUp}?entry=returning&back=%2Fhome');
    await tester.pumpAndSettle();
    final flow = tester.widget<SignUpFlow>(find.byType(SignUpFlow));
    expect(flow.entry, SignUpEntry.returning);
    expect(flow.backTo, RouteNames.home);
    expect(find.text("What's your phone number?"), findsOneWidget);

    // A fresh visit with no entry: a new account, from A1.
    router.go(RouteNames.welcome);
    await tester.pumpAndSettle();
    router.go(RouteNames.signUp);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SignUpFlow>(find.byType(SignUpFlow)).entry,
      SignUpEntry.newAccount,
    );
    expect(find.text('What should we call you?'), findsOneWidget);
  });

  testWidgets('/age-stop?from=server opens X1 refused by the server, at once', (
    tester,
  ) async {
    final notifier = RoutingNotifier(
      isFirstLaunch: true,
      flowV2: true,
      currentUserId: () => null,
    );
    final (router, _) = await _pumpAppRouter(tester, notifier);
    router.go('${RouteNames.ageStop}?from=server');
    // Never animated (§2.2): one frame and the stop is the only screen (an
    // animated page is still offstage on its first frame).
    await tester.pump();
    expect(find.byType(UnderAgeStopScreen), findsOneWidget);
    expect(
      tester.widget<UnderAgeStopScreen>(find.byType(UnderAgeStopScreen)),
      isA<UnderAgeStopScreen>().having(
        (s) => s.serverRefused,
        'serverRefused',
        isTrue,
      ),
    );
    expect(find.textContaining("We couldn't create your account."), findsOne);
    expect(find.text('Love, dating and you, in one calm place.'), findsNothing);
  });

  // Final review M-1 (re-graded Important): the under-18 block closes
  // creating an account, not signing in to one, so on a shared phone an
  // adult isn't locked out of her own account for 30 days.
  group('M-1: a blocked device', () {
    Future<(GoRouter, FakeSignUpAuth)> blockedApp(
      WidgetTester tester, {
      required bool hasAccount,
    }) async {
      final auth = FakeSignUpAuth();
      final notifier = RoutingNotifier(
        flowV2: true,
        underAgeBlocked: true,
        currentUserId: () => auth.userId,
      );
      final (router, prefs) = await _pumpAppRouter(
        tester,
        notifier,
        overrides: [
          codeSenderProvider.overrideWithValue(FakeCodeSender()),
          signUpAuthProvider.overrideWithValue(auth),
          accountServiceProvider.overrideWithValue(
            AccountService(
              FakeAccountGateway(
                homeState: FakeAccountGateway.account(hasAccount: hasAccount),
                name: 'Kofi',
              ),
            ),
          ),
          metricCounterProvider.overrideWithValue(
            MetricCounter((key) async {}),
          ),
          deviceCountryProvider.overrideWith(
            (ref) async => (sim: 'GH', region: null),
          ),
          smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
        ],
      );
      await AgeGateStore(prefs).block();
      await tester.pumpAndSettle();
      expect(_location(router), RouteNames.ageStop);
      // X1's Close, to Welcome.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(_location(router), RouteNames.welcome);
      return (router, auth);
    }

    testWidgets('"Get started" opens X1', (tester) async {
      final (router, _) = await blockedApp(tester, hasAccount: false);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(_location(router), RouteNames.ageStop);
    });

    testWidgets('"I already have an account" reaches A3 and A4, and an '
        'existing account says Welcome back, then home', (tester) async {
      final (router, auth) = await blockedApp(tester, hasAccount: true);
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      expect(_location(router), '${RouteNames.signUp}?entry=returning');
      expect(find.text("What's your phone number?"), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'),
        '244123456',
      );
      await tester.pump();
      await tester.tap(find.text('Text me a code'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Welcome back, Kofi.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(_location(router), RouteNames.home);
      expect(auth.userId, 'u1');
    });
  });
}
