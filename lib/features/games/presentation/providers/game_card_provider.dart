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

      return supabase
          .from('game_sessions')
          .stream(primaryKey: ['id'])
          .eq('id', sessionId)
          .map(
            (rows) => rows.isEmpty ? null : GameCardState.fromRow(rows.first),
          );
    });
