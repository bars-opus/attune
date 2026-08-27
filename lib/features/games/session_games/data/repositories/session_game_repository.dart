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
        // created_at alone is a total tie: every seeded row of a given
        // game_type is inserted by a single statement, so they all share
        // one now() value. `id` breaks the tie so the LIMIT is genuinely
        // deterministic. This does NOT provide variety — the ordering is
        // fixed per row, so every couple gets the same top-N questions
        // in the same order, every session, forever. Real variety needs
        // a separate mechanism: randomised selection, or extending
        // game_questions_seen (today: this_or_that, truth_or_dare only)
        // to cover mirror, sliding_scale and scenario. Deliberately out
        // of scope here.
        .order('created_at')
        .order('id')
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
  /// Questions are fetched BEFORE the session row is inserted. The old
  /// order committed a session, then fetched, then threw if nothing came
  /// back — stranding a zero-round session the user could neither play
  /// nor clear.
  ///
  /// total_rounds is derived from the questions actually returned, never
  /// from a caller's argument. Sliding Scale has only 6 seeded
  /// questions, so a caller asking for 8 would have written
  /// total_rounds = 8 against 6 real rounds and stranded the controller
  /// on round 7.
  Future<String> createSession({
    required String relationshipId,
    required String initiatorId,
    required String gameType,
    required String partnerId,
  }) async {
    const requestedRounds = 8;

    final questions = await fetchQuestions(
      gameType: gameType,
      limit: requestedRounds,
    );

    if (questions.isEmpty) {
      throw StateError('No questions available for $gameType');
    }

    final session = await _safeClient
        .from('game_sessions')
        .insert({
          'relationship_id': relationshipId,
          'initiator_id': initiatorId,
          'game_type': gameType,
          'tone': 'connecting',
          'status': 'active',
          'total_rounds': questions.length,
        })
        .select('id')
        .single();

    final sessionId = session['id'] as String;

    await _safeClient.from('game_session_rounds').insert([
      for (var i = 0; i < questions.length; i++)
        {
          'session_id': sessionId,
          'round_number': i + 1,
          'question_id': questions[i].id,
          // Mirror alternates the subject so each partner is guessed
          // about half the time. Null for the other games, which have
          // no subject.
          if (gameType == 'mirror')
            'active_partner_id': i.isEven ? initiatorId : partnerId,
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
  /// reveal gate. The column list is answer-free by design, not merely
  /// short: active_partner_id IS included because it is a subject
  /// identifier, not answer data — it names whose inner state a Mirror
  /// round is about, never a partner's response. Do not add answer_a or
  /// answer_b here.
  Future<List<SessionGameRound>> fetchRounds(String sessionId) async {
    final rows = await _safeClient
        .from('game_session_rounds')
        .select('id, round_number, question_id, both_answered, active_partner_id')
        .eq('session_id', sessionId)
        .order('round_number');

    return rows
        .map((row) => SessionGameRound.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Records the subject's judgement of their partner's guess.
  ///
  /// Goes through judge_mirror_round, which enforces that only the
  /// round's subject may judge, only after the reveal, and only once.
  Future<void> judgeRound({
    required String roundId,
    required bool wasCorrect,
  }) async {
    await _safeClient.rpc(
      'judge_mirror_round',
      params: {'p_round_id': roundId, 'p_was_correct': wasCorrect},
    );
  }

  /// Marks a session complete and, for Mirror, derives its scores.
  ///
  /// finalise_mirror_scores recomputes from SUM(was_correct) rather than
  /// incrementing, so calling this twice is safe.
  Future<void> completeSession(
    String sessionId, {
    required String gameType,
  }) async {
    await _safeClient
        .from('game_sessions')
        .update({
          'status': 'completed',
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', sessionId);

    if (gameType == 'mirror') {
      await _safeClient.rpc(
        'finalise_mirror_scores',
        params: {'p_session_id': sessionId},
      );
    }
  }

  /// Whether the signed-in user is `relationships.user_a` for
  /// [relationshipId].
  ///
  /// answer_a/answer_b are assigned by that column, not by who
  /// initiated or who is the Mirror subject — submit_session_game_answer
  /// derives `v_is_a` the same way (`user_a = auth.uid()`). The reveal
  /// screen needs this to know which slot is "yours" without ever
  /// reading the other user's id off the client.
  Future<bool> isUserA(String relationshipId) async {
    final row = await _safeClient
        .from('relationships')
        .select('user_a')
        .eq('id', relationshipId)
        .single();
    return row['user_a'] == _safeClient.auth.currentUser?.id;
  }

  /// The subject's own answer for a Mirror round, or null if not yet
  /// submitted.
  ///
  /// Safe to read directly: mirror_round_truth's RLS lets both partners
  /// SELECT it, which is deliberate — the truth is what the guess is
  /// revealed against, so both must see it at reveal. The reveal gate
  /// lives on the GUESS (get_revealed_round), and the caller must not
  /// display this before both_answered.
  Future<String?> fetchMirrorTruth(String roundId) async {
    final row = await _safeClient
        .from('mirror_round_truth')
        .select('truth_text')
        .eq('round_id', roundId)
        .maybeSingle();
    return row?['truth_text'] as String?;
  }
}
