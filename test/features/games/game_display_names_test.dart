import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every game type the app can create has a display name', () {
    // The hub's switch named only three types; everything else fell to
    // default and showed the RAW game_type. So a Mirror invite read as
    // "mirror" and a Paint Ball one as "paint_ball" — the partner's only
    // notice that a game is waiting, rendered as a database value.
    //
    // The list is every type that can reach game_sessions: the six in the
    // game_questions CHECK constraint, plus 36_questions and paint_ball,
    // which write the table without appearing in it.
    const everyType = {
      'this_or_that': 'This or That',
      'truth_or_dare': 'Truth or Dare',
      '36_questions': '36 Questions',
      'mirror': 'Mirror',
      'sliding_scale': 'Sliding Scale',
      'scenario': 'Scenario',
      'love_map': 'Love Map',
      'paint_ball': 'Paint Ball',
    };

    for (final entry in everyType.entries) {
      expect(
        gameTypeDisplayName(entry.key),
        entry.value,
        reason: '${entry.key} must not surface as a raw database value',
      );
    }
  });

  test('an unknown type degrades to something readable', () {
    // A type added to the DB before the app knows about it should not read
    // as snake_case in the UI.
    expect(gameTypeDisplayName('some_new_game'), 'Some New Game');
  });
}
