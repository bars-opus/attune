// lib/features/games/truth_or_dare/data/models/custom_truth_or_dare_question.dart

import 'dart:convert';

class CustomTruthOrDareQuestion {
  final String id;
  final String userId;
  final String questionType; // 'truth' or 'dare'
  final String content;
  final String tone;
  final bool isPrivate;
  final int timesUsed;
  final DateTime? lastUsedAt;
  final bool hiddenForReview;
  final bool sharedToCommunity;
  final int communityUsageCount;
  final DateTime createdAt;

  const CustomTruthOrDareQuestion({
    required this.id,
    required this.userId,
    required this.questionType,
    required this.content,
    required this.tone,
    this.isPrivate = true,
    this.timesUsed = 0,
    this.lastUsedAt,
    this.hiddenForReview = false,
    this.sharedToCommunity = false,
    this.communityUsageCount = 0,
    required this.createdAt,
  });

  factory CustomTruthOrDareQuestion.fromJson(Map<String, dynamic> json) {
    return CustomTruthOrDareQuestion(
      id: json['id'],
      userId: json['user_id'],
      questionType: json['question_type'],
      content: json['content'],
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
}

// lib/features/games/truth_or_dare/data/models/truth_or_dare_round.dart

class TruthOrDareRound {
  final String id;
  final String sessionId;
  final int roundNumber;
  final String questionId;
  final String questionType; // 'truth' or 'dare'
  final String questionText;
  final bool isCustom;
  final String? customQuestionId;
  final String? customQuestionType;
  final String? customContent;
  final int? level;
  final String? activePartnerId;
  final String? answerA;
  final String? answerB;
  final DateTime? answerASubmittedAt;
  final DateTime? answerBSubmittedAt;
  final bool bothAnswered;
  final DateTime? revealedAt;
  final DateTime? revealTriggeredAt;
  final bool isSkip;
  final String? skipReplacedType;
  final bool safetyTriggered;
  final Map<String, dynamic>? customQuestionData;

  const TruthOrDareRound({
    required this.id,
    required this.sessionId,
    required this.roundNumber,
    required this.questionId,
    required this.questionType,
    required this.questionText,
    this.isCustom = false,
    this.customQuestionId,
    this.customQuestionType,
    this.customContent,
    this.level,
    this.activePartnerId,
    this.answerA,
    this.answerB,
    this.answerASubmittedAt,
    this.answerBSubmittedAt,
    this.bothAnswered = false,
    this.revealedAt,
    this.revealTriggeredAt,
    this.isSkip = false,
    this.skipReplacedType,
    this.safetyTriggered = false,
    this.customQuestionData,
  });

  factory TruthOrDareRound.fromJson(Map<String, dynamic> json, {String? questionText}) {
    Map<String, dynamic>? customData;
    final rawCustomData = json['custom_question_data'];
    if (rawCustomData is Map<String, dynamic>) {
      customData = rawCustomData;
    } else if (rawCustomData is String && rawCustomData.isNotEmpty) {
      final decoded = jsonDecode(rawCustomData);
      if (decoded is Map<String, dynamic>) {
        customData = decoded;
      }
    }

    return TruthOrDareRound(
      id: json['id'],
      sessionId: json['session_id'],
      roundNumber: json['round_number'],
      questionId: json['question_id'],
      questionType: json['chosen_type'] ?? 'truth',
      questionText:
          questionText ??
          customData?['content'] as String? ??
          customData?['question_text'] as String? ??
          '',
      isCustom: json['is_custom'] ?? false,
      customQuestionId: json['custom_question_id'],
      customQuestionType: json['custom_question_type'],
      customContent: customData?['content'] as String?,
      level: json['level'],
      activePartnerId: json['active_partner_id'],
      answerA: json['answer_a'],
      answerB: json['answer_b'],
      answerASubmittedAt: json['answer_a_submitted_at'] != null
          ? DateTime.parse(json['answer_a_submitted_at'])
          : null,
      answerBSubmittedAt: json['answer_b_submitted_at'] != null
          ? DateTime.parse(json['answer_b_submitted_at'])
          : null,
      bothAnswered: json['both_answered'] ?? false,
      revealedAt: json['revealed_at'] != null
          ? DateTime.parse(json['revealed_at'])
          : null,
      revealTriggeredAt: json['reveal_triggered_at'] != null
          ? DateTime.parse(json['reveal_triggered_at'])
          : null,
      isSkip: json['is_skip'] ?? false,
      skipReplacedType: json['skip_replaced_type'],
      safetyTriggered: json['safety_triggered'] ?? false,
      customQuestionData: customData,
    );
  }
}
