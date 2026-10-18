// Spec 3a (R3-8): Healing can start from an ended relationship and, after
// its 30-day window closes, from an archived one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('getStartableRelationship accepts ended and archived', () {
    final src =
        File(
          'lib/features/healing/data/repositories/healing_repository.dart',
        ).readAsStringSync();
    final body = src.substring(
      src.indexOf('getStartableRelationship'),
      src.indexOf('hasActiveSoloJourney'),
    );
    expect(body, contains(".inFilter('status', ['ended', 'archived'])"));
    expect(body, isNot(contains(".eq('status', 'ended')")));
  });
}
