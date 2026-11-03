// Spec 1 W6a (§3.5 DM1-DM2, §3.15 H1, §2.2, §2.3; W3 carry C-2): /signup
// when the access-token hook refused the code. DM1 -> the fresh start ->
// DM2 -> a new code -> A5; H1 with the phone blocked for an age hold only;
// none of it animated; goldens at 1.0, 1.3, 2.0 and right to left.
//   flutter test --update-goldens test/features/auth/sign_up/w6/sign_up_dormancy_flow_test.dart
import 'dart:convert';

import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/ui/motion/shared_axis_step.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/fresh_start_service.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/dormant_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/fresh_start_step.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../helpers/fake_account_gateway.dart';
import '../../../../helpers/fake_sign_up.dart';
import '../../../../helpers/flow_harness.dart';
import 'sign_up_dormancy_test.dart' show FakeFreshStart;

final _now = DateTime.utc(2026, 11, 3, 12);
final _nonce = 'cd' * 64;

SignUpDraft _atCode({SignUpEntry entry = SignUpEntry.newAccount}) =>
    SignUpDraft.start(entry, now: _now).copyWith(
      name: entry == SignUpEntry.newAccount ? 'Ama' : null,
      birthDate:
          entry == SignUpEntry.newAccount ? DateTime.utc(1990, 1, 1) : null,
      phoneE164: '+233244123456',
      countryIso: 'GH',
      lastSentAt: _now,
      sendCount: 1,
    );

class _Rig {
  final sender = FakeCodeSender();
  final auth = FakeSignUpAuth();
  final gateway = FakeAccountGateway(
    homeState: FakeAccountGateway.account(hasAccount: false),
  );
  final fresh = FakeFreshStart();

  List<Override> get overrides => [
    codeSenderProvider.overrideWithValue(sender),
    signUpAuthProvider.overrideWithValue(auth),
    accountServiceProvider.overrideWithValue(AccountService(gateway)),
    signUpClockProvider.overrideWithValue(() => _now),
    deviceCountryProvider.overrideWith(
      (ref) async => (sim: 'GH', region: null),
    ),
    smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
    freshStartGatewayProvider.overrideWithValue(fresh),
  ];
}

Future<FlowHarness> _pumpAtCode(
  WidgetTester tester,
  _Rig rig, {
  SignUpEntry entry = SignUpEntry.newAccount,
}) => pumpFlowScreen(
  tester,
  () => SignUpFlow(entry: entry),
  prefsValues: {
    SignUpDraftStore.key: const JsonEncoder().convert(
      _atCode(entry: entry).toJson(),
    ),
  },
  overrides: rig.overrides,
);

Future<void> _enterCode(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '123456');
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('DM1 -> "I\'m new to Attune" -> DM2 -> a new code -> A5', (
    tester,
  ) async {
    final rig = _Rig();
    rig.auth.failVerifyWith = AuthException(
      'account_dormant:$_nonce',
      statusCode: '403',
    );
    await _pumpAtCode(tester, rig);
    await _enterCode(tester);

    expect(find.text('Welcome to Attune'), findsOneWidget);
    expect(find.text("Let's get you set up."), findsOneWidget);
    expect(
      find.text('Used Attune before on this number? Contact support'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Ama'),
      findsNothing,
      reason: 'nothing about any account is shown',
    );
    expect(
      find.byType(SharedAxisStep),
      findsNothing,
      reason: 'DM1 is never animated',
    );

    await tester.tap(find.text("I'm new to Attune"));
    await tester.pumpAndSettle();
    expect(rig.fresh.nonces, [_nonce]);
    expect(find.text('One more code to finish'), findsOneWidget);
    expect(
      find.text("We'll send a new code to +233 24 412 3456."),
      findsOneWidget,
    );
    expect(
      find.byType(SharedAxisStep),
      findsNothing,
      reason: 'DM2 is never animated',
    );

    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(rig.sender.sent.last.$1, '+233244123456');
    expect(find.text('Enter the code'), findsOneWidget);

    rig.auth
      ..failVerifyWith = null
      ..verifiesAs = 'u-new';
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Before you start'), findsOneWidget);
  });

  testWidgets('DM1 offline: said, and the same challenge is tried again', (
    tester,
  ) async {
    final rig = _Rig()..fresh.results.add(FreshStartResult.unavailable);
    rig.auth.failVerifyWith = AuthException(
      'account_dormant:$_nonce',
      statusCode: '403',
    );
    await _pumpAtCode(tester, rig);
    await _enterCode(tester);
    await tester.tap(find.text("I'm new to Attune"));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "We couldn't reach Attune. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    expect(find.text('Welcome to Attune'), findsOneWidget);
    await tester.tap(find.text("I'm new to Attune"));
    await tester.pumpAndSettle();
    expect(rig.fresh.nonces, [_nonce, _nonce]);
    expect(find.text('One more code to finish'), findsOneWidget);
  });

  testWidgets('DM1 with a spent challenge: back to A3, said', (tester) async {
    final rig = _Rig()..fresh.results.add(FreshStartResult.invalid);
    rig.auth.failVerifyWith = AuthException(
      'account_dormant:$_nonce',
      statusCode: '403',
    );
    await _pumpAtCode(tester, rig);
    await _enterCode(tester);
    await tester.tap(find.text("I'm new to Attune"));
    await tester.pumpAndSettle();
    expect(find.text("What's your phone number?"), findsOneWidget);
    expect(
      find.text('That took too long. Enter your number again.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'an age hold at sign-in: H1 and this phone blocked (W3 carry C-2)',
    (tester) async {
      final rig = _Rig();
      rig.auth.failVerifyWith = const AuthException(
        'account_review:age',
        statusCode: '403',
      );
      final h = await _pumpAtCode(tester, rig, entry: SignUpEntry.returning);
      await _enterCode(tester);
      expect(find.text('We need to check your account'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);
      expect(
        find.byType(SharedAxisStep),
        findsNothing,
        reason: 'H1 is never animated',
      );
      expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
      expect(h.routing.underAgeBlocked, isTrue);
      expect(SignUpDraftStore.readFrom(h.prefs, _now), isNull);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(h.location, '/welcome');
    },
  );

  testWidgets('a safety hold at sign-in: H1, and this phone is not blocked', (
    tester,
  ) async {
    final rig = _Rig();
    rig.auth.failVerifyWith = const AuthException(
      'account_review',
      statusCode: '403',
    );
    final h = await _pumpAtCode(tester, rig, entry: SignUpEntry.returning);
    await _enterCode(tester);
    expect(find.text('We need to check your account'), findsOneWidget);
    expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isFalse);
    expect(h.routing.underAgeBlocked, isFalse);
    expect(
      find.text("That code didn't work. Check it and try again."),
      findsNothing,
    );
  });

  testWidgets('DM1 and DM2 meet the guidelines', (tester) async {
    await pumpFlowScreen(tester, () => DormantStep(onNew: () {}));
    await expectFlowGuidelines(tester);
    await pumpFlowScreen(
      tester,
      () => FreshStartStep(phoneE164: '+233244123456', onSend: () {}),
    );
    await expectFlowGuidelines(tester);
  });

  testWidgets('DM1 goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_dormant',
      () => DormantStep(onNew: () {}),
    );
  });

  testWidgets('DM1 with its error, goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_dormant_error',
      () => DormantStep(
        onNew: () {},
        errorText:
            "We couldn't reach Attune. Check your connection and try again.",
      ),
    );
  });

  testWidgets('DM2 goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_fresh_start',
      () => FreshStartStep(phoneE164: '+233244123456', onSend: () {}),
    );
  });
}
