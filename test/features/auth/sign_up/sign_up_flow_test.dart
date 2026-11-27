// Spec 1 W2b (§3.3, §3.4, §7.3): /signup on screen — the whole new-account
// path, the under-18 stop, a returning account, resume at A4, and consent
// shown without motion.
import 'dart:async';
import 'dart:convert';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/shared_axis_step.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/one_time_code_field.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_account_gateway.dart';
import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_sign_up.dart';
import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);

List<Override> _deps(
  FakeCodeSender sender,
  FakeSignUpAuth auth,
  FakeAccountGateway gateway,
) => [
  codeSenderProvider.overrideWithValue(sender),
  signUpAuthProvider.overrideWithValue(auth),
  accountServiceProvider.overrideWithValue(AccountService(gateway)),
  signUpClockProvider.overrideWithValue(() => _now),
  deviceCountryProvider.overrideWith((ref) async => (sim: 'GH', region: null)),
  smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
];

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pump();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// A draft with a code on its way to Ama's number: the flow opens at A4.
SignUpDraft _atCode({DateTime? lastSentAt}) =>
    SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
      name: 'Ama',
      birthDate: DateTime.utc(1990, 1, 1),
      phoneE164: '+233244123456',
      countryIso: 'GH',
      lastSentAt: lastSentAt ?? _now,
      sendCount: 1,
    );

