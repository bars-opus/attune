// lib/features/forums/data/repositories/forum_repository.dart

import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForumRepository {
  final SupabaseClient _supabase;

  ForumRepository(this._supabase);

  // ============================================================
  // Topic Submission
  // ============================================================

  /// Submits a topic, optionally with a poll attached (§8.11).
  ///
  /// relationship_status is captured server-side; §7 limit (3/7d) + ban gate are
  /// enforced in the RPC.
  ///
  /// A topic's poll is NOT its activation vote: topic voting decides whether the
  /// topic becomes a live debate room, while a poll asks the topic's readers a
  /// question and gates nothing. A topic can carry both.
  ///
  /// [pollOptions] must be 2-4 plain-text options of at most 60 characters when
  /// present.
  ///
  /// [tagSlugs] is independent of [pollOptions] — a topic can carry a poll and
  /// tags, either, or neither. Attached by a second RPC after the topic exists
  /// (see attachForumTopicTags), mirroring the opinion side.
  Future<void> submitTopic({
    required String content,
    List<String>? pollOptions,
    List<String>? tagSlugs,
  }) async {
    final String newId;
    if (pollOptions == null || pollOptions.isEmpty) {
      newId =
          await _supabase.rpc(
                'create_forum_topic',
                params: {'p_content': content},
              )
              as String;
    } else {
      newId =
          await _supabase.rpc(
                'create_forum_topic_with_poll',
                params: {'p_content': content, 'p_poll_options': pollOptions},
              )
              as String;
    }
    await attachForumTopicTags(newId, tagSlugs);
  }

  // ============================================================
  // Tags — the same fixed, app-seeded vocabulary the opinion side uses
  // (FORUM.md §7 "Tags"). Same access model: the join table has no grants to
  // `authenticated`, so everything goes through a SECURITY DEFINER RPC.
  // ============================================================

  /// Attaches up to 3 tags to a just-created topic. No-ops on null/empty.
  /// Raises `too_many_tags` (22023) past 3 distinct slugs, `not_owner`
  /// (42501) for someone else's topic; unknown slugs are silently ignored.
  Future<void> attachForumTopicTags(
    String topicId,
    List<String>? tagSlugs,
  ) async {
    if (tagSlugs == null || tagSlugs.isEmpty) return;
    await _supabase.rpc(
      'attach_forum_topic_tags',
      params: {'p_topic_id': topicId, 'p_tag_slugs': tagSlugs},
    );
  }

  /// One topic's tags. At most 3 rows.
  Future<List<String>> getForumTopicTags(String topicId) async {
    final rows = await _supabase.rpc(
      'get_forum_topic_tags',
      params: {'p_topic_id': topicId},
    );
    return (rows as List).map((r) => (r as Map)['slug'] as String).toList();
  }

  /// Tags for a whole list of topics in one round trip, keyed by topic id.
  /// Topics with no tags are absent from the map.
  Future<Map<String, List<String>>> getTagsForForumTopics(
    List<String> topicIds,
  ) async {
    if (topicIds.isEmpty) return const {};
    final rows = await _supabase.rpc(
      'get_tags_for_forum_topics',
      params: {'p_topic_ids': topicIds},
    );
    final result = <String, List<String>>{};
    for (final row in (rows as List)) {
      final map = row as Map;
      final id = map['topic_id'] as String;
      (result[id] ??= <String>[]).add(map['slug'] as String);
    }
    return result;
  }

  /// Every topic carrying [tagSlug], newest first.
  ///
  /// Takes ONLY a tag — no author parameter exists in the RPC and none may be
  /// added here, for the same anti-deanonymization reason as the opinion side.
  ///
  /// Parsed with no userVote/userSide: those are named args the live paths
  /// pass from a separate per-viewer lookup, and this browse surface has no
  /// such state to attach — the RPC returns the plain topic columns only.
  Future<List<TopicModel>> getForumTopicsByTag(
    String tagSlug, {
    required int page,
    required int pageSize,
  }) async {
    final rows = await _supabase.rpc(
      'get_forum_topics_by_tag',
      params: {
        'p_tag_slug': tagSlug,
        'p_limit': pageSize,
        'p_offset': page * pageSize,
      },
    );
    return (rows as List)
        .map((r) => TopicModel.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Merges a batched tag lookup onto an already-parsed list of topics.
  /// Same shape and same failure tolerance as OpinionRepository.withTags:
  /// a tag lookup that throws leaves the list rendering without chips rather
  /// than failing the whole load.
  Future<List<TopicModel>> withTags(List<TopicModel> topics) async {
    if (topics.isEmpty) return topics;
    try {
      final byId = await getTagsForForumTopics([for (final t in topics) t.id]);
      if (byId.isEmpty) return topics;
      return [
        for (final t in topics)
          byId.containsKey(t.id) ? t.copyWith(tags: byId[t.id]) : t,
      ];
    } catch (_) {
      return topics;
    }
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
        final voteRes =
            await _supabase
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

  Future<TopicModel?> getTopicDetails(
    String topicId,
    String? currentUserId,
  ) async {
    final response =
        await _supabase
            .from('public_forum_topics')
            .select('*')
            .eq('id', topicId)
            .single();

    String? userVote;
    if (currentUserId != null) {
      final voteRes =
          await _supabase
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
    final existing =
        await _supabase
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
        await _supabase.rpc(
          'decrement_topic_upvote_count',
          params: {'p_topic_id': topicId},
        );
      } else {
        await _supabase.rpc(
          'decrement_topic_downvote_count',
          params: {'p_topic_id': topicId},
        );
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
      await _supabase.rpc(
        'increment_topic_upvote_count',
        params: {'p_topic_id': topicId},
      );
    } else {
      await _supabase.rpc(
        'increment_topic_downvote_count',
        params: {'p_topic_id': topicId},
      );
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
    await _supabase.rpc(
      'increment_topic_seen_count',
      params: {'p_topic_id': topicId},
    );
  }

  /// Records that the user actually OPENED this topic, which is the read
  /// watermark FORUM.md §10 #5 measures "3 new posts since your last visit"
  /// against.
  ///
  /// Deliberately separate from [recordImpression]: an impression is a topic
  /// CARD scrolling into view in the feed, which §10 classes as browsing and
  /// which must never make someone a notification recipient. The RPC derives
  /// the user from auth.uid(), so no user id crosses the wire.
  Future<void> recordTopicVisit({required String topicId}) async {
    await _supabase.rpc(
      'record_forum_topic_visit',
      params: {'p_topic_id': topicId},
    );
  }

  // ============================================================
  // Forum Posts
  // ============================================================

  /// relationship_status is captured server-side; §7 per-forum limit + cooldown +
  /// ban gate are enforced in the RPC, which also bumps the topic's counters.
  Future<void> createForumPost({
    required String topicId,
    required String side,
    required String content,
    String? replyToPostId,
    String? quotedText,
  }) async {
    await _supabase.rpc(
      'create_forum_post',
      params: {
        'p_topic_id': topicId,
        'p_side': side,
        'p_content': content,
        'p_reply_to_post_id': replyToPostId,
        'p_quoted_text': quotedText,
      },
    );
  }

  /// Rewrites a forum post's text within its 15-minute window (FORUM.md §7
  /// "Editing"). Rejects with `not_editable` (42501) when the caller is not
  /// the owner, the post is removed, or the window has closed; and with
  /// `invalid_content` (22023) when blank or over 280 characters.
  ///
  /// Note the parameter is `p_forum_post_id`, not `p_post_id` — the edit RPC
  /// spells it out where the like/unlike counter RPCs above use the short
  /// form. Mismatching it fails at runtime as PGRST202, not at compile time.
  Future<void> editForumPost({
    required String postId,
    required String content,
  }) async {
    await _supabase.rpc(
      'edit_forum_post',
      params: {'p_forum_post_id': postId, 'p_content': content},
    );
  }

  Future<void> likeForumPost({
    required String postId,
    required String userId,
  }) async {
    await _supabase.from('forum_post_likes').insert({
      'forum_post_id': postId,
      'user_id': userId,
    });
    await _supabase.rpc(
      'increment_forum_post_like_count',
      params: {'p_post_id': postId},
    );
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
    await _supabase.rpc(
      'decrement_forum_post_like_count',
      params: {'p_post_id': postId},
    );
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
    String reason = 'Other',
  }) async {
    await _supabase.rpc(
      'report_forum_topic',
      params: {'p_topic_id': topicId, 'p_reason': reason},
    );
  }

  /// Records the report AND auto-hides the post at the §8 threshold (10).
  Future<void> reportForumPost({
    required String postId,
    String reason = 'Other',
  }) async {
    await _supabase.rpc(
      'report_forum_post',
      params: {'p_forum_post_id': postId, 'p_reason': reason},
    );
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
