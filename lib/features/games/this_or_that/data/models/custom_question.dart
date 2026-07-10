class CustomQuestion {
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
  final DateTime createdAt;

  const CustomQuestion({
    required this.id,
    required this.userId,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    this.emojiA,
    this.emojiB,
    required this.tone,
    this.isPrivate = false,
    this.timesUsed = 0,
    this.lastUsedAt,
    required this.createdAt,
  });

  factory CustomQuestion.fromJson(Map<String, dynamic> json) {
    return CustomQuestion(
      id: json['id'],
      userId: json['user_id'],
      questionText: json['question_text'],
      optionA: json['option_a'],
      optionB: json['option_b'],
      emojiA: json['emoji_a'],
      emojiB: json['emoji_b'],
      tone: json['tone'],
      isPrivate: json['is_private'] ?? false,
      timesUsed: json['times_used'] ?? 0,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
