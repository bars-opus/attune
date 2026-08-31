// lib/features/games/thirty_six_questions/data/models/thirty_six_question_journey.dart

import 'package:equatable/equatable.dart';

class ThirtySixQuestionJourney extends Equatable {
  final String id;
  final String relationshipId;
  final String status; // 'in_progress', 'completed', 'abandoned'
  final DateTime? chapter1CompletedAt;
  final DateTime? chapter2CompletedAt;
  final DateTime? chapter3CompletedAt;
  final String? finalObservation;
  final String? finalObservationConfidence; // 'high', 'medium', 'low'
  final List<String>? finalSourceAnswerIds;
  final bool finalObservationHidden;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ThirtySixQuestionJourney({
    required this.id,
    required this.relationshipId,
    required this.status,
    this.chapter1CompletedAt,
    this.chapter2CompletedAt,
    this.chapter3CompletedAt,
    this.finalObservation,
    this.finalObservationConfidence,
    this.finalSourceAnswerIds,
    this.finalObservationHidden = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ThirtySixQuestionJourney.fromJson(Map<String, dynamic> json) {
    return ThirtySixQuestionJourney(
      id: json['id'],
      relationshipId: json['relationship_id'],
      status: json['status'],
      chapter1CompletedAt:
          json['chapter_1_completed_at'] != null
              ? DateTime.parse(json['chapter_1_completed_at'])
              : null,
      chapter2CompletedAt:
          json['chapter_2_completed_at'] != null
              ? DateTime.parse(json['chapter_2_completed_at'])
              : null,
      chapter3CompletedAt:
          json['chapter_3_completed_at'] != null
              ? DateTime.parse(json['chapter_3_completed_at'])
              : null,
      finalObservation: json['final_observation'],
      finalObservationConfidence: json['final_observation_confidence'],
      finalSourceAnswerIds:
          json['final_source_answer_ids'] != null
              ? List<String>.from(json['final_source_answer_ids'])
              : null,
      finalObservationHidden: json['final_observation_hidden'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'relationship_id': relationshipId,
      'status': status,
      'chapter_1_completed_at': chapter1CompletedAt?.toIso8601String(),
      'chapter_2_completed_at': chapter2CompletedAt?.toIso8601String(),
      'chapter_3_completed_at': chapter3CompletedAt?.toIso8601String(),
      'final_observation': finalObservation,
      'final_observation_confidence': finalObservationConfidence,
      'final_source_answer_ids': finalSourceAnswerIds,
      'final_observation_hidden': finalObservationHidden,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isAbandoned => status == 'abandoned';

  int get completedChapters {
    int count = 0;
    if (chapter1CompletedAt != null) count++;
    if (chapter2CompletedAt != null) count++;
    if (chapter3CompletedAt != null) count++;
    return count;
  }

  /// The lowest chapter not yet completed, or 4 once all three are done.
  ///
  /// Sequences rather than counting: completedChapters + 1 returned 3 for a
  /// journey with 1 and 3 finished, offering a chapter already played
  /// instead of the missing 2. Chapters are strictly progressive
  /// (36_QUESTIONS.md §1), so the next one is the first gap — and the
  /// model should not need a screen to be correct about that.
  int get nextChapter {
    if (chapter1CompletedAt == null) return 1;
    if (chapter2CompletedAt == null) return 2;
    if (chapter3CompletedAt == null) return 3;
    return 4;
  }

  bool get isFullyCompleted => completedChapters >= 3;

  bool get hasFinalObservation =>
      finalObservation != null && finalObservation!.isNotEmpty;

  @override
  List<Object?> get props => [
    id,
    relationshipId,
    status,
    chapter1CompletedAt,
    chapter2CompletedAt,
    chapter3CompletedAt,
    finalObservation,
    finalObservationConfidence,
    finalSourceAnswerIds,
    finalObservationHidden,
    createdAt,
    updatedAt,
  ];
}
