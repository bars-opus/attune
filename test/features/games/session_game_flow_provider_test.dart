import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:attune/features/games/session_games/presentation/providers/session_game_flow_provider.dart';
import 'package:flutter_test/flutter_test.dart';

SessionGameRound roundAt(int number, {required bool bothAnswered}) {
  return SessionGameRound.fromRow({
    'id': 'r$number',
    'round_number': number,
    'question_id': 'q$number',
    'both_answered': bothAnswered,
  });
}

void main() {
  group('isAlreadySubmitted', () {
    test('recognises the server\'s resubmission message', () {
      // "Answer already submitted" is NOT a failure: it is the normal
      // state of a user returning to a round they answered before
      // backgrounding the app or losing signal. Surfacing it as an error
      // would show a scary message on a round that is perfectly fine.
      expect(
        isAlreadySubmitted(Exception('Answer already submitted')),
        isTrue,
      );
    });

    test('does not swallow other failures', () {
      // A genuine failure must still surface — treating everything as
      // "already submitted" would hide real breakage.
      expect(isAlreadySubmitted(Exception('Round not found')), isFalse);
      expect(
        isAlreadySubmitted(Exception('Rating must be an integer from 1 to 10')),
        isFalse,
      );
      expect(isAlreadySubmitted(Exception('network unreachable')), isFalse);
    });
  });

  group('isAlreadyJudged', () {
    test('recognises the server\'s judge-once guard message', () {
      expect(
        isAlreadyJudged(Exception('Round already judged')),
        isTrue,
      );
    });

    test('does not match other server messages', () {
      // The two "already" messages must not be conflated, or a genuine
      // permission error would be silently swallowed.
      expect(isAlreadyJudged(Exception('Answer already submitted')), isFalse);
      expect(isAlreadyJudged(Exception('Round not found')), isFalse);
      expect(
        isAlreadyJudged(Exception('Only this round\'s subject may judge it')),
        isFalse,
      );
    });
  });

  group('initialStageAndIndexFor (C1 resume-not-restart)', () {
    // createSession now returns an existing in-progress session when the
    // partner already started one (C1). A joining partner must resume
    // at the first round they have not yet answered — landing them back
    // on round 0 would force them to re-answer completed rounds, or
    // worse, overwrite an in-flight one.
    test('a brand-new session with no rounds answered starts at round 0',
        () {
      final rounds = [
        roundAt(1, bothAnswered: false),
        roundAt(2, bothAnswered: false),
      ];
      final initial = initialStageAndIndexFor(rounds);
      expect(initial.stage, SessionGameStage.question);
      expect(initial.roundIndex, 0);
    });

    test('a joining partner resumes at the first unanswered round', () {
      final rounds = [
        roundAt(1, bothAnswered: true),
        roundAt(2, bothAnswered: true),
        roundAt(3, bothAnswered: false),
        roundAt(4, bothAnswered: false),
      ];
      final initial = initialStageAndIndexFor(rounds);
      expect(initial.stage, SessionGameStage.question);
      expect(initial.roundIndex, 2);
    });

    test('every round answered goes straight to end, not round 0', () {
      final rounds = [
        roundAt(1, bothAnswered: true),
        roundAt(2, bothAnswered: true),
      ];
      final initial = initialStageAndIndexFor(rounds);
      expect(initial.stage, SessionGameStage.end);
    });

    test('a single unanswered round in the middle is found, not just '
        'the last', () {
      final rounds = [
        roundAt(1, bothAnswered: true),
        roundAt(2, bothAnswered: false),
        roundAt(3, bothAnswered: true),
      ];
      final initial = initialStageAndIndexFor(rounds);
      expect(initial.stage, SessionGameStage.question);
      expect(initial.roundIndex, 1);
    });
  });

  group('subjectOf', () {
    test('the viewer is the subject when the round names them', () {
      expect(subjectOf(subjectId: 'me', userId: 'me'), isTrue);
    });

    test('the viewer is not the subject when the round names the partner', () {
      expect(subjectOf(subjectId: 'them', userId: 'me'), isFalse);
    });

    test('a round with no subject makes nobody the subject', () {
      // Sliding Scale and Scenario have no subject at all; treating a
      // null as "you" would give both partners a judge step that should
      // not exist.
      expect(subjectOf(subjectId: null, userId: 'me'), isFalse);
    });
  });
}
