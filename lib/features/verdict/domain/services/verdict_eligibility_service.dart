// lib/features/verdict/domain/services/verdict_eligibility_service.dart

class VerdictEligibilityService {
  /// Check if a relationship is eligible for a Verdict
  static VerdictEligibility checkEligibility({
    required int pulseCount,
    required int sessionCount,
    required bool hasStrengthEvidence,
    required bool hasWatchAreaEvidence,
  }) {
    // Minimum 3 Pulse scores
    if (pulseCount < 3) {
      return VerdictEligibility.ineligible(
        reason: 'not_enough_pulse_data',
        message:
            'Not enough shared data yet. Keep using Attune at your own pace.',
      );
    }

    // Minimum 5 eligible sessions
    if (sessionCount < 5) {
      return VerdictEligibility.ineligible(
        reason: 'not_enough_sessions',
        message:
            'Not enough shared data yet. Keep using Attune at your own pace.',
      );
    }

    // Must have evidence for both strengths and watch areas
    if (!hasStrengthEvidence || !hasWatchAreaEvidence) {
      return VerdictEligibility.ineligible(
        reason: 'insufficient_evidence',
        message:
            'Not enough shared data yet. Keep using Attune at your own pace.',
      );
    }

    return VerdictEligibility.eligible();
  }

  /// Calculate data confidence based on pulse count
  static String calculateDataConfidence(int pulseCount) {
    if (pulseCount < 3) return 'none';
    if (pulseCount < 9) return 'low';
    if (pulseCount < 20) return 'medium';
    return 'high';
  }

  /// Generate confidence label
  static String generateConfidenceLabel(int pulseCount) {
    if (pulseCount < 3) return 'Not enough shared data yet';
    if (pulseCount < 9) return 'Based on early data';
    if (pulseCount < 20) return 'Based on $pulseCount weeks of data';
    return 'Based on $pulseCount weeks of comprehensive data';
  }

  /// Get the previous completed calendar month in UTC.
  static ({DateTime start, DateTime end}) getPreviousCompletedPeriodUtc([
    DateTime? now,
  ]) {
    final reference = (now ?? DateTime.now()).toUtc();
    final currentMonthStart = DateTime.utc(reference.year, reference.month, 1);
    final previousMonthStart = DateTime.utc(
      currentMonthStart.year,
      currentMonthStart.month - 1,
      1,
    );
    return (start: previousMonthStart, end: currentMonthStart);
  }

  /// Check if a verdict exists for a period
  static bool isSamePeriod(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month;
  }
}

class VerdictEligibility {
  final bool isEligible;
  final bool isIneligible;
  final String? reason;
  final String? message;

  const VerdictEligibility._({
    required this.isEligible,
    this.reason,
    this.message,
  }) : isIneligible = !isEligible;

  factory VerdictEligibility.eligible() {
    return const VerdictEligibility._(isEligible: true);
  }

  factory VerdictEligibility.ineligible({
    required String reason,
    required String message,
  }) {
    return VerdictEligibility._(
      isEligible: false,
      reason: reason,
      message: message,
    );
  }
}
