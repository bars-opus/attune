// lib/features/healing/data/models/healing_journey.dart

import 'package:equatable/equatable.dart';

class HealingJourney extends Equatable {
  final String id;
  final String userId;
  final String? relationshipId;
  final DateTime breakupAt;
  final String breakupAtSource; // 'relationship' or 'user_reported'
  final String
  status; // 'active', 'paused', 'completed', 'eligible_for_dating_opt_in', 'archived'
  final int currentStage; // 1-5
  final Map<String, dynamic> reflectionAnswers;
  final DateTime? reflectionCompletedAt;
  final String
  postMortemStatus; // 'not_started', 'processing', 'completed', 'skipped', 'insufficient_evidence', 'failed'
  final String? postMortemObservation;
  final String? postMortemConfidence; // 'high', 'medium', 'low', 'none'
  final String? postMortemReflectionPrompt;
  final DateTime? postMortemCompletedAt;
  final DateTime? patternAwarenessCompletedAt;
  final String
  portraitStatus; // 'not_started', 'processing', 'completed', 'skipped', 'insufficient_evidence', 'failed'
  final String? portraitText;
  final String? portraitReflection;
  final String? portraitPrompt;
  final DateTime? portraitCompletedAt;
  final DateTime? readinessStageCompletedAt;
  final DateTime? completedAt;
  final DateTime? eligibleForDatingOptInAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const HealingJourney({
    required this.id,
    required this.userId,
    this.relationshipId,
    required this.breakupAt,
    required this.breakupAtSource,
    required this.status,
    required this.currentStage,
    required this.reflectionAnswers,
    this.reflectionCompletedAt,
    required this.postMortemStatus,
    this.postMortemObservation,
    this.postMortemConfidence,
    this.postMortemReflectionPrompt,
    this.postMortemCompletedAt,
    this.patternAwarenessCompletedAt,
    required this.portraitStatus,
    this.portraitText,
    this.portraitReflection,
    this.portraitPrompt,
    this.portraitCompletedAt,
    this.readinessStageCompletedAt,
    this.completedAt,
    this.eligibleForDatingOptInAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory HealingJourney.fromJson(Map<String, dynamic> json) {
    return HealingJourney(
      id: json['id'],
      userId: json['user_id'],
      relationshipId: json['relationship_id'],
      breakupAt: DateTime.parse(json['breakup_at']),
      breakupAtSource: json['breakup_at_source'],
      status: json['status'],
      currentStage: json['current_stage'] ?? 1,
      reflectionAnswers: json['reflection_answers'] ?? {},
      reflectionCompletedAt:
          json['reflection_completed_at'] != null
              ? DateTime.parse(json['reflection_completed_at'])
              : null,
      postMortemStatus: json['post_mortem_status'] ?? 'not_started',
      postMortemObservation: json['post_mortem_observation'],
      postMortemConfidence: json['post_mortem_confidence'],
      postMortemReflectionPrompt: json['post_mortem_reflection_prompt'],
      postMortemCompletedAt:
          json['post_mortem_completed_at'] != null
              ? DateTime.parse(json['post_mortem_completed_at'])
              : null,
      patternAwarenessCompletedAt:
          json['pattern_awareness_completed_at'] != null
              ? DateTime.parse(json['pattern_awareness_completed_at'])
              : null,
      portraitStatus: json['portrait_status'] ?? 'not_started',
      portraitText: json['portrait_text'],
      portraitReflection: json['portrait_reflection'],
      portraitPrompt: json['portrait_prompt'],
      portraitCompletedAt:
          json['portrait_completed_at'] != null
              ? DateTime.parse(json['portrait_completed_at'])
              : null,
      readinessStageCompletedAt:
          json['readiness_stage_completed_at'] != null
              ? DateTime.parse(json['readiness_stage_completed_at'])
              : null,
      completedAt:
          json['completed_at'] != null
              ? DateTime.parse(json['completed_at'])
              : null,
      eligibleForDatingOptInAt:
          json['eligible_for_dating_opt_in_at'] != null
              ? DateTime.parse(json['eligible_for_dating_opt_in_at'])
              : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isCompleted => status == 'completed';
  bool get isEligibleForDating => status == 'eligible_for_dating_opt_in';
  bool get isArchived => status == 'archived';

  bool get isReflectionComplete => reflectionCompletedAt != null;
  bool get isPostMortemComplete =>
      postMortemStatus == 'completed' || postMortemStatus == 'skipped';
  bool get isPatternAwarenessComplete => patternAwarenessCompletedAt != null;
  bool get isPortraitComplete =>
      portraitStatus == 'completed' || portraitStatus == 'skipped';
  bool get isReadinessComplete => readinessStageCompletedAt != null;

  bool get isFullyComplete =>
      isReflectionComplete &&
      isPostMortemComplete &&
      isPatternAwarenessComplete &&
      isPortraitComplete &&
      isReadinessComplete;

  int get nextStage {
    if (!isReflectionComplete) return 1;
    if (!isPostMortemComplete) return 2;
    if (!isPatternAwarenessComplete) return 3;
    if (!isPortraitComplete) return 4;
    if (!isReadinessComplete) return 5;
    return 5;
  }

  /// Minimum spacing between readiness attempts. A readiness score is a
  /// self-reflection check-in, not a test to grind — retaking it the same day
  /// measures mood, not readiness.
  static const Duration readinessRetakeCooldown = Duration(days: 7);

  /// Whether a new readiness attempt is allowed, given the last attempt's
  /// `submitted_at`. Pass null when no attempt has ever been submitted.
  ///
  /// Enforced client-side only: `submit_healing_readiness` deliberately accepts
  /// every attempt so a legitimate retake is never lost to clock skew, and no
  /// RPC checks the cooldown. This is a UX guardrail, not a security boundary —
  /// bypassing it costs nothing but an extra row.
  bool canRetakeReadinessAt(DateTime? lastAttemptAt, {DateTime? now}) {
    if (lastAttemptAt == null) return true;
    return retakeAvailableIn(lastAttemptAt, now: now) == Duration.zero;
  }

  /// Time remaining before another readiness attempt is allowed.
  /// [Duration.zero] means a retake is available now.
  Duration retakeAvailableIn(DateTime? lastAttemptAt, {DateTime? now}) {
    if (lastAttemptAt == null) return Duration.zero;
    final current = now ?? DateTime.now();
    final elapsed = current.difference(lastAttemptAt.toLocal());
    final remaining = readinessRetakeCooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    relationshipId,
    breakupAt,
    breakupAtSource,
    status,
    currentStage,
    postMortemStatus,
    portraitStatus,
    completedAt,
    eligibleForDatingOptInAt,
  ];
}
