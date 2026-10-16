# Couple Map Phase 1 (Map tab, presence) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Planning's third tab, **Map**, shows where each partner roughly is (an avatar over a ~1.7 km area), how far apart they are, and the controls for sharing and pausing. It sits behind `couple_map_enabled` (off).

**Architecture:** Pure domain code (cell geometry, copy, scene) in `lib/features/couple_map/domain/`. The map is behind a seam, `CoupleMapController`. The real implementation is Mapbox (`mapbox_maps_flutter` 2.24.3); tests use a fake that records calls. The tab composes the Phase 0 presence kernel (`coupleMapPresenceProvider`, `presenceStateProvider`, `partnerDistanceProvider`, `PresenceRepository`) with glass widgets. The chip, sheet and card each live in their own file.

**Tech Stack:** Flutter, Riverpod 2.6, `mapbox_maps_flutter` 2.24.3, `geolocator` 14, `cached_network_image`, `image` 4.3 (tests only).

**Spec:** `docs/superpowers/specs/2026-10-16-couple-map-design.md` (§2, §3.1–3.6, §6.1–6.3, §7 Phase 1, §8, §9). **Phase 0 ledger:** `.superpowers/sdd/2026-10-16-couple-map-phase0/progress.md` (its rulings and deferred minors carry forward).

## Global Constraints

- The partner is drawn **only** as an area: a translucent circle (radius `CoupleMapConfig.areaRadiusKm = 0.85`, so ≥ 1.6 km across and covering the whole server cell) centred on the **server-snapped cell centre**, with an avatar on top. Never a dot at a raw position, and never the Mapbox location puck: `LocationComponentSettings(enabled: false)`.
- **No online dot, no timestamps, no "last seen", "ago" or "online" copy.** Freshness shows only as opacity: `fading` = 0.5.
- Partner paused, stopped or stale, or me paused: exactly one line, **"Just you on the map right now"**. Never "waiting for", never a reason.
- Not sharing: **"See how far apart you are — shares your neighbourhood, never your address"**, which opens the Sharing sheet.
- Location permission or services off (my device): chip **"Location is off for Attune"**, notice **"Turn on location for Attune to share your area"**, which opens system settings.
- Chip states, verbatim: `Off`, `Sharing my area with {partner}`, `Paused · 42 min`, `Paused`, `Location is off for Attune`.
- Sharing sheet: `BottomSheetHeader` ("Done"), `InfoRowWidget` toggle **"Share my approximate area"**, rows **"Pause for 1 hour"**, **"Pause for 8 hours"**, **"Pause until I resume"**, and **"Resume"** while paused. Every failure shows **"Couldn't update your area. Try again."** (spec §9 2.4).
- Distance card details are joined with `" · "`. When together the headline is `Together · {city}` in `colorScheme.primary`.
- Glass buttons are 44 dp, each with a `Tooltip` and a `Semantics` label. The map canvas is wrapped in `ExcludeSemantics`. Reduced motion (`MediaQuery.disableAnimationsOf`) means camera jumps, not flights.
- Map unavailable (empty token or load error): the **list content** replaces the map, showing the same lines.
- **Never log coordinates, city or place names** (checklist 4.4). `MapPoint.toString()` redacts.
- No commits or pushes. Work on `main`, test first, and format only the files you touch. Analyzer filter: `grep -E "^\s*(error|warning) "`.
- Displayed dates use `MyDateFormat`; this phase displays only times of day (`formatClock`).
- **Out of scope here, in Phase 2 by the spec:** the Stories filter button (hidden while no story is pinned, and nothing can be pinned before Phase 2), story pins and clusters, "Remove all my places", the one-time stories hint, and quick-exit clearing of the last pin choice and home area.
- **Decision (ruling, spec §3.1 amended to match): glass is translucent, not blurred.** `BackdropFilter` over the Mapbox platform view is unreliable on Android hybrid composition and costly (spec §7 lists "blur performance" as the Phase 1 risk). So `GlassPanel` uses `surface` at 0.9 alpha with a hairline border and a soft shadow.

## Review Focus

1. **Partner disappears while I'm looking** (they pause, or 8 h pass): the next refresh must drop their area and avatar and replace the card with the neutral line. Nothing from before may linger. Test: Task 8, "partner disappears on refresh".
2. **Style switch (map ↔ satellite):** Mapbox drops runtime sources and layers on a style change, so presence must be re-applied after the new style loads. Test: Task 5 wiring test (`_styleLoaded` re-applies `_last`); verified on device.
3. **Theme flips light ↔ dark while the tab is open:** the Standard light preset follows (`day`/`night`). Test: Task 8, "theme change updates the light preset".
4. **No avatar, or the avatar fails to load:** the pin shows initials, never a blank or a crash. Test: Task 4, "loader failure falls back to initials".
5. **The map can't load** (no token, offline, Mapbox error): the list content appears in its place, and the chip and Sharing sheet still work. Test: Task 8, "load error" and "empty token".

---

## File structure

| File | Responsibility |
|---|---|
| `lib/features/couple_map/domain/couple_map_config.dart` (new) | Map constants (checklist 4.11) |
| `lib/features/couple_map/domain/map_geometry.dart` (new) | `MapPoint`, `snapCell` (mirrors SQL), `cellCorners`, `haversineKm`, `areaRing` |
| `lib/features/couple_map/domain/couple_map_scene.dart` (new) | `PresenceWho`, `SceneArea`, `sceneAreas()`, `areasGeoJson()` |
| `lib/features/couple_map/domain/couple_map_copy.dart` (new) | Chip label, pause remaining, notice, distance card copy, `initialsOf` |
| `lib/features/location/domain/location_access.dart` (new) | `enum LocationAccess { granted, denied, serviceOff }` |
| `lib/features/location/domain/distance_copy.dart` (modify) | Expose `formatKm`, `formatClock` |
| `lib/features/location/domain/reunion.dart` (modify) | Pure `withReunion()` |
| `lib/features/location/domain/presence_config.dart` (modify) | `recordDebounce` |
| `lib/features/location/data/presence_sampler.dart` (modify) | `access()`, `openSettings()`, geocoding comment fix (Phase 0 M12) |
| `lib/features/location/data/presence_repository.dart` (modify) | Client debounce (Phase 0 M11, checklist 3.7) |
| `lib/features/location/presentation/providers/presence_providers.dart` (modify) | `locationAccessProvider`, `partnerDistanceWithReunionProvider`, time zone cache refresh (Phase 0 M9) |
| `lib/features/location/presentation/widgets/partner_distance_row.dart` (modify) | Uses the reunion provider |
| `lib/features/couple_map/presentation/widgets/pin_image_renderer.dart` (new) | Avatar to PNG bytes, LRU of 64 |
| `lib/features/couple_map/presentation/map/couple_map_controller.dart` (new) | Seam: `CoupleMapController`, `CoupleMapStyle`, `CoupleMapViewBuilder` |
| `lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart` (new) | Mapbox implementation |
| `lib/features/couple_map/presentation/providers/couple_map_providers.dart` (new) | View builder, token, pin renderer, people providers |
| `lib/features/couple_map/presentation/widgets/glass_surface.dart` (new) | `GlassPanel`, `GlassIconButton` |
| `lib/features/couple_map/presentation/widgets/sharing_chip.dart` (new) | Top-left chip |
| `lib/features/couple_map/presentation/widgets/sharing_sheet.dart` (new) | Sharing and pause sheet |
| `lib/features/couple_map/presentation/widgets/distance_card.dart` (new) | Distance card, notice card, loading card |
| `lib/features/couple_map/presentation/widgets/couple_map_list_sheet.dart` (new) | Accessible list (content and sheet) |
| `lib/features/couple_map/presentation/screens/couple_map_tab.dart` (new) | The tab |
| `lib/features/couple_map/data/couple_map_device_data.dart` (new) | Quick-exit clearing |
| `lib/features/planning/presentation/screens/planning_home_screen.dart` (modify) | Third tab behind the flag |
| `lib/features/safety/domain/services/quick_exit_service.dart` (modify) | Calls `clearCoupleMapDeviceData()` |
| `test/features/planning/support/planning_test_app.dart` (modify) | Overrides the flag (default off) |
| `test/features/couple_map/support/fakes.dart` (new) | `FakeCoupleMapView`, `FakePinImageRenderer` |

**Regression risk (flagged):** `planning_home_screen.dart` and `quick_exit_service.dart` are shared. The tab is added only when the flag is on, so with the flag off (the default) Planning is unchanged. The quick-exit addition is fire-and-forget after the cover, like `clearTogetherDeviceSurfaces()`. `partner_distance_row.dart` isn't mounted anywhere today.

---

### Task 1: Cell geometry and map constants

**Files:**
- Create: `lib/features/couple_map/domain/couple_map_config.dart`, `lib/features/couple_map/domain/map_geometry.dart`
- Test: `test/features/couple_map/map_geometry_test.dart`

**Interfaces:**
- Produces:
  - `class MapPoint { const MapPoint(double lat, double lng); final double lat, lng; }` (its `==` and `hashCode` are value-based; `toString` is redacted)
  - `MapPoint snapCell(double lat, double lng)`
  - `List<MapPoint> cellCorners(double lat, double lng)`
  - `double haversineKm(MapPoint a, MapPoint b)`
  - `List<MapPoint> areaRing(MapPoint centre, {double radiusKm = CoupleMapConfig.areaRadiusKm, int points = CoupleMapConfig.areaRingPoints})` (closed: first point == last point)
  - `abstract final class CoupleMapConfig` with the constants below

- [ ] **Step 1: Write the failing test**

```dart
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
      (78.2232, 15.6267, 78.225, 15.645), // Longyearbyen: cos(lat) near the 0.2 floor
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

  test('the area circle covers the whole cell, corners included (spec §3.2)', () {
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
  });

  test('areaRing is closed and every vertex sits on the radius', () {
    const centre = MapPoint(5.565, -0.208);
    final ring = areaRing(centre);
    expect(ring.length, CoupleMapConfig.areaRingPoints + 1);
    expect(ring.first, ring.last);
    for (final p in ring) {
      expect(haversineKm(centre, p), closeTo(CoupleMapConfig.areaRadiusKm, 0.005));
    }
  });

  test('a MapPoint never prints its coordinates (checklist 4.4)', () {
    expect(const MapPoint(5.565, -0.208).toString(), isNot(contains('5.5')));
  });
}
```

- [ ] **Step 2: Run it and confirm it fails.** `flutter test test/features/couple_map/map_geometry_test.dart`. Expected: compilation error, because the files don't exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/domain/couple_map_config.dart
/// The couple map's own numbers (checklist 4.11). Presence timings live in
/// PresenceConfig, which mirrors SQL presence_config().
abstract final class CoupleMapConfig {
  /// A cell is ~1.11 km square and its centre is rounded to 0.001°, so its
  /// farthest corner is at most ~0.83 km away; 0.85 km covers the whole
  /// cell (spec §3.2: at least 1.6 km across).
  static const areaRadiusKm = 0.85;
  static const areaRingPoints = 48;

  /// Opacity of an area and avatar the server marks `fading` (4–8 h).
  static const fadingOpacity = 0.5;

  /// Avatar pin diameter, logical pixels.
  static const pinSize = 44.0;

  /// Rendered pin images kept in memory (checklist 2.12–2.15, 3.4).
  static const pinCacheEntries = 64;

  static const glassButtonSize = 44.0;
  static const fitPadding = 72.0;
  static const fitMaxZoom = 12.5;
  static const singleAreaZoom = 12.0;

