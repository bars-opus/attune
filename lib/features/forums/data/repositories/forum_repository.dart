// lib/features/forums/data/repositories/forum_repository.dart

import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForumRepository {
  final SupabaseClient _supabase;

  ForumRepository(this._supabase);

  // ============================================================
  // Topic Submission
  // ============================================================

  Future<void> submitTopic({
    required String userId,
    required String content,
    required String relationshipStatus,
  }) async {
    await _supabase.from('forum_topics').insert({
      'submitted_by': userId,
      'content': content,
      'relationship_status_at_submit': relationshipStatus,
      'upvote_count': 1, // Submitter auto-upvotes
      'seen_count': 1,    // Submitter has seen it
    });
  }

  // ============================================================
  // Topic Retrieval
  // ============================================================

  Future<List<TopicModel>> getVotingTopics(String? currentUserId) async {
    // First, activate any topics that have reached threshold
    await _activateTopics();

    // Then expire old topics
    await _expireTopics();

    // Fetch voting topics
    final response = await _supabase
        .from('public_forum_topics')
        .select('*')
        .eq('status', 'voting')
        .order('created_at', ascending: true);

    final topics = <TopicModel>[];
    for (final json in response) {
      String? userVote;
      if (currentUserId != null) {
        final voteRes = await _supabase
            .from('topic_votes')
            .select('vote_type')
            .eq('topic_id', json['id'])
            .eq('user_id', currentUserId)
            .maybeSingle();
        userVote = voteRes?['vote_type'] as String?;
      }

      topics.add(TopicModel.fromJson(json, userVote: userVote));
    }

    return topics;
  }

  Future<List<TopicModel>> getActiveForums() async {
    final response = await _supabase
        .from('public_forum_topics')
        .select('*')
        .eq('status', 'active')
        .order('last_post_at', ascending: false);

    return response.map((json) => TopicModel.fromJson(json)).toList();
  }

  Future<List<TopicModel>> getQuietForums() async {
    final response = await _supabase
        .from('public_forum_topics')
        .select('*')
        .eq('status', 'quiet')
        .order('last_post_at', ascending: false);

    return response.map((json) => TopicModel.fromJson(json)).toList();
  }

  Future<TopicModel?> getTopicDetails(String topicId, String? currentUserId) async {
    final response = await _supabase
        .from('public_forum_topics')
        .select('*')
        .eq('id', topicId)
        .single();

    String? userVote;
    if (currentUserId != null) {
      final voteRes = await _supabase
          .from('topic_votes')
          .select('vote_type')
          .eq('topic_id', topicId)
          .eq('user_id', currentUserId)
          .maybeSingle();
      userVote = voteRes?['vote_type'] as String?;
    }

    return TopicModel.fromJson(response, userVote: userVote);
  }

  // ============================================================
  // Voting
  // ============================================================

  Future<void> castVote({
    required String topicId,
    required String userId,
    required String voteType, // 'up' or 'down'
  }) async {
    // Check if user already voted
    final existing = await _supabase
        .from('topic_votes')
        .select('vote_type')
        .eq('topic_id', topicId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      // Remove old vote
      await _supabase
          .from('topic_votes')
          .delete()
          .eq('topic_id', topicId)
          .eq('user_id', userId);

      // Decrement old vote count
      if (existing['vote_type'] == 'up') {
        await _supabase.rpc('decrement_topic_upvote_count', params: {'topic_id': topicId});
      } else {
        await _supabase.rpc('decrement_topic_downvote_count', params: {'topic_id': topicId});
      }
    }

    // Add new vote
    await _supabase.from('topic_votes').insert({
      'topic_id': topicId,
      'user_id': userId,
      'vote_type': voteType,
    });

    // Increment new vote count
    if (voteType == 'up') {
      await _supabase.rpc('increment_topic_upvote_count', params: {'topic_id': topicId});
    } else {
      await _supabase.rpc('increment_topic_downvote_count', params: {'topic_id': topicId});
    }
  }

  // ============================================================
  // Impressions
  // ============================================================

  Future<void> recordImpression({
    required String topicId,
    required String userId,
  }) async {
    // Use upsert to avoid duplicate impressions
    await _supabase.from('topic_impressions').upsert({
      'topic_id': topicId,
      'user_id': userId,
    }, onConflict: 'topic_id,user_id');

    // Update seen_count
    await _supabase.rpc('increment_topic_seen_count', params: {'topic_id': topicId});
  }

  // ============================================================
  // Forum Posts
  // ============================================================

  Future<void> createForumPost({
    required String topicId,
    required String userId,
    required String side,
    required String content,
    required String relationshipStatus,
    String? replyToPostId,
    String? quotedText,
  }) async {
    await _supabase.from('forum_posts').insert({
      'topic_id': topicId,
      'user_id': userId,
      'side': side,
      'content': content,
      'relationship_status_at_post': relationshipStatus,
      'reply_to_post_id': replyToPostId,
      'quoted_text': quotedText,
    });

    // Update topic post counts
    await _supabase.rpc('increment_topic_post_count', params: {
      'topic_id': topicId,
      'side': side,
    });
  }

  Future<void> likeForumPost({
    required String postId,
    required String userId,
  }) async {
    await _supabase.from('forum_post_likes').insert({
      'forum_post_id': postId,
      'user_id': userId,
    });
    await _supabase.rpc('increment_forum_post_like_count', params: {'post_id': postId});
  }

  Future<void> unlikeForumPost({
    required String postId,
    required String userId,
  }) async {
    await _supabase
        .from('forum_post_likes')
        .delete()
        .eq('forum_post_id', postId)
        .eq('user_id', userId);
    await _supabase.rpc('decrement_forum_post_like_count', params: {'post_id': postId});
  }

  // ============================================================
  // User Forum Side
  // ============================================================

  Future<void> joinForum({
    required String topicId,
    required String userId,
    required String side, // 'for', 'against', or 'browse'
  }) async {
    await _supabase.from('user_forum_sides').upsert({
      'user_id': userId,
      'topic_id': topicId,
      'side': side,
    }, onConflict: 'user_id,topic_id');
  }

  // ============================================================
  // Reports
  // ============================================================

  Future<void> reportTopic({
    required String topicId,
    required String reportedBy,
    required String reason,
  }) async {
    await _supabase.from('forum_reports').insert({
      'reported_by': reportedBy,
      'topic_id': topicId,
      'reason': reason,
    });
  }

  Future<void> reportForumPost({
    required String postId,
    required String reportedBy,
    required String reason,
  }) async {
    await _supabase.from('forum_reports').insert({
      'reported_by': reportedBy,
      'forum_post_id': postId,
      'reason': reason,
    });
  }

  // ============================================================
  // Private Helper Methods
  // ============================================================

  Future<void> _activateTopics() async {
    await _supabase.rpc('activate_pending_topics');
  }

  Future<void> _expireTopics() async {
    await _supabase.rpc('expire_old_topics');
  }
}
