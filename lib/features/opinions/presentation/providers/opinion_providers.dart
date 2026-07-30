// lib/features/opinions/presentation/providers/opinion_providers.dart

import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/opinions/data/cache/opinion_feed_cache.dart';
import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/muted_author_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
import 'package:attune/features/opinions/presentation/providers/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================
// Providers
// ============================================================

final opinionRepositoryProvider = Provider<OpinionRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return OpinionRepository(supabase);
});

// Current user ID provider (from auth)
final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

// Current user's relationship status
final userRelationshipStatusProvider = FutureProvider<String?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final supabase = ref.watch(supabaseClientProvider);
  final response =
      await supabase
          .from('profiles')
          .select('relationship_status')
          .eq('id', userId)
          .single();
  return response['relationship_status'] as String?;
});

// Discover feed (paginated)
final discoverFeedProvider =
    AsyncNotifierProvider<DiscoverFeedNotifier, List<OpinionModel>>(
      DiscoverFeedNotifier.new,
    );

class DiscoverFeedNotifier extends AsyncNotifier<List<OpinionModel>> {
  int _currentPage = 0;
  bool _hasMore = true;
  static const int _pageSize = 20;

  /// Empty means "All" — unfiltered. Selecting one or more chips narrows the
  /// feed (OR-match) without changing its engagement×recency ranking. Only
  /// the unfiltered "All" feed is cached for instant paint on relaunch (see
  /// [build]) — a tag-filtered view is a transient scoped look, not
  /// something that needs cold-start treatment, so it always fetches fresh.
  List<String> _selectedTagSlugs = const [];

  /// Static, so it survives the notifier being recreated by invalidate().
  /// The cache is a cold-start affordance only: after a post/react/delete
  /// invalidates this provider, serving cache first would briefly re-show
  /// the pre-change list, which is exactly what those callers just changed.
  static bool _servedCache = false;

  @override
  Future<List<OpinionModel>> build() async {
    _currentPage = 0;
    _hasMore = true;

    // Paint the last-known feed immediately so a relaunch isn't a blank
    // screen while the network round-trip runs, then swap in fresh data
    // when it lands. On a cache miss this falls through to the plain
    // awaited fetch (unchanged first-run behavior).
    final cache = ref.read(opinionFeedCacheProvider);
    // Cache rows carry viewer-specific isMine/my_reaction, so they're only
    // ever read or written against a signed-in user's own key.
    final userId = ref.read(currentUserIdProvider);
    if (!_servedCache && userId != null) {
      _servedCache = true;
      final cached = cache.readFeed(OpinionFeed.discover, userId);
      if (cached.isNotEmpty) {
        _refreshInBackground(cache, userId);
        return cached;
      }
    }

    final firstPage = await _loadPage(0);
    // A short first page (fewer than pageSize) means there's nothing more to
    // load — without this, hasMore stayed true forever whenever the whole
    // feed fit on one page, so the ListView kept rendering a trailing
    // "loading" spinner that could never resolve (loadMore() only updates
    // _hasMore on a SECOND page fetch, which a short list never triggers:
    // there's nothing to scroll to reach it).
    if (firstPage.length < _pageSize) {
      _hasMore = false;
    }
    if (userId != null) {
      unawaited(cache.writeFeed(OpinionFeed.discover, userId, firstPage));
    }
    return firstPage;
  }

  /// Fetches page 0 behind an already-painted cached list. Never surfaces an
  /// AsyncLoading (that would flash the cache away) and swallows failure —
  /// the user keeps reading the cached feed until a later refresh succeeds.
  Future<void> _refreshInBackground(
    OpinionFeedCache cache,
    String userId,
  ) async {
    try {
      final firstPage = await _loadPage(0);
      if (firstPage.length < _pageSize) {
        _hasMore = false;
      }
      state = AsyncData(firstPage);
      unawaited(cache.writeFeed(OpinionFeed.discover, userId, firstPage));
    } catch (error) {
      debugPrint(
        '[opinions] discover background refresh failed: '
        '${error.runtimeType}',
      );
    }
  }

  Future<List<OpinionModel>> _loadPage(int page) async {
    final repository = ref.read(opinionRepositoryProvider);
    // Tags are not columns on the feed RPC — one batched lookup per page
    // merges them onto the parsed rows (§8.11 "Tags"). Wrapping here rather
    // than at each caller covers the first load, the background refresh and
    // loadMore alike, since all three go through this one helper.
    return await repository.withTags(
      await repository.getDiscoverFeed(
        page: page,
        pageSize: _pageSize,
        tagSlugs: _selectedTagSlugs,
      ),
    );
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    if (state is AsyncLoading) return;

    final currentList = state.value ?? [];
    _currentPage++;
    final nextPage = await _loadPage(_currentPage);
    if (nextPage.length < _pageSize) {
      _hasMore = false;
    }
    state = AsyncData([...currentList, ...nextPage]);
  }

  List<String> get selectedTagSlugs => _selectedTagSlugs;

