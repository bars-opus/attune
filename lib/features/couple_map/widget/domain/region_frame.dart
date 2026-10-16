// lib/features/couple_map/widget/domain/region_frame.dart
import 'dart:math';
import 'dart:ui' show Offset;

import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/geo_point.dart';
import 'package:flutter/foundation.dart';

const earthCircumferenceKm = 40075.0;
const _maxLat = 80.0;

double _snap(double v) =>
    (v / CoupleWidgetConfig.gridDegrees).round() *
    CoupleWidgetConfig.gridDegrees;

/// Draw-only coarsening (spec §3.3): the widget never draws finer than this.
GeoPoint snapToGrid(GeoPoint p) {
  final lng = _snap(p.lng);
  return (
    lat: _snap(p.lat).clamp(-_maxLat, _maxLat).toDouble(),
    // -180 and 180 are one meridian.
    lng: lng == -180 ? 180.0 : lng,
  );
}

/// Web Mercator in world units: x is 0..1 across -180..180 (beyond for an
/// unwrapped longitude), y is 0 at the top.
Offset mercator(GeoPoint p) {
  final lat = p.lat.clamp(-_maxLat, _maxLat) * pi / 180;
  return Offset((p.lng + 180) / 360, (1 - log(tan(pi / 4 + lat / 2)) / pi) / 2);
}

@immutable
class RegionFrame {
  const RegionFrame({
    required this.left,
    required this.top,
    required this.side,
    required this.self,
    required this.partner,
    required this.north,
    required this.cacheKey,
  });

  /// The square, in Mercator world units.
  final double left;
  final double top;
  final double side;

  /// The two snapped areas, 0..1 within the square.
  final Offset self;
  final Offset partner;

  /// The arc bows toward the nearer pole.
  final bool north;

  /// Changes only when the snapped points do (spec §3.3 cache).
  final String cacheKey;

  bool get isWorld => side >= 1;
}

/// A square fitting both snapped areas inside its central half, centred on
/// their midpoint, at least 600 km across, at most the world (spec §3.3).
RegionFrame regionFrame(GeoPoint self, GeoPoint partner) {
  final a = snapToGrid(self);
  final s = snapToGrid(partner);
  var lng = s.lng;
  while (lng - a.lng > 180) {
    lng -= 360;
  }
  while (lng - a.lng < -180) {
    lng += 360;
  }
  final b = (lat: s.lat, lng: lng);
  final ma = mercator(a);
  final mb = mercator(b);
  final cx = (ma.dx + mb.dx) / 2;
  final cy = (ma.dy + mb.dy) / 2;
  final midLat = (a.lat + b.lat) / 2;
  final minSide =
      CoupleWidgetConfig.minSpanKm /
      (earthCircumferenceKm * cos(midLat * pi / 180));
  final spread = max((ma.dx - mb.dx).abs(), (ma.dy - mb.dy).abs());
  var side = max(spread / CoupleWidgetConfig.fitFraction, minSide);
  double left;
  double top;
  if (side >= 1) {
    side = 1;
    left = cx - 0.5;
    top = 0;
  } else {
    left = cx - side / 2;
    top = cy - side / 2;
  }
  Offset inFrame(Offset m) => Offset((m.dx - left) / side, (m.dy - top) / side);
  return RegionFrame(
    left: left,
    top: top,
    side: side,
    self: inFrame(ma),
    partner: inFrame(mb),
    north: midLat >= 0,
    cacheKey: '${a.lat},${a.lng};${s.lat},${s.lng}',
  );
}
