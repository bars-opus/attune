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
  /// The `public_forum_posts` VIEW that forumPostsProvider selects from
  /// projects `edited_at` as of
  /// 20260730140000_forum_post_edit_view_columns.sql, so this parses for real
  /// and the marker renders.
  final DateTime? editedAt;

  /// True when the querying user authored this post.
  ///
  /// Comes from the view's `(user_id = auth.uid()) AS is_mine` computed column
  /// — the same ownership-without-identity pattern every other read path in
  /// this feature uses. The real `user_id` is never projected to the client
  /// (FORUM.md §3) and must never be added to this model.
  ///
  /// Drives bubble alignment in the debate room: your posts right, everyone
  /// else's left, exactly like the 1:1 chat thread.
  final bool isMine;

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
    this.isMine = false,
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
      isMine: json['is_mine'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  @override
  String toString() {
    return 'ForumPostModel(id: $id, side: $side, content: $content, likeCount: $likeCount)';
  }
}
