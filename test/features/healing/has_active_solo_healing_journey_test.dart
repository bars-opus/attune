import 'package:attune/features/healing/data/repositories/healing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasActiveSoloJourneyFromResponse', () {
    test('returns true when a row is present', () {
      expect(hasActiveSoloJourneyFromResponse({'id': 'journey-1'}), isTrue);
    });

    test('returns false when no row is present', () {
      expect(hasActiveSoloJourneyFromResponse(null), isFalse);
    });
  });
}
