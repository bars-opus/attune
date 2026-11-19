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
  ///
  /// But not past the player coming back: a screen that replaces itself
  /// (Play again) never completes the push it came from, so the page, not
  /// the future, decides when the start is over -- see [_resumed].
  bool _busy = false;

  /// Which start [_busy] belongs to. Coming back moves it on, so a start
  /// that ends late cannot free a newer one.
  int _run = 0;

  /// Whether this page's route was in front at the last look. Null before
  /// the first.
  bool? _wasCurrent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depends on the route's isCurrent alone, so this runs again exactly
    // when something covers the page or stops covering it.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && _wasCurrent == false) _resumed();
    _wasCurrent = current;
  }

  /// The page is in front again after a game, a sheet or anything else
  /// covered it.
  void _resumed() {
    // Called while the page is about to rebuild, so no setState.
    _busy = false;
    _run++;
    // Not now: re-reading may invalidate a provider, which throws during
    // build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(gameRegistryProvider)
          .byType(widget.gameType)
          ?.controller
          ?.onResume(ref);
    });
  }

  Future<void> _runOnce(FutureOr<void> Function() action) async {
    // The only guard against two taps in one frame: the button is not
    // rebuilt as busy until the next one.
    if (_busy) return;
    final run = ++_run;
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
      if (mounted && run == _run) setState(() => _busy = false);
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
