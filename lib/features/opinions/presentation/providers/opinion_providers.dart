// lib/features/opinions/presentation/providers/opinion_providers.dart

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
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

  @override
  Future<List<OpinionModel>> build() async {
    _currentPage = 0;
    _hasMore = true;
    return await _loadPage(0);
  }

  Future<List<OpinionModel>> _loadPage(int page) async {
    final repository = ref.read(opinionRepositoryProvider);
    return await repository.getDiscoverFeed(page: page, pageSize: _pageSize);
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

  bool get hasMore => _hasMore;
}

// Following feed
final followingFeedProvider =
    AsyncNotifierProvider<FollowingFeedNotifier, List<OpinionModel>>(
      FollowingFeedNotifier.new,
    );

class FollowingFeedNotifier extends AsyncNotifier<List<OpinionModel>> {
  @override
  Future<List<OpinionModel>> build() async {
    return await _loadFeed();
  }

  static const int _pageSize = 20;

  Future<List<OpinionModel>> _loadFeed() async {
    final repository = ref.read(opinionRepositoryProvider);
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) return [];
    return await repository.getFollowingFeed(page: 0, pageSize: _pageSize);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadFeed());
  }
}

// Post opinion
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

// Comments for an opinion
final commentsProvider = FutureProvider.family<List<CommentModel>, String>((
  ref,
  opinionId,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  return await repository.getComments(opinionId);
});

// Post comment
final postCommentProvider = FutureProvider.family<
  void,
  ({
    String opinionId,
    String content,
    String? replyToCommentId,
    String? quotedText,
  })
>((ref, params) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  await repository.createComment(
    opinionId: params.opinionId,
    content: params.content,
    replyToCommentId: params.replyToCommentId,
    quotedText: params.quotedText,
  );
  ref.invalidate(commentsProvider(params.opinionId));
  ref.invalidate(discoverFeedProvider);
});

// Delete comment
final deleteCommentProvider =
    FutureProvider.family<void, ({String commentId, String opinionId})>((
      ref,
      params,
    ) async {
      final repository = ref.read(opinionRepositoryProvider);
      await repository.deleteComment(params.commentId);
      ref.invalidate(commentsProvider(params.opinionId));
    });

// Like comment
final likeCommentProvider = FutureProvider.family<void, String>((
  ref,
  commentId,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  await repository.likeComment(commentId: commentId, userId: userId);
});

// Unlike comment
final unlikeCommentProvider = FutureProvider.family<void, String>((
  ref,
  commentId,
) async {
  final repository = ref.read(opinionRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');
  await repository.unlikeComment(commentId: commentId, userId: userId);
});
