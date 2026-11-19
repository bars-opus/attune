import 'package:flutter/material.dart';

/// One game's colour, and everything drawn from it.
///
/// The games area is full colour: each game owns one colour, which fills the
/// top of its screens and fades to a near-black ground by about the vertical
/// midpoint. Titles sit on the colour; body text and lists sit on the ground,
/// where contrast is easy.
///
/// The surface is the same whatever the app theme is doing, so nothing here
/// reads the ambient brightness.
@immutable
class GameTheme {
  const GameTheme({required this.primary});

  /// The game's colour.
  final Color primary;

  /// What every game screen fades down to.
  static const Color ground = Color(0xFF0B0B0B);

  /// Cards and rows that sit on the ground.
  static const Color raised = Color(0xFF1E1E20);

  /// A hairline between rows on the ground.
  static const Color hairline = Color(0xFF2A2A2E);

  /// A tile's face, and the ink on it.
  static const Color tile = Color(0xFFFFFFFF);
  static const Color tileInk = Color(0xFF111111);

  /// A tile's hard shadow. Flat, never blurred.
  static const Color tileShadow = Color(0xFF050505);

  static const Color onGround = Color(0xFFFFFFFF);
  static const Color mutedOnGround = Color(0xFFB9B9C2);

  /// The colour on its way down to the ground.
  Color get deep => Color.lerp(primary, ground, 0.6)!;

  /// Colour at the top, ground by a little past halfway.
  LinearGradient get backdrop => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primary, deep, ground],
    stops: const [0.0, 0.34, 0.56],
  );
}

/// The launch games' colours.
///
/// Each keeps white text at 3:1 or better against it, which is the bar for
/// the large bold titles that sit on the colour. A test holds that line, so a
/// retune cannot quietly make a header unreadable.
abstract final class GameColors {
  static const Color thisOrThat = Color(0xFFE0701A);
  static const Color truthOrDare = Color(0xFFE5484D);
  static const Color thirtySixQuestions = Color(0xFFA56FD6);
  static const Color wordHunt = Color(0xFF1FA463);
  static const Color snakesAndLadders = Color(0xFF4C7CF0);

  static const List<Color> all = [
    thisOrThat,
    truthOrDare,
    thirtySixQuestions,
    wordHunt,
    snakesAndLadders,
  ];
}
