// test/features/couple_map/map_geometry_test.dart
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('snapCell mirrors SQL presence_snap_cell', () {
    // Expected values computed from the SQL formula (Phase 1 plan, 2026-10-15).
    const cases = <(double, double, double, double)>[
      (5.5603, -0.2057, 5.565, -0.208), // Accra (contract C3 centre)
      (51.5074, -0.1278, 51.505, -0.121), // London
      (
        78.2232,
        15.6267,
        78.225,
        15.645,
      ), // Longyearbyen: cos(lat) near the 0.2 floor
      (-5.1477, 119.4327, -5.145, 119.431), // Makassar
      (-33.9, -179.999, -33.895, -179.994), // just east of the antimeridian
      (0.0, 0.0, 0.005, -0.005), // equator / prime meridian
    ];
    for (final (lat, lng, eLat, eLng) in cases) {
      test('($lat, $lng)', () {
        final c = snapCell(lat, lng);
        expect(c.lat, closeTo(eLat, 1e-9));
        expect(c.lng, closeTo(eLng, 1e-9));
      });
    }
  });

  test('snapping is idempotent: snap(snap(x)) == snap(x) (checklist 6.5)', () {
    for (var lat = -80.0; lat <= 80; lat += 3.7) {
      for (var lng = -179.0; lng <= 179; lng += 11.3) {
        final once = snapCell(lat, lng);
        expect(snapCell(once.lat, once.lng), once, reason: '$lat,$lng');
      }
    }
  });

  test(
    'the area circle covers the whole cell, corners included (spec §3.2)',
    () {
      var worst = 0.0;
      for (var lat = -78.0; lat <= 78; lat += 0.37) {
        for (final lng in [-179.5, -120.3, -0.2, 0.0004, 45.7, 179.5]) {
          final centre = snapCell(lat, lng);
          for (final corner in cellCorners(lat, lng)) {
            final d = haversineKm(centre, corner);
            if (d > worst) worst = d;
          }
        }
      }
      expect(worst, lessThanOrEqualTo(CoupleMapConfig.areaRadiusKm));
      expect(CoupleMapConfig.areaRadiusKm * 2, greaterThanOrEqualTo(1.6));
    },
  );

  test('areaRing is closed and every vertex sits on the radius', () {
    const centre = MapPoint(5.565, -0.208);
    final ring = areaRing(centre);
    expect(ring.length, CoupleMapConfig.areaRingPoints + 1);
    expect(ring.first, ring.last);
    for (final p in ring) {
      expect(
        haversineKm(centre, p),
        closeTo(CoupleMapConfig.areaRadiusKm, 0.005),
      );
    }
  });

  test('a MapPoint never prints its coordinates (checklist 4.4)', () {
    expect(const MapPoint(5.565, -0.208).toString(), isNot(contains('5.5')));
  });
}
