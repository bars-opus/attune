import 'package:attune/features/games/love_map/domain/love_map_selection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One Love Map round: a question, its subject, and whether the reveal gate
/// has opened.
///
/// Carries no answer fields, deliberately. game_session_rounds' RLS grants
/// relationship members the whole row, so a model with answer_a/answer_b
/// invites a `select()` that bypasses the §8.4 reveal gate. Answers arrive
/// only through get_revealed_round.
class LoveMapRound {
  const LoveMapRound({
    required this.id,
    required this.roundNumber,
    required this.questionId,
    required this.bothAnswered,
    this.subjectId,
  });

  factory LoveMapRound.fromRow(Map<String, dynamic> row) => LoveMapRound(
        id: row['id'] as String,
        roundNumber: (row['round_number'] as num).toInt(),
        questionId: row['question_id'] as String?,
        // Fails closed: a missing or null flag reads as "not revealed".
        bothAnswered: row['both_answered'] as bool? ?? false,
        subjectId: row['active_partner_id'] as String?,
      );

  final String id;
  final int roundNumber;
  final String? questionId;
  final bool bothAnswered;
  final String? subjectId;
}

/// How much of the map is filled. Mutual progress, never a per-partner
/// accuracy figure (§11.1).
class LoveMapCoverage {
  const LoveMapCoverage({required this.answered, required this.total});

  final int answered;
  final int total;
}

class LoveMapRepository {
  LoveMapRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  /// The relationship's open Love Map rounds.
  ///
  /// Selects named columns only. A bare `select()` would return
  /// answer_a/answer_b too — RLS permits it — bypassing the reveal gate.
  /// active_partner_id IS included: it is a subject identifier, not answer
  /// data. Do not add answer_a or answer_b here.
  Future<List<LoveMapRound>> fetchOpenRounds(String relationshipId) async {
    final rows = await _safeClient
        .from('game_session_rounds')
        .select('id, round_number, question_id, both_answered, active_partner_id')
        .eq('relationship_id', relationshipId)
        .order('round_number');

    return rows
        .map((row) => LoveMapRound.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// The questions behind a set of rounds.
  Future<List<LoveMapQuestion>> fetchQuestions(List<String> questionIds) async {
    if (questionIds.isEmpty) return const [];
    final rows = await _safeClient
        .from('game_questions')
        .select('id, question_text, value_domain')
        .inFilter('id', questionIds);

    return rows
        .map((row) => LoveMapQuestion(
              id: row['id'] as String,
              valueDomain: row['value_domain'] as String? ?? '',
              text: row['question_text'] as String,
            ))
        .toList();
  }

  /// How many of the bank's questions this couple has completed.
  ///
  /// The total comes from the question bank rather than a hard-coded 60, so
  /// the bar stays honest if the bank grows.
  Future<LoveMapCoverage> fetchCoverage(String relationshipId) async {
    final answeredRows = await _safeClient
        .from('game_session_rounds')
        .select('id')
        .eq('relationship_id', relationshipId)
        .eq('both_answered', true);

    final totalRows = await _safeClient
        .from('game_questions')
        .select('id')
        .eq('game_type', 'love_map')
        .eq('active', true);

    return LoveMapCoverage(
      answered: (answeredRows as List).length,
      total: (totalRows as List).length,
    );
  }

  /// Submits this caller's text for a round.
  ///
  /// The RPC decides whether it is the subject's truth or the partner's
  /// guess, from active_partner_id — the client never chooses, so it cannot
  /// write a truth row for a round it is not the subject of.
  Future<bool> submitAnswer({
    required String roundId,
    required String answer,
  }) async {
    final result = await _safeClient.rpc(
      'submit_session_game_answer',
      params: {'p_round_id': roundId, 'p_answer': answer},
    );
    return result as bool? ?? false;
  }

  /// The subject's judgement of their partner's guess.
  Future<void> judgeRound({
    required String roundId,
    required bool wasCorrect,
  }) async {
    await _safeClient.rpc(
      'judge_mirror_round',
      params: {'p_round_id': roundId, 'p_was_correct': wasCorrect},
    );
  }

  /// The subject's own answer for a round, once the gate has opened.
  Future<String?> fetchTruth(String roundId) async {
    final row = await _safeClient
        .from('mirror_round_truth')
        .select('truth_text')
        .eq('round_id', roundId)
        .maybeSingle();
    return row?['truth_text'] as String?;
  }
}
