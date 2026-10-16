// test/features/couple_map/couple_map_copy_test.dart
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 16, 12);

CoupleMapPresence _p({bool self = true, bool partner = true}) =>
    CoupleMapPresence.fromRows([
      if (self)
        {
          'who': 'self',
          'cell_lat': 5.565,
          'cell_lng': -0.208,
          'freshness': 'fresh',
        },
      if (self && partner)
        {
          'who': 'partner',
          'cell_lat': 51.505,
          'cell_lng': -0.121,
          'city': 'London',
          'freshness': 'fresh',
          'distance_km': 5100,
          'together': false,
        },
    ]);

void main() {
  group('the sharing chip (spec §3.1, verbatim)', () {
    String label(
      PresenceState s, {
      LocationAccess access = LocationAccess.granted,
    }) => sharingChipLabel(s, access: access, partnerName: 'Kofi', now: _now);

    test(
      'off',
      () => expect(label(const PresenceState(PresenceStatus.off)), 'Off'),
    );
    test(
      'sharing',
      () => expect(
        label(const PresenceState(PresenceStatus.sharing)),
        'Sharing my area with Kofi',
      ),
    );
    test('paused with an end shows what is left, rounded up', () {
      final s = PresenceState(
        PresenceStatus.paused,
        pausedUntil: _now.add(const Duration(minutes: 41, seconds: 10)),
      );
      expect(label(s), 'Paused · 42 min');
    });
    test(
      'paused until resumed',
      () => expect(label(const PresenceState(PresenceStatus.paused)), 'Paused'),
    );
    test('a pause whose end has passed reads plainly as paused', () {
      expect(
        label(
          PresenceState(
            PresenceStatus.paused,
            pausedUntil: _now.subtract(const Duration(minutes: 1)),
          ),
        ),
        'Paused',
      );
    });
    test('sharing with location off says so (my own device only)', () {
      expect(
        label(
          const PresenceState(PresenceStatus.sharing),
          access: LocationAccess.denied,
        ),
        'Location is off for Attune',
      );
      expect(
        label(
          const PresenceState(PresenceStatus.sharing),
          access: LocationAccess.serviceOff,
        ),
        'Location is off for Attune',
      );
    });
    test('paused stays paused even with location off', () {
      expect(
        label(
          const PresenceState(PresenceStatus.paused),
          access: LocationAccess.denied,
        ),
        'Paused',
      );
    });
  });

  test('pause remaining: minutes under an hour, then hours and minutes', () {
    expect(pauseRemainingLabel(const Duration(seconds: 20)), '1 min');
    expect(pauseRemainingLabel(const Duration(minutes: 59)), '59 min');
    expect(pauseRemainingLabel(const Duration(hours: 1)), '1 h');
    expect(
      pauseRemainingLabel(const Duration(hours: 7, minutes: 5)),
      '7 h 5 min',
    );
  });

  group('one notice for every reason (spec §3.4)', () {
    test('not sharing', () {
      final p = CoupleMapPresence.none;
      expect(
        coupleMapNotice(p, LocationAccess.granted),
        CoupleMapNotice.notSharing,
      );
      expect(
        noticeText(CoupleMapNotice.notSharing),
        'See how far apart you are — shares your neighbourhood, never your address',
      );
    });
    test('sharing, no partner row: one neutral line, never a reason', () {
      final n = coupleMapNotice(_p(partner: false), LocationAccess.granted);
      expect(n, CoupleMapNotice.justYou);
      expect(noticeText(n!), 'Just you on the map right now');
    });
    test('paused (partner hidden by symmetry): the same neutral line', () {
      final p = CoupleMapPresence.fromRows([
        {'who': 'self', 'freshness': 'fresh', 'my_paused_until': 'infinity'},
      ]);
      expect(
        coupleMapNotice(p, LocationAccess.granted),
        CoupleMapNotice.justYou,
      );
    });
    test('location off and no partner: turn it on', () {
      expect(
        coupleMapNotice(_p(partner: false), LocationAccess.denied),
        CoupleMapNotice.locationOff,
      );
      expect(
        noticeText(CoupleMapNotice.locationOff),
        'Turn on location for Attune to share your area',
      );
    });
    test('a partner on the map: no notice (the card shows)', () {
      expect(coupleMapNotice(_p(), LocationAccess.granted), isNull);
      expect(coupleMapNotice(_p(), LocationAccess.denied), isNull);
    });
    test('no copy anywhere mentions waiting, a reason, or a time', () {
      for (final n in CoupleMapNotice.values) {
        final t = noticeText(n).toLowerCase();
        for (final banned in [
          'waiting',
          'paused',
          'stopped',
          'ago',
          'last seen',
          'online',
        ]) {
          expect(t.contains(banned), isFalse, reason: '$n: $banned');
        }
      }
    });
  });

  group('the distance card (spec §3.1)', () {
    test(
      'far apart: the headline, then km · city · their time, joined by " · "',
      () {
        const d = PartnerDistance(
          km: 5100,
          partnerCity: 'London',
          partnerUtcOffsetMinutes: 60,
        );
        final c = distanceCardCopy(
          d,
          partnerName: 'Kofi',
          myUtcOffsetMinutes: 0,
          now: DateTime.utc(2026, 9, 2, 22, 15),
        );
        expect(c.headline, '11:15pm where they are');
        expect(c.details, '5.1k km apart · in London');
        expect(c.together, isFalse);
      },
    );
    test('a countdown keeps the time there when the zones differ', () {
      const d = PartnerDistance(
        km: 5100,
        partnerCity: 'London',
        partnerUtcOffsetMinutes: 60,
        daysUntilTogether: 12,
      );
      final c = distanceCardCopy(
        d,
        myUtcOffsetMinutes: 0,
        now: DateTime.utc(2026, 9, 2, 14, 15),
      );
      expect(c.headline, "12 days until you're together");
      expect(c.details, '5.1k km apart · in London · 3:15pm there');
    });
    test('the same zone: no "there" time', () {
      const d = PartnerDistance(
        km: 300,
        partnerCity: 'Kumasi',
        partnerUtcOffsetMinutes: 0,
      );
      final c = distanceCardCopy(d, myUtcOffsetMinutes: 0, now: _now);
      expect(c.headline, '6 hours by road');
      expect(c.details, '300 km apart · in Kumasi');
    });
    test('together: "Together · city", warm accent, no number', () {
      const d = PartnerDistance(km: 2, partnerCity: 'Accra', together: true);
      final c = distanceCardCopy(d, now: _now);
      expect(c.headline, 'Together · Accra');
      expect(c.details, isEmpty);
      expect(c.together, isTrue);
    });
    test('together with no city', () {
      expect(
        distanceCardCopy(
          const PartnerDistance(km: 1, together: true),
          now: _now,
        ).headline,
        'Together',
      );
    });
  });

  test('initials: up to two letters, uppercase; nothing gives "?"', () {
    expect(initialsOf('Ama Mensah'), 'AM');
    expect(initialsOf('kofi'), 'K');
    expect(initialsOf('  '), '?');
    expect(initialsOf(null), '?');
    expect(initialsOf('Ama Esi Mensah'), 'AE');
  });
}