  /// Applies a new chip selection and refetches page 0 under it. Empty
  /// [tagSlugs] means "All". A no-op re-selection of the same set is skipped
  /// so tapping an already-selected chip set doesn't refire the network.
  Future<void> setTagFilter(List<String> tagSlugs) async {
    if (listEquals(_selectedTagSlugs, tagSlugs)) return;
    _selectedTagSlugs = tagSlugs;
    _currentPage = 0;
    _hasMore = true;
    state = const AsyncLoading<List<OpinionModel>>().copyWithPrevious(state);
    try {
      final firstPage = await _loadPage(0);
      if (firstPage.length < _pageSize) {
        _hasMore = false;
      }
      state = AsyncData(firstPage);
      // Only the unfiltered feed is the cached one — writing a filtered
      // result under the same cache key would show a scoped view on the
      // next cold start instead of the real "All" feed.
      final userId = ref.read(currentUserIdProvider);
      if (userId != null && tagSlugs.isEmpty) {
        final cache = ref.read(opinionFeedCacheProvider);
        unawaited(cache.writeFeed(OpinionFeed.discover, userId, firstPage));
      }
    } catch (error, stack) {
      state = AsyncError<List<OpinionModel>>(
        error,
        stack,
      ).copyWithPrevious(state);
    }
  }

  /// Flips one row's isSaved in place for the optimistic bookmark toggle.
  /// No-op when this feed doesn't hold the opinion, so the caller can patch
  /// every feed blindly. Deliberately does not rewrite the cache: the cache
  /// is refreshed wholesale on the next load, and a save is cheap to re-fetch.
  void patchSavedState(String opinionId, bool isSaved) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) o.copyWith(isSaved: isSaved) else o,
    ]);
  }

  /// Rewrites one row's content and stamps its "(edited)" marker after a
  /// successful edit, so the card updates in place. Unlike the save/repost
  /// patches this is NOT optimistic — it runs only after the RPC returns, so
  /// there is no rollback path: an edit that fails leaves the old text on
  /// screen, which is exactly what is still stored. See patchSavedState for
  /// the no-op-when-absent rationale.
  void patchEditedContent(String opinionId, String newContent) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withEditedContent(o, newContent) else o,
    ]);
  }

  /// Moves one row's commentCount after posting/deleting a comment locally
  /// (see `postComment`/`deleteComment`), so the parent opinion's card
  /// reflects the change without a feed refetch. No-op when the opinion isn't
  /// currently held by this list.
  void patchCommentCount(String opinionId, int delta) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withCommentCountDelta(o, delta) else o,
    ]);
  }

  /// Flips one row's isRepostedByMe AND moves its repostCount for the
  /// optimistic repost toggle. Both must move together — the count is rendered
  /// beside the icon, so patching only the flag would show an "active" repost
  /// button next to an unchanged number. See patchSavedState for the rest.
  void patchRepostState(String opinionId, bool isReposted) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withRepostState(o, isReposted) else o,
    ]);
  }

  /// Drops every row matching [test] — the optimistic half of hide and mute
  /// (§8.11 "Muting and hiding"). See [_removeWhereFrom] for why this is one
  /// predicate method rather than a remove-by-id and a remove-by-author.
  void removeWhere(bool Function(OpinionModel) test) {
    final list = state.value;
    if (list == null) return;
    if (!list.any(test)) return;
    state = AsyncData([...list.where((o) => !test(o))]);
  }

  bool get hasMore => _hasMore;
}

/// Applies a completed edit to one row: new text, plus the "(edited)" marker.
///
/// Shared by every feed notifier for the same reason as [_withRepostState] —
/// the marker rule lives in one place rather than being re-derived at four
/// call sites.
///
/// editedAt is a client-side DateTime.now() rather than the server's
/// authoritative value: the RPC returns void, so round-tripping just to learn
/// a timestamp that is never rendered (only its non-null-ness is, as
/// "edited") would cost a fetch for nothing. The true value lands on the next
/// natural refetch.
OpinionModel _withEditedContent(OpinionModel o, String newContent) {
  return o.copyWith(content: newContent, editedAt: DateTime.now());
}

/// Moves one row's commentCount by [delta] after a local comment
/// post/delete (see `postComment`/`deleteComment`). Clamped at 0 for the same
/// reason as [_withRepostState]'s repostCount — a delete racing a stale patch
/// must never drive the visible count negative.
OpinionModel _withCommentCountDelta(OpinionModel o, int delta) {
  return o.copyWith(commentCount: (o.commentCount + delta).clamp(0, 1 << 31));
}

/// Applies an optimistic repost toggle to one row.
///
/// Shared by every feed notifier so the count arithmetic (and the no-op guard
/// below) exists once: a repeat patch in the same direction — which happens
/// when two feeds hold the same opinion and both get patched, or on a rollback
/// that never actually applied — must not move the count twice. Clamped at 0
/// to mirror the RPC's GREATEST(repost_count - 1, 0).
OpinionModel _withRepostState(OpinionModel o, bool isReposted) {
  if (o.isRepostedByMe == isReposted) return o;
  return o.copyWith(
    isRepostedByMe: isReposted,
    repostCount:
        isReposted ? o.repostCount + 1 : (o.repostCount - 1).clamp(0, 1 << 31),
  );
}

// Following feed
final followingFeedProvider =
    AsyncNotifierProvider<FollowingFeedNotifier, List<OpinionModel>>(
      FollowingFeedNotifier.new,
    );

class FollowingFeedNotifier extends AsyncNotifier<List<OpinionModel>> {
  /// See DiscoverFeedNotifier._servedCache — cold-start only, so an
  /// invalidate() after a write doesn't re-show the pre-change list.
  static bool _servedCache = false;

  @override
  Future<List<OpinionModel>> build() async {
    // Same cache-then-refresh shape as DiscoverFeedNotifier: show the
    // last-known feed straight away, fetch fresh data behind it.
    final cache = ref.read(opinionFeedCacheProvider);
    // Cache rows carry viewer-specific isMine/my_reaction, so they're only
    // ever read or written against a signed-in user's own key.
    final userId = ref.read(currentUserIdProvider);
    if (!_servedCache && userId != null) {
      _servedCache = true;
      final cached = cache.readFeed(OpinionFeed.following, userId);
      if (cached.isNotEmpty) {
        _refreshInBackground(cache, userId);
        return cached;
      }
    }

    final feed = await _loadFeed();
    if (userId != null) {
      unawaited(cache.writeFeed(OpinionFeed.following, userId, feed));
    }
    return feed;
  }

