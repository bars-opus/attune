// lib/features/games/this_or_that/data/models/game_round.dart

import 'dart:convert';

class GameRound {
  final String id;
  final String sessionId;
  final int roundNumber;
  final String questionId;
  final String? answerA;
  final String? answerB;
  final DateTime? answerASubmittedAt;
  final DateTime? answerBSubmittedAt;
  final bool bothAnswered;
  final DateTime? revealTriggeredAt;
  final bool isCustom;
  final Map<String, dynamic>? customQuestionData;
  final String? questionText;
  final String? optionA;
  final String? optionB;
  final String? emojiA;
  final String? emojiB;
  final bool isInteresting;

  GameRound({
    required this.id,
    required this.sessionId,
    required this.roundNumber,
    required this.questionId,
    this.answerA,
    this.answerB,
    this.answerASubmittedAt,
    this.answerBSubmittedAt,
    required this.bothAnswered,
    this.revealTriggeredAt,
    this.isCustom = false,
    this.customQuestionData,
    this.questionText,
    this.optionA,
    this.optionB,
    this.emojiA,
    this.emojiB,
    this.isInteresting = false,
  });

  factory GameRound.fromJson(Map<String, dynamic> json) {
    final customQuestionData = _parseCustomQuestionData(
      json['custom_question_data'],
    );
    final questionData = _parseQuestionData(json['game_questions']);

    return GameRound(
      id: json['id'],
      sessionId: json['session_id'],
      roundNumber: json['round_number'],
      questionId: json['question_id'],
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
      revealTriggeredAt:
          json['reveal_triggered_at'] != null
              ? DateTime.parse(json['reveal_triggered_at'])
              : null,
      isCustom: json['is_custom'] ?? false,
      customQuestionData: customQuestionData,
      questionText:
          customQuestionData?['question_text'] as String? ??
          questionData?['question_text'] as String?,
      optionA:
          customQuestionData?['option_a'] as String? ??
          questionData?['option_a'] as String?,
      optionB:
          customQuestionData?['option_b'] as String? ??
          questionData?['option_b'] as String?,
      emojiA:
          customQuestionData?['emoji_a'] as String? ??
          questionData?['emoji_a'] as String?,
      emojiB:
          customQuestionData?['emoji_b'] as String? ??
          questionData?['emoji_b'] as String?,
      isInteresting:
          customQuestionData?['is_interesting'] as bool? ??
          questionData?['is_interesting'] as bool? ??
          false,
    );
  }

  bool get hasUserAAnswered => answerA != null && answerA!.isNotEmpty;
  bool get hasUserBAnswered => answerB != null && answerB!.isNotEmpty;
  String get displayQuestionText => questionText ?? 'Question unavailable';
  String? get answerAText => _choiceToText(answerA);
  String? get answerBText => _choiceToText(answerB);

  String? _choiceToText(String? answer) {
    switch (answer) {
      case 'a':
        return optionA;
      case 'b':
        return optionB;
      default:
        return answer;
    }
  }

  static Map<String, dynamic>? _parseCustomQuestionData(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  static Map<String, dynamic>? _parseQuestionData(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }
}
