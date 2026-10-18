// Spec 2 (research 06 §3 F2): the root lock gate. While the PIN is required
// the app's subtree -- the Navigator included -- is not in the tree at all.
// Drive delay UI with pump(Duration), never pumpAndSettle past a running
// countdown (the lock screen ticks every second).
import 'dart:async';

import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/safety_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _World {
  bool flag = false;
  bool signedIn = true;
  bool signOutFails = false;
  bool flagReadFails = false;
  int signOuts = 0;
  int leftDecoy = 0;
  Completer<void>? flagGate;
  final pins = SafetyPinStore(
    hasher: (p) async => hashPin(p, iterations: 1000),
    verifier: (p, e) async => verifyPinHash(p, e),
  );
  SafetyLockDeps get deps => SafetyLockDeps(
    quickExitFlag: () async {
      if (flagReadFails) throw StateError('keystore');
      await flagGate?.future;
      return flag;
    },
    clearQuickExitFlag: () async => flag = false,
    pins: pins,
    signOut: () async {
      signOuts++;
      if (signOutFails) throw StateError('busy');
      signedIn = false;
    },
    signedIn: () => signedIn,
    leaveDecoy: () => leftDecoy++,
  );
}

Future<void> _pump(WidgetTester t, _World w) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [safetyLockDepsProvider.overrideWithValue(w.deps)],
      child: const MaterialApp(
        home: SafetyLockGate(child: Text('SECRET CONTENT')),
      ),
    ),
  );
}

