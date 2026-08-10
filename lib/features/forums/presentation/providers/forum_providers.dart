// lib/features/forums/presentation/providers/forum_providers.dart

import 'dart:async';

import 'package:attune/core/realtime/count_broadcast_channel.dart';
import 'package:attune/features/forums/data/cache/forum_feed_cache.dart';
import 'package:attune/features/forums/data/models/forum_post_model.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/data/repositories/forum_repository.dart';
import 'package:flutter/foundation.dart';
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

// Submit a new topic.
//
// Takes no tagSlugs for the same reason as postOpinionProvider: a family's
// argument needs value equality and a List<String> has none, so tags would
// re-run the submission on every rebuild. Tagged submissions go through
// submitTopicWithPoll below.
final submitTopicProvider = FutureProvider.family<bool, String>((
  ref,
  content,
) async {
  final repository = ref.read(forumRepositoryProvider);
  final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) throw Exception('Not authenticated');
  await repository.submitTopic(content: content);
  return true;
});

/// Submits a topic with an optional poll attached (§8.11).
///
/// A plain function rather than a `family` provider: the argument would have to
/// include the option list, and a `List<String>` has no value equality, so every
/// rebuild would create a fresh provider and re-run the submission.
///
/// [tagSlugs] is independent of [pollOptions]: a topic can carry a poll and up
/// to 3 tags, either, or neither (FORUM.md §7 "Tags").
Future<bool> submitTopicWithPoll(
  WidgetRef ref, {
  required String content,
  List<String>? pollOptions,
  List<String>? tagSlugs,
}) async {
  final repository = ref.read(forumRepositoryProvider);
  final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) throw Exception('Not authenticated');
  await repository.submitTopic(
    content: content,
    pollOptions: pollOptions,
    tagSlugs: tagSlugs,
  );
  return true;
}

/// One shared chip row above Forums Explore's three sections (Active/Voting/
/// Quiet) filters all three identically — Explore has no single "feed" to
/// attach a filter to, so this is the one piece of state all three
/// providers below read. Empty means "All" — unfiltered.
final forumsExploreTagFilterProvider = StateProvider<List<String>>(
  (ref) => const [],
);

/// Cache-then-refresh for the forum topic lists: paint the last-known list
/// immediately on a cold start so a relaunch isn't an empty screen while the
/// fetch runs, then swap in fresh data when it lands.
///
/// The cache is a cold-start affordance only. `_servedCache` is static so it
/// survives the notifier being recreated by invalidate() — after a vote or
/// an impression, serving cache first would briefly re-show the pre-change
/// list, which is exactly what those callers just changed. It's also only
/// used for the unfiltered list: a tag-filtered read always fetches fresh
/// (see [build]), matching Discover's same rule on the opinions side.
abstract class _CachedTopicsNotifier extends AsyncNotifier<List<TopicModel>> {
  ForumFeed get feed;

  Future<List<TopicModel>> fetch(List<String> tagSlugs);

  /// Per-subclass, so one list's invalidation doesn't disable another's
  /// cold-start cache. Subclasses back this with their own static field.
  bool get servedCache;
  set servedCache(bool value);

  @override
  Future<List<TopicModel>> build() async {
    final tagSlugs = ref.watch(forumsExploreTagFilterProvider);
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;

    if (tagSlugs.isEmpty) {
      final cache = ref.read(forumFeedCacheProvider);
      // Topic rows carry viewer-specific userVote/userSide, so they're only
      // ever read or written against a signed-in user's own key.
      if (!servedCache && userId != null) {
        servedCache = true;
        final cached = cache.readFeed(feed, userId);
        if (cached.isNotEmpty) {
          _refreshInBackground(cache, userId, tagSlugs);
          return cached;
        }
      }

      final topics = await fetch(tagSlugs);
      if (userId != null) {
        unawaited(cache.writeFeed(feed, userId, topics));
      }
      return topics;
    }

    return fetch(tagSlugs);
  }

  /// Fetches behind an already-painted cached list. Never surfaces an
  /// AsyncLoading (that would flash the cache away) and swallows failure —
  /// the user keeps reading the cached list until a later refresh succeeds.
  Future<void> _refreshInBackground(
    ForumFeedCache cache,
    String userId,
    List<String> tagSlugs,
  ) async {
    try {
      final topics = await fetch(tagSlugs);
      state = AsyncData(topics);
      unawaited(cache.writeFeed(feed, userId, topics));
    } catch (error) {
      debugPrint(
        '[forums] ${feed.key} background refresh failed: ${error.runtimeType}',
      );
    }
  }
}

// Voting topics (in voting pool, not expired)
final votingTopicsProvider =
    AsyncNotifierProvider<VotingTopicsNotifier, List<TopicModel>>(
      VotingTopicsNotifier.new,
    );

