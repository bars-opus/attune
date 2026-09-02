import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the row says', () {
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
      // The hardest case. Leading with 5,100 km restates the ache every
      // day; their local time changes and answers "can I call?".
      final copy = distanceCopy(
        PartnerDistance(
          km: 5100,
          partnerLocalTime: DateTime(2026, 9, 2, 23, 15),
        ),
      );

      expect(copy.headline, '11:15pm where they are');
      expect(copy.detail, '5.1k km apart');
    });

    test('travel is news, so it leads', () {
      final copy = distanceCopy(
        const PartnerDistance(km: 3900, kmClosedSinceYesterday: 1200),
      );

      expect(copy.headline, '1.2k km closer than yesterday');
    });

    test('travelling away is reported as honestly as travelling toward', () {
      final copy = distanceCopy(
        const PartnerDistance(km: 5100, kmClosedSinceYesterday: -1200),
      );

      expect(copy.headline, contains('further'));
    });

    test('a countdown outranks a plain distance but not live travel', () {
      // Both a trip and movement: the movement is happening NOW, so it
      // wins. A countdown that ignored someone already en route would be
      // the less useful of two true things.
      const travelling = PartnerDistance(
        km: 3900,
        daysUntilTogether: 2,
        kmClosedSinceYesterday: 1200,
      );

      expect(travelling.tone, DistanceTone.closing);
    });

    test('ordinary movement is not called out as travel', () {
      // A commute must never surface as news. Otherwise the row becomes
      // exactly the movement sensor the coarse distance exists to prevent.
      const commuted = PartnerDistance(km: 5100, kmClosedSinceYesterday: 30);

      expect(commuted.tone, isNot(DistanceTone.closing));
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
