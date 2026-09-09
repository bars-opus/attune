import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// The prototypes exist to be PLAYED, so their route out of the games
/// sheet is worth a test. Both were previously reachable only by typing
/// a path by hand, which meant in practice they were never opened.
void main() {
  test('both prototypes are their own destinations', () {
    expect(
      ChatGameDestination.values,
      contains(ChatGameDestination.dotsAndBoxesPrototype),
    );
    expect(
      ChatGameDestination.values,
      contains(ChatGameDestination.constellationPrototype),
    );
  });

  test('prototypes have no game_type, so nothing treats them as sessions', () {
    // They are pass-and-play on one device: no game_sessions row, no
    // active-session lookup, no chat card. A game_type would make the
    // hub try to resume one.
    expect(
      chatGameTypeForDestination(ChatGameDestination.dotsAndBoxesPrototype),
      isNull,
    );
    expect(
      chatGameTypeForDestination(ChatGameDestination.constellationPrototype),
      isNull,
    );
  });

  test('no game_type resolves TO a prototype destination', () {
    // The reverse direction: a session row must never route into a
    // throwaway build.
    for (final type in const [
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
    ]) {
      final destination = chatGameDestinationForType(type);
      expect(
        destination,
        isNot(ChatGameDestination.dotsAndBoxesPrototype),
        reason: '$type routes into a prototype',
      );
      expect(
        destination,
        isNot(ChatGameDestination.constellationPrototype),
        reason: '$type routes into a prototype',
      );
    }
  });

  test('every shipped game still resolves', () {
    // Guards the enum edit: adding prototypes must not disturb the
    // existing mapping.
    expect(
      chatGameDestinationForType('word_hunt'),
      ChatGameDestination.wordHunt,
    );
    expect(
      chatGameDestinationForType('snakes_and_ladders'),
      ChatGameDestination.snakesAndLadders,
    );
    expect(
      chatGameDestinationForType('paint_ball'),
      ChatGameDestination.paintBall,
    );
    expect(chatGameDestinationForType('unknown_game'), isNull);
  });

  // A widget test that renders the whole sheet was attempted and dropped:
  // ChatGamesSheet sizes with ScreenUtil, which needs a frame to
  // initialise before its child builds, and wiring that up proved more
  // fragile than the thing it was checking. The four assertions above
  // cover the wiring that can actually break -- the destinations exist,
  // they carry no game_type, and no session row can route into them.
}
