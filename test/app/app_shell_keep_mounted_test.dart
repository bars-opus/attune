// Stories Wave 3 (07b G7): the privacy cover and the Safety lock's return
// check hide the app without unmounting it. Mirrors the real shell's order
// (SafetyLockGate > AppPrivacyCover > QuickExitZone > Router); the order is
// pinned against lib/app/app_shell.dart in Task 4's group.
import 'dart:io';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_sdk.dart';
import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/safety/presentation/widgets/safety_lock_gate.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../helpers/state_probe.dart';

final _user = User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'a',
  createdAt: '2026-01-01T00:00:00Z',
);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const StateProbe('HOME')),
    GoRoute(path: '/page', builder: (_, __) => const StateProbe('PAGE')),
    GoRoute(
      path: '/list',
      builder:
          (_, __) => Scaffold(
            body: ListView.builder(
              itemCount: 200,
              itemExtent: 50,
              itemBuilder: (_, i) => Text('Item $i'),
            ),
          ),
    ),
    GoRoute(
      path: RouteNames.neutralScreen,
      name: 'neutralScreen',
      builder: (_, __) => const Scaffold(body: Text('DECOY')),
    ),
  ],
);

/// The real quick-exit flag (prefs + keystore mocks), a real PIN store, and
/// a sign-out the test can count.
class _World {
  _World(this.router);
  final GoRouter router;
  bool signedIn = true;
  int signOuts = 0;
  final pins = SafetyPinStore(
    hasher: (p) async => hashPin(p, iterations: 1000),
    verifier: (p, e) async => verifyPinHash(p, e),
  );
  SafetyLockDeps get deps => SafetyLockDeps(
    // A keystore read takes real time on a device, so a frame is drawn
    // while the return is checked; mocked channels would answer first.
    quickExitFlag: () async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return QuickExitService.requiresSafetyUnlock();
    },
    clearQuickExitFlag: QuickExitService.clearSafetyUnlockRequired,
    pins: pins,
    signOut: () async {
      signOuts++;
      signedIn = false;
    },
    signedIn: () => signedIn,
    leaveDecoy: () {
      final path = router.routerDelegate.currentConfiguration.uri.path;
      if (path == RouteNames.neutralScreen) router.go('/');
    },
  );
}

typedef _Shell = ({GoRouter router, _World w, ProviderContainer c});

/// Counts the gate's replays of a waiting notification tap.
class _CountingPush extends OneSignalService {
  _CountingPush(super.ref) : super(sdk: _NoSdk(), platform: 'ios');
  int replays = 0;

  @override
  void replayPendingTap() => replays++;
}

class _NoSdk implements PushSdk {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<_Shell> _pump(
  WidgetTester t, {
  List<Override> overrides = const [],
}) async {
  final router = _router();
  final w = _World(router);
  final c = ProviderContainer(
    overrides: [
      safetyLockDepsProvider.overrideWithValue(w.deps),
      currentUserProvider.overrideWithValue(_user),
      ...overrides,
    ],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) => SafetyLockGate(
              child: AppPrivacyCover(
                child: QuickExitZone(router: router, child: child!),
              ),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (router: router, w: w, c: c);
}

NavigatorState _nav(_Shell s) =>
    s.router.routerDelegate.navigatorKey.currentState!;

const _blip = [AppLifecycleState.inactive, AppLifecycleState.resumed];
const _appSwitch = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

/// One frame per state, as on a device: delivering them all in one frame
/// would let a cover that swaps the app out go up and down unbuilt.
Future<void> _drive(WidgetTester t, List<AppLifecycleState> states) async {
  for (final s in states) {
    t.binding.handleAppLifecycleStateChanged(s);
    await t.pump();
  }
  await t.pumpAndSettle();
}

/// Pushes the GoRouter page and a pageless route over it, one tap each.
Future<void> _openPageAndPageless(WidgetTester t, _Shell s) async {
  s.router.push('/page');
  await t.pumpAndSettle();
  await t.tap(find.text('PAGE 0'));
  await t.pump();
  _nav(
    s,
  ).push(MaterialPageRoute<void>(builder: (_) => const StateProbe('PAGELESS')));
  await t.pumpAndSettle();
  await t.tap(find.text('PAGELESS 0'));
  await t.pump();
}

/// Pops the pageless route: the page below must still be the kept one.
Future<void> _expectBothKept(WidgetTester t, _Shell s) async {
  expect(find.text('PAGELESS 1'), findsOneWidget);
  _nav(s).pop();
  await t.pumpAndSettle();
  expect(find.text('PAGE 1'), findsOneWidget);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    // The story wipe's real image cache arms a 3 s bound under fake time
    // (stories Wave 4 Task 9); this suite tests the shell, not the wipe.
    QuickExitService.clearStories = () async {};
    addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
  });

