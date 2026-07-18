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
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  @override
  String toString() {
    return 'ForumPostModel(id: $id, side: $side, content: $content, likeCount: $likeCount)';
  }
}
