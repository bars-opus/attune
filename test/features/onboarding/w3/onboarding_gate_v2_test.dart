// Spec 1 W3a (§3.7, §3.14, §3.15; W2 final review M-3, M-5; W2 P-15): the
// v2 gate shows only what the account lacks, in order, then A6 and R1;
// a hold opens H1; an unknown need asks for an update; no account goes back
// to sign-up; a queued A5 or A6 counts as done; offline A6 queues
// Relationship and Just for me, never Dating.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/features/onboarding/presentation/widgets/catch_up_steps.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_account_gateway.dart';
import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-gate';

class _Gate {
  _Gate(
    this.router,
    this.gateway,
    this.prefs,
    this.invites,
    this.signOuts,
    this.routing,
    this.atSignOut,
  );
  final GoRouter router;
  final FakeHomeStateGateway gateway;
  final SharedPreferences prefs;
  final FakeInvites invites;
  final List<String> signOuts;

  /// At each sign-out: was the phone blocked, and was the queue cleared?
  final List<(bool, bool)> atSignOut;

  /// No prefs: underAgeBlocked reads only what setUnderAgeBlocked set.
  final RoutingNotifier routing;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  OnboardingStore get store => OnboardingStore(prefs, scope: 'user.$_uid');
}

/// A keystore whose writes never finish (seen on some Samsung phones).
class _HangingSecure extends Fake implements FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Completer<void>().future;
}

Future<_Gate> _pumpGate(
  WidgetTester tester, {
  Map<String, dynamic>? server,
  Map<String, Object> prefsValues = const {},
  bool signedIn = true,
  String? phone = '+233244123456',
  FakeInvites? invites,
  AccountGateway? accounts,
  void Function(FakeHomeStateGateway)? setUp,
  FlutterSecureStorage? ageGateSecure,
  int settleSteps = 12,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefsValues);
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final gateway = FakeHomeStateGateway(state: server);
  setUp?.call(gateway);
  final service = HomeStateService(gateway);
  final fakeInvites = invites ?? FakeInvites();
  final signOuts = <String>[];
  final atSignOut = <(bool, bool)>[];
  final routing = RoutingNotifier(flowV2: true);
  final user = signedIn ? testUser(_uid) : null;
  final auth = FakeHomeAuth(
    user == null
        ? null
        : User(
          id: user.id,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-10-01T00:00:00Z',
          phone: phone,
        ),
  );
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
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('LOGIN')),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, s) => Scaffold(body: Text('SIGNUP ${s.uri.query}')),
      ),
      GoRoute(
        path: '/age-stop',
        builder: (_, s) => Scaffold(body: Text('X1 ${s.uri.query}')),
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
          OnboardingSyncService(
            homeStateService: service,
            accountService: accounts == null ? null : AccountService(accounts),
          ),
        ),
        invitePartnerServiceProvider.overrideWithValue(fakeInvites),
        catchUpSignOutProvider.overrideWithValue(() async {
          atSignOut.add((
            AgeGateStore.readBlocked(prefs, DateTime.now()),
            OnboardingStore(prefs, scope: 'user.$_uid').pendingInviteCode ==
                null,
          ));
          signOuts.add('out');
        }),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(openCountries: const ['GB', 'GH']),
        ),
        routingNotifierProvider.overrideWith((ref) => routing),
        if (ageGateSecure != null)
          ageGateStoreProvider.overrideWithValue(
            AgeGateStore(prefs, secure: ageGateSecure),
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
  await _settle(tester, steps: settleSteps);
  return _Gate(
    router,
    gateway,
    prefs,
    fakeInvites,
    signOuts,
    routing,
    atSignOut,
  );
}

