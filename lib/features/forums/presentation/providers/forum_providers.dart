// lib/features/forums/presentation/providers/forum_providers.dart

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/forums/data/models/forum_post_model.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/data/repositories/forum_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final forumRepositoryProvider = Provider<ForumRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return ForumRepository(supabase);
});
// Current user's relationship status (for submitter status)
final currentUserStatusProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;
  final response =
      await supabase
          .from('profiles')
          .select('relationship_status')
          .eq('id', userId)
          .single();
  return response['relationship_status'] as String?;
});

// Submit a new topic
final submitTopicProvider = FutureProvider.family<bool, String>((
  ref,
  content,
) async {
  final repository = ref.read(forumRepositoryProvider);
  final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
  final userStatus = await ref.read(currentUserStatusProvider.future);
  if (userId == null) throw Exception('Not authenticated');
  await repository.submitTopic(
    userId: userId,
    content: content,
    relationshipStatus: userStatus ?? 'single',
  );
  return true;
});

// Voting topics (in voting pool, not expired)
final votingTopicsProvider = FutureProvider<List<TopicModel>>((ref) async {
  final repository = ref.read(forumRepositoryProvider);
  final currentUserId = ref.read(supabaseClientProvider).auth.currentUser?.id;
  return await repository.getVotingTopics(currentUserId);
});

// Active forums (status = 'active')
final activeForumsProvider = FutureProvider<List<TopicModel>>((ref) async {
  final repository = ref.read(forumRepositoryProvider);
  return await repository.getActiveForums();
});

// Quiet forums (status = 'quiet')
final quietForumsProvider = FutureProvider<List<TopicModel>>((ref) async {
  final repository = ref.read(forumRepositoryProvider);
  return await repository.getQuietForums();
});

// Cast vote on a topic
final castTopicVoteProvider =
    FutureProvider.family<void, ({String topicId, String voteType})>((
      ref,
      params,
    ) async {
      final repository = ref.read(forumRepositoryProvider);
      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');
      await repository.castVote(
        topicId: params.topicId,
        userId: userId,
        voteType: params.voteType,
      );
      ref.invalidate(votingTopicsProvider);
    });

// Record impression
final recordTopicImpressionProvider = FutureProvider.family<void, String>((
  ref,
  topicId,
) async {
  final repository = ref.read(forumRepositoryProvider);
  final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return;
  await repository.recordImpression(topicId: topicId, userId: userId);
  ref.invalidate(votingTopicsProvider);
});

// Add to lib/features/forums/presentation/providers/forum_providers.dart

// Join forum (for non-voters)
final joinForumProvider =
    FutureProvider.family<void, ({String topicId, String side})>((
      ref,
      params,
    ) async {
      final supabase = ref.read(supabaseClientProvider);
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      await supabase.from('user_forum_sides').upsert({
        'user_id': userId,
        'topic_id': params.topicId,
        'side': params.side,
      });
    });

// Forum posts for a topic
final forumPostsProvider = FutureProvider.family<List<ForumPostModel>, String>((
  ref,
  topicId,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;

  final response = await supabase
      .from('public_forum_posts')
      .select('*')
      .eq('topic_id', topicId)
      .order('created_at', ascending: true);

  // Get user's likes
  Set<String> likedPostIds = {};
  if (userId != null) {
    final likesRes = await supabase
        .from('forum_post_likes')
        .select('forum_post_id')
        .eq('user_id', userId);
    likedPostIds = likesRes.map((l) => l['forum_post_id'] as String).toSet();
  }

  return response
      .map(
        (json) =>
            ForumPostModel.fromJson(json, likedPostIds.contains(json['id'])),
      )
      .toList();
});

// Submit forum post
final submitForumPostProvider = FutureProvider.family<
  void,
  ({
    String topicId,
    String content,
    String side,
    String? replyToPostId,
    String? quotedText,
  })
