import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:flutter_test/flutter_test.dart';

SessionGameFlowState stateFor({
  required String gameType,
  bool isSubject = false,
  int roundIndex = 0,
  int totalRounds = 8,
  SessionGameStage stage = SessionGameStage.question,
}) {
  return SessionGameFlowState(
    stage: stage,
    roundIndex: roundIndex,
    totalRounds: totalRounds,
    gameType: gameType,
    isSubject: isSubject,
  );
}

void main() {
  group('stageAfterSubmit', () {
    test('submitting always waits for the partner', () {
      for (final type in ['mirror', 'sliding_scale', 'scenario']) {
        expect(
          stateFor(gameType: type).stageAfterSubmit(),
          SessionGameStage.waiting,
          reason: type,
        );
      }
    });
  });

  group('stageAfterReveal', () {
    test('Mirror sends the SUBJECT to judge', () {
      // The subject is the only authority on whether their partner read
      // them accurately (§8.4), so only they get the judge step.
      expect(
        stateFor(gameType: 'mirror', isSubject: true).stageAfterReveal(),
        SessionGameStage.judge,
      );
    });

    test('Mirror does NOT send the guesser to judge', () {
      // The guesser must never judge their own guess — that would let a
      // user score themselves.
      expect(
        stateFor(gameType: 'mirror', isSubject: false).stageAfterReveal(),
        SessionGameStage.question,
      );
    });

    test('the other two games skip judging entirely', () {
      for (final type in ['sliding_scale', 'scenario']) {
        expect(
          stateFor(gameType: type, isSubject: true).stageAfterReveal(),
          SessionGameStage.question,
          reason: '$type has no subject and no judgement',
        );
      }
    });

    test('the last round ends instead of advancing', () {
      expect(
        stateFor(
          gameType: 'scenario',
          roundIndex: 7,
          totalRounds: 8,
        ).stageAfterReveal(),
        SessionGameStage.end,
      );
    });

    test('Mirror still judges on the last round before ending', () {
      // Dropping the final judgement would silently lose one mark from
      // the score.
      expect(
        stateFor(
          gameType: 'mirror',
          isSubject: true,
          roundIndex: 7,
          totalRounds: 8,
        ).stageAfterReveal(),
        SessionGameStage.judge,
      );
    });
  });

  group('isLastRound', () {
    test('true only on the final index', () {
      expect(stateFor(gameType: 'mirror', roundIndex: 6).isLastRound, isFalse);
      expect(stateFor(gameType: 'mirror', roundIndex: 7).isLastRound, isTrue);
    });

    test('handles a short session, not just the nominal 8', () {
      // Sliding Scale has only 6 seeded questions, so totalRounds is 6.
      expect(
        stateFor(gameType: 'sliding_scale', roundIndex: 5, totalRounds: 6)
            .isLastRound,
        isTrue,
      );
    });
  });
}
