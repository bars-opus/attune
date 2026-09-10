import 'dart:io';

import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the client and server agree on which games can be invited', () {
    // A game the client stages but the server refuses is a Send that
    // always fails, with no recourse and no way for the player to tell
    // why. The lists are pinned to each other here rather than
    // discovered in production.
    final migration =
        File(
          'supabase/migrations/20260937110000_game_invite_allowlist_fix.sql',
        ).readAsStringSync();

    final allowed =
        RegExp(r"'([a-z0-9_]+)'")
            .allMatches(
              migration.substring(
                migration.indexOf('SELECT p_game_type IN ('),
                migration.indexOf(');', migration.indexOf('p_game_type IN (')),
              ),
            )
            .map((m) => m.group(1)!)
            .toSet();

    expect(
      allowed,
      kInvitableGameTypes,
      reason: 'the client would stage a game the server refuses',
    );
  });

  test('every invitable game has a display name and a destination', () {
    // A game with no display name renders as a title-cased id in the
    // composer; one with no destination is a card nobody can open.
    final hub =
        File(
          'lib/features/games/presentation/providers/'
          'games_hub_providers.dart',
        ).readAsStringSync();
    final sheet =
        File(
          'lib/features/games/presentation/widgets/chat_games_sheet.dart',
        ).readAsStringSync();

    for (final game in kInvitableGameTypes) {
      expect(
        hub.contains("'$game':"),
        isTrue,
        reason: '$game would render as an id',
      );
      expect(
        sheet.contains("'$game': ChatGameDestination"),
        isTrue,
        reason: 'a $game card could not be opened',
      );
    }
  });

  test('the games left out each have their own way in', () {
    // Not oversights, and this test exists so a later reader does not
    // "fix" them back onto the generic path: each needs setup that
    // game_invite_create deliberately does not do.
    const excluded = {
      // needs journey_id and chapter
      '36_questions',
      // builds rounds in create_this_or_that_session
      'this_or_that',
      // needs total_rounds, current_round and a tone
      'truth_or_dare',
      // no session at all, by spec
      'love_map',
    };

    for (final game in excluded) {
      expect(
        kInvitableGameTypes.contains(game),
        isFalse,
        reason: '$game cannot start from a bare session row',
      );
    }
  });
}
