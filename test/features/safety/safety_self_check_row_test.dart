// Spec 8 (F14; plan review I1, §1.8): where the private check is offered.
import 'dart:io';

import 'package:attune/features/pulse/providers/pulse_providers.dart'
    show currentRelationshipIdProvider;
import 'package:attune/features/safety/self_check/safety_self_check_row.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester t, {
  required bool on,
  DateTime? answered,
  bool dueOnly = false,
}) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        safetySelfCheckEnabledProvider.overrideWith((ref) async => on),
        currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
        safetySelfCheckAnsweredAtProvider.overrideWith(
          (ref, id) async => answered,
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(body: SafetySelfCheckRow(dueOnly: dueOnly)),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('off: nothing; on: the same row whatever was answered', (
    t,
  ) async {
    await _pump(t, on: false);
    expect(find.text(safetySelfCheckRowTitle), findsNothing);
    await _pump(t, on: true);
    expect(find.text(safetySelfCheckRowTitle), findsOneWidget);
    await _pump(
      t,
      on: true,
      answered: DateTime.now().subtract(const Duration(days: 3)),
    );
    expect(find.text(safetySelfCheckRowTitle), findsOneWidget);
  });

  testWidgets('Pulse offers it only when due (90 days)', (t) async {
    await _pump(
      t,
      on: true,
      dueOnly: true,
      answered: DateTime.now().subtract(const Duration(days: 3)),
    );
    expect(find.text(safetySelfCheckRowTitle), findsNothing);
    await _pump(
      t,
      on: true,
      dueOnly: true,
      answered: DateTime.now().subtract(const Duration(days: 95)),
    );
    expect(find.text(safetySelfCheckRowTitle), findsOneWidget);
  });

  test('offered from Safety resources, Pulse and the end of Ask-2', () {
    expect(
      File(
        'lib/features/safety/presentation/screens/safety_resources_screen.dart',
      ).readAsStringSync(),
      contains('SafetySelfCheckRow()'),
    );
    expect(
      File(
        'lib/features/pulse/presentation/screens/pulse_screen.dart',
      ).readAsStringSync(),
      contains('SafetySelfCheckRow(dueOnly: true)'),
    );
    expect(
      File(
        'lib/features/onboarding/presentation/screens/ask2_flow.dart',
      ).readAsStringSync(),
      contains('offerSafetySelfCheck('),
    );
  });
}
