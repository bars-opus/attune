import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every invitable game on the client is invitable on the server', () {
    // The server allowlists game_type because the value reaches a chat
    // message's content (game_invite_type_allowed). If the client offers
    // a game the server does not accept, Send fails with a generic
    // refusal and no amount of retrying helps -- so the two lists are
    // pinned to each other here rather than discovered in production.
    final migration =
        File(
          'supabase/migrations/20260937100000_generic_game_invites.sql',
        ).readAsStringSync();

    final hub =
        File(
          'lib/features/games/presentation/providers/games_hub_providers.dart',
        ).readAsStringSync();

    const games = [
      'this_or_that',
      'truth_or_dare',
      '36_questions',
      'mirror',
      'sliding_scale',
      'scenario',
      'love_map',
      'paint_ball',
      'snakes_and_ladders',
      'word_hunt',
    ];

    for (final game in games) {
      expect(
        migration.contains("'$game'"),
        isTrue,
        reason: '$game cannot be invited: the server would refuse it',
      );
      expect(
        hub.contains("'$game'"),
        isTrue,
        reason: '$game has no display name and would render as an id',
      );
    }
  });

  test('the sheet can map every invitable game to a destination', () {
    // A game with no destination cannot be opened once its card exists,
    // so the invitation would be a dead end.
    final sheet =
        File(
          'lib/features/games/presentation/widgets/chat_games_sheet.dart',
        ).readAsStringSync();

    const games = [
      'this_or_that',
      'truth_or_dare',
      '36_questions',
      'mirror',
      'sliding_scale',
      'scenario',
      'love_map',
      'paint_ball',
      'snakes_and_ladders',
      'word_hunt',
    ];

    for (final game in games) {
      expect(
        sheet.contains("'$game': ChatGameDestination"),
        isTrue,
        reason: 'a $game card could not be opened',
      );
    }
  });
}