  static const int _pageSize = 20;

  Future<void> _refreshInBackground(
    OpinionFeedCache cache,
    String userId,
  ) async {
    try {
      final feed = await _loadFeed();
      state = AsyncData(feed);
      unawaited(cache.writeFeed(OpinionFeed.following, userId, feed));
    } catch (error) {
      debugPrint(
        '[opinions] following background refresh failed: '
        '${error.runtimeType}',
      );
    }
  }

  Future<List<OpinionModel>> _loadFeed() async {
    final repository = ref.read(opinionRepositoryProvider);
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) return [];
    // Same batched tag merge as the discover feed — see _loadPage there.
    return await repository.withTags(
      await repository.getFollowingFeed(page: 0, pageSize: _pageSize),
    );
  }

  Future<void> refresh() async {
    // Pull-to-refresh is an explicit user action — keep the current list on
    // screen and swap it for fresh data, rather than flashing a spinner.
    final fresh = await AsyncValue.guard(() => _loadFeed());
    state = fresh;
    final feed = fresh.valueOrNull;
    final userId = ref.read(currentUserIdProvider);
    if (feed != null && userId != null) {
      unawaited(
        ref
            .read(opinionFeedCacheProvider)
            .writeFeed(OpinionFeed.following, userId, feed),
      );
    }
  }

  /// See DiscoverFeedNotifier.patchSavedState.
  void patchSavedState(String opinionId, bool isSaved) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) o.copyWith(isSaved: isSaved) else o,
    ]);
  }

  /// See DiscoverFeedNotifier.patchEditedContent.
  void patchEditedContent(String opinionId, String newContent) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withEditedContent(o, newContent) else o,
    ]);
  }

  /// See DiscoverFeedNotifier.patchCommentCount.
  void patchCommentCount(String opinionId, int delta) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withCommentCountDelta(o, delta) else o,
    ]);
  }

  /// See DiscoverFeedNotifier.patchRepostState.
  void patchRepostState(String opinionId, bool isReposted) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withRepostState(o, isReposted) else o,
    ]);
  }

  /// See DiscoverFeedNotifier.removeWhere.
  void removeWhere(bool Function(OpinionModel) test) {
    final list = state.value;
    if (list == null) return;
    if (!list.any(test)) return;
    state = AsyncData([...list.where((o) => !test(o))]);
  }
}

// Post opinion.
//
// Deliberately takes NO tagSlugs: a family's argument must have value
// equality and a List<String> does not, so threading tags through here would
// re-run the post on every rebuild — the exact trap documented on
// postOpinionWithPoll below. Any call site that needs tags (or a poll) uses
// that function instead; this stays the plain no-attachment path.
final postOpinionProvider = FutureProvider.family<bool, String>((
  ref,
  content,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  await repository.createOpinion(content: content);
  return true;
});

/// Posts an opinion with an optional poll attached (§8.11).
///
/// A plain function rather than a `family` provider: the argument would have to
/// include the option list, and a `List<String>` has no value equality, so every
/// rebuild would create a fresh provider and re-run the post.
///
/// [tagSlugs] is independent of [pollOptions]: a post can carry a poll and up
/// to 3 tags, either, or neither (§8.11 "Tags").
Future<bool> postOpinionWithPoll(
  WidgetRef ref, {
  required String content,
  List<String>? pollOptions,
  List<String>? tagSlugs,
}) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  await repository.createOpinion(
    content: content,
    pollOptions: pollOptions,
    tagSlugs: tagSlugs,
  );
  return true;
}

// Delete opinion
final deleteOpinionProvider = FutureProvider.family<void, String>((
  ref,
  opinionId,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  await repository.deleteOpinion(opinionId);
  ref.invalidate(discoverFeedProvider);
  ref.invalidate(followingFeedProvider);
});

