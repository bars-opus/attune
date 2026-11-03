// Spec 1 W6a carried items (batch 5): the sign-in H1 in the gate's order
// (block, then the draft, then any session; the keystore bounded to 1 s),
// a fresh start retried after a lost 200 (400: a new code, never a dead
// end), and H1 kept on screen under the app's real redirect on the
// new-account way (the block it sets must not turn H1 into X1).
import 'dart:async';
import 'dart:convert';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/fresh_start_service.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_coordinator.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../helpers/fake_account_gateway.dart';
import '../../../../helpers/fake_reminder_rpc.dart';
import '../../../../helpers/fake_sign_up.dart';
import '../../../../helpers/flow_harness.dart'
    show FakePublicConfigGateway, FlowHarness, pumpFlowScreen;
import 'sign_up_dormancy_test.dart' show FakeFreshStart;

final _now = DateTime.utc(2026, 11, 3, 12);
const _phone = '+233244123456';
final _nonce = 'cd' * 64;

/// A keystore whose writes never finish (a stuck Android keystore).
class _StuckSecure extends Fake implements FlutterSecureStorage {
  int writes = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #write) {
      writes++;
      return Completer<void>().future;
    }
    return super.noSuchMethod(invocation);
  }
}

class _Rig {
  _Rig(this.prefs, {FlutterSecureStorage? secure}) : _secure = secure;

  final SharedPreferences prefs;
  final FlutterSecureStorage? _secure;
  final sender = FakeCodeSender();
  final auth = FakeSignUpAuth();
  final gateway = FakeAccountGateway(
    homeState: FakeAccountGateway.account(hasAccount: false),
  );
  final fresh = FakeFreshStart();

  SignUpDraftStore get drafts => SignUpDraftStore(prefs, now: () => _now);

  SignUpCoordinator coordinator() => SignUpCoordinator(
    drafts: drafts,
    sender: sender,
    auth: auth,
    accounts: AccountService(gateway),
    ageGate: AgeGateStore(prefs, secure: _secure, now: () => _now),
    onboardingStoreFor: (uid) => OnboardingStore(prefs, scope: 'user.$uid'),
    metrics: MetricCounter((key) async {}),
    now: () => _now,
    freshStart: fresh,
  );

  void refuse(String message) =>
      auth.failVerifyWith = AuthException(message, statusCode: '403');
}

