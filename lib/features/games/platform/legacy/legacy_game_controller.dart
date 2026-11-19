import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_session_status.dart';
import 'package:attune/features/games/platform/legacy/legacy_game_opener.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// For a game not yet redrawn on the shell: reads its state from the shared
/// session list and opens the screens it has today.
class LegacyGameController extends GameController {
  const LegacyGameController(this.gameType);

  /// The `game_sessions.game_type` value.
  final String gameType;

  @override
  GameLandingState watchLanding(WidgetRef ref) {
    // The list is fetched once; a session event (the partner inviting,
    // moving or finishing) fetches it again.
    ref.listen<AsyncValue<void>>(gameSessionEventsProvider, (_, next) {
      if (next.hasValue) ref.invalidate(activeGamesProvider);
    });

    final games = ref.watch(activeGamesProvider);
    // Kept through a refetch, so the page does not flash back to loading.
    final rows = games.valueOrNull;
    if (rows == null) {
      // A failed read is a fresh start, not a dead button: the game's own
      // screens resume a session that is already open.
      return GameLandingState(
        status:
            games.hasError
                ? GameLandingStatus.fresh
                : GameLandingStatus.loading,
      );
    }

    // The list is newest first, so the first match is the current game.
    for (final row in rows) {
      if (row['game_type'] != gameType) continue;
      final sessionId = row['id'] as String?;
      if (sessionId == null) continue;
      return watchSessionLanding(
        ref,
        sessionId: sessionId,
        initiatorId: row['initiator_id'] as String?,
      );
    }
    return const GameLandingState(status: GameLandingStatus.fresh);
  }

  @override
  void onResume(WidgetRef ref) {
    // A game started or finished from the screens this page opened may not
    // have sent an event the list heard: fetch it again.
    ref.invalidate(activeGamesProvider);
  }

  @override
  Future<void> onPrimary(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) {
    // The status decides, never the id: a fresh or finished state can still
    // carry the id of a session that is over, and Play or Play again must
    // start a new game rather than reopen the old one.
    final sessionId = switch (state.status) {
      GameLandingStatus.invited ||
      GameLandingStatus.yourTurn ||
      GameLandingStatus.waiting => state.sessionId,
      _ => null,
    };
    return ref.read(legacyGameOpenerProvider)(
      context,
      gameType,
      sessionId: sessionId,
    );
  }

  @override
  Future<void> openSession(
    BuildContext context,
    WidgetRef ref, {
    required String sessionId,
  }) {
    return ref.read(legacyGameOpenerProvider)(
      context,
      gameType,
      sessionId: sessionId,
    );
  }
}