// Add reaction (like/dislike)
final addReactionProvider =
    FutureProvider.family<void, ({String opinionId, String type})>((
      ref,
      params,
    ) async {
      final repository = ref.read(opinionRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw Exception('Not authenticated');
      await repository.addReaction(
        opinionId: params.opinionId,
        userId: userId,
        type: params.type,
      );
      ref.invalidate(discoverFeedProvider);
      ref.invalidate(followingFeedProvider);
    });

// Remove reaction
final removeReactionProvider = FutureProvider.family<void, String>((
  ref,
  opinionId,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  await repository.removeReaction(opinionId: opinionId, userId: userId);
  ref.invalidate(discoverFeedProvider);
  ref.invalidate(followingFeedProvider);
});

// Follow author (by opaque handle)
final followUserProvider = FutureProvider.family<void, String>((
  ref,
  authorHandle,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  await repository.followAuthor(authorHandle);
  ref.invalidate(followingFeedProvider);
  ref.invalidate(followStatusProvider(authorHandle));
});

// Unfollow author (by opaque handle)
final unfollowUserProvider = FutureProvider.family<void, String>((
  ref,
  authorHandle,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  await repository.unfollowAuthor(authorHandle);
  ref.invalidate(followingFeedProvider);
  ref.invalidate(followStatusProvider(authorHandle));
});

// Follow status (by opaque handle)
final followStatusProvider = FutureProvider.family<bool, String>((
  ref,
  authorHandle,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  return await repository.isFollowingAuthor(authorHandle);
});

// ============================================================
// Saves (bookmarks)
// ============================================================

// The caller's saved opinions, newest save first (paginated).
final savedOpinionsProvider =
    AsyncNotifierProvider<SavedOpinionsNotifier, List<OpinionModel>>(
      SavedOpinionsNotifier.new,
    );

class SavedOpinionsNotifier extends AsyncNotifier<List<OpinionModel>> {
  int _currentPage = 0;
  bool _hasMore = true;
  static const int _pageSize = 20;

  @override
  Future<List<OpinionModel>> build() async {
    _currentPage = 0;
    _hasMore = true;

    // Not cached to SharedPreferences, unlike the discover/following feeds:
    // this list is opened deliberately rather than being the cold-start
    // landing surface, so there is no blank-screen-on-relaunch problem to
    // solve, and skipping the cache means a save made on another device is
    // never shown stale here.
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return [];

    final firstPage = await _loadPage(0);
    // Same short-first-page guard as DiscoverFeedNotifier: without it a feed
    // that fits on one page keeps hasMore true forever and the list renders a
    // trailing spinner that can never resolve.
    if (firstPage.length < _pageSize) {
      _hasMore = false;
    }
    return firstPage;
  }

  Future<List<OpinionModel>> _loadPage(int page) async {
    final repository = ref.read(opinionRepositoryProvider);
    return await repository.withTags(
      await repository.getSavedFeed(page: page, pageSize: _pageSize),
    );
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    if (state is AsyncLoading) return;

    final currentList = state.value ?? [];
    _currentPage++;
    final nextPage = await _loadPage(_currentPage);
    if (nextPage.length < _pageSize) {
      _hasMore = false;
    }
    state = AsyncData([...currentList, ...nextPage]);
  }

  Future<void> refresh() async {
    // Explicit pull-to-refresh: keep the current list on screen and swap it
    // for fresh data rather than flashing a spinner (matches
    // FollowingFeedNotifier.refresh).
    _currentPage = 0;
    _hasMore = true;
    final fresh = await AsyncValue.guard(() => _loadPage(0));
    if (fresh.valueOrNull != null && fresh.value!.length < _pageSize) {
      _hasMore = false;
    }
    state = fresh;
  }

  /// Drops a row locally after it is unsaved from within this screen, so the
  /// item leaves the list immediately instead of lingering until a refetch.
  void removeLocally(String opinionId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([...current.where((o) => o.id != opinionId)]);
  }

  /// See DiscoverFeedNotifier.patchEditedContent. Needed even though this is
  /// a saves list: you can save your own opinion, so an edit made from this
  /// screen must land here too.
  void patchEditedContent(String opinionId, String newContent) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withEditedContent(o, newContent) else o,
    ]);
  }

  /// See DiscoverFeedNotifier.patchCommentCount. Needed for the same reason
  /// as patchEditedContent above: a saved opinion can gain a comment while
  /// this screen is open.
  void patchCommentCount(String opinionId, int delta) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withCommentCountDelta(o, delta) else o,
    ]);
  }

  /// See DiscoverFeedNotifier.patchRepostState. Needed even though this list
  /// is a saves membership list: a saved opinion can be reposted from this
  /// screen, and its card renders the repost count.
  void patchRepostState(String opinionId, bool isReposted) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withRepostState(o, isReposted) else o,
    ]);
  }

  bool get hasMore => _hasMore;
}

/// Toggles the save state of one opinion, optimistically.
///
/// The feed providers hold plain `List<OpinionModel>` state, so the flipped
/// row is patched directly into whichever lists already contain it — that is
/// what makes the bookmark icon respond on tap. On failure every list is
/// restored to the pre-tap value, so a failed save never leaves a filled
/// bookmark lying about persisted state.
///
/// Deliberately does NOT invalidate the feed providers on success: a refetch
/// would reorder discover (its ranking is engagement × recency) and yank the
/// card the user just tapped out from under their thumb.
/// Takes a [WidgetRef] rather than a provider [Ref] because it is called from
/// a widget callback (OpinionCard's bookmark tap), the same reason
/// postOpinionWithPoll above is a plain function instead of a family provider.
Future<void> toggleOpinionSaved(
  WidgetRef ref, {
  required String opinionId,
  required bool isCurrentlySaved,
}) async {
  final repository = ref.read(opinionRepositoryProvider);

  void patch(bool saved) {
    ref.read(discoverFeedProvider.notifier).patchSavedState(opinionId, saved);
    ref.read(followingFeedProvider.notifier).patchSavedState(opinionId, saved);
  }

  patch(!isCurrentlySaved);
  try {
    if (isCurrentlySaved) {
      await repository.unsaveOpinion(opinionId);
    } else {
      await repository.saveOpinion(opinionId);
    }
  } catch (_) {
    patch(isCurrentlySaved); // roll back to the pre-tap state
    rethrow;
  }

  // The saved list itself is a membership list, so it genuinely changes shape
  // on every toggle and must be refetched — unlike the feeds patched above.
  ref.invalidate(savedOpinionsProvider);
}

// ============================================================
// Reposts
// ============================================================

// The caller's reposted opinions, newest repost first (paginated).
final repostedOpinionsProvider =
    AsyncNotifierProvider<RepostedOpinionsNotifier, List<OpinionModel>>(
      RepostedOpinionsNotifier.new,
    );

class RepostedOpinionsNotifier extends AsyncNotifier<List<OpinionModel>> {
  int _currentPage = 0;
  bool _hasMore = true;
  static const int _pageSize = 20;

