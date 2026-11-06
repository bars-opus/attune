// Spec 1 W10a: Together and Planning at large text (audit order: 3rd).
// Planning's home on its Planning tab and its Calendar tab (the Together
// screen). The month grid (calendar_strip.dart) follows today's date, so it
// has no golden; the audit reaches it through the timeline's own tests.
//   flutter test --update-goldens test/accessibility/w10/together_planning_large_text_test.dart
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/planning/support/fake_planning_gateway.dart';
import '../../features/planning/support/planning_test_app.dart';
import 'support/large_text_audit.dart';

FakePlanningGateway _gateway() => FakePlanningGateway({
  'get_planning_home':
      (_) => {
        'categories': [
          fakeCategoryJson(
            id: 'c1',
            seedKey: 'goals',
            name: 'Goals',
            icon: 'flag',
            color: 'rose',
            entryCount: 2,
            hasNew: true,
          ),
          fakeCategoryJson(
            id: 'c2',
            seedKey: 'trips',
            name: 'Trips we keep meaning to take',
            icon: 'plane',
            color: 'teal',
          ),
        ],
      },
});

void main() {
  for (final tab in [PlanningHomeTab.planning, PlanningHomeTab.calendar]) {
    for (final phone in auditPhones) {
      for (final scale in auditScales) {
        testWidgets('${tab.name}, ${phone.width.toInt()} wide, text $scale', (
          t,
        ) async {
          setPhone(t, phone, scale);
          final overflows = await collectOverflows(() async {
            await t.pumpWidget(
              planningTestApp(
                _gateway(),
                PlanningHomeScreen(relationshipId: 'r1', initialTab: tab),
                coupleName: 'The Mensahs',
              ),
            );
            await settle(t);
            if (phone == auditPhones.first && goldenScales.contains(scale)) {
              await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile(
                  'goldens/${tab.name}.${scaleName(scale)}.png',
                ),
              );
            }
            await scrollToEnd(t);
            await t.pumpWidget(const SizedBox());
            await settle(t, const Duration(milliseconds: 300));
          });
          expect(overflows, isEmpty);
        });
      }
    }
  }
}
