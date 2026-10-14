import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_replay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a round that is not replaying', () {
    test('shows everything at rest, hiding nothing', () {
      // Between rounds the board is static and fully visible: a figure
      // that stayed hidden because no replay was running would make the
      // player invisible to themselves.
      const beats = ReplayBeats.idle;

      expect(beats.isReplaying, isFalse);
      expect(beats.emerged, isTrue);
      expect(beats.aimed, isTrue);
      expect(beats.firing, isFalse, reason: 'nothing is in the air');
      expect(beats.flightProgress, isNull);
    });

    test('a null progress is the idle state', () {
      expect(ReplayBeats.from(null).isReplaying, isFalse);
      expect(ReplayBeats.from(null).emerged, isTrue);
    });
  });

  group('the beats in order', () {
    test('nothing has happened at the very start', () {
      final beats = ReplayBeats.from(0);

      expect(beats.isReplaying, isTrue);
      expect(beats.emerged, isFalse, reason: 'still behind cover');
      expect(beats.aimed, isFalse);
      expect(beats.firing, isFalse);
      expect(beats.flightProgress, isNull);
    });

    test('each beat turns on after its own threshold and stays on', () {
      // Monotonic by construction: a beat that switched back off would
      // make the replay flicker rather than build.
      var sawEmerged = false;
      var sawAimed = false;
      var sawFiring = false;

      for (var t = 0.0; t <= 1.0; t += 0.01) {
        final beats = ReplayBeats.from(t);

        if (beats.emerged) sawEmerged = true;
        if (beats.aimed) sawAimed = true;
        if (beats.firing) sawFiring = true;

        expect(
          beats.emerged,
          sawEmerged ? isTrue : isFalse,
          reason: 'emerged must not switch back off at $t',
        );
        expect(
          beats.aimed,
          sawAimed ? isTrue : isFalse,
          reason: 'aimed must not switch back off at $t',
        );
        expect(
          beats.firing,
          sawFiring ? isTrue : isFalse,
          reason: 'firing must not switch back off at $t',
        );
      }

      // A positive control: without these the loop above would pass on a
      // ReplayBeats that never turned anything on at all.
      expect(sawEmerged, isTrue);
      expect(sawAimed, isTrue);
      expect(sawFiring, isTrue);
    });

    test('aiming never precedes emerging, nor firing the aim', () {
      // The replay's whole point is seeing the two decisions MEET. A
      // shot that left before the aim landed would skip the part worth
      // watching, which is why the thresholds are spread the way they
      // are rather than evenly.
      for (var t = 0.0; t <= 1.0; t += 0.01) {
        final beats = ReplayBeats.from(t);

        if (beats.aimed) {
          expect(beats.emerged, isTrue, reason: 'aimed before emerging at $t');
        }
        if (beats.firing) {
          expect(beats.aimed, isTrue, reason: 'fired before aiming at $t');
        }
      }
    });

    test('flight runs a full 0 to 1 inside its own slice', () {
      // The paintball has to cross the WHOLE field in the slice the
      // replay gives it, so the remap has to reach both ends.
      expect(ReplayBeats.from(NeonTokens.beatFire).flightProgress, isNull);

      final justFired = ReplayBeats.from(NeonTokens.beatFire + 0.001);
      expect(justFired.flightProgress, closeTo(0, 0.01));

      final landing = ReplayBeats.from(NeonTokens.beatFlightEnd);
      expect(landing.flightProgress, closeTo(1, 0.01));
    });
  });

  group('the frame a skip lands on', () {
    test('every beat is complete at exactly 1.0', () {
      // REVIEW FOCUS #1. Tapping to skip sets the controller to exactly
      // 1 (`_skipReplay` in paint_ball_battle_screen.dart), so this is
      // not an edge case -- it is the frame a player sees whenever they
      // are impatient, which is often.
      final beats = ReplayBeats.from(1);

      expect(beats.isReplaying, isTrue);
      expect(beats.emerged, isTrue);
      expect(beats.aimed, isTrue);
      expect(beats.firing, isTrue);
      expect(
        beats.flightProgress,
        closeTo(1, 0.001),
        reason: 'the shot has landed, not frozen mid-air',
      );
      expect(beats.settled, isTrue);
    });

    test('the resolved frame is reachable and stable', () {
      // Pumped twice because a skip can rebuild at 1.0 repeatedly; the
      // frame must be identical each time rather than depending on how
      // it was arrived at.
      expect(ReplayBeats.from(1).emerged, ReplayBeats.from(1).emerged);
      expect(
        ReplayBeats.from(1).flightProgress,
        ReplayBeats.from(1).flightProgress,
      );
    });
  });

  group('a controller driven out of bounds', () {
    test('progress above one clamps rather than overshooting', () {
      // REVIEW FOCUS #2. An easeOutBack curve overshoots past 1, and a
      // flightProgress above 1 would push the paintball off the far edge
      // of the field.
      for (final over in [1.0001, 1.4, 2.0, 100.0]) {
        final beats = ReplayBeats.from(over);

        expect(beats.emerged, isTrue, reason: 'at $over');
        expect(
          beats.flightProgress,
          lessThanOrEqualTo(1.0),
          reason: 'at $over the shot must not fly past the field',
        );
        expect(beats.flightProgress, isNotNull);
      }
    });

    test('negative progress is the start, not a shot flying backwards', () {
      // Reachable as -0.0 from a controller reset, and as a genuine
      // negative from a reversed animation.
      for (final under in [-0.0, -0.001, -1.0]) {
        final beats = ReplayBeats.from(under);

        expect(beats.emerged, isFalse, reason: 'at $under');
        expect(beats.firing, isFalse, reason: 'at $under');
        expect(
          beats.flightProgress,
          isNull,
          reason: 'at $under nothing has been fired to have progress',
        );
      }
    });

    test('a NaN progress does not propagate into the field', () {
      // A NaN offset thrown into Positioned crashes the screen rather
      // than drawing wrongly, so it is worth one branch.
      final beats = ReplayBeats.from(double.nan);

      expect(beats.flightProgress, anyOf(isNull, predicate<double>((v) => !v.isNaN)));
      expect(beats.isReplaying, isTrue);
    });
  });
}