  /// Lifts the Mapbox logo and attribution above the bottom card.
  static const ornamentLift = 120.0;
}
```

```dart
// lib/features/couple_map/domain/map_geometry.dart
import 'dart:math' as math;

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
  double radiusKm = 0.85,
  int points = 48,
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
```

Then edit the `areaRing` defaults to reference the config: add `import 'couple_map_config.dart';` and use `double radiusKm = CoupleMapConfig.areaRadiusKm, int points = CoupleMapConfig.areaRingPoints`.

- [ ] **Step 4: Run it and confirm it passes.** The same command. Expected: all pass. If a fixture is off by 0.001, rule on it (Dart and Postgres double→numeric rounding at an exact half) and ledger it. Don't loosen the coverage test.
- [ ] **Step 5: Ledger.**

---

### Task 2: Copy (chip, notice, card, initials) and `LocationAccess`

**Files:**
- Create: `lib/features/location/domain/location_access.dart`, `lib/features/couple_map/domain/couple_map_copy.dart`
- Modify: `lib/features/location/domain/distance_copy.dart` (rename `_km` → `formatKm` and `_clock` → `formatClock`, both public)
- Test: `test/features/couple_map/couple_map_copy_test.dart`

**Interfaces:**
- Consumes: `PresenceState`, `PresenceStatus`, `CoupleMapPresence` (Phase 0); `PartnerDistance`, `DistanceTone`, `distanceCopy`.
- Produces:
  - `enum LocationAccess { granted, denied, serviceOff }`
  - `String sharingChipLabel(PresenceState s, {required LocationAccess access, required String partnerName, required DateTime now})`
  - `String pauseRemainingLabel(Duration d)`
  - `enum CoupleMapNotice { notSharing, locationOff, justYou }`
  - `CoupleMapNotice? coupleMapNotice(CoupleMapPresence p, LocationAccess access)`
  - `String noticeText(CoupleMapNotice n)`
  - `class DistanceCardCopy { final String headline; final String details; final bool together; }`
  - `DistanceCardCopy distanceCardCopy(PartnerDistance d, {String? partnerName, int? myUtcOffsetMinutes, required DateTime now})`
  - `String initialsOf(String? name)`
  - `String formatKm(double km)`, `String formatClock(DateTime local)`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/couple_map/couple_map_copy_test.dart
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 16, 12);

CoupleMapPresence _p({bool self = true, bool partner = true}) =>
    CoupleMapPresence.fromRows([
      if (self) {'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'freshness': 'fresh'},
      if (self && partner)
        {'who': 'partner', 'cell_lat': 51.505, 'cell_lng': -0.121, 'city': 'London',
         'freshness': 'fresh', 'distance_km': 5100, 'together': false},
    ]);

void main() {
  group('the sharing chip (spec §3.1, verbatim)', () {
    String label(PresenceState s, {LocationAccess access = LocationAccess.granted}) =>
        sharingChipLabel(s, access: access, partnerName: 'Kofi', now: _now);

    test('off', () => expect(label(const PresenceState(PresenceStatus.off)), 'Off'));
    test('sharing', () => expect(label(const PresenceState(PresenceStatus.sharing)), 'Sharing my area with Kofi'));
    test('paused with an end shows what is left, rounded up', () {
      final s = PresenceState(PresenceStatus.paused, pausedUntil: _now.add(const Duration(minutes: 41, seconds: 10)));
      expect(label(s), 'Paused · 42 min');
    });
    test('paused until resumed', () => expect(label(const PresenceState(PresenceStatus.paused)), 'Paused'));
    test('a pause whose end has passed reads plainly as paused', () {
      expect(label(PresenceState(PresenceStatus.paused, pausedUntil: _now.subtract(const Duration(minutes: 1)))), 'Paused');
    });
    test('sharing with location off says so (my own device only)', () {
      expect(label(const PresenceState(PresenceStatus.sharing), access: LocationAccess.denied), 'Location is off for Attune');
      expect(label(const PresenceState(PresenceStatus.sharing), access: LocationAccess.serviceOff), 'Location is off for Attune');
    });
    test('paused stays paused even with location off', () {
      expect(label(const PresenceState(PresenceStatus.paused), access: LocationAccess.denied), 'Paused');
    });
  });

  test('pause remaining: minutes under an hour, then hours and minutes', () {
    expect(pauseRemainingLabel(const Duration(seconds: 20)), '1 min');
    expect(pauseRemainingLabel(const Duration(minutes: 59)), '59 min');
    expect(pauseRemainingLabel(const Duration(hours: 1)), '1 h');
    expect(pauseRemainingLabel(const Duration(hours: 7, minutes: 5)), '7 h 5 min');
  });

  group('one notice for every reason (spec §3.4)', () {
    test('not sharing', () {
      final p = CoupleMapPresence.none;
      expect(coupleMapNotice(p, LocationAccess.granted), CoupleMapNotice.notSharing);
      expect(noticeText(CoupleMapNotice.notSharing),
          'See how far apart you are — shares your neighbourhood, never your address');
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
      expect(coupleMapNotice(p, LocationAccess.granted), CoupleMapNotice.justYou);
    });
    test('location off and no partner: turn it on', () {
      expect(coupleMapNotice(_p(partner: false), LocationAccess.denied), CoupleMapNotice.locationOff);
      expect(noticeText(CoupleMapNotice.locationOff), 'Turn on location for Attune to share your area');
    });
    test('a partner on the map: no notice (the card shows)', () {
      expect(coupleMapNotice(_p(), LocationAccess.granted), isNull);
      expect(coupleMapNotice(_p(), LocationAccess.denied), isNull);
    });
    test('no copy anywhere mentions waiting, a reason, or a time', () {
      for (final n in CoupleMapNotice.values) {
        final t = noticeText(n).toLowerCase();
        for (final banned in ['waiting', 'paused', 'stopped', 'ago', 'last seen', 'online']) {
          expect(t.contains(banned), isFalse, reason: '$n: $banned');
        }
      }
    });
  });

  group('the distance card (spec §3.1)', () {
    test('far apart: the headline, then km · city · their time, joined by " · "', () {
      const d = PartnerDistance(km: 5100, partnerCity: 'London', partnerUtcOffsetMinutes: 60);
      final c = distanceCardCopy(d, partnerName: 'Kofi', myUtcOffsetMinutes: 0, now: DateTime.utc(2026, 9, 2, 22, 15));
      expect(c.headline, '11:15pm where they are');
      expect(c.details, '5.1k km apart · in London');
      expect(c.together, isFalse);
    });
    test('a countdown keeps the time there when the zones differ', () {
      const d = PartnerDistance(km: 5100, partnerCity: 'London', partnerUtcOffsetMinutes: 60, daysUntilTogether: 12);
      final c = distanceCardCopy(d, myUtcOffsetMinutes: 0, now: DateTime.utc(2026, 9, 2, 14, 15));
      expect(c.headline, "12 days until you're together");
      expect(c.details, '5.1k km apart · in London · 3:15pm there');
    });
    test('the same zone: no "there" time', () {
      const d = PartnerDistance(km: 300, partnerCity: 'Kumasi', partnerUtcOffsetMinutes: 0);
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
      expect(distanceCardCopy(const PartnerDistance(km: 1, together: true), now: _now).headline, 'Together');
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
```

- [ ] **Step 2: Run it and confirm it fails.** `flutter test test/features/couple_map/couple_map_copy_test.dart`. Expected: compilation error.

- [ ] **Step 3: Implement**

In `distance_copy.dart`, rename `_km` to `formatKm` and `_clock` to `formatClock` (with doc comments, both public), and update the two or three call sites in the same file.

```dart
// lib/features/location/domain/location_access.dart
/// Whether this device can take a location fix for Attune right now.
/// Self-facing only: the partner never learns any of this.
enum LocationAccess { granted, denied, serviceOff }
```

```dart
// lib/features/couple_map/domain/couple_map_copy.dart
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
// widgets.dart (not foundation.dart): it also exports `characters`.
import 'package:flutter/widgets.dart';

/// The top-left chip: always visible, so you always know who can see you.
String sharingChipLabel(
  PresenceState s, {
  required LocationAccess access,
  required String partnerName,
  required DateTime now,
}) {
  switch (s.status) {
    case PresenceStatus.off:
      return 'Off';
    case PresenceStatus.paused:
      final until = s.pausedUntil;
      if (until == null) return 'Paused';
      final left = until.difference(now);
      return left.isNegative || left == Duration.zero
          ? 'Paused'
          : 'Paused · ${pauseRemainingLabel(left)}';
    case PresenceStatus.sharing:
      if (access != LocationAccess.granted) return 'Location is off for Attune';
      return 'Sharing my area with $partnerName';
  }
}

/// "42 min", "1 h", "7 h 5 min". Rounded up, so it never says 0.
String pauseRemainingLabel(Duration d) {
  final mins = (d.inSeconds / 60).ceil().clamp(1, 1 << 30);
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

enum CoupleMapNotice { notSharing, locationOff, justYou }

/// The one line shown instead of the distance card, or null when the card
/// shows. Every partner-side reason (paused, stopped, stale, never shared)
/// and my own pause give the same answer: the server can't tell them apart
/// and neither may the copy (spec §3.4).
CoupleMapNotice? coupleMapNotice(CoupleMapPresence p, LocationAccess access) {
  if (p.state.status == PresenceStatus.off) return CoupleMapNotice.notSharing;
  if (p.partnerDistance != null) return null;
  if (p.state.status == PresenceStatus.sharing &&
      access != LocationAccess.granted) {
    return CoupleMapNotice.locationOff;
  }
  return CoupleMapNotice.justYou;
}

String noticeText(CoupleMapNotice n) => switch (n) {
  CoupleMapNotice.notSharing =>
    'See how far apart you are — shares your neighbourhood, never your address',
  CoupleMapNotice.locationOff =>
    'Turn on location for Attune to share your area',
  CoupleMapNotice.justYou => 'Just you on the map right now',
};

@immutable
class DistanceCardCopy {
  const DistanceCardCopy({
    required this.headline,
    required this.details,
    required this.together,
  });
  final String headline;

  /// Segments joined with " · "; empty when there is nothing to add.
  final String details;
  final bool together;
}

DistanceCardCopy distanceCardCopy(
  PartnerDistance d, {
  String? partnerName,
  int? myUtcOffsetMinutes,
  required DateTime now,
}) {
  if (d.tone == DistanceTone.together) {
    return DistanceCardCopy(
      headline: d.partnerCity == null ? 'Together' : 'Together · ${d.partnerCity}',
      details: '',
      together: true,
    );
  }
  final copy = distanceCopy(d, partnerName: partnerName, now: now);
  final offset = d.partnerUtcOffsetMinutes;
  final segments = <String>[
    if (!copy.headline.contains(' km')) '${formatKm(d.km)} apart',
    if (d.partnerCity != null) 'in ${d.partnerCity}',
    if (offset != null &&
        offset != myUtcOffsetMinutes &&
        !copy.headline.endsWith('where they are'))
      '${formatClock(now.toUtc().add(Duration(minutes: offset)))} there',
  ];
  return DistanceCardCopy(
    headline: copy.headline,
    details: segments.join(' · '),
    together: false,
  );
}

/// Up to two initials for an avatar with no photo.
String initialsOf(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}
```

- [ ] **Step 4: Run it and confirm it passes,** together with `test/features/location/distance_copy_test.dart`, which must still pass after the rename.
- [ ] **Step 5: Ledger.**

---

### Task 3: Kernel additions (location access, client debounce, time zone refresh, reunion provider)

**Files:**
- Modify: `lib/features/location/data/presence_sampler.dart`, `lib/features/location/data/presence_repository.dart`, `lib/features/location/domain/presence_config.dart`, `lib/features/location/domain/reunion.dart`, `lib/features/location/presentation/providers/presence_providers.dart`, `lib/features/location/presentation/widgets/partner_distance_row.dart`
- Test: `test/features/location/presence_repository_test.dart` (extend `FakeSampler`, add tests), `test/features/location/reunion_test.dart` (add), `test/features/location/presence_providers_test.dart` (add), `test/features/location/location_wiring_test.dart` (add)

**Interfaces:**
- Consumes: `LocationAccess` (Task 2).
- Produces:
  - `PresenceSampler.access() → Future<LocationAccess>` (never prompts)
  - `PresenceSampler.openSettings() → Future<void>`
  - `PresenceRepository(..., {DateTime Function()? now})`
  - `PresenceRepository.record(rel, {bool force = false})`
  - `PresenceConfig.recordDebounce = Duration(seconds: 60)`
  - `PartnerDistance withReunion(PartnerDistance d, Iterable<(String, DateTime)> events, {DateTime? now})`
  - `locationAccessProvider` (`FutureProvider.autoDispose<LocationAccess>`), re-checked on app resume
  - `partnerDistanceWithReunionProvider` (`Provider.autoDispose.family<PartnerDistance?, String>`)

- [ ] **Step 1: Write the failing tests**

In `presence_repository_test.dart`, extend `FakeSampler`:

```dart
  LocationAccess accessValue = LocationAccess.granted;
  int openedSettings = 0;
  @override
  Future<LocationAccess> access() async => accessValue;
  @override
  Future<void> openSettings() async => openedSettings++;
```

Add `import 'package:attune/features/location/domain/location_access.dart';` and these tests:

```dart
  test('a second automatic record within 60 s is skipped on the device (checklist 3.7)', () async {
    var now = DateTime.utc(2026, 10, 16, 12);
    final g = FakePresenceGateway();
    final s = FakeSampler(next: _accra);
    final r = PresenceRepository(g, s, () async => 'Africa/Accra', now: () => now);
    expect(await r.record('r1'), isTrue);
    now = now.add(const Duration(seconds: 30));
    expect(await r.record('r1'), isFalse);
    expect(s.sampled, 1, reason: 'no GPS fix or geocode for a write the server would ignore');
    now = now.add(const Duration(seconds: 31));
    expect(await r.record('r1'), isTrue);
    expect(s.sampled, 2);
  });

  test('opting in and resuming always record at once, whatever the debounce', () async {
    final now = DateTime.utc(2026, 10, 16, 12);
    final g = FakePresenceGateway();
    final s = FakeSampler(next: _accra);
    final r = PresenceRepository(g, s, () async => 'Africa/Accra', now: () => now);
    await r.record('r1');
    await r.startSharing('r1');
    expect(s.sampled, 2);
    await r.resume('r1');
    expect(await r.record('r1'), isTrue, reason: 'resume needs a fresh sample (spec §4.2)');
  });
```

In `reunion_test.dart`, add `import 'package:attune/features/location/domain/partner_distance.dart';` and:

```dart
  group('withReunion', () {
    final now = DateTime(2026, 10, 16, 9);
    test('far apart with a reunion: counts down to the soonest', () {
      final d = withReunion(const PartnerDistance(km: 5100), [
        ('Flight to Accra', DateTime(2026, 10, 28, 8)),
        ('Visit for Christmas', DateTime(2026, 12, 20)),
      ], now: now);
      expect(d.daysUntilTogether, 12);
    });
    test('nearby: no countdown', () {
      expect(withReunion(const PartnerDistance(km: 300), [('Flight', DateTime(2026, 10, 20))], now: now).daysUntilTogether, isNull);
    });
    test('a work trip or a past event is ignored', () {
      final d = withReunion(const PartnerDistance(km: 5100), [
        ('Work trip to Lagos', DateTime(2026, 10, 20)),
        ('Flight home', DateTime(2026, 10, 1)),
      ], now: now);
      expect(d.daysUntilTogether, isNull);
    });
    test('keeps every other field', () {
      final d = withReunion(const PartnerDistance(km: 5100, partnerCity: 'London', partnerUtcOffsetMinutes: 60), [('Visit', DateTime(2026, 10, 18))], now: now);
      expect((d.partnerCity, d.partnerUtcOffsetMinutes, d.daysUntilTogether), ('London', 60, 2));
    });
  });
```

In `presence_providers_test.dart`, add:

```dart
  test('location access is read without prompting', () async {
    final g = FakePresenceGateway();
    final s = FakeSampler()..accessValue = LocationAccess.denied;
    final c = _container(g, s);
    expect(await c.read(locationAccessProvider.future), LocationAccess.denied);
    expect(s.asked, 0);
  });
```

In `location_wiring_test.dart`, add:

```dart
  test('checking location access never prompts', () {
    final source = File('lib/features/location/data/presence_sampler.dart').readAsStringSync();
    final access = source.substring(
      source.indexOf('Future<LocationAccess> access()'),
      source.indexOf('Future<void> openSettings()'),
    );
    expect(access.contains('requestPermission'), isFalse);
  });

  test('the sampler does not claim on-device geocoding', () {
    final source = File('lib/features/location/data/presence_sampler.dart').readAsStringSync();
    expect(source.contains('On-device geocoding'), isFalse,
        reason: 'Geocoder/CLGeocoder send the fix to Google/Apple (Phase 0 M12)');
  });

  test('the presence time zone is re-read, so travel updates it', () {
    final source = File('lib/features/location/presentation/providers/presence_providers.dart').readAsStringSync();
    expect(source.contains('TimezoneUtils.clearCache()'), isTrue);
  });
```

