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
  });

  final String gameType;
  final String status;
  final String? currentTurnUserId;
  final String? winnerUserId;
  final int? currentRound;
  final int? totalRounds;

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
final gameCardProvider = StreamProvider.family<GameCardState?, String>((
  ref,
  sessionId,
) {
  final supabase = ref.watch(supabaseClientProvider);

  return supabase
      .from('game_sessions')
      .stream(primaryKey: ['id'])
      .eq('id', sessionId)
      .map((rows) => rows.isEmpty ? null : GameCardState.fromRow(rows.first));
});
