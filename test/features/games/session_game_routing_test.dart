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
}