  group('an inactive blip (Control Centre, a call, Face ID, a permission '
      'alert)', () {
    testWidgets('a GoRouter page and a pageless route keep their State', (
      t,
    ) async {
      final s = await _pump(t);
      await _openPageAndPageless(t, s);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.text('PAGELESS 1'), findsNothing, reason: 'covered');
      expect(find.text('PAGELESS 1', skipOffstage: false), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      await _expectBothKept(t, s);
    });

    testWidgets('a bottom sheet stays open and a list keeps its scroll', (
      t,
    ) async {
      final s = await _pump(t);
      s.router.push('/list');
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView), const Offset(0, -1000));
      await t.pumpAndSettle();
      expect(find.text('Item 0'), findsNothing);
      showModalBottomSheet<void>(
        context: _nav(s).context,
        builder: (_) => const SizedBox(height: 200, child: Text('SHEET')),
      );
      await t.pumpAndSettle();
      await _drive(t, _blip);
      expect(find.text('SHEET'), findsOneWidget);
      _nav(s).pop();
      await t.pumpAndSettle();
      expect(find.text('Item 0'), findsNothing, reason: 'scroll kept');
      expect(find.text('Item 20'), findsOneWidget);
    });

    testWidgets('a focused text field keeps its text and its focus '
        '(Review Focus 3)', (t) async {
      final s = await _pump(t);
      _nav(s).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: TextField(autofocus: true)),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'half a thought');
      await _drive(t, _blip);
      expect(find.text('half a thought'), findsOneWidget);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );
    });
  });

  group('an app switch (through the lock check)', () {
    Future<void> focusField(WidgetTester t, _Shell s) async {
      // The keyboard is up: the view reports its inset.
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      _nav(s).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: TextField(autofocus: true)),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'half a thought');
      expect(t.testTextInput.isVisible, isTrue);
    }

    Future<void> away(WidgetTester t) async {
      for (final st in _appSwitch.take(5)) {
        t.binding.handleAppLifecycleStateChanged(st);
        await t.pump();
      }
    }

    testWidgets('no PIN: the keyboard stays down through the check and comes '
        'back only once the lock opens (final review I1)', (t) async {
      final s = await _pump(t);
      await focusField(t, s);
      await away(t);
      expect(t.testTextInput.isVisible, isFalse, reason: 'covered');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(s.c.read(safetyLockProvider), SafetyLockState.checking);
      expect(
        t.testTextInput.isVisible,
        isFalse,
        reason: 'not over the checking cover',
      );
      await t.pumpAndSettle();
      expect(s.c.read(safetyLockProvider), SafetyLockState.open);
      expect(t.testTextInput.isVisible, isTrue);
      expect(find.text('half a thought'), findsOneWidget);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );
    });

    testWidgets('with a PIN: no keyboard over the PIN screen, and none after '
        'unlock (final review I1)', (t) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      await s.w.pins.setEveryOpen(true);
      await focusField(t, s);
      await _drive(t, _appSwitch);
      expect(find.text('Enter PIN'), findsOneWidget);
      expect(t.testTextInput.isVisible, isFalse);
      t.view.resetViewInsets(); // the keyboard went down with the app
      for (final d in '2468'.split('')) {
        await t.tap(find.widgetWithText(InkResponse, d).first);
        await t.pump();
      }
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('HOME 0'), findsOneWidget);
      expect(t.testTextInput.isVisible, isFalse);
    });

    testWidgets('no PIN: the page and the pageless route keep their State', (
      t,
    ) async {
      final s = await _pump(t);
      await _openPageAndPageless(t, s);
      await _drive(t, _appSwitch);
      await _expectBothKept(t, s);
    });

    testWidgets('a PIN not asked on every open: State kept', (t) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      await _openPageAndPageless(t, s);
      await _drive(t, _appSwitch);
      await _expectBothKept(t, s);
    });

    testWidgets('a PIN asked on every open: the lock replaces the app; after '
        'unlock the page is rebuilt fresh and the pageless route is gone', (
      t,
    ) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      await s.w.pins.setEveryOpen(true);
      await _openPageAndPageless(t, s);
      await _drive(t, _appSwitch);
      expect(find.text('Enter PIN'), findsOneWidget);
      expect(find.text('PAGELESS 1', skipOffstage: false), findsNothing);
      expect(s.router.routerDelegate.navigatorKey.currentState, isNull);
      for (final d in '2468'.split('')) {
        await t.tap(find.widgetWithText(InkResponse, d).first);
        await t.pump();
      }
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('PAGELESS 0'), findsNothing);
      expect(find.text('PAGE 0'), findsOneWidget);
    });
  });

  group('quick exit and notification taps still work from every state '
      '(Review Focus 4, 5)', () {
    Future<void> tripleTap(WidgetTester t) async {
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
    }

    testWidgets('over a kept pageless route and sheet after a blip: only the '
        'decoy remains', (t) async {
      final s = await _pump(t);
      _nav(
        s,
      ).push(MaterialPageRoute<void>(builder: (_) => const StateProbe('MAP')));
      await t.pumpAndSettle();
      showModalBottomSheet<void>(
        context: _nav(s).context,
        builder: (_) => const SizedBox(height: 200, child: Text('SHEET')),
      );
      await t.pumpAndSettle();
      await _drive(t, _blip);
      await tripleTap(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.text('SHEET', skipOffstage: false), findsNothing);
      expect(find.text('MAP 0', skipOffstage: false), findsNothing);
    });

    testWidgets('after an app switch through the check (PIN set)', (t) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      s.router.push('/page');
      await t.pumpAndSettle();
      await _drive(t, _appSwitch);
      await tripleTap(t);
      expect(find.text('DECOY'), findsOneWidget);
    });

    testWidgets('no PIN: the decoy survives a blip; the next app switch signs '
        'out (F2 (6))', (t) async {
      final s = await _pump(t);
      await tripleTap(t);
      await _drive(t, _blip);
      expect(find.text('DECOY'), findsOneWidget, reason: 'no check on a blip');
      expect(s.w.signOuts, 0);
      await _drive(t, _appSwitch);
      expect(s.w.signOuts, 1);
    });

    testWidgets('with a PIN: the next return shows only the PIN screen, and '
        'unlocking leaves the decoy', (t) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      await tripleTap(t);
      await _drive(t, _appSwitch);
      expect(find.text('Enter PIN'), findsOneWidget);
      expect(find.text('DECOY', skipOffstage: false), findsNothing);
      for (final d in '2468'.split('')) {
        await t.tap(find.widgetWithText(InkResponse, d).first);
        await t.pump();
      }
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('HOME 0'), findsOneWidget);
    });

    testWidgets('while only the cover is up the Navigator stays mounted, so a '
        'tap from Notification Centre is no longer parked for want of one', (
      t,
    ) async {
      final s = await _pump(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(s.router.routerDelegate.navigatorKey.currentContext, isNotNull);
      expect(
        shouldDeferNotificationTap(
          state: s.c.read(safetyLockProvider),
          path: '/',
          navigatorReady: true,
        ),
        isFalse,
        reason: 'lock open: the tap navigates, behind the cover',
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
    });

    testWidgets('a tap delivered between hide and resume waits (the lock is '
        'checking from hide on) and is replayed once Attune is on screen '
        '(final review M5)', (t) async {
      late _CountingPush push;
      final s = await _pump(
        t,
        overrides: [
          oneSignalServiceProvider.overrideWith(
            (ref) => push = _CountingPush(ref),
          ),
        ],
      );
      await t.pumpAndSettle();
      final before = push.replays;
      bool defers() => shouldDeferNotificationTap(
        state: s.c.read(safetyLockProvider),
        path: '/',
        navigatorReady: true,
      );
      for (final st in _appSwitch.take(5)) {
        t.binding.handleAppLifecycleStateChanged(st);
        await t.pump();
        if (st == AppLifecycleState.hidden || st == AppLifecycleState.paused) {
          expect(defers(), isTrue, reason: 'hidden: the tap must wait');
        }
      }
      expect(defers(), isTrue, reason: 'inactive on the way back: still');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(s.c.read(safetyLockProvider), SafetyLockState.open);
      expect(defers(), isFalse);
      expect(push.replays, greaterThan(before), reason: 'replayed on open');
    });

    test('the real shell keeps the order this suite mirrors', () {
      final src = File('lib/app/app_shell.dart').readAsStringSync();
      final gate = src.indexOf('SafetyLockGate(');
      final cover = src.indexOf('AppPrivacyCover(');
      final zone = src.indexOf('QuickExitZone(');
      expect(gate, greaterThan(-1));
      expect(gate < cover && cover < zone, isTrue);
    });
  });
}
