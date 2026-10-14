import 'package:flutter/widgets.dart';

import 'neon_quality.dart';

/// The tier Attune ships at, and the one place to change it.
///
/// ATTUNE_THESIS §6.10 makes performance budgets on representative
/// Ghanaian hardware a LAUNCH GATE, and [NeonQuality] exists to honour
/// it. A whole-branch review found the mechanism complete, tested and
/// obeyed by every consumer -- and declared nowhere, so every device
/// silently took `neonQualityOf`'s fallback. A guard nothing declares is
/// a facility, not a guard.
///
/// The first attempt at fixing that declared it in the games hub's
/// theme wrapper, which turned out to cover only the picker sheet: the
/// games themselves are separate routes that never pass through it. So
/// the scope is installed by the widgets that CONSUME it instead, where
/// no routing decision can bypass it.
///
/// Hardcoded deliberately. Choosing a tier from the device is a
/// measurement task the spec defers until there is a real device to
/// measure on (§5.1); what matters now is that the seam is real, so that
/// change is one constant here rather than a hunt for where it belongs.
class AttuneNeonQuality {
  const AttuneNeonQuality._();

  /// Change this, and later make it a device probe.
  static const NeonQuality forDevice = NeonQuality.glow;

  /// Declares [forDevice] for a subtree, unless an enclosing scope
  /// already said otherwise.
  ///
  /// Idempotent on purpose: a game nested inside a surface that already
  /// declared a tier must not have it silently overridden back to the
  /// default, or a future device downgrade would stop at the first
  /// widget that wrapped itself.
  static Widget wrap(BuildContext context, {required Widget child}) {
    final existing = context
        .dependOnInheritedWidgetOfExactType<NeonQualityScope>();
    if (existing != null) return child;

    return NeonQualityScope(quality: forDevice, child: child);
  }
}
