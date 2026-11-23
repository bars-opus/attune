// Platform phase 2, task 12: the hub and the landing page have routes, under
// the /games/ prefix, and no older Games route takes either path.
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/features/games/platform/shell/game_landing_page.dart';
import 'package:attune/features/games/platform/shell/games_hub_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/game_test_support.dart';

/// The route [location] resolves to: the last match, as the router builds it.
RouteBase _routeAt(GoRouter router, String location) {
  final matches = router.configuration.findMatch(location).matches;
  expect(matches, isNotEmpty, reason: 'no route matches $location');
  return matches.last.route;
}

Matcher _named(String name) =>
    isA<GoRoute>().having((r) => r.name, 'name', name);

/// The GoRoute registered as [name], anywhere in the tree.
GoRoute? _routeNamed(List<RouteBase> routes, String name) {
  for (final route in routes) {
    if (route is GoRoute && route.name == name) return route;
    final nested = _routeNamed(route.routes, name);
    if (nested != null) return nested;
  }
  return null;
}

void main() {
  test('the hub and landing routes exist under the games prefix', () {
    final router = createAppRouter(RoutingNotifier());
    addTearDown(router.dispose);
    expect(router.namedLocation('gamesHub'), '/games/hub');
    expect(
      router.namedLocation(
        'gameLanding',
        pathParameters: {'gameType': 'this_or_that'},
      ),
      '/games/play/this_or_that',
    );
  });

  test('neither new path is taken by an older games route', () {
    // /games/snakes/:relationshipId and /games/word-hunt/:relationshipId are
    // three segments too; the literal second segment must keep them apart.
    final router = createAppRouter(RoutingNotifier());
    addTearDown(router.dispose);
    expect(_routeAt(router, '/games/play/word_hunt'), _named('gameLanding'));
    expect(_routeAt(router, '/games/play/this_or_that'), _named('gameLanding'));
    // Positive controls: the older three-segment routes still resolve to
    // themselves.
    expect(_routeAt(router, '/games/snakes/abc'), _named('snakesGame'));
    expect(_routeAt(router, '/games/word-hunt/abc'), _named('wordHuntGame'));
    // The hub is two segments; no older /games/:something takes it.
    expect(_routeAt(router, '/games/hub'), _named('gamesHub'));
  });

  testWidgets('the routes build the hub, and the landing page for the type '
      'in the path', (tester) async {
    useSurface(tester, phone);
    final router = createAppRouter(RoutingNotifier());
    addTearDown(router.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );

    GoRouterState stateFor(String location, GoRoute route) {
      final match = router.configuration.findMatch(location);
      return GoRouterState(
        router.configuration,
        uri: match.uri,
        matchedLocation: match.uri.path,
        name: route.name,
        path: route.path,
        fullPath: match.fullPath,
        pathParameters: match.pathParameters,
        pageKey: const ValueKey<String>('task-12'),
      );
    }

    final routes = router.configuration.routes;
    final landing = _routeNamed(routes, 'gameLanding')!;
    final landingState = stateFor('/games/play/this_or_that', landing);
    expect(landingState.pathParameters, {'gameType': 'this_or_that'});
    expect(
      landing.builder!(context, landingState),
      isA<GameLandingPage>().having(
        (p) => p.gameType,
        'gameType',
        'this_or_that',
      ),
    );

    final hub = _routeNamed(routes, 'gamesHub')!;
    expect(
      hub.builder!(context, stateFor('/games/hub', hub)),
      isA<GamesHubScreen>(),
    );
  });
}
