// Spec 1 §2.3 (W2c): A3 with WhatsApp, the WhatsApp question, and A4 with
// the other channel after the second resend (WhatsApp only: voice is off in
// W2), at 1.0, 1.3, 2.0 and right to left.
//   flutter test --update-goldens test/features/auth/sign_up/w2c_goldens_test.dart
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
final _ghana = PhoneCountries.all.firstWhere((c) => c.isoCode == 'GH');

PhoneStep _phone() => PhoneStep(
  initialCountry: _ghana,
  initialNational: '244123456',
  onSend: (_, __) {},
  onSendWhatsApp: (_, __) {},
  onBack: () {},
);

void main() {
  testWidgets('A3 with WhatsApp', (tester) async {
    await expectFlowGoldens(tester, 'step_phone_whatsapp', _phone);
  });

  testWidgets('A3 WhatsApp question', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_phone_whatsapp_sheet',
      _phone,
      before: (tester) async {
        await tester.tap(find.text('Send by WhatsApp instead'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('A4 after the second resend: Try WhatsApp', (tester) async {
    await expectFlowGoldens(
      tester,
      'step_code_channels',
      () => CodeStep(
        phoneE164: '+233244123456',
        lastSentAt: _now.subtract(const Duration(minutes: 3)),
        sendCount: 3,
        now: () => _now,
        lastChannel: 'whatsapp',
        onCode: (_) {},
        onResend: () {},
        onChangeNumber: () {},
        onTryWhatsApp: () {},
      ),
    );
  });
}
