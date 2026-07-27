// lib/core/polls/data/repositories/poll_repository.dart

import 'package:attune/core/polls/data/models/poll_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Polls on opinions and forum topics (ATTUNE_MASTER_SPEC.md §8.11).
///
/// One repository serves both surfaces: a poll behaves identically whether it
/// hangs off an opinion or a topic, so the vote path exists once rather than
/// being duplicated per feature.
///
/// Every call goes through a SECURITY DEFINER RPC. The poll tables carry no
/// grants to `authenticated` at all, so direct table access is impossible by
/// construction — that is what keeps `poll_votes.user_id` unreachable and the
/// voters anonymous.
class PollRepository {
  final SupabaseClient _supabase;

  PollRepository(this._supabase);

  /// Fetches the poll attached to an opinion, or null if it has none.
  ///
  /// Vote counts come back NULL until this viewer has voted — the server masks
  /// them, so a hidden standing is never in the response to begin with.
  Future<PollModel?> getPollForOpinion(String opinionId) async {
    final rows = await _supabase.rpc(
      'get_post_poll',
      params: {'p_opinion_id': opinionId},
    );
    return _parse(rows);
  }

  /// Fetches the poll attached to a forum topic, or null if it has none.
  Future<PollModel?> getPollForTopic(String topicId) async {
    final rows = await _supabase.rpc(
      'get_post_poll',
      params: {'p_topic_id': topicId},
    );
    return _parse(rows);
  }

  /// Which of these opinions carry a poll. One round trip for a whole page of
  /// feed rows, so rendering a feed does not become N+1.
  Future<Map<String, String>> getPollIdsForOpinions(
    List<String> opinionIds,
  ) async {
    if (opinionIds.isEmpty) return const {};
    final rows = await _supabase.rpc(
      'get_polls_for_opinions',
      params: {'p_opinion_ids': opinionIds},
    );
    return {
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        row['opinion_id'] as String: row['poll_id'] as String,
    };
  }

  /// Which of these topics carry a poll.
  Future<Map<String, String>> getPollIdsForTopics(List<String> topicIds) async {
    if (topicIds.isEmpty) return const {};
    final rows = await _supabase.rpc(
      'get_polls_for_topics',
      params: {'p_topic_ids': topicIds},
    );
    return {
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        row['topic_id'] as String: row['poll_id'] as String,
    };
  }

  /// Casts a vote, or moves an existing one to a different option.
  ///
  /// The RPC is idempotent for the option the viewer already holds, so a
  /// double-tap cannot double-count.
  Future<void> castVote(String optionId) async {
    await _supabase.rpc('cast_poll_vote', params: {'p_option_id': optionId});
  }

  /// Retracts this viewer's vote, returning them to the pre-vote state and
  /// re-hiding the results.
  Future<void> retractVote(String pollId) async {
    await _supabase.rpc('retract_poll_vote', params: {'p_poll_id': pollId});
  }

  PollModel? _parse(dynamic rows) {
    if (rows is! List) return null;
    return PollModel.fromRows(
      rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
    );
  }
}
