/// Where a session-game round currently is.
///
/// [judge] is Mirror-only and reached only by the round's subject —
/// §8.4 makes them the sole authority on whether their partner read them
/// accurately.
enum SessionGameStage { question, waiting, reveal, judge, end }

/// One session's progression, as pure data.
///
/// I/O-free and separate from the notifier so the transitions can be
/// unit-tested without Supabase, matching how mirror_scoring.dart and
/// sliding_scale_gap.dart were split out.
class SessionGameFlowState {
  const SessionGameFlowState({
    required this.stage,
    required this.roundIndex,
    required this.totalRounds,
    required this.gameType,
    required this.isSubject,
  });

  final SessionGameStage stage;

  /// Zero-based index of the current round.
  final int roundIndex;

  /// Derived from the questions actually fetched, never assumed to be 8 —
  /// Sliding Scale has only 6 seeded questions.
  final int totalRounds;

  final String gameType;

  /// Whether the viewer is this round's subject. Always false outside
  /// Mirror.
  final bool isSubject;

  bool get isLastRound => roundIndex >= totalRounds - 1;

  /// After submitting, you always wait: the partner has not answered yet,
  /// and the reveal gate will not open until they do.
  SessionGameStage stageAfterSubmit() => SessionGameStage.waiting;

  /// After the reveal, Mirror's subject judges the guess; everyone else
  /// moves on. The judge step comes BEFORE the end check so the final
  /// round's judgement is not silently dropped from the score.
  SessionGameStage stageAfterReveal() {
    if (gameType == 'mirror' && isSubject) return SessionGameStage.judge;
    if (isLastRound) return SessionGameStage.end;
    return SessionGameStage.question;
  }

  SessionGameFlowState copyWith({
    SessionGameStage? stage,
    int? roundIndex,
  }) {
    return SessionGameFlowState(
      stage: stage ?? this.stage,
      roundIndex: roundIndex ?? this.roundIndex,
      totalRounds: totalRounds,
      gameType: gameType,
      isSubject: isSubject,
    );
  }
}
