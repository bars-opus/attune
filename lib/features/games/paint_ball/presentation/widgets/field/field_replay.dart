import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/foundation.dart';

/// Where a replay has got to, as six beats rather than one number.
///
/// Spec §3.2: timing lives in ONE place that the field's parts read. It
/// was previously six threshold comparisons inline in the field's build
/// method, which meant the only way to test "what does the frame a skip
/// lands on look like" was to pump a whole field and inspect it.
///
/// Deliberately a value object with no rendering logic. §3.2 names the
/// hazard it was written to avoid: a replay class that accumulates
/// per-beat drawing parameters becomes the god-object the file split
/// existed to prevent. If something here starts deciding how a thing
/// looks rather than when it happens, it is in the wrong file.
@immutable
class ReplayBeats {
  const ReplayBeats._({
    required this.isReplaying,
    required this.emerged,
    required this.aimed,
    required this.firing,
    required this.impacting,
    required this.settled,
    this.flightProgress,
    this.impactProgress,
  });

  /// Between rounds: everything visible, nothing in the air.
  ///
  /// `emerged` and `aimed` are TRUE here, which looks odd until you
  /// consider what false would mean -- a player hidden from themselves
  /// because no replay happens to be running.
  static const ReplayBeats idle = ReplayBeats._(
    isReplaying: false,
    emerged: true,
    aimed: true,
    firing: false,
    impacting: false,
    settled: false,
  );

  /// Maps the battle screen's single 0→1 controller value onto the
  /// beats. The only place that mapping exists.
  factory ReplayBeats.from(double? progress) {
    if (progress == null) return idle;

    // A NaN reaches Positioned as a NaN offset and crashes the screen
    // rather than drawing wrongly, so it resolves to the resolved frame
    // -- the same place a skip lands, which is the safest wrong answer.
    if (progress.isNaN) return ReplayBeats.from(1);

    final t = progress.clamp(0.0, 1.0);

    final firing = t > NeonTokens.beatFire;

    return ReplayBeats._(
      isReplaying: true,
      emerged: t > NeonTokens.beatEmerge,
      aimed: t > NeonTokens.beatAim,
      firing: firing,
      impacting: t > NeonTokens.beatFlightEnd,
      settled: t >= NeonTokens.beatImpactEnd,
      // Remapped so the paintball still crosses the whole field in the
      // slice of the replay given to flight.
      flightProgress:
          firing
              ? ((t - NeonTokens.beatFire) /
                      (NeonTokens.beatFlightEnd - NeonTokens.beatFire))
                  .clamp(0.0, 1.0)
              : null,
      impactProgress:
          t > NeonTokens.beatFlightEnd
              ? ((t - NeonTokens.beatFlightEnd) /
                      (1.0 - NeonTokens.beatFlightEnd))
                  .clamp(0.0, 1.0)
              : null,
    );
  }

  /// False between rounds.
  final bool isReplaying;

  /// Both players have stepped out of cover.
  final bool emerged;

  /// Both aims have landed on their chosen bay.
  final bool aimed;

  /// Both shots have left. A round is a simultaneous duel, so this is
  /// never true for one side alone.
  final bool firing;

  /// The shots have arrived and the paint is blooming.
  final bool impacting;

  /// The replay has run its course.
  final bool settled;

  /// 0→1 across the flight slice, or null before anything is fired.
  final double? flightProgress;

  /// 0→1 across impact and settle, or null before the shots land.
  final double? impactProgress;
}
