// lib/features/opinions/data/models/opinion_model.dart

/// How long after posting a contribution can still be edited
/// (ATTUNE_MASTER_SPEC.md §8.11 "Editing", FORUM.md §7). One window, one rule,
/// identical for opinions, comments and forum posts.
///
/// Client-side this only decides whether an Edit affordance is OFFERED —
/// enforcement is the `created_at > now() - interval '15 minutes'` check
/// inside edit_opinion / edit_opinion_comment / edit_forum_post, which still
/// runs regardless of what the UI showed. MUST be kept in step with that
/// interval: a longer value here just means offering edits that the server
/// then rejects.
const Duration kOpinionEditWindow = Duration(minutes: 15);

class OpinionModel {
  final String id;

  /// Opaque, stable per-author handle (server-side HMAC of the real user_id).
  /// The real user_id is NEVER sent to clients (FORUM.md §3). This handle lets us
  /// group an author's posts and drive Follow without knowing who they are.
  final String authorHandle;

  /// True when this post belongs to the current user (server-computed). Used for
  /// the Delete affordance and to suppress the Follow button / self-reactions.
  final bool isMine;

  final String content;
  final String? relationshipStatus;
  final int likeCount;
  final int dislikeCount;
  final int commentCount;
  final int followerCount;
  final String? userReaction; // 'like', 'dislike', or null

  /// True when the current user has bookmarked this opinion. Server-computed
  /// per viewer (LEFT JOIN opinion_saves in the feed RPCs). A save is private
  /// to the saver — the author is never told who saved their post.
  final bool isSaved;

  /// How many users have reposted this opinion. Public feed content (everyone
  /// who sees the opinion sees the same number), unlike [isSaved] which is
  /// per-viewer — mirrors likeCount/dislikeCount/commentCount.
  final int repostCount;

  /// True when the current user has reposted this opinion. Server-computed per
  /// viewer (LEFT JOIN opinion_reposts in the feed RPCs).
  final bool isRepostedByMe;

  /// How many opinions quote this one. Public, like repostCount.
  ///
  /// Unlike the other counts this does NOT arrive on the feed row: it is
  /// merged in afterwards by OpinionRepository.withQuoteCounts, one batched
  /// get_quote_counts call per page. Defaults to 0, which is also what a
  /// failed lookup leaves in place — the count is decoration on the card, so
  /// it degrades to "no number" rather than failing the feed.
  final int quoteCount;

  /// When non-null, this opinion is a *quote*: a full opinion of its own that
  /// also points at the opinion it quotes (ATTUNE_MASTER_SPEC.md §8.11
  /// "Quotes"). Set once at creation and never toggled, unlike [isSaved] /
  /// [isRepostedByMe] — so no optimistic patch path exists for it.
  ///
  /// The embedded original's content is NOT carried here: the feed RPCs return
  /// only this id, and the client resolves the original lazily per rendered
  /// card via get_quoted_opinion (a feed page can be 30 rows, and eagerly
  /// joining a column that is null on most of them is the wrong trade).
  final String? quotedOpinionId;

  /// Non-null once the author has edited this opinion inside its 15-minute
  /// window (ATTUNE_MASTER_SPEC.md §8.11 "Editing"). Drives the subtle
  /// "(edited)" marker beside the timestamp — the value itself is never
  /// rendered, and no edit history is exposed, so readers learn only that a
  /// change happened.
  ///
  /// Server-authoritative (the RPC sets it to now()); the optimistic patch in
  /// opinion_providers.dart writes a client-side DateTime.now() so the marker
  /// appears instantly without a refetch.
  final DateTime? editedAt;

