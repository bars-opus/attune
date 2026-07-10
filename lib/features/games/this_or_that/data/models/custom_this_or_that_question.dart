// lib/features/games/this_or_that/data/models/custom_this_or_that_question.dart

class CustomThisOrThatQuestion {
  final String id;
  final String userId;
  final String questionText;
  final String optionA;
  final String optionB;
  final String? emojiA;
  final String? emojiB;
  final String tone;
  final bool isPrivate;
  final int timesUsed;
  final DateTime? lastUsedAt;
  final bool hiddenForReview;
  final bool sharedToCommunity;
  final int communityUsageCount;
  final DateTime createdAt;

  const CustomThisOrThatQuestion({
    required this.id,
    required this.userId,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    this.emojiA,
    this.emojiB,
    required this.tone,
    this.isPrivate = true,
    this.timesUsed = 0,
    this.lastUsedAt,
    this.hiddenForReview = false,
    this.sharedToCommunity = false,
    this.communityUsageCount = 0,
    required this.createdAt,
  });

  factory CustomThisOrThatQuestion.fromJson(Map<String, dynamic> json) {
    return CustomThisOrThatQuestion(
      id: json['id'],
      userId: json['user_id'],
      questionText: json['question_text'],
      optionA: json['option_a'],
      optionB: json['option_b'],
      emojiA: json['emoji_a'],
      emojiB: json['emoji_b'],
      tone: json['tone'],
      isPrivate: json['is_private'] ?? true,
      timesUsed: json['times_used'] ?? 0,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'])
          : null,
      hiddenForReview: json['hidden_for_review'] ?? false,
      sharedToCommunity: json['shared_to_community'] ?? false,
      communityUsageCount: json['community_usage_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'question_text': questionText,
      'option_a': optionA,
      'option_b': optionB,
      'emoji_a': emojiA,
      'emoji_b': emojiB,
      'tone': tone,
      'is_private': isPrivate,
      'times_used': timesUsed,
      'last_used_at': lastUsedAt?.toIso8601String(),
      'hidden_for_review': hiddenForReview,
      'shared_to_community': sharedToCommunity,
      'community_usage_count': communityUsageCount,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