  @override
  Future<List<OpinionModel>> build() async {
    _currentPage = 0;
    _hasMore = true;

    // Not cached to SharedPreferences, for the same reason as
    // SavedOpinionsNotifier: this list is opened deliberately rather than
    // being a cold-start landing surface, so there is no blank screen to
    // solve, and skipping the cache means a repost made on another device is
    // never shown stale here.
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return [];

    final firstPage = await _loadPage(0);
    // Same short-first-page guard as DiscoverFeedNotifier.
    if (firstPage.length < _pageSize) {
      _hasMore = false;
    }
    return firstPage;
  }

  Future<List<OpinionModel>> _loadPage(int page) async {
    final repository = ref.read(opinionRepositoryProvider);
    return await repository.withTags(
      await repository.getRepostedFeed(page: page, pageSize: _pageSize),
    );
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    if (state is AsyncLoading) return;

    final currentList = state.value ?? [];
    _currentPage++;
    final nextPage = await _loadPage(_currentPage);
    if (nextPage.length < _pageSize) {
      _hasMore = false;
    }
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

  /// Drops a row locally after it is un-reposted from within this screen, so
  /// the item leaves the list immediately instead of lingering until a
  /// refetch (mirrors SavedOpinionsNotifier.removeLocally).
  void removeLocally(String opinionId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([...current.where((o) => o.id != opinionId)]);
  }

  /// See DiscoverFeedNotifier.patchEditedContent. Unlike patchRepostState
  /// below, an edit does not change this list's membership — a reposted
  /// opinion stays reposted after its author edits it — so this is a plain
  /// in-place patch like every other feed's.
  void patchEditedContent(String opinionId, String newContent) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withEditedContent(o, newContent) else o,
    ]);
  }

  /// See DiscoverFeedNotifier.patchCommentCount. A reposted opinion can gain
  /// a comment while this screen is open, same as an edit above.
  void patchCommentCount(String opinionId, int delta) {
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withCommentCountDelta(o, delta) else o,
    ]);
  }

  /// This list IS the repost membership list, so un-reposting removes the row
  /// rather than flipping it in place — leaving a hollow repost icon on a
  /// screen titled "Reposted" would read as a rendering bug. A re-repost is
  /// left to the invalidate() in toggleOpinionReposted, which refetches with
  /// the row back in its correct newest-first position; inserting it locally
  /// would have to guess that position.
  void patchRepostState(String opinionId, bool isReposted) {
    if (!isReposted) {
      removeLocally(opinionId);
      return;
    }
    final list = state.value;
    if (list == null) return;
    if (!list.any((o) => o.id == opinionId)) return;
    state = AsyncData([
      for (final o in list)
        if (o.id == opinionId) _withRepostState(o, isReposted) else o,
    ]);
  }

  bool get hasMore => _hasMore;
}

/// Toggles the repost state of one opinion, optimistically.
///
/// Same shape as [toggleOpinionSaved]: patch every feed that might hold the
/// row, await the RPC, roll back on failure. The one difference is that a
/// repost patch moves TWO fields (the flag and the public count) — see
/// _withRepostState.
///
/// Deliberately does NOT invalidate the discover/following feeds on success,
/// for the same reason as saves: a refetch reorders discover and yanks the
/// card out from under the user's thumb.
///
/// Lets a `cannot_repost_own_opinion` (22023) from the RPC propagate rather
/// than swallowing it. OpinionCard hides the button entirely when
/// opinion.isMine, so this should never fire from a real tap — if it does, the
/// caller surfaces it rather than the tap silently doing nothing.
Future<void> toggleOpinionReposted(
  WidgetRef ref, {
  required String opinionId,
  required bool isCurrentlyReposted,
}) async {
  final repository = ref.read(opinionRepositoryProvider);

  void patch(bool reposted) {
    ref
        .read(discoverFeedProvider.notifier)
        .patchRepostState(opinionId, reposted);
    ref
        .read(followingFeedProvider.notifier)
        .patchRepostState(opinionId, reposted);
    ref
        .read(savedOpinionsProvider.notifier)
        .patchRepostState(opinionId, reposted);
    ref
        .read(repostedOpinionsProvider.notifier)
        .patchRepostState(opinionId, reposted);
  }

  patch(!isCurrentlyReposted);
  try {
    if (isCurrentlyReposted) {
      await repository.unrepostOpinion(opinionId);
    } else {
      await repository.repostOpinion(opinionId);
    }
  } catch (_) {
    patch(isCurrentlyReposted); // roll back to the pre-tap state
    rethrow;
  }

  // The reposted list is a membership list, so it genuinely changes shape on
  // every toggle and must be refetched — unlike the feeds patched above.
  ref.invalidate(repostedOpinionsProvider);

  // The author-profile list is a plain FutureProvider with no local mutable
  // state to patch, so it can only be refreshed by invalidation. Doing it
  // unconditionally keeps a profile page open behind the feed from showing a
  // stale count; it is a cheap, single-author query.
  ref.invalidate(profileOpinionsProvider);
}

// ============================================================
// Hides and mutes (§8.11 "Muting and hiding")
// ============================================================

/// Drops matching rows from the two PASSIVE feeds, optimistically.
///
/// Shared by hide and mute because the two differ only in their predicate —
/// one opinion by id, or every opinion by one author. Folding them into a
/// single predicate-taking helper keeps the "which feeds does this affect"
/// decision in exactly one place; duplicating it per-notifier per-action would
/// be four near-identical bodies that could drift.
///
/// Deliberately does NOT touch savedOpinionsProvider or
/// repostedOpinionsProvider: saving or reposting something is a deliberate
/// keep, and a later hide/mute does not retroactively strip it from your own
/// lists. The server agrees — get_saved_opinions and get_reposted_opinions
/// carry no hide/mute filter, so removing rows here would only produce a list
/// that reappears on the next refetch.
void _removeWhereFrom(WidgetRef ref, bool Function(OpinionModel) test) {
  ref.read(discoverFeedProvider.notifier).removeWhere(test);
  ref.read(followingFeedProvider.notifier).removeWhere(test);
}

