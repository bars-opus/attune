// lib/features/forums/data/models/forum_post_model.dart

class ForumPostModel {
  final String id;
  final String topicId;
  final String side; // 'for' or 'against'
  final String content;
  final String? relationshipStatus;
  final String? replyToPostId;
  final String? quotedText;
  final int likeCount;
  final bool userLiked;

  /// Non-null once the author has edited this post inside its 15-minute window
  /// (FORUM.md §7 "Editing"). Drives the "(edited)" marker; no history shown.
  ///
  /// NOTE: as of this change the `public_forum_posts` VIEW that
  /// forumPostsProvider selects from does NOT project `edited_at` (nor any
  /// ownership column), so this parses as null in practice and the marker
  /// never renders. Parsing it here anyway means the SQL follow-up that adds
  /// the column to that view needs no further Dart change.
  final DateTime? editedAt;

  final DateTime createdAt;

  ForumPostModel({
    required this.id,
    required this.topicId,
    required this.side,
    required this.content,
    this.relationshipStatus,
    this.replyToPostId,
    this.quotedText,
    required this.likeCount,
    required this.userLiked,
    this.editedAt,
    required this.createdAt,
  });

  factory ForumPostModel.fromJson(
    Map<String, dynamic> json, [
    bool userLiked = false,
  ]) {
    return ForumPostModel(
      id: json['id'],
      topicId: json['topic_id'],
      side: json['side'],
      content: json['content'],
      relationshipStatus: json['relationship_status_at_post'],
      replyToPostId: json['reply_to_post_id'],
      quotedText: json['quoted_text'],
      likeCount: json['like_count'] ?? 0,
      userLiked: userLiked,
      editedAt:
          json['edited_at'] != null
              ? DateTime.parse(json['edited_at'] as String)
              : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  @override
  String toString() {
    return 'ForumPostModel(id: $id, side: $side, content: $content, likeCount: $likeCount)';
  }
}
