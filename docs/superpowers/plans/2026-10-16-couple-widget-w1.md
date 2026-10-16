# Couple Distance Widget — W1 (Dart side) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything the home-screen distance widget needs on the Dart side. That means:
- the pure payload and the region frame;
- the bundled world outline and the map painter;
- the App Group sync with clearing;
- a publisher that writes only from reads (never sampling);
- the Sharing-sheet toggle with a preview.

The native widgets (W2) then only display what's written.

**Architecture:** Five pieces, in dependency order:
- **Pure domain.** `couple_widget_payload.dart` builds the payload; `region_frame.dart` holds the geometry.
- **Assets and painting.** The outline asset (built by a committed script) and a `CustomPainter` rendered to PNG with `dart:ui`.
- **Sync.** `CoupleWidgetSync` sits over a `CoupleWidgetStore` seam (home_widget in production, memory in tests), with a static `generation` counter.
- **Publisher.** A keep-alive provider. It hears every presence read through a broadcast stream added to `presence_providers.dart`, so it never keeps `coupleMapPresenceProvider` alive. It does a read-only `fetchMapPresence` on resume.
- **UI.** A Sharing-sheet row and a preview card.

**Tech Stack:** Flutter, Riverpod 2.4 (`flutter_riverpod ^2.4.9`), `home_widget ^0.9.2` (already locked), `shared_preferences`, `dart:ui` `PictureRecorder`, `flutter_test` goldens.

**Spec:** `docs/superpowers/specs/2026-10-16-couple-distance-widget-design.md` (W1 row of §7). Read it alongside this plan.

## Global Constraints

**How we work**
- Work directly on `main`. **No commits or pushes**: each task ends with a ledger line instead of a commit.
- Write each test first and watch it fail before writing code.
- **Never `dart format` a pre-existing file or directory.** Format only files created by this plan.
- **Snapshot-diff every shared file.** Before editing one, `cp <file> "$WS/snapshots/"`. After editing, run `diff -u "$WS/snapshots/<name>" <file>` and check it shows only the intended lines. `git diff --numstat` is blind here: most `lib/features/couple_map/**` files and their tests are untracked (couple-map Phases 0–3 are uncommitted), and `presence_providers.dart` already carries the owner's uncommitted edits.
- Analyzer gate: `flutter analyze <files> 2>&1 | grep -E "^\s*(error|warning) "` prints nothing.
- **Shared files touched** (each is a surgical edit; flag the regression risk in the ledger):
  - `lib/features/location/presentation/providers/presence_providers.dart`
  - `lib/features/couple_map/data/couple_map_device_data.dart`
  - `lib/features/together/data/together_device_surfaces.dart`
  - `lib/features/couple_map/presentation/widgets/sharing_sheet.dart`
  - `lib/app/app.dart`
  - `pubspec.yaml`
  - `android/app/src/main/res/xml/backup_rules.xml` and `data_extraction_rules.xml`

**Privacy**
- **Never log coordinates, place labels, city names or partner names** (checklist 4.4). Logs carry only the categories `widget_render_failed` and `widget_read_failed`, via `dart:developer` `log(..., name: 'couple_widget')`.
- **The payload JSON never contains** coordinates, cell ids, city, country, partner name, avatar, relationship id or user id (spec §4.4).
- **The publisher never calls `PresenceRepository.record`**, never `watch`es or `listen`s to `coupleMapPresenceProvider`, and never samples (spec §4.1).

**Distance rules**
- Distance is written only when **both** areas are `fresh` and I'm `sharing`. It is valid for **3 h** from the write (spec §4.2).
- The reunion comes only from `withReunion` (km ≥ 800), and is kept until its day passes (spec §3.1).

**Copy (verbatim)**
- "Nothing to show yet"
- "Practically together"
- "{clock} there"
- "{n} days until you're together", "Together tomorrow", "Together today"
- "{n} days" / "until you're together"
- "{formatKm} apart"
- Toggle: "Show distance on my home screen", subtitle "No names or places. Cleared by quick exit."
- Preview label: "Your home screen shows roughly this"
- iOS: "Touch and hold your home screen, tap +, then find Attune"
- Android: "Touch and hold your home screen, tap Widgets, then find Attune"

**Constants (`CoupleWidgetConfig`)**

| Name | Value |
|---|---|
| validity | 3 h |
| map threshold | 100 km |
| grid | 0.5° |
| minimum span | 600 km |
| fit | central 50 % |
| read debounce | 5 min |
| image | 480 px |
| render budget | 2 s |
| glow radius | 0.125 of the image side (20 pt on a 160 pt pane) |

**Keys**
- Prefs `couple_widget_enabled`.
- Payload `couple_widget_v1`.
- Image `couple_widget_map`.
- iOS kind `CoupleWidget`.
- Android `com.barsopus.attune.CoupleWidgetProvider`.
- App Group `group.com.barsopus.attune` (constant `togetherWidgetAppGroup` from `lib/features/together/data/together_widget_sync.dart`).

## Review Focus

