import 'dart:async';

import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Emits whenever one session or its rounds change.
///
/// The Games hub refreshes live, but the game SCREENS did not: none of the
/// four games had a subscription or a poll, so a player waiting on their
/// partner saw nothing until they tapped something. In a turn-based game
/// that is most of the time.
///
/// Watches BOTH tables because progress lands in both: accepting an
/// invite, a knockout and a completion update game_sessions, while a
/// partner submitting an answer updates a row in game_session_rounds.
/// Subscribing only to the session row would miss the event the waiting
/// screen exists for.
///
/// Emits rather than carrying data, so each screen invalidates the
/// providers it actually reads — the alternative is this file knowing
/// every game's provider graph.
final gameSessionLiveProvider = StreamProvider.family<void, String>((
  ref,
  sessionId,
) async* {
  final supabase = ref.read(supabaseClientProvider);
  final controller = StreamController<void>.broadcast();

  void emit(dynamic _) {
    if (!controller.isClosed) controller.add(null);
  }

  final channel =
      supabase
          .channel('game-session:$sessionId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'game_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: sessionId,
            ),
            callback: emit,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'game_session_rounds',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'session_id',
              value: sessionId,
            ),
            callback: emit,
          )
          .subscribe();

  // A channel outliving its provider leaks a socket subscription for the
  // rest of the session, and these are created per game played.
  ref.onDispose(() {
    unawaited(controller.close());
    unawaited(supabase.removeChannel(channel));
  });

  yield* controller.stream;
});
