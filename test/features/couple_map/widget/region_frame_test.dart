// test/features/couple_map/widget/region_frame_test.dart
import 'dart:math';

import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/region_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snaps to the 0.5° grid and clamps latitude to ±80', () {
    expect(snapToGrid((lat: 5.565, lng: -0.208)), (lat: 5.5, lng: 0.0));
    expect(snapToGrid((lat: 51.76, lng: -0.24)), (lat: 52.0, lng: 0.0));
    expect(snapToGrid((lat: 89.0, lng: 10.0)).lat, 80);
  });

  test('centres on the midpoint, never on one area', () {
    final f = regionFrame(
      (lat: 5.565, lng: -0.208),
      (lat: 51.505, lng: -0.125),
    );
    final centre = Offset(0.5, 0.5);
    expect(((f.self + f.partner) / 2 - centre).distance, lessThan(1e-9));
    expect((f.self - centre).distance, greaterThan(0.1));
  });

  test('Auckland to Los Angeles crosses the Pacific', () {
    final f = regionFrame(
      (lat: -36.85, lng: 174.76),
      (lat: 34.05, lng: -118.24),
    );
    expect(f.isWorld, isFalse);
    expect(f.partner.dx, greaterThan(f.self.dx), reason: 'east, over the sea');
  });

  test('either side of 180° in Fiji is one place', () {
    // Both latitudes snap to -17.5; both longitudes to the 180° meridian.
    final f = regionFrame((lat: -17.7, lng: 179.9), (lat: -17.6, lng: -179.9));
    expect((f.self - f.partner).distance, lessThan(1e-9));
  });

  test('antipodes give the world view', () {
    final f = regionFrame((lat: 0, lng: 0), (lat: 0, lng: 180));
    expect(f.isWorld, isTrue);
    expect(f.side, 1);
  });

  test('identical snapped points: minimum span, both in the middle', () {
    final f = regionFrame((lat: 5.56, lng: -0.2), (lat: 5.6, lng: -0.21));
    // Not exact equality: the frame arithmetic leaves ~1e-15 of float error.
    expect((f.self - const Offset(0.5, 0.5)).distance, lessThan(1e-9));
    expect((f.partner - const Offset(0.5, 0.5)).distance, lessThan(1e-9));
    final km = f.side * earthCircumferenceKm * cos(5.5 * pi / 180);
    expect(km, closeTo(CoupleWidgetConfig.minSpanKm, 1e-6));
  });

  test('cache key changes only with the snapped points', () {
    final a = regionFrame((lat: 5.56, lng: -0.2), (lat: 51.5, lng: -0.12));
    final b = regionFrame((lat: 5.58, lng: -0.19), (lat: 51.49, lng: -0.13));
    final c = regionFrame((lat: 6.9, lng: -0.2), (lat: 51.5, lng: -0.12));
    expect(a.cacheKey, b.cacheKey);
    expect(a.cacheKey, isNot(c.cacheKey));
  });

  test('properties over 2000 random couples (spec §8)', () {
    final r = Random(42);
    double lat() => r.nextDouble() * 160 - 80;
    double lng() => r.nextDouble() * 360 - 180;
    for (var i = 0; i < 2000; i++) {
      final a = (lat: lat(), lng: lng());
      final b = (lat: lat(), lng: lng());
      final f = regionFrame(a, b);
      for (final p in [f.self, f.partner]) {
        expect(p.dx, inInclusiveRange(-1e-9, 1 + 1e-9), reason: '$a $b');
        expect(p.dy, inInclusiveRange(-1e-9, 1 + 1e-9), reason: '$a $b');
        if (!f.isWorld) {
          expect(p.dx, inInclusiveRange(0.25 - 1e-9, 0.75 + 1e-9));
          expect(p.dy, inInclusiveRange(0.25 - 1e-9, 0.75 + 1e-9));
        }
      }
      if (!f.isWorld) {
        final sa = snapToGrid(a);
        final sb = snapToGrid(b);
        final midLat = (sa.lat + sb.lat) / 2;
        final km = f.side * earthCircumferenceKm * cos(midLat * pi / 180);
        expect(km, greaterThanOrEqualTo(CoupleWidgetConfig.minSpanKm - 1e-6));
      }
    }
  });
}
