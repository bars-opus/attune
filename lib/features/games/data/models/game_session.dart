// lib/features/games/data/models/game_session.dart

import 'package:equatable/equatable.dart';

class GameSession extends Equatable {
  final String id;
  final String relationshipId;
  final String initiatorId;
  final String gameType; // 'this_or_that', 'truth_or_dare', '36_questions'
  final String tone;
  final String status; // 'invited', 'active', 'completed', 'abandoned'
  final int totalRounds;
  final int currentRound;
  final int? skipsUsedA;
  final int? skipsUsedB;
  final bool intimateConsentA;
  final bool intimateConsentB;
  final int? matchCount;
  final int? totalRoundsCompleted;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? abandonedAt;
  final DateTime createdAt;
  final List<String>? hiddenByUserIds;

  const GameSession({
    required this.id,
    required this.relationshipId,
    required this.initiatorId,
    required this.gameType,
    required this.tone,
    required this.status,
    required this.totalRounds,
    required this.currentRound,
    this.skipsUsedA,
    this.skipsUsedB,
    required this.intimateConsentA,
    required this.intimateConsentB,
    this.matchCount,
    this.totalRoundsCompleted,
    this.startedAt,
    this.completedAt,
    this.abandonedAt,
    required this.createdAt,
    this.hiddenByUserIds,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id'],
      relationshipId: json['relationship_id'],
      initiatorId: json['initiator_id'],
      gameType: json['game_type'],
      tone: json['tone'],
      status: json['status'],
      totalRounds: json['total_rounds'],
      currentRound: json['current_round'] ?? 0,
      skipsUsedA: json['skips_used_a'],
      skipsUsedB: json['skips_used_b'],
      intimateConsentA: json['intimate_consent_a'] ?? false,
      intimateConsentB: json['intimate_consent_b'] ?? false,
      matchCount: json['match_count'],
      totalRoundsCompleted: json['total_rounds_completed'],
      startedAt: json['started_at'] != null ? DateTime.parse(json['started_at']) : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      abandonedAt: json['abandoned_at'] != null ? DateTime.parse(json['abandoned_at']) : null,
      createdAt: DateTime.parse(json['created_at']),
      hiddenByUserIds: json['hidden_by_user_ids'] != null
          ? List<String>.from(json['hidden_by_user_ids'])
          : null,
    );
  }

  bool get isActive => status == 'active';
  bool get isInvited => status == 'invited';
  bool get isCompleted => status == 'completed';
  bool get isAbandoned => status == 'abandoned';

  bool get isComplete => currentRound >= totalRounds;

  int get answeredCount {
    // This will be populated from rounds
    return 0;
  }

  @override
  List<Object?> get props => [
        id,
        relationshipId,
        initiatorId,
        gameType,
        tone,
        status,
        totalRounds,
        currentRound,
        intimateConsentA,
        intimateConsentB,
        createdAt,
      ];
}

// lib/features/games/data/models/game_round.dart

class GameRound extends Equatable {
  final String id;
  final String sessionId;
  final int roundNumber;
  final String questionId;
  final int? level;
  final String? activePartnerId;
  final String? answerA;
  final String? answerB;
  final DateTime? answerASubmittedAt;
  final DateTime? answerBSubmittedAt;
  final String? chosenType;
  final bool bothAnswered;
  final DateTime? revealedAt;
  final DateTime? revealTriggeredAt;

  const GameRound({
    required this.id,
    required this.sessionId,
    required this.roundNumber,
    required this.questionId,
    this.level,
    this.activePartnerId,
    this.answerA,
    this.answerB,
    this.answerASubmittedAt,
    this.answerBSubmittedAt,
    this.chosenType,
    required this.bothAnswered,
    this.revealedAt,
    this.revealTriggeredAt,
  });

  factory GameRound.fromJson(Map<String, dynamic> json) {
    return GameRound(
      id: json['id'],
      sessionId: json['session_id'],
      roundNumber: json['round_number'],
      questionId: json['question_id'],
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
      chosenType: json['chosen_type'],
      bothAnswered: json['both_answered'] ?? false,
      revealedAt: json['revealed_at'] != null
          ? DateTime.parse(json['revealed_at'])
          : null,
      revealTriggeredAt: json['reveal_triggered_at'] != null
          ? DateTime.parse(json['reveal_triggered_at'])
          : null,
    );
  }

  bool get hasUserAnsweredA => answerA != null && answerA!.isNotEmpty;
  bool get hasUserAnsweredB => answerB != null && answerB!.isNotEmpty;

  @override
  List<Object?> get props => [
        id,
        sessionId,
        roundNumber,
        questionId,
        bothAnswered,
      ];
}
