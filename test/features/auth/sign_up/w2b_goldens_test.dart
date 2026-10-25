// Spec 1 §2.3 (W2b): every sign-up step at text sizes 1.0, 1.3 and 2.0 and
// once right to left. Look at the images when they change.
//   flutter test --update-goldens test/features/auth/sign_up/w2b_goldens_test.dart
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/birth_date_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/consent_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/name_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/no_account_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/join_attune_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
final _ghana = PhoneCountries.all.firstWhere((c) => c.isoCode == 'GH');

void main() {
  testWidgets('A1 name', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_name',
      () => NameStep(initialName: 'Ɛsi', onSubmit: (_) {}, onBack: () {}),
    );
  });

  testWidgets('A2 date of birth, confirmed', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_birth_date',
      () => BirthDateStep(
        order: BirthDateOrder.dayMonthYear,
        todayUtc: _now,
        initialDate: DateTime.utc(1991, 11, 8),
        onSubmit: (_) {},
        onBack: () {},
      ),
    );
  });

  testWidgets('A3 phone, with a send error', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_phone',
      () => PhoneStep(
        initialCountry: _ghana,
        initialNational: '244123456',
        sendError: "We couldn't send a code. Try again or try WhatsApp.",
        onSend: (_, __) {},
        onBack: () {},
      ),
    );
  });

  testWidgets('A4 code, after a resend, with a wrong code', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_code',
      () => CodeStep(
        phoneE164: '+233244123456',
        lastSentAt: _now,
        sendCount: 2,
        now: () => _now,
        errorText: "That code didn't work. Check it and try again.",
        errorCount: 1,
        onCode: (_) {},
        onResend: () {},
        onChangeNumber: () {},
      ),
    );
  });

  testWidgets('A5 consent', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_consent',
      () => ConsentStep(onAgree: () {}, onNotNow: () {}),
    );
  });

  testWidgets('A5c updated terms', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_consent_updated',
      () => ConsentStep(updatedTerms: true, onAgree: () {}, onNotNow: () {}),
    );
  });

  testWidgets('N1 no account', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_no_account',
      () => NoAccountStep(onCreate: () {}, onOtherNumber: () {}),
    );
  });

  testWidgets('Welcome back', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_welcome_back',
      () => const WelcomeBackStep(firstName: 'Esi'),
    );
  });

  testWidgets('G2 Join Attune', (tester) async {
    await expectFlowGoldens(
      tester,
      'join_attune',
      () => const Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: JoinAttunePanel(),
          ),
        ),
      ),
      before: _allThreeButtonsShown,
    );
  });
}

/// Every image of G2 shows all three ways in (review m-5). At 2.0 they sit
/// below the fold, so the image is taken scrolled to the last; at 1.0 and
/// 1.3 everything fits and nothing moves.
Future<void> _allThreeButtonsShown(WidgetTester tester) async {
  await tester.ensureVisible(find.text('I have an invite'));
  await tester.pumpAndSettle();
  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  for (final label in [
    'Get started',
    'I already have an account',
    'I have an invite',
  ]) {
    final rect = tester.getRect(find.text(label));
    expect(
      screen.contains(rect.topLeft) && screen.contains(rect.bottomRight),
      isTrue,
      reason: '"$label" is off the image',
    );
  }
}
