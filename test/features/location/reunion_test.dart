import 'package:attune/features/location/domain/reunion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what counts as a reunion', () {
    test('plain travel-to-each-other reads as one', () {
      for (final title in [
        'Ada visits',
        'Flight to Accra',
        'Trip to see you',
        'She arrives Friday',
        'Coming home',
        'Together at last',
      ]) {
        expect(
          isReunionEvent(title),
          isTrue,
          reason: '"$title" should start a countdown',
        );
      }
    });

    test('a work trip is time APART and must not count down', () {
      // The inversion that matters: "work trip" contains "trip", and
      // counting down to it would tell a couple they are about to be
      // together when one of them is leaving.
      for (final title in [
        'Work trip to Lagos',
        'Business trip',
        'Conference in Nairobi',
        'Leaving for Kumasi',
        'Away next week',
      ]) {
        expect(
          isReunionEvent(title),
          isFalse,
          reason: '"$title" is time apart, not a reunion',
        );
      }
    });

    test('ordinary events stay silent', () {
      // "12 days until you're together" above a dentist appointment is
      // worse than showing no countdown at all, so anything ambiguous
      // shows nothing.
      for (final title in [
        'Dentist',
        'Rent due',
        'Mum birthday',
        'Pay the electricity',
      ]) {
        expect(isReunionEvent(title), isFalse, reason: '"$title"');
      }
    });

    test('matching ignores case', () {
      expect(isReunionEvent('FLIGHT TO LONDON'), isTrue);
      expect(isReunionEvent('WORK TRIP'), isFalse);
    });
  });

  group('counting the days', () {
    test('counts by date, not by elapsed hours', () {
      // An event at 9am tomorrow is "tomorrow" whether you check at
      // midnight or at 8am. Hour arithmetic would call it "today" for
      // part of the night -- wrong, and briefly cruel.
      final event = DateTime(2026, 9, 3, 9);

      expect(daysUntil(event, now: DateTime(2026, 9, 2, 0, 30)), 1);
      expect(daysUntil(event, now: DateTime(2026, 9, 2, 23, 30)), 1);
    });

    test('today is zero', () {
      expect(
        daysUntil(DateTime(2026, 9, 2, 18), now: DateTime(2026, 9, 2, 9)),
        0,
      );
    });

    test('past events are negative, so callers can skip them', () {
      expect(
        daysUntil(DateTime(2026, 9, 1), now: DateTime(2026, 9, 2)),
        lessThan(0),
      );
    });
  });
}