/// Invalidates both passive feeds so they refetch from the server.
///
/// The recovery path for a failed hide/mute, and the success path for an
/// unmute. An optimistic REMOVAL cannot be rolled back the way a flag toggle
/// can: re-inserting the row would have to guess its position in a feed whose
/// discover ordering is engagement × recency, so a clean refetch is the only
/// way back to a correct list.
void _refetchPassiveFeeds(WidgetRef ref) {
  ref.invalidate(discoverFeedProvider);
  ref.invalidate(followingFeedProvider);
}

/// Hides one opinion from the caller's own feeds.
///
/// Unlike [toggleOpinionSaved] this is not a toggle and flips no field: there
/// is no `isHidden` on OpinionModel because a hidden opinion simply stops
/// being returned by the feed RPCs. The card leaves the list immediately and
/// the server makes that permanent on the next fetch.
///
/// Purely a per-viewer filter — no effect on the opinion's counts, no
/// notification to its author, no effect on any other viewer.
Future<void> hideOpinionFromFeed(
  WidgetRef ref, {
  required String opinionId,
}) async {
  final repository = ref.read(opinionRepositoryProvider);

  _removeWhereFrom(ref, (o) => o.id == opinionId);
  try {
    await repository.hideOpinion(opinionId);
  } catch (_) {
    _refetchPassiveFeeds(ref); // the row comes back; see _refetchPassiveFeeds
    rethrow;
  }
}

/// Mutes an author, removing ALL of their currently-loaded opinions from the
/// passive feeds.
///
/// Muting is retroactive within those feeds (§8.11): leaving the posts that
/// prompted the mute on screen would defeat the point, and the feed RPCs
/// exclude them from the next fetch anyway, so the local removal just makes
/// the server's answer visible now.
///
/// The RPC is awaited BEFORE the removal, unlike hide above: mute raises
/// invalid_handle (22023) on an empty handle, and clearing an author's whole
/// feed presence only to restore it on that error would be a far more
/// jarring flash than one opinion reappearing. Silent and one-directional —
/// the muted author is never told.
Future<void> muteAuthorFromFeed(
  WidgetRef ref, {
  required String authorHandle,
}) async {
  final repository = ref.read(opinionRepositoryProvider);

  await repository.muteAuthor(authorHandle);
  _removeWhereFrom(ref, (o) => o.authorHandle == authorHandle);
  ref.invalidate(mutedAuthorsProvider);
}

/// The caller's own muted handles, newest mute first — backs
/// MutedAuthorsScreen.
///
/// A plain FutureProvider with no local mutable state: the list only changes
/// through mute/unmute, both of which invalidate it, and it is small enough
/// that a refetch is cheaper than maintaining a patched copy.
final mutedAuthorsProvider = FutureProvider<List<MutedAuthor>>((ref) async {
  final repository = ref.read(opinionRepositoryProvider);
  return await repository.getMutedAuthors();
});

/// Unmutes an author and lets their content back into the passive feeds.
///
/// Everything here is invalidation rather than patching: there is no
/// "add back" analog to the optimistic removal above, since the un-muted
/// author's posts have to land in their correct ranked positions among rows
/// this client may never have fetched. A refetch is the only correct answer.
Future<void> unmuteAuthor(WidgetRef ref, {required String authorHandle}) async {
  final repository = ref.read(opinionRepositoryProvider);
  await repository.unmuteAuthor(authorHandle);
  ref.invalidate(mutedAuthorsProvider);
  _refetchPassiveFeeds(ref);
}

// ============================================================
// Quotes
// ============================================================

/// The embedded original for one quote card, or null when it has been removed
/// or deleted (rendered as "This opinion is no longer available").
///
/// Family-keyed on the QUOTED opinion's id rather than the quote's, so several
/// quotes of the same original on one feed page share a single fetch and a
/// single cache entry. Read-only — a quote's target is immutable, so unlike
/// the save/repost state there is nothing here to patch optimistically.
final quotedOriginalProvider = FutureProvider.family<OpinionModel?, String>((
  ref,
  quotedOpinionId,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  return await repository.getQuotedOpinion(quotedOpinionId);
});

/// Posts a quote of [quotedOpinionId] and returns the new opinion's id.
///
/// A plain function rather than a `family` provider for the same reason as
/// [postOpinionWithPoll]: a mutation taking several arguments does not fit the
/// family shape, and re-running it on a rebuild would double-post.
///
/// Deliberately does NOT invalidate the feeds here — posting a normal opinion
/// doesn't either. Both compose screens pop with `true`, and the FAB call site
/// in opinions_tab.dart owns the invalidate-then-scroll-to-top so the new post
/// is actually visible rather than landing off-screen. Quoting reuses that
/// exact path so it feels identical to posting.
Future<String> postQuoteOpinion(
  WidgetRef ref, {
  required String content,
  required String quotedOpinionId,
  List<String>? tagSlugs,
}) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  return await repository.createQuoteOpinion(
    content: content,
    quotedOpinionId: quotedOpinionId,
    tagSlugs: tagSlugs,
  );
}

// ============================================================
// Editing (15-minute window — §8.11 "Editing")
// ============================================================

