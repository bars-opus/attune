import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each session game has a distinct route', () {
    final routes = {
      RouteNames.mirrorGame,
      RouteNames.slidingScaleGame,
      RouteNames.scenarioGame,
    };
    // A copy-paste slip that pointed two games at one path would send a
    // user to the wrong game with no compile error.
    expect(routes.length, 3);
    for (final route in routes) {
      expect(route.startsWith('/'), isTrue);
    }
  });

  test('no session-game route depends on GoRouter extra', () async {
    // The previous branch shipped routes that read
    // `state.extra as SessionGameQuestion?` while every caller passed
    // nothing, so all three games rendered "Question unavailable." The
    // controller now supplies the question, so no route should read
    // extra at all — this asserts the regression cannot come back.
    final source = await File('lib/app/routing/app_router.dart').readAsString();

    // Scoped to the three game routes only: state.extra is used
    // legitimately by ~60 other routes in this file, so an unscoped
    // search would be permanently red. The window runs from the first
    // game route to the end of the last one — located by the next
    // GoRoute after it rather than a fixed character count, so the
    // assertion cannot silently under-scope if that route grows.
    final start = source.indexOf("name: 'mirrorGame'");
    final lastRoute = source.indexOf("name: 'scenarioGame'");
    final afterLast = source.indexOf('GoRoute(', lastRoute);
    final gameRouteBlock = source.substring(
      start,
      afterLast == -1 ? source.length : afterLast,
    );

    expect(start, isNot(-1), reason: 'mirrorGame route not found');
    expect(lastRoute, isNot(-1), reason: 'scenarioGame route not found');
    expect(gameRouteBlock.contains('state.extra'), isFalse);
    expect(gameRouteBlock.contains('Question unavailable'), isFalse);
  });
}
