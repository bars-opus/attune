// Spec 2 W8a (§3.0 Lock, §3.13, §3.14, §7.4, §7.7; I-9; carry: every
// Dating push type and route honours the Dating lock): with the lock on,
// every Dating route asks for the Safety PIN first, whether it is opened
// from inside the app, by a deep link (the platform's route, warm or as
// the cold start's first route) or as the first page of a cold start, and
// nothing of the page is built until then: the route's redirect builds no
// page at all (checked every frame), and the page's own gate, reached with
// no redirect, builds none of what it guards (fix round 1, M-1, M-3).
// Every Dating push the server can send (me_update, me_checkin; the old
// dating_mutual_match for one release) opens Me or the check-in, the
// check-in behind the PIN. The route list is read from datingRoutes(), so
// a route a later wave adds is covered without editing this file.
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/dating_shell.dart';

/// Every Dating route with its full path (the unlock included).
List<(String, GoRoute)> datingGoRoutes() {
  final routes = <(String, GoRoute)>[];
  void walk(List<RouteBase> list, String prefix) {
    for (final r in list) {
      if (r is GoRoute) {
        final full = r.path.startsWith('/') ? r.path : '$prefix/${r.path}';
        routes.add((full, r));
        walk(r.routes, full);
      } else {
        walk(r.routes, prefix);
      }
    }
  }

  walk(datingRoutes(signedIn: () => true), '');
  return routes;
}

/// A route's path with sample parameters.
String sampleLocation(String path) => path.replaceAllMapped(
  RegExp(r':(\w+)'),
  (m) => m[1] == 'step' ? 'how' : 'm1',
);

/// Every Dating route's path with sample parameters (the unlock aside).
List<String> datingLocations() => [
  for (final (p, _) in datingGoRoutes())
    if (p != DatingPaths.unlock) sampleLocation(p),
];

/// The same pages under /raw with no redirect: what each page's own gate
/// does when nothing redirects first.
List<RouteBase> rawDatingRoutes() => [
  for (final (p, r) in datingGoRoutes())
    if (p != DatingPaths.unlock)
      GoRoute(path: '/raw$p', builder: r.builder, pageBuilder: r.pageBuilder),
];

/// Pumps a second frame by frame, checking [each] after every frame
/// (pumpAndSettle shows only the end). Not settled after: once the unlock
/// asks, its button's busy spinner turns until the sheet closes.
Future<void> settleChecking(WidgetTester t, void Function() each) async {
  each();
  for (var i = 0; i < 60; i++) {
    await t.pump(const Duration(milliseconds: 16));
    each();
  }
}

/// No Dating page is built at all, on stage or off (each one is wrapped in
/// its gate).
void noDatingPageBuilt() =>
    expect(find.byType(DatingLockGate, skipOffstage: false), findsNothing);

Future<void> deepLink(WidgetTester t, String location) =>
    t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        MethodCall('pushRouteInformation', {
          'location': location,
          'state': null,
        }),
      ),
      (_) {},
    );

void expectUnlockFor(DatingShell s, String location) {
  expect(s.location, startsWith('${DatingPaths.unlock}?from='));
  expect(
    Uri.parse(s.location).queryParameters['from'],
    location,
    reason: 'the unlock comes back to the place asked for',
  );
}

