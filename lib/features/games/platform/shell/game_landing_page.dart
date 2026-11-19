import 'dart:async';

import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/games_catalogue.dart';
import 'package:attune/features/games/platform/shell/game_how_to_play_sheet.dart';
import 'package:attune/features/games/platform/shell/game_landing_screen.dart';
import 'package:attune/features/games/platform/shell/game_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The page a game opens on. Route: /games/play/:gameType.
///
/// Finds the game in the registry and asks its controller where the couple
/// stands, then shows the landing screen for it.
class GameLandingPage extends ConsumerStatefulWidget {
  const GameLandingPage({super.key, required this.gameType});

  /// The `game_sessions.game_type` value the route names.
  final String gameType;

  @override
  ConsumerState<GameLandingPage> createState() => _GameLandingPageState();
}

class _GameLandingPageState extends ConsumerState<GameLandingPage> {
  /// A start asked for by the button or a row is still running. A
  /// controller's start usually lasts until the game screen it opened is
  /// closed, so this is held for that long: a second tap meanwhile would
  /// start a second game.
  bool _busy = false;

  Future<void> _runOnce(FutureOr<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error, stack) {
      // Reported, not rethrown: nothing awaits a tap, so a rethrow would
      // surface as an uncaught zone error with no screen context. And not
      // swallowed: FlutterError.onError is where the app's failures go.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'games',
          context: ErrorDescription('while opening ${widget.gameType}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final definition = ref.watch(gameRegistryProvider).byType(widget.gameType);
    if (definition == null) return const _UnknownGame();

    final controller = definition.controller;
    final live = controller?.watchLanding(ref);

    if (controller == null ||
        live == null ||
        !_canOpen(definition, live.status)) {
      return GameLandingScreen(
        definition: definition,
        state: const GameLandingState(status: GameLandingStatus.comingSoon),
        onHowToPlay: _howToPlay(definition),
      );
    }

    final entries = [
      for (final entry in controller.entries(context, ref, live))
        GameEntry(
          title: entry.title,
          subtitle: entry.subtitle,
          onTap:
              entry.onTap == null
                  ? null
                  : (rowContext) => _runOnce(() => entry.onTap!(rowContext)),
        ),
    ];

    return GameLandingScreen(
      definition: definition,
      state: live,
      entries: entries,
      busy: _busy,
      onPrimary: () => _runOnce(() => controller.onPrimary(context, ref, live)),
      onRemind:
          live.canRemind
              ? () => _runOnce(() => controller.onRemind(context, ref, live))
              : null,
      onHowToPlay: _howToPlay(definition),
    );
  }

  /// A coming-soon game opens only on a game already under way: one started
  /// before it was pulled back stays reachable, but a new one cannot begin.
  /// Its controller reads `fresh` when nothing is in progress, which would
  /// otherwise show an enabled Play.
  static bool _canOpen(GameDefinition definition, GameLandingStatus status) {
    if (definition.availability == GameAvailability.launch) return true;
    return switch (status) {
      GameLandingStatus.invited ||
      GameLandingStatus.yourTurn ||
      GameLandingStatus.waiting => true,
      _ => false,
    };
  }

  VoidCallback? _howToPlay(GameDefinition definition) {
    if (definition.howToPlay.isEmpty) return null;
    return () => showGameHowToPlay(context, definition: definition);
  }
}

/// A route naming a game this build does not know: one added to the
/// database first, or a stale link.
class _UnknownGame extends StatelessWidget {
  const _UnknownGame();

  @override
  Widget build(BuildContext context) {
    return const GameScaffold(
      // The grey every not-yet-playable game wears: no game's colour.
      theme: GameTheme(primary: GameColors.comingSoon),
      title: GameStrings.games,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            GameStrings.notAvailable,
            textAlign: TextAlign.center,
            style: TextStyle(color: GameTheme.onGround, fontSize: 17),
          ),
        ),
      ),
    );
  }
}
