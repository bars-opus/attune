// lib/features/opinions/data/repositories/opinion_repository.dart

import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OpinionRepository {
  final SupabaseClient _supabase;

  OpinionRepository(this._supabase);

  // ============================================================
  // Opinions
  // ============================================================

  Future<List<OpinionModel>> getDiscoverFeed({
    required int page,
    required int pageSize,
    required String? currentUserId,
  }) async {
    final offset = page * pageSize;

    // First, get user's relationship status for ordering
    String? userStatus;
    if (currentUserId != null) {
      final profileRes =
          await _supabase
              .from('profiles')
              .select('relationship_status')
              .eq('id', currentUserId)
              .maybeSingle();
      userStatus = profileRes?['relationship_status'] as String?;
    }

    // Query using the public view (no user_id exposed)
    var query = _supabase
        .from('public_opinions')
        .select('*')
        .order('created_at', ascending: false)
        .range(offset, offset + pageSize - 1);

    final response = await query;

    final List<OpinionModel> opinions = [];
    for (final json in response) {
      // Fetch user's reaction for this opinion (if authenticated)
      String? userReaction;
      if (currentUserId != null) {
        final reactionRes =
            await _supabase
                .from('opinion_reactions')
                .select('reaction_type')
                .eq('opinion_id', json['id'])
                .eq('user_id', currentUserId)
                .maybeSingle();
        userReaction = reactionRes?['reaction_type'] as String?;
      }

      // For discover feed ordering, we need to fetch the user_id to check status
      // But we never expose it in the response
      // This is a limitation of the view approach. Alternative: fetch user_id separately
      // For now, we'll fetch it from opinions table (admin-only in production)
      // In real implementation, create a stored procedure that returns ordered feed with user_id stripped
      // This is a simplified version:
      final opinionUserRes =
          await _supabase
              .from('opinions')
              .select('user_id')
              .eq('id', json['id'])
              .single();
      final userId = opinionUserRes['user_id'] as String;

      opinions.add(
        OpinionModel(
          id: json['id'],
          userId: userId,
          content: json['content'],
          relationshipStatus: json['relationship_status_at_post'],
          likeCount: json['like_count'] ?? 0,
          dislikeCount: json['dislike_count'] ?? 0,
          commentCount: json['comment_count'] ?? 0,
          userReaction: userReaction,
          createdAt: DateTime.parse(json['created_at']),
        ),
      );
    }

    // Apply ordering: same status first, then engagement score
    if (userStatus != null && userStatus.isNotEmpty) {
      opinions.sort((a, b) {
        final aSameStatus = a.relationshipStatus == userStatus;
        final bSameStatus = b.relationshipStatus == userStatus;
        if (aSameStatus != bSameStatus) {
          return bSameStatus ? 1 : -1;
        }
        final aScore = (a.likeCount - a.dislikeCount) + (a.commentCount * 2);
        final bScore = (b.likeCount - b.dislikeCount) + (b.commentCount * 2);
        return bScore.compareTo(aScore);
      });
    }

    return opinions;
  }

  Future<List<OpinionModel>> getFollowingFeed(String currentUserId) async {
    // Get users that current user follows
    final followsRes = await _supabase
        .from('opinion_follows')
        .select('following_id')
        .eq('follower_id', currentUserId);

    final followingIds =
        followsRes.map((f) => f['following_id'] as String).toList();

    // If not following anyone, return empty list immediately
    if (followingIds.isEmpty) {
      return [];
    }

    // Get opinions from followed users
    final opinionsRes = await _supabase
        .from('opinions')
        .select('*')
        .inFilter('user_id', followingIds)
        .isFilter('removed_at', null)
        .eq('hidden_pending_review', false)
        .order('created_at', ascending: false);

    final List<OpinionModel> opinions = [];
    for (final json in opinionsRes) {
      final reactionRes =
          await _supabase
              .from('opinion_reactions')
              .select('reaction_type')
              .eq('opinion_id', json['id'])
              .eq('user_id', currentUserId)
              .maybeSingle();

      opinions.add(
        OpinionModel(
          id: json['id'],
          userId: json['user_id'],
          content: json['content'],
          relationshipStatus: json['relationship_status_at_post'],
          likeCount: json['like_count'] ?? 0,
          dislikeCount: json['dislike_count'] ?? 0,
          commentCount: json['comment_count'] ?? 0,
          userReaction: reactionRes?['reaction_type'] as String?,
          createdAt: DateTime.parse(json['created_at']),
        ),
      );
    }

    return opinions;
  }

  Future<void> createOpinion({
    required String userId,
    required String content,
  }) async {
    // Get user's current relationship status
    final profileRes =
        await _supabase
            .from('profiles')
            .select('relationship_status')
            .eq('id', userId)
            .single();

    final status = profileRes['relationship_status'] as String? ?? 'single';

    await _supabase.from('opinions').insert({
      'user_id': userId,
      'content': content,
      'relationship_status_at_post': status,
    });
  }

  Future<void> deleteOpinion(String opinionId) async {
    await _supabase
        .from('opinions')
        .update({'removed_at': DateTime.now().toIso8601String()})
        .eq('id', opinionId);
  }

  // ============================================================
  // Reactions (Likes/Dislikes)
  // ============================================================

  Future<void> addReaction({
    required String opinionId,
    required String userId,
    required String type,
  }) async {
    // Check if user already has a reaction
    final existing =
        await _supabase
            .from('opinion_reactions')
            .select('reaction_type')
            .eq('opinion_id', opinionId)
            .eq('user_id', userId)
            .maybeSingle();

    if (existing != null) {
      // Remove existing reaction first
      await _supabase
          .from('opinion_reactions')
          .delete()
          .eq('opinion_id', opinionId)
          .eq('user_id', userId);

      // Decrement old reaction count
      if (existing['reaction_type'] == 'like') {
        await _supabase.rpc(
          'decrement_opinion_like_count',
          params: {'opinion_id': opinionId},
        );
      } else {
        await _supabase.rpc(
          'decrement_opinion_dislike_count',
          params: {'opinion_id': opinionId},
        );
      }
    }

    // Insert new reaction
    await _supabase.from('opinion_reactions').insert({
      'opinion_id': opinionId,
      'user_id': userId,
      'reaction_type': type,
    });

    // Increment new reaction count
    if (type == 'like') {
      await _supabase.rpc(
        'increment_opinion_like_count',
        params: {'opinion_id': opinionId},
      );
    } else {
      await _supabase.rpc(
        'increment_opinion_dislike_count',
        params: {'opinion_id': opinionId},
      );
    }
  }

  Future<void> removeReaction({
    required String opinionId,
    required String userId,
  }) async {
    final existing =
        await _supabase
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

    if (existing['reaction_type'] == 'like') {
      await _supabase.rpc(
        'decrement_opinion_like_count',
        params: {'opinion_id': opinionId},
      );
    } else {
      await _supabase.rpc(
        'decrement_opinion_dislike_count',
        params: {'opinion_id': opinionId},
      );
    }
  }

  // ============================================================
  // Follows
  // ============================================================

  Future<void> followUser({
    required String followerId,
    required String followingId,
  }) async {
    await _supabase.from('opinion_follows').insert({
      'follower_id': followerId,
      'following_id': followingId,
    });
  }

  Future<void> unfollowUser({
    required String followerId,
    required String followingId,
  }) async {
    await _supabase
        .from('opinion_follows')
        .delete()
        .eq('follower_id', followerId)
        .eq('following_id', followingId);
  }

  Future<bool> isFollowing({
    required String followerId,
    required String followingId,
  }) async {
    final res =
        await _supabase
            .from('opinion_follows')
            .select('id')
            .eq('follower_id', followerId)
            .eq('following_id', followingId)
            .maybeSingle();
    return res != null;
  }

  // ============================================================
  // Comments
  // ============================================================

  Future<List<CommentModel>> getComments(String opinionId) async {
    final response = await _supabase
        .from('opinion_comments')
        .select('*')
        .eq('opinion_id', opinionId)
        .isFilter('removed_at', null)
        .eq('hidden_pending_review', false)
        .order('created_at', ascending: true);

    return response.map((json) => CommentModel.fromJson(json)).toList();
  }

  Future<void> createComment({
    required String opinionId,
    required String userId,
    required String content,
    String? replyToCommentId,
    String? quotedText,
  }) async {
    // Get user's current relationship status
    final profileRes =
        await _supabase
            .from('profiles')
            .select('relationship_status')
            .eq('id', userId)
            .single();

    final status = profileRes['relationship_status'] as String? ?? 'single';

    await _supabase.from('opinion_comments').insert({
      'opinion_id': opinionId,
      'user_id': userId,
      'content': content,
      'relationship_status_at_post': status,
      'reply_to_comment_id': replyToCommentId,
      'quoted_text': quotedText,
    });

    // Increment comment count on opinion
    await _supabase.rpc(
      'increment_opinion_comment_count',
      params: {'opinion_id': opinionId},
    );
  }

  Future<void> deleteComment(String commentId) async {
    final comment =
        await _supabase
            .from('opinion_comments')
            .select('opinion_id')
            .eq('id', commentId)
            .single();

    await _supabase
        .from('opinion_comments')
        .update({'removed_at': DateTime.now().toIso8601String()})
        .eq('id', commentId);

    // Decrement comment count on opinion
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
  // Reports
  // ============================================================

  Future<void> reportOpinion({
    required String opinionId,
    required String reportedBy,
    required String reason,
  }) async {
    await _supabase.from('forum_reports').insert({
      'reported_by': reportedBy,
      'opinion_id': opinionId,
      'reason': reason,
      'priority': _isPriorityReason(reason),
    });

    // Increment report count on opinion
    await _supabase.rpc(
      'increment_opinion_report_count',
      params: {'opinion_id': opinionId},
    );
  }

  bool _isPriorityReason(String reason) {
    const priorityReasons = [
      'Identifies a real person',
      'Harmful or dangerous content',
      'Hate speech or discrimination',
    ];
    return priorityReasons.contains(reason);
  }
}
