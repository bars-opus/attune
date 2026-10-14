import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the cue a resolved round plays', () {
    test('a hit sounds like a hit', () {
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.hit,
          knockout: false,
        ),
        AppSound.gameHit,
      );
    });

    test('a miss sounds like a miss', () {
      // The two outcomes must be distinguishable with the screen away
      // from your face -- this is an asynchronous game and a player
      // often hears the result before they look at it.
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.miss,
          knockout: false,
        ),
        AppSound.gameMiss,
      );
    });

    test('an opening shot is a miss, not a hit', () {
      // An opener resolves nothing: the partner has not chosen yet. It
      // must not play the hit cue and promise a result that has not
      // happened.
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.opening,
          knockout: false,
        ),
        AppSound.gameMiss,
      );
    });

    test('a knockout outranks the hit that caused it', () {
      // The last life going is the loudest thing in the game, and a
      // knockout is always a hit, so without this the bigger moment
      // would be announced by the smaller cue.
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.hit,
          knockout: true,
        ),
        AppSound.gameKnockout,
      );
    });

    test('a knockout on a miss still reads as a knockout', () {
      // Reachable on a double knockout, where one side's shot missed
      // and the round still ended the game.
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.miss,
          knockout: true,
        ),
        AppSound.gameKnockout,
      );
    });

    test('every outcome maps to a cue that exists', () {
      // A positive control over the enum rather than a sample of it: a
      // new outcome added without a cue would otherwise fall through to
      // whatever the last branch happens to be.
      for (final outcome in PaintBallShotOutcome.values) {
        final cue = paintBallRoundCue(outcome: outcome, knockout: false);
        expect(
          const [AppSound.gameHit, AppSound.gameMiss, AppSound.gameKnockout],
          contains(cue),
          reason: '$outcome must map to one of the round cues',
        );
      }
    });
  });
}
