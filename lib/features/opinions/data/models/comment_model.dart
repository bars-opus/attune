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
    required this.createdAt,
  });

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
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
