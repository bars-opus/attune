import 'dart:io';

import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the client and server agree on which games can be invited', () {
    // A game the client stages but the server refuses is a Send that
    // always fails, with no recourse and no way for the player to tell
    // why. The lists are pinned to each other here rather than
    // discovered in production.
    //
    // Reads the LATEST migration to define the allowlist: an earlier one
    // narrowed it to six while four games were unfinished, and a test
    // anchored on that file would now be asserting history.
    final migration =
        File(
          'supabase/migrations/20260937120000_game_invite_all_games.sql',
        ).readAsStringSync();

    final body = migration.substring(
      migration.indexOf('SELECT p_game_type IN ('),
      migration.indexOf(');', migration.indexOf('p_game_type IN (')),
    );
    final allowed =
        RegExp(
          r"'([a-z0-9_]+)'",
        ).allMatches(body).map((m) => m.group(1)!).toSet();

    expect(
      allowed,
      kInvitableGameTypes,
      reason: 'the client would stage a game the server refuses',
    );
    expect(allowed, hasLength(10), reason: 'a game lost its invitation');
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

  test('the games needing a session shape are given one', () {
    // These four could not start from a bare session row, which is why
    // they had no invitation at first. The RPC now supplies what each
    // needs, and this pins the reasons so a later reader does not strip
    // the special cases back out.
    final migration =
        File(
          'supabase/migrations/20260937120000_game_invite_all_games.sql',
        ).readAsStringSync();

    // Truth or Dare and This or That read total_rounds; a bare row made
    // their cards say "Round 1 of 0".
    expect(migration.contains("WHEN 'truth_or_dare' THEN 10"), isTrue);
    expect(migration.contains("WHEN 'this_or_that'  THEN 10"), isTrue);

    // 36 Questions is invisible to its own queries without a journey.
    expect(migration.contains("WHEN '36_questions'  THEN 12"), isTrue);
    expect(migration.contains('thirty_six_question_journeys'), isTrue);
    expect(migration.contains("p_game_type = '36_questions'"), isTrue);

    // Love Map is sessionless by design, so its invitation opens active
    // -- nothing in Love Map ever accepts one, and the card would
    // otherwise read "Waiting for them" forever.
    final loveMap =
        File(
          'supabase/migrations/20260937130000_love_map_invite_shape.sql',
        ).readAsStringSync();
    expect(loveMap.contains("IF p_game_type = 'love_map' THEN"), isTrue);
    expect(loveMap.contains("SET status = 'active'"), isTrue);
  });
}