  /// Up to 3 slugs from the app's fixed tag vocabulary (ATTUNE_MASTER_SPEC.md
  /// §8.11 "Tags"). Never freeform — every string here already existed in the
  /// `tags` table before any user posted, which is what keeps a tag from
  /// becoming an author fingerprint.
  ///
  /// NOT returned by the feed RPCs: tags arrive from a separate batched
  /// get_tags_for_opinions call and are merged onto an already-parsed page
  /// (see OpinionRepository.withTags). So a freshly parsed feed row carries an
  /// empty list until that merge runs — an empty list means "no tags known
  /// yet OR genuinely untagged", and both render the same (no chip row).
  ///
  /// Set once at creation and never editable, like [quotedOpinionId] — there
  /// is no retag RPC, so nothing flips this after the fact.
  final List<String> tags;

  final DateTime createdAt;

  OpinionModel({
    required this.id,
    required this.authorHandle,
    required this.isMine,
    required this.content,
    this.relationshipStatus,
    required this.likeCount,
    required this.dislikeCount,
    required this.commentCount,
    this.followerCount = 0,
    this.userReaction,
    this.isSaved = false,
    this.repostCount = 0,
    this.isRepostedByMe = false,
    this.quoteCount = 0,
    this.quotedOpinionId,
    this.editedAt,
    this.tags = const [],
    required this.createdAt,
  });

  /// Used by the optimistic bookmark/repost toggles in OpinionCard: flips the
  /// named field locally so the icon responds instantly, and lets the caller
  /// roll back to the previous value if the RPC fails.
  ///
  /// [content] and [editedAt] are overridable for the same reason but a
  /// different caller: the edit patch in opinion_providers.dart rewrites both
  /// together (new text + the marker) so an edited card updates in place
  /// rather than waiting on a refetch. Both still fall back to the current
  /// value, so a save/repost toggle can never blank an edit.
  /// [tags] is overridable for a third reason again: the batch tag fetch
  /// merges a page's tags onto rows that were already parsed without them
  /// (OpinionRepository.withTags). Like the others it falls back to the
  /// current value, so an optimistic save/repost toggle can never strip the
  /// chips off an already-merged card.
  OpinionModel copyWith({
    bool? isSaved,
    int? repostCount,
    bool? isRepostedByMe,
    int? quoteCount,
    String? content,
    DateTime? editedAt,
    int? commentCount,
    List<String>? tags,
  }) {
    return OpinionModel(
      id: id,
      authorHandle: authorHandle,
      isMine: isMine,
      content: content ?? this.content,
      relationshipStatus: relationshipStatus,
      likeCount: likeCount,
      dislikeCount: dislikeCount,
      commentCount: commentCount ?? this.commentCount,
      followerCount: followerCount,
      userReaction: userReaction,
      isSaved: isSaved ?? this.isSaved,
      repostCount: repostCount ?? this.repostCount,
      isRepostedByMe: isRepostedByMe ?? this.isRepostedByMe,
      // Overridable so withQuoteCounts can merge a page's counts onto rows
      // already parsed without them, and falls back to the current value for
      // the same reason as editedAt below: an optimistic save/repost toggle
      // must not reset an already-merged count back to zero.
      quoteCount: quoteCount ?? this.quoteCount,
      // Carried through unconditionally rather than being an overridable
      // parameter: a quote's target is immutable, so there is nothing for a
      // caller to flip — but dropping it here would silently un-quote a card
      // on every optimistic save/repost toggle.
      quotedOpinionId: quotedOpinionId,
      // Falls back to the current value rather than being dropped, same trap
      // as quotedOpinionId above: an optimistic save/repost patch on an
      // already-edited card must not silently clear its "(edited)" marker.
      editedAt: editedAt ?? this.editedAt,
      tags: tags ?? this.tags,
      createdAt: createdAt,
    );
  }

