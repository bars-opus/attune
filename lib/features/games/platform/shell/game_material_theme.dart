import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';

/// A dark Material theme for everything inside a game, whatever the app's
/// own theme is: text fields, dialogs, list rows, switches. Keeps the
/// ambient text theme's fonts.
ThemeData gameMaterialTheme(BuildContext context, GameTheme theme) {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: theme.primary,
      brightness: Brightness.dark,
    ).copyWith(surface: GameTheme.raised),
    scaffoldBackgroundColor: GameTheme.ground,
    textTheme: Theme.of(context).textTheme.apply(
      bodyColor: GameTheme.onGround,
      displayColor: GameTheme.onGround,
    ),
  );
}
