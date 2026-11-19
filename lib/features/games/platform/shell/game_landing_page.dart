import 'dart:async';

import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/games_catalogue.dart';
import 'package:attune/features/games/platform/shell/game_how_to_play_sheet.dart';
import 'package:attune/features/games/platform/shell/game_landing_screen.dart';
import 'package:attune/features/games/platform/shell/game_route_resume.dart';
import 'package:attune/features/games/platform/shell/game_scaffold.dart';
import 'package:attune/features/games/platform/shell/game_tap_guard.dart';
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

class _GameLandingPageState extends ConsumerState<GameLandingPage>
    with GameRouteResume<GameLandingPage>, GameTapGuard<GameLandingPage> {
  /// A start asked for by the button or a row is still running (a consent
  /// dialog, the call that creates the game, the push) is drawn busy: a
  /// second tap meanwhile would start a second game.
  @override
  void onTapHeldChanged() => setState(() {});

  /// The page is in front again after a game, a sheet or anything else
  /// covered it: the game re-reads its state.
  @override
  void onRouteResumed() {
    ref
        .read(gameRegistryProvider)
        .byType(widget.gameType)
        ?.controller
        ?.onResume(ref);
  }

  Future<void> _runOnce(FutureOr<void> Function() action) =>
      runOnce(widget.gameType, action);

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
      busy: tapHeld,
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
