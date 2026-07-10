// lib/features/opinions/data/models/comment_model.dart

class CommentModel {
  final String id;
  final String userId;
  final String content;
  final String? relationshipStatus;
  final String? quotedText;
  final String? replyToCommentId;
  final int likeCount;
  final int dislikeCount;
  final DateTime createdAt;

  CommentModel({
    required this.id,
    required this.userId,
    required this.content,
    this.relationshipStatus,
    this.quotedText,
    this.replyToCommentId,
    required this.likeCount,
    required this.dislikeCount,
    required this.createdAt,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'],
      userId: json['user_id'],
      content: json['content'],
      relationshipStatus: json['relationship_status_at_post'],
      quotedText: json['quoted_text'],
      replyToCommentId: json['reply_to_comment_id'],
      likeCount: json['like_count'] ?? 0,
      dislikeCount: json['dislike_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