- [ ] **Step 2: Run them and confirm they fail.** `flutter test test/features/location/`. Expected: compilation errors (`access`, `now:`, `withReunion`, `locationAccessProvider`).

- [ ] **Step 3: Implement**

`presence_config.dart`: add

```dart
  /// Client-side debounce of automatic samples; mirrors SQL rate_limit_s.
  static const recordDebounce = Duration(seconds: 60);
```

`presence_sampler.dart`:
- Add `import 'package:attune/features/location/domain/location_access.dart';`.
- Add to `abstract class PresenceSampler`, after `requestPermission()`:

```dart
  /// Whether a fix is possible right now. Never prompts.
  Future<LocationAccess> access();

  /// Opens the system settings where Attune's location can be turned on.
  Future<void> openSettings();
```

- In `GeolocatorPresenceSampler`, after `requestPermission()`:

```dart
  @override
  Future<LocationAccess> access() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceOff;
      }
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse ||
              p == LocationPermission.always
          ? LocationAccess.granted
          : LocationAccess.denied;
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }
```

- Replace the comment `// On-device geocoding: coordinates never go to a third-party HTTP API.` with `// The platform geocoder (Android Geocoder / iOS CLGeocoder): the app calls no third-party HTTP API, though the OS may ask Google or Apple.`

`presence_repository.dart`:
- Constructor: `PresenceRepository(this._gateway, this._sampler, this._timezone, {LocationService? placeService, DateTime Function()? now}) : _placeService = placeService ?? LocationService(), _now = now ?? DateTime.now;`
- Add the fields `final DateTime Function() _now;` and `final _lastRecordedAt = <String, DateTime>{};`, keyed by relationship so one couple's record never debounces another's.
- `record`:

```dart
  /// Records my area if I can get a fix; false otherwise. Never throws.
  ///
  /// Automatic calls within [PresenceConfig.recordDebounce] of the last
  /// success are skipped before sampling: the server would ignore the
  /// write, and each one costs a fix and a geocode (checklist 3.7).
  Future<bool> record(String relationshipId, {bool force = false}) async {
    final last = _lastRecordedAt[relationshipId];
    if (!force &&
        last != null &&
        _now().difference(last) < PresenceConfig.recordDebounce) {
      return false;
    }
    final s = await _sampler.sample();
    if (s == null) return false;
    try {
      await _gateway.rpc('record_presence', params: { /* unchanged */ });
      _lastRecordedAt[relationshipId] = _now();
      return true;
    } catch (e) {
      _log('record', e);
      return false;
    }
  }
```

- `startSharing` calls `record(relationshipId, force: true)`.
- `resume` and `stopSharing` call `_lastRecordedAt.remove(relationshipId)` before their RPC (convert them to `async`).
- Add `import 'package:attune/features/location/domain/presence_config.dart';`.

`reunion.dart`: add

```dart
/// Adds a countdown when the calendar holds a reunion, only for couples
/// far enough apart for a countdown to mean something.
PartnerDistance withReunion(
  PartnerDistance d,
  Iterable<(String, DateTime)> events, {
  DateTime? now,
}) {
  if (d.km < PartnerDistance.sameCountryKm) return d;
  int? soonest;
  for (final (title, at) in events) {
    if (!isReunionEvent(title)) continue;
    final days = daysUntil(at, now: now);
    if (days < 0) continue;
    if (soonest == null || days < soonest) soonest = days;
  }
  if (soonest == null) return d;
  return PartnerDistance(
    km: d.km,
    partnerCity: d.partnerCity,
    partnerUtcOffsetMinutes: d.partnerUtcOffsetMinutes,
    daysUntilTogether: soonest,
    together: d.together,
  );
}
```