Future<SignUpCoordinator> _atCode(_Rig rig) async {
  final c = rig.coordinator();
  c.start(SignUpEntry.newAccount);
  await c.saveName('Esi');
  expect(await c.saveBirthDate(DateTime.utc(1996, 3, 27)), isTrue);
  expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the coordinator', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('an age hold with a stuck keystore: H1 within about a second, the '
        'block already in prefs (W3 carry C-2)', () async {
      final secure = _StuckSecure();
      final rig = _Rig(prefs, secure: secure);
      final c = await _atCode(rig);
      rig.refuse('account_review:age');
      final watch = Stopwatch()..start();
      final outcome = await c
          .verify('123456')
          .timeout(const Duration(seconds: 4));
      watch.stop();
      expect((outcome as VerifiedHeld).age, isTrue);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 2500)));
      expect(secure.writes, 1);
      expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
      expect(rig.drafts.read(), isNull);
    });

    test('H1 ends a session left on the phone, after the block and the '
        'draft; a failed sign-out still shows H1', () async {
      final rig = _Rig(prefs);
      final c = await _atCode(rig);
      rig.auth
        ..userId = 'u-stale'
        ..failSignOut = true;
      rig.refuse('account_review:age');
      final outcome = await c.verify('123456');
      expect((outcome as VerifiedHeld).age, isTrue);
      expect(rig.auth.signOuts, 1);
      expect(rig.auth.userId, isNull);
      expect(AgeGateStore.readBlocked(prefs, _now), isTrue);
      expect(rig.drafts.read(), isNull);
    });

    test('a safety hold ends a session left on the phone too, and never '
        'blocks it', () async {
      final rig = _Rig(prefs);
      final c = await _atCode(rig);
      rig.auth.userId = 'u-stale';
      rig.refuse('account_review');
      final outcome = await c.verify('123456');
      expect((outcome as VerifiedHeld).age, isFalse);
      expect(rig.auth.signOuts, 1);
      expect(AgeGateStore.readBlocked(prefs, _now), isFalse);
    });

    test('DM1 signs nobody out and keeps the draft', () async {
      final rig = _Rig(prefs);
      final c = await _atCode(rig);
      rig.refuse('account_dormant:$_nonce');
      expect(await c.verify('123456'), isA<VerifiedDormant>());
      expect(rig.auth.signOuts, 0);
      expect(rig.drafts.read()?.phoneE164, _phone);
    });

    test('a fresh start retried after a lost 200 gets 400: A3 on the same '
        'number, and a new code goes on to a new account', () async {
      final rig = _Rig(prefs);
      final c = await _atCode(rig);
      rig.refuse('account_dormant:$_nonce');
      await c.verify('123456');
      // The 200 never arrived (the park ran); the retry finds the nonce
      // spent: 400 fresh_start:invalid.
      rig.fresh.results.addAll([
        FreshStartResult.unavailable,
        FreshStartResult.invalid,
      ]);
      expect(await c.startFresh(), FreshStartOutcome.failed);
      expect(await c.startFresh(), FreshStartOutcome.expired);
      expect(rig.fresh.nonces, [_nonce, _nonce]);
      expect(c.phoneForA3, _phone);

      expect(await c.sendCode(phoneE164: _phone, countryIso: 'GH'), isNull);
      expect(rig.sender.sent.last.$1, _phone);
      rig.auth
        ..failVerifyWith = null
        ..verifiesAs = 'u-new';
      final outcome = await c.verify('123456');
      expect((outcome as VerifiedNew).next, SignUpStepId.consent);
      expect(c.draft.name, 'Esi', reason: 'A1/A2 typed here come back');
    });
  });

  group('under the app redirect', () {
    Future<(GoRouter, RoutingNotifier, SharedPreferences)> pumpApp(
      WidgetTester tester, {
      required List<Override> overrides,
      required String location,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final draft = SignUpDraft.start(
        SignUpEntry.newAccount,
        now: _now,
      ).copyWith(
        name: 'Ama',
        birthDate: DateTime.utc(1990, 1, 1),
        phoneE164: _phone,
        countryIso: 'GH',
        lastSentAt: _now,
        sendCount: 1,
      );
      SharedPreferences.setMockInitialValues({
        SignUpDraftStore.key: const JsonEncoder().convert(draft.toJson()),
      });
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final routing = RoutingNotifier(prefs: prefs, flowV2: true);
      final router = GoRouter(
        initialLocation: location,
        refreshListenable: routing,
        redirect:
            (context, state) => appRedirect(
              routing,
              state.matchedLocation,
              entry: state.uri.queryParameters['entry'],
            ),
        routes: [
          GoRoute(
            path: RouteNames.signUp,
            builder:
                (context, state) => SignUpFlow(
                  entry: SignUpEntry.fromWire(
                    state.uri.queryParameters['entry'],
                  ),
                  backTo: state.uri.queryParameters['back'],
                ),
          ),
          GoRoute(
            path: RouteNames.ageStop,
            builder: (_, __) => const Scaffold(body: Text('at X1')),
          ),
          GoRoute(
            path: RouteNames.welcome,
            builder: (_, __) => const Scaffold(body: Text('at Welcome')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            routingNotifierProvider.overrideWith((ref) => routing),
            metricCounterProvider.overrideWithValue(
              MetricCounter((key) async {}),
            ),
            publicAppConfigGatewayProvider.overrideWithValue(
              FakePublicConfigGateway(),
            ),
            journalReminderRpcProvider.overrideWithValue(
              FakeReminderRpc().call,
            ),
            ...overrides,
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
      await tester.pumpAndSettle();
      return (router, routing, prefs);
    }

    List<Override> overridesFor(_FlowRig rig) => [
      codeSenderProvider.overrideWithValue(rig.sender),
      signUpAuthProvider.overrideWithValue(rig.auth),
      accountServiceProvider.overrideWithValue(AccountService(rig.gateway)),
      signUpClockProvider.overrideWithValue(() => _now),
      deviceCountryProvider.overrideWith(
        (ref) async => (sim: 'GH', region: null),
      ),
      smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
      freshStartGatewayProvider.overrideWithValue(rig.fresh),
    ];

    testWidgets('an age hold on the new-account way: H1 stays (never X1), '
        'and Sign out leaves with this phone blocked', (tester) async {
      final rig = _FlowRig();
      rig.auth.failVerifyWith = const AuthException(
        'account_review:age',
        statusCode: '403',
      );
      final (router, routing, prefs) = await pumpApp(
        tester,
        overrides: overridesFor(rig),
        location: '${RouteNames.signUp}?entry=new&back=%2Fwelcome',
      );
      expect(find.text('Enter the code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('We need to check your account'), findsOneWidget);
      expect(find.text('at X1'), findsNothing);
      expect(routing.underAgeBlocked, isTrue);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '${RouteNames.signUp}?entry=returning&back=%2Fwelcome',
        reason: 'the one /signup a blocked phone keeps open',
      );

      // Anything else that refreshes the router while H1 shows.
      routing.updateLocation('/elsewhere');
      await tester.pumpAndSettle();
      expect(find.text('We need to check your account'), findsOneWidget);
      expect(find.text('at X1'), findsNothing);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('at Welcome'), findsOneWidget);
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
    });

    testWidgets('a safety hold on the new-account way: H1, no block, the '
        'way in unchanged', (tester) async {
      final rig = _FlowRig();
      rig.auth.failVerifyWith = const AuthException(
        'account_review',
        statusCode: '403',
      );
      final (router, routing, _) = await pumpApp(
        tester,
        overrides: overridesFor(rig),
        location: '${RouteNames.signUp}?entry=new',
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('We need to check your account'), findsOneWidget);
      expect(routing.underAgeBlocked, isFalse);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '${RouteNames.signUp}?entry=new',
      );
    });
  });

  group('fix round 1', () {
    var clock = _now;
    setUp(() => clock = _now);
    const blockedUntil = '2099-01-01T00:00:00.000Z';

    SignUpDraft atCode(SignUpEntry entry) =>
        SignUpDraft.start(entry, now: _now).copyWith(
          name: entry == SignUpEntry.newAccount ? 'Ama' : null,
          birthDate:
              entry == SignUpEntry.newAccount ? DateTime.utc(1990, 1, 1) : null,
          phoneE164: _phone,
          countryIso: 'GH',
          lastSentAt: _now,
          sendCount: 1,
        );

    Future<SharedPreferences> pumpAtDormant(
      WidgetTester tester,
      _FlowRig rig, {
      SignUpEntry entry = SignUpEntry.newAccount,
      bool blocked = false,
    }) async {
      rig.auth.failVerifyWith = AuthException(
        'account_dormant:$_nonce',
        statusCode: '403',
      );
      final h = await pumpFlowScreen(
        tester,
        () => SignUpFlow(entry: entry),
        prefsValues: {
          SignUpDraftStore.key: const JsonEncoder().convert(
            atCode(entry).toJson(),
          ),
          if (blocked) AgeGateStore.blockUntilKey: blockedUntil,
        },
        overrides: [
          codeSenderProvider.overrideWithValue(rig.sender),
          signUpAuthProvider.overrideWithValue(rig.auth),
          accountServiceProvider.overrideWithValue(AccountService(rig.gateway)),
          signUpClockProvider.overrideWithValue(() => clock),
          deviceCountryProvider.overrideWith(
            (ref) async => (sim: 'GH', region: null),
          ),
          smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
          freshStartGatewayProvider.overrideWithValue(rig.fresh),
        ],
      );
      _harness = h;
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Attune'), findsOneWidget);
      return h.prefs;
    }

    /// The phone locked (or the app left) for [time], then back.
    Future<void> away(WidgetTester tester, Duration time) async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      clock = clock.add(time);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('I-1: DM2 left in the background for 6 minutes: A1, never a '
        'DM2 with no number', (tester) async {
      final rig = _FlowRig();
      await pumpAtDormant(tester, rig);
      await tester.tap(find.text("I'm new to Attune"));
      await tester.pumpAndSettle();
      expect(find.text('One more code to finish'), findsOneWidget);

      await away(tester, const Duration(minutes: 6));
      expect(find.text('One more code to finish'), findsNothing);
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.textContaining('send a new code to .'), findsNothing);
    });

    testWidgets('I-1: DM2 after a short absence stays, with its number', (
      tester,
    ) async {
      final rig = _FlowRig();
      await pumpAtDormant(tester, rig);
      await tester.tap(find.text("I'm new to Attune"));
      await tester.pumpAndSettle();
      await away(tester, const Duration(minutes: 2));
      expect(
        find.text("We'll send a new code to +233 24 412 3456."),
        findsOneWidget,
      );
    });

    testWidgets('I-2: system back on DM1 leaves for Welcome; the challenge '
        'and the draft are gone, nothing parked', (tester) async {
      final rig = _FlowRig();
      final prefs = await pumpAtDormant(tester, rig);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_harness!.location, RouteNames.welcome);
      expect(rig.fresh.nonces, isEmpty);
      expect(SignUpDraftStore.readFrom(prefs, _now), isNull);
      expect(
        prefs.getKeys().map((k) => '${prefs.get(k)}').join(' '),
        isNot(contains(_phone)),
      );
    });

    testWidgets("the minor: DM2's failed send offers SMS only", (tester) async {
      final rig = _FlowRig();
      await pumpAtDormant(tester, rig);
      await tester.tap(find.text("I'm new to Attune"));
      await tester.pumpAndSettle();
      rig.sender.failNext = Exception('offline');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(find.text("We couldn't send a code. Try again."), findsOneWidget);
      expect(find.textContaining('WhatsApp'), findsNothing);
      expect(find.text('One more code to finish'), findsOneWidget);
    });

    testWidgets("a blocked phone: \"I'm new\" goes to X1 and never calls "
        'start-fresh-account', (tester) async {
      final rig = _FlowRig();
      final prefs = await pumpAtDormant(
        tester,
        rig,
        entry: SignUpEntry.returning,
        blocked: true,
      );
      await tester.tap(find.text("I'm new to Attune"));
      await tester.pumpAndSettle();
      expect(rig.fresh.nonces, isEmpty);
      expect(_harness!.location, RouteNames.ageStop);
      expect(_harness!.routing.underAgeBlocked, isTrue);
      expect(SignUpDraftStore.readFrom(prefs, _now), isNull);
    });

    test('a blocked phone: startFresh is blocked, the server never called, '
        'the challenge and the draft gone', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final rig = _Rig(prefs);
      final c = await _atCode(rig);
      rig.refuse('account_dormant:$_nonce');
      expect(await c.verify('123456'), isA<VerifiedDormant>());
      await prefs.setString(AgeGateStore.blockUntilKey, blockedUntil);
      expect(await c.startFresh(), FreshStartOutcome.blocked);
      expect(rig.fresh.nonces, isEmpty);
      expect(rig.drafts.read(), isNull);
      expect(await c.startFresh(), isNot(FreshStartOutcome.done));
      expect(rig.fresh.nonces, isEmpty);
    });

    test('I-2: leaveDormant drops the challenge and the draft', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final rig = _Rig(prefs);
      final c = await _atCode(rig);
      rig.refuse('account_dormant:$_nonce');
      await c.verify('123456');
      await c.leaveDormant();
      expect(rig.drafts.read(), isNull);
      expect(await c.startFresh(), FreshStartOutcome.expired);
      expect(rig.fresh.nonces, isEmpty);
    });
  });
}

FlowHarness? _harness;

class _FlowRig {
  final sender = FakeCodeSender();
  final auth = FakeSignUpAuth();
  final gateway = FakeAccountGateway(
    homeState: FakeAccountGateway.account(hasAccount: false),
  );
  final fresh = FakeFreshStart();
}
