import 'package:flutter/widgets.dart';

/// Stable handles onto the field's parts, for tests.
///
/// Spec §3.6.1. The field's 25 tests used to find painters by
/// `runtimeType.toString().contains('Triangle')` and read their state
/// through `(painter as dynamic).splats`. Both work and both are traps:
/// renaming a private painter breaks a dozen assertions with no
/// behaviour change, and worse, a name filter that matches nothing
/// yields an empty collection, so `expect(count, 0)` and
/// `for (x in matches)` keep passing while asserting nothing at all.
/// Two of the field's tests were in exactly that state.
///
/// So the parts carry keys and the painters expose public fields. A test
/// that asks for a named thing either finds it or fails.
///
/// Keyed per position AND per side, because the old filters could not
/// tell the two rows apart -- they counted totals across the whole
/// field and inferred whose was whose.
class PaintBallFieldKeys {
  const PaintBallFieldKeys._();

  /// A player's figure in its cover.
  static Key figure(int position, {required bool isOpponent}) =>
      ValueKey('paintball.figure.${isOpponent ? 'theirs' : 'mine'}.$position');

  /// One cover bay.
  static Key bay(int position, {required bool isOpponent}) =>
      ValueKey('paintball.bay.${isOpponent ? 'theirs' : 'mine'}.$position');

  /// A paintball in flight. Both sides' shots are airborne together
  /// during a replay (§2.6), so each needs its own handle.
  static Key projectile({required bool isMine}) =>
      ValueKey('paintball.projectile.${isMine ? 'mine' : 'theirs'}');

  static const Key ground = ValueKey('paintball.ground');
  static const Key paint = ValueKey('paintball.paint');
  static const Key divider = ValueKey('paintball.divider');
}
