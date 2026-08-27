/// One round of a session game, WITHOUT its answers.
///
/// The absence of answer fields is deliberate and load-bearing. Answers
/// reach the UI only through SessionGameRepository.fetchRevealedRound,
/// which calls the gated get_revealed_round RPC. game_session_rounds'
/// RLS grants relationship members the whole row, so a model that could
/// carry answers would invite a direct table select that RLS permits and
/// the reveal gate never sees — reintroducing exactly the hole the RPC
/// exists to close (§8.4).
class SessionGameRound {
  const SessionGameRound({
    required this.id,
    required this.roundNumber,
    required this.questionId,
    required this.bothAnswered,
    this.subjectId,
  });

  final String id;
  final int roundNumber;
  final String? questionId;

  /// Whether the reveal gate has opened. Fails closed: a missing or
  /// non-boolean value reads as false, because a wrong `true` would show
  /// both answers early while a wrong `false` only delays a reveal.
  final bool bothAnswered;

  /// Whose inner state this round is about — Mirror only, null for the
  /// other two games. Mirror alternates it across the session, so the
  /// controller reads it to decide whether this user submits a truth or
  /// a guess, and who may judge the round afterwards.
  final String? subjectId;

  factory SessionGameRound.fromRow(Map<String, dynamic> row) {
    return SessionGameRound(
      id: row['id'] as String,
      roundNumber: (row['round_number'] as num?)?.toInt() ?? 0,
      questionId: row['question_id'] as String?,
      bothAnswered: row['both_answered'] == true,
      subjectId: row['active_partner_id'] as String?,
    );
  }
}
