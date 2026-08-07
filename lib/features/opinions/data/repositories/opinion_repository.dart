// lib/features/opinions/data/repositories/opinion_repository.dart

import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/muted_author_model.dart';
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

  /// [tagSlugs] null or empty means "All" — unfiltered, the same result as
  /// before this parameter existed. Non-empty means OR-match: an opinion
  /// needs at least one of the given tags to appear. Ranking
  /// (engagement×recency) is unchanged either way — a tag filter narrows
  /// which rows appear, it does not switch Discover to a different,
  /// chronological ordering.
  Future<List<OpinionModel>> getDiscoverFeed({
    required int page,
    required int pageSize,
    List<String>? tagSlugs,
  }) async {
    final rows = await _supabase.rpc(
      'get_discover_opinions',
      params: {
        'p_limit': pageSize,
        'p_offset': page * pageSize,
        'p_tag_slugs': (tagSlugs == null || tagSlugs.isEmpty) ? null : tagSlugs,
      },
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

  /// Posts an opinion, optionally with a poll attached (§8.11).
  ///
  /// relationship_status is captured server-side from the profile; §7 daily
  /// limit + cooldown + ban gate are enforced in the RPC.
  ///
  /// [pollOptions] must be 2-4 plain-text options of at most 60 characters when
  /// present. The opinion and its poll are created in one transaction, so a
  /// rate-limit rejection cannot leave a poll behind.
  ///
  /// [tagSlugs] is INDEPENDENT of [pollOptions] — a post can have a poll and
  /// tags, either, or neither. Tags are attached by a second RPC rather than a
  /// create_opinion_with_poll_and_tags combinator, per the migration's design
  /// note: tags are orthogonal metadata that apply equally to a plain, poll,
  /// or quote post, so folding them into the create_* variants would multiply
  /// combinatorially. Both calls complete before the post is rendered to
  /// anyone else, so there is no visible window where it exists untagged.
  Future<void> createOpinion({
    required String content,
    List<String>? pollOptions,
    List<String>? tagSlugs,
  }) async {
    final String newId;
    if (pollOptions == null || pollOptions.isEmpty) {
      newId =
          await _supabase.rpc('create_opinion', params: {'p_content': content})
              as String;
    } else {
      newId =
          await _supabase.rpc(
                'create_opinion_with_poll',
                params: {'p_content': content, 'p_poll_options': pollOptions},
              )
              as String;
    }
    await attachOpinionTags(newId, tagSlugs);
  }

  /// Rewrites an opinion's text within its 15-minute window (§8.11
  /// "Editing"), setting the server-side edited_at that drives the "(edited)"
  /// marker.
  ///
  /// Throws PostgrestException on rejection, which the caller surfaces:
  ///   - `not_editable` (42501) — not the owner, already removed, or the
  ///     window has closed. Deliberately one message for all three server-side.
  ///   - `invalid_content` (22023) — blank or over 5000 characters.
  Future<void> editOpinion({
    required String opinionId,
    required String content,
  }) async {
    await _supabase.rpc(
      'edit_opinion',
      params: {'p_opinion_id': opinionId, 'p_content': content},
    );
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
    final existing =
        await _supabase
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
        params: {'p_opinion_id': opinionId},
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
      params: {'p_opinion_id': opinionId},
    );
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
    await _supabase.rpc(
      existing['reaction_type'] == 'like'
          ? 'decrement_opinion_like_count'
          : 'decrement_opinion_dislike_count',
      params: {'p_opinion_id': opinionId},
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
  // Saves (bookmarks) — keyed on opinion_id, so unlike follows there is no
  // handle to resolve. A save is private to the saver; nothing exposes it to
  // the opinion's author.
  // ============================================================

  Future<List<OpinionModel>> getSavedFeed({
    required int page,
    required int pageSize,
  }) async {
    final rows = await _supabase.rpc(
      'get_saved_opinions',
      params: {'p_limit': pageSize, 'p_offset': page * pageSize},
    );
    return (rows as List)
        .map((r) => OpinionModel.fromFeedRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Idempotent server-side (ON CONFLICT DO NOTHING), so a double-tap races
  /// harmlessly rather than throwing a unique-violation at the UI.
  Future<void> saveOpinion(String opinionId) async {
    await _supabase.rpc('save_opinion', params: {'p_opinion_id': opinionId});
  }

  Future<void> unsaveOpinion(String opinionId) async {
    await _supabase.rpc('unsave_opinion', params: {'p_opinion_id': opinionId});
  }

  Future<bool> isOpinionSaved(String opinionId) async {
    final res = await _supabase.rpc(
      'is_opinion_saved',
      params: {'p_opinion_id': opinionId},
    );
    return res as bool? ?? false;
  }

  // ============================================================
  // Reposts — keyed on opinion_id like saves, but public: a repost is feed
  // content everyone sees, and the author is notified (anonymously). Self-
  // repost is rejected server-side with cannot_repost_own_opinion (22023).
  // ============================================================

  Future<List<OpinionModel>> getRepostedFeed({
    required int page,
    required int pageSize,
  }) async {
    final rows = await _supabase.rpc(
      'get_reposted_opinions',
      params: {'p_limit': pageSize, 'p_offset': page * pageSize},
    );
    return (rows as List)
        .map((r) => OpinionModel.fromFeedRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Idempotent server-side (ON CONFLICT DO NOTHING) — the counter only moves
  /// and the author is only notified on a genuinely new repost, so a
  /// double-tap cannot double-count. Throws on a self-repost attempt; the UI
  /// gates that before it can reach here.
  Future<void> repostOpinion(String opinionId) async {
    await _supabase.rpc('repost_opinion', params: {'p_opinion_id': opinionId});
  }

  Future<void> unrepostOpinion(String opinionId) async {
    await _supabase.rpc(
      'unrepost_opinion',
      params: {'p_opinion_id': opinionId},
    );
  }

  Future<bool> isOpinionReposted(String opinionId) async {
    final res = await _supabase.rpc(
      'is_opinion_reposted',
      params: {'p_opinion_id': opinionId},
    );
    return res as bool? ?? false;
  }

  // ============================================================
  // Hides and mutes — per-viewer feed filters, never visible to anyone else
  // (ATTUNE_MASTER_SPEC.md §8.11 "Muting and hiding"). Neither touches the
  // opinion's counts nor notifies the affected author.
  //
  // The filtering itself is server-side: get_discover_opinions and
  // get_following_opinions already exclude hidden/muted rows, so there is no
  // client-side predicate to keep in sync. Saved/Reposted deliberately do NOT
  // filter — content you chose to keep stays yours.
  // ============================================================

  /// Dismisses one opinion from the caller's own feeds. Idempotent server-side
  /// (ON CONFLICT DO NOTHING), so a double-tap races harmlessly.
  Future<void> hideOpinion(String opinionId) async {
    await _supabase.rpc('hide_opinion', params: {'p_opinion_id': opinionId});
  }

  Future<void> unhideOpinion(String opinionId) async {
    await _supabase.rpc('unhide_opinion', params: {'p_opinion_id': opinionId});
  }

  /// Mutes an author by their opaque handle — never a user_id, which the
  /// client does not have (FORUM.md §3). The feed RPCs resolve the handle back
  /// server-side, the same one-directional resolution follows already use.
  ///
  /// Idempotent server-side. Raises invalid_handle (22023) on an empty handle.
  Future<void> muteAuthor(String authorHandle) async {
    await _supabase.rpc(
      'mute_opinion_author',
      params: {'p_author_handle': authorHandle},
    );
  }

  Future<void> unmuteAuthor(String authorHandle) async {
    await _supabase.rpc(
      'unmute_opinion_author',
      params: {'p_author_handle': authorHandle},
    );
  }

  /// The caller's own muted handles, newest mute first.
  Future<List<MutedAuthor>> getMutedAuthors() async {
    final rows = await _supabase.rpc('get_muted_authors');
    return (rows as List)
        .map((r) => MutedAuthor.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ============================================================
  // Quotes — unlike a repost, a quote IS a full opinion (own text, own
  // counts, own feed placement) that additionally points at what it quotes
  // (ATTUNE_MASTER_SPEC.md §8.11 "Quotes").
  // ============================================================

  /// Posts a quote of [quotedOpinionId] and returns the NEW opinion's id.
  ///
  /// The RPC delegates the base insert to create_opinion, so the 5000-char
  /// limit, keyword filter, §7 rate limit/cooldown and ban gate all apply
  /// exactly as they do to a normal opinion — a quote is a post.
  ///
  /// Self-quote is allowed (unlike self-repost), and quoting something that is
  /// itself a quote is re-targeted server-side to the original underneath, so
  /// the caller can pass whatever opinion the user tapped Quote on without
  /// walking a chain.
  Future<String> createQuoteOpinion({
    required String content,
    required String quotedOpinionId,
    List<String>? tagSlugs,
  }) async {
    final res = await _supabase.rpc(
      'create_opinion_with_quote',
      params: {'p_content': content, 'p_quoted_opinion_id': quotedOpinionId},
    );
    final newId = res as String;
    // A quote is a full opinion, so it takes tags exactly like any other post
    // — attached as the same independent follow-up call, not a fourth
    // create_opinion_with_quote_and_tags combinator.
    await attachOpinionTags(newId, tagSlugs);
    return newId;
  }

  /// Resolves the embedded original for one quote, or null when it has since
  /// been removed or deleted.
  ///
  /// A vanished original is an expected steady state, not an error: the RPC
  /// returns ZERO rows rather than raising, and the caller renders "This
  /// opinion is no longer available" on null.
  Future<OpinionModel?> getQuotedOpinion(String opinionId) async {
    final rows = await _supabase.rpc(
      'get_quoted_opinion',
      params: {'p_opinion_id': opinionId},
    );
    final list = rows as List;
    if (list.isEmpty) return null;
    return OpinionModel.fromFeedRow(Map<String, dynamic>.from(list.first));
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

  /// Returns the new comment's id (the RPC's RETURNS uuid) so the caller can
  /// build the row locally instead of refetching the whole thread — see
  /// [postCommentLocally] in opinion_providers.dart for why.
  Future<String> createComment({
    required String opinionId,
    required String content,
    String? replyToCommentId,
    String? quotedText,
  }) async {
    final res = await _supabase.rpc(
      'create_opinion_comment',
      params: {
        'p_opinion_id': opinionId,
        'p_content': content,
        'p_reply_to_comment_id': replyToCommentId,
        'p_quoted_text': quotedText,
      },
    );
    return res as String;
  }

  /// Rewrites a comment's text within its 15-minute window. Same rejection
  /// shape as [editOpinion]: `not_editable` (42501) / `invalid_content`
  /// (22023).
  Future<void> editComment({
    required String commentId,
    required String content,
  }) async {
    await _supabase.rpc(
      'edit_opinion_comment',
      params: {'p_comment_id': commentId, 'p_content': content},
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

    await _supabase.rpc(
      'decrement_opinion_comment_count',
      params: {'p_opinion_id': comment['opinion_id']},
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
      params: {'p_comment_id': commentId},
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
      params: {'p_comment_id': commentId},
    );
  }

  // ============================================================
  // Reports — RPC records the report AND auto-hides at the §8 threshold (10).
  // ============================================================

  Future<void> reportOpinion({
    required String opinionId,
    String reason = 'Other',
  }) async {
    await _supabase.rpc(
      'report_opinion',
      params: {'p_opinion_id': opinionId, 'p_reason': reason},
    );
  }

  Future<void> reportComment({
    required String commentId,
    String reason = 'Other',
  }) async {
    await _supabase.rpc(
      'report_opinion_comment',
      params: {'p_comment_id': commentId, 'p_reason': reason},
    );
  }

  // ============================================================
  // Tags — a fixed, app-seeded vocabulary (ATTUNE_MASTER_SPEC.md §8.11
  // "Tags"). Never freeform: a user-invented tag is an author fingerprint,
  // so the client can only ever send slugs that already exist server-side,
  // and unknown slugs are silently dropped by the RPC rather than created.
  //
  // The join tables carry no grants to `authenticated` at all, so every read
  // and write below goes through a SECURITY DEFINER RPC — the same access
  // model as polls and saves/reposts.
  // ============================================================

  /// Attaches up to 3 tags to a just-created opinion. No-ops on null/empty so
  /// the creation paths can call it unconditionally.
  ///
  /// Throws PostgrestException on rejection:
  ///   - `too_many_tags` (22023) — more than 3 DISTINCT slugs. Repeats are
  ///     de-duplicated server-side rather than counted, so ['love','love'] is
  ///     one tag, not two.
  ///   - `not_owner` (42501) — not this opinion's author.
  /// Slugs outside the vocabulary are ignored, not rejected: an older backend
  /// meeting a newer app's tag degrades to fewer tags rather than failing a
  /// post that has already been created by this point.
  Future<void> attachOpinionTags(
    String opinionId,
    List<String>? tagSlugs,
  ) async {
    if (tagSlugs == null || tagSlugs.isEmpty) return;
    await _supabase.rpc(
      'attach_opinion_tags',
      params: {'p_opinion_id': opinionId, 'p_tag_slugs': tagSlugs},
    );
  }

  /// One opinion's tags. At most 3 rows, so no pagination.
  Future<List<String>> getOpinionTags(String opinionId) async {
    final rows = await _supabase.rpc(
      'get_opinion_tags',
      params: {'p_opinion_id': opinionId},
    );
    return (rows as List).map((r) => (r as Map)['slug'] as String).toList();
  }

  /// Tags for a whole feed page in ONE round trip, keyed by opinion id.
  ///
  /// This is why tags are not fetched per card: a page is 20-30 rows and a
  /// per-card lookup would be N+1. Opinions with no tags are simply absent
  /// from the map, so callers must treat a missing key as "untagged".
  Future<Map<String, List<String>>> getTagsForOpinions(
    List<String> opinionIds,
  ) async {
    if (opinionIds.isEmpty) return const {};
    final rows = await _supabase.rpc(
      'get_tags_for_opinions',
      params: {'p_opinion_ids': opinionIds},
    );
    final result = <String, List<String>>{};
    for (final row in (rows as List)) {
      final map = row as Map;
      final id = map['opinion_id'] as String;
      (result[id] ??= <String>[]).add(map['slug'] as String);
    }
    return result;
  }

  /// The opinions that quote [opinionId], newest first.
  ///
  /// A quote is a full opinion, so these come back in the standard feed shape
  /// and render as ordinary cards.
  Future<List<OpinionModel>> getQuotesOfOpinion(
    String opinionId, {
    required int page,
    required int pageSize,
  }) async {
    final rows = await _supabase.rpc(
      'get_quotes_of_opinion',
      params: {
        'p_opinion_id': opinionId,
        'p_limit': pageSize,
        'p_offset': page * pageSize,
      },
    );
    return (rows as List)
        .map((r) => OpinionModel.fromFeedRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Who reposted [opinionId], newest repost first.
  ///
  /// Each row is the ORIGINAL opinion carrying the reposter's handle — a
  /// repost has no content of its own, so there is nothing else to show. Same
  /// shape get_author_reposted_opinions uses on the profile screen.
  Future<List<OpinionModel>> getRepostersOfOpinion(
    String opinionId, {
    required int page,
    required int pageSize,
  }) async {
    final rows = await _supabase.rpc(
      'get_reposters_of_opinion',
      params: {
        'p_opinion_id': opinionId,
        'p_limit': pageSize,
        'p_offset': page * pageSize,
      },
    );
    return (rows as List)
        .map((r) => OpinionModel.fromFeedRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// How many times each opinion in a feed page has been quoted, keyed by
  /// opinion id.
  ///
  /// Batched for the same reason tags are: a page is 20-30 rows and a per-card
  /// lookup would be N+1. Opinions nobody has quoted are absent from the map,
  /// so callers must read a missing key as zero.
  ///
  /// Unlike like/repost/comment counts this is not carried on the feed row —
  /// adding a column to the feed RPCs' result shape would mean DROPping and
  /// recreating all eight of them (see 20260819120000_quote_counts.sql).
  Future<Map<String, int>> getQuoteCounts(List<String> opinionIds) async {
    if (opinionIds.isEmpty) return const {};
    final rows = await _supabase.rpc(
      'get_quote_counts',
      params: {'p_opinion_ids': opinionIds},
    );
    return {
      for (final row in (rows as List))
        (row as Map)['opinion_id'] as String: (row)['quote_count'] as int,
    };
  }

  /// The full fixed vocabulary, for the composer's chip picker and the tag
  /// browse surface. Static server-side, so callers cache it rather than
  /// refetching per keystroke.
  Future<List<String>> getAllTags() async {
    final rows = await _supabase.rpc('get_all_tags');
    return (rows as List).map((r) => (r as Map)['slug'] as String).toList();
  }

  /// Every opinion carrying [tagSlug], newest first, in the same anonymized
  /// row shape as the discover feed (so fromFeedRow parses it unchanged).
  ///
  /// Takes ONLY a tag — there is deliberately no author parameter here or in
  /// the RPC, and none may be added. "Everyone who used this tag" is safe;
  /// "this author's posts tagged X" would let a viewer narrow in on one
  /// person by topic, which is the exact deanonymization risk a fixed
  /// vocabulary exists to prevent (§8.11 "Tag browsing").
  ///
  /// Tags do not come back on these rows either — this is a feed like any
  /// other, so the caller merges them via [withTags] the same way.
  Future<List<OpinionModel>> getOpinionsByTag(
    String tagSlug, {
    required int page,
    required int pageSize,
  }) async {
    final rows = await _supabase.rpc(
      'get_opinions_by_tag',
      params: {
        'p_tag_slug': tagSlug,
        'p_limit': pageSize,
        'p_offset': page * pageSize,
      },
    );
    return (rows as List)
        .map((r) => OpinionModel.fromFeedRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Merges a batched tag lookup onto an already-parsed feed page.
  ///
  /// The feed RPCs do not join tags, so every parsed row starts with an empty
  /// list; this does the one batch call and patches each row via copyWith.
  /// Returns a new list — the input models are immutable and untouched.
  ///
  /// Deliberately tolerant of failure: a tag lookup that throws leaves the
  /// page rendering without chips rather than failing the whole feed load. A
  /// feed is the primary content and tags are decoration on it, so a tag
  /// outage must not turn Discover into an error screen.
  Future<List<OpinionModel>> withTags(List<OpinionModel> opinions) async {
    if (opinions.isEmpty) return opinions;
    try {
      final byId = await getTagsForOpinions([for (final o in opinions) o.id]);
      if (byId.isEmpty) return opinions;
      return [
        for (final o in opinions)
          byId.containsKey(o.id) ? o.copyWith(tags: byId[o.id]) : o,
      ];
    } catch (_) {
      return opinions;
    }
  }

  /// Merges a batched quote-count lookup onto an already-parsed feed page.
  ///
  /// Same shape and same failure posture as [withTags]: the feed RPCs do not
  /// carry quote_count, so every parsed row starts at 0 and this patches the
  /// ones that have quotes. A lookup that throws leaves the page rendering
  /// without quote numbers rather than failing the whole feed — the count is
  /// decoration on the card, not the content.
  Future<List<OpinionModel>> withQuoteCounts(
    List<OpinionModel> opinions,
  ) async {
    if (opinions.isEmpty) return opinions;
    try {
      final byId = await getQuoteCounts([for (final o in opinions) o.id]);
      if (byId.isEmpty) return opinions;
      return [
        for (final o in opinions)
          byId.containsKey(o.id) ? o.copyWith(quoteCount: byId[o.id]) : o,
      ];
    } catch (_) {
      return opinions;
    }
  }

  /// Both per-page side-data merges ([withTags] and [withQuoteCounts]) in one
  /// call, with the two lookups issued concurrently.
  ///
  /// Every feed provider wants both, and neither depends on the other, so
  /// running them in sequence would add a needless round trip to each page
  /// load. Each still fails independently: a tag outage cannot strip the quote
  /// counts, and vice versa.
  Future<List<OpinionModel>> withSideData(List<OpinionModel> opinions) async {
    if (opinions.isEmpty) return opinions;
    final ids = [for (final o in opinions) o.id];
    final results = await Future.wait([
      getTagsForOpinions(ids).catchError((_) => <String, List<String>>{}),
      getQuoteCounts(ids).catchError((_) => <String, int>{}),
    ]);
    final tagsById = results[0] as Map<String, List<String>>;
    final quotesById = results[1] as Map<String, int>;
    if (tagsById.isEmpty && quotesById.isEmpty) return opinions;
    return [
      for (final o in opinions)
        o.copyWith(
          tags: tagsById[o.id] ?? o.tags,
          quoteCount: quotesById[o.id] ?? o.quoteCount,
        ),
    ];
  }
}
