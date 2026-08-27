import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a failure is the server's resubmission guard rather than a
/// real error.
///
/// The RPC raises for validation, membership and resubmission alike, and
/// they all arrive as one undifferentiated exception. "Answer already
/// submitted" is not a failure at all — it is what a user hits when they
/// return to a round they already answered after backgrounding the app,
/// navigating back, or retrying on a flaky connection. Treated as an
/// error it shows a scary message on a round that is perfectly fine.
bool isAlreadySubmitted(Object error) =>
    error.toString().contains('Answer already submitted');

/// Whether a failure is the server's judge-once guard rather than a real
/// error.
///
/// Like [isAlreadySubmitted], this is not a failure: it is what a user
/// hits retrying `judge()` after the judgement committed but a later
/// step (advancing, or `completeSession` on the last round) failed. The
/// judgement is irreversible server-side, so a retry must be able to
/// move forward on work that already succeeded rather than getting stuck
/// re-erroring on it.
bool isAlreadyJudged(Object error) =>
    error.toString().contains('Round already judged');

/// Whether the viewer is this round's subject.
///
/// A null subjectId means the game has no subject (Sliding Scale,
/// Scenario), so nobody is — returning true there would give both
/// partners a judge step that should not exist.
bool subjectOf({required String? subjectId, required String userId}) =>
    subjectId != null && subjectId == userId;

/// Where a joining caller should resume: the first round that is NOT
/// bothAnswered, or the end stage if every round already is.
///
/// Pulled out as a pure function (rather than inlined in start()) so the
/// "resume, don't restart" behaviour is unit-testable without a
/// Supabase client. createSession (C1) now returns an existing session
/// when the partner already started one, so start() can no longer
/// assume round 0 is where the caller belongs — a joining partner
/// landing on round 0 of a session already underway would be forced to
/// re-answer completed rounds, or overwrite an in-flight one.
({SessionGameStage stage, int roundIndex}) initialStageAndIndexFor(
  List<SessionGameRound> rounds,
) {
  final firstUnanswered = rounds.indexWhere((r) => !r.bothAnswered);
  if (firstUnanswered == -1) {
    // Every round answered: the session is finished. roundIndex is 0
    // rather than the last index because nothing reads it once stage is
    // end — currentQuestion still resolves against a valid index into a
    // non-empty _questions list, but the value itself is never shown.
    return (stage: SessionGameStage.end, roundIndex: 0);
  }
  return (stage: SessionGameStage.question, roundIndex: firstUnanswered);
}

final sessionGameRepositoryProvider = Provider<SessionGameRepository>(
  (ref) => SessionGameRepository(),
);

final sessionGameFlowProvider =
    AsyncNotifierProvider<SessionGameFlowNotifier, SessionGameFlowState>(
  SessionGameFlowNotifier.new,
);

/// Drives one session: question -> waiting -> reveal -> [judge] -> end.
///
/// Owns the session id, its rounds, and the fetched questions, and
/// supplies the SessionGameQuestion each screen renders. Nothing did
/// that before, which is why the routes read a null `extra` and every
/// game rendered "Question unavailable."
class SessionGameFlowNotifier extends AsyncNotifier<SessionGameFlowState> {
  late String _sessionId;
  late String _gameType;
  late String _userId;
  late String _relationshipId;
  List<SessionGameRound> _rounds = const [];
  List<SessionGameQuestion> _questions = const [];

  SessionGameRepository get _repository =>
      ref.read(sessionGameRepositoryProvider);

  @override
  Future<SessionGameFlowState> build() async {
    // No session until start() is called. The routes render their own
    // empty state while this is the case.
    return const SessionGameFlowState(
      stage: SessionGameStage.question,
      roundIndex: 0,
      totalRounds: 0,
      gameType: '',
      isSubject: false,
    );
  }

  /// The question for the current round, or null before start().
  SessionGameQuestion? get currentQuestion {
    final current = state.value;
    if (current == null || _questions.isEmpty) return null;
    if (current.roundIndex >= _questions.length) return null;
    return _questions[current.roundIndex];
  }

  String? get currentRoundId {
    final current = state.value;
    if (current == null || _rounds.isEmpty) return null;
    if (current.roundIndex >= _rounds.length) return null;
    return _rounds[current.roundIndex].id;
  }

  /// The relationship this session belongs to, or null before start().
  ///
  /// Lets the reveal stage resolve which answer slot ("user_a" vs
  /// "user_b") is the viewer's own, without the client ever learning
  /// the partner's id.
  String? get relationshipId {
    if (state.value == null) return null;
    return _relationshipId;
  }

  /// This session's id, or null before start().
  ///
  /// Lets the end stage fetch the caller's own Mirror score without the
  /// notifier having to carry score-fetching logic itself.
  String? get sessionId {
    if (state.value == null) return null;
    return _sessionId;
  }

