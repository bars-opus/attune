// Spec 1 W10a (batch 2 fix round 1): the WhatsApp question grows with the
// phone's text size once, through BottomSheetUtils: 60% of the screen at
// 1.0, that times the text size above it, up to 90% of the screen. The
// step's own context sits above FlowFrame's AllowLargeText (the root clamp
// keeps it at 1.0), so the sheet must be opened from inside it.
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _ghana = PhoneCountries.all.firstWhere((c) => c.isoCode == 'GH');

PhoneStep _phone() => PhoneStep(
  initialCountry: _ghana,
  initialNational: '244123456',
  onSend: (_, __) {},
  onSendWhatsApp: (_, __) {},
  onBack: () {},
);

Future<double> _sheetMax(WidgetTester t, double scale) async {
  await pumpFlowScreen(t, _phone, textScale: scale);
  await t.tap(find.text('Send by WhatsApp instead'));
  await t.pumpAndSettle();
  return t.widget<BottomSheet>(find.byType(BottomSheet)).constraints!.maxHeight;
}

void main() {
  const screen = 844.0;

  testWidgets('60% of the screen at 1.0', (t) async {
    expect(await _sheetMax(t, 1.0), screen * 0.6);
  });

  testWidgets('grown once by the text size at 1.3', (t) async {
    expect(await _sheetMax(t, 1.3), closeTo(screen * 0.6 * 1.3, 0.01));
  });

  testWidgets('90% of the screen at 2.0', (t) async {
    expect(await _sheetMax(t, 2.0), closeTo(screen * 0.9, 0.01));
  });
}
