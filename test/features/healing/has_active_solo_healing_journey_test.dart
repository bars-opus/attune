import 'package:attune/features/healing/data/repositories/healing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealingRepository.hasActiveSoloJourney', () {
    test('returns false when unauthenticated', () async {
      final repository =
          _FakeHealingRepository(hasActiveSoloJourneyValue: false);

      expect(await repository.hasActiveSoloJourney(), isFalse);
    });

    test('returns true when an active solo journey exists', () async {
      final repository =
          _FakeHealingRepository(hasActiveSoloJourneyValue: true);

      expect(await repository.hasActiveSoloJourney(), isTrue);
    });

    test('returns false when only a completed/archived solo journey exists',
        () async {
      final repository =
          _FakeHealingRepository(hasActiveSoloJourneyValue: false);

      expect(await repository.hasActiveSoloJourney(), isFalse);
    });
  });
}

/// Fake HealingRepository for testing.
class _FakeHealingRepository implements HealingRepository {
  _FakeHealingRepository({required this.hasActiveSoloJourneyValue});

  final bool hasActiveSoloJourneyValue;

  @override
  Future<bool> hasActiveSoloJourney() async => hasActiveSoloJourneyValue;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no method should be called');
}