  factory OpinionModel.fromFeedRow(Map<String, dynamic> json) {
    return OpinionModel(
      id: json['id'] as String,
      authorHandle: json['author_handle'] as String? ?? '',
      isMine: json['is_mine'] as bool? ?? false,
      content: json['content'] as String? ?? '',
      relationshipStatus: json['relationship_status_at_post'] as String?,
      likeCount: json['like_count'] as int? ?? 0,
      dislikeCount: json['dislike_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? 0,
      followerCount: json['follower_count'] as int? ?? 0,
      userReaction: json['my_reaction'] as String?,
      // Defaults false rather than null-erroring: RPCs predating opinion_saves
      // omit the column entirely, and an un-joined row genuinely is unsaved.
      isSaved: json['is_saved'] as bool? ?? false,
      // Same defaulting rationale as is_saved: RPCs predating
      // opinion_reposts omit both columns, and an un-joined row genuinely has
      // no reposts and is not reposted by the viewer.
      repostCount: json['repost_count'] as int? ?? 0,
      isRepostedByMe: json['is_reposted_by_me'] as bool? ?? false,
      // No feed RPC returns this — it is merged in afterwards by
      // withQuoteCounts (see 20260819120000_quote_counts.sql for why it is a
      // separate batched call rather than a column). Parsed anyway so a row
      // that does carry it (a cached toJson round-trip) keeps its value.
      quoteCount: json['quote_count'] as int? ?? 0,
      // Null on the overwhelming majority of rows (most opinions are not
      // quotes), and absent entirely from RPCs predating opinion_quotes —
      // both mean the same thing here, so no defaulting is needed.
      quotedOpinionId: json['quoted_opinion_id'] as String?,
      // Null on every un-edited opinion (the overwhelming majority) and absent
      // entirely from RPCs predating the edit window — both mean "never
      // edited", so no defaulting is needed.
      editedAt:
          json['edited_at'] != null
              ? DateTime.parse(json['edited_at'] as String)
              : null,
      // Absent from EVERY feed RPC row (get_discover_opinions and friends do
      // not join tags — the batch get_tags_for_opinions call does, and its
      // result is merged in afterwards). Present only when this map came back
      // out of the cache, which round-trips the merged value via toFeedRow.
      tags:
          (json['tags'] as List?)?.map((t) => t as String).toList() ??
          const <String>[],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Mirrors [fromFeedRow]'s keys exactly so a cached payload round-trips
  /// through the same parser the live RPC path uses — no second mapping to
  /// drift out of sync when a field is added.
  Map<String, dynamic> toFeedRow() {
    return {
      'id': id,
      'author_handle': authorHandle,
      'is_mine': isMine,
      'content': content,
      'relationship_status_at_post': relationshipStatus,
      'like_count': likeCount,
      'dislike_count': dislikeCount,
      'comment_count': commentCount,
      'follower_count': followerCount,
      'my_reaction': userReaction,
      // MUST stay in lockstep with fromFeedRow's 'is_saved' read: a field
      // written by one and not the other silently loses its value on every
      // cache round-trip (see topic_model.dart's toCachedJson for the same
      // trap). The round-trip test in opinion_feed_cache_test.dart guards it.
      'is_saved': isSaved,
      // Same lockstep requirement as 'is_saved' above — both repost fields are
      // read back by fromFeedRow, so omitting either here would silently reset
      // it on every cache round-trip.
      'repost_count': repostCount,
      'is_reposted_by_me': isRepostedByMe,
      // Same lockstep requirement: merged in per page rather than returned by
      // the feed RPCs, so omitting it here would make a cached card come back
      // with no quote count until the next merge.
      'quote_count': quoteCount,
      // Same lockstep requirement as the fields above: omitted here, a cached
      // quote would come back out of the cache as a plain opinion and lose its
      // embedded original on every relaunch.
      'quoted_opinion_id': quotedOpinionId,
      // Same lockstep requirement as the fields above: omitted here, an edited
      // opinion would come back out of the cache with no "(edited)" marker on
      // every relaunch.
      'edited_at': editedAt?.toIso8601String(),
      // Same lockstep requirement as the fields above, and the ONLY reason a
      // cached card keeps its chips: tags are not in the feed RPC's own row,
      // so if this key were omitted a restored opinion would come back
      // untagged on every relaunch and stay that way until the next batch
      // tag fetch landed.
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