/// Rewrites an opinion's text, then patches every feed that might hold it so
/// the card updates in place.
///
/// A plain function rather than a `family` provider, matching
/// [postQuoteOpinion] / [toggleOpinionSaved]: it takes two arguments, it is
/// called from a widget callback, and re-running it on a rebuild would
/// re-submit the edit.
///
/// Unlike the save/repost toggles the patch happens AFTER the await, not
/// before: an edit has no instant-feedback affordance to keep responsive (the
/// user is leaving an edit screen, not tapping an icon), and patching first
/// would mean showing text the server may yet reject with `not_editable` —
/// e.g. the window closing between opening the editor and submitting. Failure
/// therefore needs no rollback; the exception propagates for the caller to
/// surface.
///
/// Deliberately does NOT invalidate the feeds: a refetch would reorder
/// discover and yank the card the user just edited out from under them, the
/// same reasoning as [toggleOpinionSaved].
Future<void> editOpinion(
  WidgetRef ref, {
  required String opinionId,
  required String content,
}) async {
  final repository = ref.read(opinionRepositoryProvider);
  await repository.editOpinion(opinionId: opinionId, content: content);

  ref
      .read(discoverFeedProvider.notifier)
      .patchEditedContent(opinionId, content);
  ref
      .read(followingFeedProvider.notifier)
      .patchEditedContent(opinionId, content);
  ref
      .read(savedOpinionsProvider.notifier)
      .patchEditedContent(opinionId, content);
  ref
      .read(repostedOpinionsProvider.notifier)
      .patchEditedContent(opinionId, content);

  // The quoted-original card is a separate FutureProvider with no local
  // mutable state to patch, so editing an opinion that others have quoted can
  // only be reflected by invalidating it — cheap, single-row, and keyed on
  // this exact id so nothing else refetches.
  ref.invalidate(quotedOriginalProvider(opinionId));
}

/// Rewrites YOUR OWN comment's text in place, patched locally like
/// [editOpinion] above — not an invalidate-and-refetch.
///
/// [commentsProvider] used to be a plain `FutureProvider.family` with no
/// notifier to patch, so this invalidated the whole thread instead. That
/// meant an edit could interleave anyone else's new comment posted in the
/// same window into the list at the same moment — a visible reorder mid-edit
/// reads as a bug. `commentsProvider` is now `CommentsNotifier`
/// (`AsyncNotifier`) specifically so post/edit/delete/like on your own
/// comment can patch in place instead — other people's changes only arrive
/// via an explicit pull-to-refresh ([CommentsNotifier.refresh]).
Future<void> editComment(
  WidgetRef ref, {
  required String commentId,
  required String content,
  required String opinionId,
}) async {
  final repository = ref.read(opinionRepositoryProvider);
  await repository.editComment(commentId: commentId, content: content);
  ref
      .read(commentsProvider(opinionId).notifier)
      .patch(
        commentId,
        (c) => c.copyWith(content: content, editedAt: DateTime.now()),
      );
}

// Report opinion (reason kept for the priority-review UX; the RPC records the
// report and auto-hides at threshold — reason is currently client-side only).
final reportOpinionProvider =
    FutureProvider.family<void, ({String opinionId, String reason})>((
      ref,
      params,
    ) async {
      final repository = ref.read(opinionRepositoryProvider);
      await repository.reportOpinion(
        opinionId: params.opinionId,
        reason: params.reason,
      );
    });

/// Comments for one opinion. An [AsyncNotifier] rather than a plain
/// [FutureProvider], so posting/editing/deleting/liking YOUR OWN comment can
/// patch this list directly instead of invalidating and refetching the whole
/// thread from the server.
///
/// The refetch-on-every-mutation this replaced is what caused the "jump":
/// posting a comment re-fetched the entire thread, and if anyone else had
/// commented in that same window, their comment interleaved into the list at
/// the same moment yours appeared — the visible reorder read as a UI bug.
/// Instagram-style fix: your own writes land locally and instantly; other
/// people's new comments only arrive on an explicit pull-to-refresh
/// ([refresh]), never silently mid-scroll.
final commentsProvider =
    AsyncNotifierProvider.family<CommentsNotifier, List<CommentModel>, String>(
      CommentsNotifier.new,
    );

class CommentsNotifier extends FamilyAsyncNotifier<List<CommentModel>, String> {
  @override
  Future<List<CommentModel>> build(String opinionId) {
    return ref.read(opinionRepositoryProvider).getComments(opinionId);
  }

  /// Explicit pull-to-refresh: the one place another user's new comments,
  /// edits, or likes are allowed to appear — never as a side effect of the
  /// viewer's own action.
  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(opinionRepositoryProvider).getComments(arg),
    );
  }

  /// Appends a just-posted comment (own write, so it belongs on screen
  /// immediately rather than waiting for the next pull-to-refresh).
  void append(CommentModel comment) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([...list, comment]);
  }

  /// Drops a just-deleted comment (own write, same reasoning as [append]).
  void remove(String commentId) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData(list.where((c) => c.id != commentId).toList());
  }

  /// Rewrites one comment in place — edit and like both use this.
  void patch(String commentId, CommentModel Function(CommentModel) apply) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([
      for (final c in list)
        if (c.id == commentId) apply(c) else c,
    ]);
  }
}

