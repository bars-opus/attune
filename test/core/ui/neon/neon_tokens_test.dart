import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('beat thresholds are ordered and inside the unit interval', () {
    // field_replay maps one 0->1 value onto six beats by comparing
    // against these. Out-of-order thresholds would make a beat
    // unreachable, and the bug would present as a missing animation
    // rather than as a crash.
    final beats = [
      NeonTokens.beatEmerge,
      NeonTokens.beatAim,
      NeonTokens.beatFire,
      NeonTokens.beatFlightEnd,
      NeonTokens.beatImpactEnd,
    ];

    for (final beat in beats) {
      expect(beat, greaterThan(0.0));
      expect(beat, lessThanOrEqualTo(1.0));
    }
    for (var i = 1; i < beats.length; i++) {
      expect(
        beats[i],
        greaterThan(beats[i - 1]),
        reason: 'beat $i must come after beat ${i - 1}',
      );
    }
  });

  test('the four original thresholds are preserved', () {
    // The existing replay choreography was tuned on a device and its
    // rationale is documented: emerging and aiming need room to read
    // before anything is fired. Keeping the numbers means the rebuild
    // is a repaint, not a retiming.
    expect(NeonTokens.beatEmerge, 0.12);
    expect(NeonTokens.beatAim, 0.34);
    expect(NeonTokens.beatFire, 0.52);
    expect(NeonTokens.beatFlightEnd, 0.86);
  });

  test('motion durations stay inside the 150-320ms band', () {
    // Master Spec §17.4. A duration outside the band reads as either a
    // glitch or a wait.
    for (final duration in [
      NeonTokens.impactFlashDuration,
      NeonTokens.bloomFadeDuration,
      NeonTokens.burstSettleDuration,
    ]) {
      expect(duration.inMilliseconds, greaterThanOrEqualTo(150));
      expect(duration.inMilliseconds, lessThanOrEqualTo(320));
    }
  });

  test('structure is dimmer than actors', () {
    // Spec §2.1: if everything glows, nothing does. Structure is
    // architecture; actors are the only bright things on the field.
    expect(NeonTokens.structureAlphaRest, lessThan(NeonTokens.actorAlpha));
    expect(NeonTokens.structureAlphaActive, lessThan(NeonTokens.actorAlpha));
    expect(
      NeonTokens.structureAlphaRest,
      lessThan(NeonTokens.structureAlphaActive),
    );
  });

  test('the ground emits nothing', () {
    // §2.1 tier 1: the ground receives light and emits none. Near-black
    // rather than pure black, so coloured glow does not vibrate on it.
    expect(NeonTokens.groundColor.a, 1.0);
    expect(NeonTokens.groundColor.r, lessThan(0.08));
    expect(NeonTokens.groundColor.g, lessThan(0.08));
    expect(NeonTokens.groundColor.b, lessThan(0.08));
  });
}
