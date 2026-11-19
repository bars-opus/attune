import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A game's colour fading down to the ground, behind everything.
///
/// Sets white as the default ink, because every game screen is dark-based
/// whatever the app theme is doing.
///
/// The Material sits here, above the ink colour, on purpose. A Material
/// resets the default text style to the app theme's, so one placed lower
/// down turns every unstyled word back to the theme's dark ink on a dark
/// ground. Here it gives InkWells something to splash on, over the
/// gradient, and the white default is applied after it.
class GameBackdrop extends StatelessWidget {
  const GameBackdrop({super.key, required this.theme, required this.child});

  final GameTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: theme.backdrop),
        child: Material(
          type: MaterialType.transparency,
          child: IconTheme.merge(
            data: const IconThemeData(color: GameTheme.onGround),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: GameTheme.onGround),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