/// What a screen reader was asked to read out, in order.
List<String> _announcements(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  final said = <String>[];
  messenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final event = message as Map<Object?, Object?>;
      if (event['type'] == 'announce') {
        said.add((event['data'] as Map<Object?, Object?>)['message'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return said;
}

/// How far A4's six boxes are moved sideways right now.
double _shake(WidgetTester tester) {
  final boxes =
      find
          .descendant(
            of: find.byType(OneTimeCodeField),
            matching: find.byType(Stack),
          )
          .first;
  return tester
      .widget<Transform>(
        find.ancestor(of: boxes, matching: find.byType(Transform)).first,
      )
      .transform
      .getTranslation()
      .x;
}

/// The colours of A4's six box borders.
List<Color> _boxBorders(WidgetTester tester) => [
  for (final container in tester.widgetList<Container>(
    find.descendant(
      of: find.byType(OneTimeCodeField),
      matching: find.byType(Container),
    ),
  ))
    if (container.decoration case BoxDecoration(border: final Border border))
      border.top.color,
];

/// The account-check hold (review B5 fix round 2): its own words, Try
/// again and Not now, nothing about a code.
void _expectAccountHold() {
  expect(find.text("We couldn't check your account"), findsOneWidget);
  expect(
    find.ancestor(
      of: find.text('Check your connection and try again.'),
      matching: find.byType(FlowErrorLine),
    ),
    findsOneWidget,
  );
  expect(find.text('Try again'), findsOneWidget);
  expect(find.text('Not now'), findsOneWidget);
  expect(find.text('Enter the code'), findsNothing);
  expect(find.textContaining('We sent a 6-digit code'), findsNothing);
  expect(find.textContaining('Send a new code'), findsNothing);
}

void main() {
  testWidgets('a new account from A1 to home', (tester) async {
    final sender = FakeCodeSender();
    final auth = FakeSignUpAuth();
    final gateway = FakeAccountGateway(
      homeState: FakeAccountGateway.account(hasAccount: false),
    );
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      overrides: _deps(sender, auth, gateway),
    );

    expect(find.text('What should we call you?'), findsOneWidget);
    await _type(tester, 'Your name', 'Ɛsi');
    await _tapText(tester, 'Continue');

    expect(find.text("What's your date of birth?"), findsOneWidget);
    await _type(tester, 'Day', '27');
    await _type(tester, 'Month', '3');
    await _type(tester, 'Year', '1996');
    expect(
      find.text('Wednesday, March 27, 1996 - that makes you 30.'),
      findsOneWidget,
    );
    await _tapText(tester, 'Continue');

    expect(find.text("What's your phone number?"), findsOneWidget);
    expect(
      find.textContaining('Ghana (+233)'),
      findsOneWidget,
      reason: 'the SIM country',
    );
    await _type(tester, 'Phone number', '0244123456');
    await _tapText(tester, 'Text me a code');
    expect(sender.sent.single.$1, '+233244123456');

    expect(find.text('Enter the code'), findsOneWidget);
    // The time rolls as its own digits (2026-11-26): the line is whole for a
    // screen reader.
    expect(find.bySemanticsLabel('Send a new code in 0:30'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Before you start'), findsOneWidget);
    // Entry gates fix round: no account yet, so nothing to delete (only
    // the gate's A5c and H1 offer it).
    expect(find.text('Delete my account'), findsNothing);
    expect(find.text('Download my data'), findsNothing);
    await _tapText(tester, 'Agree and continue');
    expect(h.location, '/home');
    expect(gateway.count('complete_sign_up'), 1);
    expect(SignUpDraftStore.readFrom(h.prefs, _now), isNull);
  });

  testWidgets('under 18 at A2 opens X1 and nothing is sent', (tester) async {
    final sender = FakeCodeSender();
    final gateway = FakeAccountGateway();
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      overrides: _deps(sender, FakeSignUpAuth(), gateway),
    );
    await _type(tester, 'Your name', 'Kid');
    await _tapText(tester, 'Continue');
    await _type(tester, 'Day', '1');
    await _type(tester, 'Month', '1');
    await _type(tester, 'Year', '2012');
    await _tapText(tester, 'Continue');

    expect(h.location, '/age-stop');
    expect(h.routing.underAgeBlocked, isTrue);
    expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
    expect(sender.sent, isEmpty);
    expect(gateway.calls, isEmpty);
    expect(SignUpDraftStore.readFrom(h.prefs, _now), isNull);
  });

  testWidgets('a returning account: "Welcome back, Kofi." then home', (
    tester,
  ) async {
    final gateway = FakeAccountGateway(
      homeState: FakeAccountGateway.account(),
      name: 'Kofi',
    );
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(FakeCodeSender(), FakeSignUpAuth(), gateway),
    );
    expect(find.text("What's your phone number?"), findsOneWidget);
    await _type(tester, 'Phone number', '244123456');
    await _tapText(tester, 'Text me a code');
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Welcome back, Kofi.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(h.location, '/home');
  });

  testWidgets('a returning number with no account sees N1', (tester) async {
    final gateway = FakeAccountGateway(
      homeState: FakeAccountGateway.account(hasAccount: false),
    );
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(FakeCodeSender(), FakeSignUpAuth(), gateway),
    );
    await _type(tester, 'Phone number', '244123456');
    await _tapText(tester, 'Text me a code');
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't find an Attune account for this number"),
      findsOneWidget,
    );
    await _tapText(tester, 'Create an account');
    expect(find.text('What should we call you?'), findsOneWidget);
  });

  testWidgets('a wrong code says so and keeps the person on A4', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(
        FakeCodeSender(),
        FakeSignUpAuth(),
        FakeAccountGateway(),
      ),
    );
    await _type(tester, 'Phone number', '244123456');
    await _tapText(tester, 'Text me a code');
    await tester.enterText(find.byType(TextField), '999999');
    await tester.pumpAndSettle();
    expect(
      find.text("That code didn't work. Check it and try again."),
      findsOneWidget,
    );
    expect(find.text('Enter the code'), findsOneWidget);
  });

  testWidgets('reopened with a code on its way, the flow opens at A4', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
      overrides: _deps(
        FakeCodeSender(),
        FakeSignUpAuth(),
        FakeAccountGateway(),
      ),
    );
    expect(find.text('Enter the code'), findsOneWidget);
  });

  testWidgets('consent replaces A4 at once, with no step animation '
      '(ruling C3)', (tester) async {
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
      overrides: _deps(
        FakeCodeSender(),
        FakeSignUpAuth(),
        FakeAccountGateway(
          homeState: FakeAccountGateway.account(hasAccount: false),
        ),
      ),
    );
    expect(find.text('Enter the code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(kCodeAcceptedHold);
    expect(find.text('Before you start'), findsOneWidget);

    // One frame after the step change: no A4 fading out beside it, and no
    // shared-axis step around it.
    await tester.pump();
    expect(find.text('Enter the code'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('Before you start'),
        matching: find.byType(SharedAxisStep),
      ),
      findsNothing,
    );
  });

  testWidgets('"Not now" signs out and goes back to Welcome', (tester) async {
    final draft = SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
      name: 'Ama',
      birthDate: DateTime.utc(1990, 1, 1),
      phoneE164: '+233244123456',
      lastSentAt: _now,
      sendCount: 1,
      verifiedUserId: 'u1',
      accountChecked: true,
    );
    final auth = FakeSignUpAuth(userId: 'u1');
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(draft)},
      overrides: _deps(FakeCodeSender(), auth, FakeAccountGateway()),
    );
    await _tapText(tester, 'Not now');
    expect(auth.signOuts, 1);
    expect(h.location, '/welcome');
    expect(
      RoutingNotifier(prefs: h.prefs, currentUserId: () => null).signUpToResume,
      isFalse,
    );
  });

  group('batch 5 carries', () {
    testWidgets('Review Focus 1 (B3 I-1): A2 follows the phone\'s region, so '
        'Ghana reads Day · Month · Year', (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en', 'GH');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(),
          FakeAccountGateway(),
        ),
      );
      await _type(tester, 'Your name', 'Ama');
      await _tapText(tester, 'Continue');
      double x(String label) =>
          tester.getCenter(find.widgetWithText(TextField, label)).dx;
      expect(x('Day'), lessThan(x('Month')));
      expect(x('Month'), lessThan(x('Year')));
    });

    testWidgets('A2 in the US reads Month · Day · Year (the order comes from '
        'the region, not a fixed choice)', (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(),
          FakeAccountGateway(),
        ),
      );
      await _type(tester, 'Your name', 'Ama');
      await _tapText(tester, 'Continue');
      double x(String label) =>
          tester.getCenter(find.widgetWithText(TextField, label)).dx;
      expect(x('Month'), lessThan(x('Day')));
      expect(x('Day'), lessThan(x('Year')));
    });

    testWidgets('a rate-limited resend is a notice: read out, the boxes '
        'neither shake nor turn red; a wrong code still shakes', (
      tester,
    ) async {
      final said = _announcements(tester);
      final sender =
          FakeCodeSender()
            ..failNext = const AuthException('otp:rate_limited:120');
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {
          SignUpDraftStore.key: jsonEncodeDraft(
            _atCode(lastSentAt: _now.subtract(const Duration(minutes: 2))),
          ),
        },
        overrides: _deps(sender, FakeSignUpAuth(), FakeAccountGateway()),
      );
      const notice = 'Too many codes. Try again in 2 minutes.';
      await tester.tap(find.text('Send a new code'));
      await tester.pump();
      final error =
          Theme.of(
            tester.element(find.byType(OneTimeCodeField)),
          ).colorScheme.error;
      for (final ms in [30, 30, 60, 120]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(_shake(tester), 0, reason: 'at +$ms ms');
      }
      expect(
        find.ancestor(
          of: find.text(notice),
          matching: find.byType(FlowErrorLine),
        ),
        findsOneWidget,
      );
      expect(said, contains(notice));
      expect(_boxBorders(tester), isNot(contains(error)));
      expect(sender.sent, isEmpty);
      // Review B5 M-3: no resend while the refusal's two minutes last.
      expect(find.text('Send a new code'), findsNothing);
      expect(find.bySemanticsLabel('Send a new code in 2:00'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '999999');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(_shake(tester), isNot(0), reason: 'a wrong code shakes');
      await tester.pumpAndSettle();
      expect(
        find.text("That code didn't work. Check it and try again."),
        findsOneWidget,
      );
    });

    testWidgets('an expired code is said and red, but neither shakes nor '
        'buzzes: only a wrong code does (§3.3 A4)', (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {
          SignUpDraftStore.key: jsonEncodeDraft(
            _atCode(lastSentAt: _now.subtract(const Duration(minutes: 11))),
          ),
        },
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(),
          FakeAccountGateway(),
        ),
      );
      await tester.enterText(find.byType(TextField), '999999');
      await tester.pump();
      for (final ms in [30, 30, 60, 120]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(_shake(tester), 0, reason: 'at +$ms ms');
      }
      expect(
        find.text('That code has expired. Send a new one.'),
        findsOneWidget,
      );
      expect(haptics, isEmpty);
    });

    testWidgets('system back while a code is being checked does nothing, '
        'however often it is pressed', (tester) async {
      final auth = FakeSignUpAuth()..holdVerify = Completer<void>();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
        overrides: _deps(
          FakeCodeSender(),
          auth,
          FakeAccountGateway(
            homeState: FakeAccountGateway.account(hasAccount: false),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(auth.verifyCalls, 1);

      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.text("What's your phone number?"), findsNothing);
      expect(
        SignUpDraftStore.readFrom(h.prefs, _now)!.awaitingCode,
        isTrue,
        reason: 'the number was not changed under the check',
      );

      auth.holdVerify!.complete();
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      expect(find.text('Before you start'), findsOneWidget);
      expect(auth.verifyCalls, 1);
    });

    testWidgets('Back while A3 is sending waits for the send', (tester) async {
      final sender = FakeCodeSender()..hold = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(sender, FakeSignUpAuth(), FakeAccountGateway()),
      );
      await _type(tester, 'Your name', 'Ama');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '27');
      await _type(tester, 'Month', '3');
      await _type(tester, 'Year', '1996');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Phone number', '0244123456');
      await tester.tap(find.text('Text me a code'));
      await tester.pump();

      // Pumped by hand: "Sending your code…" runs until the send answers.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(find.text("What's your date of birth?"), findsNothing);

      sender.hold!.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Enter the code'), findsOneWidget);
      expect(sender.sent, hasLength(1));
    });

    testWidgets('system back on A4 is "Wrong number? Change it"', (
      tester,
    ) async {
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(),
          FakeAccountGateway(),
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(
        SignUpDraftStore.readFrom(h.prefs, _now),
        isNull,
        reason: 'no code left sent: nothing to resume (fix round 5)',
      );
    });

    testWidgets('Review Focus 4: an account on EULA v1 sees "We\'ve updated '
        'our terms" once, records v2, then home', (tester) async {
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(needs: ['consent']),
        name: 'Kofi',
      );
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(FakeCodeSender(), FakeSignUpAuth(), gateway),
      );
      await _type(tester, 'Phone number', '244123456');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      expect(find.text("We've updated our terms"), findsOneWidget);

      await _tapText(tester, 'Agree and continue');
      expect(find.text('Welcome back, Kofi.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(h.location, '/home');
      expect(
        [
          for (final (fn, params) in gateway.calls)
            if (fn == 'record_eula_acceptance') params,
        ],
        [
          {'p_version': '2'},
        ],
      );
      expect(gateway.count('complete_sign_up'), 0);
    });
  });

  group('review B5 fix round 1', () {
    testWidgets('I-1: already signed in with no account: A1, A2, then A5, '
        'and no code is sent', (tester) async {
      final sender = FakeCodeSender();
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(hasAccount: false),
      );
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(
          sender,
          FakeSignUpAuth(userId: 'u1', phone: '+233244123456'),
          gateway,
        ),
      );
      expect(find.text('What should we call you?'), findsOneWidget);
      await _type(tester, 'Your name', 'Ama');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '27');
      await _type(tester, 'Month', '3');
      await _type(tester, 'Year', '1996');
      await _tapText(tester, 'Continue');
      expect(find.text('Before you start'), findsOneWidget);
      await _tapText(tester, 'Agree and continue');
      expect(h.location, '/home');
      expect(sender.sent, isEmpty);
      expect(gateway.count('complete_sign_up'), 1);
    });

    testWidgets('I-1: already signed in on an account on EULA v1: A5c, no '
        'code', (tester) async {
      final sender = FakeCodeSender();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(
          sender,
          FakeSignUpAuth(userId: 'u1'),
          FakeAccountGateway(
            homeState: FakeAccountGateway.account(needs: ['consent']),
            name: 'Kofi',
          ),
        ),
      );
      expect(find.text("We've updated our terms"), findsOneWidget);
      expect(find.text("What's your phone number?"), findsNothing);
      expect(sender.sent, isEmpty);
    });

    testWidgets('I-2: reopened after a check that failed: the account is '
        'checked again, so an existing one gets "Welcome back", not A5', (
      tester,
    ) async {
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(),
        name: 'Kofi',
      );
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {
          SignUpDraftStore.key: jsonEncodeDraft(
            _atCode().copyWith(verifiedUserId: 'u1'),
          ),
        },
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(userId: 'u1'),
          gateway,
        ),
      );
      expect(find.text('Before you start'), findsNothing);
      expect(find.text('Welcome back, Kofi.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(h.location, '/home');
      expect(gateway.count('complete_sign_up'), 0);
    });

    testWidgets('I-2: the check fails again: its own state (fix round 2), '
        'then Try again goes on', (tester) async {
      final gateway = FakeAccountGateway(); // get_my_home_state unreadable
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {
          SignUpDraftStore.key: jsonEncodeDraft(
            _atCode().copyWith(verifiedUserId: 'u1'),
          ),
        },
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(userId: 'u1'),
          gateway,
        ),
      );
      _expectAccountHold();
      gateway.homeState = FakeAccountGateway.account(hasAccount: false);
      await _tapText(tester, 'Try again');
      expect(find.text('Before you start'), findsOneWidget);
    });

    testWidgets('I-3: under 18 at A2 after N1 ends the session and opens X1', (
      tester,
    ) async {
      final auth = FakeSignUpAuth();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(
          FakeCodeSender(),
          auth,
          FakeAccountGateway(
            homeState: FakeAccountGateway.account(hasAccount: false),
          ),
        ),
      );
      await _type(tester, 'Phone number', '244123456');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Create an account');
      await _type(tester, 'Your name', 'Kid');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '1');
      await _type(tester, 'Month', '1');
      await _type(tester, 'Year', '2012');
      await _tapText(tester, 'Continue');
      expect(h.location, '/age-stop');
      expect(auth.signOuts, 1);
      expect(auth.currentUserId, isNull);
      expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
      expect(SignUpDraftStore.readFrom(h.prefs, _now), isNull);
    });

    testWidgets("M-2: A3's Back follows the draft's own way in", (
      tester,
    ) async {
      final h = await pumpFlowScreen(
        tester,
        // The router resumes to a bare /signup.
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {
          SignUpDraftStore.key: jsonEncodeDraft(
            SignUpDraft.start(SignUpEntry.returning, now: _now).copyWith(
              phoneE164: '+233244123456',
              countryIso: 'GH',
              lastSentAt: _now,
              sendCount: 1,
            ),
          ),
        },
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(),
          FakeAccountGateway(),
        ),
      );
      await _tapText(tester, 'Wrong number? Change it');
      expect(find.text("What's your phone number?"), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text("What's your date of birth?"), findsNothing);
      expect(h.location, '/welcome');
    });

    testWidgets('M-3: a rate-limited check says so without inventing '
        'minutes', (tester) async {
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth()
            ..failVerifyWith = const AuthException(
              'Request rate limit reached',
              code: 'over_request_rate_limit',
              statusCode: '429',
            ),
          FakeAccountGateway(),
        ),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      expect(
        find.text('Too many tries. Try again in a few minutes.'),
        findsOneWidget,
      );
      expect(find.textContaining('1 minute'), findsNothing);
    });

    testWidgets('M-5: N1 "Use a different number" that fails to sign out '
        'says so', (tester) async {
      final auth = FakeSignUpAuth();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(
          FakeCodeSender(),
          auth,
          FakeAccountGateway(
            homeState: FakeAccountGateway.account(hasAccount: false),
          ),
        ),
      );
      await _type(tester, 'Phone number', '244123456');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      auth.failSignOut = true;
      await _tapText(tester, 'Use a different number');
      expect(
        find.text("We couldn't find an Attune account for this number"),
        findsOneWidget,
      );
      expect(find.text("We couldn't save that. Try again."), findsOneWidget);
    });

    testWidgets('M-7: the session gone at A5: back to A3 for a new code', (
      tester,
    ) async {
      final auth = FakeSignUpAuth(userId: 'u1');
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(hasAccount: false),
      );
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {
          SignUpDraftStore.key: jsonEncodeDraft(
            _atCode().copyWith(verifiedUserId: 'u1', accountChecked: true),
          ),
        },
        overrides: _deps(FakeCodeSender(), auth, gateway),
      );
      expect(find.text('Before you start'), findsOneWidget);
      auth.userId = null;
      await _tapText(tester, 'Agree and continue');
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(
        find.text('That code has expired. Send a new one.'),
        findsOneWidget,
      );
      expect(gateway.count('complete_sign_up'), 0);
    });
  });

  group('review B5 fix round 2', () {
    /// What person A left: A1, A2 (an adult), number A, no code pending,
    /// nothing verified ("Not now" at A5).
    SignUpDraft leftByA() =>
        SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
          name: 'Adult A',
          birthDate: DateTime.utc(1990, 5, 5),
          phoneE164: '+233244111111',
          countryIso: 'GH',
        );

    testWidgets("I-6: B, signed in on another number, is asked A1 and A2 "
        "afresh, never shown A's name", (tester) async {
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(hasAccount: false),
      );
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(leftByA())},
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(userId: 'uB', phone: '+233244222222'),
          gateway,
        ),
      );
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Adult A'), findsNothing);
      await _type(tester, 'Your name', 'B');
      await _tapText(tester, 'Continue');
      expect(find.text("What's your date of birth?"), findsOneWidget);
      expect(find.text('1990'), findsNothing);
      expect(gateway.count('complete_sign_up'), 0);
    });

    testWidgets("I-6: \"I already have an account\" on B's number after A's "
        'attempt: N1, then A1', (tester) async {
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(leftByA())},
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(verifiesAs: 'uB'),
          FakeAccountGateway(
            homeState: FakeAccountGateway.account(hasAccount: false),
          ),
        ),
      );
      await _type(tester, 'Phone number', '244222222');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      expect(
        find.text("We couldn't find an Attune account for this number"),
        findsOneWidget,
      );
      await _tapText(tester, 'Create an account');
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Adult A'), findsNothing);
    });

    testWidgets('hold: signed in and offline, its own state; Try again '
        'online on an existing account says "Welcome back"', (tester) async {
      final gateway = FakeAccountGateway(name: 'Kofi');
      final sender = FakeCodeSender();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(
          sender,
          FakeSignUpAuth(userId: 'u1', phone: '+233244123456'),
          gateway,
        ),
      );
      _expectAccountHold();
      gateway.homeState = FakeAccountGateway.account();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Welcome back, Kofi.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(h.location, '/home');
      expect(sender.sent, isEmpty);
    });

    testWidgets('hold: while the account is read it says so, never A4', (
      tester,
    ) async {
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(hasAccount: false),
      )..holdHomeState = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(userId: 'u1', phone: '+233244123456'),
          gateway,
        ),
      );
      expect(find.text('Checking your account…'), findsOneWidget);
      expect(find.text('Enter the code'), findsNothing);
      expect(find.textContaining('We sent a 6-digit code'), findsNothing);
      gateway.holdHomeState!.complete();
      await tester.pumpAndSettle();
      expect(find.text('What should we call you?'), findsOneWidget);
    });

    testWidgets('hold: Try again offline again says so again', (tester) async {
      final said = _announcements(tester);
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(userId: 'u1'),
          FakeAccountGateway(),
        ),
      );
      _expectAccountHold();
      await _tapText(tester, 'Try again');
      _expectAccountHold();
      expect(
        said.where((s) => s == 'Check your connection and try again.'),
        hasLength(2),
      );
    });

    testWidgets('hold: "Not now" signs out, goes to Welcome and leaves '
        'nothing to resume', (tester) async {
      final auth = FakeSignUpAuth(userId: 'u1');
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(FakeCodeSender(), auth, FakeAccountGateway()),
      );
      _expectAccountHold();
      await _tapText(tester, 'Not now');
      expect(auth.signOuts, 1);
      expect(h.location, '/welcome');
      expect(
        RoutingNotifier(
          prefs: h.prefs,
          currentUserId: () => null,
        ).signUpToResume,
        isFalse,
      );
    });

    testWidgets('hold: a code accepted on A4 whose account then can\'t be '
        'read leaves A4 for the hold (no stray resend)', (tester) async {
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(),
          FakeAccountGateway(),
        ),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      _expectAccountHold();
    });
  });

  group('review B5 fix round 3 (I-7)', () {
    for (final entry in [SignUpEntry.newAccount, SignUpEntry.returning]) {
      testWidgets('(d) A left at A4; B changes the number: A1 and A2 are '
          "shown, A's date is never sent for B (${entry.wire})", (
        tester,
      ) async {
        final left = SignUpDraft.start(
          SignUpEntry.newAccount,
          now: _now.subtract(const Duration(days: 3)),
        ).copyWith(
          name: 'Adult A',
          birthDate: DateTime.utc(1990, 5, 5),
          phoneE164: '+233244111111',
          countryIso: 'GH',
          lastSentAt: _now.subtract(const Duration(days: 3)),
          sendCount: 1,
        );
        final gateway = FakeAccountGateway(
          homeState: FakeAccountGateway.account(hasAccount: false),
        );
        final sender = FakeCodeSender();
        final h = await pumpFlowScreen(
          tester,
          () => SignUpFlow(entry: entry),
          prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(left)},
          overrides: _deps(sender, FakeSignUpAuth(verifiesAs: 'uB'), gateway),
        );
        expect(find.text('Enter the code'), findsOneWidget);
        await _tapText(tester, 'Wrong number? Change it');
        await _type(tester, 'Phone number', '244222222');
        await _tapText(tester, 'Text me a code');
        expect(sender.sent.single.$1, '+233244222222');
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();
        await tester.pump(kCodeAcceptedHold);
        await tester.pumpAndSettle();
        expect(find.text('Before you start'), findsNothing);
        expect(find.text('What should we call you?'), findsOneWidget);
        expect(find.text('Adult A'), findsNothing);

        await _type(tester, 'Your name', 'B');
        await _tapText(tester, 'Continue');
        expect(find.text("What's your date of birth?"), findsOneWidget);
        expect(find.text('1990'), findsNothing);
        await _type(tester, 'Day', '1');
        await _type(tester, 'Month', '8');
        await _type(tester, 'Year', '1995');
        await _tapText(tester, 'Continue');
        await _tapText(tester, 'Agree and continue');
        expect(h.location, '/home');
        expect(
          [
            for (final (fn, params) in gateway.calls)
              if (fn == 'complete_sign_up') params!['p_birth_date'],
          ],
          ['1995-08-01'],
        );
      });
    }
  });

  group('review B5 fix round 4 (I-8: A1/A2 are bound to their number)', () {
    var clock = _now;
    setUp(() => clock = _now);

    List<Override> deps(
      FakeCodeSender sender,
      FakeSignUpAuth auth,
      FakeAccountGateway gateway,
    ) => [
      codeSenderProvider.overrideWithValue(sender),
      signUpAuthProvider.overrideWithValue(auth),
      accountServiceProvider.overrideWithValue(AccountService(gateway)),
      signUpClockProvider.overrideWithValue(() => clock),
      deviceCountryProvider.overrideWith(
        (ref) async => (sim: 'GH', region: null),
      ),
      smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
    ];

    List<(Object?, Object?)> sent(FakeAccountGateway gateway) => [
      for (final (fn, params) in gateway.calls)
        if (fn == 'complete_sign_up')
          (params!['p_display_name'], params['p_birth_date']),
    ];

    FakeAccountGateway noAccount() => FakeAccountGateway(
      homeState: FakeAccountGateway.account(hasAccount: false),
    );

    /// Person A, live: A1, A2 (an adult), A3 to number A; now on A4.
    Future<void> aToA4(WidgetTester tester) async {
      await _type(tester, 'Your name', 'Adult A');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '5');
      await _type(tester, 'Month', '5');
      await _type(tester, 'Year', '1990');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Phone number', '244111111');
      await _tapText(tester, 'Text me a code');
      expect(find.text('Enter the code'), findsOneWidget);
    }

    /// "Change it", B's own number, B's code.
    Future<void> bChangesTheNumber(WidgetTester tester) async {
      await _tapText(tester, 'Wrong number? Change it');
      await _type(tester, 'Phone number', '244222222');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
    }

    /// B's own A1 and A2, both shown empty, then A5 and home.
    Future<void> bOwnA1A2ThenA5(WidgetTester tester) async {
      expect(find.text('Before you start'), findsNothing);
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Adult A'), findsNothing);
      await _type(tester, 'Your name', 'B');
      await _tapText(tester, 'Continue');
      expect(find.text("What's your date of birth?"), findsOneWidget);
      expect(find.text('1990'), findsNothing);
      await _type(tester, 'Day', '1');
      await _type(tester, 'Month', '8');
      await _type(tester, 'Year', '1995');
      await _tapText(tester, 'Continue');
      await _tapText(tester, 'Agree and continue');
    }

    for (final entry in [SignUpEntry.newAccount, SignUpEntry.invite]) {
      testWidgets('(e) F1: A leaves the app in the background at A4 (not '
          'closed); days later B changes the number: A1 and A2 are asked, '
          "empty, and only B's date is sent (${entry.wire})", (tester) async {
        final gateway = noAccount();
        final sender = FakeCodeSender();
        final h = await pumpFlowScreen(
          tester,
          () => SignUpFlow(entry: entry),
          overrides: deps(sender, FakeSignUpAuth(verifiesAs: 'uB'), gateway),
        );
        await aToA4(tester);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }
        clock = _now.add(const Duration(days: 3));
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('Enter the code'), findsOneWidget, reason: 'live');

        await bChangesTheNumber(tester);
        await bOwnA1A2ThenA5(tester);
        expect(h.location, '/home');
        expect(sent(gateway), [('B', '1995-08-01')]);
        expect(sender.sent.map((s) => s.$1), [
          '+233244111111',
          '+233244222222',
        ]);
      });
    }

    testWidgets("F2: a resumed A4, \"Change it\", then Back from A3: A2 and "
        "A1 open empty, never with A's date or name; only B's date is "
        'sent', (tester) async {
      final left = SignUpDraft.start(
        SignUpEntry.newAccount,
        now: _now.subtract(const Duration(days: 3)),
      ).copyWith(
        name: 'Adult A',
        birthDate: DateTime.utc(1990, 5, 5),
        phoneE164: '+233244111111',
        countryIso: 'GH',
        lastSentAt: _now.subtract(const Duration(days: 3)),
        sendCount: 1,
      );
      final gateway = noAccount();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(left)},
        overrides: deps(
          FakeCodeSender(),
          FakeSignUpAuth(verifiesAs: 'uB'),
          gateway,
        ),
      );
      expect(find.text('Enter the code'), findsOneWidget);
      await _tapText(tester, 'Wrong number? Change it');
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(find.text('244111111'), findsOneWidget, reason: 'A3 keeps it');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text("What's your date of birth?"), findsOneWidget);
      expect(find.text('1990'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Adult A'), findsNothing);

      await _type(tester, 'Your name', 'B');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '1');
      await _type(tester, 'Month', '8');
      await _type(tester, 'Year', '1995');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Phone number', '244222222');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Agree and continue');
      expect(h.location, '/home');
      expect(sent(gateway), [('B', '1995-08-01')]);
    });

    testWidgets('(g) F3: a deep link into /signup while the flow is on A4 '
        'keeps the flow, and a new number still asks A1 and A2 before A5', (
      tester,
    ) async {
      final gateway = noAccount();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: deps(
          FakeCodeSender(),
          FakeSignUpAuth(verifiesAs: 'uB'),
          gateway,
        ),
      );
      await aToA4(tester);
      h.router.go('/test?entry=invite');
      await tester.pumpAndSettle();
      expect(find.text('Enter the code'), findsOneWidget, reason: 'same flow');

      await bChangesTheNumber(tester);
      await bOwnA1A2ThenA5(tester);
      expect(sent(gateway), [('B', '1995-08-01')]);
    });

    testWidgets('(h) A fixes a typo in the number: A3 shows the number to '
        "fix; after the code A1 and A2 are asked again, empty (the ruled "
        "cost), and A5 sends A's date", (tester) async {
      final gateway = noAccount();
      final sender = FakeCodeSender();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: deps(sender, FakeSignUpAuth(verifiesAs: 'uA'), gateway),
      );
      await _type(tester, 'Your name', 'Adult A');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '5');
      await _type(tester, 'Month', '5');
      await _type(tester, 'Year', '1990');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Phone number', '244111112');
      await _tapText(tester, 'Text me a code');
      await _tapText(tester, 'Wrong number? Change it');
      expect(find.text('244111112'), findsOneWidget);
      await _type(tester, 'Phone number', '244111111');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();

      expect(find.text('Before you start'), findsNothing);
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Adult A'), findsNothing);
      await _type(tester, 'Your name', 'Adult A');
      await _tapText(tester, 'Continue');
      expect(find.text('1990'), findsNothing);
      await _type(tester, 'Day', '5');
      await _type(tester, 'Month', '5');
      await _type(tester, 'Year', '1990');
      await _tapText(tester, 'Continue');
      await _tapText(tester, 'Agree and continue');
      expect(h.location, '/home');
      expect(sent(gateway), [('Adult A', '1990-05-05')]);
      expect(sender.sent.map((s) => s.$1), ['+233244111112', '+233244111111']);
    });

    testWidgets('A5 left open and its session gone: Agree goes to A3, and '
        'Back from there shows no name or date (the M-7 way to A3)', (
      tester,
    ) async {
      final auth = FakeSignUpAuth(userId: 'u1');
      final gateway = noAccount();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {
          SignUpDraftStore.key: jsonEncodeDraft(
            _atCode().copyWith(verifiedUserId: 'u1', accountChecked: true),
          ),
        },
        overrides: deps(FakeCodeSender(), auth, gateway),
      );
      expect(find.text('Before you start'), findsOneWidget);
      auth.userId = null;
      await _tapText(tester, 'Agree and continue');
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(find.text('244123456'), findsOneWidget, reason: 'A3 keeps it');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text("What's your date of birth?"), findsOneWidget);
      expect(find.text('1990'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Ama'), findsNothing);
      expect(sent(gateway), isEmpty);
    });

    testWidgets('A\'s own resume on the same number is untouched: "Change it", '
        'the same number, the code, then A5 at once with A\'s date', (
      tester,
    ) async {
      final gateway = noAccount();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
        overrides: deps(FakeCodeSender(), FakeSignUpAuth(), gateway),
      );
      await _tapText(tester, 'Wrong number? Change it');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Agree and continue');
      expect(h.location, '/home');
      expect(sent(gateway), [('Ama', '1990-01-01')]);
    });
  });

  group('review B5 fix round 5 (unbound A1/A2: memory only)', () {
    var clock = _now;
    setUp(() => clock = _now);

    List<Override> deps(
      FakeCodeSender sender,
      FakeSignUpAuth auth,
      FakeAccountGateway gateway,
    ) => [
      codeSenderProvider.overrideWithValue(sender),
      signUpAuthProvider.overrideWithValue(auth),
      accountServiceProvider.overrideWithValue(AccountService(gateway)),
      signUpClockProvider.overrideWithValue(() => clock),
      deviceCountryProvider.overrideWith(
        (ref) async => (sim: 'GH', region: null),
      ),
      smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
    ];

    FakeAccountGateway noAccount() => FakeAccountGateway(
      homeState: FakeAccountGateway.account(hasAccount: false),
    );

    List<(Object?, Object?)> sent(FakeAccountGateway gateway) => [
      for (final (fn, params) in gateway.calls)
        if (fn == 'complete_sign_up')
          (params!['p_display_name'], params['p_birth_date']),
    ];

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
    }

    /// A types A1 and A2 and is on A3, number typed, nothing sent.
    Future<void> aToA3(WidgetTester tester) async {
      await _type(tester, 'Your name', 'Adult A');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '5');
      await _type(tester, 'Month', '5');
      await _type(tester, 'Year', '1990');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Phone number', '244111111');
    }

    void expectNowhereOnThePhone(SharedPreferences prefs, List<String> what) {
      for (final key in prefs.getKeys()) {
        for (final value in what) {
          expect('${prefs.get(key)}', isNot(contains(value)), reason: key);
        }
      }
    }

    testWidgets("P1: A's send fails at A3 and the phone locks for more than 5 "
        'minutes: A1 opens empty at once (no fading old field), and B\'s '
        "number never receives A's name or date", (tester) async {
      final gateway = noAccount();
      final sender = FakeCodeSender()..failNext = StateError('offline');
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: deps(sender, FakeSignUpAuth(verifiesAs: 'uB'), gateway),
      );
      await aToA3(tester);
      await _tapText(tester, 'Text me a code');
      expect(find.text("What's your phone number?"), findsOneWidget);
      expectNowhereOnThePhone(h.prefs, ['Adult A', '1990-05-05']);

      await away(tester, const Duration(minutes: 6));
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Adult A'), findsNothing, reason: 'not even fading');
      expect(find.text("What's your phone number?"), findsNothing);
      await tester.pumpAndSettle();

      await _type(tester, 'Your name', 'B');
      await _tapText(tester, 'Continue');
      expect(find.text('1990'), findsNothing);
      await _type(tester, 'Day', '1');
      await _type(tester, 'Month', '8');
      await _type(tester, 'Year', '1995');
      await _tapText(tester, 'Continue');
      expect(find.text('244111111'), findsNothing, reason: 'A3 empty too');
      await _type(tester, 'Phone number', '244222222');
      await _tapText(tester, 'Text me a code');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Agree and continue');
      expect(h.location, '/home');
      expect(sent(gateway), [('B', '1995-08-01')]);
    });

    testWidgets('a background under 5 minutes keeps A1 and A2: A3 stays, and '
        "Back shows A's own date", (tester) async {
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: deps(FakeCodeSender(), FakeSignUpAuth(), noAccount()),
      );
      await aToA3(tester);
      await away(tester, const Duration(minutes: 4));
      await tester.pumpAndSettle();
      expect(find.text("What's your phone number?"), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('1990'), findsOneWidget);
    });

    testWidgets('path 6: closed at A3 before any code, then opened again: '
        'A1 is empty', (tester) async {
      final first = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: deps(FakeCodeSender(), FakeSignUpAuth(), noAccount()),
      );
      await aToA3(tester);
      final onThePhone = {
        for (final key in first.prefs.getKeys()) key: first.prefs.get(key)!,
      };
      expect(onThePhone.containsKey(SignUpDraftStore.key), isFalse);

      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: onThePhone,
        overrides: deps(FakeCodeSender(), FakeSignUpAuth(), noAccount()),
      );
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Adult A'), findsNothing);
    });

    testWidgets('"Not now" before any code was sent (signed in already): '
        'nothing at all is left on the phone', (tester) async {
      final gateway = noAccount();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: deps(
          FakeCodeSender(),
          FakeSignUpAuth(userId: 'u1', phone: '+233244123456'),
          gateway,
        ),
      );
      await _type(tester, 'Your name', 'Ama');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '27');
      await _type(tester, 'Month', '3');
      await _type(tester, 'Year', '1996');
      await _tapText(tester, 'Continue');
      expect(find.text('Before you start'), findsOneWidget);
      expectNowhereOnThePhone(h.prefs, ['Ama', '1996-03-27']);
      await _tapText(tester, 'Not now');
      expect(h.location, '/welcome');
      expect(h.prefs.containsKey(SignUpDraftStore.key), isFalse);
      expectNowhereOnThePhone(h.prefs, ['Ama', '1996-03-27']);
      expect(sent(gateway), isEmpty);
    });

    testWidgets('a code sent: a long background keeps A4, and A5 follows '
        "with A's date", (tester) async {
      final gateway = noAccount();
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: deps(FakeCodeSender(), FakeSignUpAuth(), gateway),
      );
      await aToA3(tester);
      await _tapText(tester, 'Text me a code');
      await away(tester, const Duration(hours: 2));
      await tester.pumpAndSettle();
      expect(find.text('Enter the code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      await _tapText(tester, 'Agree and continue');
      expect(h.location, '/home');
      expect(sent(gateway), [('Adult A', '1990-05-05')]);
    });
  });

  group('batch 5 re-review 4 m-1 (set-aside A1/A2 come back only when '
      'nothing was typed since)', () {
    var clock = _now;
    setUp(() => clock = _now);

    List<Override> deps(
      FakeCodeSender sender,
      FakeSignUpAuth auth,
      FakeAccountGateway gateway,
    ) => [
      codeSenderProvider.overrideWithValue(sender),
      signUpAuthProvider.overrideWithValue(auth),
      accountServiceProvider.overrideWithValue(AccountService(gateway)),
      signUpClockProvider.overrideWithValue(() => clock),
      deviceCountryProvider.overrideWith(
        (ref) async => (sim: 'GH', region: null),
      ),
      smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
    ];

    List<(Object?, Object?)> sent(FakeAccountGateway gateway) => [
      for (final (fn, params) in gateway.calls)
        if (fn == 'complete_sign_up')
          (params!['p_display_name'], params['p_birth_date']),
    ];

    /// The phone locked for [time], then back.
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
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    /// B's adult date at A2, then on to A3.
    Future<void> bDate(WidgetTester tester) async {
      expect(find.text("What's your date of birth?"), findsOneWidget);
      await _type(tester, 'Day', '1');
      await _type(tester, 'Month', '8');
      await _type(tester, 'Year', '1995');
      await _tapText(tester, 'Continue');
    }

    /// The flow opened again later from what is on the phone; A enters
    /// A's code. A1 must open empty, and A's own A1/A2 then go to A5.
    Future<void> aResumesAndRetypes(
      WidgetTester tester,
      SharedPreferences prefs,
      FakeSignUpAuth auth,
      FakeAccountGateway gateway,
    ) async {
      final phone = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
      clock = clock.add(const Duration(hours: 5));
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: phone,
        overrides: deps(FakeCodeSender(), auth, gateway),
      );
      expect(find.text('Enter the code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      expect(find.text('Before you start'), findsNothing);
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Adult A'), findsNothing);
      expect(find.text('Bee'), findsNothing);
      await _type(tester, 'Your name', 'Adult A');
      await _tapText(tester, 'Continue');
      expect(find.text('1995'), findsNothing);
      await _type(tester, 'Day', '5');
      await _type(tester, 'Month', '5');
      await _type(tester, 'Year', '1990');
      await _tapText(tester, 'Continue');
      await _tapText(tester, 'Agree and continue');
      expect(h.location, '/home');
      expect(sent(gateway), [('Adult A', '1990-05-05')]);
      expect(auth.currentUserId, 'uA');
    }

    for (final bTypesName in [false, true]) {
      testWidgets('M1: A left at A4; B "Change it", Back, types '
          '${bTypesName ? 'A1 and A2' : 'A2'} and sends the number A3 shows '
          "(A's); A's code later asks A1/A2 again, never B's", (tester) async {
        final gateway = FakeAccountGateway(
          homeState: FakeAccountGateway.account(hasAccount: false),
        );
        final auth = FakeSignUpAuth(verifiesAs: 'uA');
        final h = await pumpFlowScreen(
          tester,
          () => const SignUpFlow(entry: SignUpEntry.newAccount),
          overrides: deps(FakeCodeSender(), auth, gateway),
        );
        await _type(tester, 'Your name', 'Adult A');
        await _tapText(tester, 'Continue');
        await _type(tester, 'Day', '5');
        await _type(tester, 'Month', '5');
        await _type(tester, 'Year', '1990');
        await _tapText(tester, 'Continue');
        await _type(tester, 'Phone number', '244111111');
        await _tapText(tester, 'Text me a code');
        await away(tester, const Duration(hours: 3));
        // B
        await _tapText(tester, 'Wrong number? Change it');
        expect(find.text('244111111'), findsOneWidget, reason: "A's number");
        await back(tester);
        if (bTypesName) {
          await back(tester);
          await _type(tester, 'Your name', 'Bee');
          await _tapText(tester, 'Continue');
        }
        await bDate(tester);
        expect(find.text('244111111'), findsOneWidget);
        await _tapText(tester, 'Text me a code');
        expect(find.text('Enter the code'), findsOneWidget);
        // B can't get A's SMS and leaves; the app is closed. A, later:
        await aResumesAndRetypes(tester, h.prefs, auth, gateway);
      });
    }

    testWidgets("M2: A verified, A's session gone; B opens A3 pre-filled with "
        "A's number, goes Back, types A2 and sends it; A's code later asks "
        "A1/A2 again, never B's", (tester) async {
      final left = SignUpDraft.start(
        SignUpEntry.newAccount,
        now: _now.subtract(const Duration(hours: 30)),
      ).copyWith(
        name: 'Adult A',
        birthDate: DateTime.utc(1990, 5, 5),
        phoneE164: '+233244111111',
        countryIso: 'GH',
        lastSentAt: _now.subtract(const Duration(hours: 30)),
        sendCount: 1,
        verifiedUserId: 'uA-old',
        accountChecked: true,
      );
      final gateway = FakeAccountGateway(
        homeState: FakeAccountGateway.account(hasAccount: false),
      );
      final auth = FakeSignUpAuth(verifiesAs: 'uA');
      final h = await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(left)},
        overrides: deps(FakeCodeSender(), auth, gateway),
      );
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(find.text('244111111'), findsOneWidget);
      await back(tester);
      await bDate(tester);
      await _tapText(tester, 'Text me a code');
      expect(find.text('Enter the code'), findsOneWidget);
      await aResumesAndRetypes(tester, h.prefs, auth, gateway);
    });
  });

  // Final review M-1: a blocked device signs in to an account it already
  // has, but a number with no account never reaches N1's "Create an
  // account": X1, signed out, nothing kept, and the block not restarted.
  testWidgets('M-1: blocked, "I already have an account", a number with no '
      'account: X1, never N1', (tester) async {
    final until = DateTime.now().toUtc().add(const Duration(days: 3));
    final auth = FakeSignUpAuth();
    final gateway = FakeAccountGateway(
      homeState: FakeAccountGateway.account(hasAccount: false),
    );
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      prefsValues: {AgeGateStore.blockUntilKey: until.toIso8601String()},
      overrides: _deps(FakeCodeSender(), auth, gateway),
    );
    await _type(tester, 'Phone number', '244123456');
    await _tapText(tester, 'Text me a code');
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(h.location, '/age-stop');
    expect(
      find.text("We couldn't find an Attune account for this number"),
      findsNothing,
    );
    expect(auth.signOuts, 1);
    expect(auth.userId, isNull);
    expect(SignUpDraftStore.readFrom(h.prefs, _now), isNull);
    expect(
      h.prefs.getString(AgeGateStore.blockUntilKey),
      until.toIso8601String(),
      reason: 'the block in force is kept as it is, not restarted',
    );
    expect(gateway.count('complete_sign_up'), 0);
  });

  // Owner 2026-11-26: the path chosen on Welcome is set once A5 has made
  // the account, and A6 is never asked for it.
  group('the path chosen on Welcome', () {
    /// A4 (a resumed draft), the code, then A5's Agree.
    Future<FlowHarness> agree(
      WidgetTester tester, {
      AppPath? path,
      required FakeHomeStateGateway home,
      FakeAccountGateway? gateway,
      Map<String, Object> prefsValues = const {},
      List<Override> overrides = const [],
    }) async {
      final h = await pumpFlowScreen(
        tester,
        () => SignUpFlow(entry: SignUpEntry.newAccount, path: path),
        prefsValues: {
          SignUpDraftStore.key: jsonEncodeDraft(_atCode()),
          ...prefsValues,
        },
        overrides: [
          ...overrides,
          ..._deps(
            FakeCodeSender(),
            FakeSignUpAuth(),
            gateway ??
                FakeAccountGateway(
                  homeState: FakeAccountGateway.account(hasAccount: false),
                ),
          ),
          homeStateServiceProvider.overrideWithValue(HomeStateService(home)),
        ],
      );
      expect(find.text('Enter the code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      expect(find.text('Before you start'), findsOneWidget);
      await _tapText(tester, 'Agree and continue');
      return h;
    }

    OnboardingStore store(FlowHarness h) =>
        OnboardingStore(h.prefs, scope: 'user.u1');

    for (final (path, wire, target) in [
      (AppPath.relationship, 'relationship', '/invite-partner'),
      (AppPath.dating, 'dating', '/home'),
      (AppPath.justMe, 'just_me', '/home'),
    ]) {
      testWidgets('${path.name}: set as A6 sets it, then $target', (
        tester,
      ) async {
        final home = FakeHomeStateGateway(state: homeJson(path: wire));
        final h = await agree(tester, path: path, home: home);
        expect(home.calls.where((c) => c.$1 == 'set_my_path').single.$2, {
          'p_path': wire,
          'p_confirmed': false,
        });
        expect(h.location, target);
        expect(store(h).pendingPath, isNull);
      });
    }

    testWidgets('no path (the returning way, invites): home, nothing set', (
      tester,
    ) async {
      final home = FakeHomeStateGateway();
      final h = await agree(tester, home: home);
      expect(home.calls, isEmpty);
      expect(h.location, '/home');
    });

    for (final path in [AppPath.relationship, AppPath.justMe]) {
      testWidgets('${path.name}, set_my_path offline: queued for the '
          'replay, home', (tester) async {
        final home = FakeHomeStateGateway()
          ..failAlways = TimeoutException('offline');
        final h = await agree(tester, path: path, home: home);
        expect(home.count('set_my_path'), 1);
        expect(store(h).pendingPath, path);
        expect(h.location, '/home', reason: 'R1 needs the account online');
      });
    }

    testWidgets('dating, set_my_path offline: nothing queued (D20), home', (
      tester,
    ) async {
      final home = FakeHomeStateGateway()
        ..failAlways = TimeoutException('offline');
      final h = await agree(tester, path: AppPath.dating, home: home);
      expect(store(h).pendingPath, isNull);
      expect(h.location, '/home');
      expect(h.prefs.getKeys().any((k) => k.contains('dating')), isFalse);
    });

    // Fix round M-1: a path the server refused is never queued (its replay
    // would be refused too); home, where the gate asks A6.
    for (final refusal in ['path:invalid', 'path:relationship_open']) {
      testWidgets('a refusal ($refusal) never undoes the account: nothing '
          'queued, home', (tester) async {
        final home = FakeHomeStateGateway()
          ..failAlways = FakeHomeStateGateway.refusal(refusal);
        final gateway = FakeAccountGateway(
          homeState: FakeAccountGateway.account(hasAccount: false),
        );
        final h = await agree(
          tester,
          path: AppPath.justMe,
          home: home,
          gateway: gateway,
        );
        expect(gateway.count('complete_sign_up'), 1);
        expect(store(h).pendingPath, isNull);
        expect(h.location, '/home');
      });
    }

    testWidgets('path:needs_signup (the account not ready yet): queued, '
        'home', (tester) async {
      final home = FakeHomeStateGateway()
        ..failAlways = FakeHomeStateGateway.refusal('path:needs_signup');
      final h = await agree(tester, path: AppPath.relationship, home: home);
      expect(store(h).pendingPath, AppPath.relationship);
      expect(h.location, '/home');
    });

    // Fix round M-7: the path is in the home state before home opens, so
    // the gate has nothing to ask (no A6).
    testWidgets('after a set the home state holds the path, no A6 need', (
      tester,
    ) async {
      final home = FakeHomeStateGateway(state: homeJson(path: 'just_me'));
      final h = await agree(tester, path: AppPath.justMe, home: home);
      expect(h.location, '/home');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final snapshot = container.read(homeStateProvider('u1'));
      expect(snapshot.path, AppPath.justMe);
      expect(snapshot.needs, isNot(contains(HomeNeed.path)));
      expect(snapshot.isComplete, isTrue);
    });

    // Fix round I-1: a partner's invite is waiting: never R1 ("Create my
    // invite"); where the gate goes with a stored invite.
    for (final (couplesV2, target) in [
      (true, '/join-invite'),
      (false, '/home'),
    ]) {
      testWidgets('relationship with a stored invite, flow_couples_v2 '
          '$couplesV2: $target, never R1', (tester) async {
        final home = FakeHomeStateGateway(state: homeJson(path: 'relationship'));
        final h = await agree(
          tester,
          path: AppPath.relationship,
          home: home,
          prefsValues: {
            'attune.onboarding.anonymous.pending_invite':
                '{"code":"K7P2QM","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}',
          },
          overrides: [flowCouplesV2Provider.overrideWithValue(couplesV2)],
        );
        expect(home.count('set_my_path'), 1);
        expect(h.location, target);
        expect(store(h).pendingInviteCode, 'K7P2QM', reason: 'kept for RI-3');
      });
    }

    for (final (path, queued) in [
      (AppPath.relationship, AppPath.relationship),
      (AppPath.justMe, AppPath.justMe),
      (AppPath.dating, null),
    ]) {
      testWidgets('${path.name} with the account only queued: no call, '
          '${queued == null ? 'nothing' : 'the path'} queued, home', (
        tester,
      ) async {
        final home = FakeHomeStateGateway();
        final gateway = FakeAccountGateway(
          homeState: FakeAccountGateway.account(hasAccount: false),
        );
        final h = await pumpFlowScreen(
          tester,
          () => SignUpFlow(entry: SignUpEntry.newAccount, path: path),
          prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
          overrides: [
            ..._deps(FakeCodeSender(), FakeSignUpAuth(), gateway),
            homeStateServiceProvider.overrideWithValue(HomeStateService(home)),
          ],
        );
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();
        await tester.pump(kCodeAcceptedHold);
        await tester.pumpAndSettle();
        gateway.failWith = TimeoutException('offline');
        await _tapText(tester, 'Agree and continue');
        expect(store(h).pendingSignUp, isNotNull);
        expect(home.calls, isEmpty);
        expect(store(h).pendingPath, queued);
        expect(h.location, '/home');
      });
    }
  });

  // Fix round M-4: the way in's own back (the intro's "I already have an
  // account" passes /start) is where A3's Back and A5's Not now go.
  testWidgets('with back=/start, A3 Back and A5 Not now go to the intro', (
    tester,
  ) async {
    final h = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(
        entry: SignUpEntry.returning,
        backTo: RouteNames.start,
      ),
      overrides: _deps(FakeCodeSender(), FakeSignUpAuth(), FakeAccountGateway()),
    );
    expect(find.text("What's your phone number?"), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(h.location, '/start');

    final auth = FakeSignUpAuth();
    final h2 = await pumpFlowScreen(
      tester,
      () => const SignUpFlow(
        entry: SignUpEntry.newAccount,
        backTo: RouteNames.start,
      ),
      prefsValues: {SignUpDraftStore.key: jsonEncodeDraft(_atCode())},
      overrides: _deps(
        FakeCodeSender(),
        auth,
        FakeAccountGateway(
          homeState: FakeAccountGateway.account(hasAccount: false),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(kCodeAcceptedHold);
    await tester.pumpAndSettle();
    await _tapText(tester, 'Not now');
    expect(auth.signOuts, 1);
    expect(h2.location, '/start');
  });

  // Owner 2026-11-26: A3's quiet "Read Opinions first", for a new account
  // past A2's adult check.
  group('A3 Read Opinions first', () {
    const line = 'Not ready to share your number? Read Opinions first.';

    Future<FlowHarness> toPhone(
      WidgetTester tester,
      SignUpEntry entry, {
      RoutingNotifier? routing,
      Map<String, Object> prefsValues = const {},
      List<Override> overrides = const [],
    }) async {
      final h = await pumpFlowScreen(
        tester,
        () => SignUpFlow(entry: entry),
        routing: routing ?? RoutingNotifier(flowV2: true),
        prefsValues: prefsValues,
        overrides: [
          ..._deps(FakeCodeSender(), FakeSignUpAuth(), FakeAccountGateway()),
          ...overrides,
        ],
      );
      await _type(tester, 'Your name', 'Ama');
      await _tapText(tester, 'Continue');
      await _type(tester, 'Day', '27');
      await _type(tester, 'Month', '3');
      await _type(tester, 'Year', '1996');
      await _tapText(tester, 'Continue');
      expect(find.text("What's your phone number?"), findsOneWidget);
      return h;
    }

    testWidgets('a new account: the guest pass with A2\'s year, then home', (
      tester,
    ) async {
      final h = await toPhone(tester, SignUpEntry.newAccount);
      expect(find.text(line), findsOneWidget);
      expect(AgeGateStore.readGuestOk(h.prefs), isFalse);
      await _tapText(tester, line);
      expect(AgeGateStore.readGuestOk(h.prefs), isTrue);
      expect(h.routing.guestAgeOk, isTrue);
      expect(await AgeGateStore(h.prefs).guestBirthYear(), 1996);
      expect(h.location, '/home');
    });

    // Fix round M-2.
    testWidgets('a phone already holding the guest pass never offers it', (
      tester,
    ) async {
      await toPhone(
        tester,
        SignUpEntry.newAccount,
        routing: RoutingNotifier(flowV2: true, guestAgeOk: true),
      );
      expect(find.text(line), findsNothing);
    });

    testWidgets('a blocked phone never offers it', (tester) async {
      await toPhone(
        tester,
        SignUpEntry.newAccount,
        routing: RoutingNotifier(flowV2: true, underAgeBlocked: true),
      );
      expect(find.text(line), findsNothing);
    });

    testWidgets('a pass that cannot be saved stays on A3 with the error', (
      tester,
    ) async {
      final h = await toPhone(
        tester,
        SignUpEntry.newAccount,
        overrides: [
          ageGateStoreProvider.overrideWith(
            (ref) => _PassFails(ref.watch(sharedPreferencesProvider)),
          ),
        ],
      );
      await _tapText(tester, line);
      expect(tester.takeException(), isNull);
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(find.text("We couldn't save that. Try again."), findsOneWidget);
      expect(h.routing.guestAgeOk, isFalse);
      expect(h.location, isNot('/home'));
    });

    testWidgets('an invite never offers it', (tester) async {
      await toPhone(tester, SignUpEntry.invite);
      expect(find.text(line), findsNothing);
    });

    testWidgets('the returning way (no date of birth) never offers it', (
      tester,
    ) async {
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(
          FakeCodeSender(),
          FakeSignUpAuth(),
          FakeAccountGateway(),
        ),
      );
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(find.text(line), findsNothing);
    });

    testWidgets('A3 with the line meets the guidelines', (tester) async {
      final semantics = tester.ensureSemantics();
      await toPhone(tester, SignUpEntry.newAccount);
      await expectFlowGuidelines(tester);
      semantics.dispose();
    });
  });
}

/// Fix round M-2: the guest pass can't be written.
class _PassFails extends AgeGateStore {
  _PassFails(super.prefs);

  @override
  Future<void> passGuestGate(int year) async => throw StateError('disk full');
}

String jsonEncodeDraft(SignUpDraft draft) =>
    const JsonEncoder().convert(draft.toJson());
