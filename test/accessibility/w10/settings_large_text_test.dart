// Spec 1 W10a: Settings at large text (audit order: 4th).
//   flutter test --update-goldens test/accessibility/w10/settings_large_text_test.dart
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/flow_harness.dart';
import 'support/large_text_audit.dart';

void main() {
  for (final phone in auditPhones) {
    for (final scale in auditScales) {
      testWidgets('Settings, ${phone.width.toInt()} wide, text $scale', (
        t,
      ) async {
        final overflows = await collectOverflows(() async {
          await pumpFlowScreen(
            t,
            () => const SettingsScreen(currentUserId: 'me'),
            textScale: scale,
            rootTextScaleCap: scale,
            size: phone,
          );
          if (phone == auditPhones.first && goldenScales.contains(scale)) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/settings.${scaleName(scale)}.png'),
            );
          }
          await scrollToEnd(t);
        });
        expect(overflows, isEmpty);
      });
    }
  }
}
