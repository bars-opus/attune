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

  /// Distinct people who picked each side (user_forum_sides), NOT a count of
  /// posts — forPosts/againstPosts count posts, and one person can post many
  /// times, so those two pairs diverge as soon as anyone posts more than
  /// once. ForumCardSubDetails' "For"/"Against" numbers use this pair.
  final int forPeople;
  final int againstPeople;
  final DateTime? lastPostAt;
  final DateTime? activatedAt;
  final DateTime votingExpiresAt;
  final DateTime createdAt;
  final String? userVote; // 'up', 'down', or null (from topic_votes)
  final String?
  userSide; // 'FOR', 'AGAINST', or null (from user_forum_sides or derived from vote)

  /// Up to 3 slugs from the app's fixed tag vocabulary (FORUM.md §7 "Tags").
  /// Like the opinion side, these are NOT a column on public_forum_topics or
  /// on any topic RPC — they arrive from a separate batched
  /// get_tags_for_forum_topics call and are merged onto already-parsed rows
  /// (see ForumRepository.withTags), so a freshly parsed topic carries an
  /// empty list until that merge runs.
  final List<String> tags;

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
    this.forPeople = 0,
    this.againstPeople = 0,
    this.lastPostAt,
    this.activatedAt,
    required this.votingExpiresAt,
    required this.createdAt,
    this.userVote,
    this.userSide,
    this.tags = const [],
  });

  /// Only [tags] is overridable, and only for the batch tag merge: everything
  /// else on a topic either comes straight from the row or is passed as a
  /// named arg by the caller that already has it. Every other field is
  /// carried through unchanged so a merge cannot quietly drop the viewer's
  /// own vote/side, which do NOT come from the row.
  TopicModel copyWith({List<String>? tags}) {
    return TopicModel(
      id: id,
      content: content,
      submitterStatus: submitterStatus,
      status: status,
      upvoteCount: upvoteCount,
      downvoteCount: downvoteCount,
      seenCount: seenCount,
      totalPosts: totalPosts,
      forPosts: forPosts,
      againstPosts: againstPosts,
      forPeople: forPeople,
      againstPeople: againstPeople,
      lastPostAt: lastPostAt,
      activatedAt: activatedAt,
      votingExpiresAt: votingExpiresAt,
      createdAt: createdAt,
      userVote: userVote,
      userSide: userSide,
      tags: tags ?? this.tags,
    );
  }

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
      forPeople: json['for_people'] ?? 0,
      againstPeople: json['against_people'] ?? 0,
      lastPostAt:
          json['last_post_at'] != null
              ? DateTime.parse(json['last_post_at'])
              : null,
      activatedAt:
          json['activated_at'] != null
              ? DateTime.parse(json['activated_at'])
              : null,
      votingExpiresAt: DateTime.parse(json['voting_expires_at']),
      createdAt: DateTime.parse(json['created_at']),
      userVote: userVote,
      userSide: userSide,
      // Never a column on the live topic rows — merged in afterwards by the
      // batch tag fetch. Present only on a cached payload, which round-trips
      // the merged value via toCachedJson.
      tags:
          (json['tags'] as List?)?.map((t) => t as String).toList() ??
          const <String>[],
    );
  }

  /// Round-trips through [fromCachedJson]. Note this writes `user_vote` and
  /// `user_side` into the map, which [fromJson] deliberately does NOT read —
  /// those arrive as named args on the live path, so a cached payload has to
  /// carry them itself or a restored topic silently loses the viewer's own
  /// vote and side.
  Map<String, dynamic> toCachedJson() {
    return {
      'id': id,
      'content': content,
      'relationship_status_at_submit': submitterStatus,
      'status': status,
      'upvote_count': upvoteCount,
      'downvote_count': downvoteCount,
      'seen_count': seenCount,
      'total_posts': totalPosts,
      'for_posts': forPosts,
      'against_posts': againstPosts,
      'for_people': forPeople,
      'against_people': againstPeople,
      'last_post_at': lastPostAt?.toIso8601String(),
      'activated_at': activatedAt?.toIso8601String(),
      'voting_expires_at': votingExpiresAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'user_vote': userVote,
      'user_side': userSide,
      // Read back by fromJson, so it must be written here — same trap as
      // user_vote/user_side above: omitted, a cached topic loses its chips on
      // every relaunch until the next batch tag fetch.
      'tags': tags,
    };
  }

  /// Inverse of [toCachedJson] — reuses [fromJson] for the shared columns and
  /// lifts the viewer-specific fields back out of the payload.
  factory TopicModel.fromCachedJson(Map<String, dynamic> json) {
    return TopicModel.fromJson(
      json,
      userVote: json['user_vote'] as String?,
      userSide: json['user_side'] as String?,
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
