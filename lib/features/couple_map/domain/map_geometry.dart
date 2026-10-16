import 'dart:math' as math;

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:flutter/foundation.dart';

@immutable
class MapPoint {
  const MapPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is MapPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  /// Redacted: a coordinate must never reach a log (checklist 4.4).
  @override
  String toString() => 'MapPoint(redacted)';
}

const _cellDeg = 0.01;
const _minCos = 0.2;
const _earthKm = 6371.0; // as SQL haversine_km

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// Half away from zero, like Postgres round(numeric, 3).
double _round3(double v) => (v * 1000).round() / 1000;

double _bandLat(double lat) =>
    math.min((lat / _cellDeg).floor(), 8999) * _cellDeg + _cellDeg / 2;

double _lngStep(double bandLat) =>
    _cellDeg / math.max(math.cos(_rad(bandLat)), _minCos);

/// Mirrors SQL presence_snap_cell. The server is the authority; this exists
/// so tests can prove the drawn area covers a whole cell.
MapPoint snapCell(double lat, double lng) {
  final band = _bandLat(lat);
  final step = _lngStep(band);
  final c = (((lng + 180) / step).floor() * step + step / 2 - 180).clamp(
    -180.0,
    180.0,
  );
  return MapPoint(_round3(band), _round3(c));
}

/// The four corners of the cell that contains (lat, lng).
List<MapPoint> cellCorners(double lat, double lng) {
  final band = _bandLat(lat);
  final step = _lngStep(band);
  final west = ((lng + 180) / step).floor() * step - 180;
  final south = band - _cellDeg / 2;
  final north = band + _cellDeg / 2;
  return [
    MapPoint(south, west),
    MapPoint(south, west + step),
    MapPoint(north, west),
    MapPoint(north, west + step),
  ];
}

double haversineKm(MapPoint a, MapPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthKm * math.asin(math.sqrt(h));
}

/// A closed ring of [points] vertices at [radiusKm] around [centre]
/// (spherical destination formula), for the area's fill polygon.
List<MapPoint> areaRing(
  MapPoint centre, {
  double radiusKm = CoupleMapConfig.areaRadiusKm,
  int points = CoupleMapConfig.areaRingPoints,
}) {
  final lat1 = _rad(centre.lat);
  final lng1 = _rad(centre.lng);
  final d = radiusKm / _earthKm;
  final ring = <MapPoint>[];
  for (var i = 0; i < points; i++) {
    final bearing = 2 * math.pi * i / points;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(d) +
          math.cos(lat1) * math.sin(d) * math.cos(bearing),
    );
    final lng2 =
        lng1 +
        math.atan2(
          math.sin(bearing) * math.sin(d) * math.cos(lat1),
          math.cos(d) - math.sin(lat1) * math.sin(lat2),
        );
    ring.add(MapPoint(_deg(lat2), _deg(lng2)));
  }
  ring.add(ring.first);
  return ring;
}
