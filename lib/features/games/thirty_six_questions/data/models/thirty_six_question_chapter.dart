// lib/features/games/thirty_six_questions/data/models/thirty_six_question_chapter.dart

import 'package:equatable/equatable.dart';

class ThirtySixQuestionChapter extends Equatable {
  final String sessionId;
  final String journeyId;
  final int chapterNumber; // 1, 2, or 3
  final String status; // 'invited', 'active', 'completed', 'abandoned'
  final String?
  abandonReason; // 'inactivity', 'invite_expired', 'user_initiated'
  final int skipsUsed;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? abandonedAt;
  final DateTime createdAt;

  const ThirtySixQuestionChapter({
    required this.sessionId,
    required this.journeyId,
    required this.chapterNumber,
    required this.status,
    this.abandonReason,
    this.skipsUsed = 0,
    this.startedAt,
    this.completedAt,
    this.abandonedAt,
    required this.createdAt,
  });

  factory ThirtySixQuestionChapter.fromJson(Map<String, dynamic> json) {
    return ThirtySixQuestionChapter(
      sessionId: json['id'],
      journeyId: json['journey_id'],
      chapterNumber: json['chapter'],
      status: json['status'],
      abandonReason: json['abandon_reason'],
      skipsUsed: json['skips_used'] ?? 0,
      startedAt:
          json['started_at'] != null
              ? DateTime.parse(json['started_at'])
              : null,
      completedAt:
          json['completed_at'] != null
              ? DateTime.parse(json['completed_at'])
              : null,
      abandonedAt:
          json['abandoned_at'] != null
              ? DateTime.parse(json['abandoned_at'])
              : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  bool get isInvited => status == 'invited';
  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isAbandoned => status == 'abandoned';

  bool get hasSkipsRemaining => skipsUsed < 2;

  @override
  List<Object?> get props => [
    sessionId,
    journeyId,
    chapterNumber,
    status,
    abandonReason,
    skipsUsed,
    startedAt,
    completedAt,
    abandonedAt,
    createdAt,
  ];
}
