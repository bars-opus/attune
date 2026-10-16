// test/features/location/couple_map_presence_test.dart
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(
  String who, {
  num? lat = 5.565,
  String? city = 'Accra',
  int? offset = 0,
  String freshness = 'fresh',
  String? pausedUntil,
  int? km,
  bool? together,
}) => {
  'who': who,
  'cell_lat': lat,
  'cell_lng': lat == null ? null : -0.205,
  'city': city,
  'country': 'Ghana',
  'utc_offset_minutes': offset,
  'freshness': freshness,
  'my_paused_until': pausedUntil,
  'distance_km': km,
  'together': together,
};

void main() {
  test('no rows: not sharing, nothing to show', () {
    final p = CoupleMapPresence.fromRows(const []);
    expect(p.state.status, PresenceStatus.off);
    expect(p.self, isNull);
    expect(p.partner, isNull);
    expect(p.partnerDistance, isNull);
  });

  test('self only: sharing, no partner and no distance', () {
    final p = CoupleMapPresence.fromRows([_row('self')]);
    expect(p.state.status, PresenceStatus.sharing);
    expect(p.self!.city, 'Accra');
    expect(p.partnerDistance, isNull);
  });

  test('a pause shows as paused with its end, self-facing only', () {
    final p = CoupleMapPresence.fromRows([
      _row('self', lat: null, city: null, pausedUntil: '2026-10-16T12:00:00Z'),
    ]);
    expect(p.state.status, PresenceStatus.paused);
    expect(p.state.pausedUntil, DateTime.utc(2026, 10, 16, 12));
  });

  test('both: the partner area, the rounded distance and their offset', () {
    final p = CoupleMapPresence.fromRows([
      _row('self'),
      _row(
        'partner',
        lat: 51.505,
        city: 'London',
        offset: 60,
        freshness: 'fading',
        km: 5100,
        together: false,
      ),
    ]);
    expect(p.partner!.freshness, PresenceFreshness.fading);
    expect(p.partnerDistance!.km, 5100);
    expect(p.partnerDistance!.partnerUtcOffsetMinutes, 60);
    expect(p.partnerDistance!.partnerCity, 'London');
  });

  test('adjacent cells read as together', () {
    final p = CoupleMapPresence.fromRows([
      _row('self'),
      _row('partner', km: 2, together: true),
    ]);
    expect(p.partnerDistance!.tone, DistanceTone.together);
  });

  test('an unknown freshness value is treated as fading, never as fresh', () {
    final p = CoupleMapPresence.fromRows([
      _row('self'),
      _row('partner', freshness: 'weird', km: 10, together: false),
    ]);
    expect(p.partner!.freshness, PresenceFreshness.fading);
  });

  test('a pause "until I resume" (infinity) reads as paused with no end', () {
    final p = CoupleMapPresence.fromRows([
      {'who': 'self', 'freshness': 'fresh', 'my_paused_until': 'infinity'},
    ]);
    expect(p.state.status, PresenceStatus.paused);
    expect(p.state.pausedUntil, isNull);
  });

  test('an unreadable pause value still reads as paused, never as sharing', () {
    final p = CoupleMapPresence.fromRows([
      {'who': 'self', 'freshness': 'fresh', 'my_paused_until': 'garbage'},
    ]);
    expect(p.state.status, PresenceStatus.paused);
  });
}