>((ref, params) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) throw Exception('Not authenticated');

  // Get user's relationship status
  final profileRes =
      await supabase
          .from('profiles')
          .select('relationship_status')
          .eq('id', userId)
          .single();
  final status = profileRes['relationship_status'] as String? ?? 'single';

  await supabase.from('forum_posts').insert({
    'topic_id': params.topicId,
    'user_id': userId,
    'content': params.content,
    'side': params.side,
    'relationship_status_at_post': status,
    'reply_to_post_id': params.replyToPostId,
    'quoted_text': params.quotedText,
  });

  // Update topic post counts
  await supabase.rpc(
    'increment_topic_post_count',
    params: {'topic_id': params.topicId, 'side': params.side},
  );
});

// Like forum post
final likeForumPostProvider = FutureProvider.family<void, String>((
  ref,
  postId,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) throw Exception('Not authenticated');

  await supabase.from('forum_post_likes').insert({
    'forum_post_id': postId,
    'user_id': userId,
  });
  await supabase.rpc(
    'increment_forum_post_like_count',
    params: {'post_id': postId},
  );
});

// Unlike forum post
final unlikeForumPostProvider = FutureProvider.family<void, String>((
  ref,
  postId,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) throw Exception('Not authenticated');

  await supabase
      .from('forum_post_likes')
      .delete()
      .eq('forum_post_id', postId)
      .eq('user_id', userId);
  await supabase.rpc(
    'decrement_forum_post_like_count',
    params: {'post_id': postId},
  );
});

// Forums the user has contributed to (voted or posted in)
final contributingForumsProvider = FutureProvider<List<TopicModel>>((
  ref,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Get topics where user has voted OR posted
  final votedTopicsRes = await supabase
      .from('topic_votes')
      .select('topic_id, vote_type')
      .eq('user_id', userId);

  final postedTopicsRes = await supabase
      .from('forum_posts')
      .select('topic_id, side')
      .eq('user_id', userId);

  final topicIds = <String>{};
  final userVotes = <String, String>{};
  final userSides = <String, String>{};

  for (final vote in votedTopicsRes) {
    final topicId = vote['topic_id'] as String;
    topicIds.add(topicId);
    userVotes[topicId] = vote['vote_type'] == 'up' ? 'up' : 'down';
    userSides[topicId] = vote['vote_type'] == 'up' ? 'FOR' : 'AGAINST';
  }

  for (final post in postedTopicsRes) {
    final topicId = post['topic_id'] as String;
    topicIds.add(topicId);
    if (!userSides.containsKey(topicId)) {
      final side = post['side'] as String;
      userSides[topicId] = side.toUpperCase();
    }
  }

  if (topicIds.isEmpty) return [];

  // Fetch topic details
  final topicsRes = await supabase
      .from('public_forum_topics')
      .select('*')
      .inFilter('id', topicIds.toList())
      .order('last_post_at', ascending: false);

  return topicsRes.map((json) {
    final topicId = json['id'] as String;
    return TopicModel.fromJson(
      json,
      userVote: userVotes[topicId],
      userSide: userSides[topicId],
    );
  }).toList();
});

// Add this to the existing providers
final topicDetailsProvider = FutureProvider.family<TopicModel?, String>((
  ref,
  topicId,
) async {
  final repository = ref.read(forumRepositoryProvider);
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  return await repository.getTopicDetails(topicId, userId);
});

final reportForumProvider = FutureProvider.family<void, String>((
  ref,
  topicId,
) async {
  final repository = ref.read(forumRepositoryProvider);
  final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) throw Exception('Not authenticated');
  await repository.reportTopic(
    topicId: topicId,
    reportedBy: userId,
    reason: 'Reported from forum screen',
  );
});

final reportForumPostProvider =
    FutureProvider.family<void, ({String postId, String reason})>((
      ref,
      params,
    ) async {
      final repository = ref.read(forumRepositoryProvider);
      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');
      await repository.reportForumPost(
        postId: params.postId,
        reportedBy: userId,
        reason: params.reason,
      );
    });
