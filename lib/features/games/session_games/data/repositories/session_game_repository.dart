import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A round's answers, readable only once both partners have submitted.
class RevealedRound {
  const RevealedRound({
    required this.answerA,
    required this.answerB,
    required this.bothAnswered,
  });

  /// Null until [bothAnswered] — the server withholds them, the client
  /// does not merely hide them.
  final String? answerA;
  final String? answerB;
  final bool bothAnswered;
}

/// Data access shared by Mirror, Sliding Scale and Scenario.
class SessionGameRepository {
  SessionGameRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  Future<List<SessionGameQuestion>> fetchQuestions({
    required String gameType,
    required int limit,
  }) async {
    final rows = await _safeClient
        .from('game_questions')
        .select()
        .eq('game_type', gameType)
        .eq('active', true)
        // Explicit ordering makes the LIMIT deterministic: without it
        // Postgres gives no guarantee on which subset an unordered
        // LIMIT returns. This does NOT provide variety — created_at is
        // fixed per row, so every couple gets the same top-N questions
        // in the same order, every session, forever. Real variety needs
        // a separate mechanism: randomised selection, or extending
        // game_questions_seen (today: this_or_that, truth_or_dare only)
        // to cover mirror, sliding_scale and scenario. Deliberately out
        // of scope here.
        .order('created_at')
        .limit(limit);

    return rows
        .map((row) =>
            SessionGameQuestion.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Reads a round's answers through the reveal gate.
  ///
  /// Deliberately an RPC, not a table select. game_session_rounds' RLS
  /// grants relationship members access to the whole row and checks
  /// both_answered only inside RPCs, so a direct select would let a
  /// partner read the other's answer before reveal — the mechanic §8.4
  /// calls non-negotiable. get_revealed_round returns nulls until both
  /// have submitted.
  Future<RevealedRound> fetchRevealedRound(String roundId) async {
    final rows = await _safeClient
        .rpc('get_revealed_round', params: {'p_round_id': roundId});

    final list = rows as List<dynamic>;
    if (list.isEmpty) {
      return const RevealedRound(
        answerA: null,
        answerB: null,
        bothAnswered: false,
      );
    }
    final row = Map<String, dynamic>.from(list.first as Map);
    return RevealedRound(
      answerA: row['answer_a'] as String?,
      answerB: row['answer_b'] as String?,
      bothAnswered: row['both_answered'] as bool? ?? false,
    );
  }

  /// Creates a session and its rounds.
  ///
  /// Rounds are created here rather than by a trigger so the question
  /// selection is visible and testable. Questions are drawn with an
  /// explicit ORDER BY — `fetchQuestions` has none, so an unordered
  /// LIMIT would serve the same rows every time.
  Future<String> createSession({
    required String relationshipId,
    required String initiatorId,
    required String gameType,
    required int totalRounds,
  }) async {
    final session = await _safeClient
        .from('game_sessions')
        .insert({
          'relationship_id': relationshipId,
          'initiator_id': initiatorId,
          'game_type': gameType,
          'tone': 'connecting',
          'status': 'active',
          'total_rounds': totalRounds,
        })
        .select('id')
        .single();

    final sessionId = session['id'] as String;

    final questions = await fetchQuestions(
      gameType: gameType,
      limit: totalRounds,
    );

    if (questions.isEmpty) {
      throw StateError('No questions available for $gameType');
    }

    await _safeClient.from('game_session_rounds').insert([
      for (var i = 0; i < questions.length; i++)
        {
          'session_id': sessionId,
          'round_number': i + 1,
          'question_id': questions[i].id,
        },
    ]);

    return sessionId;
  }

  /// Submits this user's answer for a round.
  ///
  /// Goes through the submit_session_game_answer RPC, never a direct
  /// update. The RPC validates the answer for its game type, refuses a
  /// resubmission, and is the only thing that may set both_answered —
  /// a client that wrote the row directly could force an early reveal.
  ///
  /// Returns true when this submission completed the round.
  Future<bool> submitAnswer({
    required String roundId,
    required String answer,
  }) async {
    final result = await _safeClient.rpc(
      'submit_session_game_answer',
      params: {'p_round_id': roundId, 'p_answer': answer},
    );
    return result == true;
  }

  /// Rounds for a session, without answers.
  ///
  /// Selects only the non-answer columns. A `select()` with no argument
  /// would return answer_a/answer_b too — RLS permits it — bypassing the
  /// reveal gate.
  Future<List<SessionGameRound>> fetchRounds(String sessionId) async {
    final rows = await _safeClient
        .from('game_session_rounds')
        .select('id, round_number, question_id, both_answered')
        .eq('session_id', sessionId)
        .order('round_number');

    return rows
        .map((row) => SessionGameRound.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }
}
