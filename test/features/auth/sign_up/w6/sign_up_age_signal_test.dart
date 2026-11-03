// Spec 1 W6b (§3.3 A2, platform_age_signals): A2 reads the platform's age
// signal once. Minor or supervised: X1 without asking for the date; an
// adult date with a minor signal: X1 (the stricter wins); unknown or
// unavailable: the date decides; off: never asked. Nothing is sent.
import 'dart:async';

import 'package:attune/core/platform/age_signals.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_draft_store.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/sign_up_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fake_account_gateway.dart';
import '../../../../helpers/fake_sign_up.dart';
import '../../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 11, 3, 12);

class _Rig {
  _Rig({this.on = true, Future<AgeSignal> Function()? answer, this.settings})
    : _answer =
          answer ??
          (() async =>
              const AgeSignal('play_age_signals', AgeSignalStatus.unknown));

  final bool on;
  final Future<AgeSignal> Function() _answer;

  /// Fix round 1 (M-2): the settings as a provider a test can change.
  final StateProvider<({bool on, List<String> storefronts})>? settings;
  final sender = FakeCodeSender();
  final gateway = FakeAccountGateway();
  final asked = <List<String>>[];

  List<Override> get overrides => [
    codeSenderProvider.overrideWithValue(sender),
    signUpAuthProvider.overrideWithValue(FakeSignUpAuth()),
    accountServiceProvider.overrideWithValue(AccountService(gateway)),
    signUpClockProvider.overrideWithValue(() => _now),
    deviceCountryProvider.overrideWith(
      (ref) async => (sim: 'GH', region: null),
    ),
    smsCodeListenerProvider.overrideWithValue(FakeSmsCodeListener()),
    if (settings case final settings?)
      ageSignalSettingsProvider.overrideWith((ref) => ref.watch(settings))
    else
      ageSignalSettingsProvider.overrideWithValue((
        on: on,
        storefronts: const ['USA'],
      )),
    ageSignalReaderProvider.overrideWithValue((storefronts) {
      asked.add(storefronts);
      return _answer();
    }),
  ];
}

Future<FlowHarness> _toA2(WidgetTester tester, _Rig rig) async {
  final h = await pumpFlowScreen(
    tester,
    () => const SignUpFlow(entry: SignUpEntry.newAccount),
    overrides: rig.overrides,
  );
  await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Esi');
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _typeDate(WidgetTester tester, String year) async {
  await tester.enterText(find.widgetWithText(TextField, 'Day'), '27');
  await tester.enterText(find.widgetWithText(TextField, 'Month'), '3');
  await tester.enterText(find.widgetWithText(TextField, 'Year'), year);
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void _expectStopped(FlowHarness h, _Rig rig) {
  expect(h.location, '/age-stop');
  expect(h.routing.underAgeBlocked, isTrue);
  expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
  expect(SignUpDraftStore.readFrom(h.prefs, _now), isNull);
  expect(rig.sender.sent, isEmpty);
  expect(rig.gateway.calls, isEmpty);
}

/// Batch 6 (Play Age Signals terms: no analytics use): a stop the signal
/// caused is never counted.
void _expectNotCounted(FlowHarness h) {
  expect(h.metrics, isNot(contains('signup_age_stop')));
}

void main() {
  for (final status in [AgeSignalStatus.minor, AgeSignalStatus.supervised]) {
    testWidgets('a $status signal at A2: X1 before any date is typed', (
      tester,
    ) async {
      final rig = _Rig(
        answer: () async => AgeSignal('play_age_signals', status),
      );
      final h = await _toA2(tester, rig);
      expect(rig.asked, [
        const ['USA'],
      ]);
      _expectStopped(h, rig);
      _expectNotCounted(h);
    });
  }

  testWidgets(
    'an adult date with a minor signal still out: X1 (the stricter wins)',
    (tester) async {
      final slow = Completer<AgeSignal>();
      final rig = _Rig(answer: () => slow.future);
      final h = await _toA2(tester, rig);
      expect(find.text("What's your date of birth?"), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Day'), '27');
      await tester.enterText(find.widgetWithText(TextField, 'Month'), '3');
      await tester.enterText(find.widgetWithText(TextField, 'Year'), '1996');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      slow.complete(
        const AgeSignal('apple_declared_age_range', AgeSignalStatus.minor),
      );
      await tester.pumpAndSettle();
      _expectStopped(h, rig);
      _expectNotCounted(h);
    },
  );

  testWidgets('unknown or unavailable: the date decides; asked once', (
    tester,
  ) async {
    final rig = _Rig(
      answer:
          () async =>
              const AgeSignal('play_age_signals', AgeSignalStatus.unavailable),
    );
    await _toA2(tester, rig);
    await _typeDate(tester, '1996');
    expect(find.text("What's your phone number?"), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text("What's your date of birth?"), findsOneWidget);
    expect(
      rig.asked,
      hasLength(1),
      reason: 'read once per sign-up, never again',
    );
  });

  testWidgets('an adult signal never lets an under-18 date through', (
    tester,
  ) async {
    final rig = _Rig(
      answer:
          () async =>
              const AgeSignal('play_age_signals', AgeSignalStatus.adult),
    );
    final h = await _toA2(tester, rig);
    await _typeDate(tester, '2012');
    _expectStopped(h, rig);
    // The date decided, so the age stop is counted as it always was.
    expect(h.metrics, contains('signup_age_stop'));
  });

  // Fix round 1 (M-2): the anon config not known yet when A2 opens (first
  // install, slow network). Once it arrives on, A2 still asks, once.
  testWidgets('the config arrives after A2 opens: the signal is still read', (
    tester,
  ) async {
    final settings = StateProvider<({bool on, List<String> storefronts})>(
      (ref) => (on: false, storefronts: const <String>[]),
    );
    final rig = _Rig(
      settings: settings,
      answer:
          () async =>
              const AgeSignal('play_age_signals', AgeSignalStatus.minor),
    );
    final h = await _toA2(tester, rig);
    expect(rig.asked, isEmpty);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SignUpFlow)),
    );
    container.read(settings.notifier).state = (
      on: true,
      storefronts: const ['USA'],
    );
    await tester.pumpAndSettle();
    expect(rig.asked, [
      const ['USA'],
    ]);
    _expectStopped(h, rig);
    container.read(settings.notifier).state = (
      on: true,
      storefronts: const ['USA', 'BRA'],
    );
    await tester.pumpAndSettle();
    expect(rig.asked, hasLength(1), reason: 'read once per sign-up');
  });

  testWidgets('platform_age_signals off: never asked', (tester) async {
    final rig = _Rig(
      on: false,
      answer: () async => const AgeSignal('x', AgeSignalStatus.minor),
    );
    await _toA2(tester, rig);
    await _typeDate(tester, '1996');
    expect(rig.asked, isEmpty);
    expect(find.text("What's your phone number?"), findsOneWidget);
  });
}
