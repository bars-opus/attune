import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Shared spring for the "settle" feel — a gentle overshoot that damps quickly.
/// One spring, reused everywhere, so the whole app moves with one personality.
class AppSpring {
  const AppSpring._();
  static const SpringDescription settle = SpringDescription(
    mass: 1,
    stiffness: 480,
    damping: 26,
  );
}

/// Tween fallbacks for widgets that use an implicit/explicit tween rather than a
/// physics simulation. Kept in the 150–320ms band (Spec §2 rule 4).
const Duration kSettleDuration = Duration(milliseconds: 280);
const Curve kSettleCurve = Curves.easeOutBack;
