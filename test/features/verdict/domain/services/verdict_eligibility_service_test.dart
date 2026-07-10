import 'package:attune/features/verdict/domain/services/verdict_eligibility_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VerdictEligibilityService', () {
    test('requires at least 3 pulse scores', () {
      final result = VerdictEligibilityService.checkEligibility(
        pulseCount: 2,
        sessionCount: 8,
        hasStrengthEvidence: true,
        hasWatchAreaEvidence: true,
      );

      expect(result.isEligible, false);
      expect(result.reason, 'not_enough_pulse_data');
    });

    test('requires at least 5 eligible sessions', () {
      final result = VerdictEligibilityService.checkEligibility(
        pulseCount: 4,
        sessionCount: 4,
        hasStrengthEvidence: true,
        hasWatchAreaEvidence: true,
      );

      expect(result.isEligible, false);
      expect(result.reason, 'not_enough_sessions');
    });

    test('requires both strength and watch evidence', () {
      final result = VerdictEligibilityService.checkEligibility(
        pulseCount: 4,
        sessionCount: 6,
        hasStrengthEvidence: true,
        hasWatchAreaEvidence: false,
      );

      expect(result.isEligible, false);
      expect(result.reason, 'insufficient_evidence');
    });

    test('returns eligible when all gates pass', () {
      final result = VerdictEligibilityService.checkEligibility(
        pulseCount: 5,
        sessionCount: 6,
        hasStrengthEvidence: true,
        hasWatchAreaEvidence: true,
      );

      expect(result.isEligible, true);
      expect(result.reason, isNull);
    });

    test('data confidence follows locked thresholds', () {
      expect(VerdictEligibilityService.calculateDataConfidence(2), 'none');
      expect(VerdictEligibilityService.calculateDataConfidence(3), 'low');
      expect(VerdictEligibilityService.calculateDataConfidence(9), 'medium');
      expect(VerdictEligibilityService.calculateDataConfidence(20), 'high');
    });

    test('computes previous completed month in UTC', () {
      final period = VerdictEligibilityService.getPreviousCompletedPeriodUtc(
        DateTime.utc(2026, 7, 3, 12),
      );

      expect(period.start, DateTime.utc(2026, 6, 1));
      expect(period.end, DateTime.utc(2026, 7, 1));
    });
  });
}