  /// Starts a new session, or joins one already in progress, and loads
  /// the first round the caller still needs to play.
  ///
  /// [partnerId] must be the caller's actual partner from the
  /// relationship — it is written into `active_partner_id` for Mirror
  /// rounds, and neither RLS nor the repository validates that it is
  /// really a member of the relationship. This controller is the only
  /// production caller of `createSession`, so it is the one place that
  /// enforcement can happen; an untrusted or attacker-supplied value here
  /// would silently strand the round and skew scoring.
  ///
  /// createSession now returns an existing session when the partner
  /// already started one, so this cannot assume round 0 is where the
  /// caller belongs: a joining partner who lands on round 0 of a session
  /// already underway would be forced to re-answer already-completed
  /// rounds, or worse, overwrite an in-flight one. The initial roundIndex
  /// is therefore the first round that is NOT bothAnswered. If every
  /// round is already answered the session is finished, and the caller
  /// goes straight to the end stage rather than to a question screen
  /// with nothing left to ask.
  Future<void> start({
    required String gameType,
    required String relationshipId,
    required String userId,
    required String partnerId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _gameType = gameType;
      _userId = userId;
      _relationshipId = relationshipId;

      _sessionId = await _repository.createSession(
        relationshipId: relationshipId,
        initiatorId: userId,
        gameType: gameType,
        partnerId: partnerId,
      );

      _rounds = await _repository.fetchRounds(_sessionId);
      _questions = await _repository.fetchQuestions(
        gameType: gameType,
        limit: _rounds.length,
      );

      final initial = initialStageAndIndexFor(_rounds);

      return SessionGameFlowState(
        stage: initial.stage,
        roundIndex: initial.roundIndex,
        // From the rounds actually created, never assumed — Sliding
        // Scale has only 6 seeded questions.
        totalRounds: _rounds.length,
        gameType: gameType,
        isSubject: subjectOf(
          subjectId:
              _rounds.isEmpty ? null : _rounds[initial.roundIndex].subjectId,
          userId: userId,
        ),
      );
    });
  }

  Future<void> submit(String answer) async {
    final current = state.value;
    final roundId = currentRoundId;
    if (current == null || roundId == null) return;

    try {
      await _repository.submitAnswer(roundId: roundId, answer: answer);
    } catch (error) {
      // A returning user has already answered this round; that is the
      // normal path, not a failure. Anything else is real.
      if (!isAlreadySubmitted(error)) rethrow;
    }

    state = AsyncData(current.copyWith(stage: current.stageAfterSubmit()));
  }

  /// Called by the waiting screen once the reveal gate opens.
  void onRevealed() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(stage: SessionGameStage.reveal));
  }

  Future<void> judge(bool wasCorrect) async {
    final current = state.value;
    final roundId = currentRoundId;
    if (current == null || roundId == null) return;

    try {
      await _repository.judgeRound(roundId: roundId, wasCorrect: wasCorrect);
    } catch (error) {
      // The judgement is irreversible server-side, so a retry after a
      // partial failure (judgeRound committed but advance()'s
      // completeSession then failed) must be able to move forward
      // rather than re-erroring on work that already succeeded.
      // Anything else is a real failure and must still surface.
      if (!isAlreadyJudged(error)) rethrow;
    }
    await advance();
  }

  /// Moves past the current round, ending the session on the last one.
  ///
  /// Called both from the reveal screen's "Next" and from [judge]'s
  /// tail. From reveal, Mirror's subject must land on the judge step
  /// rather than the next round or the end — stageAfterReveal() decides
  /// that; everyone else (and anyone leaving judge) always proceeds to
  /// the next round or the end.
  Future<void> advance() async {
    final current = state.value;
    if (current == null) return;

    if (current.stage == SessionGameStage.reveal &&
        current.stageAfterReveal() == SessionGameStage.judge) {
      state = AsyncData(current.copyWith(stage: SessionGameStage.judge));
      return;
    }

    if (current.isLastRound) {
      await _repository.completeSession(_sessionId, gameType: _gameType);
      state = AsyncData(current.copyWith(stage: SessionGameStage.end));
      return;
    }

    final nextIndex = current.roundIndex + 1;
    state = AsyncData(
      SessionGameFlowState(
        stage: SessionGameStage.question,
        roundIndex: nextIndex,
        totalRounds: current.totalRounds,
        gameType: current.gameType,
        // Mirror alternates the subject, so this is recomputed each
        // round rather than carried forward.
        isSubject: subjectOf(
          subjectId: _rounds[nextIndex].subjectId,
          userId: _userId,
        ),
      ),
    );
  }
}
