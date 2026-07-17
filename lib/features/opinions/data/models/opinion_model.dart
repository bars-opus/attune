// lib/features/opinions/data/models/opinion_model.dart

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
    required this.createdAt,
  });

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
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
