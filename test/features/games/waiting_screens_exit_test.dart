import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every screen that waits on a partner must let the player leave.
///
/// Session games, 36 Questions and Truth or Dare all park a player on a
/// polling screen until their partner acts -- which in a couples app can
/// be hours. Two of them had no way out at all: Truth or Dare's
/// partner-watching screen had an AppBar with no back button, so the only
/// escape was killing the app.
///
/// Source-level because these screens need a live session, a partner and
/// a poll to reach their waiting state; a widget test would assert
/// against a spinner rather than the behaviour. What must hold is that
/// none of them is a dead end.
void main() {
  const waitingScreens = <String, String>{
    'thirty_six_waiting_screen':
        'lib/features/games/thirty_six_questions/presentation/screens/'
            'thirty_six_waiting_screen.dart',
    'partner_watching_screen':
        'lib/features/games/truth_or_dare/presentation/screens/'
            'partner_watching_screen.dart',
    'this_or_that_waiting_screen':
        'lib/features/games/this_or_that/presentation/screens/'
            'waiting_screen.dart',
  };

  waitingScreens.forEach((name, path) {
    test('$name offers a way out of the wait', () {
      final source = File(path).readAsStringSync();

      expect(
        source.contains('leading: IconButton'),
        isTrue,
        reason:
            '$name waits on the partner indefinitely and must not rely on '
            'an implicit back button that a full-screen route may not show',
      );

      // The exit must be confirmed, not immediate: the player is mid-game
      // and a mis-tap should not drop them out of it.
      expect(
        source.contains('showDialog'),
        isTrue,
        reason: '$name should confirm before leaving a game in progress',
      );
    });
  });

  test('the session-game wait hands off to the chat', () {
    // Different shape from the others: it does not pop itself, it tells
    // the flow scaffold to, so the game card can take over the state.
    final source =
        File(
          'lib/features/games/session_games/presentation/screens/'
          'session_game_waiting_screen.dart',
        ).readAsStringSync();

    expect(source.contains('onLeaveToChat'), isTrue);
    expect(
      source.contains('Back to chat'),
      isTrue,
      reason: 'the player must be able to leave before the grace window',
    );
  });
}