class VotingTopicsNotifier extends _CachedTopicsNotifier {
  static bool _servedCache = false;

  @override
  ForumFeed get feed => ForumFeed.voting;

  @override
  bool get servedCache => _servedCache;

  @override
  set servedCache(bool value) => _servedCache = value;

  @override
  Future<List<TopicModel>> fetch(List<String> tagSlugs) async {
    final repository = ref.read(forumRepositoryProvider);
    final currentUserId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    // Tags aren't columns on the topic rows — one batched lookup merges them
    // onto the parsed list (FORUM.md §7 "Tags").
    return repository.withTags(
      await repository.getVotingTopics(currentUserId, tagSlugs: tagSlugs),
    );
  }
}

// Active forums (status = 'active')
final activeForumsProvider =
    AsyncNotifierProvider<ActiveForumsNotifier, List<TopicModel>>(
      ActiveForumsNotifier.new,
    );

class ActiveForumsNotifier extends _CachedTopicsNotifier {
  static bool _servedCache = false;

  @override
  ForumFeed get feed => ForumFeed.active;

  @override
  bool get servedCache => _servedCache;

  @override
  set servedCache(bool value) => _servedCache = value;

  @override
  Future<List<TopicModel>> fetch(List<String> tagSlugs) async {
    final repository = ref.read(forumRepositoryProvider);
    return repository.withTags(
      await repository.getActiveForums(tagSlugs: tagSlugs),
    );
  }
}

// Quiet forums (status = 'quiet')
final quietForumsProvider =
    AsyncNotifierProvider<QuietForumsNotifier, List<TopicModel>>(
      QuietForumsNotifier.new,
    );

class QuietForumsNotifier extends _CachedTopicsNotifier {
  static bool _servedCache = false;

  @override
  ForumFeed get feed => ForumFeed.quiet;

  @override
  bool get servedCache => _servedCache;

  @override
  set servedCache(bool value) => _servedCache = value;

  @override
  Future<List<TopicModel>> fetch(List<String> tagSlugs) async {
    final repository = ref.read(forumRepositoryProvider);
    return repository.withTags(
      await repository.getQuietForums(tagSlugs: tagSlugs),
    );
  }
}

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

// Record that the user opened a topic (read watermark for §10 #5 activity
// notifications). Distinct from the impression provider above, which fires for
// mere browsing.
final recordTopicVisitProvider = FutureProvider.family<void, String>((
  ref,
  topicId,
) async {
  final repository = ref.read(forumRepositoryProvider);
  final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return;
  await repository.recordTopicVisit(topicId: topicId);
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
  if (supabase.auth.currentUser?.id == null) {
    throw Exception('Not authenticated');
  }
  // Goes through the rate-limited, ban-gated RPC (relationship_status captured
  // server-side; topic counters bumped inside the RPC).
  await ref
      .read(forumRepositoryProvider)
      .createForumPost(
        topicId: params.topicId,
        side: params.side,
        content: params.content,
        replyToPostId: params.replyToPostId,
        quotedText: params.quotedText,
      );
});

/// Edits a forum post within its 15-minute window (FORUM.md §7 "Editing"),
/// then refetches the topic's posts so the new text and its "(edited)" marker
/// appear.
///
/// A plain function rather than a `family` provider, matching editOpinion /
/// editComment in opinion_providers.dart: it takes several arguments and
/// re-running it on a rebuild would re-submit the edit.
///
/// Invalidation rather than an in-place patch, because forumPostsProvider is a
/// plain FutureProvider.family with no notifier to patch — the same shape, and
/// the same reasoning, as editComment. It is what likeForumPostProvider's
/// callers already do (see ForumPostBubble._toggleLike).
///
/// NOT WIRED TO ANY UI YET, but no longer blocked: the `public_forum_posts`
/// view now projects both `edited_at` and `is_mine`
/// (20260730140000_forum_post_edit_view_columns.sql), so the "(edited)" marker
/// renders on ForumPostBubble and an Edit affordance can be gated on
/// `post.isMine` whenever one is added.
Future<void> editForumPost(
  WidgetRef ref, {
  required String postId,
  required String topicId,
  required String content,
}) async {
  await ref
      .read(forumRepositoryProvider)
      .editForumPost(postId: postId, content: content);
  ref.invalidate(forumPostsProvider(topicId));
}

/// Deletes YOUR OWN forum post and refetches the topic's posts — same
/// invalidation reasoning as [editForumPost] (forumPostsProvider has no
/// notifier to patch locally). [side] is the deleted post's own FOR/AGAINST
/// side, needed so decrement_topic_post_count knows which of
/// for_posts/against_posts to decrement alongside total_posts.
Future<void> deleteForumPost(
  WidgetRef ref, {
  required String postId,
  required String topicId,
  required String side,
}) async {
  await ref
      .read(forumRepositoryProvider)
      .deleteForumPost(postId: postId, topicId: topicId, side: side);
  ref.invalidate(forumPostsProvider(topicId));
}

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
    params: {'p_post_id': postId},
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
    params: {'p_post_id': postId},
  );
});

