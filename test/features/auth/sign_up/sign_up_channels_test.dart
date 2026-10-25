// Spec 1 W2c (§3.3 A3/A4, §4.5): the delivery intent before every code,
// WhatsApp, Android autofill, and the iOS domain-bound code. Voice is
// hard-disabled on the server in W2 (batch 7 M-4), so A4 never offers a call.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/otp_delivery_service.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_account_gateway.dart';
import '../../../helpers/fake_sign_up.dart';
import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
final _ghana = PhoneCountries.all.firstWhere((c) => c.isoCode == 'GH');

class _Auth extends PasswordlessAuthService {
  _Auth({this.configured = true});

  final bool configured;
  final asked = <String>[];

  @override
  Future<PasswordlessAuthResult> requestPhoneOtp(
    String phoneNumber, {
    OtpChannel channel = OtpChannel.sms,
  }) async {
    asked.add('$phoneNumber/${channel.name}');
    return PasswordlessAuthResult(isConfigured: configured);
  }
}

/// Supabase's functions client, recording which function was called.
class _Functions implements FunctionsClient {
  final calls = <(String, Object?)>[];

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<http.MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
  }) async {
    calls.add((functionName, body));
    return FunctionResponse(status: 204);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _deps(
  FakeCodeSender sender,
  FakeSmsCodeListener listener, {
  Map<String, dynamic>? home,
  FakeSignUpAuth? auth,
  DateTime Function()? clock,
}) => [
  codeSenderProvider.overrideWithValue(sender),
  signUpAuthProvider.overrideWithValue(auth ?? FakeSignUpAuth()),
  accountServiceProvider.overrideWithValue(
    AccountService(
      FakeAccountGateway(
        homeState: home ?? FakeAccountGateway.account(hasAccount: false),
      ),
    ),
  ),
  signUpClockProvider.overrideWithValue(clock ?? () => _now),
  deviceCountryProvider.overrideWith((ref) async => (sim: 'GH', region: null)),
  smsCodeListenerProvider.overrideWithValue(listener),
];

/// A draft with a code on its way to Ama's number: the flow opens at A4.
SignUpDraft _atCode({required int sendCount, DateTime? lastSentAt}) =>
    SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
      name: 'Ama',
      birthDate: DateTime.utc(1990, 1, 1),
      phoneE164: '+233244123456',
      countryIso: 'GH',
      lastSentAt: lastSentAt ?? _now,
      sendCount: sendCount,
    );

Map<String, Object> _saved(SignUpDraft draft) => {
  SignUpDraftStore.key: jsonEncode(draft.toJson()),
};

/// "Get started" to A3, through A1 and A2: only the way to a new account
/// offers WhatsApp (final review I-2: an existing account's code always
/// goes by SMS).
Future<void> _newAccountToA3(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Ama');
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  for (final (label, value) in [
    ('Day', '5'),
    ('Month', '5'),
    ('Year', '1990'),
  ]) {
    await tester.enterText(find.widgetWithText(TextField, label), value);
    await tester.pump();
  }
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  expect(find.text("What's your phone number?"), findsOneWidget);
}

