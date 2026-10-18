// Spec 2 (research 06 §3 F2 (6)): setting the Safety PIN in Settings, and
// the one-time offer on Support resources.
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/screens/safety_pin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

SafetyPinStore _store() => SafetyPinStore(
  hasher: (p) async => hashPin(p, iterations: 1000),
  verifier: (p, e) async => verifyPinHash(p, e),
);

Future<void> _type(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(find.widgetWithText(InkResponse, d).first);
    await t.pump();
  }
  await t.tap(find.text('Next'));
  await t.pumpAndSettle();
}

Widget _wrap(Widget child) => ProviderScope(
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(home: child),
  ),
);

Future<void> _pump(WidgetTester t, SafetyPinStore s) async {
  await t.pumpWidget(_wrap(SafetyPinScreen(store: s)));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('set a PIN: choose, confirm, done', (t) async {
    final s = _store();
    await _pump(t, s);
    expect(find.text('Set a PIN'), findsOneWidget);
    await t.tap(find.text('Set a PIN'));
    await t.pumpAndSettle();
    expect(find.text('Choose a 4–8 digit PIN'), findsOneWidget);
    await _type(t, '2468');
    expect(find.text('Enter it again'), findsOneWidget);
    await _type(t, '2468');
    expect(await s.hasPin(), isTrue);
    expect(find.text('Change PIN'), findsOneWidget);
    expect(find.text('Remove PIN'), findsOneWidget);
  });

  testWidgets('a mismatched confirmation is refused', (t) async {
    final s = _store();
    await _pump(t, s);
    await t.tap(find.text('Set a PIN'));
    await t.pumpAndSettle();
    await _type(t, '2468');
    await _type(t, '1357');
    expect(find.text("Those PINs didn't match."), findsOneWidget);
    expect(await s.hasPin(), isFalse);
  });

  testWidgets('every-open turns on freely but off only with the PIN', (
    t,
  ) async {
    final s = _store();
    await s.setPin('2468');
    await _pump(t, s);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(await s.everyOpen(), isTrue);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Enter your current PIN'), findsOneWidget);
    await _type(t, '1111');
    expect(await s.everyOpen(), isTrue, reason: 'a wrong PIN leaves it on');
    await _type(t, '2468');
    expect(await s.everyOpen(), isFalse);
  });

  testWidgets('remove needs the current PIN', (t) async {
    final s = _store();
    await s.setPin('2468');
    await _pump(t, s);
    await t.tap(find.text('Remove PIN'));
    await t.pumpAndSettle();
    expect(find.text('Enter your current PIN'), findsOneWidget);
    await _type(t, '1111');
    expect(await s.hasPin(), isTrue);
    await _type(t, '2468');
    expect(await s.hasPin(), isFalse);
    expect(find.text('Set a PIN'), findsOneWidget);
  });

  testWidgets('a keystore error does not leave the screen stuck '
      '(review M-2)', (t) async {
    final s = SafetyPinStore(
      hasher: (p) async => throw StateError('keystore'),
      verifier: (p, e) async => false,
    );
    await _pump(t, s);
    await t.tap(find.text('Set a PIN'));
    await t.pumpAndSettle();
    await _type(t, '2468');
    await _type(t, '2468');
    expect(find.text("Couldn't save. Try again."), findsOneWidget);
    await _type(t, '2468');
    expect(find.text('Enter it again'), findsOneWidget, reason: 'usable');
  });

  testWidgets('Support resources offers the PIN once', (t) async {
    final s = _store();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(body: SafetyPinPromptCard(store: s)),
        ),
        GoRoute(
          path: '/settings/safety-pin',
          name: 'safetyPin',
          builder: (_, __) => const Text('PIN SCREEN'),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Set a Safety PIN'), findsOneWidget);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(find.text('Set a Safety PIN'), findsNothing);
    // Rebuilt later: still dismissed.
    await t.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Set a Safety PIN'), findsNothing);
  });
}
