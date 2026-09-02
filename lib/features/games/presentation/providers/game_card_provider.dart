import 'dart:async';

import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The live state a chat game card renders.
///
/// The card's label is NOT stored on the message row. One message exists
/// per game for the life of that game, and it must read "Let's play" on
/// Monday and "You won" on Friday without a second bubble appearing. So
/// the row carries only game_session_id, and this watches the session.
class GameCardState {
  const GameCardState({
    required this.gameType,
    required this.status,
    required this.currentTurnUserId,
    required this.winnerUserId,
    required this.currentRound,
    required this.totalRounds,
    this.viewerAnswered,
    this.partnerAnswered,
  });

  GameCardState withRoundState({
    required bool? viewerAnswered,
    required bool? partnerAnswered,
  }) {
    return GameCardState(
      gameType: gameType,
      status: status,
      currentTurnUserId: currentTurnUserId,
      winnerUserId: winnerUserId,
      currentRound: currentRound,
      totalRounds: totalRounds,
      viewerAnswered: viewerAnswered,
      partnerAnswered: partnerAnswered,
    );
  }

  final String gameType;
  final String status;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final int? currentRound;
  final int? totalRounds;

  /// For session games only (Mirror, Sliding Scale, Scenario), which have
  /// no turn order: both partners answer the same round independently.
  /// Null for every other game, and while still loading.
  final bool? viewerAnswered;
  final bool? partnerAnswered;

  static GameCardState fromRow(Map<String, dynamic> row) {
    return GameCardState(
      gameType: (row['game_type'] as String?) ?? '',
      status: (row['status'] as String?) ?? '',
      currentTurnUserId: row['current_turn_user_id'] as String?,
      winnerUserId: row['winner_user_id'] as String?,
      currentRound: (row['current_round'] as num?)?.toInt(),
      totalRounds: (row['total_rounds'] as num?)?.toInt(),
    );
  }
}

/// Streams one game session.
///
/// A stream rather than a future: the whole point of the card is that the
/// partner's move changes it without the reader doing anything. Supabase's
/// .stream() gives the initial row and every update on one subscription.
///
/// autoDispose, and this matters: a chat page loads 50 messages, so a
/// conversation with a long game history would otherwise hold a websocket
/// subscription per card for the rest of the session -- every one of them
/// still streaming after the card scrolled out of sight. They are released
/// when no card is watching.
///
/// The 30-second keep-alive stops the opposite problem: scrolling a card
/// off and straight back on would tear down and rebuild its subscription
/// each time, which is slower and noisier than holding it briefly.
final gameCardProvider = StreamProvider.autoDispose
    .family<GameCardState?, String>((ref, sessionId) {
      final link = ref.keepAlive();
      Timer? expiry;

      ref.onCancel(() {
        expiry = Timer(const Duration(seconds: 30), link.close);
      });
      ref.onResume(() {
        expiry?.cancel();
        expiry = null;
      });
      ref.onDispose(() => expiry?.cancel());

      final supabase = ref.watch(supabaseClientProvider);

      // Session games carry no current_turn_user_id -- both partners
      // answer the same round -- so their card needs the per-round answer
      // state to say anything more useful than "Round 2 of 6".
      //
      // Fetched per session update rather than streamed:
      // game_session_rounds holds the answers themselves, and a client
      // must never subscribe to a table it is not allowed to read before
      // the reveal (spec 8.4). The RPC returns booleans only.
      return supabase
          .from('game_sessions')
          .stream(primaryKey: ['id'])
          .eq('id', sessionId)
          .asyncMap((rows) async {
            if (rows.isEmpty) return null;
            final state = GameCardState.fromRow(rows.first);

            // Asked for every game that does NOT carry its own turn.
            //
            // This was a list of the three session games, which silently
            // excluded This or That, Truth or Dare and 36 Questions --
            // their cards could only ever show a round count, because the
            // one call that knows whose move it is was never made for
            // them.
            //
            // Inverted so the question is "does this session already say
            // whose turn it is?" rather than a list that has to be
            // remembered every time a game is added. Only Paint Ball sets
            // current_turn_user_id.
            if (state.status != 'active' || state.currentTurnUserId != null) {
              return state;
            }

            try {
              final result = await supabase.rpc(
                'session_game_round_state',
                params: {'p_session_id': sessionId},
              );
              if (result is List && result.isNotEmpty) {
                final row = Map<String, dynamic>.from(result.first as Map);
                return state.withRoundState(
                  viewerAnswered: row['viewer_answered'] as bool?,
                  partnerAnswered: row['partner_answered'] as bool?,
                );
              }
            } catch (_) {
              // Falls back to the round-count label rather than blanking
              // the card: a failed receipt read must not remove a live
              // game from the conversation.
            }
            return state;
          });
    });

/// The games where both partners answer the same round independently,
/// so there is no turn to read from the session row.
///
/// Kept for tests and callers that need to name them; the card no longer
/// gates on it, because a list of game types is a thing to forget when a
/// game is added, and forgetting it makes a card silently useless.
bool isSessionGame(String gameType) =>
    gameType == 'mirror' ||
    gameType == 'sliding_scale' ||
    gameType == 'scenario';
