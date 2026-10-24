// Spec 3 (forum removal) §5: a forum push sent before the producers stopped
// can still be tapped from the tray. Whatever its payload, it lands on home,
// never on a removed route. Drives the real tap handler against a real
// GoRouter, as app_shell_keep_mounted_test.dart does.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/state_probe.dart';

/// A context below the router, captured by the start screen.
late BuildContext _tapContext;

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder:
          (_, __) => Builder(
            builder: (context) {
              _tapContext = context;
              return const StateProbe('START');
            },
          ),
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (_, __) => const StateProbe('HOME'),
    ),
    GoRoute(
      path: RouteNames.opinionLoader,
      builder: (_, state) => StateProbe('OPINION ${state.extra}'),
    ),
  ],
);

/// Pumps the router, taps a push carrying [data], and returns the location
/// of every screen on the stack, bottom first. A `go` replaces the stack
/// (`[home]`); a `push` stacks onto the start screen (`['/', …]`), so the
/// two read differently.
Future<List<String>> _tap(
  WidgetTester tester,
  Map<String, dynamic> data,
) async {
  final router = _router();
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  final config = buildNanoEmbryoNotificationConfig();
  config.onNotificationTap!(
    AppNotification(
      id: 'n1',
      title: 'Forum check',
      body: 'Tap me',
      data: data,
      createdAt: DateTime(2026, 10, 25),
    ),
    _tapContext,
  );
  await tester.pumpAndSettle();
  return [
    for (final match in router.routerDelegate.currentConfiguration.matches)
      match.matchedLocation,
  ];
}

void main() {
  const retired = ['forum_topic_activated', 'forum_activity', 'forum_quiet'];
  final payloads = <String, Map<String, dynamic> Function(String type)>{
    'with a topic_id': (t) => {'type': t, 'topic_id': 'topic-1'},
    'with an empty topic_id': (t) => {'type': t, 'topic_id': ''},
    'with no topic_id': (t) => {'type': t},
  };

  for (final type in retired) {
    for (final entry in payloads.entries) {
      testWidgets('$type ${entry.key} lands on home', (tester) async {
        expect(await _tap(tester, entry.value(type)), [RouteNames.home]);
        expect(find.text('HOME 0'), findsOneWidget);
      });
    }
  }

  testWidgets('a retired push with a non-string topic_id lands on home', (
    tester,
  ) async {
    // A hand-built or legacy row can carry a number here; the old handler
    // cast it with `as String?` and threw before navigating anywhere.
    expect(await _tap(tester, {'type': 'forum_activity', 'topic_id': 42}), [
      RouteNames.home,
    ]);
    expect(tester.takeException(), isNull);
  });

  for (final type in ['forum_content_removed', 'forum_posting_banned']) {
    testWidgets('$type (kept Opinions moderation notice) lands on home', (
      tester,
    ) async {
      expect(await _tap(tester, {'type': type, 'opinion_id': 'op-1'}), [
        RouteNames.home,
      ]);
    });
  }

  testWidgets('opinion_liked still opens the opinion loader', (tester) async {
    expect(
      await _tap(tester, {'type': 'opinion_liked', 'opinion_id': 'op-1'}),
      ['/', RouteNames.opinionLoader],
    );
    expect(find.text('OPINION op-1 0'), findsOneWidget);
  });
}