void main() {
  final locations = datingLocations();

  test('the route list is the whole Dating group', () {
    expect(locations, contains(DatingPaths.today));
    expect(locations, contains(DatingPaths.checkin));
    expect(locations, contains(DatingPaths.plan('m1')));
    // The gate check's own probe runs on this one (below).
    expect(locations, contains(DatingPaths.notOpen));
    expect(locations.every((l) => l.startsWith('/dating/')), isTrue);
    expect(locations.length, greaterThanOrEqualTo(14));
  });

  for (final location in locations) {
    testWidgets('locked: $location asks for the PIN first, from inside the '
        'app and as a cold start', (t) async {
      final s = await pumpDatingShell(
        t,
        locked: true,
        pinSet: true,
        extraRoutes: rawDatingRoutes(),
      );
      // Inside the app: the redirect builds no page, in any frame.
      s.router.go(location);
      await settleChecking(t, noDatingPageBuilt);
      expectUnlockFor(s, location);
      // One Dating page is open at the end: the unlock.
      expect(DatingPageWatch.open, 1);
      // A deep link while the app runs (the platform's route): the same.
      s.router.go('/home');
      await t.pumpAndSettle();
      await deepLink(t, location);
      await settleChecking(t, noDatingPageBuilt);
      expectUnlockFor(s, location);
      expect(s.container.read(datingUnlockedProvider), isFalse);
      // With no redirect, the page's own gate builds nothing it guards.
      s.router.go('/home');
      await t.pumpAndSettle();
      var gates = 0;
      s.router.go('/raw$location');
      await settleChecking(t, () {
        // Off stage too: a page entering is built before it shows.
        for (final g in t.widgetList<DatingLockGate>(
          find.byType(DatingLockGate, skipOffstage: false),
        )) {
          gates++;
          expect(find.byWidget(g.child, skipOffstage: false), findsNothing);
        }
      });
      expect(gates, greaterThan(0), reason: 'the gate was reached');
      expect(s.location, startsWith('${DatingPaths.unlock}?from='));
      if (location == DatingPaths.notOpen) {
        // The check above can see a page: unlocked, the gate shows it.
        final open = await pumpDatingShell(t, extraRoutes: rawDatingRoutes());
        open.router.go('/raw$location');
        await t.pumpAndSettle();
        final g = t.widget<DatingLockGate>(
          find.byType(DatingLockGate, skipOffstage: false),
        );
        expect(find.byWidget(g.child, skipOffstage: false), findsOneWidget);
      }
      // A cold start on that page.
      final cold = await pumpDatingShell(
        t,
        initial: location,
        locked: true,
        pinSet: true,
      );
      expectUnlockFor(cold, location);
      expect(DatingPageWatch.open, 1);
      // A cold start from a link (the platform's first route).
      t.platformDispatcher.defaultRouteNameTestValue = location;
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      final link = await pumpDatingShell(t, locked: true, pinSet: true);
      t.platformDispatcher.clearDefaultRouteNameTestValue();
      expectUnlockFor(link, location);
      expect(DatingPageWatch.open, 1);
    });
  }

  testWidgets('a deep link (the platform\'s route) into a chat asks for the '
      'PIN first', (t) async {
    final s = await pumpDatingShell(t, locked: true, pinSet: true);
    await deepLink(t, '/dating/chat/m1');
    await t.pumpAndSettle();
    expectUnlockFor(s, '/dating/chat/m1');
    expect(s.container.read(datingUnlockedProvider), isFalse);
  });

  for (final (type, route, lockedTo, openTo) in [
    ('me_update', 'me', '/home?tab=me', '/home?tab=me'),
    ('dating_mutual_match', 'me', '/home?tab=me', '/home?tab=me'),
    (
      'me_checkin',
      'me_checkin',
      '${DatingPaths.unlock}?from=',
      DatingPaths.checkin,
    ),
  ]) {
    for (final locked in [true, false]) {
      testWidgets('the $type push (locked: $locked)', (t) async {
        late BuildContext tapContext;
        final s = await pumpDatingShell(
          t,
          initial: '/somewhere',
          locked: locked,
          pinSet: true,
          extraRoutes: [
            GoRoute(
              path: '/somewhere',
              builder:
                  (context, _) => Builder(
                    builder: (c) {
                      tapContext = c;
                      return const Scaffold(body: Text('ELSEWHERE'));
                    },
                  ),
            ),
          ],
        );
        buildNanoEmbryoNotificationConfig().onNotificationTap!(
          AppNotification(
            id: 'n1',
            title: 'Attune',
            body: 'You have something new in Attune.',
            data: {'type': type, 'route': route},
            createdAt: DateTime.utc(2026, 11, 22, 9),
          ),
          tapContext,
        );
        await t.pumpAndSettle();
        expect(s.location, startsWith(locked ? lockedTo : openTo));
        if (locked && type == 'me_checkin') {
          // Fix round 1 (M-2): the unlock comes back to the check-in.
          expect(
            Uri.parse(s.location).queryParameters['from'],
            DatingPaths.checkin,
          );
        }
      });
    }
  }
}
