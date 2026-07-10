// lib/features/games/preset_questions/models/this_or_that_preset_question.dart

class ThisOrThatPresetQuestion {
  final String id;
  final String questionText;
  final String optionA;
  final String optionB;
  final String? emojiA;
  final String? emojiB;
  final String tone;
  final int toneLevel;
  final bool isInteresting;

  const ThisOrThatPresetQuestion({
    required this.id,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    this.emojiA,
    this.emojiB,
    required this.tone,
    required this.toneLevel,
    this.isInteresting = false,
  });

  factory ThisOrThatPresetQuestion.fromJson(Map<String, dynamic> json) {
    return ThisOrThatPresetQuestion(
      id: json['id'],
      questionText: json['question_text'],
      optionA: json['option_a'],
      optionB: json['option_b'],
      emojiA: json['emoji_a'],
      emojiB: json['emoji_b'],
      tone: json['tone'],
      toneLevel: json['tone_level'] ?? 1,
      isInteresting: json['is_interesting'] ?? false,
    );
  }
}