1. **A presence read fails** (offline or RPC error) while a payload is stored. The last payload stays as it is (it expires by itself) and nothing throws. Pinned in Task 7 ("a failing read leaves the stored payload").
2. **Partner row present but `distance_km` null** (the server gives no honest number). No distance part, and the countdown is kept if one exists. Pinned in Task 1 ("partner without a distance writes nothing").
3. **Partner time zone unknown** (`utc_offset_minutes` null) in the distant tone. The headline is "5.1k km apart" with no clock. Pinned in Task 1 ("distant without an offset leads with the km").
4. **A reunion is today, or already past.** Today reads "Together today"; a past one is never shown. Pinned in Task 1 (resolve tests).
5. **Sign-out or quick exit while a render or read is in flight.** The late result never writes. Pinned in Task 7 ("a clear during a slow render drops the render").

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/features/couple_map/widget/domain/couple_widget_config.dart` (new) | Named constants |
| `lib/features/couple_map/widget/domain/geo_point.dart` (new) | `GeoPoint` record typedef |
| `lib/features/couple_map/widget/domain/couple_widget_payload.dart` (new) | Payload type, JSON, expiry, `buildCoupleWidget`, `resolveCoupleWidget` |
| `lib/features/couple_map/widget/domain/region_frame.dart` (new) | Snapping, Mercator, unwrap, square frame |
| `tool/build_land_outline.dart` (new) | GeoJSON → `assets/geo/land_50m_merc.bin` |
| `assets/geo/land_50m_merc.bin`, `assets/geo/README.md` (new) | The outline and its licence note |
| `lib/features/couple_map/widget/data/world_outline.dart` (new) | Parses the outline; `worldOutlineProvider` |
| `lib/features/couple_map/widget/presentation/region_map_painter.dart` (new) | Painter, `paintRegionMap`, `renderRegionMap` |
| `lib/features/couple_map/widget/data/couple_widget_sync.dart` (new) | Store seam, `CoupleWidgetSync` (publish, hide, clear, expire, generation) |
| `lib/features/couple_map/widget/presentation/couple_widget_publisher.dart` (new) | Publisher and providers |
| `lib/features/couple_map/widget/presentation/couple_widget_preview.dart` (new) | The Sharing-sheet preview card |
| `lib/features/location/presentation/providers/presence_providers.dart` (shared) | `presenceReadsProvider` + one hook line |
| `lib/features/couple_map/presentation/widgets/sharing_sheet.dart` (shared) | Toggle, preview, hide-on-pause |
| `lib/features/couple_map/data/couple_map_device_data.dart` (shared) | Clears the widget first |
| `lib/features/together/data/together_device_surfaces.dart` (shared) | Clears the widget |
| `lib/app/app.dart` (shared) | `startIfEnabled()` at launch |
| Android `backup_rules.xml`, `data_extraction_rules.xml` (shared) | Exclude widget storage |

Tests live under `test/features/couple_map/widget/` (new folder) plus the existing `test/features/couple_map/sharing_sheet_test.dart`, `couple_map_device_data_test.dart` and `test/features/location/`.

---

### Task 1: Payload domain (config, build, resolve, expiry)

**Files:**
- Create: `lib/features/couple_map/widget/domain/couple_widget_config.dart`
- Create: `lib/features/couple_map/widget/domain/geo_point.dart`
- Create: `lib/features/couple_map/widget/domain/couple_widget_payload.dart`
- Test: `test/features/couple_map/widget/couple_widget_payload_test.dart`

**Interfaces:**
- Consumes:
  - `CoupleMapPresence`, `PresenceArea`, `PresenceFreshness`, `PresenceState`, `PresenceStatus` (`lib/features/location/domain/couple_map_presence.dart`);
  - `PartnerDistance`, `DistanceTone` (`partner_distance.dart`);
  - `distanceCopy`, `formatKm`, `formatClock` (`distance_copy.dart`);
  - `withReunion`, `daysUntil` (`reunion.dart`).
- Produces:
  - `typedef GeoPoint = ({double lat, double lng});`
  - `abstract final class CoupleWidgetConfig` (constants below).
  - `class CoupleWidgetPayload`:
    - fields: `headline`, `headlineIsClock`, `caption`, `clockOffsetMinutes`, `clockLine`, `validUntilMs`, `reunionDate`;
    - `hasDistance`, `encode()`, `static decode(String?)`, `withoutDistance()`, `current(DateTime now)`, `static const empty`.
  - `class CoupleWidgetBuild { CoupleWidgetPayload payload; GeoPoint? mapSelf; GeoPoint? mapPartner; bool get hasMap; }`
  - `CoupleWidgetBuild buildCoupleWidget({required CoupleMapPresence presence, required Iterable<(String, DateTime)> events, required DateTime now, DateTime? readAt, String? keptReunionDate})`. `readAt` (default `now`) is when the presence was READ; `validUntilMs = readAt + 3 h`, so re-publishing a remembered read never extends the validity.
  - `class CoupleWidgetView { String headline; String? caption; String? clockLine; bool neutral; String get semanticsLabel; }`
  - `CoupleWidgetView resolveCoupleWidget(CoupleWidgetPayload stored, DateTime now)`
  - `String dateKey(DateTime d)` → `yyyy-MM-dd`
  - `const neutralHeadline = 'Nothing to show yet';`

- [ ] **Step 1: Write the failing tests**

```dart
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

    test('current() drops the distance at validUntil, the reunion after its day', () {
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
    });
  });

  group('resolveCoupleWidget', () {
    test('distant: the live clock leads', () {
      final v = resolveCoupleWidget(build(presence()).payload, now);
      final there = formatClock(now.toUtc().add(const Duration(minutes: 60)));
      expect(v.headline, '$there there');
      expect(v.caption, '5.1k km apart');
      expect(v.clockLine, isNull);
    });

    test('countdown with distance: 12 days, Together tomorrow, Together today', () {
      for (final (date, headline) in [
        ('2026-10-28', "12 days until you're together"),
        ('2026-10-17', 'Together tomorrow'),
        ('2026-10-16', 'Together today'),
      ]) {
        final p = CoupleWidgetPayload(
          caption: '5.1k km apart',
          clockOffsetMinutes: 60,
          clockLine: true,
          validUntilMs: now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          reunionDate: date,
        );
        final v = resolveCoupleWidget(p, now);
        expect(v.headline, headline);
        expect(v.clockLine, endsWith(' there'));
      }
    });

    test('expired distance falls back to the countdown alone', () {
      final p = CoupleWidgetPayload(
        caption: '5.1k km apart',
        validUntilMs: now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
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
      expect(v.semanticsLabel, 'Together tomorrow. 5.1k km apart. 3:15pm there');
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/couple_map/widget/couple_widget_payload_test.dart`
Expected: FAIL to compile, with "Target of URI doesn't exist: 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart'".

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/couple_map/widget/domain/couple_widget_config.dart
/// The home-screen widget's tunables (spec §9, 4.11).
abstract final class CoupleWidgetConfig {
  static const payloadVersion = 1;

  /// How long a written distance stays on the widget (spec §4.2).
  static const validFor = Duration(hours: 3);

  /// The region map appears from this distance (spec §3.3).
  static const mapMinKm = 100.0;

  /// Draw-only coarsening of each area (~55 km).
  static const gridDegrees = 0.5;

  /// The map never shows less than this across.
  static const minSpanKm = 600.0;

  /// Both glows sit inside this central fraction of the square.
  static const fitFraction = 0.5;

  /// At most one widget read per this long.
  static const readDebounce = Duration(minutes: 5);

  static const imagePx = 480;
  static const renderBudget = Duration(seconds: 2);

  /// Glow radius as a fraction of the image side (20 pt on a 160 pt pane).
  static const glowRadiusFraction = 0.125;
}
```

```dart
// lib/features/couple_map/widget/domain/geo_point.dart
typedef GeoPoint = ({double lat, double lng});
```

```dart
// lib/features/couple_map/widget/domain/couple_widget_payload.dart
import 'dart:convert';

import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/geo_point.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:attune/features/location/domain/reunion.dart';
import 'package:flutter/foundation.dart';

const neutralHeadline = 'Nothing to show yet';

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

int _daysTo(String date, DateTime now) {
  final at = DateTime.tryParse(date);
  return at == null ? -1 : daysUntil(at, now: now);
}

/// What the app writes to the App Group (spec §4.4). No coordinates,
/// places, names or ids: only lines of copy, a clock offset, my own write
/// time + 3 h, and a reunion date.
@immutable
class CoupleWidgetPayload {
  const CoupleWidgetPayload({
    this.headline,
    this.headlineIsClock = false,
    this.caption,
    this.clockOffsetMinutes,
    this.clockLine = false,
    this.validUntilMs,
    this.reunionDate,
  });

  static const empty = CoupleWidgetPayload();

  final String? headline;

  /// The headline is the partner's live clock (distant tone).
  final bool headlineIsClock;
  final String? caption;
  final int? clockOffsetMinutes;

  /// Show "{clock} there" as its own line.
  final bool clockLine;

  /// The distance part's end; null means there is no distance part.
  final int? validUntilMs;

  /// yyyy-MM-dd, local.
  final String? reunionDate;

  bool get hasDistance => validUntilMs != null;

  Map<String, Object> toJson() => {
    'v': CoupleWidgetConfig.payloadVersion,
    if (headline != null) 'headline': headline!,
    if (headlineIsClock) 'headlineIsClock': true,
    if (caption != null) 'caption': caption!,
    if (clockOffsetMinutes != null) 'clockOffsetMinutes': clockOffsetMinutes!,
    if (clockLine) 'clockLine': true,
    if (validUntilMs != null) 'validUntilMs': validUntilMs!,
    if (reunionDate != null) 'reunionDate': reunionDate!,
  };

  String encode() => jsonEncode(toJson());

  static CoupleWidgetPayload decode(String? raw) {
    if (raw == null) return empty;
    try {
      final m = jsonDecode(raw);
      if (m is! Map || m['v'] != CoupleWidgetConfig.payloadVersion) {
        return empty;
      }
      return CoupleWidgetPayload(
        headline: m['headline'] as String?,
        headlineIsClock: m['headlineIsClock'] == true,
        caption: m['caption'] as String?,
        clockOffsetMinutes: (m['clockOffsetMinutes'] as num?)?.toInt(),
        clockLine: m['clockLine'] == true,
        validUntilMs: (m['validUntilMs'] as num?)?.toInt(),
        reunionDate: m['reunionDate'] as String?,
      );
    } catch (_) {
      return empty;
    }
  }

  /// Keeps only the reunion (calendar data, not location).
  CoupleWidgetPayload withoutDistance() =>
      CoupleWidgetPayload(reunionDate: reunionDate);

  /// What is still true at [now]: the distance part until validUntil, the
  /// reunion until its day has passed.
  CoupleWidgetPayload current(DateTime now) {
    final distanceLive =
        validUntilMs != null && validUntilMs! > now.millisecondsSinceEpoch;
    final reunionLive = reunionDate != null && _daysTo(reunionDate!, now) >= 0;
    final base = distanceLive ? this : withoutDistance();
    if (reunionLive) return base;
    return CoupleWidgetPayload(
      headline: base.headline,
      headlineIsClock: base.headlineIsClock,
      caption: base.caption,
      clockOffsetMinutes: base.clockOffsetMinutes,
      clockLine: base.clockLine,
      validUntilMs: base.validUntilMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoupleWidgetPayload && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

@immutable
class CoupleWidgetBuild {
  const CoupleWidgetBuild(this.payload, {this.mapSelf, this.mapPartner});
  final CoupleWidgetPayload payload;

  /// The two cells, only when the region map applies (spec §3.3). They
  /// never enter the payload; the frame snaps them before drawing.
  final GeoPoint? mapSelf;
  final GeoPoint? mapPartner;
  bool get hasMap => mapSelf != null && mapPartner != null;
}

/// Turns one presence read into what the widget may show (spec §3.1, §4.2).
CoupleWidgetBuild buildCoupleWidget({
  required CoupleMapPresence presence,
  required Iterable<(String, DateTime)> events,
  required DateTime now,
  DateTime? readAt,
  String? keptReunionDate,
}) {
  final kept =
      CoupleWidgetPayload(reunionDate: keptReunionDate).current(now).reunionDate;
  final none = CoupleWidgetBuild(CoupleWidgetPayload(reunionDate: kept));
  final self = presence.self;
  final partner = presence.partner;
  final raw = presence.partnerDistance;
  if (presence.state.status != PresenceStatus.sharing ||
      self == null ||
      partner == null ||
      raw == null ||
      self.freshness != PresenceFreshness.fresh ||
      partner.freshness != PresenceFreshness.fresh) {
    return none;
  }
  final d = withReunion(raw, events, now: now);
  // From the READ, not the publish: a remembered read re-published later
  // (reminders changed) must not stay up longer (spec §4.2).
  final validUntilMs =
      (readAt ?? now).add(CoupleWidgetConfig.validFor).millisecondsSinceEpoch;
  final apart = '${formatKm(d.km)} apart';
  final offset = d.partnerUtcOffsetMinutes;
  final copy = distanceCopy(d, now: now);
  GeoPoint? at(PresenceArea a) =>
      a.cellLat == null || a.cellLng == null
          ? null
          : (lat: a.cellLat!, lng: a.cellLng!);
  CoupleWidgetBuild withMap(CoupleWidgetPayload p) {
    final a = at(self);
    final b = at(partner);
    if (d.km < CoupleWidgetConfig.mapMinKm || a == null || b == null) {
      return CoupleWidgetBuild(p);
    }
    return CoupleWidgetBuild(p, mapSelf: a, mapPartner: b);
  }

  switch (d.tone) {
    case DistanceTone.together:
    case DistanceTone.nearby:
      return CoupleWidgetBuild(
        CoupleWidgetPayload(headline: copy.headline, validUntilMs: validUntilMs),
      );
    case DistanceTone.sameCountry:
      final differs = offset != null && offset != now.timeZoneOffset.inMinutes;
      return withMap(
        CoupleWidgetPayload(
          headline: copy.headline,
          caption: apart,
          clockOffsetMinutes: differs ? offset : null,
          clockLine: differs,
          validUntilMs: validUntilMs,
        ),
      );
    case DistanceTone.countdown:
      final day = DateTime(now.year, now.month, now.day + d.daysUntilTogether!);
      return withMap(
        CoupleWidgetPayload(
          caption: apart,
          clockOffsetMinutes: offset,
          clockLine: offset != null,
          validUntilMs: validUntilMs,
          reunionDate: dateKey(day),
        ),
      );
    case DistanceTone.distant:
      return withMap(
        offset == null
            ? CoupleWidgetPayload(headline: apart, validUntilMs: validUntilMs)
            : CoupleWidgetPayload(
              headlineIsClock: true,
              caption: apart,
              clockOffsetMinutes: offset,
              validUntilMs: validUntilMs,
            ),
      );
  }
}

/// The lines a widget shows at [now]. The reference that W2's Swift and
/// Kotlin mirror, and what the in-app preview renders.
@immutable
class CoupleWidgetView {
  const CoupleWidgetView({
    required this.headline,
    this.caption,
    this.clockLine,
    this.neutral = false,
  });
  final String headline;
  final String? caption;
  final String? clockLine;
  final bool neutral;

  String get semanticsLabel =>
      [headline, caption, clockLine].whereType<String>().join('. ');
}

CoupleWidgetView resolveCoupleWidget(CoupleWidgetPayload stored, DateTime now) {
  final p = stored.current(now);
  final days = p.reunionDate == null ? null : _daysTo(p.reunionDate!, now);
  final offset = p.clockOffsetMinutes;
  final clock =
      offset == null
          ? null
          : '${formatClock(now.toUtc().add(Duration(minutes: offset)))} there';
  String countdown(int d) => switch (d) {
    0 => 'Together today',
    1 => 'Together tomorrow',
    _ => "$d days until you're together",
  };
  if (p.hasDistance) {
    if (days != null) {
      return CoupleWidgetView(
        headline: countdown(days),
        caption: p.caption,
        clockLine: p.clockLine ? clock : null,
      );
    }
    if (p.headlineIsClock && clock != null) {
      return CoupleWidgetView(headline: clock, caption: p.caption);
    }
    if (p.headline != null) {
      return CoupleWidgetView(
        headline: p.headline!,
        caption: p.caption,
        clockLine: p.clockLine ? clock : null,
      );
    }
  }
  if (days != null) {
    return days <= 1
        ? CoupleWidgetView(headline: countdown(days))
        : CoupleWidgetView(headline: '$days days', caption: "until you're together");
  }
  return const CoupleWidgetView(headline: neutralHeadline, neutral: true);
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `flutter test test/features/couple_map/widget/couple_widget_payload_test.dart`
Expected: all pass.

- [ ] **Step 5: Format the new files and run the analyzer**

Run:
```
dart format lib/features/couple_map/widget test/features/couple_map/widget
flutter analyze lib/features/couple_map/widget test/features/couple_map/widget 2>&1 | grep -E "^\s*(error|warning) "
```
Expected: no output from the grep. (Both folders are new, so formatting them is allowed.)

- [ ] **Step 6: Ledger**

Append `Task 1: complete (tests: …payload_test → N/N)` to the ledger. No commit.

---

### Task 2: Region frame (snapping, Mercator, unwrap, square fit)

**Files:**
- Create: `lib/features/couple_map/widget/domain/region_frame.dart`
- Test: `test/features/couple_map/widget/region_frame_test.dart`

**Interfaces:**
- Consumes: `GeoPoint`, `CoupleWidgetConfig` (Task 1).
- Produces:
  - `GeoPoint snapToGrid(GeoPoint p)`
  - `Offset mercator(GeoPoint p)` → world units (x 0..1 across −180..180, unbounded for unwrapped longitudes; y 0 at the top)
  - `class RegionFrame`:
    - `double left, top, side` (Mercator units);
    - `Offset self, partner` (0..1 within the frame);
    - `bool north` (the arc bows north);
    - `bool get isWorld`;
    - `String get cacheKey`.
  - `RegionFrame regionFrame(GeoPoint self, GeoPoint partner)`
  - `const earthCircumferenceKm = 40075.0;`

- [ ] **Step 1: Write the failing tests**

```dart
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
    final f = regionFrame((lat: 5.565, lng: -0.208), (lat: 51.505, lng: -0.125));
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/couple_map/widget/region_frame_test.dart`
Expected: FAIL to compile (`region_frame.dart` doesn't exist).

- [ ] **Step 3: Write the implementation**

```dart
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
  return Offset(
    (p.lng + 180) / 360,
    (1 - log(tan(pi / 4 + lat / 2)) / pi) / 2,
  );
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
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `flutter test test/features/couple_map/widget/region_frame_test.dart`
Expected: all pass. If a property fails, read the printed `reason` pair and fix the code, not the test. The world view is the only case allowed outside the central half.

- [ ] **Step 5: Format and analyze the new files (as in Task 1, Step 5)**

- [ ] **Step 6: Ledger**

Append `Task 2: complete (…)`.

---

### Task 3: World outline asset, build script and loader

**Files:**
- Create: `tool/build_land_outline.dart`
- Create: `assets/geo/land_50m_merc.bin` (generated), `assets/geo/README.md`
- Create: `lib/features/couple_map/widget/data/world_outline.dart`
- Modify: `pubspec.yaml` (add one asset line under `flutter: assets:`, after the existing `- assets/images/` block. Don't reflow anything else.)
- Test: `test/features/couple_map/widget/world_outline_test.dart`

**Interfaces:**
- Produces:
  - `class WorldOutline`:
    - `List<Float32List> rings` (interleaved x,y in world units 0..1);
    - `List<Rect> bounds`;
    - `static WorldOutline parse(ByteData data)`, which throws `FormatException` on a bad magic number;
    - `static const asset = 'assets/geo/land_50m_merc.bin'`;
    - `static const version = 1`.
  - `final worldOutlineProvider = FutureProvider<WorldOutline>(...)`, loaded from `rootBundle`.
  - **Binary format (little-endian):**
    - the ASCII bytes `LND1`;
    - `uint32` ring count;
    - per ring: a `uint32` point count n, then n × (`uint16` x, `uint16` y), where value = round(unit × 65535) and y comes from the Mercator formula with latitude clamped to ±85.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/widget/world_outline_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ByteData encode(List<List<(int, int)>> rings, {String magic = 'LND1'}) {
  final b = BytesBuilder();
  b.add(magic.codeUnits);
  final head = ByteData(4)..setUint32(0, rings.length, Endian.little);
  b.add(head.buffer.asUint8List());
  for (final r in rings) {
    final n = ByteData(4)..setUint32(0, r.length, Endian.little);
    b.add(n.buffer.asUint8List());
    for (final (x, y) in r) {
      final p =
          ByteData(4)
            ..setUint16(0, x, Endian.little)
            ..setUint16(2, y, Endian.little);
      b.add(p.buffer.asUint8List());
    }
  }
  return ByteData.sublistView(b.toBytes());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses rings into world units with their bounds', () {
    final o = WorldOutline.parse(
      encode([
        [(0, 0), (65535, 0), (65535, 32767)],
      ]),
    );
    expect(o.rings, hasLength(1));
    expect(o.rings.single[2], closeTo(1.0, 1e-6));
    expect(o.bounds.single.left, 0);
    expect(o.bounds.single.right, closeTo(1.0, 1e-6));
    expect(o.bounds.single.bottom, closeTo(0.5, 1e-4));
  });

  test('a wrong magic number is a FormatException', () {
    expect(
      () => WorldOutline.parse(encode(const [], magic: 'NOPE')),
      throwsFormatException,
    );
  });

  test('a truncated file is a FormatException', () {
    final full = encode([
      [(0, 0), (1, 1)],
    ]);
    expect(
      () => WorldOutline.parse(ByteData.sublistView(full, 0, full.lengthInBytes - 2)),
      throwsFormatException,
    );
  });

  test('the bundled outline loads, is real, and stays under 400 KB', () async {
    final file = File(WorldOutline.asset);
    expect(file.lengthSync(), lessThanOrEqualTo(400 * 1024));
    final o = WorldOutline.parse(await rootBundle.load(WorldOutline.asset));
    expect(o.rings.length, greaterThan(1000));
    final points = o.rings.fold<int>(0, (n, r) => n + r.length ~/ 2);
    expect(points, greaterThan(40000));
  });

  test('the licence note names Natural Earth', () {
    expect(
      File('assets/geo/README.md').readAsStringSync(),
      contains('Natural Earth'),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/couple_map/widget/world_outline_test.dart`
Expected: FAIL to compile (`world_outline.dart` doesn't exist).

- [ ] **Step 3: Write the build script**

```dart
// tool/build_land_outline.dart
// Builds assets/geo/land_50m_merc.bin from Natural Earth's 1:50m land
// GeoJSON (public domain). Usage:
//   dart run tool/build_land_outline.dart <ne_50m_land.geojson> assets/geo/land_50m_merc.bin
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _maxLat = 85.0;

int _q(double unit) => (unit.clamp(0.0, 1.0) * 65535).round();

(int, int) _project(num lng, num lat) {
  final la = lat.toDouble().clamp(-_maxLat, _maxLat) * pi / 180;
  final x = (lng.toDouble() + 180) / 360;
  final y = (1 - log(tan(pi / 4 + la / 2)) / pi) / 2;
  return (_q(x), _q(y));
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: build_land_outline <in.geojson> <out.bin>');
    exit(64);
  }
  final geo = jsonDecode(File(args[0]).readAsStringSync()) as Map;
  final rings = <List<(int, int)>>[];
  for (final f in geo['features'] as List) {
    final g = (f as Map)['geometry'] as Map;
    final polys =
        g['type'] == 'Polygon'
            ? [g['coordinates'] as List]
            : (g['coordinates'] as List).cast<List>();
    for (final poly in polys) {
      for (final ring in poly) {
        final out = <(int, int)>[];
        for (final c in ring as List) {
          final p = _project((c as List)[0] as num, c[1] as num);
          if (out.isEmpty || out.last != p) out.add(p);
        }
        if (out.length >= 3) rings.add(out);
      }
    }
  }
  final b = BytesBuilder()..add('LND1'.codeUnits);
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  u32(rings.length);
  for (final r in rings) {
    u32(r.length);
    for (final (x, y) in r) {
      b.add(
        (ByteData(4)
              ..setUint16(0, x, Endian.little)
              ..setUint16(2, y, Endian.little))
            .buffer
            .asUint8List(),
      );
    }
  }
  File(args[1])
    ..createSync(recursive: true)
    ..writeAsBytesSync(b.toBytes());
  stdout.writeln('${rings.length} rings → ${args[1]}');
}
```

- [ ] **Step 4: Fetch the source into the scratchpad and build the asset**

Run:
```
curl -fsSL -o "$SCRATCH/ne_50m_land.geojson" https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_land.geojson
dart run tool/build_land_outline.dart "$SCRATCH/ne_50m_land.geojson" assets/geo/land_50m_merc.bin
ls -l assets/geo/land_50m_merc.bin
```
Here `$SCRATCH` is the session scratchpad path.
Expected: about 1,400 rings, and a file around 250 KB (≤ 400 KB). The GeoJSON is never committed.

- [ ] **Step 5: Write the licence note and register the asset**

```markdown
<!-- assets/geo/README.md -->
# Geographic assets

`land_50m_merc.bin` — world land outline for the home-screen distance widget's
region map. Made with Natural Earth (1:50m land), public domain:
https://www.naturalearthdata.com/about/terms-of-use/

Built by `dart run tool/build_land_outline.dart <ne_50m_land.geojson> assets/geo/land_50m_merc.bin`.
Format: "LND1", uint32 ring count, then per ring uint32 n and n × (uint16 x,
uint16 y) Web Mercator world units × 65535 (latitude clamped to ±85).
Little-endian.
```

In `pubspec.yaml`, under `flutter: assets:`, add one line directly after the existing `- assets/images/` entry and its nested-folder lines:
```yaml
    - assets/geo/
```
Run `diff -u "$WS/snapshots/pubspec.yaml" pubspec.yaml`. Expected: exactly one added line.

- [ ] **Step 6: Write the loader**

```dart
// lib/features/couple_map/widget/data/world_outline.dart
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bundled land outline (Natural Earth 1:50m, public domain), already
/// in Web Mercator world units, so a render does no trigonometry.
class WorldOutline {
  WorldOutline._(this.rings, this.bounds);

  static const asset = 'assets/geo/land_50m_merc.bin';

  /// Bumped when the asset changes (part of the render cache key).
  static const version = 1;

  /// Interleaved x,y in world units (0..1).
  final List<Float32List> rings;
  final List<Rect> bounds;

  static WorldOutline parse(ByteData data) {
    try {
      if (data.lengthInBytes < 8 ||
          String.fromCharCodes([
                for (var i = 0; i < 4; i++) data.getUint8(i),
              ]) !=
              'LND1') {
        throw const FormatException('not a land outline');
      }
      var o = 4;
      final count = data.getUint32(o, Endian.little);
      o += 4;
      final rings = <Float32List>[];
      final bounds = <Rect>[];
      for (var r = 0; r < count; r++) {
        final n = data.getUint32(o, Endian.little);
        o += 4;
        final pts = Float32List(n * 2);
        var l = 1.0, t = 1.0, rt = 0.0, b = 0.0;
        for (var i = 0; i < n; i++) {
          final x = data.getUint16(o, Endian.little) / 65535;
          final y = data.getUint16(o + 2, Endian.little) / 65535;
          o += 4;
          pts[i * 2] = x;
          pts[i * 2 + 1] = y;
          if (x < l) l = x;
          if (x > rt) rt = x;
          if (y < t) t = y;
          if (y > b) b = y;
        }
        rings.add(pts);
        bounds.add(Rect.fromLTRB(l, t, rt, b));
      }
      return WorldOutline._(rings, bounds);
    } on RangeError {
      throw const FormatException('truncated land outline');
    }
  }
}

final worldOutlineProvider = FutureProvider<WorldOutline>(
  (ref) async => WorldOutline.parse(await rootBundle.load(WorldOutline.asset)),
);
```

- [ ] **Step 7: Run the tests and verify they pass**

Run: `flutter test test/features/couple_map/widget/world_outline_test.dart`
Expected: all pass.

- [ ] **Step 8: Format and analyze the new files**

Format: `tool/build_land_outline.dart`, `lib/features/couple_map/widget`, `test/features/couple_map/widget`. Don't format `pubspec.yaml`.

- [ ] **Step 9: Ledger**

Record the asset size and ring count in the ledger line.

---

### Task 4: Region map painter and PNG render

**Files:**
- Create: `lib/features/couple_map/widget/presentation/region_map_painter.dart`
- Test: `test/features/couple_map/widget/region_map_painter_test.dart` (goldens under `test/features/couple_map/widget/goldens/`)

**Interfaces:**
- Consumes: `RegionFrame`, `regionFrame` (Task 2); `WorldOutline` (Task 3); `CoupleWidgetConfig` (Task 1).
- Produces:
  - `class RegionMapPainter extends CustomPainter { RegionMapPainter({required RegionFrame frame, required WorldOutline outline}); }`
  - `Future<ui.Image> paintRegionMap(RegionFrame frame, WorldOutline outline, {int px})`
  - `Future<Uint8List> renderRegionMap(RegionFrame frame, WorldOutline outline, {int px})` (PNG bytes)
  - `const regionLandColor = Color(0x38808080);` (mid-grey at ~22 %)
  - `regionSelfColor = LightColors.primary`, `regionPartnerColor = LightColors.against`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/widget/region_map_painter_test.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:attune/features/couple_map/widget/domain/region_frame.dart';
import 'package:attune/features/couple_map/widget/presentation/region_map_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<WorldOutline> realOutline() async =>
    WorldOutline.parse(await rootBundle.load(WorldOutline.asset));

Future<Color> pixel(ui.Image img, Offset at) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = ((at.dy.round() * img.width) + at.dx.round()) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

Widget golden(RegionFrame f, WorldOutline o, Color bg) => Center(
  child: RepaintBoundary(
    child: Container(
      color: bg,
      width: 160,
      height: 160,
      child: CustomPaint(painter: RegionMapPainter(frame: f, outline: o)),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('glows are drawn opaque at the snapped areas; open sea is clear', () async {
    final o = await realOutline();
    final f = regionFrame((lat: 5.565, lng: -0.208), (lat: 51.505, lng: -0.125));
    final img = await paintRegionMap(f, o, px: 480);
    final self = await pixel(img, f.self * 480);
    final partner = await pixel(img, f.partner * 480);
    expect(self.a, closeTo(1, 0.02));
    expect(partner.a, closeTo(1, 0.02));
    expect(self, isNot(partner), reason: 'two different tones');
    img.dispose();
  });

  test('renderRegionMap returns a 480 px PNG', () async {
    final o = await realOutline();
    final f = regionFrame((lat: 5.565, lng: -0.208), (lat: 51.505, lng: -0.125));
    final png = await renderRegionMap(f, o);
    expect(png.sublist(1, 4), Uint8List.fromList('PNG'.codeUnits));
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 480);
    expect(frame.image.height, 480);
  });

  test('records the world view within 150 ms (spec §9 6.9, CI-host proxy)', () async {
    final o = await realOutline();
    final f = regionFrame((lat: 0, lng: 0), (lat: 0, lng: 180));
    final painter = RegionMapPainter(frame: f, outline: o);
    void paintOnce() {
      final rec = ui.PictureRecorder();
      painter.paint(Canvas(rec), const Size.square(480));
      rec.endRecording().dispose();
    }

    paintOnce(); // warm up
    final sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      paintOnce();
    }
    expect(sw.elapsedMilliseconds / 5, lessThan(150));
  });

  test('rasterises the world view to 480 px within 1 s (measured for the ledger)', () async {
    final o = await realOutline();
    final f = regionFrame((lat: 0, lng: 0), (lat: 0, lng: 180));
    (await paintRegionMap(f, o)).dispose(); // warm up
    final sw = Stopwatch()..start();
    for (var i = 0; i < 3; i++) {
      (await paintRegionMap(f, o)).dispose();
    }
    final avg = sw.elapsedMilliseconds / 3;
    // ignore: avoid_print
    print('region map rasterise avg: ${avg.toStringAsFixed(1)} ms');
    expect(avg, lessThan(1000));
  });

  for (final (name, a, b) in [
    ('far_apart', (lat: 5.565, lng: -0.208), (lat: 51.505, lng: -0.125)),
    ('pacific', (lat: -36.85, lng: 174.76), (lat: 34.05, lng: -118.24)),
    ('world', (lat: 0.0, lng: 0.0), (lat: 0.0, lng: 180.0)),
    ('minimum_span', (lat: 5.565, lng: -0.208), (lat: 6.7, lng: -1.6)),
  ]) {
    for (final (mode, bg) in [
      ('light', const Color(0xFFF2F2F7)),
      ('dark', const Color(0xFF1C1C1E)),
    ]) {
      testWidgets('golden: $name on $mode', (t) async {
        final o = (await t.runAsync(realOutline))!;
        await t.pumpWidget(golden(regionFrame(a, b), o, bg));
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/region_map_${name}_$mode.png'),
        );
      });
    }
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/couple_map/widget/region_map_painter_test.dart`
Expected: FAIL to compile (`region_map_painter.dart` doesn't exist).

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/couple_map/widget/presentation/region_map_painter.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:attune/app/theme/app_colors.dart';
import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/region_frame.dart';
import 'package:flutter/material.dart';

/// Mid-grey at ~22 %: reads on light and dark widget backgrounds alike, so
/// one transparent image serves both (spec §3.3).
const regionLandColor = Color(0x38808080);

/// Mine is the app's green; theirs the warm accent.
const regionSelfColor = LightColors.primary;
const regionPartnerColor = LightColors.against;

/// Land, two fixed-size glows and a dashed arc. No text, labels or dots.
class RegionMapPainter extends CustomPainter {
  RegionMapPainter({required this.frame, required this.outline});

  final RegionFrame frame;
  final WorldOutline outline;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / frame.side;
    final view = Rect.fromLTWH(frame.left, frame.top, frame.side, frame.side);
    final land = Paint()..color = regionLandColor;
    // Copies one world either side fill the frame across the antimeridian.
    for (final shift in const [-1.0, 0.0, 1.0]) {
      final path = Path();
      for (var r = 0; r < outline.rings.length; r++) {
        final b = outline.bounds[r].shift(Offset(shift, 0));
        if (!b.overlaps(view)) continue;
        if (b.width * scale < 1 && b.height * scale < 1) continue;
        final pts = outline.rings[r];
        path.moveTo(
          (pts[0] + shift - frame.left) * scale,
          (pts[1] - frame.top) * scale,
        );
        for (var i = 2; i < pts.length; i += 2) {
          path.lineTo(
            (pts[i] + shift - frame.left) * scale,
            (pts[i + 1] - frame.top) * scale,
          );
        }
        path.close();
      }
      canvas.drawPath(path, land);
    }

    final a = Offset(frame.self.dx * size.width, frame.self.dy * size.height);
    final b = Offset(
      frame.partner.dx * size.width,
      frame.partner.dy * size.height,
    );
    final glow = size.width * CoupleWidgetConfig.glowRadiusFraction;
    if ((b - a).distance > glow) {
      final mid = (a + b) / 2;
      final bow = (b - a).distance * 0.25;
      final control = mid + Offset(0, frame.north ? -bow : bow);
      final arc =
          Path()
            ..moveTo(a.dx, a.dy)
            ..quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);
      final dash =
          Paint()
            ..color = regionSelfColor.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = size.width / 120;
      final on = size.width / 48;
      final off = size.width / 64;
      for (final m in arc.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += on + off) {
          canvas.drawPath(m.extractPath(d, d + on), dash);
        }
      }
    }
    _glow(canvas, a, glow, regionSelfColor);
    _glow(canvas, b, glow, regionPartnerColor);
  }

  void _glow(Canvas canvas, Offset c, double r, Color color) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color, color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
          stops: const [0, 0.28, 0.55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(RegionMapPainter old) =>
      old.frame.cacheKey != frame.cacheKey || old.outline != outline;
}

Future<ui.Image> paintRegionMap(
  RegionFrame frame,
  WorldOutline outline, {
  int px = CoupleWidgetConfig.imagePx,
}) {
  final rec = ui.PictureRecorder();
  RegionMapPainter(
    frame: frame,
    outline: outline,
  ).paint(Canvas(rec), Size.square(px.toDouble()));
  final picture = rec.endRecording();
  return picture.toImage(px, px).whenComplete(picture.dispose);
}

/// PNG bytes for the App Group (spec §3.3: 480 × 480, transparent sea).
Future<Uint8List> renderRegionMap(
  RegionFrame frame,
  WorldOutline outline, {
  int px = CoupleWidgetConfig.imagePx,
}) async {
  final img = await paintRegionMap(frame, outline, px: px);
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('png encode failed');
    return data.buffer.asUint8List();
  } finally {
    img.dispose();
  }
}
```

- [ ] **Step 4: Generate the goldens, then look at them**

Run: `flutter test --update-goldens test/features/couple_map/widget/region_map_painter_test.dart`
Then open each `goldens/region_map_*.png` with the Read tool and check:
- far_apart: West Africa and Europe;
- pacific: the arc crosses the sea;
- world: the whole world;
- minimum_span: Ghana at roughly 600 km across.

Also check that two glows are visible and inside the frame, and that there are no labels.

- [ ] **Step 5: Run the tests and verify they pass**

Run: `flutter test test/features/couple_map/widget/region_map_painter_test.dart`
Expected: all pass, including both benchmarks. Record the record-time and rasterise averages in the ledger. The 1 s rasterise bound is a CI guard; the real budget is the 2 s render timeout plus the device check on a low-end Android.

- [ ] **Step 6: Format and analyze the new files**

- [ ] **Step 7: Ledger**

---

### Task 5: Sync, store seam, clearing and backup excludes

**Files:**
- Create: `lib/features/couple_map/widget/data/couple_widget_sync.dart`
- Modify: `lib/features/couple_map/data/couple_map_device_data.dart` (start the widget clear first)
- Modify: `lib/features/together/data/together_device_surfaces.dart` (one `await` line + import)
- Modify: `android/app/src/main/res/xml/backup_rules.xml`, `android/app/src/main/res/xml/data_extraction_rules.xml`
- Test: `test/features/couple_map/widget/couple_widget_sync_test.dart`, plus additions to `test/features/couple_map/couple_map_device_data_test.dart`
- Create (test support): `test/features/couple_map/widget/support/memory_widget_store.dart`

**Interfaces:**
- Consumes: `CoupleWidgetPayload` (Task 1); `togetherWidgetAppGroup` (`lib/features/together/data/together_widget_sync.dart`).
- Produces:
  - `const coupleWidgetEnabledKey = 'couple_widget_enabled';`, `coupleWidgetPayloadKey = 'couple_widget_v1'`, `coupleWidgetMapKey = 'couple_widget_map'`
  - `sealed class MapUpdate` with `KeepMap`, `ReplaceMap(Uint8List png)` and `RemoveMap`
  - `abstract class CoupleWidgetStore { Future<String?> readPayload(); Future<void> writePayload(String json); Future<void> writeMap(Uint8List png); Future<void> removeMap(); Future<void> notifyWidgets(); }`
  - `class HomeWidgetCoupleStore implements CoupleWidgetStore`
  - `class CoupleWidgetSync` (static members):
    - `store`, `generation`;
    - `Future<bool> isEnabled()`;
    - `Future<bool> publish(CoupleWidgetPayload p, {required MapUpdate map, required int generation})`;
    - `Future<void> hideDistanceNow()`;
    - `Future<void> clear({bool resetOptIn = true})`;
    - `Future<void> dropExpired(DateTime now)`.

- [ ] **Step 1: Write the test support store**

```dart
// test/features/couple_map/widget/support/memory_widget_store.dart
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';

class MemoryCoupleWidgetStore implements CoupleWidgetStore {
  String? payload;
  Uint8List? map;
  int notified = 0;
  final log = <String>[];

  @override
  Future<String?> readPayload() async => payload;

  @override
  Future<void> writePayload(String json) async {
    log.add('payload');
    payload = json;
  }

  @override
  Future<void> writeMap(Uint8List png) async {
    log.add('map');
    map = png;
  }

  @override
  Future<void> removeMap() async {
    log.add('removeMap');
    map = null;
  }

  @override
  Future<void> notifyWidgets() async {
    log.add('notify');
    notified++;
  }
}

/// Android before W2: the provider class doesn't exist, so updateWidget
/// throws a PlatformException after the data is written.
class NotifyFailsStore extends MemoryCoupleWidgetStore {
  @override
  Future<void> notifyWidgets() => throw Exception('-3 no provider class');
}

class ThrowingCoupleWidgetStore implements CoupleWidgetStore {
  @override
  Future<String?> readPayload() => throw Exception('no plugin');
  @override
  Future<void> writePayload(String json) => throw Exception('no plugin');
  @override
  Future<void> writeMap(Uint8List png) => throw Exception('no plugin');
  @override
  Future<void> removeMap() => throw Exception('no plugin');
  @override
  Future<void> notifyWidgets() => throw Exception('no plugin');
}
```

- [ ] **Step 2: Write the failing tests**

```dart
// test/features/couple_map/widget/couple_widget_sync_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_widget_store.dart';

final now = DateTime(2026, 10, 16, 12);
final png = Uint8List.fromList([1, 2, 3]);
CoupleWidgetPayload distance() => CoupleWidgetPayload(
  caption: '5.1k km apart',
  validUntilMs: now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
  reunionDate: '2026-10-28',
);

void main() {
  late MemoryCoupleWidgetStore store;
  setUp(() {
    store = MemoryCoupleWidgetStore();
    CoupleWidgetSync.store = store;
  });

  Future<void> optIn(bool on) async =>
      SharedPreferences.setMockInitialValues({coupleWidgetEnabledKey: on});

  test('publishes only when opted in, read from storage', () async {
    await optIn(false);
    final g = CoupleWidgetSync.generation;
    expect(
      await CoupleWidgetSync.publish(distance(), map: ReplaceMap(png), generation: g),
      isFalse,
    );
    expect(store.payload, isNull);
    await optIn(true);
    expect(
      await CoupleWidgetSync.publish(distance(), map: ReplaceMap(png), generation: g),
      isTrue,
    );
    expect(CoupleWidgetPayload.decode(store.payload), distance());
    expect(store.map, png);
    expect(store.notified, 1);
  });

  test('a stale generation never writes', () async {
    await optIn(true);
    final g = CoupleWidgetSync.generation;
    await CoupleWidgetSync.hideDistanceNow();
    store.log.clear();
    expect(
      await CoupleWidgetSync.publish(distance(), map: ReplaceMap(png), generation: g),
      isFalse,
    );
    expect(store.log, isEmpty);
  });

  test('no distance part removes the map', () async {
    await optIn(true);
    store.map = png;
    await CoupleWidgetSync.publish(
      const CoupleWidgetPayload(reunionDate: '2026-10-28'),
      map: const KeepMap(),
      generation: CoupleWidgetSync.generation,
    );
    expect(store.map, isNull);
  });

  test('hideDistanceNow keeps the reunion, drops distance and map, bumps the generation', () async {
    await optIn(true);
    store.payload = distance().encode();
    store.map = png;
    final g = CoupleWidgetSync.generation;
    await CoupleWidgetSync.hideDistanceNow();
    expect(CoupleWidgetSync.generation, g + 1);
    final p = CoupleWidgetPayload.decode(store.payload);
    expect(p.hasDistance, isFalse);
    expect(p.reunionDate, '2026-10-28');
    expect(store.map, isNull);
  });

  test('clear empties, broadcasts before deleting the map, and resets the opt-in', () async {
    await optIn(true);
    store.payload = distance().encode();
    store.map = png;
    await CoupleWidgetSync.clear();
    expect(CoupleWidgetPayload.decode(store.payload), CoupleWidgetPayload.empty);
    expect(store.map, isNull);
    expect(store.log.indexOf('notify'), lessThan(store.log.indexOf('removeMap')));
    expect(await CoupleWidgetSync.isEnabled(), isFalse);
  });

  test('clear(resetOptIn: false) keeps the choice (flag off)', () async {
    await optIn(true);
    await CoupleWidgetSync.clear(resetOptIn: false);
    expect(await CoupleWidgetSync.isEnabled(), isTrue);
  });

  test('dropExpired removes a passed distance and its map from storage (§4.2)', () async {
    await optIn(true);
    store.payload =
        CoupleWidgetPayload(
          caption: 'x',
          validUntilMs: now.millisecondsSinceEpoch - 1,
          reunionDate: '2026-10-28',
        ).encode();
    store.map = png;
    await CoupleWidgetSync.dropExpired(now);
    final p = CoupleWidgetPayload.decode(store.payload);
    expect(p.hasDistance, isFalse);
    expect(p.reunionDate, '2026-10-28');
    expect(store.map, isNull);
  });

  test('a failed widget refresh still counts as written (Android before W2)', () async {
    await optIn(true);
    final s = NotifyFailsStore();
    CoupleWidgetSync.store = s;
    s.map = png;
    expect(
      await CoupleWidgetSync.publish(
        distance(),
        map: ReplaceMap(png),
        generation: CoupleWidgetSync.generation,
      ),
      isTrue,
    );
    expect(CoupleWidgetPayload.decode(s.payload), distance());
    await CoupleWidgetSync.hideDistanceNow();
    expect(s.map, isNull, reason: 'a notify failure must not skip the delete');
  });

  test('never throws without the plugin', () async {
    await optIn(true);
    CoupleWidgetSync.store = ThrowingCoupleWidgetStore();
    await CoupleWidgetSync.clear();
    await CoupleWidgetSync.hideDistanceNow();
    await CoupleWidgetSync.dropExpired(now);
    expect(
      await CoupleWidgetSync.publish(
        distance(),
        map: const KeepMap(),
        generation: CoupleWidgetSync.generation,
      ),
      isFalse,
    );
  });

  test('Android backup never carries the widget storage (§4.4)', () {
    for (final path in [
      'android/app/src/main/res/xml/backup_rules.xml',
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      expect(
        RegExp('domain="sharedpref" path="HomeWidgetPreferences.xml"').allMatches(xml).length,
        path.contains('extraction') ? 2 : 1,
        reason: path,
      );
      expect(
        RegExp('domain="file" path="home_widget/"').allMatches(xml).length,
        path.contains('extraction') ? 2 : 1,
        reason: path,
      );
    }
  });
}
```

Add to `test/features/couple_map/couple_map_device_data_test.dart`. This needs an import of `couple_widget_sync.dart`, an import of `widget/support/memory_widget_store.dart`, and an import of `package:shared_preferences/shared_preferences.dart`. Also add, at the top of `main()`, so the existing tests never reach the real plugin:
```dart
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    CoupleWidgetSync.store = MemoryCoupleWidgetStore();
    SharedPreferences.setMockInitialValues({});
  });
```
Then add the two tests:

```dart
  test('quick exit clears the home-screen widget first (widget spec §6.4)', () async {
    SharedPreferences.setMockInitialValues({'couple_widget_enabled': true});
    final widget = MemoryCoupleWidgetStore()..payload = '{"v":1,"caption":"x","validUntilMs":9999999999999}';
    CoupleWidgetSync.store = widget;
    final order = <String>[];
    await clearCoupleMapDeviceData(
      clearMapCache: () async => order.add('map cache'),
      pins: FakePinImageRenderer(),
      store: MemoryCoupleMapLocalStore(),
    );
    expect(widget.payload, '{"v":1}');
    expect(widget.notified, 1);
    expect(await CoupleWidgetSync.isEnabled(), isFalse);
  });

  test('sign-out and the other Together exits clear the widget too', () {
    final source =
        File('lib/features/together/data/together_device_surfaces.dart').readAsStringSync();
    expect(source.contains('await CoupleWidgetSync.clear();'), isTrue);
  });
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/features/couple_map/widget/couple_widget_sync_test.dart test/features/couple_map/couple_map_device_data_test.dart`
Expected: the sync test fails to compile (`couple_widget_sync.dart` missing); the device-data additions fail.

- [ ] **Step 4: Write the sync**

```dart
// lib/features/couple_map/widget/data/couple_widget_sync.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/together/data/together_widget_sync.dart'
    show togetherWidgetAppGroup;
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This phone's opt-in (spec §2 ruling 1). Off unless set; every clearing
/// path resets it.
const coupleWidgetEnabledKey = 'couple_widget_enabled';
const coupleWidgetPayloadKey = 'couple_widget_v1';
const coupleWidgetMapKey = 'couple_widget_map';

sealed class MapUpdate {
  const MapUpdate();
}

class KeepMap extends MapUpdate {
  const KeepMap();
}

class ReplaceMap extends MapUpdate {
  const ReplaceMap(this.png);
  final Uint8List png;
}

class RemoveMap extends MapUpdate {
  const RemoveMap();
}

/// Where the native widgets read from (a seam for tests).
abstract class CoupleWidgetStore {
  Future<String?> readPayload();
  Future<void> writePayload(String json);
  Future<void> writeMap(Uint8List png);
  Future<void> removeMap();
  Future<void> notifyWidgets();
}

class HomeWidgetCoupleStore implements CoupleWidgetStore {
  const HomeWidgetCoupleStore();

  Future<void> _group() => HomeWidget.setAppGroupId(togetherWidgetAppGroup);

  @override
  Future<String?> readPayload() async {
    await _group();
    return HomeWidget.getWidgetData<String>(coupleWidgetPayloadKey);
  }

  @override
  Future<void> writePayload(String json) async {
    await _group();
    await HomeWidget.saveWidgetData<String>(coupleWidgetPayloadKey, json);
  }

  @override
  Future<void> writeMap(Uint8List png) async {
    await _group();
    await HomeWidget.saveFile(coupleWidgetMapKey, png, extension: 'png');
  }

  @override
  Future<void> removeMap() async {
    await _group();
    // A null value deletes the plugin-managed file too.
    await HomeWidget.saveWidgetData<String>(coupleWidgetMapKey, null);
  }

  @override
  Future<void> notifyWidgets() => HomeWidget.updateWidget(
    iOSName: 'CoupleWidget',
    qualifiedAndroidName: 'com.barsopus.attune.CoupleWidgetProvider',
  );
}

/// Fills, hides or empties the home-screen distance widget. Never throws: a
/// phone without the widget (or a test without the plugin) must not break
/// the caller. Writes are serialised, and a write that started under an
/// older [generation] is dropped (spec §4.1).
class CoupleWidgetSync {
  static CoupleWidgetStore store = const HomeWidgetCoupleStore();

  /// Bumped by every state-changing write (hide, clear). A read or render
  /// that began under an older value must not land.
  static int generation = 0;

  static Future<void> _tail = Future.value();

  static Future<T> _serial<T>(Future<T> Function() body) {
    final next = _tail.then((_) => body());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<bool> isEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(
            coupleWidgetEnabledKey,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> publish(
    CoupleWidgetPayload payload, {
    required MapUpdate map,
    required int generation,
  }) => _serial(() async {
    try {
      if (generation != CoupleWidgetSync.generation) return false;
      if (!await isEnabled()) return false;
      if (!payload.hasDistance) {
        await store.removeMap();
      } else if (map is ReplaceMap) {
        await store.writeMap(map.png);
      } else if (map is RemoveMap) {
        await store.removeMap();
      }
      if (generation != CoupleWidgetSync.generation) return false;
      await store.writePayload(payload.encode());
      // Written is written: before W2 ships the Android provider, this
      // throws (ClassNotFound → PlatformException) on every call.
      try {
        await store.notifyWidgets();
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  });

  /// Pause, stop, sharing off: the distance goes at once, the reunion stays.
  static Future<void> hideDistanceNow() {
    generation++;
    return _serial(() async {
      if (!await isEnabled()) return;
      try {
        final p = CoupleWidgetPayload.decode(await store.readPayload());
        await store.writePayload(p.withoutDistance().encode());
      } catch (_) {}
      try {
        await store.notifyWidgets();
      } catch (_) {}
      try {
        await store.removeMap();
      } catch (_) {}
    });
  }

  /// Quick exit, sign-out, account deletion, end relationship, toggle off,
  /// flag off: nothing readable is left (spec §6.4). The broadcast goes out
  /// before the image delete, so Android's 300 ms quick exit still repaints.
  static Future<void> clear({bool resetOptIn = true}) {
    generation++;
    return _serial(() async {
      if (resetOptIn) {
        try {
          await (await SharedPreferences.getInstance()).remove(
            coupleWidgetEnabledKey,
          );
        } catch (_) {}
      }
      try {
        await store.writePayload(CoupleWidgetPayload.empty.encode());
      } catch (_) {}
      try {
        await store.notifyWidgets();
      } catch (_) {}
      try {
        await store.removeMap();
      } catch (_) {}
    });
  }

  /// At app open: what has run out is deleted from storage, not just hidden.
  static Future<void> dropExpired(DateTime now) => _serial(() async {
    try {
      final raw = await store.readPayload();
      final stored = CoupleWidgetPayload.decode(raw);
      final current = stored.current(now);
      if (current == stored) return;
      await store.writePayload(current.encode());
      if (!current.hasDistance) await store.removeMap();
    } catch (_) {
      return;
    }
    try {
      await store.notifyWidgets();
    } catch (_) {}
  });
}
```

Before editing the shared files, re-read each one: the owner edits by hand.

**Edit `lib/features/couple_map/data/couple_map_device_data.dart`.** Add the import `package:attune/features/couple_map/widget/data/couple_widget_sync.dart`. Add a doc sentence: "The home-screen widget is cleared first (widget spec §6.4)." Then change the body to start the widget clear first and await it with the rest:
```dart
  final widget = CoupleWidgetSync.clear();
  (pins ?? sharedPinImageRenderer).clear();
  final s = store ?? SecureCoupleMapLocalStore();
  await Future.wait([
    widget,
    for (final key in CoupleMapLocalKeys.all) s.delete(key),
    Future(
      () => (clearMapCache ?? MapboxMapsOptions.clearData)(),
    ).catchError((Object _) {}),
  ]);
```

**Edit `lib/features/together/data/together_device_surfaces.dart`.** Add the import `package:attune/features/couple_map/widget/data/couple_widget_sync.dart`. Insert as the **first** line inside `clearTogetherDeviceSurfaces()`, before `TogetherWidgetSync.clear()`, so sign-out never waits on the calendar delete before the widget goes:
```dart
  await CoupleWidgetSync.clear();
```
Extend its doc comment by one line: "…and the couple map's distance widget (widget spec §6.4)."

**Edit both backup XML files.** In `backup_rules.xml`, add inside `<full-backup-content>`:
```xml
    <exclude domain="sharedpref" path="HomeWidgetPreferences.xml" />
    <exclude domain="file" path="home_widget/" />
```
In `data_extraction_rules.xml`, add the same two lines inside both `<cloud-backup>` and `<device-transfer>`. Then update each file's header comment with one sentence: "Also excludes the home-screen widgets' data (Together and the distance widget; widget spec §4.4)."

- [ ] **Step 5: Run the tests and verify they pass**

Run: `flutter test test/features/couple_map/widget/couple_widget_sync_test.dart test/features/couple_map/couple_map_device_data_test.dart test/features/together/`
Expected: all pass. The Together tests prove `clearTogetherDeviceSurfaces` still works; if one stubs `TogetherWidgetSync.store` only, the couple-widget clear swallows the missing plugin.

- [ ] **Step 6: Check the diffs and analyze**

Snapshot-diff the four shared files. Expected: only the added lines, plus the two changed lines in `couple_map_device_data.dart`. Then run the analyzer gate on all touched Dart files. Format only the new files.

- [ ] **Step 7: Ledger**

Note the shared-file regression risk:
- quick exit: low (the clear never throws, and it runs in parallel);
- Together exits: low (an extra awaited no-throw call).

---

### Task 6: Presence read hook (shared file)

**Files:**
- Modify: `lib/features/location/presentation/providers/presence_providers.dart`
- Test: `test/features/location/presence_reads_hook_test.dart`

**Interfaces:**
- Consumes: `coupleMapPresenceProvider`, `presenceRepositoryProvider`.
- Produces: `final presenceReadsProvider = Provider<StreamController<(String, CoupleMapPresence)>>`, a broadcast stream of every read the couple-map provider emits.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/location/presence_reads_hook_test.dart
import 'dart:async';

import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'presence_repository_test.dart' show FakePresenceGateway, FakeSampler;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(FakePresenceGateway g) => ProviderContainer(
    overrides: [
      presenceGatewayProvider.overrideWithValue(g),
      presenceSamplerProvider.overrideWithValue(FakeSampler()),
      presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
    ],
  );

  test('every couple-map read is announced with its relationship', () async {
    final g = FakePresenceGateway({
      'couple_map_presence': (_) => const [
        {'who': 'self', 'freshness': 'fresh', 'my_paused_until': 'infinity'},
      ],
    });
    final c = container(g);
    addTearDown(c.dispose);
    final heard = <(String, CoupleMapPresence)>[];
    c.read(presenceReadsProvider).stream.listen(heard.add);
    final sub = c.listen(coupleMapPresenceProvider('r1'), (_, __) {});
    await c.read(coupleMapPresenceProvider('r1').future);
    await Future<void>.delayed(Duration.zero);
    expect(heard.single.$1, 'r1');
    expect(heard.single.$2.state.status, PresenceStatus.paused);
    sub.close();
  });

  test('listening to the hook never starts the couple-map provider (no sampling)', () async {
    final g = FakePresenceGateway({'couple_map_presence': (_) => const []});
    final c = container(g);
    addTearDown(c.dispose);
    c.read(presenceReadsProvider).stream.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(g.calls, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/location/presence_reads_hook_test.dart`
Expected: FAIL to compile, with "Undefined name 'presenceReadsProvider'".

- [ ] **Step 3: Make the surgical edit (re-read the file first)**

Add just above `coupleMapPresenceProvider`:
```dart
/// Every couple-map presence read, as it lands. The home-screen widget
/// listens here; it must never watch coupleMapPresenceProvider itself, or
/// that autoDispose provider would stay alive and keep sampling (widget
/// spec §4.1).
final presenceReadsProvider =
    Provider<StreamController<(String, CoupleMapPresence)>>((ref) {
      final c = StreamController<(String, CoupleMapPresence)>.broadcast();
      ref.onDispose(c.close);
      return c;
    });
```
Inside `refresh()`, change the one emitting line:
```dart
      if (!closed && !controller.isClosed) controller.add(p);
```
to:
```dart
      if (!closed && !controller.isClosed) {
        controller.add(p);
        try {
          ref.read(presenceReadsProvider).add((relationshipId, p));
        } catch (_) {}
      }
```
Check that `CoupleMapPresence` is already imported (it is used as the family's value type).

- [ ] **Step 4: Run the tests, including every presence consumer**

Run: `flutter test test/features/location/ test/features/couple_map/ test/features/chat/ test/features/planning/`
Expected: all pass. This is a shared kernel file, so the wider run is the regression gate.

- [ ] **Step 5: Diff check and analyzer**

`diff -u` against the snapshot shows only the new provider (about 12 added lines) and the one emitting line becoming five. Don't format this file.

- [ ] **Step 6: Ledger**

Shared-file risk: low. The hook runs after the existing emit, inside a try, and changes nothing for existing listeners.

---

### Task 7: Publisher (reads only, debounce, generation, render budget)

**Files:**
- Create: `lib/features/couple_map/widget/presentation/couple_widget_publisher.dart`
- Modify: `lib/app/app.dart` (one microtask line in `initState` + import)
- Test: `test/features/couple_map/widget/couple_widget_publisher_test.dart`

**Interfaces:**
- Consumes:
  - `presenceReadsProvider` (Task 6), `presenceRepositoryProvider`, `coupleMapEnabledProvider` (`presence_providers.dart`);
  - `currentRelationshipIdProvider` from `lib/features/planning/presentation/planning_providers.dart`;
  - `remindersListProvider` (`lib/features/reminders/presentation/providers/reminders_providers.dart`; `ReminderModel.title`, `.remindAt`);
  - `buildCoupleWidget`, `resolveCoupleWidget` (Task 1), `regionFrame` (Task 2), `worldOutlineProvider`, `WorldOutline.version` (Task 3), `renderRegionMap` (Task 4), `CoupleWidgetSync`, `MapUpdate` (Task 5).
- Produces:
  - `class CoupleWidgetPreview { CoupleWidgetView view; Uint8List? map; }`
  - `class CoupleWidgetPublisher`:
    - `Future<void> startIfEnabled()`, `void start()`, `bool get started`;
    - `Future<void> refreshFromServer({bool force = false})`;
    - `ValueNotifier<CoupleWidgetPreview?> preview`;
    - test seams: `DateTime Function() clock`, `Future<Uint8List> Function(RegionFrame, WorldOutline) render`, `Duration renderBudget`;
    - `void dispose()`.
  - `final coupleWidgetPublisherProvider = Provider<CoupleWidgetPublisher>`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/widget/couple_widget_publisher_test.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    show currentRelationshipIdProvider;
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    show remindersListProvider, RemindersListNotifier;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../location/presence_repository_test.dart'
    show FakePresenceGateway, FakeSampler;
import 'support/memory_widget_store.dart';

class _Reminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => <ReminderModel>[];

  /// A new list instance, so listeners are told.
  void touch() => state = AsyncData(<ReminderModel>[]);
}

const farRows = [
  {
    'who': 'self',
    'cell_lat': 5.565,
    'cell_lng': -0.208,
    'freshness': 'fresh',
    'utc_offset_minutes': 0,
  },
  {
    'who': 'partner',
    'cell_lat': 51.505,
    'cell_lng': -0.125,
    'freshness': 'fresh',
    'utc_offset_minutes': 60,
    'distance_km': 5100,
    'together': false,
  },
];

const storedDistance = '{"v":1,"caption":"x","validUntilMs":9999999999999}';

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

int reads(FakePresenceGateway g) =>
    g.calls.where((c) => c.$1 == 'couple_map_presence').length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryCoupleWidgetStore store;
  late FakeSampler sampler;
  late WorldOutline outline;

  setUpAll(() async {
    outline = WorldOutline.parse(await rootBundle.load(WorldOutline.asset));
  });

  setUp(() {
    store = MemoryCoupleWidgetStore();
    CoupleWidgetSync.store = store;
    sampler = FakeSampler();
    SharedPreferences.setMockInitialValues({coupleWidgetEnabledKey: true});
  });

  (ProviderContainer, CoupleWidgetPublisher) make(
    FakePresenceGateway g, {
    bool flag = true,
    DateTime Function()? clock,
    bool stubRender = false,
  }) {
    final c = ProviderContainer(
      overrides: [
        presenceGatewayProvider.overrideWithValue(g),
        presenceSamplerProvider.overrideWithValue(sampler),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        coupleMapEnabledProvider.overrideWith((ref) async => flag),
        currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
        remindersListProvider.overrideWith(_Reminders.new),
        worldOutlineProvider.overrideWith((ref) async => outline),
      ],
    );
    addTearDown(c.dispose);
    final p = c.read(coupleWidgetPublisherProvider);
    if (clock != null) p.clock = clock;
    if (stubRender) p.render = (_, __) async => Uint8List.fromList([1]);
    return (c, p);
  }

  FakePresenceGateway far() =>
      FakePresenceGateway({'couple_map_presence': (_) => farRows});

  test('a resume read writes distance and map, and never records or samples', () async {
    final g = far();
    final (_, p) = make(g);
    await p.refreshFromServer(force: true);
    final payload = CoupleWidgetPayload.decode(store.payload);
    expect(payload.hasDistance, isTrue);
    expect(payload.caption, '5.1k km apart');
    expect(store.map, isNotNull);
    expect(g.calls.map((c) => c.$1), isNot(contains('record_presence')));
    expect(sampler.sampled, 0);
    expect(p.preview.value?.view.caption, '5.1k km apart');
  });

  test('not opted in: no read, nothing written', () async {
    SharedPreferences.setMockInitialValues({});
    final g = far();
    final (_, p) = make(g);
    await p.refreshFromServer(force: true);
    expect(g.calls, isEmpty);
    expect(store.payload, isNull);
  });

  test('at most one read per 5 minutes', () async {
    var t = DateTime(2026, 10, 16, 12);
    final g = far();
    final (_, p) = make(g, clock: () => t, stubRender: true);
    await p.refreshFromServer();
    await p.refreshFromServer();
    expect(reads(g), 1);
    t = t.add(const Duration(minutes: 6));
    await p.refreshFromServer();
    expect(reads(g), 2);
  });

  test('a pause during an in-flight read drops the read (spec §4.1)', () async {
    final gate = Completer<List<Map<String, Object?>>>();
    final g = FakePresenceGateway({'couple_map_presence': (_) => gate.future});
    final (_, p) = make(g, stubRender: true);
    final pending = p.refreshFromServer(force: true);
    await Future<void>.delayed(Duration.zero);
    await CoupleWidgetSync.hideDistanceNow();
    gate.complete(farRows);
    await pending;
    expect(CoupleWidgetPayload.decode(store.payload).hasDistance, isFalse);
    expect(store.map, isNull);
  });

  test('a clear during a slow render drops the render (Review Focus 5)', () async {
    final gate = Completer<Uint8List>();
    final (_, p) = make(far());
    p.render = (_, __) => gate.future;
    final pending = p.refreshFromServer(force: true);
    // Let the read land and the render start (it waits on [gate]).
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await CoupleWidgetSync.clear();
    gate.complete(Uint8List.fromList([9]));
    await pending;
    expect(CoupleWidgetPayload.decode(store.payload), CoupleWidgetPayload.empty);
    expect(store.map, isNull);
  });

  test('a render over budget publishes the text layout', () async {
    final (_, p) = make(far());
    p.render = (_, __) => Completer<Uint8List>().future;
    p.renderBudget = const Duration(milliseconds: 10);
    await p.refreshFromServer(force: true);
    expect(CoupleWidgetPayload.decode(store.payload).hasDistance, isTrue);
    expect(store.map, isNull);
  });

  test('flag off (after a good read) clears without forgetting the choice', () async {
    store.payload = storedDistance;
    final (_, p) = make(far(), flag: false);
    await p.refreshFromServer(force: true);
    expect(store.payload, '{"v":1}');
    expect(await CoupleWidgetSync.isEnabled(), isTrue);
  });

  test('offline at launch never clears, even with the flag reading false', () async {
    store.payload = storedDistance;
    final g = FakePresenceGateway({
      'couple_map_presence': (_) => throw Exception('offline'),
    });
    final (_, p) = make(g, flag: false);
    await p.refreshFromServer(force: true);
    expect(store.payload, storedDistance);
  });

  test('a failing read leaves the stored payload (Review Focus 1)', () async {
    store.payload = storedDistance;
    final g = FakePresenceGateway({
      'couple_map_presence': (_) => throw Exception('offline'),
    });
    final (_, p) = make(g);
    await p.refreshFromServer(force: true);
    expect(store.payload, storedDistance);
  });

  test('a read from the map tab (the hook) publishes — the only path that can here', () async {
    // The publisher's own reads fail, so only the hook can write a distance.
    final g = FakePresenceGateway({
      'couple_map_presence': (_) => throw Exception('offline'),
    });
    final (c, p) = make(g, stubRender: true);
    p.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(store.payload, isNull);
    c.read(presenceReadsProvider).add(('r1', CoupleMapPresence.fromRows(farRows)));
    await until(() => store.payload != null);
    expect(CoupleWidgetPayload.decode(store.payload).hasDistance, isTrue);
  });

  test('a reminders change re-publishes from memory: no new read, same validity', () async {
    var t = DateTime(2026, 10, 16, 12);
    final g = far();
    final (c, p) = make(g, clock: () => t, stubRender: true);
    p.start();
    await until(() => store.payload != null);
    final readsBefore = reads(g);
    final writesBefore = store.log.where((e) => e == 'payload').length;
    final validBefore = CoupleWidgetPayload.decode(store.payload).validUntilMs;
    t = t.add(const Duration(minutes: 1));
    (c.read(remindersListProvider.notifier) as _Reminders).touch();
    await until(() => store.log.where((e) => e == 'payload').length > writesBefore);
    expect(reads(g), readsBefore);
    expect(CoupleWidgetPayload.decode(store.payload).validUntilMs, validBefore);
  });

  test('never keeps the couple-map provider alive (spec §8)', () async {
    final g = far();
    final (c, p) = make(g, stubRender: true);
    p.start();
    await until(() => store.payload != null);
    final sub = c.listen(coupleMapPresenceProvider('r1'), (_, __) {});
    await c.read(coupleMapPresenceProvider('r1').future);
    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      c.getAllProviderElements().where(
        (e) => e.origin == coupleMapPresenceProvider('r1'),
      ),
      isEmpty,
    );
    final settled = reads(g);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reads(g), settled);
  });

  test('disposing mid-render is safe (no late write, no error)', () async {
    final gate = Completer<Uint8List>();
    final c = ProviderContainer(
      overrides: [
        presenceGatewayProvider.overrideWithValue(far()),
        presenceSamplerProvider.overrideWithValue(sampler),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        coupleMapEnabledProvider.overrideWith((ref) async => true),
        currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
        remindersListProvider.overrideWith(_Reminders.new),
        worldOutlineProvider.overrideWith((ref) async => outline),
      ],
    );
    final p = c.read(coupleWidgetPublisherProvider)..render = (_, __) => gate.future;
    p.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.dispose();
    gate.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(store.map, isNull);
  });

  test('the same snapped region is not re-rendered', () async {
    var renders = 0;
    final (_, p) = make(far());
    p.render = (f, o) {
      renders++;
      return Future.value(Uint8List.fromList([1]));
    };
    await p.refreshFromServer(force: true);
    await p.refreshFromServer(force: true);
    expect(renders, 1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/couple_map/widget/couple_widget_publisher_test.dart`
Expected: FAIL to compile (`couple_widget_publisher.dart` missing).

- [ ] **Step 3: Write the publisher**

```dart
// lib/features/couple_map/widget/presentation/couple_widget_publisher.dart
import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/couple_map/widget/domain/region_frame.dart';
import 'package:attune/features/couple_map/widget/presentation/region_map_painter.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    show currentRelationshipIdProvider;
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    show remindersListProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class CoupleWidgetPreview {
  const CoupleWidgetPreview(this.view, this.map);
  final CoupleWidgetView view;
  final Uint8List? map;
}

/// Writes the home-screen widget from presence READS only (spec §4.1): the
/// map tab's own refresh (via presenceReadsProvider) and one read on app
/// resume. It never records, never samples, and never watches the
/// couple-map provider (that would keep it alive and sampling). Reminder
/// changes re-publish the last read from memory, with its original read
/// time, so they cost no network and never extend the 3 h validity.
class CoupleWidgetPublisher {
  CoupleWidgetPublisher(this._ref);

  final Ref _ref;
  DateTime Function() clock = DateTime.now;
  Future<Uint8List> Function(RegionFrame, WorldOutline) render =
      (f, o) => renderRegionMap(f, o);
  Duration renderBudget = CoupleWidgetConfig.renderBudget;

  final preview = ValueNotifier<CoupleWidgetPreview?>(null);

  bool _started = false;
  bool _disposed = false;
  DateTime? _lastRead;
  CoupleMapPresence? _lastPresence;
  DateTime? _lastPresenceAt;
  String? _mapKey;
  Uint8List? _mapBytes;
  int _seenGeneration = -1;
  StreamSubscription<(String, CoupleMapPresence)>? _reads;
  AppLifecycleListener? _life;
  ProviderSubscription<AsyncValue<List<ReminderModel>>>? _reminders;

  bool get started => _started;

  /// At launch: costs nothing unless this phone opted in.
  Future<void> startIfEnabled() async {
    if (await CoupleWidgetSync.isEnabled()) start();
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _reads = _ref
        .read(presenceReadsProvider)
        .stream
        .listen(
          (e) => unawaited(
            _publish(e.$2, CoupleWidgetSync.generation, readAt: clock()),
          ),
        );
    _life = AppLifecycleListener(onResume: () => unawaited(refreshFromServer()));
    _reminders = _ref.listen<AsyncValue<List<ReminderModel>>>(
      remindersListProvider,
      (_, next) {
        if (next.isLoading) return; // wait for the settled value
        final last = _lastPresence;
        final at = _lastPresenceAt;
        if (last != null && at != null) {
          unawaited(_publish(last, CoupleWidgetSync.generation, readAt: at));
        }
      },
    );
    unawaited(_startup());
  }

  Future<void> _startup() async {
    await CoupleWidgetSync.dropExpired(clock());
    await refreshFromServer(force: true);
  }

  Future<bool> _flagOn() async {
    try {
      return await _ref.read(coupleMapEnabledProvider.future);
    } catch (_) {
      return false;
    }
  }

  /// One read-only fetch, at most every 5 minutes unless [force]. A failed
  /// read leaves what's stored: it expires by itself (spec §4.2).
  Future<void> refreshFromServer({bool force = false}) async {
    if (_disposed) return;
    final t = clock();
    if (!force &&
        _lastRead != null &&
        t.difference(_lastRead!) < CoupleWidgetConfig.readDebounce) {
      return;
    }
    if (!await CoupleWidgetSync.isEnabled() || _disposed) return;
    _lastRead = t;
    final g = CoupleWidgetSync.generation;
    final CoupleMapPresence p;
    try {
      final rel = await _ref.read(currentRelationshipIdProvider.future);
      if (rel == null || _disposed) return;
      p = await _ref.read(presenceRepositoryProvider).fetchMapPresence(rel);
    } catch (_) {
      dev.log('widget_read_failed', name: 'couple_widget');
      return;
    }
    if (_disposed) return;
    // The flag provider caches a safe "false" when the server couldn't be
    // reached (ChatFeatureFlags). The read just succeeded, so ask again
    // before clearing on flag-off.
    if (!await _flagOn()) {
      if (_disposed) return;
      _ref.invalidate(coupleMapEnabledProvider);
      if (await _flagOn() || _disposed) {
        if (!_disposed) await _publish(p, g, readAt: t);
        return;
      }
      await CoupleWidgetSync.clear(resetOptIn: false);
      return;
    }
    await _publish(p, g, readAt: t);
  }

  Future<List<(String, DateTime)>?> _events() async {
    try {
      final list = await _ref
          .read(remindersListProvider.future)
          .timeout(const Duration(seconds: 5));
      return [for (final r in list) (r.title, r.remindAt)];
    } catch (_) {
      return null;
    }
  }

  Future<void> _publish(
    CoupleMapPresence presence,
    int g, {
    required DateTime readAt,
  }) async {
    if (_disposed) return;
    if (_lastRead == null || readAt.isAfter(_lastRead!)) _lastRead = readAt;
    if (_lastPresenceAt == null || !readAt.isBefore(_lastPresenceAt!)) {
      _lastPresence = presence;
      _lastPresenceAt = readAt;
    }
    if (g != CoupleWidgetSync.generation) return;
    if (!await CoupleWidgetSync.isEnabled() || !await _flagOn()) return;
    // Reminders unknown (still loading past 5 s, or failed): don't write a
    // payload that would drop a kept countdown. The listener publishes
    // again when they settle.
    final events = await _events();
    if (events == null || _disposed) return;
    if (_seenGeneration != CoupleWidgetSync.generation) {
      _seenGeneration = CoupleWidgetSync.generation;
      _mapKey = null;
      _mapBytes = null;
    }
    String? kept;
    try {
      kept =
          CoupleWidgetPayload.decode(
            await CoupleWidgetSync.store.readPayload(),
          ).reunionDate;
    } catch (_) {}
    if (_disposed) return;
    final now = clock();
    final b = buildCoupleWidget(
      presence: presence,
      events: events,
      now: now,
      readAt: readAt,
      keptReunionDate: kept,
    );
    MapUpdate map = const RemoveMap();
    String? key;
    Uint8List? bytes;
    if (b.hasMap) {
      final frame = regionFrame(b.mapSelf!, b.mapPartner!);
      key = '${WorldOutline.version}|${frame.cacheKey}';
      if (key == _mapKey && _mapBytes != null) {
        map = const KeepMap();
        bytes = _mapBytes;
      } else {
        try {
          final outline = await _ref.read(worldOutlineProvider.future);
          bytes = await render(frame, outline).timeout(renderBudget);
          map = ReplaceMap(bytes);
        } catch (_) {
          dev.log('widget_render_failed', name: 'couple_widget');
          bytes = null;
          key = null;
        }
      }
    }
    if (_disposed) return;
    final ok = await CoupleWidgetSync.publish(b.payload, map: map, generation: g);
    if (!ok || _disposed) return;
    _mapKey = map is RemoveMap ? null : key;
    _mapBytes = map is RemoveMap ? null : bytes;
    preview.value = CoupleWidgetPreview(
      resolveCoupleWidget(b.payload, now),
      b.payload.hasDistance ? _mapBytes : null,
    );
  }

  void dispose() {
    _disposed = true;
    unawaited(_reads?.cancel());
    _life?.dispose();
    _reminders?.close();
    preview.dispose();
  }
}

final coupleWidgetPublisherProvider = Provider<CoupleWidgetPublisher>((ref) {
  final p = CoupleWidgetPublisher(ref);
  ref.onDispose(p.dispose);
  return p;
});
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `flutter test test/features/couple_map/widget/couple_widget_publisher_test.dart`
Expected: all pass. Note in the ledger: a failed read still counts against the 5-minute debounce (spec: "doesn't retry").

If "a resume read writes distance…" finds `store.map` null, check that `render` ran: a real `toImage` in a plain `test()` needs the binding, which `ensureInitialized` provides. Don't weaken the assertion.

- [ ] **Step 5: Start it at launch (shared file `lib/app/app.dart`; re-read it first)**

Add the import `package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart`. Add a microtask in `_AppState.initState`, after the OneSignal one:
```dart
    // The home-screen distance widget: costs nothing unless opted in.
    Future.microtask(() {
      if (!mounted) return;
      unawaited(ref.read(coupleWidgetPublisherProvider).startIfEnabled());
    });
```
Add `import 'dart:async';` if `unawaited` isn't already available. Snapshot-diff `lib/app/app.dart` and expect only added lines.

Then run the app-level tests that build `App`, if any: `grep -rl "App()" test | head`. Run each one found.

- [ ] **Step 6: Format the new files and analyze everything touched**

- [ ] **Step 7: Ledger**

Shared-file risk for `app.dart`: low. It's a microtask that returns at once when not opted in, and the publisher never throws.

---

### Task 8: Sharing-sheet toggle, preview and hide-on-pause

**Files:**
- Create: `lib/features/couple_map/widget/presentation/couple_widget_preview.dart` (the preview card plus `CoupleWidgetEnabled` / `coupleWidgetEnabledProvider`)
- Modify: `lib/features/couple_map/presentation/widgets/sharing_sheet.dart`
- Test: additions to `test/features/couple_map/sharing_sheet_test.dart`; `test/features/couple_map/widget/couple_widget_preview_test.dart`

**Interfaces:**
- Consumes: `CoupleWidgetSync` (Task 5), `coupleWidgetPublisherProvider`, `CoupleWidgetPreview` (Task 7), `resolveCoupleWidget`, `neutralHeadline` (Task 1).
- Produces:
  - `class CoupleWidgetEnabled extends AsyncNotifier<bool> { Future<void> set(bool on); }`
  - `final coupleWidgetEnabledProvider`
  - `class CoupleWidgetPreviewCard extends ConsumerWidget`
  - copy constants `widgetToggleTitle`, `widgetToggleSubtitle`, `widgetPreviewLabel`, `widgetHowToIos`, `widgetHowToAndroid`

- [ ] **Step 1: Write the failing tests**

`test/features/couple_map/widget/couple_widget_preview_test.dart`:
```dart
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_preview.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Publisher extends Fake implements CoupleWidgetPublisher {
  @override
  final preview = ValueNotifier<CoupleWidgetPreview?>(null);
}

Future<_Publisher> pump(WidgetTester t, CoupleWidgetPreview? value) async {
  final p = _Publisher()..preview.value = value;
  await t.pumpWidget(
    ProviderScope(
      overrides: [coupleWidgetPublisherProvider.overrideWithValue(p)],
      child: const MaterialApp(home: Scaffold(body: CoupleWidgetPreviewCard())),
    ),
  );
  return p;
}

void main() {
  testWidgets('shows the lines and the label; the image is hidden from screen readers', (t) async {
    final semantics = t.ensureSemantics();
    await pump(
      t,
      CoupleWidgetPreview(
        const CoupleWidgetView(
          headline: 'Together tomorrow',
          caption: '5.1k km apart',
          clockLine: '3:15pm there',
        ),
        Uint8List.fromList(kTransparentPng),
      ),
    );
    expect(find.text(widgetPreviewLabel), findsOneWidget);
    expect(find.text('Together tomorrow'), findsOneWidget);
    expect(find.text('5.1k km apart'), findsOneWidget);
    expect(find.text('3:15pm there'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(
      t.widget<Image>(find.byType(Image)).excludeFromSemantics,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('nothing yet: the neutral card, no image', (t) async {
    await pump(t, null);
    expect(find.text(neutralHeadline), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('one platform instruction line', (t) async {
    await pump(t, null);
    expect(
      find.text(widgetHowToIos).evaluate().length +
          find.text(widgetHowToAndroid).evaluate().length,
      1,
    );
  });
}

const kTransparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
```

Additions to `test/features/couple_map/sharing_sheet_test.dart`:
- **New imports:**
  - `couple_widget_sync.dart`, `couple_widget_preview.dart`, `couple_widget_publisher.dart`;
  - `widget/support/memory_widget_store.dart`;
  - `package:shared_preferences/shared_preferences.dart`;
  - `planning_providers.dart show currentRelationshipIdProvider`;
  - `reminders_providers.dart show remindersListProvider, RemindersListNotifier`;
  - `reminder_model.dart`.
- **New `_pump` overrides:** `coupleMapEnabledProvider.overrideWith((ref) async => true)`, `currentRelationshipIdProvider.overrideWith((ref) async => 'r1')`, and `remindersListProvider.overrideWith(_NoReminders.new)`, with this class defined in the test file:
  ```dart
  class _NoReminders extends RemindersListNotifier {
    @override
    Future<List<ReminderModel>> build() async => <ReminderModel>[];
  }
  ```
- **One more `_pump` override:** `coupleWidgetPublisherProvider.overrideWithValue(_IdlePublisher())`. The real publisher's render and reminder timeouts would leave timers pending, which fails `testWidgets`; the publisher has its own tests in Task 7. Define in the test file:
  ```dart
  class _IdlePublisher extends Fake implements CoupleWidgetPublisher {
    @override
    final preview = ValueNotifier<CoupleWidgetPreview?>(null);
    @override
    bool started = false;
    @override
    void start() => started = true;
    @override
    Future<void> refreshFromServer({bool force = false}) async {}
  }
  ```
- **`setUp`:** `CoupleWidgetSync.store = MemoryCoupleWidgetStore(); SharedPreferences.setMockInitialValues({});`.

```dart
  testWidgets('home-screen toggle: off by default; on shows the preview; off clears', (t) async {
    final widget = MemoryCoupleWidgetStore();
    CoupleWidgetSync.store = widget;
    await _pump(t, const [_self]);
    // A toggle row isn't an InkWell (info_row_widget.dart): tap its switch.
    final toggle = find.descendant(
      of: find.widgetWithText(InfoRowWidget, widgetToggleTitle),
      matching: find.byType(Switch),
    );
    await t.ensureVisible(toggle);
    await t.pumpAndSettle();
    expect(find.text(widgetPreviewLabel), findsNothing);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(await CoupleWidgetSync.isEnabled(), isTrue);
    expect(find.text(widgetPreviewLabel), findsOneWidget);
    await t.ensureVisible(toggle);
    await t.pumpAndSettle();
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(await CoupleWidgetSync.isEnabled(), isFalse);
    expect(widget.payload, '{"v":1}');
  });

  testWidgets('pausing hides the widget distance before the call (spec §4.3)', (t) async {
    await _pump(t, const [_self]);
    final g = CoupleWidgetSync.generation;
    await t.tap(find.text('Pause for 1 hour'));
    await t.pumpAndSettle();
    expect(CoupleWidgetSync.generation, greaterThan(g));
  });

  testWidgets('turning sharing off hides the widget distance too', (t) async {
    await _pump(t, const [_self]);
    final g = CoupleWidgetSync.generation;
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(CoupleWidgetSync.generation, greaterThan(g));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/couple_map/widget/couple_widget_preview_test.dart test/features/couple_map/sharing_sheet_test.dart`
Expected: the preview test fails to compile; the new sheet tests fail (the toggle text isn't found, and the generation doesn't change).

- [ ] **Step 3: Write the preview card and opt-in notifier**

```dart
// lib/features/couple_map/widget/presentation/couple_widget_preview.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const widgetToggleTitle = 'Show distance on my home screen';
const widgetToggleSubtitle = 'No names or places. Cleared by quick exit.';
const widgetPreviewLabel = 'Your home screen shows roughly this';
const widgetHowToIos = 'Touch and hold your home screen, tap +, then find Attune';
const widgetHowToAndroid =
    'Touch and hold your home screen, tap Widgets, then find Attune';

/// This phone's opt-in (spec §2 ruling 1). Off by default.
class CoupleWidgetEnabled extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => CoupleWidgetSync.isEnabled();

  Future<void> set(bool on) async {
    if (on) {
      try {
        await (await SharedPreferences.getInstance()).setBool(
          coupleWidgetEnabledKey,
          true,
        );
      } catch (_) {}
      state = const AsyncData(true);
      // start() already does one forced read; a restart after "off" in the
      // same session needs its own.
      final publisher = ref.read(coupleWidgetPublisherProvider);
      if (publisher.started) {
        unawaited(publisher.refreshFromServer(force: true));
      } else {
        publisher.start();
      }
    } else {
      await CoupleWidgetSync.clear();
      state = const AsyncData(false);
    }
  }
}

final coupleWidgetEnabledProvider =
    AsyncNotifierProvider<CoupleWidgetEnabled, bool>(CoupleWidgetEnabled.new);

/// Roughly what the home screen shows (spec §3.4): the same lines and
/// image, in a plain card. Not a pixel copy of the native widget.
class CoupleWidgetPreviewCard extends ConsumerWidget {
  const CoupleWidgetPreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final publisher = ref.watch(coupleWidgetPublisherProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.xs,
        Spacing.md,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widgetPreviewLabel, style: muted),
          const SizedBox(height: Spacing.sm),
          ValueListenableBuilder<CoupleWidgetPreview?>(
            valueListenable: publisher.preview,
            builder: (context, value, _) {
              final view =
                  value?.view ??
                  const CoupleWidgetView(headline: neutralHeadline, neutral: true);
              final map = value?.map;
              return Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    if (map != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          map,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          gaplessPlayback: true,
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                    ] else if (view.neutral) ...[
                      Icon(
                        Icons.favorite_border,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Spacing.sm),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            view.headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (view.caption != null)
                            Text(view.caption!, style: muted),
                          if (view.clockLine != null)
                            Text(view.clockLine!, style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: Spacing.sm),
          Text(Platform.isIOS ? widgetHowToIos : widgetHowToAndroid, style: muted),
        ],
      ),
    );
  }
}
```

Check `Spacing.xs/sm/md` exist in `lib/app/theme/design_tokens.dart`; the sharing sheet already uses `Spacing.sm/md/lg`, and `story_pin_toggle.dart` uses `Spacing.xs`.

- [ ] **Step 4: Edit the Sharing sheet (re-read it first; surgical)**

Add imports for `couple_widget_preview.dart` and `couple_widget_sync.dart`.

In `build`, read the opt-in:
```dart
    final widgetOn = ref.watch(coupleWidgetEnabledProvider).valueOrNull ?? false;
```

**Hide the widget's distance on pause.** In `pauseRow`, change `onTap`:
```dart
            onTap:
                _busy
                    ? null
                    : () => _run((r) async {
                      await CoupleWidgetSync.hideDistanceNow();
                      await r.pause(rel, d);
                    }),
```

**Hide it when sharing is turned off.** In the share toggle, change the action:
```dart
                        _run(
                          (r) async {
                            if (!v) await CoupleWidgetSync.hideDistanceNow();
                            await (v ? r.startSharing(rel) : r.stopSharing(rel));
                          },
                          onError: () => setState(() => _pendingOn = null),
                        );
```

**Add the home-screen card.** Insert a new card after the "Pausing hides you from each other…" `Padding`, before the story-places `CardInkWell`:
```dart
            // The home-screen distance widget (widget spec §3.4).
            CardInkWell(
              child: Column(
                children: [
                  MergeSemantics(
                    child: InfoRowWidget(
                      // M3's secondary-text colour: meets WCAG AA at 12 sp.
                      subTitleFontColor: theme.colorScheme.onSurfaceVariant,
                      title: widgetToggleTitle,
                      subtitle: widgetToggleSubtitle,
                      icon: Icons.widgets_outlined,
                      isToggleItem: true,
                      toggleValue: widgetOn,
                      showAvatar: false,
                      showDivider: false,
                      onToggleChanged:
                          (v) => ref
                              .read(coupleWidgetEnabledProvider.notifier)
                              .set(v),
                    ),
                  ),
                  if (widgetOn) const CoupleWidgetPreviewCard(),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
```

- [ ] **Step 5: Run the tests and verify they pass**

Run: `flutter test test/features/couple_map/`
Expected: all pass, including `accessibility_test.dart` and `couple_map_tab_test.dart`. Those open the sheet; without a `SharedPreferences` mock the opt-in reads false and the new row renders off.

`accessibility_test.dart` already checks "the sharing sheet ($mode)" with the widget row **off** (no prefs mock). It uses `expectSheetGuidelines`, not the tap-target guidelines, because the shared header's "Done" is 24 dp. Add one case per mode with the row **on**, so the preview card is checked too. It needs `import 'package:shared_preferences/shared_preferences.dart';` and `import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';` plus `import 'widget/support/memory_widget_store.dart';`. Add it inside the existing `for (final mode …)` loop:
```dart
    testWidgets('the sharing sheet with the home-screen row on ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      CoupleWidgetSync.store = MemoryCoupleWidgetStore();
      SharedPreferences.setMockInitialValues({'couple_widget_enabled': true});
      final h = TabHarness([selfRow])..themeMode = mode;
      await h.pump(t);
      await t.tap(find.byType(SharingChip));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Your home screen shows roughly this'),
        200,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ).first,
      );
      await expectSheetGuidelines(t);
      semantics.dispose();
    });
```
Then check whether `TabHarness` overrides `currentRelationshipIdProvider` (planning) and `remindersListProvider`. The preview card only reads the publisher and never starts it, so it needs neither. If the test reports a provider error, add those two overrides to the harness's override list, exactly as in Task 7's `make()`.

- [ ] **Step 6: Diff check, format and analyze**

Snapshot-diff `sharing_sheet.dart`. Expected: only added and changed lines in the regions above. Don't format the sheet; do format the new file. Run the analyzer gate on both.

- [ ] **Step 7: Ledger**

Shared-file risk: medium-low. The sheet's existing pause and share flows now await a no-throw hide first; the existing sheet tests (pause sends its end, failure copy, dismiss mid-call) are the regression gate.

---

### Task 9: Evidence, spec status, full suite

**Files:**
- Modify: `docs/superpowers/specs/2026-10-16-couple-distance-widget-design.md` (status line, plus the §7 W1 row marked "Built")
- Modify: the plan ledger (`.superpowers/sdd/2026-10-16-couple-widget-w1/progress.md`)

- [ ] **Step 1: Run the full suite**

Run: `flutter test > "$WS/full.txt" 2>&1; tail -5 "$WS/full.txt"`, where `$WS` is the plan workspace.
Expected: `All tests passed!`. Record the count at the start of this plan (run once before Task 1) and at the end; the end count is higher by this plan's new tests. If anything fails, fix it before going on, and record each fix as a ruling.

- [ ] **Step 2: Run the analyzer over everything touched**

Run: `flutter analyze lib test tool 2>&1 | grep -E "^\s*(error|warning) "`
Expected: no output.

- [ ] **Step 3: Coverage for spec §9 6.7**

Run: `flutter test --coverage test/features/couple_map/widget/`. Then compute line coverage for the following from `coverage/lcov.info` with a small `awk` over the `SF:`/`LH:`/`LF:` lines:
- `lib/features/couple_map/widget/domain/` (target ≥ 90 %);
- `lib/features/couple_map/widget/data/` and `presentation/couple_widget_publisher.dart` (target ≥ 70 %).

Record the numbers. If one misses its target, add tests for the uncovered branches (read the lcov `DA:` lines with 0 hits) before going on.

- [ ] **Step 4: Run the privacy greps (checklist 4.4, spec §4.4)**

Run:
```
grep -rnE "log\(|print\(|debugPrint\(" lib/features/couple_map/widget | grep -vE "widget_(render|read)_failed"
grep -rnE "cellLat|cellLng|city|country" lib/features/couple_map/widget/data lib/features/couple_map/widget/presentation/couple_widget_preview.dart
```
Expected: both print nothing. (`couple_widget_payload.dart` reads the cells to build map points, and the publisher passes them only to `regionFrame`.)

- [ ] **Step 5: Write the checklist v3.1 evidence map into the ledger**

One line per item in spec §9, each citing the test name or command:

| Item | Evidence |
|---|---|
| 1.4 | Grep: no Supabase import under `widget/data`; reads go through the existing repository |
| 1.5 / 1.11 | `clear empties, broadcasts before deleting the map, and resets the opt-in` |
| 2.1 | `malformed or unknown version decodes to empty`; `a truncated file is a FormatException` |
| 2.4 | `never throws without the plugin` |
| 2.5 | `the same snapped region is not re-rendered`; `at most one read per 5 minutes`; asset ≤ 400 KB test |
| 2.10 | `CoupleWidgetPublisher.dispose` (listener, subscription, notifier) |
| 4.4 | The payload scan test; Step 4 greps |
| 1.1 | Full-payload replace; `clear` idempotent |
| 1.2 | `a render over budget publishes the text layout` |
| 1.6 / 2.16 / 6.3 | `a pause during an in-flight read drops the read`; `a clear during a slow render drops the render` |
| 6.1 | Region-frame tests (antimeridian, Fiji, antipodes, identical points, polar clamp); payload expiry boundaries |
| 6.4 | Fading, paused, off, not opted in, flag off tests |
| 6.5 | The 2000-pair property test |
| 6.7 | Step 3 numbers |
| 6.9 | The 150 ms painter benchmark (record the measured average) |
| 8.1 | `flag off clears without forgetting the choice` |
| 7.1–7.3 | No new dependency (`git diff pubspec.yaml` shows only the asset line); Step 2 |

- [ ] **Step 6: Update the spec status**

Change the spec's `**Status:**` line to add: "W1 (Dart) built 2026-10-16; see `docs/superpowers/plans/2026-10-16-couple-widget-w1.md`." Then mark the §7 W1 row "Built".

- [ ] **Step 7: Run the final Fable review (executing-plans' final review)**

Generate the review package and dispatch Fable with:
- the package;
- the plan and spec paths;
- this plan's Review Focus verbatim;
- the ledger's `Ruling:` lines.

Then do one fix pass, where each fix is proved by a test that failed first.

---

## Self-review (done while writing)

**Spec coverage**

| Spec section | Task |
|---|---|
| §2 rulings | Tasks 1, 5, 7, 8 |
| §3.1 copy | Task 1 |
| §3.3 map | Tasks 2–4 |
| §3.4 sheet | Task 8 |
| §4.1 writes | Tasks 6, 7, 8 |
| §4.2 expiry | Tasks 1, 5 (`dropExpired`), 7 (startup) |
| §4.3 pause | Tasks 5, 8 |
| §4.4 storage | Tasks 1 (scan), 5 (keys, backup) |
| §6.1 files | All |
| §6.4 clearing | Task 5 |
| §8 Dart tests | Tasks 1–8 |
| §9 checklist | Task 9 |

Native code (§6.2, §6.3) and the deep link (§6.5) are W2, out of scope here.

**Type consistency**
- `CoupleWidgetPayload`, `CoupleWidgetBuild.mapSelf/mapPartner`, `RegionFrame.cacheKey`, `WorldOutline.version`, `MapUpdate {KeepMap, ReplaceMap, RemoveMap}`, `CoupleWidgetSync.publish(payload, map:, generation:)` and `CoupleWidgetPreview(view, map)` are used with the same names in every task.

**Placeholders**
- None. Every code step carries its code, and the one conditional accessibility test has its full body pattern.

**Recorded deviations from the spec**
- **Toggle placement:** a card of its own just after the "Pausing hides you…" note, not inside the pause card. Same position on screen, a clearer group.
- **Fields:** the payload adds `headlineIsClock` and `clockLine` (two booleans that carry no new information), so the native side knows which line is the live clock.
- **Kept reunion:** read back from the stored payload, so it survives an app restart.

## Plan review (Fable, 2026-10-16) — all applied

**Critical**
- **C1.** The toggle test tapped the title, but toggle rows only react to their switch. It now taps the row's `Switch`.
- **C2.** The Fiji coordinates snapped to different latitudes. They now snap to the same one.
- **C3.** The exact `Offset` equality would fail on float error. It's now a tolerance check.
- **C4.** The publisher wasn't safe after dispose, and the hook test was racy and passed even without the hook. Fixed with a `_disposed` guard after every await; the hook test is now the only path that can write.

**Important**
- **I1.** On Android before W2, the widget refresh fails and was making every publish return false. A failed refresh is now swallowed after the write.
- **I2.** An offline launch cleared the widget, because the flag reads a safe "false" when the server can't be reached. Now it clears only after a successful read, plus a re-check of the flag.
- **I3.** Reminder changes forced presence reads. They now re-publish the last read from memory, keeping its read time (`readAt`).
- **I4.** The accessibility claim was wrong. A row-on case now uses `expectSheetGuidelines`.
- **I5.** Added the "never keeps the provider alive" test.
- **I6.** `git diff --numstat` is blind for these files. Every shared file is snapshot-diffed instead.
- **I7.** A kept reunion could flicker while reminders load. The publish now waits for reminders, or is skipped until they settle.

**Minor**
- M1: the benchmark is split into record time and rasterise time.
- M2: the read debounce after a failure is noted.
- M3: the widget clear runs first in the Together exits.
- M4: no double read when the toggle is turned on.
- M5: the toggle placement is recorded as a deviation.
- M7: the device-data test gets its own `setUp` store.
- M8: the test-count baseline is measured at the start, not assumed.

**Found while applying:** the Sharing-sheet tests use an idle publisher fake, so `testWidgets` has no pending timers.
