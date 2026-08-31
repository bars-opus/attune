import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a live provider exists for an individual session', () {
    // The hub refreshes live, but the game SCREENS did not: none of the
    // four had a subscription or a poll, so while waiting on a partner
    // nothing updated until the user tapped something. That is the state
    // a player sits in for most of a turn-based game.
    final src =
        File(
          'lib/features/games/presentation/providers/game_session_live_provider.dart',
        ).readAsStringSync();

    expect(src, contains('gameSessionLiveProvider'));
    expect(
      src,
      contains('PostgresChangeEvent.all'),
      reason:
          'a partner answering is an UPDATE to the session or an INSERT of '
          'a round, and a screen waiting on them needs both',
    );
  });

  test('it watches rounds as well as the session row', () {
    // Most turn-based progress lands in game_session_rounds, not on the
    // session: a partner submitting an answer updates a ROUND. Watching
    // only game_sessions would miss exactly the event the waiting screen
    // exists for.
    final src =
        File(
          'lib/features/games/presentation/providers/game_session_live_provider.dart',
        ).readAsStringSync();

    expect(src, contains("table: 'game_sessions'"));
    expect(src, contains("table: 'game_session_rounds'"));
  });

  test('the channel is torn down with the provider', () {
    final src =
        File(
          'lib/features/games/presentation/providers/game_session_live_provider.dart',
        ).readAsStringSync();

    expect(src, contains('onDispose'));
    expect(src, contains('removeChannel'));
  });

  test('the game routers watch it', () {
    // A StreamProvider nothing listens to is never created, so the
    // subscription would simply never open.
    for (final path in [
      'lib/features/games/this_or_that/presentation/screens/this_or_that_session_router_screen.dart',
      'lib/features/games/truth_or_dare/presentation/screens/truth_or_dare_session_router_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('ref.watch(gameSessionLiveProvider('),
        reason: '$path does not subscribe to its own session',
      );
    }
  });
}
