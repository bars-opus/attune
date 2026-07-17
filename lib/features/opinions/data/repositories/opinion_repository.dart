// lib/features/opinions/data/repositories/opinion_repository.dart

import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All reads go through anonymized RPCs (get_discover_opinions, etc.) that return
/// an opaque author_handle and an is_mine flag but NEVER the real user_id
/// (FORUM.md §3). All writes that carry spam/ban limits go through RPCs so §7
/// limits are enforced server-side, not merely on the client.
class OpinionRepository {
  final SupabaseClient _supabase;

  OpinionRepository(this._supabase);

  // ============================================================
  // Opinions — feeds (server-side ordered, anonymized, single query)
  // ============================================================

  Future<List<OpinionModel>> getDiscoverFeed({
    required int page,
    required int pageSize,
  }) async {
    final rows = await _supabase.rpc(
      'get_discover_opinions',
      params: {'p_limit': pageSize, 'p_offset': page * pageSize},
    );
    return (rows as List)
        .map((r) => OpinionModel.fromFeedRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<List<OpinionModel>> getFollowingFeed({
    required int page,
    required int pageSize,
  }) async {
    final rows = await _supabase.rpc(
      'get_following_opinions',
      params: {'p_limit': pageSize, 'p_offset': page * pageSize},
    );
    return (rows as List)
        .map((r) => OpinionModel.fromFeedRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Posts an opinion. relationship_status is captured server-side from the
  /// profile; §7 daily limit + cooldown + ban gate are enforced in the RPC.
  Future<void> createOpinion({required String content}) async {
    await _supabase.rpc('create_opinion', params: {'p_content': content});
  }

  Future<void> deleteOpinion(String opinionId) async {
    // RLS restricts UPDATE to the owner; a non-owner delete is a no-op.
    await _supabase
        .from('opinions')
        .update({'removed_at': DateTime.now().toIso8601String()})
        .eq('id', opinionId);
  }

  // ============================================================
  // Reactions (Likes/Dislikes) — reactions are owner-scoped rows, no id leak
  // ============================================================

  Future<void> addReaction({
    required String opinionId,
    required String userId,
    required String type,
  }) async {
    final existing = await _supabase
        .from('opinion_reactions')
        .select('reaction_type')
        .eq('opinion_id', opinionId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('opinion_reactions')
          .delete()
          .eq('opinion_id', opinionId)
          .eq('user_id', userId);
      await _supabase.rpc(
        existing['reaction_type'] == 'like'
            ? 'decrement_opinion_like_count'
            : 'decrement_opinion_dislike_count',
        params: {'opinion_id': opinionId},
      );
    }

    await _supabase.from('opinion_reactions').insert({
      'opinion_id': opinionId,
      'user_id': userId,
      'reaction_type': type,
    });
    await _supabase.rpc(
      type == 'like'
          ? 'increment_opinion_like_count'
          : 'increment_opinion_dislike_count',
      params: {'opinion_id': opinionId},
    );
  }

  Future<void> removeReaction({
    required String opinionId,
    required String userId,
  }) async {
    final existing = await _supabase
        .from('opinion_reactions')
        .select('reaction_type')
        .eq('opinion_id', opinionId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing == null) return;

    await _supabase
        .from('opinion_reactions')
        .delete()
        .eq('opinion_id', opinionId)
        .eq('user_id', userId);
    await _supabase.rpc(
      existing['reaction_type'] == 'like'
          ? 'decrement_opinion_like_count'
          : 'decrement_opinion_dislike_count',
      params: {'opinion_id': opinionId},
    );
  }

  // ============================================================
  // Follows — by opaque author handle; the RPC resolves it to a user_id
  // server-side so the real id never reaches the client.
  // ============================================================

  Future<void> followAuthor(String authorHandle) async {
    await _supabase.rpc(
      'follow_opinion_author',
      params: {'p_author_handle': authorHandle},
    );
  }

  Future<void> unfollowAuthor(String authorHandle) async {
    await _supabase.rpc(
      'unfollow_opinion_author',
      params: {'p_author_handle': authorHandle},
    );
  }

  Future<bool> isFollowingAuthor(String authorHandle) async {
    final res = await _supabase.rpc(
      'is_following_author',
      params: {'p_author_handle': authorHandle},
    );
    return res as bool? ?? false;
  }

  // ============================================================
  // Comments — anonymized read RPC; rate-limited write RPC
  // ============================================================

  Future<List<CommentModel>> getComments(String opinionId) async {
    final rows = await _supabase.rpc(
      'get_opinion_comments',
      params: {'p_opinion_id': opinionId},
    );
    return (rows as List)
        .map((r) => CommentModel.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> createComment({
    required String opinionId,
    required String content,
    String? replyToCommentId,
    String? quotedText,
  }) async {
    await _supabase.rpc('create_opinion_comment', params: {
      'p_opinion_id': opinionId,
      'p_content': content,
      'p_reply_to_comment_id': replyToCommentId,
      'p_quoted_text': quotedText,
    });
  }

  Future<void> deleteComment(String commentId) async {
    final comment = await _supabase
        .from('opinion_comments')
        .select('opinion_id')
        .eq('id', commentId)
        .single();

    await _supabase
        .from('opinion_comments')
        .update({'removed_at': DateTime.now().toIso8601String()})
        .eq('id', commentId);

    await _supabase.rpc(
      'decrement_opinion_comment_count',
      params: {'opinion_id': comment['opinion_id']},
    );
  }

  Future<void> likeComment({
    required String commentId,
    required String userId,
  }) async {
    await _supabase.from('comment_likes').insert({
      'comment_id': commentId,
      'user_id': userId,
    });
    await _supabase.rpc(
      'increment_comment_like_count',
      params: {'comment_id': commentId},
    );
  }

  Future<void> unlikeComment({
    required String commentId,
    required String userId,
  }) async {
    await _supabase
        .from('comment_likes')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId);
    await _supabase.rpc(
      'decrement_comment_like_count',
      params: {'comment_id': commentId},
    );
  }

  // ============================================================
  // Reports — RPC records the report AND auto-hides at the §8 threshold (10).
  // ============================================================

  Future<void> reportOpinion({
    required String opinionId,
    String reason = 'Other',
  }) async {
    await _supabase.rpc('report_opinion',
        params: {'p_opinion_id': opinionId, 'p_reason': reason});
  }

  Future<void> reportComment({
    required String commentId,
    String reason = 'Other',
  }) async {
    await _supabase.rpc('report_opinion_comment',
        params: {'p_comment_id': commentId, 'p_reason': reason});
  }
}
