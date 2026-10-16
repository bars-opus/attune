// test/features/couple_map/widget/couple_widget_payload_test.dart
import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 16, 12);

CoupleMapPresence presence({
  int? km = 5100,
  bool together = false,
  PresenceFreshness self = PresenceFreshness.fresh,
  PresenceFreshness partner = PresenceFreshness.fresh,
  PresenceStatus status = PresenceStatus.sharing,
  int? offset = 60,
}) => CoupleMapPresence(
  self: PresenceArea(
    cellLat: 5.565,
    cellLng: -0.208,
    city: 'Accra',
    country: 'Ghana',
    utcOffsetMinutes: 0,
    freshness: self,
  ),
  partner: PresenceArea(
    cellLat: 51.505,
    cellLng: -0.125,
    city: 'London',
    country: 'United Kingdom',
    utcOffsetMinutes: offset,
    freshness: partner,
  ),
  distanceKm: km,
  together: together,
  state: PresenceState(status),
);

CoupleWidgetBuild build(
  CoupleMapPresence p, {
  List<(String, DateTime)> events = const [],
  String? kept,
}) => buildCoupleWidget(
  presence: p,
  events: events,
  now: now,
  keptReunionDate: kept,
);

void main() {
  group('buildCoupleWidget', () {
    test('both fresh, far apart: clock headline, km caption, 3 h, map', () {
      final b = build(presence());
      expect(b.payload.headlineIsClock, isTrue);
      expect(b.payload.caption, '5.1k km apart');
      expect(b.payload.clockOffsetMinutes, 60);
      expect(
        b.payload.validUntilMs,
        now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
      );
      expect(b.hasMap, isTrue);
      expect(b.mapSelf, (lat: 5.565, lng: -0.208));
      expect(b.mapPartner, (lat: 51.505, lng: -0.125));
    });

    for (final (who, p) in [
      ('my area', presence(self: PresenceFreshness.fading)),
      ('their area', presence(partner: PresenceFreshness.fading)),
    ]) {
      test('$who fading: no distance part, no map (spec §4.2)', () {
        final b = build(p);
        expect(b.payload.hasDistance, isFalse);
        expect(b.payload.caption, isNull);
        expect(b.hasMap, isFalse);
      });
    }

    test('paused or off writes no distance', () {
      expect(
        build(presence(status: PresenceStatus.paused)).payload.hasDistance,
        isFalse,
      );
      expect(build(CoupleMapPresence.none).payload.hasDistance, isFalse);
    });

    test('partner without a distance writes nothing (Review Focus 2)', () {
      final b = build(presence(km: null), kept: '2026-10-20');
      expect(b.payload.hasDistance, isFalse);
      expect(b.payload.reunionDate, '2026-10-20');
    });

    test('together: one warm line, no number, no clock, no map', () {
      final b = build(presence(km: 2, together: true));
      expect(b.payload.headline, 'Practically together');
      expect(b.payload.caption, isNull);
      expect(b.payload.clockOffsetMinutes, isNull);
      expect(b.hasMap, isFalse);
    });

    test('nearby: the app\'s own headline, no caption, no map', () {
      final b = build(presence(km: 12));
      expect(
        b.payload.headline,
        distanceCopy(const PartnerDistance(km: 12)).headline,
      );
      expect(b.payload.caption, isNull);
      expect(b.hasMap, isFalse);
    });

    test('same country: road headline, km caption, map from 100 km', () {
      final mine = now.timeZoneOffset.inMinutes;
      final far = build(presence(km: 400, offset: mine + 60));
      expect(
        far.payload.headline,
        distanceCopy(const PartnerDistance(km: 400)).headline,
      );
      expect(far.payload.caption, '400 km apart');
      expect(far.payload.clockLine, isTrue);
      expect(far.hasMap, isTrue);
      final sameZone = build(presence(km: 400, offset: mine));
      expect(sameZone.payload.clockLine, isFalse);
      expect(sameZone.payload.clockOffsetMinutes, isNull);
      expect(build(presence(km: 60)).hasMap, isFalse);
    });

    test('countdown: reunion date from withReunion, km caption', () {
      final b = build(
        presence(),
        events: [('Flight to see you', DateTime(2026, 10, 28, 9))],
      );
      expect(b.payload.reunionDate, '2026-10-28');
      expect(b.payload.caption, '5.1k km apart');
      expect(b.payload.clockLine, isTrue);
      expect(b.hasMap, isTrue);
    });

    test('no reunion under 800 km, even with a trip (withReunion gate)', () {
      final b = build(
        presence(km: 400),
        events: [('Trip to Lisbon', DateTime(2026, 10, 28))],
      );
      expect(b.payload.reunionDate, isNull);
    });

    test('distant without an offset leads with the km (Review Focus 3)', () {
      final b = build(presence(offset: null));
      expect(b.payload.headline, '5.1k km apart');
      expect(b.payload.headlineIsClock, isFalse);
      expect(b.payload.clockOffsetMinutes, isNull);
    });

    test('a kept reunion survives until its day, then goes', () {
      expect(
        build(CoupleMapPresence.none, kept: '2026-10-20').payload.reunionDate,
        '2026-10-20',
      );
      expect(
        build(CoupleMapPresence.none, kept: '2026-10-10').payload.reunionDate,
        isNull,
      );
    });

    test('validity runs from the read, not from a later re-publish', () {
      final b = buildCoupleWidget(
        presence: presence(),
        events: const [],
        now: now,
        readAt: now.subtract(const Duration(hours: 2)),
      );
      expect(
        b.payload.validUntilMs,
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
    });

    test('a fresh distance replaces the kept reunion with its own', () {
      final b = build(presence(km: 2, together: true), kept: '2026-10-20');
      expect(b.payload.reunionDate, isNull, reason: 'together: no countdown');
    });

    test('no coordinate, city, name or id ever reaches the JSON (§4.4)', () {
      final json =
          build(
            presence(),
            events: [('Flight to see you', DateTime(2026, 10, 28))],
          ).payload.encode();
      for (final banned in [
        'Accra',
        'London',
        'Ghana',
        'United Kingdom',
        '5.565',
        '-0.208',
        '51.505',
        '-0.125',
        'cell',
        'lat',
        'lng',
      ]) {
        expect(json.contains(banned), isFalse, reason: banned);
      }
    });
  });

  group('payload JSON and expiry', () {
    test('round-trips', () {
      final p = build(presence()).payload;
      expect(CoupleWidgetPayload.decode(p.encode()), p);
    });

    test('malformed or unknown version decodes to empty', () {
      expect(CoupleWidgetPayload.decode('{'), CoupleWidgetPayload.empty);
      expect(
        CoupleWidgetPayload.decode('{"v":2,"headline":"x"}'),
        CoupleWidgetPayload.empty,
      );
      expect(CoupleWidgetPayload.decode(null), CoupleWidgetPayload.empty);
    });

    test(
      'current() drops the distance at validUntil, the reunion after its day',
      () {
        final p = CoupleWidgetPayload(
          caption: '5.1k km apart',
          validUntilMs: now.millisecondsSinceEpoch,
          reunionDate: '2026-10-16',
        );
        final c = p.current(now);
        expect(c.hasDistance, isFalse);
        expect(c.caption, isNull);
        expect(c.reunionDate, '2026-10-16', reason: 'today still counts');
        expect(p.current(DateTime(2026, 10, 17)).reunionDate, isNull);
      },
    );
  });

  group('resolveCoupleWidget', () {
    test('distant: the live clock leads', () {
      final v = resolveCoupleWidget(build(presence()).payload, now);
      final there = formatClock(now.toUtc().add(const Duration(minutes: 60)));
      expect(v.headline, '$there there');
      expect(v.caption, '5.1k km apart');
      expect(v.clockLine, isNull);
    });

    test(
      'countdown with distance: 12 days, Together tomorrow, Together today',
      () {
        for (final (date, headline) in [
          ('2026-10-28', "12 days until you're together"),
          ('2026-10-17', 'Together tomorrow'),
          ('2026-10-16', 'Together today'),
        ]) {
          final p = CoupleWidgetPayload(
            caption: '5.1k km apart',
            clockOffsetMinutes: 60,
            clockLine: true,
            validUntilMs:
                now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
            reunionDate: date,
          );
          final v = resolveCoupleWidget(p, now);
          expect(v.headline, headline);
          expect(v.clockLine, endsWith(' there'));
        }
      },
    );

    test('expired distance falls back to the countdown alone', () {
      final p = CoupleWidgetPayload(
        caption: '5.1k km apart',
        validUntilMs:
            now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
        reunionDate: '2026-10-28',
      );
      final v = resolveCoupleWidget(p, now);
      expect(v.headline, '12 days');
      expect(v.caption, "until you're together");
    });

    test('nothing left: the one neutral card', () {
      final v = resolveCoupleWidget(CoupleWidgetPayload.empty, now);
      expect(v.headline, neutralHeadline);
      expect(v.neutral, isTrue);
    });

    test('a past reunion never shows (Review Focus 4)', () {
      final v = resolveCoupleWidget(
        const CoupleWidgetPayload(reunionDate: '2026-10-15'),
        now,
      );
      expect(v.neutral, isTrue);
    });

    test('semantics label joins the lines', () {
      const v = CoupleWidgetView(
        headline: 'Together tomorrow',
        caption: '5.1k km apart',
        clockLine: '3:15pm there',
      );
      expect(
        v.semanticsLabel,
        'Together tomorrow. 5.1k km apart. 3:15pm there',
      );
    });

    test('config holds the spec values', () {
      expect(CoupleWidgetConfig.validFor, const Duration(hours: 3));
      expect(CoupleWidgetConfig.mapMinKm, 100);
      expect(CoupleWidgetConfig.gridDegrees, 0.5);
      expect(CoupleWidgetConfig.minSpanKm, 600);
      expect(CoupleWidgetConfig.fitFraction, 0.5);
      expect(CoupleWidgetConfig.readDebounce, const Duration(minutes: 5));
      expect(CoupleWidgetConfig.imagePx, 480);
      expect(CoupleWidgetConfig.renderBudget, const Duration(seconds: 2));
    });
  });
}
