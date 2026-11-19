import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The route names a game page can push, each stood in for here.
const List<String> standInRouteNames = [
  'gamesHub',
  'gameLanding',
  'thisOrThatSessionRouter',
  'thisOrThatCustomList',
  'thisOrThatSessionHistory',
  'communityFeed',
];

/// Hosts [home] in a GoRouter whose named routes are stand-ins. Each shows
/// `opened:<name>:<detail>`, where detail is the gameType path parameter,
/// else the `type` query parameter, else `extra`, else empty. Names:
/// gamesHub, gameLanding, thisOrThatSessionRouter, thisOrThatCustomList,
/// thisOrThatSessionHistory, communityFeed.
///
/// What `gameHost` provides -- local preferences, a silent sound service and
/// haptics, a light app, a text scale -- but routed, so a page that pushes by
/// name can be followed to where it went. Each stand-in can be popped.
Widget gameRouterHost({
  required Widget home,
  required SharedPreferences prefs,
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  GoRoute standIn(String name, String path) => GoRoute(
    path: path,
    name: name,
    builder: (context, state) => _StandIn(name: name, detail: _detail(state)),
  );

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => home),
      standIn('gamesHub', '/games'),
      standIn('gameLanding', '/games/play/:gameType'),
      standIn('thisOrThatSessionRouter', '/stand-in/session-router'),
      standIn('thisOrThatCustomList', '/stand-in/custom-list'),
      standIn('thisOrThatSessionHistory', '/stand-in/session-history'),
      standIn('communityFeed', '/stand-in/community-feed'),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      soundServiceProvider.overrideWithValue(FakeSoundService()),
      hapticsProvider.overrideWithValue(FakeHaptics()),
      ...overrides,
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto', brightness: brightness),
      routerConfig: router,
      builder:
          (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: app!,
          ),
    ),
  );
}

String _detail(GoRouterState state) {
  return state.pathParameters['gameType'] ??
      state.uri.queryParameters['type'] ??
      state.extra?.toString() ??
      '';
}

class _StandIn extends StatelessWidget {
  const _StandIn({required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    // The app bar brings a Back button whenever there is a page to pop to.
    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text('opened:$name:$detail')),
    );
  }
}
