import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/widgets.dart';

/// Every duration and curve the games move with.
///
/// Named here so no screen carries a raw number: ten games each choosing
/// their own "about 200ms" is how a set of games stops feeling like one set.
abstract final class GameMotion {
  /// A tile going down under a finger. Short enough to feel like contact.
  static const Duration press = Duration(milliseconds: 90);

  /// Something arriving at rest: a tile landing, a tab changing.
  static const Duration settle = Duration(milliseconds: 240);

  /// A screen's pieces coming in.
  static const Duration enter = Duration(milliseconds: 320);

  /// The spark burst on a placement or a match.
  static const Duration burst = Duration(milliseconds: 420);

  /// The gap between one piece starting and the next, in a staggered entry.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Overshoots a little, then comes back: the spring in a landing tile.
  static const Curve settleCurve = Curves.easeOutBack;

  static const Curve enterCurve = Curves.easeOutCubic;

  /// [duration], or nothing at all when the OS asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduceMotionOf(context) ? Duration.zero : duration;
}
