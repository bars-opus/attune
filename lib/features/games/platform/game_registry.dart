import 'package:attune/features/games/platform/game_definition.dart';

/// The games Attune knows about.
class GameRegistry {
  /// Throws if two definitions share a game type: a second one would
  /// silently shadow the first and its game would become unreachable.
  GameRegistry(List<GameDefinition> definitions)
    : all = List.unmodifiable(definitions),
      _byType = _index(definitions);

  /// Every game, in the order it should be shown.
  final List<GameDefinition> all;

  final Map<String, GameDefinition> _byType;

  static Map<String, GameDefinition> _index(List<GameDefinition> definitions) {
    final byType = <String, GameDefinition>{};
    for (final definition in definitions) {
      if (byType.containsKey(definition.gameType)) {
        throw ArgumentError(
          'Duplicate game type "${definition.gameType}" in the registry',
        );
      }
      byType[definition.gameType] = definition;
    }
    return byType;
  }

  /// The game for a `game_sessions.game_type`, or null for one this build
  /// has not been taught -- a type added to the database first must not
  /// crash the hub.
  GameDefinition? byType(String? gameType) => _byType[gameType];

  Iterable<GameDefinition> get launch =>
      all.where((game) => game.availability == GameAvailability.launch);

  Iterable<GameDefinition> get comingSoon =>
      all.where((game) => game.availability == GameAvailability.comingSoon);
}
