// lib/features/games/thirty_six_questions/data/models/thirty_six_question_round.dart

import 'package:equatable/equatable.dart';

class ThirtySixQuestionRound extends Equatable {
  final String id;
  final String sessionId;
  final int roundNumber;
  final String canonicalQuestionId;
  final String questionTextSnapshot;
  final int? level;
  final String? answerA;
  final String? answerB;
  final DateTime? answerASubmittedAt;
  final DateTime? answerBSubmittedAt;
  final bool bothAnswered;
  final DateTime? revealedAt;
  final DateTime? revealTriggeredAt;

  const ThirtySixQuestionRound({
    required this.id,
    required this.sessionId,
    required this.roundNumber,
    required this.canonicalQuestionId,
    required this.questionTextSnapshot,
    this.level,
    this.answerA,
    this.answerB,
    this.answerASubmittedAt,
    this.answerBSubmittedAt,
    this.bothAnswered = false,
    this.revealedAt,
    this.revealTriggeredAt,
  });

  factory ThirtySixQuestionRound.fromJson(Map<String, dynamic> json) {
    return ThirtySixQuestionRound(
      id: json['id'],
      sessionId: json['session_id'],
      roundNumber: json['round_number'],
      canonicalQuestionId: json['canonical_question_id'],
      questionTextSnapshot: json['question_text_snapshot'] ?? '',
      level: json['level'],
      answerA: json['answer_a'],
      answerB: json['answer_b'],
      answerASubmittedAt:
          json['answer_a_submitted_at'] != null
              ? DateTime.parse(json['answer_a_submitted_at'])
              : null,
      answerBSubmittedAt:
          json['answer_b_submitted_at'] != null
              ? DateTime.parse(json['answer_b_submitted_at'])
              : null,
      bothAnswered: json['both_answered'] ?? false,
      revealedAt:
          json['revealed_at'] != null
              ? DateTime.parse(json['revealed_at'])
              : null,
      revealTriggeredAt:
          json['reveal_triggered_at'] != null
              ? DateTime.parse(json['reveal_triggered_at'])
              : null,
    );
  }

  bool get hasUserAAnswered => answerA != null && answerA!.isNotEmpty;
  bool get hasUserBAnswered => answerB != null && answerB!.isNotEmpty;

  @override
  List<Object?> get props => [
    id,
    sessionId,
    roundNumber,
    canonicalQuestionId,
    questionTextSnapshot,
    bothAnswered,
  ];
}
