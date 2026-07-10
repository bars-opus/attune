// lib/features/games/thirty_six_questions/data/models/thirty_six_question_answer.dart

import 'package:equatable/equatable.dart';

class ThirtySixQuestionAnswer extends Equatable {
  final String id;
  final String roundId;
  final String userId;
  final String? answerText;
  final bool isRemoved;
  final bool isSafetyTriggered;
  final bool isExcludedFromAi;
  final DateTime submittedAt;
  final DateTime? removedAt;

  const ThirtySixQuestionAnswer({
    required this.id,
    required this.roundId,
    required this.userId,
    this.answerText,
    this.isRemoved = false,
    this.isSafetyTriggered = false,
    this.isExcludedFromAi = false,
    required this.submittedAt,
    this.removedAt,
  });

  factory ThirtySixQuestionAnswer.fromJson(Map<String, dynamic> json) {
    return ThirtySixQuestionAnswer(
      id: json['id'],
      roundId: json['round_id'],
      userId: json['user_id'],
      answerText: json['answer_text'],
      isRemoved: json['is_removed'] ?? false,
      isSafetyTriggered: json['is_safety_triggered'] ?? false,
      isExcludedFromAi: json['is_excluded_from_ai'] ?? false,
      submittedAt: DateTime.parse(json['submitted_at']),
      removedAt:
          json['removed_at'] != null
              ? DateTime.parse(json['removed_at'])
              : null,
    );
  }

  bool get hasAnswer => answerText != null && answerText!.isNotEmpty;

  bool get isUsableForAi =>
      hasAnswer && !isRemoved && !isSafetyTriggered && !isExcludedFromAi;

  @override
  List<Object?> get props => [
    id,
    roundId,
    userId,
    answerText,
    isRemoved,
    isSafetyTriggered,
    isExcludedFromAi,
    submittedAt,
    removedAt,
  ];
}
