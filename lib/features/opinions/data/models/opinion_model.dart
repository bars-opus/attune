// lib/features/opinions/data/models/opinion_model.dart

class OpinionModel {
  final String id;
  final String userId;
  final String content;
  final String? relationshipStatus;
  final int likeCount;
  final int dislikeCount;
  final int commentCount;
  final String? userReaction; // 'like', 'dislike', or null
  final DateTime createdAt;

  OpinionModel({
    required this.id,
    required this.userId,
    required this.content,
    this.relationshipStatus,
    required this.likeCount,
    required this.dislikeCount,
    required this.commentCount,
    this.userReaction,
    required this.createdAt,
  });
}
