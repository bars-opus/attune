import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
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
}
