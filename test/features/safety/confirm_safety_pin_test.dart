// Spec 3c (plan review I8): with a Safety PIN set, a sensitive action asks
// for it first; without one, it goes ahead.
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SafetyPinStore _store() => SafetyPinStore(
  hasher: (p) async => hashPin(p, iterations: 1000),
  verifier: (p, e) async => verifyPinHash(p, e),
);

Future<List<bool?>> _pump(WidgetTester t, SafetyPinStore s) async {
  final results = <bool?>[];
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed:
                    () async =>
                        results.add(await confirmSafetyPin(context, store: s)),
                child: const Text('GO'),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('GO'));
  await t.pumpAndSettle();
  return results;
}

Future<void> _type(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(find.widgetWithText(InkResponse, d).first);
    await t.pump();
  }
  await t.tap(find.text('Confirm'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no PIN set: goes ahead without asking', (t) async {
    final r = await _pump(t, _store());
    expect(r, [true]);
    expect(find.text('Enter your Safety PIN'), findsNothing);
  });

  testWidgets('a PIN set: the right PIN confirms, a wrong one does not', (
    t,
  ) async {
    final s = _store();
    await s.setPin('2468');
    final r = await _pump(t, s);
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    await _type(t, '1111');
    expect(find.text("That PIN didn't match."), findsOneWidget);
    expect(r, isEmpty);
    await _type(t, '2468');
    expect(r, [true]);
  });

  testWidgets('cancel is a no', (t) async {
    final s = _store();
    await s.setPin('2468');
    final r = await _pump(t, s);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(r, [false]);
  });
}