void main() {
  group('W2c: the three accessibility guidelines (review B8 I-1)', () {
    CodeStep code({
      String lastChannel = 'sms',
      String? noticeText,
      FutureOr<void> Function()? onCallMe,
    }) => CodeStep(
      phoneE164: '+233244123456',
      lastSentAt: _now.subtract(const Duration(minutes: 3)),
      sendCount: 3,
      now: () => _now,
      lastChannel: lastChannel,
      noticeText: noticeText,
      noticeCount: noticeText == null ? 0 : 1,
      onCode: (_) {},
      onResend: () {},
      onChangeNumber: () {},
      onTryWhatsApp: () {},
      onCallMe: onCallMe,
    );

    final screens =
        <String, (Widget Function(), Future<void> Function(WidgetTester)?)>{
          'A3 with WhatsApp': (
            () => PhoneStep(
              initialCountry: _ghana,
              initialNational: '244123456',
              onSend: (_, __) {},
              onSendWhatsApp: (_, __) {},
              onBack: () {},
            ),
            null,
          ),
          'A3 WhatsApp question': (
            () => PhoneStep(
              initialCountry: _ghana,
              initialNational: '244123456',
              onSend: (_, __) {},
              onSendWhatsApp: (_, __) {},
              onBack: () {},
            ),
            (tester) async {
              await tester.tap(find.text('Send by WhatsApp instead'));
              await tester.pumpAndSettle();
              expect(
                find.text('Is WhatsApp on +233 24 412 3456?'),
                findsOneWidget,
              );
            },
          ),
          'A4 after the second resend, Try WhatsApp': (code, null),
          'A4 "Try WhatsApp" refused, the notice': (
            () => code(
              noticeText: "We couldn't send a code. Try again or try WhatsApp.",
            ),
            null,
          ),
          'A4 the calling line (plumbing, unused in W2)': (
            () => code(lastChannel: 'voice', onCallMe: () {}),
            null,
          ),
        };
    for (final MapEntry(key: name, value: (screen, before))
        in screens.entries) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$name at $scale', (tester) async {
          final semantics = tester.ensureSemantics();
          await pumpFlowScreen(tester, screen, textScale: scale);
          if (before != null) await before(tester);
          await expectFlowGuidelines(tester);
          semantics.dispose();
        });
      }
    }
  });

  group('OtpDeliveryService', () {
    test('the intent goes first, then the code, always asked as SMS', () async {
      final order = <String>[];
      final auth = _Auth();
      final service = OtpDeliveryService(
        postIntent: (body) async => order.add('intent ${jsonEncode(body)}'),
        auth: auth,
        platform: () => 'android',
        locale: () => 'en-GH',
      );
      await service.send(
        phoneE164: '+233244123456',
        channel: 'whatsapp',
        deviceNonce: 'n' * 22,
      );
      expect(order.single, contains('"channel":"whatsapp"'));
      expect(order.single, contains('"device_nonce":"${'n' * 22}"'));
      expect(order.single, contains('"platform":"android"'));
      expect(order.single, contains('"locale":"en-GH"'));
      expect(order.single, contains('"phone":"+233244123456"'));
      expect(auth.asked, ['+233244123456/sms']);
    });

    test('a failed or slow intent never stops the code', () async {
      final auth = _Auth();
      await OtpDeliveryService(
        postIntent: (_) => Future.error(Exception('down')),
        auth: auth,
        platform: () => 'ios',
        locale: () => 'en',
      ).send(
        phoneE164: '+447911123456',
        channel: 'voice',
        deviceNonce: 'n' * 22,
      );
      expect(auth.asked, ['+447911123456/sms']);
    });

    testWidgets('an intent that never answers waits 4 s at most', (
      tester,
    ) async {
      final auth = _Auth();
      var done = false;
      unawaited(
        OtpDeliveryService(
              postIntent: (_) => Completer<void>().future,
              auth: auth,
              platform: () => 'android',
              locale: () => 'en',
            )
            .send(
              phoneE164: '+233244123456',
              channel: 'sms',
              deviceNonce: 'n' * 22,
            )
            .then((_) => done = true),
      );
      await tester.pump(const Duration(milliseconds: 3900));
      expect(auth.asked, isEmpty, reason: 'still waiting for the intent');
      await tester.pump(const Duration(milliseconds: 200));
      expect(auth.asked, ['+233244123456/sms']);
      expect(done, isTrue);
    });

    test('phone sign-in switched off reads as such', () async {
      final service = OtpDeliveryService(
        postIntent: (_) async {},
        auth: _Auth(configured: false),
        platform: () => 'ios',
        locale: () => 'en',
      );
      expect(
        () => service.send(
          phoneE164: '+447911123456',
          channel: 'sms',
          deviceNonce: 'x',
        ),
        throwsA(
          isA<AuthException>().having((e) => e.code, 'code', 'otp_disabled'),
        ),
      );
    });

    test('the intent goes to otp-delivery-intent, the function that exists and '
        'config.toml opens (review B8 n-1)', () async {
      final functions = _Functions();
      final body = {'phone': '+233244123456'};
      await functionsIntentPoster(() => functions)(body);
      expect(functions.calls.single.$1, 'otp-delivery-intent');
      expect(functions.calls.single.$2, body);
      expect(otpDeliveryIntentFunction, 'otp-delivery-intent');
      expect(
        File(
          'supabase/functions/$otpDeliveryIntentFunction/index.ts',
        ).existsSync(),
        isTrue,
      );
    });

    test('platform names', () {
      expect(OtpDeliveryService.platformName(TargetPlatform.iOS), 'ios');
      expect(
        OtpDeliveryService.platformName(TargetPlatform.android),
        'android',
      );
      expect(OtpDeliveryService.platformName(TargetPlatform.macOS), 'other');
    });
  });

  test(
    'iOS never listens for an SMS; it fills from the domain-bound line',
    () async {
      expect(
        await SmartAuthCodeListener(platform: TargetPlatform.iOS).next(),
        isNull,
      );
      final entitlements =
          File('ios/Runner/Runner.entitlements').readAsStringSync();
      expect(
        entitlements,
        contains('<string>webcredentials:invite.attune.barsopus.com</string>'),
      );
      expect(
        entitlements,
        contains('<string>applinks:invite.attune.barsopus.com</string>'),
      );
    },
  );

  test('the phone number is never printed (spec §5.2)', () {
    final source =
        File(
          'lib/features/auth/data/passwordless_auth_service.dart',
        ).readAsStringSync();
    expect(source, isNot(contains('signInWithOtp phone=')));
  });

  test('both functions are public to their callers, not JWT-checked', () {
    final config = File('supabase/config.toml').readAsStringSync();
    expect(
      config,
      contains('[functions.$otpDeliveryIntentFunction]\nverify_jwt = false'),
    );
    expect(config, contains('[functions.send-sms-hook]\nverify_jwt = false'));
    expect(
      RegExp(r'^\[auth\.hook', multiLine: true).hasMatch(config),
      isFalse,
      reason: 'the hook is switched on in the dashboard, never from this file',
    );
  });

  testWidgets(
    'A3: "Send by WhatsApp instead" asks first, then sends by WhatsApp',
    (tester) async {
      final sender = FakeCodeSender();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(sender, FakeSmsCodeListener()),
      );
      await _newAccountToA3(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'),
        '244123456',
      );
      await tester.tap(find.text('Send by WhatsApp instead'));
      await tester.pumpAndSettle();
      expect(find.text('Is WhatsApp on +233 24 412 3456?'), findsOneWidget);
      expect(sender.sent, isEmpty, reason: 'nothing before the answer');
      await tester.tap(find.text('Yes, send it to WhatsApp'));
      await tester.pumpAndSettle();
      expect(sender.sent.single.$2, 'whatsapp');
      expect(find.text('Enter the code'), findsOneWidget);
    },
  );

  group('the WhatsApp question never outlives its number (review B8 m-2)', () {
    var clock = _now;
    setUp(() => clock = _now);

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

    testWidgets('the restart after more than 5 minutes away closes it', (
      tester,
    ) async {
      final sender = FakeCodeSender();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(sender, FakeSmsCodeListener(), clock: () => clock),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'A');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      for (final (label, value) in [
        ('Day', '5'),
        ('Month', '5'),
        ('Year', '1990'),
      ]) {
        await tester.enterText(find.widgetWithText(TextField, label), value);
        await tester.pump();
      }
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'),
        '244111111',
      );
      await tester.tap(find.text('Send by WhatsApp instead'));
      await tester.pumpAndSettle();
      expect(find.text('Is WhatsApp on +233 24 411 1111?'), findsOneWidget);

      await away(tester, const Duration(minutes: 6));
      expect(find.text('Is WhatsApp on +233 24 411 1111?'), findsNothing);
      expect(find.text('Yes, send it to WhatsApp'), findsNothing);
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(sender.sent, isEmpty);
    });

    testWidgets('asked again for a changed number, never the one before', (
      tester,
    ) async {
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        overrides: _deps(FakeCodeSender(), FakeSmsCodeListener()),
      );
      await _newAccountToA3(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'),
        '244111111',
      );
      await tester.tap(find.text('Send by WhatsApp instead'));
      await tester.pumpAndSettle();
      expect(find.text('Is WhatsApp on +233 24 411 1111?'), findsOneWidget);
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'),
        '244222222',
      );
      await tester.tap(find.text('Send by WhatsApp instead'));
      await tester.pumpAndSettle();
      expect(find.text('Is WhatsApp on +233 24 422 2222?'), findsOneWidget);
      expect(find.textContaining('411 1111'), findsNothing);
    });
  });

  testWidgets('A3: "No, text me" sends by SMS', (tester) async {
    final sender = FakeCodeSender();
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      overrides: _deps(sender, FakeSmsCodeListener()),
    );
    await _newAccountToA3(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '244123456',
    );
    await tester.tap(find.text('Send by WhatsApp instead'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, text me'));
    await tester.pumpAndSettle();
    expect(sender.sent.single.$2, 'sms');
  });

  testWidgets('A3: the WhatsApp question dismissed sends nothing', (
    tester,
  ) async {
    final sender = FakeCodeSender();
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      overrides: _deps(sender, FakeSmsCodeListener()),
    );
    await _newAccountToA3(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '244123456',
    );
    await tester.tap(find.text('Send by WhatsApp instead'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.text('Is WhatsApp on +233 24 412 3456?'), findsNothing);
    expect(sender.sent, isEmpty);
    expect(find.text("What's your phone number?"), findsOneWidget);
  });

  testWidgets(
    'A4: after the second resend, "Try WhatsApp" and never a call (voice is '
    'off in W2); it resends by WhatsApp',
    (tester) async {
      final sender = FakeCodeSender();
      final draft = SignUpDraft.start(
        SignUpEntry.newAccount,
        now: _now,
      ).copyWith(
        phoneE164: '+233244123456',
        countryIso: 'GH',
        lastSentAt: _now.subtract(const Duration(minutes: 5)),
        sendCount: 3,
      );
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: _saved(draft),
        overrides: _deps(sender, FakeSmsCodeListener()),
      );
      expect(find.text('Send a new code'), findsOneWidget);
      expect(find.text('Try WhatsApp'), findsOneWidget);
      expect(find.text('Call me with the code'), findsNothing);
      await tester.tap(find.text('Try WhatsApp'));
      await tester.pumpAndSettle();
      expect(sender.sent.single.$2, 'whatsapp');
      expect(find.text('Call me with the code'), findsNothing);
      expect(find.textContaining("We're calling"), findsNothing);
    },
  );

  testWidgets('A4: before the second resend there are no other channels', (
    tester,
  ) async {
    final draft = SignUpDraft.start(SignUpEntry.newAccount, now: _now).copyWith(
      phoneE164: '+233244123456',
      lastSentAt: _now.subtract(const Duration(minutes: 5)),
      sendCount: 2,
    );
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: _saved(draft),
      overrides: _deps(FakeCodeSender(), FakeSmsCodeListener()),
    );
    expect(find.text('Send a new code'), findsOneWidget);
    expect(find.text('Try WhatsApp'), findsNothing);
    expect(find.text('Call me with the code'), findsNothing);
  });

  testWidgets(
    "A4: the hook's refusal of \"Try WhatsApp\" is a notice under the resend "
    'row, never the code error',
    (tester) async {
      final sender =
          FakeCodeSender()..failNext = const AuthException('otp:unavailable');
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: _saved(
          _atCode(
            sendCount: 3,
            lastSentAt: _now.subtract(const Duration(minutes: 5)),
          ),
        ),
        overrides: _deps(sender, FakeSmsCodeListener()),
      );
      await tester.tap(find.text('Try WhatsApp'));
      await tester.pumpAndSettle();
      expect(
        find.text("We couldn't send a code. Try again or try WhatsApp."),
        findsOneWidget,
      );
      expect(
        find.text("That code didn't work. Check it and try again."),
        findsNothing,
      );
      expect(sender.sent, isEmpty);
    },
  );

  testWidgets('A4: an SMS read by Android fills the code and verifies it', (
    tester,
  ) async {
    final listener = FakeSmsCodeListener();
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.newAccount),
      prefsValues: _saved(_atCode(sendCount: 1)),
      overrides: _deps(FakeCodeSender(), listener),
    );
    expect(listener.listens, 1, reason: 'A4 listens as it opens');
    listener.arrive('123456');
    // The SMS reaches the flow, the flow the step, the step the field.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      expect(
        find.text(digit),
        findsOneWidget,
        reason: 'the code filled the boxes',
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Before you start'), findsOneWidget);
    expect(
      listener.stops,
      greaterThan(0),
      reason: 'the listener stops after A4',
    );
  });

  testWidgets('A3 listens only once a send is out; A4 goes on listening', (
    tester,
  ) async {
    final listener = FakeSmsCodeListener();
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(FakeCodeSender(), listener),
    );
    expect(listener.listens, 0);
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '244123456',
    );
    await tester.tap(find.text('Text me a code'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code'), findsOneWidget);
    expect(listener.listens, 1);
  });

  testWidgets('an SMS that arrives before the send has returned is filled, and '
      'checked once (review B8 m-1)', (tester) async {
    final listener = FakeSmsCodeListener();
    final sender = FakeCodeSender()..hold = Completer<void>();
    final auth = FakeSignUpAuth();
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(sender, listener, auth: auth),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '244123456',
    );
    await tester.tap(find.text('Text me a code'));
    await tester.pump();
    expect(listener.listens, 1, reason: 'listening before the send returns');
    listener.arrive('123456');
    await tester.pump();
    expect(find.text("What's your phone number?"), findsOneWidget);
    sender.hold!.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(kCodeAcceptedHold);
    await tester.pumpAndSettle();
    expect(auth.verifyCalls, 1);
    expect(
      find.text("We couldn't find an Attune account for this number"),
      findsOneWidget,
    );
  });

  testWidgets('a send that fails stops the listener it started', (
    tester,
  ) async {
    final listener = FakeSmsCodeListener();
    final sender =
        FakeCodeSender()..failNext = const AuthException('otp:unavailable');
    await pumpFlowScreen(
      tester,
      () => const SignUpFlow(entry: SignUpEntry.returning),
      overrides: _deps(sender, listener),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '244123456',
    );
    await tester.tap(find.text('Text me a code'));
    await tester.pumpAndSettle();
    expect(find.text("What's your phone number?"), findsOneWidget);
    expect(listener.listens, 1);
    expect(listener.stops, 1);
  });

  testWidgets(
    '"Change it" stops the listener, and an SMS after that fills nothing',
    (tester) async {
      final listener = FakeSmsCodeListener();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: _saved(_atCode(sendCount: 1)),
        overrides: _deps(FakeCodeSender(), listener),
      );
      await tester.tap(find.text('Wrong number? Change it'));
      await tester.pumpAndSettle();
      expect(find.text("What's your phone number?"), findsOneWidget);
      expect(listener.stops, 1);
      listener.arrive('123456');
      await tester.pumpAndSettle();
      expect(find.text("What's your phone number?"), findsOneWidget);
    },
  );

  testWidgets(
    'a wrong autofilled code, then a new code: the listener listens again '
    'and the new SMS verifies',
    (tester) async {
      final listener = FakeSmsCodeListener();
      final sender = FakeCodeSender();
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.newAccount),
        prefsValues: _saved(
          _atCode(
            sendCount: 1,
            lastSentAt: _now.subtract(const Duration(minutes: 5)),
          ),
        ),
        overrides: _deps(sender, listener),
      );
      listener.arrive('000000');
      await tester.pumpAndSettle();
      expect(
        find.text("That code didn't work. Check it and try again."),
        findsOneWidget,
      );
      await tester.tap(find.text('Send a new code'));
      await tester.pumpAndSettle();
      expect(sender.sent.single.$2, 'sms');
      expect(listener.listens, 2, reason: 'listening for the new SMS');
      listener.arrive('123456');
      await tester.pump();
      await tester.pump();
      await tester.pump(kCodeAcceptedHold);
      await tester.pumpAndSettle();
      expect(find.text('Before you start'), findsOneWidget);
    },
  );

  // Final review I-2 (ruling): WhatsApp codes are only for numbers with no
  // account. The server sends an existing account's code by SMS whatever
  // was asked, so the way back in to one never offers WhatsApp, nor
  // mentions it.
  group('I-2: "I already have an account" never offers WhatsApp', () {
    testWidgets('A3 offers SMS only, and a failed send says only "try again"', (
      tester,
    ) async {
      final sender =
          FakeCodeSender()..failNext = const AuthException('otp:unavailable');
      await pumpFlowScreen(
        tester,
        () => const SignUpFlow(entry: SignUpEntry.returning),
        overrides: _deps(sender, FakeSmsCodeListener()),
      );
      expect(find.text('Text me a code'), findsOneWidget);
      expect(find.text('Send by WhatsApp instead'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'),
        '244123456',
      );
      await tester.tap(find.text('Text me a code'));
      await tester.pumpAndSettle();
      expect(find.text("We couldn't send a code. Try again."), findsOneWidget);
      expect(find.textContaining('WhatsApp'), findsNothing);
    });

    // A returning draft reopened by a bare /signup (the resume) is still
    // the returning way: the draft's own way in decides.
    for (final opened in [SignUpEntry.returning, SignUpEntry.newAccount]) {
      testWidgets('A4 after the second resend offers a new code only '
          '(opened as ${opened.wire})', (tester) async {
        final sender = FakeCodeSender();
        final draft = SignUpDraft.start(
          SignUpEntry.returning,
          now: _now,
        ).copyWith(
          phoneE164: '+233244123456',
          countryIso: 'GH',
          lastSentAt: _now.subtract(const Duration(minutes: 5)),
          sendCount: 3,
        );
        await pumpFlowScreen(
          tester,
          () => SignUpFlow(entry: opened),
          prefsValues: _saved(draft),
          overrides: _deps(sender, FakeSmsCodeListener()),
        );
        expect(find.text('Enter the code'), findsOneWidget);
        expect(find.text('Send a new code'), findsOneWidget);
        expect(find.text('Try WhatsApp'), findsNothing);

        sender.failNext = const AuthException('otp:unavailable');
        await tester.tap(find.text('Send a new code'));
        await tester.pumpAndSettle();
        expect(
          find.text("We couldn't send a code. Try again."),
          findsOneWidget,
        );
        expect(find.textContaining('WhatsApp'), findsNothing);
      });
    }
  });
}
