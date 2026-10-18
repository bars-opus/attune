// Spec 8 (research 06 B10; plan review I17): "a trained outside
// perspective" — a resource, reachable from Pulse, Settings and the
// Understand footer; never "recommended for your relationship".
import 'dart:io';

import 'package:attune/features/safety/presentation/outside_perspective_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('what it is, what to look for, where to find someone, and your partner struggling', (t) async {
    t.view.physicalSize = const Size(1170, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: OutsidePerspectiveScreen()));
    for (final title in ['What couples counselling is', 'What to look for', 'How to find someone',
      'Support for you on your own', 'When your partner is struggling']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.textContaining('recommended for your relationship'), findsNothing);
  });

  test('reachable from Pulse and Settings, and routed', () {
    expect(File('lib/features/pulse/presentation/screens/pulse_screen.dart').readAsStringSync(),
        contains('OutsidePerspectiveScreen.routeName'));
    expect(File('lib/features/settings/data/settings_data.dart').readAsStringSync(),
        contains("'/support/outside-perspective'"));
    expect(File('lib/app/routing/app_router.dart').readAsStringSync(), contains('OutsidePerspectiveScreen()'));
  });
}
