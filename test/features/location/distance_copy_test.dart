import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the row says', () {
    test(
      'within the country it speaks in hours by road, naming their city',
      () {
        final copy = distanceCopy(
          const PartnerDistance(km: 300, partnerCity: 'Kumasi'),
          partnerName: 'Kofi',
        );
        expect(copy.headline, '6 hours by road');
        expect(copy.detail, 'Kofi in Kumasi');
      },
    );

    test('far apart with no known time zone: the distance, then the city', () {
      final copy = distanceCopy(
        const PartnerDistance(km: 900, partnerCity: 'Lagos'),
      );
      expect(copy.headline, '900 km apart');
      expect(copy.detail, 'Lagos');
    });

    test('under a kilometre it stops counting', () {
      // GPS drift alone spans this. A number here would be both absurd and
      // a movement sensor -- it would twitch while someone sat still.
      expect(
        distanceCopy(const PartnerDistance(km: 0.4)).headline,
        'Practically together',
      );
    });

    test('across a city it speaks in minutes, not kilometres', () {
      final copy = distanceCopy(const PartnerDistance(km: 12));
      expect(copy.headline, contains('min'));
      expect(copy.headline, isNot(contains('km')));
    });

    test('a booked trip replaces the distance with a countdown', () {
      // The strongest thing this can say to a long-distance couple: the
      // distance is temporary, and here is when it ends.
      final copy = distanceCopy(
        const PartnerDistance(km: 5100, daysUntilTogether: 12),
      );

      expect(copy.headline, "12 days until you're together");
      expect(
        copy.detail,
        contains('apart'),
        reason: 'the distance is demoted, not hidden',
      );
    });

    test('far apart with nothing booked leads with their clock', () {
      final copy = distanceCopy(
        const PartnerDistance(km: 5100, partnerUtcOffsetMinutes: 60),
        now: DateTime.utc(2026, 9, 2, 22, 15),
      );
      expect(copy.headline, '11:15pm where they are');
      expect(copy.detail, '5.1k km apart');
    });

    test('a reunion booked turns a far distance into a countdown', () {
      const far = PartnerDistance(km: 3900, daysUntilTogether: 2);
      expect(far.tone, DistanceTone.countdown);
    });

    test(
      'there is no "travelling" tone: it would need yesterday\'s distance',
      () {
        // History is never kept (spec 2026-10-16 §4.3), so movement can't be news.
        expect(
          DistanceTone.values.map((t) => t.name),
          isNot(contains('closing')),
        );
      },
    );

    test('adjacent cells read as together, whatever the rounded number', () {
      const close = PartnerDistance(km: 5, together: true);
      expect(close.tone, DistanceTone.together);
    });
  });

  group('travel time', () {
    test('is coarse enough that it cannot be read as movement', () {
      // Two positions 400m apart must produce the SAME answer, or the row
      // reveals that someone moved.
      expect(
        travelTimeFor(11.8, TravelMode.drive),
        travelTimeFor(12.2, TravelMode.drive),
      );
    });

    test('flying includes the airport, not just the air', () {
      // "1 hour by air" for a flight you spend a day reaching is a worse
      // answer than a rounder, truer one.
      final time = travelTimeFor(800, TravelMode.fly);
      expect(time.inHours, greaterThanOrEqualTo(4));
    });

    test('mode follows the distance', () {
      expect(travelModeFor(1), TravelMode.walk);
      expect(travelModeFor(30), TravelMode.drive);
      expect(travelModeFor(5000), TravelMode.fly);
    });
  });
}
