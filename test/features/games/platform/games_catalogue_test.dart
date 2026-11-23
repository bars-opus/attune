import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:attune/features/games/platform/game_registry.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/games_catalogue.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the five launch games, in order', () {
    final registry = GameRegistry(gameCatalogue);
    expect(registry.launch.map((g) => g.gameType), [
      'this_or_that',
      'truth_or_dare',
      '36_questions',
      'word_hunt',
      'snakes_and_ladders',
    ]);
  });

  test('every title is the name the chat card uses', () {
    expect(gameCatalogue, isNotEmpty);
    for (final game in gameCatalogue) {
      expect(
        game.title,
        gameTypeDisplayName(game.gameType),
        reason: game.gameType,
      );
    }
  });

  test('every launch game can be opened', () {
    final launch = GameRegistry(gameCatalogue).launch;
    expect(launch, hasLength(5));
    for (final game in launch) {
      expect(game.controller, isNotNull, reason: game.gameType);
    }
  });

  test('every game type the chat can route has a place in the catalogue', () {
    // The sheet's own list: a game added there and missed here would vanish
    // from the hub.
    final known = gameCatalogue.map((g) => g.gameType).toSet();
    expect(kInvitableGameTypes, isNotEmpty);
    for (final type in kInvitableGameTypes) {
      expect(known, contains(type));
    }
  });

  test('each launch game has its own colour, and no coming-soon game borrows '
      'one', () {
    final registry = GameRegistry(gameCatalogue);
    final launch = registry.launch.toList();
    final comingSoon = registry.comingSoon.toList();
    expect(launch, isNotEmpty);
    expect(comingSoon, isNotEmpty);

    final launchColours = launch.map((g) => g.theme.primary).toList();
    // Five games, five colours, each one of the tested launch colours.
    expect(launchColours.toSet(), hasLength(launch.length));
    expect(launchColours.toSet(), GameColors.all.toSet());

    for (final game in comingSoon) {
      expect(game.theme.primary, GameColors.comingSoon, reason: game.gameType);
    }
    expect(GameColors.all, isNot(contains(GameColors.comingSoon)));
  });
}
