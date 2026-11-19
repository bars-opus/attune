import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';

void main() {
  test('a game is found by its database type', () {
    final registry = GameRegistry([
      demoGame(gameType: 'this_or_that'),
      demoGame(gameType: 'word_hunt'),
    ]);

    expect(registry.byType('word_hunt')?.gameType, 'word_hunt');
  });

  test('a type this build does not know is null, not a crash', () {
    // A game type can reach the database before the app is updated.
    final registry = GameRegistry([demoGame()]);

    expect(registry.byType('not_a_game'), isNull);
    expect(registry.byType(null), isNull);
  });

  test('two games cannot share a type', () {
    // The second would shadow the first and make it unreachable.
    expect(
      () => GameRegistry([
        demoGame(gameType: 'same'),
        demoGame(gameType: 'same'),
      ]),
      throwsArgumentError,
    );
  });

  test('every game is either playable or coming soon, never both', () {
    final registry = GameRegistry([
      demoGame(gameType: 'a'),
      demoGame(gameType: 'b', availability: GameAvailability.comingSoon),
      demoGame(gameType: 'c'),
    ]);

    expect(registry.launch.map((g) => g.gameType), ['a', 'c']);
    expect(registry.comingSoon.map((g) => g.gameType), ['b']);
    expect(
      registry.launch.length + registry.comingSoon.length,
      registry.all.length,
    );
  });

  test('games keep the order they were listed in', () {
    final registry = GameRegistry([
      demoGame(gameType: 'z'),
      demoGame(gameType: 'a'),
      demoGame(gameType: 'm'),
    ]);

    expect(registry.all.map((g) => g.gameType), ['z', 'a', 'm']);
  });
}
