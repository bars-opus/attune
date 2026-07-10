import 'package:attune/features/safety/domain/services/safety_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = <String, dynamic>{
    'tiers': {
      'explicit_threat': {
        'tier': 1,
        'minimum_occurrences': 1,
        'rules': [
          {'id': 'explicit_threat_001', 'pattern': 'kill you'},
        ],
      },
      'isolation_control': {
        'tier': 2,
        'minimum_occurrences': 1,
        'rules': [
          {'id': 'isolation_001', 'pattern': "you don't need them"},
        ],
      },
      'pattern_control': {
        'tier': 3,
        'minimum_occurrences': 3,
        'rules': [
          {'id': 'pattern_control_001', 'pattern': 'if you leave'},
        ],
      },
    },
  };

  group('SafetyDetector.detect', () {
    test('matches normalized token phrases', () {
      final result = SafetyDetector.detect("  You DON’T   need them  ", config);

      expect(result.hasMatch, isTrue);
      expect(result.tier, 2);
      expect(result.ruleIds, ['isolation_001']);
    });

    test('does not match substrings inside larger words', () {
      final result = SafetyDetector.detect(
        'skill yourself before you leave',
        config,
      );

      expect(result.hasMatch, isFalse);
    });

    test('prefers tier 1 over lower-priority higher-numbered tiers', () {
      final result = SafetyDetector.detect(
        'if you leave I will kill you',
        config,
      );

      expect(result.hasMatch, isTrue);
      expect(result.tier, 1);
      expect(result.ruleIds, ['explicit_threat_001']);
    });

    test('returns no match for empty content', () {
      final result = SafetyDetector.detect('   ', config);

      expect(result.hasMatch, isFalse);
      expect(result.ruleIds, isEmpty);
    });
  });
}
