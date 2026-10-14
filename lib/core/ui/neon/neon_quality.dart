import 'package:flutter/widgets.dart';

/// How much light this device can afford.
///
/// ATTUNE_THESIS §6.10 makes performance budgets on representative
/// Ghanaian hardware a LAUNCH GATE, and payload thrift a permanent
/// discipline rather than an optimization pass. A neon surface is made
/// of blur passes, which is exactly the kind of cost that is invisible
/// on a developer's phone and ruinous on a low-end one.
///
/// So the tier exists from the first primitive rather than being
/// retrofitted: every neon widget reads it, and degrading is a
/// multiplication rather than a branch nobody wrote.
enum NeonQuality {
  /// One crisp stroke, no halo, few droplets. Still playable, still
  /// legible -- the game must not become unusable on the hardware this
  /// tier is for.
  plain,

  /// The everyday look: one halo pass. The default.
  glow,

  /// Two halo passes and ground-cast light.
  rich;

  /// Blurred passes drawn behind a core stroke.
  int get haloPasses => switch (this) {
    NeonQuality.plain => 0,
    NeonQuality.glow => 1,
    NeonQuality.rich => 2,
  };

  /// Droplets a single paint burst may emit.
  int get maxDroplets => switch (this) {
    NeonQuality.plain => 3,
    NeonQuality.glow => 10,
    NeonQuality.rich => 24,
  };

  /// Whether a travelling actor lights the ground under it. The most
  /// expensive effect in the language and the first to go.
  bool get castsGroundLight => this != NeonQuality.plain;
}

/// Declares the tier for a subtree.
class NeonQualityScope extends InheritedWidget {
  const NeonQualityScope({
    super.key,
    required this.quality,
    required super.child,
  });

  final NeonQuality quality;

  @override
  bool updateShouldNotify(NeonQualityScope oldWidget) =>
      quality != oldWidget.quality;
}

/// The tier in effect, or [NeonQuality.glow] where nothing declared one.
///
/// The middle is the only safe default: rich would punish precisely the
/// devices the tiering protects, and plain would make any screen that
/// forgot the scope look broken.
NeonQuality neonQualityOf(BuildContext context) =>
    context
        .dependOnInheritedWidgetOfExactType<NeonQualityScope>()
        ?.quality ??
    NeonQuality.glow;
