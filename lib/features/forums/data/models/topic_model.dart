// lib/features/forums/data/models/topic_model.dart

class TopicModel {
  final String id;
  final String content;
  final String? submitterStatus;
  final String status;
  final int upvoteCount;
  final int downvoteCount;
  final int seenCount;
  final int totalPosts;
  final int forPosts;
  final int againstPosts;
  final DateTime? lastPostAt;
  final DateTime? activatedAt;
  final DateTime votingExpiresAt;
  final DateTime createdAt;
  final String? userVote;      // 'up', 'down', or null (from topic_votes)
  final String? userSide;      // 'FOR', 'AGAINST', or null (from user_forum_sides or derived from vote)

  TopicModel({
    required this.id,
    required this.content,
    this.submitterStatus,
    required this.status,
    required this.upvoteCount,
    required this.downvoteCount,
    required this.seenCount,
    required this.totalPosts,
    required this.forPosts,
    required this.againstPosts,
    this.lastPostAt,
    this.activatedAt,
    required this.votingExpiresAt,
    required this.createdAt,
    this.userVote,
    this.userSide,
  });

  factory TopicModel.fromJson(
    Map<String, dynamic> json, {
    String? userVote,
    String? userSide,
  }) {
    return TopicModel(
      id: json['id'],
      content: json['content'],
      submitterStatus: json['relationship_status_at_submit'],
      status: json['status'],
      upvoteCount: json['upvote_count'] ?? 0,
      downvoteCount: json['downvote_count'] ?? 0,
      seenCount: json['seen_count'] ?? 0,
      totalPosts: json['total_posts'] ?? 0,
      forPosts: json['for_posts'] ?? 0,
      againstPosts: json['against_posts'] ?? 0,
      lastPostAt: json['last_post_at'] != null ? DateTime.parse(json['last_post_at']) : null,
      activatedAt: json['activated_at'] != null ? DateTime.parse(json['activated_at']) : null,
      votingExpiresAt: DateTime.parse(json['voting_expires_at']),
      createdAt: DateTime.parse(json['created_at']),
      userVote: userVote,
      userSide: userSide,
    );
  }

  // Helper to get display side from vote or stored side
  String? get displaySide {
    if (userSide != null) return userSide;
    if (userVote == 'up') return 'FOR';
    if (userVote == 'down') return 'AGAINST';
    return null;
  }
}
