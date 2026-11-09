// Spec 2 W3a (§3.0 Lock, §3.14; R-8, R-9, R-10; carry 6): one redirect for
// every Dating route: signed in, then the Dating lock; D0 routed; quick
// exit takes the unlock and D0's typed answers with it.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart'
    show RouteNames, createAppRouter;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

void main() {
  setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));

  testWidgets('signed out: every Dating route goes to sign in', (t) async {
    for (final path in [DatingPaths.step('wait'), DatingPaths.unlock]) {
      final s = await pumpDatingShell(t, initial: path, signedIn: false);
      expect(find.text('LOGIN'), findsOneWidget, reason: path);
      expect(s.location, '/login');
    }
  });

  testWidgets('lock off: D0 opens straight away at /dating/setup/wait', (
    t,
  ) async {
    final s = await pumpDatingShell(t, initial: DatingPaths.step('wait'));
    expect(find.text('Before you begin'), findsOneWidget);
    expect(s.location, '/dating/setup/wait');
  });

  testWidgets('lock on: a deep link to a step asks for the PIN first', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
      pinSet: true,
    );
    expect(s.location, startsWith('/dating/unlock?from='));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text('Before you begin'), findsNothing);
  });

  testWidgets('lock on, no PIN set: the unlock goes on to the step asked for', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
    );
    expect(find.text('Before you begin'), findsOneWidget);
    expect(s.location, '/dating/setup/wait');
    expect(s.container.read(datingUnlockedProvider), isTrue);
  });

  testWidgets('the unlock ends when the app is put away', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
    );
    expect(s.container.read(datingUnlockedProvider), isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    expect(s.container.read(datingUnlockedProvider), isFalse);
  });

  testWidgets('an unreadable lock setting asks for the PIN (fail closed)', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      lockUnreadable: true,
      pinSet: true,
    );
    expect(s.location, startsWith('/dating/unlock'));
  });

  // Fix round 1: the gate (C-1) also ends on the PIN screen, so the redirect
  // is pinned on its own: a deep link is answered before any page is built.
  testWidgets('the redirect itself: locked or unreadable asks first; '
      'unlocked passes', (t) async {
    final answers = <String?>[];
    final probe = GoRoute(
      path: '/dating/probe',
      redirect: (context, state) async {
        answers.add(await datingRedirect(context, state, signedIn: true));
        return null;
      },
      builder: (_, __) => const Scaffold(body: Text('PROBE')),
    );
    final s = await pumpDatingShell(
      t,
      initial: '/dating/probe',
      locked: true,
      pinSet: true,
      extraRoutes: [probe],
    );
    expect(answers.last, '/dating/unlock?from=%2Fdating%2Fprobe');
    s.container.read(datingUnlockedProvider.notifier).unlock();
    s.router.go('/dating/probe');
    await t.pumpAndSettle();
    expect(answers.last, isNull);
    await pumpDatingShell(
      t,
      initial: '/dating/probe',
      lockUnreadable: true,
      pinSet: true,
      extraRoutes: [probe],
    );
    expect(answers.last, '/dating/unlock?from=%2Fdating%2Fprobe');
  });

  test('an unlock never returns outside Dating (no open redirect)', () {
    expect(datingSafeReturn('/dating/setup/where'), '/dating/setup/where');
    for (final from in [
      null,
      '',
      '/home',
      'https://example.com/dating/x',
      '//evil/dating/x',
      '/dating/unlock?from=/dating/setup/how',
      '/dating/../home',
    ]) {
      expect(datingSafeReturn(from), startsWith('/home?tab=me'), reason: from);
    }
  });

  testWidgets('a step no batch has built yet opens Me', (t) async {
    final s = await pumpDatingShell(t, initial: DatingPaths.step('nowhere'));
    expect(find.text('ME me'), findsOneWidget);
    expect(s.location, startsWith('/home?tab=me'));
  });

  test(
    'step numbers: looking-for is 1, ready is 12; how and wait have none',
    () {
      expect(datingStepNumber('looking-for'), 1);
      expect(datingStepNumber('ready'), 12);
      expect(datingStepNumber('how'), isNull);
      expect(datingStepNumber('wait'), isNull);
      expect(datingSetupOrder.length, 13);
    },
  );

  test(
    'motion: D0, D4 and D13 never move; D12 cross-fades; the rest slide',
    () {
      expect(datingStepMotion('wait'), DatingMotion.none);
      expect(datingStepMotion('privacy'), DatingMotion.none);
      expect(datingStepMotion('ready'), DatingMotion.none);
      expect(datingStepMotion('preview'), DatingMotion.fade);
      expect(datingStepMotion('where'), DatingMotion.sharedAxis);
    },
  );

  testWidgets('D0: "Set up Dating now" opens the saved next step', (t) async {
    final home = FakeDatingHomeGateway(
      home: const DatingHome(
        state: DatingHomeState.gentleWait,
        nextStep: 'looking-for',
      ),
    );
    final steps = <String>[];
    await pumpFlowScreen(
      t,
      () => DatingWaitStep(
        nav: DatingStepNav(next: steps.add, back: () {}, toMe: () {}),
      ),
      overrides: datingShellOverrides(home: home),
    );
    await tapInReach(t, find.text('Set up Dating now'));
    await t.pumpAndSettle();
    expect(steps, ['looking-for']);
  });

  // Fix round 1 (C-1, §3.0, §3.14): an open Dating page is re-guarded
  // when the unlock ends, not only on the next navigation.
  Future<DatingShell> unlockedOnD0(WidgetTester t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
      pinSet: true,
    );
    s.container.read(datingUnlockedProvider.notifier).unlock();
    s.router.go(DatingPaths.step('wait'));
    await t.pumpAndSettle();
    expect(find.text('Before you begin'), findsOneWidget);
    return s;
  }

  testWidgets('C-1: D0 open, the app put away and back: the PIN screen, '
      'and nothing of D0', (t) async {
    final s = await unlockedOnD0(t);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
    }
    await t.pump();
    // Not even the frame the app comes back on shows D0.
    expect(find.text('Before you begin'), findsNothing);
    await t.pumpAndSettle();
    expect(
      s.location,
      startsWith('/dating/unlock?from=%2Fdating%2Fsetup%2Fwait'),
    );
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text('Before you begin'), findsNothing);
  });

  testWidgets('C-1, I-1: another account on D0 starts locked (D8): the PIN '
      'screen, and nothing of D0', (t) async {
    final s = await unlockedOnD0(t);
    s.container.read(datingTestAccount.notifier).state = 'kofi';
    // The new account arrives (an auth stream event) ...
    await t.pump();
    expect(s.container.read(datingUnlockedProvider), isFalse);
    // ... and the first frame after it shows nothing of D0.
    await t.pump();
    expect(find.text('Before you begin'), findsNothing);
    await t.pumpAndSettle();
    expect(
      s.location,
      startsWith('/dating/unlock?from=%2Fdating%2Fsetup%2Fwait'),
    );
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text('Before you begin'), findsNothing);
  });

  // Fix round 2 (I-3): a sheet or dialog over a Dating page goes with it.
  Future<void> awayAndBack(WidgetTester t) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
    }
    await t.pumpAndSettle();
  }

  for (final (kind, root) in [
    ('dialog', false),
    ('dialog', true),
    ('sheet', false),
    ('sheet', true),
  ]) {
    testWidgets('I-3: a $kind over D0 (root navigator: $root) goes with it '
        'when the app is put away', (t) async {
      final s = await unlockedOnD0(t);
      final context = t.element(find.text('Before you begin'));
      if (kind == 'dialog') {
        unawaited(
          showDialog<void>(
            context: context,
            useRootNavigator: root,
            builder: (_) => const AlertDialog(content: Text('MODAL TEXT')),
          ),
        );
      } else {
        unawaited(
          showModalBottomSheet<void>(
            context: context,
            useRootNavigator: root,
            builder:
                (_) => const SizedBox(height: 200, child: Text('MODAL TEXT')),
          ),
        );
      }
      await t.pumpAndSettle();
      expect(find.text('MODAL TEXT'), findsOneWidget);
      await awayAndBack(t);
      expect(find.text('MODAL TEXT'), findsNothing);
      expect(find.text('Before you begin'), findsNothing);
      expect(
        s.location,
        startsWith('/dating/unlock?from=%2Fdating%2Fsetup%2Fwait'),
      );
      expect(find.text('Enter your Safety PIN'), findsOneWidget);
    });
  }

  testWidgets('I-3: a page that is not Dating on top (the decoy) stays put; '
      'D0 under it shows nothing', (t) async {
    final s = await unlockedOnD0(t);
    unawaited(s.router.push(RouteNames.neutralScreen));
    await t.pumpAndSettle();
    expect(find.text('DECOY'), findsOneWidget);
    var moves = 0;
    s.router.routeInformationProvider.addListener(() => moves++);
    await awayAndBack(t);
    expect(moves, 0);
    expect(find.text('DECOY'), findsOneWidget);
    expect(find.text('Enter your Safety PIN'), findsNothing);
    expect(find.text('Before you begin', skipOffstage: false), findsNothing);
  });

  testWidgets('I-3: stacked Dating pages ask once, for the page on top', (
    t,
  ) async {
    final s = await unlockedOnD0(t);
    unawaited(s.router.push('/dating/setup/wait?n=2'));
    await t.pumpAndSettle();
    var moves = 0;
    s.router.routeInformationProvider.addListener(() => moves++);
    await awayAndBack(t);
    expect(moves, 1);
    expect(s.location, '/dating/unlock?from=%2Fdating%2Fsetup%2Fwait%3Fn%3D2');
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
  });

  testWidgets('C-1 guard: every Dating route but the unlock hides itself and '
      'asks for the PIN when the lock comes on', (t) async {
    final gated = [
      for (final route in datingRoutes(signedIn: () => true))
        if (route is GoRoute && route.path != DatingPaths.unlock) route.path,
    ];
    expect(gated, isNotEmpty);
    for (final path in gated) {
      final location = path.replaceAllMapped(
        RegExp(r':(\w+)'),
        (m) => m[1] == 'step' ? 'wait' : 'x',
      );
      final s = await pumpDatingShell(t, initial: location, pinSet: true);
      expect(s.location, location, reason: path);
      s.lock.on = true;
      s.container.invalidate(datingLockProvider);
      await t.pumpAndSettle();
      expect(s.location, startsWith('/dating/unlock?from='), reason: path);
    }
  });

  test('I-1, I-2: the unlock is per account, and the same account '
      'signalled again (a token refresh) keeps it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final accounts = StreamController<String?>();
    addTearDown(accounts.close);
    final c = ProviderContainer(
      overrides: [
        datingLockAccountProvider.overrideWith((ref) => accounts.stream),
      ],
    );
    addTearDown(c.dispose);
    c.listen(datingUnlockedProvider, (_, __) {});
    accounts.add('ama');
    await pumpEventQueue();
    c.read(datingUnlockedProvider.notifier).unlock();
    expect(c.read(datingUnlockedProvider), isTrue);
    accounts.add('ama');
    await pumpEventQueue();
    expect(c.read(datingUnlockedProvider), isTrue);
    accounts.add('kofi');
    await pumpEventQueue();
    expect(c.read(datingUnlockedProvider), isFalse);
  });

  testWidgets('M-2: an unlock asked to go on outside Dating opens Me', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: '/dating/unlock?from=%2Fhome',
      locked: true,
    );
    expect(find.text('ME me'), findsOneWidget);
    expect(s.location, startsWith('/home?tab=me'));
  });

  test('M-3: every /dating route in the app carries the one redirect', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(
      datingRoutes(
        signedIn: () => true,
      ).every((r) => r is GoRoute && r.redirect != null),
      isTrue,
    );
    final router = createAppRouter(
      RoutingNotifier(flowV2: true, currentUserId: () => null),
    );
    addTearDown(router.dispose);
    final dating = <GoRoute>[];
    void walk(List<RouteBase> routes) {
      for (final route in routes) {
        if (route is GoRoute && route.path.startsWith('/dating')) {
          dating.add(route);
        }
        walk(route.routes);
      }
    }

    walk(router.configuration.routes);
    expect(
      dating.map((r) => r.path),
      containsAll([DatingPaths.unlock, '/dating/setup/:step']),
    );
    for (final route in dating) {
      expect(route.redirect, isNotNull, reason: route.path);
    }
  });

  group('quick exit (carry 6, R-9)', () {
    setUp(() {
      QuickExitService.clearStories = () async {};
      addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
    });

    testWidgets('from D0 on the real route: the typed answers and the unlock '
        'go with it', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('wait'),
        locked: true,
        wrap: (router, child) => QuickExitZone(router: router, child: child),
      );
      expect(s.container.read(datingUnlockedProvider), isTrue);
      await t.enterText(
        find.byKey(const ValueKey('gentle_wait_q3')),
        'Ama typed this',
      );
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
      expect(s.container.read(datingUnlockedProvider), isFalse);
      // The lock itself is protective: still on (D19).
      expect(s.lock.on, isTrue);
      // Back on D0 (no PIN on this phone, so the unlock lets it through):
      // a new read, and nothing typed before is left.
      final reads = s.wait.reads;
      s.router.go(DatingPaths.step('wait'));
      await t.pumpAndSettle();
      expect(s.location, '/dating/setup/wait');
      expect(s.wait.reads, reads + 1);
      expect(find.text('Ama typed this'), findsNothing);
    });
  });
  // Spec 2 W3c (R-40): a step opened with ?from= goes back when it moves
  // on; without it, it walks forward. (A push doesn't change
  // currentConfiguration.uri in go_router 10, so the screen shown is read.)
  testWidgets('from=preview: Continue goes back instead of forward', (t) async {
    final shell = await pumpDatingShell(
      t,
      overrides: [
        datingPreviewGatewayProvider.overrideWithValue(
          FakeDatingPreviewGateway(),
        ),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
        datingPhotosGatewayProvider.overrideWithValue(FakeDatingPhotosGateway()),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
    );
    shell.router.push('${DatingPaths.step('verify')}?from=preview');
    await t.pumpAndSettle();
    expect(find.text("Verify it's you"), findsOneWidget);
    await tapInReach(t, find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text("Verify it's you"), findsNothing);
    expect(find.text('This is what others see'), findsNothing);
    expect(find.textContaining('ME '), findsOneWidget);
    shell.router.push(DatingPaths.step('verify'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('This is what others see'), findsOneWidget);
  });
  // Spec 2 W3c (§3.14): Leave is inside the group, behind the lock. (A push
  // doesn't change currentConfiguration.uri in go_router 10: the screen
  // shown is read.)
  testWidgets('/dating/leave asks for the PIN first when the lock is on', (
    t,
  ) async {
    final shell = await pumpDatingShell(t, locked: true, pinSet: true);
    shell.router.push(DatingPaths.leave);
    await t.pumpAndSettle();
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text('Leave Dating?'), findsNothing);
  });
}
