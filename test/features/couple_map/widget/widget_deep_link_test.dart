// test/features/couple_map/widget/widget_deep_link_test.dart
import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/couple_map/widget/presentation/widget_deep_link.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart'
    show PlanningHomeTab;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<GoRouter> pump(WidgetTester t, {String initial = '/'}) async {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Text('home')),
      GoRoute(
        path: RouteNames.neutralScreen,
        builder: (_, __) => const Text('neutral'),
      ),
      GoRoute(
        path: RouteNames.planning,
        builder:
            (_, s) =>
                Text('planning ${s.extra} ${s.uri.queryParameters['tab']}'),
      ),
    ],
  );
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
  await t.pumpAndSettle();
  return router;
}

Future<bool> open(
  GoRouter r, {
  bool signedIn = true,
  Future<String?> Function()? rel,
  bool flag = true,
}) => openPlanningFromLink(
  r,
  PlanningHomeTab.map,
  signedIn: () => signedIn,
  relationshipId: rel ?? () async => 'r1',
  mapEnabled: () async => flag,
);

void main() {
  test('reads only attune://planning links', () {
    expect(
      planningTabFromLink(Uri.parse(coupleWidgetLink)),
      PlanningHomeTab.map,
    );
    expect(
      planningTabFromLink(Uri.parse('attune://planning')),
      PlanningHomeTab.planning,
    );
    expect(
      planningTabFromLink(Uri.parse('attune://planning?tab=bogus')),
      PlanningHomeTab.planning,
    );
    expect(planningTabFromLink(Uri.parse('attune://invite?code=abc')), isNull);
    expect(planningTabFromLink(Uri.parse('https://planning?tab=map')), isNull);
    expect(planningTabFromLink(Uri.parse('attune://auth/callback')), isNull);
  });

  test('the link carries no ids and no homeWidget item (spec §6.5)', () {
    final uri = Uri.parse(coupleWidgetLink);
    expect(uri.queryParameters.keys, ['tab']);
  });

  testWidgets('a signed-in, paired person lands on Planning → Map', (t) async {
    final r = await pump(t);
    expect(await open(r), isTrue);
    await t.pumpAndSettle();
    expect(find.text('planning r1 map'), findsOneWidget);
  });

  testWidgets('never over quick exit\'s neutral screen (Review Focus 3)', (
    t,
  ) async {
    final r = await pump(t, initial: RouteNames.neutralScreen);
    expect(await open(r), isFalse);
    await t.pumpAndSettle();
    expect(find.text('neutral'), findsOneWidget);
  });

  testWidgets('quick exit during the lookup still wins', (t) async {
    final r = await pump(t);
    final gate = Completer<String?>();
    final pending = open(r, rel: () => gate.future);
    r.go(RouteNames.neutralScreen);
    await t.pumpAndSettle();
    gate.complete('r1');
    expect(await pending, isFalse);
    await t.pumpAndSettle();
    expect(find.text('neutral'), findsOneWidget);
  });

  testWidgets(
    'signed out, unpaired, a failing lookup, or the flag off: nothing',
    (t) async {
      final r = await pump(t);
      expect(await open(r, signedIn: false), isFalse);
      expect(await open(r, rel: () async => null), isFalse);
      expect(
        await open(r, rel: () async => throw Exception('offline')),
        isFalse,
      );
      expect(await open(r, flag: false), isFalse);
      await t.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    },
  );

  testWidgets('the same link twice at once (cold start) pushes once', (
    t,
  ) async {
    final r = await pump(t);
    final gate = Completer<String?>();
    final first = open(r, rel: () => gate.future);
    final second = open(r);
    gate.complete('r1');
    expect(await first, isTrue);
    expect(await second, isFalse);
    await t.pumpAndSettle();
    expect(
      r.routerDelegate.currentConfiguration.matches
          .where((m) => m.matchedLocation == RouteNames.planning)
          .length,
      1,
    );
  });

  testWidgets('already on Planning: no second copy pushed', (t) async {
    final r = await pump(t, initial: RouteNames.planning);
    expect(await open(r), isFalse);
  });

  test('main.dart routes planning links before invites', () {
    final source = File('lib/main.dart').readAsStringSync();
    final handler = source.substring(source.indexOf('void _handleDeepLink'));
    expect(handler.indexOf('planningTabFromLink(uri)'), greaterThan(-1));
    expect(
      handler.indexOf('planningTabFromLink(uri)'),
      lessThan(handler.indexOf('_extractInviteCode(uri)')),
    );
  });
}
