// lib/features/opinions/data/models/comment_model.dart

class CommentModel {
  final String id;

  /// Opaque per-author handle (see [OpinionModel.authorHandle]). Real user_id is
  /// never sent to clients (FORUM.md §3).
  final String authorHandle;

  /// True when this comment belongs to the current user (server-computed).
  final bool isMine;

  final String content;
  final String? relationshipStatus;
  final String? quotedText;
  final String? replyToCommentId;
  final int likeCount;
  final bool likedByMe;

  /// Non-null once the author has edited this comment inside its 15-minute
  /// window (ATTUNE_MASTER_SPEC.md §8.11 "Editing"). Drives the "(edited)"
  /// marker beside the timestamp; no edit history is exposed.
  ///
  /// Unlike OpinionModel there is no cache round-trip to keep in lockstep —
  /// comments are fetched fresh per thread (commentsProvider) and never
  /// persisted, so this single parse site is the only place it flows through.
  final DateTime? editedAt;

  final DateTime createdAt;

  CommentModel({
    required this.id,
    required this.authorHandle,
    required this.isMine,
    required this.content,
    this.relationshipStatus,
    this.quotedText,
    this.replyToCommentId,
    required this.likeCount,
    this.likedByMe = false,
    this.editedAt,
    required this.createdAt,
  });

  /// Used by the local patches in opinion_providers.dart (edit/like/unlike) so
  /// a mutation on your own comment updates the thread in place instead of
  /// refetching it — see [postCommentLocally] for the full rationale.
  CommentModel copyWith({
    String? content,
    int? likeCount,
    bool? likedByMe,
    DateTime? editedAt,
  }) {
    return CommentModel(
      id: id,
      authorHandle: authorHandle,
      isMine: isMine,
      content: content ?? this.content,
      relationshipStatus: relationshipStatus,
      quotedText: quotedText,
      replyToCommentId: replyToCommentId,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      editedAt: editedAt ?? this.editedAt,
      createdAt: createdAt,
    );
  }

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] as String,
      authorHandle: json['author_handle'] as String? ?? '',
      isMine: json['is_mine'] as bool? ?? false,
      content: json['content'] as String? ?? '',
      relationshipStatus: json['relationship_status_at_post'] as String?,
      quotedText: json['quoted_text'] as String?,
      replyToCommentId: json['reply_to_comment_id'] as String?,
      likeCount: json['like_count'] as int? ?? 0,
      likedByMe: json['liked_by_me'] as bool? ?? false,
      // Null on every un-edited comment, and absent entirely from RPCs
      // predating the edit window — both mean "never edited".
      editedAt:
          json['edited_at'] != null
              ? DateTime.parse(json['edited_at'] as String)
              : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