(Import `partner_distance.dart` if it isn't imported yet.)

`presence_providers.dart`:
- `presenceTimezoneProvider` becomes:

```dart
final presenceTimezoneProvider = Provider<Future<String> Function()>(
  (ref) => () {
    // Re-read each time (records are debounced to one a minute): someone
    // who travels would otherwise keep their old zone until a restart.
    TimezoneUtils.clearCache();
    return TimezoneUtils.getDeviceTimezone();
  },
);
```

- Add:

```dart
/// Whether this device can take a fix, re-checked when the app resumes
/// (e.g. back from Settings). Never prompts.
final locationAccessProvider = FutureProvider.autoDispose<LocationAccess>((
  ref,
) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return ref.watch(presenceSamplerProvider).access();
});

/// The distance with a reunion countdown from the shared calendar.
/// Keeps the last value through refreshes (valueOrNull), so the card
/// doesn't flicker.
final partnerDistanceWithReunionProvider = Provider.autoDispose
    .family<PartnerDistance?, String>((ref, relationshipId) {
      final d = ref.watch(partnerDistanceProvider(relationshipId)).valueOrNull;
      if (d == null) return null;
      final reminders = ref.watch(remindersListProvider).valueOrNull ?? const [];
      return withReunion(d, [for (final r in reminders) (r.title, r.remindAt)]);
    });
```

- Add the imports: `location_access.dart`, `reunion.dart`, and `package:attune/features/reminders/presentation/providers/reminders_providers.dart`.

`partner_distance_row.dart`:
- `final distance = ref.watch(partnerDistanceWithReunionProvider(relationshipId));`
- Delete `_withReunion` and pass `distance` straight to `distanceCopy`.
- Remove the now-unused `reminders_providers` and `reunion` imports.

- [ ] **Step 4: Run them and confirm they pass.** `flutter test test/features/location/ test/features/chat/chat_settings_location_toggle_test.dart test/features/planning/planning_couple_blocks_screen_test.dart`. Expected: all pass.
- [ ] **Step 5: Ledger.**

---

### Task 4: The pin image renderer

**Files:**
- Create: `lib/features/couple_map/presentation/widgets/pin_image_renderer.dart`
- Test: `test/features/couple_map/pin_image_renderer_test.dart`

**Interfaces:**
- Produces:
  - `typedef PinImageLoader = Future<ui.Image?> Function(String url);`
  - `class PinSpec { const PinSpec({String? imageUrl, required String initials, required Color ring, required Color fill, required Color onFill, required int sizePx}); }` (value-equal)
  - `class PinImageRenderer { PinImageRenderer({PinImageLoader? loader, int maxEntries}); Future<Uint8List> render(PinSpec); int get length; void clear(); }`
  - `final sharedPinImageRenderer = PinImageRenderer();`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/couple_map/pin_image_renderer_test.dart
import 'dart:ui' as ui;

import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

PinSpec _spec(String initials, {String? url}) => PinSpec(
      imageUrl: url,
      initials: initials,
      ring: Colors.white,
      fill: Colors.indigo,
      onFill: Colors.white,
      sizePx: 88,
    );

Future<ui.Image> _photo() async {
  final r = ui.PictureRecorder();
  Canvas(r).drawColor(Colors.orange, BlendMode.src);
  return r.endRecording().toImage(10, 10);
}

void main() {
  testWidgets('initials render to a PNG of the requested size', (t) async {
    await t.runAsync(() async {
      final bytes = await PinImageRenderer().render(_spec('AM'));
      expect(bytes.sublist(0, 4), [137, 80, 78, 71]);
      final png = img.decodePng(bytes)!;
      expect((png.width, png.height), (88, 88));
    });
  });

  testWidgets('loader failure falls back to initials, never a blank or a throw', (t) async {
    await t.runAsync(() async {
      final r = PinImageRenderer(loader: (_) async => throw Exception('404'));
      final bytes = await r.render(_spec('K', url: 'https://x/a.jpg'));
      expect(img.decodePng(bytes), isNotNull);
    });
  });

  testWidgets('a photo is fetched once per spec (cached)', (t) async {
    await t.runAsync(() async {
      var loads = 0;
      final r = PinImageRenderer(loader: (_) async {
        loads++;
        return _photo();
      });
      final a = await r.render(_spec('K', url: 'https://x/a.jpg'));
      final b = await r.render(_spec('K', url: 'https://x/a.jpg'));
      expect(loads, 1);
      expect(identical(a, b), isTrue);
    });
  });

  testWidgets('the cache is a bounded LRU (checklist 2.12–2.15)', (t) async {
    await t.runAsync(() async {
      var loads = 0;
      final r = PinImageRenderer(maxEntries: 2, loader: (_) async {
        loads++;
        return null;
      });
      await r.render(_spec('A', url: 'u1'));
      await r.render(_spec('B', url: 'u2'));
      await r.render(_spec('A', url: 'u1')); // A is now most recent
      await r.render(_spec('C', url: 'u3')); // evicts B
      expect(r.length, 2);
      await r.render(_spec('A', url: 'u1'));
      expect(loads, 3, reason: 'A stayed cached');
      await r.render(_spec('B', url: 'u2'));
      expect(loads, 4, reason: 'B was evicted');
    });
  });

  testWidgets('clear empties the cache (quick exit)', (t) async {
    await t.runAsync(() async {
      final r = PinImageRenderer();
      await r.render(_spec('A'));
      r.clear();
      expect(r.length, 0);
    });
  });
}
```

- [ ] **Step 2: Run it and confirm it fails.** `flutter test test/features/couple_map/pin_image_renderer_test.dart`. Expected: compilation error.

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/presentation/widgets/pin_image_renderer.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

typedef PinImageLoader = Future<ui.Image?> Function(String url);

@immutable
class PinSpec {
  const PinSpec({
    this.imageUrl,
    required this.initials,
    required this.ring,
    required this.fill,
    required this.onFill,
    required this.sizePx,
  });
  final String? imageUrl;
  final String initials;
  final Color ring;
  final Color fill;
  final Color onFill;
  final int sizePx;

  @override
  bool operator ==(Object o) =>
      o is PinSpec &&
      o.imageUrl == imageUrl &&
      o.initials == initials &&
      o.ring == ring &&
      o.fill == fill &&
      o.onFill == onFill &&
      o.sizePx == sizePx;

  @override
  int get hashCode => Object.hash(imageUrl, initials, ring, fill, onFill, sizePx);
}

/// Renders an avatar pin (photo or initials in a ring) to PNG bytes for a
/// Mapbox point annotation. Results are kept in a bounded LRU; a failed
/// photo falls back to initials and is not retried until evicted.
class PinImageRenderer {
  PinImageRenderer({
    PinImageLoader? loader,
    this.maxEntries = CoupleMapConfig.pinCacheEntries,
  }) : _loader = loader ?? _networkImage;

  final PinImageLoader _loader;
  final int maxEntries;
  final _cache = <PinSpec, Future<Uint8List>>{}; // insertion order = recency

  int get length => _cache.length;

  void clear() => _cache.clear();

  Future<Uint8List> render(PinSpec spec) {
    final hit = _cache.remove(spec);
    if (hit != null) {
      _cache[spec] = hit;
      return hit;
    }
    final drawn = _draw(spec);
    _cache[spec] = drawn;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return drawn;
  }

  Future<Uint8List> _draw(PinSpec s) async {
    ui.Image? photo;
    final url = s.imageUrl;
    if (url != null && url.isNotEmpty) {
      try {
        photo = await _loader(url).timeout(const Duration(seconds: 5));
      } catch (_) {
        photo = null;
      }
    }
    final size = s.sizePx.toDouble();
    final r = size / 2;
    final centre = Offset(r, r);
    final inner = r - size * 0.08;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(centre, r, Paint()..color = s.ring);
    final face = Rect.fromCircle(center: centre, radius: inner);
    if (photo != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(face));
      paintImage(canvas: canvas, rect: face, image: photo, fit: BoxFit.cover);
      canvas.restore();
    } else {
      canvas.drawCircle(centre, inner, Paint()..color = s.fill);
      final tp = TextPainter(
        text: TextSpan(
          text: s.initials,
          style: TextStyle(
            color: s.onFill,
            fontSize: inner * 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
    }
    final image = await recorder.endRecording().toImage(s.sizePx, s.sizePx);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    photo?.dispose();
    return data!.buffer.asUint8List();
  }
}

Future<ui.Image?> _networkImage(String url) {
  final completer = Completer<ui.Image?>();
  final stream = CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (_, __) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// One process-wide cache, so quick exit can clear it without a ref.
final sharedPinImageRenderer = PinImageRenderer();
```

- [ ] **Step 4: Run it and confirm it passes.** The same command.
- [ ] **Step 5: Ledger.**

---

### Task 5: The scene, the map seam, Mapbox, and the fakes

**Files:**
- Create: `lib/features/couple_map/domain/couple_map_scene.dart`, `lib/features/couple_map/presentation/map/couple_map_controller.dart`, `lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart`, `lib/features/couple_map/presentation/providers/couple_map_providers.dart`, `test/features/couple_map/support/fakes.dart`
- Test: `test/features/couple_map/couple_map_scene_test.dart`, `test/features/couple_map/mapbox_wiring_test.dart`

**Interfaces:**
- Consumes: `MapPoint`, `areaRing`, `CoupleMapConfig` (Task 1); `CoupleMapPresence` (Phase 0); `PinImageRenderer` (Task 4).
- Produces:
  - `enum PresenceWho { self, partner }`
  - `class SceneArea { final PresenceWho who; final MapPoint centre; final double opacity; }`
  - `List<SceneArea> sceneAreas(CoupleMapPresence p)`
  - `String areasGeoJson(List<SceneArea> areas, {required bool together})`
  - `enum CoupleMapStyle { standard, satellite }`
  - `abstract class CoupleMapController { Future<void> setStyle(CoupleMapStyle style, {required bool dark}); Future<void> setPresence(List<SceneArea> areas, Map<PresenceWho, Uint8List> avatars, {required Color areaColor, required bool together, required int pinSizePx}); Future<void> fitTo(List<MapPoint> points, {required bool animate}); Future<void> zoomBy(double delta, {required bool animate}); }`
  - `typedef CoupleMapViewBuilder = Widget Function({required CoupleMapStyle style, required bool dark, required ValueChanged<CoupleMapController> onReady, required VoidCallback onLoadError});`
  - Providers: `coupleMapViewBuilderProvider`, `coupleMapTokenProvider` (`Provider<String>`), `pinImageRendererProvider`, `coupleMapPeopleProvider` (`FutureProvider.autoDispose.family<CoupleMapPeople, String>`)
  - `class CoupleMapPeople { selfUrl, selfInitials, partnerUrl, partnerInitials, partnerName }`
  - Test support: `FakeCoupleMapView` (`builder`, `controller`, `built`, `failLoad()`), `FakeCoupleMapController`, `FakePinImageRenderer`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/couple_map_scene_test.dart
import 'dart:convert';

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter_test/flutter_test.dart';

CoupleMapPresence _p({String partnerFreshness = 'fresh', bool partner = true, bool together = false}) =>
    CoupleMapPresence.fromRows([
      {'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'freshness': 'fresh'},
      if (partner)
        {'who': 'partner', 'cell_lat': 5.575, 'cell_lng': -0.208, 'freshness': partnerFreshness,
         'distance_km': together ? 2 : 5, 'together': together},
    ]);

void main() {
  test('one area per person, at the server cell centre', () {
    final a = sceneAreas(_p());
    expect(a.map((x) => x.who), [PresenceWho.self, PresenceWho.partner]);
    expect((a.last.centre.lat, a.last.centre.lng), (5.575, -0.208));
  });

  test('fading reads only as opacity (no time, no dot)', () {
    final a = sceneAreas(_p(partnerFreshness: 'fading'));
    expect(a.last.opacity, CoupleMapConfig.fadingOpacity);
    expect(a.first.opacity, 1.0);
  });

  test('no partner row: only my area', () {
    expect(sceneAreas(_p(partner: false)).map((x) => x.who), [PresenceWho.self]);
  });

  test('my row without a cell (accuracy too low): nothing drawn', () {
    final p = CoupleMapPresence.fromRows([{'who': 'self', 'city': 'Accra', 'freshness': 'fresh'}]);
    expect(sceneAreas(p), isEmpty);
  });

  test('GeoJSON: polygons only, carrying opacity; together draws one shared area', () {
    final apart = jsonDecode(areasGeoJson(sceneAreas(_p()), together: false)) as Map;
    final features = apart['features'] as List;
    expect(features, hasLength(2));
    for (final f in features) {
      expect(f['geometry']['type'], 'Polygon');
      expect(f['properties']['opacity'], isA<num>());
    }
    final together = jsonDecode(areasGeoJson(sceneAreas(_p(together: true)), together: true)) as Map;
    expect(together['features'], hasLength(1));
  });
}
```

```dart
// test/features/couple_map/mapbox_wiring_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src() => File('lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart').readAsStringSync();

void main() {
  test('the location puck is turned off explicitly (spec §6.3)', () {
    expect(_src().contains('LocationComponentSettings(enabled: false)'), isTrue);
  });

  test('the map canvas is excluded from semantics (spec §3.5)', () {
    expect(_src().contains('ExcludeSemantics('), isTrue);
  });

  test('the map takes its own gestures inside the swipeable tabs', () {
    expect(_src().contains('EagerGestureRecognizer'), isTrue);
  });

  test('presence is re-applied after a style change (Review Focus 2)', () {
    final s = _src();
    final loaded = s.substring(s.indexOf('Future<void> _styleLoaded()'));
    expect(loaded.contains('_last'), isTrue);
  });

  test('only a style failure counts as "no map" (tile errors are not)', () {
    expect(_src().contains('MapLoadErrorType.STYLE'), isTrue);
  });

  test('the controller goes inert when its widget is disposed (checklist 2.10)', () {
    final s = _src();
    final dispose = s.substring(s.indexOf('void dispose()'));
    expect(dispose.contains('_map = null'), isTrue);
  });

  test('the Mapbox logo and attribution are lifted above the card (Mapbox terms)', () {
    final s = _src();
    expect(s.contains('LogoSettings('), isTrue);
    expect(s.contains('AttributionSettings('), isTrue);
  });

  test('areas are fills, never point circles; nothing is logged (checklist 4.4)', () {
    final s = _src();
    expect(s.contains('FillLayer('), isTrue);
    expect(s.contains('CircleLayer('), isFalse);
    expect(RegExp(r'\b(print|debugPrint)\(').hasMatch(s), isFalse);
  });
}
```

- [ ] **Step 2: Run them and confirm they fail.** `flutter test test/features/couple_map/couple_map_scene_test.dart test/features/couple_map/mapbox_wiring_test.dart`. Expected: a compilation error, and file-not-found errors.

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/domain/couple_map_scene.dart
import 'dart:convert';

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/foundation.dart';

enum PresenceWho { self, partner }

@immutable
class SceneArea {
  const SceneArea({required this.who, required this.centre, required this.opacity});
  final PresenceWho who;
  final MapPoint centre;
  final double opacity;
}

double _opacity(PresenceFreshness f) =>
    f == PresenceFreshness.fresh ? 1.0 : CoupleMapConfig.fadingOpacity;

SceneArea? _area(PresenceWho who, PresenceArea? a) {
  final lat = a?.cellLat;
  final lng = a?.cellLng;
  if (a == null || lat == null || lng == null) return null;
  return SceneArea(who: who, centre: MapPoint(lat, lng), opacity: _opacity(a.freshness));
}

/// What the map draws: at most my area and my partner's, at server cell
/// centres. A row without a cell (only a city) draws nothing.
List<SceneArea> sceneAreas(CoupleMapPresence p) => [
  if (_area(PresenceWho.self, p.self) case final s?) s,
  if (_area(PresenceWho.partner, p.partner) case final s?) s,
];

/// The areas as a GeoJSON FeatureCollection of polygons. Together (same
/// or adjacent cell) draws one shared area, under both avatars.
String areasGeoJson(List<SceneArea> areas, {required bool together}) {
  final drawn = together && areas.length > 1 ? [areas.first] : areas;
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final a in drawn)
        {
          'type': 'Feature',
          'properties': {'who': a.who.name, 'opacity': a.opacity},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [for (final p in areaRing(a.centre)) [p.lng, p.lat]],
            ],
          },
        },
    ],
  });
}
```

```dart
// lib/features/couple_map/presentation/map/couple_map_controller.dart
import 'dart:typed_data';

import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:flutter/widgets.dart';

enum CoupleMapStyle { standard, satellite }

/// The seam between the tab and the map engine (spec §6.2). Mapbox in the
/// app; a recording fake in tests.
abstract class CoupleMapController {
  Future<void> setStyle(CoupleMapStyle style, {required bool dark});

  Future<void> setPresence(
    List<SceneArea> areas,
    Map<PresenceWho, Uint8List> avatars, {
    required Color areaColor,
    required bool together,
    required int pinSizePx,
  });

  Future<void> fitTo(List<MapPoint> points, {required bool animate});

  Future<void> zoomBy(double delta, {required bool animate});
}

typedef CoupleMapViewBuilder =
    Widget Function({
      required CoupleMapStyle style,
      required bool dark,
      required ValueChanged<CoupleMapController> onReady,
      required VoidCallback onLoadError,
    });
```

```dart
// lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart
import 'dart:typed_data';

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

Widget mapboxCoupleMapViewBuilder({
  required CoupleMapStyle style,
  required bool dark,
  required ValueChanged<CoupleMapController> onReady,
  required VoidCallback onLoadError,
}) => MapboxCoupleMapView(
  style: style,
  dark: dark,
  onReady: onReady,
  onLoadError: onLoadError,
);

class MapboxCoupleMapView extends StatefulWidget {
  const MapboxCoupleMapView({
    super.key,
    required this.style,
    required this.dark,
    required this.onReady,
    required this.onLoadError,
  });
  final CoupleMapStyle style;
  final bool dark;
  final ValueChanged<CoupleMapController> onReady;
  final VoidCallback onLoadError;

  @override
  State<MapboxCoupleMapView> createState() => _MapboxCoupleMapViewState();
}

typedef _Presence =
    ({
      List<SceneArea> areas,
      Map<PresenceWho, Uint8List> avatars,
      Color areaColor,
      bool together,
      int pinSizePx,
    });

class _MapboxCoupleMapViewState extends State<MapboxCoupleMapView>
    implements CoupleMapController {
  static const _source = 'couple-presence-areas';
  static const _fill = 'couple-presence-fill';
  static const _outline = 'couple-presence-outline';

  MapboxMap? _map;
  PointAnnotationManager? _pins;
  late CoupleMapStyle _style = widget.style;
  late bool _dark = widget.dark;

  /// The last presence, re-applied after a style change: a new style drops
  /// every runtime source and layer.
  _Presence? _last;

  /// Sources and layers can be added only once the style has loaded;
  /// onMapCreated usually fires first.
  bool _styleReady = false;

  @override
  void dispose() {
    // The tab may still hold this controller: make every call a no-op.
    _map = null;
    _pins = null;
    super.dispose();
  }

  static String _uri(CoupleMapStyle s) => switch (s) {
    CoupleMapStyle.standard => MapboxStyles.STANDARD,
    CoupleMapStyle.satellite => MapboxStyles.STANDARD_SATELLITE,
  };

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MapWidget(
        key: const ValueKey('couple-map'),
        styleUri: _uri(_style),
        cameraOptions: CameraOptions(zoom: 1.5),
        // The map sits in a swipeable TabBarView: it takes its own pans.
        gestureRecognizers: {
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        onMapCreated: _created,
        onStyleLoadedListener: (_) => _styleLoaded(),
        // Only a style failure means "no map". A tile, sprite or glyph
        // error on a flaky connection must not swap the map for the list.
        onMapLoadErrorListener: (e) {
          if (e.type == MapLoadErrorType.STYLE) widget.onLoadError();
        },
      ),
    );
  }

  Future<void> _created(MapboxMap map) async {
    _map = map;
    // Never the "you are here" puck: it would draw a raw position (§6.3).
    await map.location.updateSettings(LocationComponentSettings(enabled: false));
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    // Below the right-hand column (3 buttons, a gap, 2 zoom buttons):
    // 16 + 5×44 + 3×8 + 16 + 16 = 292. Shows only when rotated.
    await map.compass.updateSettings(
      CompassSettings(position: OrnamentPosition.TOP_RIGHT, marginTop: 292, marginRight: 16),
    );
    // Mapbox's terms require the logo and attribution to stay visible: lift
    // them above the distance card.
    await map.logo.updateSettings(
      LogoSettings(position: OrnamentPosition.BOTTOM_LEFT, marginBottom: CoupleMapConfig.ornamentLift, marginLeft: 16),
    );
    await map.attribution.updateSettings(
      AttributionSettings(position: OrnamentPosition.BOTTOM_RIGHT, marginBottom: CoupleMapConfig.ornamentLift, marginRight: 16),
    );
    // Flat: areas stay round and readable.
    await map.gestures.updateSettings(GesturesSettings(pitchEnabled: false));
    _pins = await map.annotations.createPointAnnotationManager();
    if (mounted) widget.onReady(this);
  }

  Future<void> _styleLoaded() async {
    final map = _map;
    if (map == null) return;
    _styleReady = true;
    if (_style == CoupleMapStyle.standard) {
      await map.style.setStyleImportConfigProperty('basemap', 'lightPreset', _dark ? 'night' : 'day');
    }
    final last = _last;
    if (last != null) await _apply(last);
  }

  @override
  Future<void> setStyle(CoupleMapStyle style, {required bool dark}) async {
    final map = _map;
    final changed = style != _style;
    _style = style;
    _dark = dark;
    if (map == null) return;
    if (changed) {
      _styleReady = false;
      await map.loadStyleURI(_uri(style)); // _styleLoaded re-applies presence
    } else if (style == CoupleMapStyle.standard) {
      await map.style.setStyleImportConfigProperty('basemap', 'lightPreset', dark ? 'night' : 'day');
    }
  }

  @override
  Future<void> setPresence(
    List<SceneArea> areas,
    Map<PresenceWho, Uint8List> avatars, {
    required Color areaColor,
    required bool together,
    required int pinSizePx,
  }) async {
    final p = (areas: areas, avatars: avatars, areaColor: areaColor, together: together, pinSizePx: pinSizePx);
    _last = p;
    await _apply(p);
  }

  Future<void> _apply(_Presence p) async {
    final map = _map;
    final pins = _pins;
    if (map == null || pins == null || !_styleReady) return;
    try {
      await _draw(map, pins, p);
    } catch (_) {
      // A style swapped mid-draw: _styleLoaded re-applies _last. No log
      // (it would carry nothing useful and must never carry a place).
    }
  }

  Future<void> _draw(MapboxMap map, PointAnnotationManager pins, _Presence p) async {
    final style = map.style;
    for (final layer in [_outline, _fill]) {
      if (await style.styleLayerExists(layer)) await style.removeStyleLayer(layer);
    }
    if (await style.styleSourceExists(_source)) await style.removeStyleSource(_source);
    await style.addSource(GeoJsonSource(id: _source, data: areasGeoJson(p.areas, together: p.together)));
    await style.addLayer(FillLayer(
      id: _fill,
      sourceId: _source,
      fillColor: p.areaColor.toARGB32(),
      fillOpacityExpression: ['*', 0.22, ['get', 'opacity']],
    ));
    await style.addLayer(LineLayer(
      id: _outline,
      sourceId: _source,
      lineColor: p.areaColor.toARGB32(),
      lineWidth: 1.5,
      lineOpacityExpression: ['*', 0.6, ['get', 'opacity']],
    ));
    await pins.deleteAll();
    // iconOffset is in image pixels (the PNG is pinSize × dpr).
    final offset = p.pinSizePx * 0.6;
    await pins.createMulti([
      for (final a in p.areas)
        if (p.avatars[a.who] case final image?)
          PointAnnotationOptions(
            geometry: Point(coordinates: Position(a.centre.lng, a.centre.lat)),
            image: image,
            iconOpacity: a.opacity,
            iconOffset: p.together ? [a.who == PresenceWho.self ? -offset : offset, 0] : [0, 0],
          ),
    ]);
  }

  @override
  Future<void> fitTo(List<MapPoint> points, {required bool animate}) async {
    final map = _map;
    if (map == null || points.isEmpty) return;
    const pad = CoupleMapConfig.fitPadding;
    final camera = points.length == 1
        ? CameraOptions(
            center: Point(coordinates: Position(points.first.lng, points.first.lat)),
            zoom: CoupleMapConfig.singleAreaZoom,
          )
        : await map.cameraForCoordinatesPadding(
            [for (final p in points) Point(coordinates: Position(p.lng, p.lat))],
            CameraOptions(),
            MbxEdgeInsets(top: pad, left: pad, bottom: pad * 2, right: pad),
            CoupleMapConfig.fitMaxZoom,
            null,
          );
    animate
        ? await map.flyTo(camera, MapAnimationOptions(duration: 800))
        : await map.setCamera(camera);
  }

  @override
  Future<void> zoomBy(double delta, {required bool animate}) async {
    final map = _map;
    if (map == null) return;
    final state = await map.getCameraState();
    final camera = CameraOptions(zoom: state.zoom + delta);
    animate
        ? await map.easeTo(camera, MapAnimationOptions(duration: 250))
        : await map.setCamera(camera);
  }
}
```

(If `Color.toARGB32()` isn't available on this Flutter version, use `.value` and ledger it. If `loadStyleURI` behaves differently, use `map.style.setStyleURI` and ledger it.)

```dart
// lib/features/couple_map/presentation/providers/couple_map_providers.dart
import 'package:attune/core/config/env.dart';
import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/map/mapbox_couple_map_view.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' as quiz;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coupleMapViewBuilderProvider = Provider<CoupleMapViewBuilder>(
  (ref) => mapboxCoupleMapViewBuilder,
);

/// Empty means no map: the list content shows in its place.
final coupleMapTokenProvider = Provider<String>((ref) => Environment.mapboxAccessToken);

final pinImageRendererProvider = Provider<PinImageRenderer>((ref) => sharedPinImageRenderer);

@immutable
class CoupleMapPeople {
  const CoupleMapPeople({
    this.selfUrl,
    required this.selfInitials,
    this.partnerUrl,
    required this.partnerInitials,
    required this.partnerName,
  });
  final String? selfUrl;
  final String selfInitials;
  final String? partnerUrl;
  final String partnerInitials;
  final String partnerName;
}

/// Names and avatars for the pins and the card. Never throws: a missing
/// profile shows initials.
final coupleMapPeopleProvider = FutureProvider.autoDispose
    .family<CoupleMapPeople, String>((ref, relationshipId) async {
      Future<T?> safe<T>(Future<T> f) async {
        try {
          return await f;
        } catch (_) {
          return null;
        }
      }

      final me = await safe(ref.watch(currentUserProfileProvider.future));
      final conversations =
          await safe(ref.watch(conversationsProvider.future)) ?? const [];
      final partnerConversation = conversations
          .where((c) => c.relationshipId == relationshipId)
          .firstOrNull;
      final partnerName =
          await safe(ref.watch(quiz.partnerNameProvider.future)) ??
          partnerConversation?.name;
      return CoupleMapPeople(
        selfUrl: me?.avatarUrl,
        selfInitials: initialsOf(me?.displayName ?? me?.username),
        partnerUrl: partnerConversation?.avatarUrl,
        partnerInitials: initialsOf(partnerName),
        partnerName: partnerName ?? 'your partner',
      );
    });
```

(`currentUserProfileProvider` is generated in `lib/core/providers/profile_providers/profile_provider.g.dart`, a `part` of `profile_provider.dart`. Import the library file.)

```dart
// test/features/couple_map/support/fakes.dart
import 'dart:typed_data';

import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:flutter/material.dart';

class FakeCoupleMapController implements CoupleMapController {
  final styles = <(CoupleMapStyle, bool)>[];
  final presences = <(List<SceneArea>, Map<PresenceWho, Uint8List>, bool)>[];
  final fits = <(List<MapPoint>, bool)>[];
  final zooms = <(double, bool)>[];

  List<SceneArea> get lastAreas => presences.last.$1;

  @override
  Future<void> setStyle(CoupleMapStyle style, {required bool dark}) async => styles.add((style, dark));

  @override
  Future<void> setPresence(List<SceneArea> areas, Map<PresenceWho, Uint8List> avatars,
          {required Color areaColor, required bool together, required int pinSizePx}) async =>
      presences.add((areas, avatars, together));

  @override
  Future<void> fitTo(List<MapPoint> points, {required bool animate}) async => fits.add((points, animate));

  @override
  Future<void> zoomBy(double delta, {required bool animate}) async => zooms.add((delta, animate));
}

class FakeCoupleMapView {
  final controller = FakeCoupleMapController();
  int built = 0;
  CoupleMapStyle? builtStyle;
  bool? builtDark;
  VoidCallback? _fail;

  void failLoad() => _fail?.call();

  CoupleMapViewBuilder get builder => ({
        required CoupleMapStyle style,
        required bool dark,
        required ValueChanged<CoupleMapController> onReady,
        required VoidCallback onLoadError,
      }) {
        built++;
        builtStyle = style;
        builtDark = dark;
        _fail = onLoadError;
        return _FakeMap(onReady: () => onReady(controller));
      };
}

class _FakeMap extends StatefulWidget {
  const _FakeMap({required this.onReady});
  final VoidCallback onReady;
  @override
  State<_FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<_FakeMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady());
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFFDDE5EC), key: ValueKey('fake-map'));
}

class FakePinImageRenderer extends PinImageRenderer {
  final rendered = <PinSpec>[];
  final _kept = <PinSpec>{};
  @override
  Future<Uint8List> render(PinSpec spec) async {
    rendered.add(spec);
    _kept.add(spec);
    return Uint8List.fromList(spec.initials.codeUnits);
  }

  @override
  int get length => _kept.length;

  @override
  void clear() => _kept.clear();
}
```

- [ ] **Step 4: Run them and confirm they pass,** together with `flutter analyze lib/features/couple_map 2>&1 | grep -E "^\s*(error|warning) "`, which should print nothing.
- [ ] **Step 5: Ledger.**

---

### Task 6: Glass surfaces, the sharing chip, and the Sharing sheet

**Files:**
- Create: `lib/features/couple_map/presentation/widgets/glass_surface.dart`, `lib/features/couple_map/presentation/widgets/sharing_chip.dart`, `lib/features/couple_map/presentation/widgets/sharing_sheet.dart`
- Test: `test/features/couple_map/sharing_sheet_test.dart`, `test/features/couple_map/sharing_chip_test.dart`

**Interfaces:**
- Consumes: `presenceStateProvider`, `presenceRepositoryProvider`, `coupleMapPresenceProvider` (Phase 0); `pauseRemainingLabel` (Task 2).
- Produces:
  - `GlassPanel({required Widget child, BorderRadius borderRadius, EdgeInsetsGeometry padding})`
  - `GlassIconButton({required IconData icon, required String tooltip, required VoidCallback? onPressed})`
  - `SharingChip({required String label, required PresenceStatus? status, required bool locationOff, required VoidCallback onTap})` (status null = not read yet)
  - `Future<void> showSharingSheet(BuildContext context, {required String relationshipId})`
  - `SharingSheet({required String relationshipId})`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/sharing_chip_test.dart
import 'package:attune/features/couple_map/presentation/widgets/sharing_chip.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(home: Scaffold(body: Center(child: w))),
    ));

void main() {
  testWidgets('shows the label, is a 44 dp target, says what it does, and taps', (t) async {
    final semantics = t.ensureSemantics();
    var taps = 0;
    await _pump(t, SharingChip(label: 'Sharing my area with Kofi', status: PresenceStatus.sharing, locationOff: false, onTap: () => taps++));
    expect(find.text('Sharing my area with Kofi'), findsOneWidget);
    expect(t.getSize(find.byType(SharingChip)).height, greaterThanOrEqualTo(44));
    final chip = find.bySemanticsLabel(RegExp('Sharing: Sharing my area with Kofi'));
    expect(chip, findsOneWidget);
    // Activatable by a screen reader, not just announced (checklist 5.6).
    expect(t.getSemantics(chip), containsSemantics(hasTapAction: true));
    await t.tap(find.byType(SharingChip));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('a long label ellipsizes instead of overflowing at 320 dp', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t, SharingChip(label: 'Sharing my area with Kwabena Ofori-Atta Mensah', status: PresenceStatus.sharing, locationOff: false, onTap: () {}));
    expect(t.takeException(), isNull);
  });
}
```

```dart
// test/features/couple_map/sharing_sheet_test.dart
import 'package:attune/features/couple_map/presentation/widgets/sharing_sheet.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../location/presence_repository_test.dart' show FakePresenceGateway, FakeSampler;

const _self = {'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'freshness': 'fresh'};

Future<FakePresenceGateway> _pump(WidgetTester t, List<Map<String, Object?>> rows,
    {Map<String, dynamic Function(Map<String, dynamic>)> handlers = const {}, ValueNotifier<bool>? shown}) async {
  final visible = shown ?? ValueNotifier(true);
  final g = FakePresenceGateway({'couple_map_presence': (_) => rows, ...handlers});
  await t.pumpWidget(ProviderScope(
    overrides: [
      presenceGatewayProvider.overrideWithValue(g),
      presenceSamplerProvider.overrideWithValue(FakeSampler(next: const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40))),
      presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, show, __) => show ? const SharingSheet(relationshipId: 'r1') : const SizedBox(),
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return g;
}

Iterable<String> _fns(FakePresenceGateway g) => g.calls.map((c) => c.$1);

void main() {
  testWidgets('off: one switch, no pause rows; turning it on opts in and records', (t) async {
    final g = await _pump(t, const []);
    expect(find.text('Share my approximate area'), findsOneWidget);
    expect(find.text('Pause for 1 hour'), findsNothing);
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(_fns(g), containsAllInOrder(['start_presence', 'record_presence']));
  });

  testWidgets('sharing: the three pause rows; each sends its end', (t) async {
    final g = await _pump(t, const [_self]);
    for (final row in ['Pause for 1 hour', 'Pause for 8 hours', 'Pause until I resume']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    await t.tap(find.text('Pause for 1 hour'));
    await t.pumpAndSettle();
    final hour = g.calls.lastWhere((c) => c.$1 == 'set_presence_pause').$2['p_until'] as String;
    expect(DateTime.parse(hour).difference(DateTime.now().toUtc()).inMinutes, inInclusiveRange(58, 60));
  });

  testWidgets('pause until I resume sends infinity', (t) async {
    final g = await _pump(t, const [_self]);
    await t.tap(find.text('Pause until I resume'));
    await t.pumpAndSettle();
    expect(g.calls.lastWhere((c) => c.$1 == 'set_presence_pause').$2['p_until'], 'infinity');
  });

  testWidgets('paused: Resume replaces the pause rows and clears the pause', (t) async {
    final g = await _pump(t, const [{'who': 'self', 'freshness': 'fresh', 'my_paused_until': 'infinity'}]);
    expect(find.text('Pause for 1 hour'), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
    await t.tap(find.text('Resume'));
    await t.pumpAndSettle();
    final pause = g.calls.lastWhere((c) => c.$1 == 'set_presence_pause');
    expect(pause.$2.containsKey('p_until'), isTrue);
    expect(pause.$2['p_until'], isNull);
  });

  testWidgets('a failure says so in plain words (spec §9 2.4)', (t) async {
    await _pump(t, const [_self], handlers: {'set_presence_pause': (_) => throw Exception('offline')});
    await t.tap(find.text('Pause for 8 hours'));
    await t.pumpAndSettle();
    expect(find.text("Couldn't update your area. Try again."), findsOneWidget);
  });

  testWidgets('dismissing the sheet mid-call is safe and the map still re-reads', (t) async {
    final shown = ValueNotifier(true);
    final g = await _pump(t, const [_self], shown: shown, handlers: {
      'set_presence_pause': (_) => Future<void>.delayed(const Duration(milliseconds: 50)),
    });
    final reads = g.calls.where((c) => c.$1 == 'couple_map_presence').length;
    await t.tap(find.text('Pause for 1 hour'));
    shown.value = false; // the sheet is swiped away before the RPC returns
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
    expect(g.calls.where((c) => c.$1 == 'couple_map_presence').length, greaterThan(reads),
        reason: 'the map re-reads even though the sheet is gone');
  });

  testWidgets('pause and resume rows carry no external-link glyph', (t) async {
    await _pump(t, const [_self]);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
  });

  testWidgets('explains symmetry without naming the partner\'s state', (t) async {
    await _pump(t, const [_self]);
    expect(find.text('Pausing hides you from each other. Nobody is told.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them and confirm they fail.** `flutter test test/features/couple_map/sharing_chip_test.dart test/features/couple_map/sharing_sheet_test.dart`. Expected: compilation error.

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/presentation/widgets/glass_surface.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:flutter/material.dart';

/// The map's floating surface: translucent, not blurred. A BackdropFilter
/// over the Mapbox platform view is unreliable on Android hybrid
/// composition and costly (spec §7 risk); a 90 % surface with a hairline
/// border reads the same and follows the theme.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = BorderRadiusTokens.lgAll,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.9),
        borderRadius: borderRadius,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6), width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A 44 dp round glass button with a tooltip and a matching label.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const size = CoupleMapConfig.glassButtonSize;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        // excludeSemantics drops the InkWell's action: give it back.
        onTap: onPressed,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: GlassPanel(
            borderRadius: const BorderRadius.all(Radius.circular(size / 2)),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: Icon(icon, size: 22, color: cs.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

```dart
// lib/features/couple_map/presentation/widgets/sharing_chip.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/presentation/widgets/glass_surface.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/material.dart';

/// Top left, always visible: who can see you right now (spec §3.1).
class SharingChip extends StatelessWidget {
  const SharingChip({
    super.key,
    required this.label,
    required this.status,
    required this.locationOff,
    required this.onTap,
  });
  final String label;

  /// Null while my state hasn't been read: a neutral icon, no claim.
  final PresenceStatus? status;
  final bool locationOff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      null => (Icons.location_searching, cs.onSurfaceVariant),
      PresenceStatus.off => (Icons.location_off_outlined, cs.onSurfaceVariant),
      PresenceStatus.paused => (Icons.pause_circle_outline, cs.onSurfaceVariant),
      PresenceStatus.sharing when locationOff => (Icons.location_disabled, cs.error),
      PresenceStatus.sharing => (Icons.location_on, cs.primary),
    };
    return Semantics(
      button: true,
      label: 'Sharing: $label',
      hint: 'Opens sharing settings',
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: GlassPanel(
          borderRadius: BorderRadiusTokens.floatingNavAll,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadiusTokens.floatingNavAll,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.smMd),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

(Check that `Spacing.smMd` exists; it's in `design_tokens.dart` line 11. If its value makes the chip shorter than 44, `minHeight` covers it.)

```dart
// lib/features/couple_map/presentation/widgets/sharing_sheet.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/location/data/presence_repository.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const sharingErrorCopy = "Couldn't update your area. Try again.";

Future<void> showSharingSheet(BuildContext context, {required String relationshipId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SharingSheet(relationshipId: relationshipId),
    );

/// Share on or off, and pause or resume (spec §3.1). Pause is symmetric
/// and silent: nobody is told, and you can't see them while it lasts.
class SharingSheet extends ConsumerStatefulWidget {
  const SharingSheet({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<SharingSheet> createState() => _SharingSheetState();
}

class _SharingSheetState extends ConsumerState<SharingSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(PresenceRepository r) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Captured now: the sheet may be dismissed before the call returns, and
    // the map must still re-read (ref can't be used after dispose).
    final container = ProviderScope.containerOf(context);
    try {
      await action(container.read(presenceRepositoryProvider));
    } catch (_) {
      if (mounted) context.showErrorSnackbar(sharingErrorCopy);
    } finally {
      container.invalidate(coupleMapPresenceProvider(widget.relationshipId));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.relationshipId;
    final theme = Theme.of(context);
    final state = ref.watch(presenceStateProvider(rel)).valueOrNull ??
        const PresenceState(PresenceStatus.off);
    final until = state.pausedUntil;
    final left = until?.difference(DateTime.now());
    Widget pauseRow(String title, Duration? d, {required bool last}) => InfoRowWidget(
          title: title,
          subtitle: d == null ? 'Until you turn it back on' : 'Then back at your next open',
          icon: Icons.pause_outlined,
          showAvatar: false,
          showTrailingArrow: false,
          // Without this InfoRowWidget adds an "open in new" glyph.
          disableTrailing: true,
          showDivider: !last,
          onTap: _busy ? null : () => _run((r) => r.pause(rel, d)),
        );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomSheetHeader(title: 'Sharing'),
          CardInkWell(
            child: Column(
              children: [
                InfoRowWidget(
                  title: 'Share my approximate area',
                  subtitle: 'Your neighbourhood, never your address. Updates when you open Attune.',
                  icon: Icons.location_on_outlined,
                  isToggleItem: true,
                  toggleValue: state.isOn,
                  showAvatar: false,
                  showDivider: state.isOn,
                  onToggleChanged: (v) {
                    if (_busy) return;
                    _run((r) => v ? r.startSharing(rel) : r.stopSharing(rel));
                  },
                ),
                if (state.status == PresenceStatus.sharing) ...[
                  pauseRow('Pause for 1 hour', const Duration(hours: 1), last: false),
                  pauseRow('Pause for 8 hours', const Duration(hours: 8), last: false),
                  pauseRow('Pause until I resume', null, last: true),
                ],
                if (state.status == PresenceStatus.paused)
                  InfoRowWidget(
                    title: 'Resume',
                    subtitle: left == null || left.isNegative
                        ? 'Paused until you resume'
                        : 'Paused · ${pauseRemainingLabel(left)} left',
                    icon: Icons.play_arrow_rounded,
                    showAvatar: false,
                    showTrailingArrow: false,
                    disableTrailing: true,
                    showDivider: false,
                    onTap: _busy ? null : () => _run((r) => r.resume(rel)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
            child: Text(
              'Pausing hides you from each other. Nobody is told.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
```

(The tests find the switch with `find.byType(Switch)`. If `AppToggleSwitch` doesn't wrap a Material `Switch`, find it by type `AppToggleSwitch` and call its callback instead, and ledger it.)

- [ ] **Step 4: Run them and confirm they pass.**
- [ ] **Step 5: Ledger.**

---

### Task 7: The distance card, the notice card, and the list content

**Files:**
- Create: `lib/features/couple_map/presentation/widgets/distance_card.dart`, `lib/features/couple_map/presentation/widgets/couple_map_list_sheet.dart`
- Test: `test/features/couple_map/distance_card_test.dart`, `test/features/couple_map/couple_map_list_test.dart`

**Interfaces:**
- Consumes: `DistanceCardCopy`, `CoupleMapNotice`, `noticeText`, `formatClock` (Task 2); `GlassPanel` (Task 6); `CoupleMapPeople` (Task 5).
- Produces:
  - `DistanceCard({required DistanceCardCopy copy, required CoupleMapPeople people})`
  - `NoticeCard({required CoupleMapNotice notice, VoidCallback? onTap})`
  - `LoadingCard()`
  - `RetryCard({required VoidCallback onTap})`, which reads "Couldn't load your map. Try again." 
  - `CoupleMapListContent({required CoupleMapPresence presence, required String partnerName, required CoupleMapNotice? notice, required DateTime now, VoidCallback? onNoticeTap})`
  - `Future<void> showCoupleMapListSheet(BuildContext context, {required String relationshipId})`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/distance_card_test.dart
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/widgets/distance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _people = CoupleMapPeople(selfInitials: 'AM', partnerInitials: 'K', partnerName: 'Kofi');

Future<void> _pump(WidgetTester t, Widget w, {double width = 390}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: w))),
  ));
}

void main() {
  testWidgets('headline and " · " details; one readable label', (t) async {
    final semantics = t.ensureSemantics();
    await _pump(t, const DistanceCard(
      copy: DistanceCardCopy(headline: '8 hours by road', details: '412 km apart · in Accra', together: false),
      people: _people,
    ));
    expect(find.text('8 hours by road'), findsOneWidget);
    expect(find.text('412 km apart · in Accra'), findsOneWidget);
    expect(find.bySemanticsLabel('8 hours by road. 412 km apart · in Accra'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('together: a warm accent, no details line', (t) async {
    await _pump(t, const DistanceCard(
      copy: DistanceCardCopy(headline: 'Together · Accra', details: '', together: true),
      people: _people,
    ));
    final headline = t.widget<Text>(find.text('Together · Accra'));
    final primary = Theme.of(t.element(find.text('Together · Accra'))).colorScheme.primary;
    expect(headline.style?.color, primary);
  });

  testWidgets('long copy never overflows at 320 dp', (t) async {
    await _pump(t, const DistanceCard(
      copy: DistanceCardCopy(headline: "12 days until you're together", details: '5.1k km apart · in Llanfairpwllgwyngyll · 11:15pm there', together: false),
      people: _people,
    ), width: 320);
    expect(t.takeException(), isNull);
  });

  testWidgets('notice: the neutral line is not a button; the onboarding line is', (t) async {
    await _pump(t, const NoticeCard(notice: CoupleMapNotice.justYou));
    expect(find.text('Just you on the map right now'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    var taps = 0;
    await _pump(t, NoticeCard(notice: CoupleMapNotice.notSharing, onTap: () => taps++));
    await t.tap(find.byType(NoticeCard));
    expect(taps, 1);
  });
}
```

```dart
// test/features/couple_map/couple_map_list_test.dart
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/widgets/couple_map_list_sheet.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, CoupleMapPresence p, CoupleMapNotice? n) => t.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: CoupleMapListContent(presence: p, partnerName: 'Kofi', notice: n, now: DateTime.utc(2026, 9, 2, 14, 15)),
        ),
      ),
    ));

void main() {
  testWidgets('presence rows: "{Partner}" with "city · time there" (spec §3.5)', (t) async {
    final p = CoupleMapPresence.fromRows([
      {'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'city': 'Accra', 'freshness': 'fresh'},
      {'who': 'partner', 'cell_lat': 51.505, 'cell_lng': -0.121, 'city': 'London', 'utc_offset_minutes': 60,
       'freshness': 'fresh', 'distance_km': 5100, 'together': false},
    ]);
    await _pump(t, p, null);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Accra'), findsOneWidget);
    expect(find.text('Kofi'), findsOneWidget);
    expect(find.text('London · 3:15pm there'), findsOneWidget);
  });

  testWidgets('no partner: the same neutral line as the map, nothing else about them', (t) async {
    final p = CoupleMapPresence.fromRows([{'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'freshness': 'fresh'}]);
    await _pump(t, p, CoupleMapNotice.justYou);
    expect(find.text('Just you on the map right now'), findsOneWidget);
    expect(find.text('Kofi'), findsNothing);
  });

  testWidgets('never a time of update, an online state, or "last seen"', (t) async {
    final p = CoupleMapPresence.fromRows([
      {'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'freshness': 'fresh'},
      {'who': 'partner', 'cell_lat': 5.6, 'cell_lng': -0.2, 'freshness': 'fading', 'distance_km': 5, 'together': false},
    ]);
    await _pump(t, p, null);
    for (final banned in ['ago', 'online', 'last seen', 'updated']) {
      expect(find.textContaining(RegExp(banned, caseSensitive: false)), findsNothing, reason: banned);
    }
  });
}
```

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/presentation/widgets/distance_card.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/widgets/glass_surface.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({this.url, required this.initials});
  final String? url;
  final String initials;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final u = url;
    return CircleAvatar(
      radius: 16,
      backgroundColor: cs.surface,
      child: CircleAvatar(
        radius: 14,
        backgroundColor: cs.primaryContainer,
        foregroundImage: u == null || u.isEmpty ? null : CachedNetworkImageProvider(u),
        child: Text(initials, style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
      ),
    );
  }
}

/// Bottom of the map: both avatars and how far apart, in words (§3.1).
class DistanceCard extends StatelessWidget {
  const DistanceCard({super.key, required this.copy, required this.people});
  final DistanceCardCopy copy;
  final CoupleMapPeople people;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      container: true,
      label: copy.details.isEmpty ? copy.headline : '${copy.headline}. ${copy.details}',
      excludeSemantics: true,
      child: GlassPanel(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 32,
              child: Stack(children: [
                _MiniAvatar(url: people.selfUrl, initials: people.selfInitials),
                Positioned(left: 20, child: _MiniAvatar(url: people.partnerUrl, initials: people.partnerInitials)),
              ]),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: copy.together ? cs.primary : cs.onSurface,
                    ),
                  ),
                  if (copy.details.isNotEmpty)
                    Text(
                      copy.details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one line shown instead of the card (spec §3.4). Tappable only when
/// it leads somewhere I can act: my own sharing or my own location.
class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.notice, this.onTap});
  final CoupleMapNotice notice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final body = Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Icon(
            notice == CoupleMapNotice.justYou ? Icons.person_pin_circle_outlined : Icons.near_me_outlined,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(child: Text(noticeText(notice), style: theme.textTheme.bodyMedium)),
          if (onTap != null) Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
    return GlassPanel(
      child: onTap == null
          ? body
          : Material(
              type: MaterialType.transparency,
              child: InkWell(borderRadius: BorderRadiusTokens.lgAll, onTap: onTap, child: body),
            ),
    );
  }
}

/// A failed first read with nothing to show (checklist 1.3): plain copy,
/// tap to retry.
class RetryCard extends StatelessWidget {
  const RetryCard({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassPanel(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadiusTokens.lgAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(children: [
              Icon(Icons.refresh, color: cs.onSurfaceVariant),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text("Couldn't load your map. Try again.", style: Theme.of(context).textTheme.bodyMedium),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shown within the first frame while presence loads (checklist 5.2).
class LoadingCard extends StatelessWidget {
  const LoadingCard({super.key});
  @override
  Widget build(BuildContext context) => GlassPanel(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(children: [
          const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Spacing.md),
          Text('Loading your map…', style: Theme.of(context).textTheme.bodyMedium),
        ]),
      );
}
```

```dart
// lib/features/couple_map/presentation/widgets/couple_map_list_sheet.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The accessible alternative to the map (spec §3.5), also shown in the
/// map's place when it can't load. Stories join it in Phase 2.
class CoupleMapListContent extends StatelessWidget {
  const CoupleMapListContent({
    super.key,
    required this.presence,
    required this.partnerName,
    required this.notice,
    required this.now,
    this.onNoticeTap,
  });
  final CoupleMapPresence presence;
  final String partnerName;
  final CoupleMapNotice? notice;
  final DateTime now;
  final VoidCallback? onNoticeTap;

  @override
  Widget build(BuildContext context) {
    final self = presence.self;
    final partner = presence.partner;
    final offset = partner?.utcOffsetMinutes;
    final partnerLine = [
      if (partner?.city case final c?) c,
      if (offset != null) '${formatClock(now.toUtc().add(Duration(minutes: offset)))} there',
    ].join(' · ');
    final n = notice;
    return CardInkWell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (self != null)
            InfoRowWidget(
              title: 'You',
              subtitle: self.city ?? 'Your area is shared',
              icon: Icons.person_pin_circle_outlined,
              showAvatar: false,
              showDivider: partner != null || n != null,
            ),
          if (partner != null)
            InfoRowWidget(
              title: partnerName,
              subtitle: partnerLine.isEmpty ? 'On the map' : partnerLine,
              icon: Icons.favorite_border,
              showAvatar: false,
              showDivider: n != null,
            ),
          if (n != null)
            InfoRowWidget(
              title: noticeText(n),
              subtitle: '',
              icon: Icons.near_me_outlined,
              showAvatar: false,
              showDivider: false,
              titleMaxLines: 3,
              showTrailingArrow: onNoticeTap != null,
              onTap: onNoticeTap,
            ),
        ],
      ),
    );
  }
}

Future<void> showCoupleMapListSheet(BuildContext context, {required String relationshipId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CoupleMapListSheet(relationshipId: relationshipId),
    );

class _CoupleMapListSheet extends ConsumerWidget {
  const _CoupleMapListSheet({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(coupleMapPresenceProvider(relationshipId)).valueOrNull ?? CoupleMapPresence.none;
    final access = ref.watch(locationAccessProvider).valueOrNull ?? LocationAccess.granted;
    final people = ref.watch(coupleMapPeopleProvider(relationshipId)).valueOrNull;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const BottomSheetHeader(title: 'On our map'),
        CoupleMapListContent(
          presence: presence,
          partnerName: people?.partnerName ?? 'your partner',
          notice: coupleMapNotice(presence, access),
          now: DateTime.now(),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}
```

(If `InfoRowWidget` rejects an empty subtitle visually, pass the notice in `subtitle` with a short title instead and ledger it. The test finds the notice by its text.)

- [ ] **Step 4: Run them and confirm they pass.**
- [ ] **Step 5: Ledger.**

---

### Task 8: The Map tab

**Files:**
- Create: `lib/features/couple_map/presentation/screens/couple_map_tab.dart`
- Test: `test/features/couple_map/couple_map_tab_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: `CoupleMapTab({required String relationshipId})`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/couple_map_tab_test.dart
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/screens/couple_map_tab.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../location/presence_repository_test.dart' show FakePresenceGateway, FakeSampler;
import 'support/fakes.dart';

class _NoReminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}

const _self = {'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'city': 'Accra', 'freshness': 'fresh'};
Map<String, Object?> _partner({String freshness = 'fresh'}) => {
      'who': 'partner', 'cell_lat': 51.505, 'cell_lng': -0.121, 'city': 'London', 'utc_offset_minutes': 60,
      'freshness': freshness, 'distance_km': 5100, 'together': false,
    };

class _Harness {
  _Harness(this.rows);
  List<Map<String, Object?>> rows;
  late final gateway = FakePresenceGateway({'couple_map_presence': (_) => rows});
  final sampler = FakeSampler(next: const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40));
  final view = FakeCoupleMapView();
  final pins = FakePinImageRenderer();
  String token = 'pk.test';
  ThemeMode themeMode = ThemeMode.light;
  bool reduceMotion = false;

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
  }

  Widget _app() => ProviderScope(
        overrides: [
          presenceGatewayProvider.overrideWithValue(gateway),
          presenceSamplerProvider.overrideWithValue(sampler),
          presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
          coupleMapViewBuilderProvider.overrideWithValue(view.builder),
          coupleMapTokenProvider.overrideWithValue(token),
          pinImageRendererProvider.overrideWithValue(pins),
          coupleMapPeopleProvider.overrideWith((ref, rel) async =>
              const CoupleMapPeople(selfInitials: 'AM', partnerInitials: 'K', partnerName: 'Kofi')),
          remindersListProvider.overrideWith(_NoReminders.new),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: themeMode,
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion, size: const Size(390, 844)),
              child: const Scaffold(body: CoupleMapTab(relationshipId: 'r1')),
            ),
          ),
        ),
      );
}

void main() {
  testWidgets('both sharing: two areas at cell centres, fitted once, the card and the chip', (t) async {
    final h = _Harness([_self, _partner()]);
    await h.pump(t);
    final c = h.view.controller;
    expect(c.lastAreas.map((a) => a.who), [PresenceWho.self, PresenceWho.partner]);
    expect(c.presences.last.$2.keys, containsAll([PresenceWho.self, PresenceWho.partner]));
    expect(c.fits, hasLength(1));
    expect(c.fits.single.$1, hasLength(2));
    expect(find.text('Sharing my area with Kofi'), findsOneWidget);
    expect(find.textContaining('5.1k km apart · in London'), findsOneWidget);
  });

  testWidgets('a fading partner is drawn at half opacity, with no time anywhere', (t) async {
    final h = _Harness([_self, _partner(freshness: 'fading')]);
    await h.pump(t);
    expect(h.view.controller.lastAreas.last.opacity, CoupleMapConfig.fadingOpacity);
    for (final banned in ['ago', 'online', 'last seen']) {
      expect(find.textContaining(RegExp(banned, caseSensitive: false)), findsNothing);
    }
  });

  testWidgets('no partner row: only my area and one neutral line', (t) async {
    final h = _Harness([_self]);
    await h.pump(t);
    expect(h.view.controller.lastAreas.map((a) => a.who), [PresenceWho.self]);
    expect(find.text('Just you on the map right now'), findsOneWidget);
  });

  testWidgets('partner disappears on refresh: their area and the card go (Review Focus 1)', (t) async {
    final h = _Harness([_self, _partner()]);
    await h.pump(t);
    h.rows = [_self];
    final container = ProviderScope.containerOf(t.element(find.byType(CoupleMapTab)));
    container.invalidate(coupleMapPresenceProvider('r1'));
    await t.pumpAndSettle();
    expect(h.view.controller.lastAreas.map((a) => a.who), [PresenceWho.self]);
    expect(find.textContaining('km apart'), findsNothing);
    expect(find.text('Just you on the map right now'), findsOneWidget);
  });

  testWidgets('not sharing: the onboarding line opens the sheet; never sampled or prompted', (t) async {
    final h = _Harness(const []);
    await h.pump(t);
    expect(h.sampler.sampled, 0);
    expect(h.sampler.asked, 0);
    await t.tap(find.text('See how far apart you are — shares your neighbourhood, never your address'));
    await t.pumpAndSettle();
    expect(find.text('Share my approximate area'), findsOneWidget);
  });

  testWidgets('location off: the chip says so and the notice opens settings', (t) async {
    final h = _Harness([_self])..sampler.accessValue = LocationAccess.denied;
    await h.pump(t);
    expect(find.text('Location is off for Attune'), findsOneWidget);
    await t.tap(find.text('Turn on location for Attune to share your area'));
    await t.pumpAndSettle();
    expect(h.sampler.openedSettings, 1);
  });

  testWidgets('load error: the list content replaces the map; the chip still works (Review Focus 5)', (t) async {
    final h = _Harness([_self, _partner()]);
    await h.pump(t);
    h.view.failLoad();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('fake-map')), findsNothing);
    expect(find.textContaining('London'), findsWidgets);
    expect(find.text('Sharing my area with Kofi'), findsOneWidget);
  });

  testWidgets('empty token: no map is built, the list shows', (t) async {
    final h = _Harness([_self])..token = '';
    await h.pump(t);
    expect(h.view.built, 0);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('style toggle switches to satellite and back', (t) async {
    final h = _Harness([_self]);
    await h.pump(t);
    await t.tap(find.byTooltip('Satellite view'));
    await t.pumpAndSettle();
    expect(h.view.controller.styles.last.$1, CoupleMapStyle.satellite);
    expect(find.byTooltip('Map view'), findsOneWidget);
  });

  testWidgets('recentre flies normally', (t) async {
    final h = _Harness([_self, _partner()]);
    await h.pump(t);
    await t.tap(find.byTooltip('Recentre on us'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits.last.$2, isTrue);
  });

  testWidgets('recentre with reduced motion jumps instead of flying', (t) async {
    final h = _Harness([_self, _partner()])..reduceMotion = true;
    await h.pump(t);
    await t.tap(find.byTooltip('Recentre on us'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits.last.$2, isFalse);
  });

  testWidgets('theme change updates the light preset (Review Focus 3)', (t) async {
    final h = _Harness([_self]);
    await h.pump(t);
    h.themeMode = ThemeMode.dark;
    await t.pumpWidget(h._app());
    await t.pumpAndSettle();
    expect(h.view.controller.styles.last, (CoupleMapStyle.standard, true));
  });

  testWidgets('every control has a label and a tap action (spec §3.5)', (t) async {
    final semantics = t.ensureSemantics();
    final h = _Harness([_self, _partner()]);
    await h.pump(t);
    for (final label in ['Satellite view', 'Recentre on us', 'List', 'Zoom in', 'Zoom out']) {
      final f = find.bySemanticsLabel(label);
      expect(f, findsOneWidget, reason: label);
      expect(t.getSemantics(f), containsSemantics(hasTapAction: true), reason: label);
    }
    semantics.dispose();
  });

  testWidgets('offline at open: says so plainly, retries on tap, never claims Off (checklist 1.3)', (t) async {
    final h = _Harness([_self]);
    h.gateway.handlers['couple_map_presence'] = (_) => throw Exception('offline');
    await h.pump(t);
    expect(find.text("Couldn't load your map. Try again."), findsOneWidget);
    expect(find.text('Off'), findsNothing);
    h.gateway.handlers['couple_map_presence'] = (_) => h.rows;
    await t.tap(find.text("Couldn't load your map. Try again."));
    await t.pumpAndSettle();
    expect(find.text('Just you on the map right now'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them and confirm they fail.** `flutter test test/features/couple_map/couple_map_tab_test.dart`. Expected: compilation error.

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/presentation/screens/couple_map_tab.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/widgets/couple_map_list_sheet.dart';
import 'package:attune/features/couple_map/presentation/widgets/distance_card.dart';
import 'package:attune/features/couple_map/presentation/widgets/glass_surface.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:attune/features/couple_map/presentation/widgets/sharing_chip.dart';
import 'package:attune/features/couple_map/presentation/widgets/sharing_sheet.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Planning's third tab (spec §3). Watching coupleMapPresenceProvider is
/// what samples on tab open (only while sharing) and on app resume.
class CoupleMapTab extends ConsumerStatefulWidget {
  const CoupleMapTab({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<CoupleMapTab> createState() => _CoupleMapTabState();
}

class _CoupleMapTabState extends ConsumerState<CoupleMapTab> {
  CoupleMapController? _controller;
  CoupleMapStyle _style = CoupleMapStyle.standard;
  bool _failed = false;
  bool _fitted = false;
  bool? _dark;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps "Paused · 42 min" counting down.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  int get _pinSizePx =>
      (CoupleMapConfig.pinSize * MediaQuery.devicePixelRatioOf(context)).round();

  void _onReady(CoupleMapController c) {
    _controller = c;
    final p = ref.read(coupleMapPresenceProvider(widget.relationshipId)).valueOrNull;
    if (p != null) unawaited(_push(p));
  }

  Future<void> _push(CoupleMapPresence p) async {
    final c = _controller;
    if (c == null || !mounted) return;
    final areas = sceneAreas(p);
    final avatars = await _avatars(areas);
    if (!mounted || _controller != c) return;
    await c.setPresence(
      areas,
      avatars,
      areaColor: Theme.of(context).colorScheme.primary,
      together: p.together,
      pinSizePx: _pinSizePx,
    );
    if (!_fitted && areas.isNotEmpty) {
      _fitted = true;
      await c.fitTo([for (final a in areas) a.centre], animate: false);
    }
  }

  Future<Map<PresenceWho, Uint8List>> _avatars(List<SceneArea> areas) async {
    final people = await ref.read(coupleMapPeopleProvider(widget.relationshipId).future);
    if (!mounted) return const {};
    final cs = Theme.of(context).colorScheme;
    final px = _pinSizePx;
    final renderer = ref.read(pinImageRendererProvider);
    PinSpec spec(String? url, String initials) => PinSpec(
          imageUrl: url,
          initials: initials,
          ring: cs.surface,
          fill: cs.primaryContainer,
          onFill: cs.onPrimaryContainer,
          sizePx: px,
        );
    return {
      for (final a in areas)
        a.who: await renderer.render(a.who == PresenceWho.self
            ? spec(people.selfUrl, people.selfInitials)
            : spec(people.partnerUrl, people.partnerInitials)),
    };
  }

  Future<void> _fit() async {
    final p = ref.read(coupleMapPresenceProvider(widget.relationshipId)).valueOrNull;
    final areas = p == null ? const <SceneArea>[] : sceneAreas(p);
    await _controller?.fitTo([for (final a in areas) a.centre], animate: !_reduceMotion);
  }

  void _toggleStyle(bool dark) {
    final next = _style == CoupleMapStyle.standard ? CoupleMapStyle.satellite : CoupleMapStyle.standard;
    setState(() => _style = next);
    unawaited(_controller?.setStyle(next, dark: dark));
  }

  void _onNoticeTap(CoupleMapNotice n) {
    switch (n) {
      case CoupleMapNotice.notSharing:
        showSharingSheet(context, relationshipId: widget.relationshipId);
      case CoupleMapNotice.locationOff:
        ref.read(presenceSamplerProvider).openSettings();
      case CoupleMapNotice.justYou:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.relationshipId;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if (_dark != null && _dark != dark) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller?.setStyle(_style, dark: dark);
        // Areas and pin rings take theme colours: redraw them too.
        final p = ref.read(coupleMapPresenceProvider(rel)).valueOrNull;
        if (p != null) unawaited(_push(p));
      });
    }
    _dark = dark;

    ref.listen(coupleMapPresenceProvider(rel), (_, next) {
      final p = next.valueOrNull;
      if (p != null) unawaited(_push(p));
    });

    final presenceAsync = ref.watch(coupleMapPresenceProvider(rel));
    final presence = presenceAsync.valueOrNull;
    // Unknown access must not claim "off".
    final access = ref.watch(locationAccessProvider).valueOrNull ?? LocationAccess.granted;
    final people = ref.watch(coupleMapPeopleProvider(rel)).valueOrNull;
    final partnerName = people?.partnerName ?? 'your partner';
    final distance = ref.watch(partnerDistanceWithReunionProvider(rel));
    final now = DateTime.now();
    final state = presence?.state;
    final notice = presence == null ? null : coupleMapNotice(presence, access);
    // A failed first read with nothing to fall back on: say so, offer a
    // retry, and never claim "Off" for a state we haven't read (1.3).
    final loadFailed = presence == null && presenceAsync.hasError;
    final mapAvailable = !_failed && ref.watch(coupleMapTokenProvider).isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom + Spacing.md;

    final Widget bottom;
    if (loadFailed) {
      bottom = RetryCard(
        onTap: () => ref.invalidate(coupleMapPresenceProvider(rel)),
      );
    } else if (presence == null) {
      bottom = const LoadingCard();
    } else if (notice != null) {
      bottom = NoticeCard(
        notice: notice,
        onTap: notice == CoupleMapNotice.justYou ? null : () => _onNoticeTap(notice),
      );
    } else if (distance != null) {
      bottom = DistanceCard(
        copy: distanceCardCopy(
          distance,
          partnerName: partnerName,
          myUtcOffsetMinutes: now.timeZoneOffset.inMinutes,
          now: now,
        ),
        people: people ??
            const CoupleMapPeople(selfInitials: '?', partnerInitials: '?', partnerName: 'your partner'),
      );
    } else {
      bottom = const SizedBox.shrink();
    }

    final chip = SharingChip(
      // Unread state: a neutral word, never "Off".
      label: state == null
          ? 'Sharing'
          : sharingChipLabel(state, access: access, partnerName: partnerName, now: now),
      status: state?.status,
      locationOff: access != LocationAccess.granted,
      onTap: () => showSharingSheet(context, relationshipId: rel),
    );

    if (!mapAvailable) {
      return ColoredBox(
        color: theme.colorScheme.surface,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Align(alignment: Alignment.centerLeft, child: chip),
            const SizedBox(height: Spacing.md),
            CoupleMapListContent(
              presence: presence ?? CoupleMapPresence.none,
              partnerName: partnerName,
              notice: notice,
              now: now,
              onNoticeTap: notice == null || notice == CoupleMapNotice.justYou ? null : () => _onNoticeTap(notice),
            ),
          ],
        ),
      );
    }

    final build = ref.watch(coupleMapViewBuilderProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: build(
            style: _style,
            dark: dark,
            onReady: _onReady,
            onLoadError: () {
              if (!mounted) return;
              // The map's State is going away: stop calling it.
              _controller = null;
              _fitted = false;
              setState(() => _failed = true);
            },
          ),
        ),
        Positioned(
          top: Spacing.md,
          left: Spacing.md,
          right: Spacing.md + CoupleMapConfig.glassButtonSize + Spacing.sm,
          child: Align(alignment: Alignment.centerLeft, child: chip),
        ),
        // One right-hand column, so nothing overlaps on short screens; the
        // compass sits below it (marginTop 292 in the Mapbox view).
        Positioned(
          top: Spacing.md,
          right: Spacing.md,
          child: Column(children: [
            GlassIconButton(
              icon: _style == CoupleMapStyle.standard ? Icons.satellite_alt_outlined : Icons.map_outlined,
              tooltip: _style == CoupleMapStyle.standard ? 'Satellite view' : 'Map view',
              onPressed: () => _toggleStyle(dark),
            ),
            const SizedBox(height: Spacing.sm),
            GlassIconButton(icon: Icons.center_focus_strong_outlined, tooltip: 'Recentre on us', onPressed: _fit),
            const SizedBox(height: Spacing.sm),
            GlassIconButton(
              icon: Icons.list_alt_rounded,
              tooltip: 'List',
              onPressed: () => showCoupleMapListSheet(context, relationshipId: rel),
            ),
            const SizedBox(height: Spacing.md),
            GlassIconButton(
              icon: Icons.add,
              tooltip: 'Zoom in',
              onPressed: () => _controller?.zoomBy(1, animate: !_reduceMotion),
            ),
            const SizedBox(height: Spacing.sm),
            GlassIconButton(
              icon: Icons.remove,
              tooltip: 'Zoom out',
              onPressed: () => _controller?.zoomBy(-1, animate: !_reduceMotion),
            ),
          ]),
        ),
        Positioned(
          left: Spacing.md,
          right: Spacing.md,
          bottom: bottomInset,
          child: AnimatedSwitcher(
            duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
            child: KeyedSubtree(key: ValueKey(bottom.runtimeType), child: bottom),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run them and confirm they pass,** together with `flutter test test/features/couple_map/ test/features/location/`.
- [ ] **Step 5: Ledger.**

---

### Task 9: The third tab, quick exit, and the test harness

**Files:**
- Create: `lib/features/couple_map/data/couple_map_device_data.dart`
- Modify: `lib/features/planning/presentation/screens/planning_home_screen.dart`, `lib/features/safety/domain/services/quick_exit_service.dart`, `test/features/planning/support/planning_test_app.dart`
- Test: `test/features/couple_map/couple_map_device_data_test.dart`, `test/features/planning/planning_home_screen_test.dart` (add two tests)

**Interfaces:**
- Consumes: `coupleMapEnabledProvider` (Phase 0), `CoupleMapTab` (Task 8), `sharedPinImageRenderer` (Task 4).
- Produces:
  - `Future<void> clearCoupleMapDeviceData({Future<void> Function()? clearMapCache, PinImageRenderer? pins})`
  - `planningOverrides(..., {bool mapEnabled = false})`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/couple_map_device_data_test.dart
import 'dart:io';

import 'package:attune/features/couple_map/data/couple_map_device_data.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('clears the Mapbox cache and the pin images', () async {
    var cleared = 0;
    final pins = FakePinImageRenderer();
    await pins.render(const PinSpec(initials: 'A', ring: Color(0xFFFFFFFF), fill: Color(0xFF000000), onFill: Color(0xFFFFFFFF), sizePx: 8));
    expect(pins.length, 1);
    await clearCoupleMapDeviceData(clearMapCache: () async => cleared++, pins: pins);
    expect(cleared, 1);
    expect(pins.length, 0);
  });

  test('a failing map clear never throws (quick exit must not stall)', () async {
    await clearCoupleMapDeviceData(clearMapCache: () async => throw Exception('no map'), pins: FakePinImageRenderer());
  });

  test('quick exit clears the map after the cover, and never touches server presence', () {
    final source = File('lib/features/safety/domain/services/quick_exit_service.dart').readAsStringSync();
    final execute = source.substring(source.indexOf('static Future<void> execute'), source.indexOf('static Future<void> _markSafetyUnlockRequired'));
    expect(execute.indexOf('_showNeutralCover(context)'), lessThan(execute.indexOf('clearCoupleMapDeviceData()')));
    expect(execute.contains('unawaited(clearCoupleMapDeviceData())'), isTrue);
    for (final rpc in ['stop_presence', 'set_presence_pause', 'stopSharing']) {
      expect(source.contains(rpc), isFalse, reason: 'a sudden disappearance is itself a signal (spec §3.6)');
    }
  });
}
```

In `test/features/planning/planning_home_screen_test.dart`, add:

```dart
  testWidgets('with couple_map_enabled on, Planning has a third tab: Map', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), const PlanningHomeScreen(relationshipId: 'r1'), mapEnabled: true));
    await tester.pumpAndSettle();
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
  });

  testWidgets('with the flag off (the default), there is no Map tab', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), const PlanningHomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Map'), findsNothing);
  });
```

(The Map tab's content isn't built until it's visited, because `TabBarView` builds lazily, so these tests need no map fakes.)

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/data/couple_map_device_data.dart
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Clears what the couple map keeps on this device (quick exit, spec §3.6):
/// the Mapbox tile and style cache, which holds the partner's area, and the
/// rendered pins. Server presence is deliberately untouched: a sudden
/// disappearance would itself be a signal. Phase 2 adds the last pin
/// choice and the home area.
Future<void> clearCoupleMapDeviceData({
  Future<void> Function()? clearMapCache,
  PinImageRenderer? pins,
}) async {
  (pins ?? sharedPinImageRenderer).clear();
  try {
    await (clearMapCache ?? MapboxMapsOptions.clearData)();
  } catch (_) {}
}
```

`quick_exit_service.dart`:
- Add `import 'package:attune/features/couple_map/data/couple_map_device_data.dart';`.
- After `unawaited(clearTogetherDeviceSurfaces());`, add:

```dart
    // The map's tile cache holds the partner's area; pins hold faces.
    unawaited(clearCoupleMapDeviceData());
```

`planning_home_screen.dart`:
- Imports: `package:attune/features/couple_map/presentation/screens/couple_map_tab.dart` and `package:attune/features/location/presentation/providers/presence_providers.dart` (which has `coupleMapEnabledProvider`).
- In `build`: `final mapEnabled = ref.watch(coupleMapEnabledProvider).valueOrNull ?? false;`
- Update the comment to: `// Planning, the couple's Together calendar (embedded, so it has no app bar of its own), and — behind couple_map_enabled — the couple map.`
- Append to `tabs`:

```dart
          if (mapEnabled)
            AppTabItem(
              label: 'Map',
              icon: Icons.map_outlined,
              content: CoupleMapTab(relationshipId: widget.relationshipId),
            ),
```

`planning_test_app.dart`:
- Add the parameter `bool mapEnabled = false` to both `planningOverrides` and `planningTestApp`.
- `planningTestApp` passes it on: `overrides: planningOverrides(gateway, store: store, coupleName: coupleName, mapEnabled: mapEnabled)`.
- In `planningOverrides`, add `coupleMapEnabledProvider.overrideWith((ref) async => mapEnabled),` with the import `package:attune/features/location/presentation/providers/presence_providers.dart`, which may already be imported for `partnerDistanceProvider`.

- [ ] **Step 4: Run them and confirm they pass.** `flutter test test/features/couple_map/ test/features/planning/`.
- [ ] **Step 5: Ledger.**

---

## Final verification (Phase 1 exit)

1. **Full suite.** Run `flutter test` with the output redirected to the ledger directory. It must be green; a flaky test is rerun three times on its own and named.
2. **Analyzer.** Run `flutter analyze lib test 2>&1 | grep -E "^\s*(error|warning) "`: 0 errors, and no findings in touched files.
3. **Coverage (6.7).**
   - Run `flutter test --coverage test/features/couple_map test/features/location`.
   - Targets: `couple_map/domain` ≥ 90%, widgets ≥ 50%.
   - Record the numbers. The Mapbox view is platform code, covered by the wiring test and the device check.
4. **Builds.** Run `flutter build apk --debug` and `flutter build ios --debug --no-codesign`; both must succeed.
5. **Scans (7.1–7.3).**
   - Secret scan: `git grep -nE "pk\.[A-Za-z0-9]{20,}|sk\.[A-Za-z0-9]{20,}"`. Expected: nothing, since the token comes only from `Environment`.
   - Dependency check: `flutter pub outdated mapbox_maps_flutter`, plus a GitHub advisory search for `mapbox_maps_flutter` / `mapbox-maps-ios` / `mapbox-maps-android` 11.24.
   - Record both results in the ledger.
6. **PII grep (4.4).** `grep -rnE "(print|debugPrint|log)\(" lib/features/couple_map` must show nothing that interpolates a lat, lng, city or label.
7. **SQL.** No migration in this phase. Rerun `couple_map_presence_contracts.sql` on `run5` to confirm it's unchanged.
8. **Fable review.** A fresh Fable reviewer checks the whole Phase 1 diff against spec §2, §3, §6.2–6.3 and §9, plus this plan's Review Focus. Then one fix pass: each fix gets a test that fails first.
9. **Manual (owner, two devices, flag on in a dev build).**
   - Both partners sharing: two areas.
   - Pause from each side: the neutral line, and resuming shows nothing until the next open.
   - Map ↔ satellite with both pins present (Review Focus 2).
   - Light ↔ dark.
   - Airplane mode at open: the list fallback.
   - Location off: the chip, then Settings, then back.
   - Android telemetry check (Phase 0 M14): `getEventsCollectionState()` reads false.
   - Quick exit, then reopen: the map cache is cleared (tiles reload).

## Checklist v3.1 evidence map (Phase 1)

| Item | Where it's proven |
|---|---|
| 1.2 Timeouts | Pin photo 5 s (Task 4); fix 20 s and geocode 10 s (Phase 0); map load error, then the list (Task 8) |
| 1.3 Graceful degradation | Location off, then chip and notice (Task 8); Mapbox style down or no token, then the list (Task 8); a tile error keeps the map (Task 5); offline at open, then "Couldn't load your map. Try again." and never "Off" (Task 8); sheet failure, then plain copy (Task 6); dismissing mid-call is safe (Task 6) |
| 1.4 / 1.5 Authorization | Unchanged server RPCs (Phase 0 C4, C10, C11), rerun in final verification step 7 |
| 2.4 / 5.5 Errors don't leak | "Couldn't update your area. Try again." (Task 6 test); no IDs or traces in the UI |
| 2.6 Output sanitisation | City and labels rendered as plain `Text` (Tasks 7 and 8) |
| 2.7–2.9 Secrets | Token from `Environment` via `coupleMapTokenProvider`; secret scan (final verification step 5) |
| 2.10 Resources released | The map controller goes inert on dispose (Task 5 wiring test) and the tab drops it on load error; tab ticker cancelled in `dispose`; provider timer and lifecycle listener (Phase 0); no pending timers at test end (flutter_test enforces it) |
| 2.12–2.15 / 3.4 Bounded cache | Pin LRU of 64 (Task 4 test) |
| 3.7 / 3.8 Rate limiting | 60 s client debounce (Task 3 test) plus server 60 s (Phase 0 C10) |
| 4.4 No PII in logs | `MapPoint.toString` redacted (Task 1); Mapbox wiring test finds no print or debugPrint (Task 5); PII grep (final verification step 6) |
| 4.11 Configuration | `CoupleMapConfig` and `PresenceConfig.recordDebounce` |
| 5.1 / 5.2 UX | Actionable notices (Task 8); `LoadingCard` on the first frame; card cross-fade at 200 ms |
| 5.6 Accessibility | Labels **and tap actions** on every control (Tasks 6 and 8 tests); `ExcludeSemantics` on the canvas (Task 5); list content (Task 7); reduced motion (Task 8) |
| 6.1 Edge cases | Snapping at the equator, the antimeridian and the cos floor (Task 1); paused, infinity and expired pause chips (Task 2) |
| 6.2 Failure tests | Loader failure (Task 4); RPC failure (Task 6); map load failure and empty token (Task 8) |
| 6.4 Negative tests | No partner, so no partner area or name (Tasks 7 and 8); not sharing, so never sampled or prompted (Task 8) |
| 6.5 Property tests | snap idempotence; area covers every corner (Task 1) |
| 6.7 Coverage | Final verification step 3 |
| 7.1–7.3 Scans | Final verification step 5 |
| 8.1 Rollback | `couple_map_enabled` off hides the tab (Task 9 test); no migration in this phase |
| Mapbox terms (logo and attribution visible) | Lifted above the card (Task 5 wiring test); checked on device |
| 3.4 cache key | `PinSpec` is keyed by avatar URL. Record in the ledger whether profile `avatar_url`s are stable public URLs; if they're signed or rotating, key by storage path instead |