Future<void> _type(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(find.widgetWithText(InkResponse, d).first);
    await t.pump();
  }
  await t.tap(find.text('Unlock'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  const background = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  testWidgets('on resume nothing of the app paints before the check ends '
      '(review I-1)', (t) async {
    final w = _World();
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    await w.pins.setPin('2468');
    await w.pins.setEveryOpen(true);
    w.flagGate = Completer<void>();
    for (final s in background) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pump();
    expect(find.text('SECRET CONTENT'), findsNothing);
    w.flagGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Enter PIN'), findsOneWidget);
  });

  testWidgets('forgot PIN whose sign-out fails keeps the PIN, so a relaunch '
      'is still locked (review I-3)', (t) async {
    final w =
        _World()
          ..flag = true
          ..signOutFails = true;
    await w.pins.setPin('2468');
    await _pump(t, w);
    await t.pumpAndSettle();
    await t.tap(find.text('Forgot PIN?'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    expect(await w.pins.hasPin(), isTrue);
    expect(w.flag, isTrue);
    await t.pumpWidget(const SizedBox());
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsNothing);
    expect(find.text('Enter PIN'), findsOneWidget);
  });

  testWidgets('quick exit with no PIN whose sign-out fails keeps the flag '
      '(review I-3)', (t) async {
    final w =
        _World()
          ..flag = true
          ..signOutFails = true;
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(w.flag, isTrue);
    expect(find.text('SECRET CONTENT'), findsNothing);
  });

  testWidgets('a signed-out app keeps no PIN (review I-6)', (t) async {
    final w = _World()..signedIn = false;
    await w.pins.setPin('2468');
    await w.pins.setEveryOpen(true);
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(await w.pins.hasPin(), isFalse);
    expect(await w.pins.everyOpen(), isFalse);
  });

  testWidgets('a PIN that should be there but is not signs out '
      '(keystore reset or backup restore, review I-4)', (t) async {
    final w = _World();
    await w.pins.setPin('2468');
    await SafetyPinStore.defaultStorage.delete(key: 'safety_pin_hash');
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(w.signOuts, 1);
  });

  testWidgets('a reset keystore value is not a PIN (review I-4)', (t) async {
    final w = _World();
    await w.pins.setPin('2468');
    await SafetyPinStore.defaultStorage.write(
      key: 'safety_pin_hash',
      value: 'Data has been reset',
    );
    expect(await w.pins.hasPin(), isFalse);
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(w.signOuts, 1);
  });

  test('the seed clears a signed-out PIN and defers a corrupt one', () async {
    final pins = SafetyPinStore(
      hasher: (p) async => hashPin(p, iterations: 1000),
      verifier: (p, e) async => verifyPinHash(p, e),
    );
    var flag = true;
    await pins.setPin('2468');
    final out = await computeLockSeed(
      quickExitFlag: () async => flag,
      clearQuickExitFlag: () async => flag = false,
      pins: pins,
      signedIn: false,
    );
    expect(out, SafetyLockState.open);
    expect(await pins.hasPin(), isFalse);
    expect(flag, isFalse);

    await pins.setPin('2468');
    await SafetyPinStore.defaultStorage.delete(key: 'safety_pin_hash');
    final corrupt = await computeLockSeed(
      quickExitFlag: () async => false,
      clearQuickExitFlag: () async {},
      pins: pins,
      signedIn: true,
    );
    expect(corrupt, SafetyLockState.checking, reason: 'evaluate signs out');
  });

  test('notification taps wait while locked, on the decoy or before the '
      'navigator (review I-2)', () {
    expect(
      shouldDeferNotificationTap(
        state: SafetyLockState.open,
        path: '/neutralScreen',
        navigatorReady: true,
      ),
      isTrue,
    );
    expect(
      shouldDeferNotificationTap(
        state: SafetyLockState.locked,
        path: '/home',
        navigatorReady: true,
      ),
      isTrue,
    );
    expect(
      shouldDeferNotificationTap(
        state: SafetyLockState.open,
        path: '/home',
        navigatorReady: false,
      ),
      isTrue,
    );
    expect(
      shouldDeferNotificationTap(
        state: SafetyLockState.open,
        path: '/home',
        navigatorReady: true,
      ),
      isFalse,
    );
  });

  test('a waiting tap is replayed only into a signed-in, open app '
      '(review I-5)', () {
    expect(
      canReplayNotificationTap(
        signedIn: false,
        state: SafetyLockState.open,
        path: '/intro',
        navigatorReady: true,
      ),
      isFalse,
    );
    expect(
      canReplayNotificationTap(
        signedIn: true,
        state: SafetyLockState.open,
        path: '/home',
        navigatorReady: true,
      ),
      isTrue,
    );
    expect(
      canReplayNotificationTap(
        signedIn: true,
        state: SafetyLockState.open,
        path: '/neutralScreen',
        navigatorReady: true,
      ),
      isFalse,
    );
  });

  testWidgets('no PIN, no flag: the app opens', (t) async {
    final w = _World();
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);
  });

  testWidgets('cold start with the quick-exit flag and a PIN shows only the '
      'lock, and never a frame of the app', (t) async {
    final w = _World()..flag = true;
    await w.pins.setPin('2468');
    await _pump(t, w);
    expect(find.text('SECRET CONTENT'), findsNothing, reason: 'first frame');
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsNothing);
    expect(find.text('Enter PIN'), findsOneWidget);
    await _type(t, '1111');
    expect(find.text("That PIN didn't match."), findsOneWidget);
    expect(find.text('SECRET CONTENT'), findsNothing);
    await _type(t, '2468');
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    expect(w.flag, isFalse, reason: 'the flag clears on unlock');
    expect(
      w.leftDecoy,
      greaterThanOrEqualTo(1),
      reason: 'unlock leaves the decoy',
    );
  });

  testWidgets('quick exit with no PIN: the next open signs out', (t) async {
    final w = _World()..flag = true;
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(w.signOuts, 1);
    expect(w.flag, isFalse);
    expect(
      find.text('SECRET CONTENT'),
      findsOneWidget,
      reason: 'signed out now',
    );
  });

  testWidgets('a sign-out that fails never opens the app', (t) async {
    final w =
        _World()
          ..flag = true
          ..signOutFails = true;
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsNothing);
    expect(find.text('Enter PIN'), findsOneWidget);
  });

  testWidgets('a keystore that cannot be read fails closed: signed out', (
    t,
  ) async {
    final w = _World()..flagReadFails = true;
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(w.signOuts, 1);
    expect(
      find.text('SECRET CONTENT'),
      findsOneWidget,
      reason: 'signed out now',
    );
  });

  testWidgets('every-open: locks at cold start and after the background, '
      'not before', (t) async {
    final w = _World();
    await w.pins.setPin('2468');
    await w.pins.setEveryOpen(true);
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('Enter PIN'), findsOneWidget);
    await _type(t, '2468');
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    // A notification shade (inactive only) does not lock.
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    // The background does.
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pumpAndSettle();
    expect(find.text('Enter PIN'), findsOneWidget);
  });

  testWidgets('forgot PIN signs out and removes the PIN', (t) async {
    final w = _World()..flag = true;
    await w.pins.setPin('2468');
    await _pump(t, w);
    await t.pumpAndSettle();
    await t.tap(find.text('Forgot PIN?'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    expect(w.signOuts, 1);
    expect(await w.pins.hasPin(), isFalse);
  });

  testWidgets('signed out: never locks, and signing out removes the PIN data', (
    t,
  ) async {
    final w = _World()..signedIn = false;
    await w.pins.setPin('2468');
    await w.pins.setEveryOpen(true);
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    final c = ProviderScope.containerOf(t.element(find.byType(SafetyLockGate)));
    await c.read(safetyLockProvider.notifier).onSignedOut();
    expect(await w.pins.hasPin(), isFalse);
  });

  testWidgets('a deep link while locked lands behind the lock, not above it', (
    t,
  ) async {
    final w = _World()..flag = true;
    await w.pins.setPin('2468');
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('SECRET CONTENT')),
        GoRoute(path: '/deep', builder: (_, __) => const Text('DEEP LINKED')),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [safetyLockDepsProvider.overrideWithValue(w.deps)],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => SafetyLockGate(child: child!),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      router.routerDelegate.navigatorKey.currentState,
      isNull,
      reason: 'nothing can be pushed while locked',
    );
    router.go('/deep');
    await t.pumpAndSettle();
    expect(find.text('DEEP LINKED'), findsNothing);
    expect(find.text('Enter PIN'), findsOneWidget);
    await _type(t, '2468');
    expect(find.text('DEEP LINKED'), findsOneWidget, reason: 'behind the lock');
  });

  test('the seed: what the first frame shows before any async read', () {
    expect(
      initialLockState(
        flag: false,
        hasPin: false,
        everyOpen: false,
        signedIn: true,
      ),
      SafetyLockState.open,
    );
    expect(
      initialLockState(
        flag: true,
        hasPin: true,
        everyOpen: false,
        signedIn: true,
      ),
      SafetyLockState.locked,
    );
    expect(
      initialLockState(
        flag: false,
        hasPin: true,
        everyOpen: true,
        signedIn: true,
      ),
      SafetyLockState.locked,
    );
    expect(
      initialLockState(
        flag: true,
        hasPin: false,
        everyOpen: false,
        signedIn: true,
      ),
      SafetyLockState.checking,
      reason: 'needs a sign-out first',
    );
    expect(
      initialLockState(
        flag: true,
        hasPin: true,
        everyOpen: true,
        signedIn: false,
      ),
      SafetyLockState.open,
    );
  });

  test('foreground pushes are hidden while locked or on the decoy', () {
    expect(
      shouldSuppressForegroundPush(SafetyLockState.locked, '/home'),
      isTrue,
    );
    expect(
      shouldSuppressForegroundPush(SafetyLockState.checking, '/home'),
      isTrue,
    );
    expect(
      shouldSuppressForegroundPush(SafetyLockState.open, '/neutralScreen'),
      isTrue,
    );
    expect(
      shouldSuppressForegroundPush(SafetyLockState.open, '/home'),
      isFalse,
    );
  });
}