/// Lets the gate's calls and waitForRouterSettled's polls run. No
/// pumpAndSettle: the loading step's spinner never settles.
Future<void> _settle(WidgetTester tester, {int steps = 12}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets(
    'needs [consent]: A5c before home, every launch until accepted (M-3)',
    (tester) async {
      var g = await _pumpGate(tester, server: homeJson(needs: ['consent']));
      expect(find.text("We've updated our terms"), findsOneWidget);

      // Killed here and opened again: A5c again, not home.
      g = await _pumpGate(tester, server: homeJson(needs: ['consent']));
      expect(find.text("We've updated our terms"), findsOneWidget);

      // Set before the tap: awaiting the tap already runs the calls.
      g.gateway.state = homeJson();
      await tester.tap(find.text('Agree and continue'));
      await _settle(tester);
      expect(g.gateway.count('record_eula_acceptance'), 1);
      expect(find.text('HOME'), findsOneWidget);
    },
  );

  testWidgets('A5c "Not now" signs out', (tester) async {
    final g = await _pumpGate(tester, server: homeJson(needs: ['consent']));
    await tester.tap(find.text('Not now'));
    await _settle(tester);
    expect(g.signOuts, ['out']);
  });

  testWidgets('no account and nothing queued: back to sign-up (M-5)', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(
        hasAccount: false,
        path: null,
        needs: ['consent', 'birth_date', 'name', 'path'],
      ),
    );
    expect(g.location, '/signup?entry=returning');
  });

  testWidgets('a queued A5 counts as done: only A6 is asked', (tester) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(
        hasAccount: false,
        path: null,
        needs: ['consent', 'birth_date', 'name', 'path'],
      ),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_sign_up':
            '{"display_name":"Ama","birth_date":"1990-01-01"}',
      },
      setUp: (gw) => gw.failNext = null,
    );
    // The replay ran (complete_sign_up refused offline here, so it stays
    // queued) and the server still has no account: A6.
    expect(find.text('What brings you to Attune?'), findsOneWidget);
    expect(g.store.pendingSignUp, isNotNull);
  });

  testWidgets('needs [birth_date]: "Add your date of birth", then home', (
    tester,
  ) async {
    final g = await _pumpGate(tester, server: homeJson(needs: ['birth_date']));
    expect(find.text('Add your date of birth'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    await tester.enterText(find.bySemanticsLabel('Day of birth'), '8');
    await tester.enterText(find.bySemanticsLabel('Month of birth'), '11');
    await tester.enterText(find.bySemanticsLabel('Year of birth'), '1991');
    await tester.pump(const Duration(milliseconds: 300));
    g.gateway.state = homeJson();
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(g.gateway.calls.firstWhere((c) => c.$1 == 'set_my_birth_date').$2, {
      'p_birth_date': '1991-11-08',
    });
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('an under-18 date of birth: block, clear, sign out, then X1', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(needs: ['birth_date']),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
    );
    g.gateway.birthDateStatus = 'not_eligible';
    await tester.enterText(find.bySemanticsLabel('Day of birth'), '1');
    await tester.enterText(find.bySemanticsLabel('Month of birth'), '1');
    await tester.enterText(find.bySemanticsLabel('Year of birth'), '2012');
    await tester.pump(const Duration(milliseconds: 300));
    g.gateway.state = homeJson(needs: ['birth_date'], hold: true);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    // Ruling (B3 fix round): signed out at once, no tap; the block and the
    // cleared queue were in place before the sign-out (W2 I-3 order).
    expect(g.signOuts, ['out']);
    expect(g.atSignOut, [(true, true)]);
    // F-8: blocked in prefs and in this session; entry=returning stays
    // open (M-1).
    expect(AgeGateStore.readBlocked(g.prefs, DateTime.now()), isTrue);
    expect(g.routing.underAgeBlocked, isTrue);
    expect(g.store.pendingInviteCode, isNull);
    // X1, which needs no session; never H1 waiting for a tap.
    expect(g.location, '/age-stop?from=account');
    expect(find.text('We need to check your account'), findsNothing);
  });

  testWidgets('X1 after the catch-up says the account is on hold', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () => const UnderAgeStopScreen(accountHeld: true),
    );
    expect(find.text('Attune is for adults'), findsOneWidget);
    expect(
      find.text(
        'You need to be 18 or older to use Attune. Your account is on hold.',
      ),
      findsOneWidget,
    );
    // Not the sign-up wording: this account exists and its date is kept.
    expect(find.textContaining("haven't saved"), findsNothing);
    expect(find.textContaining("couldn't create"), findsNothing);
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('an adult catch-up date of birth never blocks the phone', (
    tester,
  ) async {
    final g = await _pumpGate(tester, server: homeJson(needs: ['birth_date']));
    await tester.enterText(find.bySemanticsLabel('Day of birth'), '8');
    await tester.enterText(find.bySemanticsLabel('Month of birth'), '11');
    await tester.enterText(find.bySemanticsLabel('Year of birth'), '1991');
    await tester.pump(const Duration(milliseconds: 300));
    g.gateway.state = homeJson();
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(AgeGateStore.readBlocked(g.prefs, DateTime.now()), isFalse);
    expect(g.routing.underAgeBlocked, isFalse);
  });

  testWidgets('the catch-up steps start empty (D8: nothing pre-filled)', (
    tester,
  ) async {
    // A name and date from another attempt on this phone are never shown.
    final g = await _pumpGate(
      tester,
      server: homeJson(needs: ['birth_date', 'name']),
      prefsValues: {
        'attune.onboarding.user.$_uid.display_name': 'Someone Else',
        'attune.flow.anonymous.signup_draft':
            '{"name":"Someone Else","birth_date":"2001-02-03"}',
      },
    );
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.controller?.text ?? '', isEmpty);
    }
    await tester.enterText(find.bySemanticsLabel('Day of birth'), '8');
    await tester.enterText(find.bySemanticsLabel('Month of birth'), '11');
    await tester.enterText(find.bySemanticsLabel('Year of birth'), '1991');
    await tester.pump(const Duration(milliseconds: 300));
    g.gateway.state = homeJson(needs: ['name']);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('What should we call you?'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('A1 and A2: a failed save is shown with its icon; '
      'what was typed stays (I#1)', (tester) async {
    var g = await _pumpGate(tester, server: homeJson(needs: ['name']));
    g.gateway.failAlways = TimeoutException('offline');
    await tester.enterText(find.byType(TextField), 'Akosua');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text("We couldn't save that. Try again."), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Akosua',
    );

    g = await _pumpGate(tester, server: homeJson(needs: ['birth_date']));
    g.gateway.failAlways = TimeoutException('offline');
    await tester.enterText(find.bySemanticsLabel('Day of birth'), '8');
    await tester.enterText(find.bySemanticsLabel('Month of birth'), '11');
    await tester.enterText(find.bySemanticsLabel('Year of birth'), '1991');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text("We couldn't save that. Try again."), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      [
        for (final field in tester.widgetList<TextField>(
          find.byType(TextField),
        ))
          field.controller!.text,
        // The test locale (en-US) orders them month, day, year.
      ],
      ['11', '8', '1991'],
    );
    // Try again works from the same fields.
    g.gateway.failAlways = null;
    g.gateway.state = homeJson();
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('one visit walks every need in order, each once', (tester) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(
        path: null,
        needs: ['consent', 'birth_date', 'name', 'path'],
      ),
    );
    expect(find.text("We've updated our terms"), findsOneWidget);
    g.gateway.state = homeJson(
      path: null,
      needs: ['birth_date', 'name', 'path'],
    );
    await tester.tap(find.text('Agree and continue'));
    await _settle(tester);
    expect(find.text('Add your date of birth'), findsOneWidget);
    await tester.enterText(find.bySemanticsLabel('Day of birth'), '8');
    await tester.enterText(find.bySemanticsLabel('Month of birth'), '11');
    await tester.enterText(find.bySemanticsLabel('Year of birth'), '1991');
    await tester.pump(const Duration(milliseconds: 300));
    g.gateway.state = homeJson(path: null, needs: ['name', 'path']);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('What should we call you?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Akosua');
    g.gateway.state = homeJson(path: null, needs: ['path']);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('What brings you to Attune?'), findsOneWidget);
    g.gateway.onSetPath =
        (p) => g.gateway.state = homeJson(path: p['p_path'] as String);
    await tester.tap(find.text('Just for me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
    expect(
      [
        for (final call in g.gateway.calls)
          if (call.$1 != 'get_my_home_state') call.$1,
      ],
      ['record_eula_acceptance', 'set_my_birth_date', 'set_my_path'],
    );
    expect(g.gateway.savedNames, [(_uid, 'Akosua')]);
  });

  testWidgets('a need this build does not know wins over a known one', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      server: homeJson(needs: ['birth_date', 'from_a_later_wave']),
    );
    expect(find.text('Update Attune to continue'), findsOneWidget);
    expect(find.text('Add your date of birth'), findsNothing);
  });

  testWidgets('a queued A5: no invite before the account, and A6 queues '
      '(I#2, §3.14)', (tester) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(
        hasAccount: false,
        path: null,
        needs: ['consent', 'birth_date', 'name', 'path'],
      ),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_sign_up':
            '{"display_name":"Ama","birth_date":"1990-01-01"}',
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
      accounts: FakeAccountGateway()..failWith = TimeoutException('flaky'),
    );
    expect(find.text('What brings you to Attune?'), findsOneWidget);
    // accept-invite waits for the date of birth on the server (§3.14).
    expect(g.invites.accepted, isEmpty);
    expect(g.store.pendingInviteCode, 'K7P2QM');

    // Dating is never queued (D20), and says why.
    await tester.tap(find.text('Single and open to dating'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(
      find.text("Dating needs a connection. Try again when you're online."),
      findsOneWidget,
    );
    expect(g.store.pendingPath, isNull);

    await tester.tap(find.text('Just for me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text("We couldn't save that. Try again."), findsNothing);
    expect(g.store.pendingPath, AppPath.justMe);
    expect(g.gateway.count('set_my_path'), 0);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a queued A5 that lands: the queued A6 follows it, then home', (
    tester,
  ) async {
    final accounts = FakeAccountGateway()..failWith = TimeoutException('flaky');
    final g = await _pumpGate(
      tester,
      server: homeJson(
        hasAccount: false,
        path: null,
        needs: ['consent', 'birth_date', 'name', 'path'],
      ),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_sign_up':
            '{"display_name":"Ama","birth_date":"1990-01-01"}',
      },
      accounts: accounts,
    );
    expect(find.text('What brings you to Attune?'), findsOneWidget);
    // The connection comes back: A5 lands on the next replay, and the
    // account then owes only the path.
    accounts.failWith = null;
    g.gateway.state = homeJson(path: null, needs: ['path']);
    g.gateway.onSetPath =
        (p) => g.gateway.state = homeJson(path: p['p_path'] as String);
    await tester.tap(find.text('Just for me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(accounts.count('complete_sign_up'), 2);
    expect(g.store.pendingSignUp, isNull);
    expect(g.gateway.calls.firstWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'just_me',
      'p_confirmed': false,
    });
    expect(g.store.pendingPath, isNull);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('A6 keeps the chosen card after an error (Try again)', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
    );
    g.gateway.failAlways = TimeoutException('offline');
    await tester.tap(find.text('Single and open to dating'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(
      find.text("Dating needs a connection. Try again when you're online."),
      findsOneWidget,
    );
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(
            find.bySemanticsLabel(RegExp(r'^Single and open to dating\.')),
          )
          .hasFlag(SemanticsFlag.isChecked),
      isTrue,
    );
    semantics.dispose();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a refused shared-space set shows A6, not "couldn\'t check"', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path'], link: 'linked'),
      setUp:
          (gw) =>
              gw.onSetPath =
                  (_) => throw FakeHomeStateGateway.refusal('path:invalid'),
    );
    expect(find.text("We couldn't check your account"), findsNothing);
    expect(find.text('What brings you to Attune?'), findsOneWidget);
    expect(g.gateway.count('set_my_path'), 1);
  });

  testWidgets('A6 with a shared space open says so in words', (tester) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
    );
    g.gateway.failNext = FakeHomeStateGateway.refusal('path:relationship_open');
    await tester.tap(find.text('Just for me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(
      find.text(
        "You're in a shared space. To use Attune another way, end it or "
        'pause it first.',
      ),
      findsOneWidget,
    );
    expect(find.text("We couldn't save that. Try again."), findsNothing);
  });

  testWidgets('a refused typed code stays on the code step, in our words', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
      invites: FakeInvites(
        acceptError: const RelationshipInviteException('raw server text'),
      ),
    );
    await tester.ensureVisible(find.text('My partner already invited me'));
    await tester.tap(find.text('My partner already invited me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'K7P2QM');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(g.invites.accepted, ['K7P2QM']);
    expect(find.text('Enter your invite code'), findsOneWidget);
    expect(find.text('raw server text'), findsNothing);
    expect(
      find.text(
        "This code didn't work. It may have expired or been used. "
        'Ask for a new one.',
      ),
      findsOneWidget,
    );

    g.invites.acceptError = const RelationshipInviteException(
      'Could not accept invite.',
      retryable: true,
    );
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(
      find.text("We couldn't check that code. Try again when you're online."),
      findsOneWidget,
    );
  });

  testWidgets('the loading step is labelled', (tester) async {
    final semantics = tester.ensureSemantics();
    final g = await _pumpGate(
      tester,
      server: homeJson(),
      setUp: (gw) => gw.hold = Completer<void>(),
    );
    expect(
      find.bySemanticsLabel('Checking your account\u2026'),
      findsOneWidget,
    );
    g.gateway.hold!.complete();
    await _settle(tester);
    semantics.dispose();
  });

  testWidgets('a hold opens H1; Sign out signs out', (tester) async {
    final g = await _pumpGate(tester, server: homeJson(hold: true));
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await _settle(tester);
    expect(g.signOuts, ['out']);
  });

  // Ruling N-2: H1 for an age hold also blocks this phone (creation and
  // guest Opinions), as F-8 does; "I already have an account" stays open.
  void expectAgeHoldBlock(_Gate g) {
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(AgeGateStore.readBlocked(g.prefs, DateTime.now()), isTrue);
    expect(g.routing.underAgeBlocked, isTrue);
    expect(flowV2Redirect(g.routing, RouteNames.signUp), RouteNames.ageStop);
    expect(
      flowV2Redirect(g.routing, RouteNames.signUp, entry: 'returning'),
      isNull,
    );
  }

  testWidgets('a retried under-18 catch-up (already_set): H1 and the '
      'device block (N-2)', (tester) async {
    final g = await _pumpGate(tester, server: homeJson(needs: ['birth_date']));
    await tester.enterText(find.bySemanticsLabel('Day of birth'), '1');
    await tester.enterText(find.bySemanticsLabel('Month of birth'), '1');
    await tester.enterText(find.bySemanticsLabel('Year of birth'), '2012');
    await tester.pump(const Duration(milliseconds: 300));
    // The first answer was lost: the server already holds the date.
    g.gateway.failNext = FakeHomeStateGateway.refusal(
      'birth_date:already_set',
    );
    g.gateway.state = homeJson(hold: true);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expectAgeHoldBlock(g);
  });

  testWidgets('a hung keystore never keeps H1 away (I-2)', (tester) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(hold: true),
      ageGateSecure: _HangingSecure(),
      // Less than the keystore bound: H1 never waits on the block.
      settleSteps: 4,
    );
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(AgeGateStore.readBlocked(g.prefs, DateTime.now()), isTrue);
    await _settle(tester);
    expectAgeHoldBlock(g);
  });

  testWidgets('a hung keystore never keeps the under-18 sign-out and X1 '
      'away (I-2)', (tester) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(needs: ['birth_date']),
      ageGateSecure: _HangingSecure(),
    );
    g.gateway.birthDateStatus = 'not_eligible';
    await tester.enterText(find.bySemanticsLabel('Day of birth'), '1');
    await tester.enterText(find.bySemanticsLabel('Month of birth'), '1');
    await tester.enterText(find.bySemanticsLabel('Year of birth'), '2012');
    await tester.pump(const Duration(milliseconds: 300));
    g.gateway.state = homeJson(needs: ['birth_date'], hold: true);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(g.signOuts, ['out']);
    expect(g.atSignOut, [(true, true)]);
    expect(g.routing.underAgeBlocked, isTrue);
    expect(g.location, '/age-stop?from=account');
  });

  testWidgets('a held minor signing back in: H1 and the device block (N-2)', (
    tester,
  ) async {
    final g = await _pumpGate(tester, server: homeJson(hold: true));
    expectAgeHoldBlock(g);
  });

  testWidgets('an unknown need asks for an update, never home (P-15)', (
    tester,
  ) async {
    await _pumpGate(tester, server: homeJson(needs: ['from_a_later_wave']));
    expect(find.text('Update Attune to continue'), findsOneWidget);
  });

  testWidgets('needs [name]: the name, then home', (tester) async {
    final g = await _pumpGate(tester, server: homeJson(needs: ['name']));
    await tester.enterText(find.byType(TextField), '  Akosua  ');
    g.gateway.state = homeJson();
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(g.gateway.savedNames.single, (_uid, 'Akosua'));
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('leaving the gate while a call runs never throws', (
    tester,
  ) async {
    for (final (name, server, offline, act) in <
      (String, Map<String, dynamic>, bool, Future<void> Function())
    >[
      (
        'A5c accepted',
        homeJson(needs: ['consent']),
        false,
        () => tester.tap(find.text('Agree and continue')),
      ),
      (
        'A6 queued offline',
        homeJson(path: null, needs: ['path']),
        true,
        () async {
          await tester.tap(find.text('Just for me'));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('Continue'));
        },
      ),
      (
        'A2 under 18',
        homeJson(needs: ['birth_date']),
        false,
        () async {
          await tester.enterText(find.bySemanticsLabel('Day of birth'), '1');
          await tester.enterText(find.bySemanticsLabel('Month of birth'), '1');
          await tester.enterText(
            find.bySemanticsLabel('Year of birth'),
            '2012',
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('Continue'));
        },
      ),
    ]) {
      final g = await _pumpGate(tester, server: server);
      g.gateway.birthDateStatus = 'not_eligible';
      final held = Completer<void>();
      g.gateway.hold = held;
      if (offline) g.gateway.failAlways = TimeoutException('offline');
      await act();
      await tester.pump();
      g.router.go('/login');
      await _settle(tester);
      expect(find.text('LOGIN'), findsOneWidget);
      held.complete();
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: name);
      if (name == 'A2 under 18') {
        // The block and the sign-out land even though the gate has gone.
        expect(AgeGateStore.readBlocked(g.prefs, DateTime.now()), isTrue);
        expect(g.routing.underAgeBlocked, isTrue);
        expect(g.signOuts, ['out']);
      }
      if (name == 'A6 queued offline') {
        expect(g.store.pendingPath, AppPath.justMe);
      }
    }
  });

  testWidgets('A6 Just for me: set_my_path, then home', (tester) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
    );
    g.gateway.onSetPath =
        (p) => g.gateway.state = homeJson(path: p['p_path'] as String);
    await tester.tap(find.text('Just for me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(g.gateway.calls.firstWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'just_me',
      'p_confirmed': false,
    });
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('A6 Relationship: R1 follows', (tester) async {
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
    expect(find.byType(InvitePartnerScreen), findsOneWidget);
    await tester.tap(find.text('Create my invite'));
    await _settle(tester);
    expect(g.invites.creates, 1);
    expect(find.text('K7P2QM'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('A6 offline: Just for me is queued; Dating is not (D20)', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
    );
    g.gateway.failAlways = TimeoutException('offline');
    await tester.tap(find.text('Single and open to dating'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(
      find.text("Dating needs a connection. Try again when you're online."),
      findsOneWidget,
    );
    expect(g.store.pendingPath, isNull);
    for (final key in g.prefs.getKeys()) {
      expect('${g.prefs.get(key)}'.toLowerCase(), isNot(contains('dating')));
    }

    await tester.tap(find.text('Just for me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(g.store.pendingPath, AppPath.justMe);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('an open shared space is Relationship without asking', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path'], link: 'linked'),
      setUp:
          (gateway) =>
              gateway.onSetPath =
                  (_) =>
                      gateway.state = homeJson(
                        path: 'relationship',
                        link: 'linked',
                      ),
    );
    expect(find.text('What brings you to Attune?'), findsNothing);
    expect(g.gateway.calls.firstWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'relationship',
      'p_confirmed': true,
    });
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets(
    'a stored invite is accepted after the name, not before (D9, §5.2)',
    (tester) async {
      final g = await _pumpGate(
        tester,
        server: homeJson(path: null, needs: ['name', 'path']),
        prefsValues: {
          'attune.onboarding.user.$_uid.pending_invite':
              '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
        },
      );
      expect(g.invites.accepted, isEmpty, reason: 'not before the name');
      g.gateway.state = homeJson(path: null, needs: ['path']);
      g.gateway.onSetPath =
          (p) =>
              g.gateway.state = homeJson(path: 'relationship', link: 'linked');
      await tester.enterText(find.byType(TextField), 'Akosua');
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      expect(g.invites.accepted, ['K7P2QM']);
      expect(find.text('You are connected'), findsOneWidget);
      expect(g.store.pendingInviteCode, isNull);
    },
  );

  testWidgets('A6 "My partner already invited me" takes a code', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
    );
    await tester.ensureVisible(find.text('My partner already invited me'));
    await tester.tap(find.text('My partner already invited me'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Enter your invite code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(
      find.text(
        'Codes have 6 letters and numbers. Check it with the person who sent it.',
      ),
      findsOneWidget,
    );
    g.gateway.onSetPath =
        (p) => g.gateway.state = homeJson(path: 'relationship', link: 'linked');
    await tester.enterText(find.byType(TextField), 'k7p 2qm');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(g.invites.accepted, ['K7P2QM']);
    expect(find.text('You are connected'), findsOneWidget);
  });

  testWidgets('the invite code step meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpGate(tester, server: homeJson(path: null, needs: ['path']));
    await tester.ensureVisible(find.text('My partner already invited me'));
    await tester.tap(find.text('My partner already invited me'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectFlowGuidelines(tester);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('nothing known and offline: try again or sign out', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      setUp: (gw) => gw.failAlways = TimeoutException('offline'),
    );
    expect(find.text("We couldn't check your account"), findsOneWidget);
    g.gateway.failAlways = null;
    g.gateway.state = homeJson();
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('signed out: to sign-in', (tester) async {
    final g = await _pumpGate(tester, signedIn: false);
    expect(g.location, '/login');
  });

  testWidgets('H1, update and offline meet the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final screen in <Widget Function()>[
      () => AccountHoldStep(onSignOut: () {}),
      () => UpdateAppStep(onSignOut: () {}),
      () => CheckOfflineStep(onRetry: () {}, onSignOut: () {}),
    ]) {
      await pumpFlowScreen(tester, screen);
      await expectFlowGuidelines(tester);
    }
    semantics.dispose();
  });

  testWidgets('invite code step and confirmation sheet goldens', (
    tester,
  ) async {
    await expectFlowGoldens(
      tester,
      'invite_code',
      () =>
          InviteCodeStep(onSubmit: (_) async {}, onBack: () {}, errorCount: 0),
    );
    await expectFlowGoldens(
      tester,
      'flow_confirm',
      () => const Scaffold(
        body: FlowConfirmSheet(
          title: 'Cancel your invite?',
          body:
              "Your invite code will stop working. Your partner won't be told.",
          confirm: 'Cancel invite and switch',
          cancel: 'Keep invite',
        ),
      ),
    );
  });

  testWidgets('H1, update and offline goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'h1_hold',
      () => AccountHoldStep(onSignOut: () {}),
    );
    await expectFlowGoldens(
      tester,
      'update_app',
      () => UpdateAppStep(onSignOut: () {}),
    );
    await expectFlowGoldens(
      tester,
      'check_offline',
      () => CheckOfflineStep(onRetry: () {}, onSignOut: () {}),
    );
  });

  // W4a (batch 3, Task 2's answers): past the attempt limit (429
  // invite:try_later) says so and keeps the code; never "didn't work".
  testWidgets('a stored invite past the attempt limit: try later, code kept', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
      invites: FakeInvites(
        acceptError: inviteAcceptFailure(
          const FunctionException(
            status: 429,
            details: {'error': 'invite:try_later', 'code': 'invite:try_later'},
          ),
        ),
      ),
    );
    expect(g.invites.accepted, ['K7P2QM']);
    expect(
      find.text("You've checked a lot of codes. Try again in a little while."),
      findsOneWidget,
    );
    expect(find.textContaining("This code didn't work"), findsNothing);
    expect(find.textContaining('invite:'), findsNothing);
    expect(g.store.pendingInviteCode, 'K7P2QM');
  });

  // W4a (Task 1 ruling I-3): the acceptor's own hold (403 account:hold)
  // opens H1 from the server's answer; the code is dropped.
  testWidgets('a stored invite refused for the acceptor\'s hold opens H1', (
    tester,
  ) async {
    late _Gate g;
    final invites = _OnAccept(
      inviteAcceptFailure(
        const FunctionException(
          status: 403,
          details: {'error': 'account:hold', 'code': 'account:hold'},
        ),
      ),
      () => g.gateway.state = homeJson(path: null, needs: ['path'], hold: true),
    );
    g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['name', 'path']),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
      invites: invites,
    );
    g.gateway.state = homeJson(path: null, needs: ['path']);
    await tester.enterText(find.byType(TextField), 'Akosua');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(invites.accepted, ['K7P2QM']);
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(find.text('What brings you to Attune?'), findsNothing);
    expect(find.textContaining('account:'), findsNothing);
    expect(g.store.pendingInviteCode, isNull);
    // Batch-3 review #3: H1's device block (ruling N-2) on this path too.
    expect(g.routing.underAgeBlocked, isTrue);
  });

  // Batch-3 review #4: the server said account:hold, then the read that
  // would show H1 failed. The person stays on H1 (the last answer was a
  // hold), never A6 with nothing said.
  testWidgets('a hold refusal, then a failed read: still H1, never A6', (
    tester,
  ) async {
    late _Gate g;
    final invites = _OnAccept(
      inviteAcceptFailure(
        const FunctionException(
          status: 403,
          details: {'error': 'account:hold', 'code': 'account:hold'},
        ),
      ),
      () => g.gateway.failAlways = Exception('offline'),
    );
    g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['name', 'path']),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
      invites: invites,
    );
    g.gateway.state = homeJson(path: null, needs: ['path']);
    await tester.enterText(find.byType(TextField), 'Akosua');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(invites.accepted, ['K7P2QM']);
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(find.text('What brings you to Attune?'), findsNothing);
    expect(g.store.pendingInviteCode, isNull);
    expect(g.routing.underAgeBlocked, isTrue);
  });

  // Batch-3 review #5: a 503 invite:try_again is the server's own failure
  // (it answered), so the words never blame the connection; the code is
  // kept for the next try.
  testWidgets('a stored invite the server could not finish: neutral retry', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
      invites: FakeInvites(
        acceptError: inviteAcceptFailure(
          const FunctionException(
            status: 503,
            details: {'error': 'invite:try_again', 'code': 'invite:try_again'},
          ),
        ),
      ),
    );
    expect(g.invites.accepted, ['K7P2QM']);
    expect(
      find.text('Something went wrong on our side. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('online'), findsNothing);
    expect(find.textContaining('invite:'), findsNothing);
    expect(g.store.pendingInviteCode, 'K7P2QM');
  });

  // ...and a real connection failure still says so.
  testWidgets('a stored invite that could not reach the server: offline', (
    tester,
  ) async {
    final g = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
      prefsValues: {
        'attune.onboarding.user.$_uid.pending_invite':
            '{"code":"K7P2QM","stored_at":"2099-01-01T00:00:00.000Z"}',
      },
      invites: FakeInvites(
        acceptError: inviteAcceptFailure(Exception('socket closed')),
      ),
    );
    expect(g.invites.accepted, ['K7P2QM']);
    expect(
      find.text("We couldn't check that code. Try again when you're online."),
      findsOneWidget,
    );
    expect(g.store.pendingInviteCode, 'K7P2QM');
  });
}

/// FakeInvites whose accept runs [onAccept] (the server's state changing
/// with the answer), then refuses with [error].
class _OnAccept extends FakeInvites {
  _OnAccept(RelationshipInviteException error, this.onAccept)
    : super(acceptError: error);

  final void Function() onAccept;

  @override
  Future<InviteAcceptance> acceptInvite(String inviteCode) {
    onAccept();
    return super.acceptInvite(inviteCode);
  }
}
