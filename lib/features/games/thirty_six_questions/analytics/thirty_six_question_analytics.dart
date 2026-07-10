class ThirtySixQuestionAnalytics {
  static const String _journeyStarted = 'thirty_six_journey_started';
  static const String _chapterStarted = 'thirty_six_chapter_started';
  static const String _chapterCompleted = 'thirty_six_chapter_completed';
  static const String _chapterInviteSent = 'thirty_six_chapter_invite_sent';
  static const String _chapterInviteAccepted =
      'thirty_six_chapter_invite_accepted';
  static const String _chapterInviteExpired =
      'thirty_six_chapter_invite_expired';
  static const String _chapterAbandoned = 'thirty_six_chapter_abandoned';
  static const String _questionSkipped = 'thirty_six_question_skipped';
  static const String _journeyCompleted = 'thirty_six_journey_completed';
  static const String _aiReflectionGenerated =
      'thirty_six_ai_reflection_generated';
  static const String _aiReflectionTimeout = 'thirty_six_ai_reflection_timeout';
  static const String _answerRemoved = 'thirty_six_answer_removed';
  static const String _answerSafetyTriggered =
      'thirty_six_answer_safety_triggered';

  static void journeyStarted({
    required String relationshipId,
    required String journeyId,
  }) {
    _capture(_journeyStarted, {
      'relationship_id': relationshipId,
      'journey_id': journeyId,
    });
  }

  static void chapterStarted({
    required String journeyId,
    required int chapter,
    required String sessionId,
  }) {
    _capture(_chapterStarted, {
      'journey_id': journeyId,
      'chapter': chapter,
      'session_id': sessionId,
    });
  }

  static void chapterCompleted({
    required String journeyId,
    required int chapter,
    required int durationSeconds,
    required String sessionId,
  }) {
    _capture(_chapterCompleted, {
      'journey_id': journeyId,
      'chapter': chapter,
      'duration_seconds': durationSeconds,
      'session_id': sessionId,
    });
  }

  static void chapterInviteSent({
    required String journeyId,
    required int chapter,
    required String inviterId,
    required String sessionId,
  }) {
    _capture(_chapterInviteSent, {
      'journey_id': journeyId,
      'chapter': chapter,
      'inviter_id': inviterId,
      'session_id': sessionId,
    });
  }

  static void chapterInviteAccepted({
    required String journeyId,
    required int chapter,
    required String sessionId,
  }) {
    _capture(_chapterInviteAccepted, {
      'journey_id': journeyId,
      'chapter': chapter,
      'session_id': sessionId,
    });
  }

  static void chapterInviteExpired({
    required String journeyId,
    required int chapter,
    required String sessionId,
  }) {
    _capture(_chapterInviteExpired, {
      'journey_id': journeyId,
      'chapter': chapter,
      'session_id': sessionId,
    });
  }

  static void chapterAbandoned({
    required String journeyId,
    required int chapter,
    required String reason,
    required String sessionId,
  }) {
    _capture(_chapterAbandoned, {
      'journey_id': journeyId,
      'chapter': chapter,
      'reason': reason,
      'session_id': sessionId,
    });
  }

  static void questionSkipped({
    required String journeyId,
    required int chapter,
    required String canonicalQuestionId,
    required String sessionId,
  }) {
    _capture(_questionSkipped, {
      'journey_id': journeyId,
      'chapter': chapter,
      'canonical_question_id': canonicalQuestionId,
      'session_id': sessionId,
    });
  }

  static void journeyCompleted({
    required String journeyId,
    required int totalDurationSeconds,
  }) {
    _capture(_journeyCompleted, {
      'journey_id': journeyId,
      'total_duration_seconds': totalDurationSeconds,
    });
  }

  static void aiReflectionGenerated({
    required String journeyId,
    required int? chapter,
    required String confidence,
    required String reflectionType, // 'chapter' or 'journey'
  }) {
    _capture(_aiReflectionGenerated, {
      'journey_id': journeyId,
      'chapter': chapter,
      'confidence': confidence,
      'reflection_type': reflectionType,
    });
  }

  static void aiReflectionTimeout({
    required String journeyId,
    required int? chapter,
    required String reflectionType,
  }) {
    _capture(_aiReflectionTimeout, {
      'journey_id': journeyId,
      'chapter': chapter,
      'reflection_type': reflectionType,
    });
  }

  static void answerRemoved({
    required String journeyId,
    required int chapter,
    required String canonicalQuestionId,
    required String answerId,
  }) {
    _capture(_answerRemoved, {
      'journey_id': journeyId,
      'chapter': chapter,
      'canonical_question_id': canonicalQuestionId,
      'answer_id': answerId,
    });
  }

  static void answerSafetyTriggered({
    required String journeyId,
    required int chapter,
    required String canonicalQuestionId,
    required String answerId,
  }) {
    _capture(_answerSafetyTriggered, {
      'journey_id': journeyId,
      'chapter': chapter,
      'canonical_question_id': canonicalQuestionId,
      'answer_id': answerId,
    });
  }

  static void _capture(String eventName, Map<String, Object?> properties) {
    // Analytics wiring is intentionally centralized here. The app currently has
    // no PostHog dependency, so this keeps call sites stable without adding a
    // new production dependency during the 36Q implementation pass.
  }
}