// Forums the user has contributed to (voted or posted in)
final contributingForumsProvider =
    AsyncNotifierProvider<ContributingForumsNotifier, List<TopicModel>>(
      ContributingForumsNotifier.new,
    );

class ContributingForumsNotifier extends _CachedTopicsNotifier {
  static bool _servedCache = false;

  @override
  ForumFeed get feed => ForumFeed.contributing;

  @override
  bool get servedCache => _servedCache;

  @override
  set servedCache(bool value) => _servedCache = value;

  // Contributing has no tag-filter UI (out of scope — only Discover and
  // Explore got the filter chip row), so tagSlugs is always empty here.
  @override
  Future<List<TopicModel>> fetch(List<String> tagSlugs) async {
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
  }
}

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
  await repository.reportTopic(topicId: topicId);
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
        reason: params.reason,
      );
    });

// ============================================================
// Tags (FORUM.md §7 "Tags")
// ============================================================

/// Forum topics carrying one tag, paginated, newest first.
///
/// Keyed ONLY by the tag slug, for the same reason as the opinion side: a tag
/// filter may never be combined with an author filter, so no author-scoped
/// variant of this provider exists and none may be added. The RPC takes no
/// author parameter either.
///
/// Parsed with no userVote/userSide — the browse RPC returns the plain topic
/// columns, with no per-viewer vote state to attach.
final forumTopicsByTagProvider = AsyncNotifierProvider.family<
  ForumTopicsByTagNotifier,
  List<TopicModel>,
  String
>(ForumTopicsByTagNotifier.new);

class ForumTopicsByTagNotifier
    extends FamilyAsyncNotifier<List<TopicModel>, String> {
  int _currentPage = 0;
  bool _hasMore = true;
  static const int _pageSize = 20;

  @override
  Future<List<TopicModel>> build(String arg) async {
    _currentPage = 0;
    _hasMore = true;
    final firstPage = await _loadPage(0);
    if (firstPage.length < _pageSize) _hasMore = false;
    return firstPage;
  }

  Future<List<TopicModel>> _loadPage(int page) async {
    final repository = ref.read(forumRepositoryProvider);
    return repository.withTags(
      await repository.getForumTopicsByTag(
        arg,
        page: page,
        pageSize: _pageSize,
      ),
    );
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    if (state is AsyncLoading) return;
    final currentList = state.value ?? [];
    _currentPage++;
    final nextPage = await _loadPage(_currentPage);
    if (nextPage.length < _pageSize) _hasMore = false;
    state = AsyncData([...currentList, ...nextPage]);
  }

  Future<void> refresh() async {
    _currentPage = 0;
    _hasMore = true;
    final fresh = await AsyncValue.guard(() => _loadPage(0));
    if (fresh.valueOrNull != null && fresh.value!.length < _pageSize) {
      _hasMore = false;
    }
    state = fresh;
  }

  bool get hasMore => _hasMore;
}

// ============================================================
// Live counts — cross-user, including guests, via Realtime Broadcast.
// See 20260826120000_realtime_count_broadcasts.sql and
// opinionLiveCountsProvider (opinion_providers.dart) for the full rationale
// — same pattern, mirrored here for topic votes and forum post likes.
// ============================================================

class TopicLiveCounts {
  const TopicLiveCounts({required this.upvoteCount, required this.downvoteCount});
  final int upvoteCount;
  final int downvoteCount;
}

final topicLiveCountsProvider =
    StreamProvider.family<TopicLiveCounts, String>((ref, topicId) {
      final supabase = ref.watch(supabaseClientProvider);
      final controller = StreamController<TopicLiveCounts>();
      final channel = CountBroadcastChannel(
        supabase: supabase,
        topic: 'topic-counts:$topicId',
        onCounts: (payload) {
          final up = payload['upvote_count'];
          final down = payload['downvote_count'];
          if (up is int && down is int) {
            controller.add(
              TopicLiveCounts(upvoteCount: up, downvoteCount: down),
            );
          }
        },
      );
      ref.onDispose(() {
        channel.dispose();
        controller.close();
      });
      return controller.stream;
    });

final postLikeLiveCountProvider =
    StreamProvider.family<int, String>((ref, postId) {
      final supabase = ref.watch(supabaseClientProvider);
      final controller = StreamController<int>();
      final channel = CountBroadcastChannel(
        supabase: supabase,
        topic: 'post-counts:$postId',
        onCounts: (payload) {
          final like = payload['like_count'];
          if (like is int) controller.add(like);
        },
      );
      ref.onDispose(() {
        channel.dispose();
        controller.close();
      });
      return controller.stream;
    });