/// Posts a comment/reply and appends it to [commentsProvider] locally.
///
/// The RPC's RETURNS uuid gives back the new row's real id, so there is
/// nothing to reconcile later — the locally-built [CommentModel] IS the row
/// the next natural refetch would have returned, just without waiting for
/// one. `authorHandle` is left as `''`: the anonymous handle is never
/// actually rendered on a comment card (see CommentModel's isMine-only
/// styling), so there is nothing for the client to know or guess here — the
/// same blank the server-side fallback already uses for a missing handle.
///
/// Also bumps the opinion's `comment_count` on every feed holding it, the
/// same in-place patch style [toggleOpinionReposted] already uses for its
/// counter, so the parent opinion's card reflects the new comment without a
/// feed refetch either.
Future<void> postComment(
  WidgetRef ref, {
  required String opinionId,
  required String content,
  String? replyToCommentId,
  String? quotedText,
}) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  final newId = await repository.createComment(
    opinionId: opinionId,
    content: content,
    replyToCommentId: replyToCommentId,
    quotedText: quotedText,
  );

  final status = ref.read(userRelationshipStatusProvider).valueOrNull;
  final newComment = CommentModel(
    id: newId,
    authorHandle: '',
    isMine: true,
    content: content,
    relationshipStatus: status,
    quotedText: quotedText,
    replyToCommentId: replyToCommentId,
    likeCount: 0,
    createdAt: DateTime.now(),
  );

  ref.read(commentsProvider(opinionId).notifier).append(newComment);
  _bumpCommentCount(ref, opinionId, 1);
}

void _bumpCommentCount(WidgetRef ref, String opinionId, int delta) {
  // Four distinct notifier classes (no shared patchable base), so each is
  // called explicitly rather than iterated — matches toggleOpinionReposted's
  // patch() above.
  ref.read(discoverFeedProvider.notifier).patchCommentCount(opinionId, delta);
  ref.read(followingFeedProvider.notifier).patchCommentCount(opinionId, delta);
  ref.read(savedOpinionsProvider.notifier).patchCommentCount(opinionId, delta);
  ref
      .read(repostedOpinionsProvider.notifier)
      .patchCommentCount(opinionId, delta);
}

/// Deletes YOUR OWN comment and drops it from [commentsProvider] locally —
/// same reasoning as [postComment]: no reason to refetch a whole thread for
/// a change only the deleting user could have made.
Future<void> deleteComment(
  WidgetRef ref, {
  required String commentId,
  required String opinionId,
}) async {
  final repository = ref.read(opinionRepositoryProvider);
  await repository.deleteComment(commentId);

  ref.read(commentsProvider(opinionId).notifier).remove(commentId);
  _bumpCommentCount(ref, opinionId, -1);
}

/// Likes/unlikes YOUR OWN reaction to a comment, patched locally — a like is
/// always the viewer's own action, so there is nothing here another user's
/// pull-to-refresh needs to reveal.
Future<void> toggleCommentLiked(
  WidgetRef ref, {
  required String opinionId,
  required String commentId,
  required bool isCurrentlyLiked,
}) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  final notifier = ref.read(commentsProvider(opinionId).notifier);

  void patch(bool liked) {
    notifier.patch(
      commentId,
      (c) => c.copyWith(
        likedByMe: liked,
        likeCount:
            liked ? c.likeCount + 1 : (c.likeCount - 1).clamp(0, 1 << 31),
      ),
    );
  }

  patch(!isCurrentlyLiked);
  try {
    if (isCurrentlyLiked) {
      await repository.unlikeComment(commentId: commentId, userId: userId);
    } else {
      await repository.likeComment(commentId: commentId, userId: userId);
    }
  } catch (_) {
    patch(isCurrentlyLiked);
    rethrow;
  }
}

// ============================================================
// Tags (§8.11 "Tags") — a fixed, app-seeded vocabulary, never freeform.
// ============================================================

/// The full tag vocabulary, for the composer's chip picker and the tag browse
/// entry point.
///
/// A plain FutureProvider because the list is static server-side: fetched once
/// and cached for the app's lifetime, so opening the composer repeatedly (or
/// typing in the tag search field) never re-hits the network.
final allTagsProvider = FutureProvider<List<String>>((ref) async {
  return ref.read(opinionRepositoryProvider).getAllTags();
});

/// Opinions carrying one tag, paginated, newest first.
///
/// Keyed ONLY by the tag slug. There is no author-scoped variant of this
/// provider and there must never be one: "everyone who used this tag" is safe,
/// while "this author's posts tagged X" would let a viewer narrow in on one
/// person by topic — the deanonymization risk the fixed vocabulary exists to
/// prevent (§8.11 "Tag browsing"). The RPC takes no author parameter either.
final opinionsByTagProvider = AsyncNotifierProvider.family<
  OpinionsByTagNotifier,
  List<OpinionModel>,
  String
>(OpinionsByTagNotifier.new);

class OpinionsByTagNotifier
    extends FamilyAsyncNotifier<List<OpinionModel>, String> {
  int _currentPage = 0;
  bool _hasMore = true;
  static const int _pageSize = 20;

  @override
  Future<List<OpinionModel>> build(String arg) async {
    _currentPage = 0;
    _hasMore = true;
    final firstPage = await _loadPage(0);
    // Same short-first-page guard as the other paginated lists: without it a
    // list that fits on one page keeps hasMore true forever and renders a
    // trailing spinner that can never resolve.
    if (firstPage.length < _pageSize) _hasMore = false;
    return firstPage;
  }

  Future<List<OpinionModel>> _loadPage(int page) async {
    final repository = ref.read(opinionRepositoryProvider);
    // Tag-browse rows come back in the discover shape, which carries no tags
    // — so they get the same batched merge every other feed page gets.
    return repository.withTags(
      await repository.getOpinionsByTag(arg, page: page, pageSize: _pageSize),
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
