# Couple Map Phase 3 (Polish) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the couple map:
- videos lose their embedded location;
- place lookups explain a missing permission and never re-prompt on their own;
- the camera pill survives a failed post and fits small phones;
- the map stops flickering and follows theme and partner changes;
- every control passes the accessibility guidelines;
- the September spec says what replaced its §2.

**Architecture:** Mostly small changes inside the existing seams:
- a pure-Dart `Mp4LocationStripper`, which renames the location atoms to `free` in place, so no offset changes;
- a lookup result type for `StoryPlaceResolver`;
- in-place GeoJSON updates for presence;
- 48 dp hit areas around the 44 dp glass visuals;
- one SQL helper replacing a catalogue scan.

**Tech Stack:** Flutter, Riverpod 2.6, `mapbox_maps_flutter` 2.24.3, `geolocator` 14, `video_compress`, PL/pgSQL.

**Spec:** `docs/superpowers/specs/2026-10-16-couple-map-design.md`:
- §7 Phase 3: video metadata strip, accessibility audit, the September spec's §2 marked as replaced;
- §3.3 and §3.5;
- §9 (5.6, 4.4, 1.3).

**Carried forward:** deferred minors from `.superpowers/sdd/2026-10-16-couple-map-phase0/`, `…-phase1/` and `…-phase2/progress.md`.

## Global Constraints

- **Never `dart format` a pre-existing file.** The repo uses an older formatter style. Format only files created in this work, and check `git diff --numstat` against the real change.
- **Video:**
  - after compression, every location atom is neutralised in place: `©xyz`, `loci`, and QuickTime `mdta` keys containing `location`;
  - file size and every other byte offset are unchanged, so `stco`/`co64` stay valid;
  - a file it can't parse is left untouched, and stripping never fails the send.
- **Place lookup:**
  - only an explicit "on" tap may show the system permission prompt; a remembered "on" at camera open never prompts;
  - no permission: **"Allow location for Attune to pin places"**, and tapping it opens settings;
  - iOS Precise Location off: the preview reads **"{label} · approximate"**.
- **Accessibility:**
  - every tappable control on the map tab, sheets, camera pill and reel places controls meets `androidTapTargetGuideline` (48 dp), `iOSTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline`, in light and dark;
  - glass buttons keep their **44 dp visual** inside a **48 dp hit area**.
- **Never log coordinates, labels or cities** (4.4).
- No commits. Work on `main`, test first, and filter the analyzer with `grep -E "^\s*(error|warning) "`.
- **SQL:** `20261016100000_presence_v2.sql` is **not yet deployed** (the owner's `db push` is pending), so the time-zone helper is edited into it. If it has been deployed by the time this runs, put the same SQL in a new `20261018100000_presence_tz_helper.sql` instead, and ledger the choice.
- **Out of scope (stay deferred):**
  - the presence pins' annotation redraw;
  - a debounce on `storyPlacesProvider`;
  - removing the unmounted `PartnerDistanceRow` and the unused `planningTimezoneOffsetProvider`;
  - the chat-settings toggle's disabled look with no conversation;
  - the `TimezoneUtils` `'UTC'` fallback;
  - the minute ticker rebuilding `MapWidget`;
  - the device-only checks (telemetry, layer order, together offset, `to-string`).

## Review Focus

1. **Real clips:**
   - an iPhone export is moov-first, with QuickTime `meta/keys/ilst` and `com.apple.quicktime.location.ISO6709`;
   - an Android MediaMuxer output is moov-last, with `udta/©xyz` and possibly a 64-bit mdat.

   The location goes, and the video still plays. Tests: Task 1, both fixtures.
2. **A remembered "on" after the user denied location:** opening the camera must not prompt again. It shows the "Allow location…" line, and posting goes ahead without a place. Test: Task 2, "remembered on never prompts".
3. **A post fails** (prepare rejected): the pill comes back with the same switch state and no second lookup or prompt. Test: Task 3, "a failed post keeps the same switch".
4. **Theme flips before the map is ready:** the first style still loads with the right light preset. Test: Task 4 wiring, "dark is tracked before onReady".
5. **A 320 dp phone:** the camera pill's title stays readable and nothing overflows. Test: Task 3, "fits a 320 dp screen".


## Review amendments (binding: they override the task text where they differ)

The Fable plan review (2026-10-18) found no critical issues and nine important ones; all are folded in here.

**A1 (Task 5): the optimistic switch must not snap back on the refetch frame.**
- `_run` gains `{VoidCallback? onError}`, called in its `catch`. Its `finally` no longer touches `_pendingOn`.
- The toggle row is `toggleValue: _pendingOn ?? state.isOn`.
- `onToggleChanged: (v) { if (_busy) return; setState(() => _pendingOn = v); _run((r) => v ? r.startSharing(rel) : r.stopSharing(rel), onError: () => setState(() => _pendingOn = null)); }`
- In `build`, before using `state`, clear `_pendingOn` once the provider agrees: `final async = ref.watch(coupleMapPresenceProvider(rel)); if (_pendingOn != null && !async.isRefreshing && !async.isLoading && state.isOn == _pendingOn) _pendingOn = null;`. A post-frame `setState` isn't needed; it's a plain field read in build.
- The test adds `gate.complete(); await t.pump(); expect(switchValue, isTrue);` **before** `pumpAndSettle` (the frame that used to snap back).

**A2 (Tasks 2 and 7): the pill is one tap target in the "Allow location" state; the Switch keeps its own label.**
- Don't put a `GestureDetector` on the subtitle.
- `final needsSettings = c.notice == StoryPinNotice.allowLocation;`
- The outer `Semantics(container: true, button: needsSettings, label: …, hint: needsSettings ? (c.canAsk ? 'Asks for location' : 'Opens Settings') : null, onTap: needsSettings ? _allowTap : null)` wraps `Material(transparency)`, then `GestureDetector(excludeFromSemantics: true, behavior: HitTestBehavior.opaque, onTap: needsSettings ? _allowTap : null)`, then the existing `ConstrainedBox`/`DecoratedBox`/`Row`.
- In the Row, the Switch is wrapped in `Semantics(container: true, label: 'Pin to our map', child: Switch(...))`.
- `_allowTap` is `c.canAsk ? () => c.setOn(true) : () => ref.read(presenceSamplerProvider).openSettings()` (see A3).
- Task 7's pill accessibility case runs in three states: found, approximate, and allowLocation.

**A3 (Task 2): ask when asking is still possible; Settings only when it isn't.**
- `enum StoryPlaceProblem { needsAsk, noPermission, notFound }`. `needsAsk` means denied but the system would still show a prompt.
- The resolver returns `needsAsk` when `p == LocationPermission.denied && !ask`, and `noPermission` for `deniedForever`, a still-denied permission after asking, or services off.
- The controller maps both `needsAsk` and `noPermission` to **`StoryPinNotice.allowLocation`** (the renamed `noPermission`), and exposes `bool get canAsk` (last problem == `needsAsk`).
- The copy for both is "Allow location for Attune to pin places".
- Tests:
  - `problem = needsAsk`: tap the line, and expect `resolver.asks == [false, true]` and `openedSettings == 0`;
  - `problem = noPermission`: tap, and expect `openedSettings == 1`.

**A4 (Tasks 2 and 3): the new subtitles aren't cut short.**
- The pill subtitle gets `maxLines: 2`; the pill grows, and `minHeight` 48 holds the one-line case.
- The 320 dp test also asserts `didExceedMaxLines == false` on the subtitle in the allowLocation and approximate states.

**A5 (Task 7): `GlassIconButton` keeps its ripple.** The Material/InkWell stays **inside** the 44 dp panel, and the extra hit area is a translucent `GestureDetector` outside it:

```dart
return Tooltip(
  message: tooltip,
  child: Semantics(
    button: true, label: tooltip, onTap: onPressed, excludeSemantics: true,
    child: SizedBox.square(
      dimension: CoupleMapConfig.glassTarget,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onPressed,
        child: Center(
          child: SizedBox.square(
            dimension: size,
            child: GlassPanel(
              borderRadius: const BorderRadius.all(Radius.circular(size / 2)),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(customBorder: const CircleBorder(), onTap: onPressed,
                    child: Icon(icon, size: 22, color: cs.onSurface)),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
```

**A6 (Task 7): the chip keeps a 44 dp visual inside a 48 dp hit area,** like the buttons.
- An outer transparent `ConstrainedBox(minHeight: 48)` carries the `Semantics` and the tap.
- Inside it, `Center` holds the existing `GlassPanel`, kept at `minHeight: 44`.

**A7 (Task 7): the Sharing sheet's toggle row gets a label without touching the shared widget.** Wrap that one `InfoRowWidget(isToggleItem: true …)` in `MergeSemantics(...)` inside `sharing_sheet.dart`, as `SwitchListTile` does. `lib/core/widgets/info_row_widget.dart` is **not** edited.

**A8 (Task 7): contrast is really evaluated.**
- `expectGuidelines` also runs `await expectLater(t, meetsGuideline(CustomMinimumContrastGuideline(finder: find.byType(Text))))`, because `textContrastGuideline` skips nodes with a custom `Semantics` label (the chip, glass buttons and pill).
- The evidence map notes that the harness uses `ThemeData.light()`/`dark()`.

**A9 (Tasks 4 and 7): the harness keeps a public re-pump.**
- `TabHarness` exposes `Widget app()` and `Future<void> repump(WidgetTester t) async { await t.pumpWidget(app()); await t.pumpAndSettle(); }`.
- Both theme tests (the existing light-preset test and Task 4's story re-push test) use `h.repump(t)`.

**Minors folded in:**
- Task 1: the `stripBytes` doc reads "boxes in [b]". XMP `uuid` boxes are out of scope (phones don't write GPS there).
- Task 1 runs regardless of `couple_map_enabled`. That's deliberate, like Phase 0's EXIF fix: it's privacy for all video. Ledger it.
- Task 6:
  - the comment says single-token legacy zones (`Japan`, `GB`, `EST5EDT`) are deliberately refused, and C14 asserts `presence_tz_ok('Japan')` is false;
  - also `REVOKE ALL ON FUNCTION public.presence_offset_minutes(text) FROM PUBLIC, anon, authenticated;`;
  - check deployment with `supabase migration list` before editing the Phase 0 file.
- Task 4: `_fittedWho` doesn't re-fit a partner who went stale and came back (acceptable). The duplicate preset call on a flip is harmless; comment it. `rightColumnBottom` uses `Spacing.md`, not a literal 16.
- Task 4: if the broken-URL avatar test flakes on the cache manager, give `_MiniAvatar` an `@visibleForTesting` image-provider builder.
- Task 7: add one reel case (`StoryReelScreen.forPlaces`, author item, timed pumps) to `accessibility_test.dart`, so the "reel place controls" claim is proven.
- Task 3: update the camera test comment "its controller with it"; under `Offstage` the controller now survives.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/features/chat/domain/services/mp4_location_stripper.dart` (new) | In-place MP4/MOV location removal |
| `lib/features/chat/domain/services/chat_video_preparer.dart` (modify) | Calls the stripper on the compressed output |
| `lib/features/couple_map/data/story_place_resolver.dart` (modify) | `StoryPlaceLookup` result; `ask` flag; reduced-accuracy flag |
| `lib/features/couple_map/presentation/camera/story_pin_controller.dart` (modify) | `noPermission` notice, `approximate`, ask only on tap |
| `lib/features/couple_map/presentation/camera/story_pin_toggle.dart` (modify) | Copy, opening settings, compact layout, 48 dp |
| `lib/features/stories/presentation/screens/story_camera_screen.dart` (modify) | Pill kept mounted (`Offstage` + `IgnorePointer`) while enqueuing |
| `lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart` (modify) | In-place presence data, theme before ready |
| `lib/features/couple_map/presentation/screens/couple_map_tab.dart` (modify) | Re-fit when the partner appears, story re-push on theme, column metrics |
| `lib/features/couple_map/presentation/widgets/distance_card.dart` (modify) | Avatar image error handler |
| `lib/features/couple_map/presentation/widgets/glass_surface.dart` (modify) | 48 dp hit area |
| `lib/features/couple_map/presentation/widgets/sharing_chip.dart` (modify) | 48 dp minimum |
| `lib/features/couple_map/presentation/widgets/sharing_sheet.dart` (modify) | Optimistic toggle, remove-all guard and dialog copy |
| `lib/features/couple_map/domain/couple_map_config.dart` (modify) | `glassTarget`, `glassGap`, `glassGroupGap`, `rightColumnBottom()` |
| `supabase/migrations/20261016100000_presence_v2.sql` (modify) | `presence_tz_ok()` replaces two `pg_timezone_names` scans |
| `supabase/tests/couple_map_presence_contracts.sql` (modify) | C14 |
| `test/features/couple_map/accessibility_test.dart` (new) | Guideline checks across surfaces, light and dark |
| `docs/superpowers/specs/2026-09-02-location-presence-design.md` (modify) | §2 marked replaced |
| `docs/superpowers/specs/2026-10-16-couple-map-design.md` (modify) | §7 status, §10 log |

**Regression risk (flagged):**
- `chat_video_preparer.dart` is shared by chat, streak and story video. The stripper is best-effort and size-preserving, and is called after the existing checks for output and size.
- `story_camera_screen.dart` is shared. The pill stays in the tree while enqueuing, hidden and inert.
- The `GlassIconButton` size change moves the right-hand column, so `ornamentTop` is recomputed from one function.

---

### Task 1: Videos lose their embedded location

**Files:**
- Create: `lib/features/chat/domain/services/mp4_location_stripper.dart`
- Modify: `lib/features/chat/domain/services/chat_video_preparer.dart` (after the `outFile` null check, before `outFile.length()`)
- Test: `test/features/chat/mp4_location_stripper_test.dart`

**Interfaces:**
- Produces: `abstract final class Mp4LocationStripper { static Future<int> strip(File file); static int stripBytes(Uint8List moovPayloadRegion) }`. It returns the number of atoms neutralised and never throws.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/mp4_location_stripper_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/mp4_location_stripper.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

/// A box: 32-bit size + 4-byte type (a String, or raw bytes for '©xyz').
Uint8List box(Object type, List<int> payload) {
  final t = type is String ? ascii.encode(type) : type as List<int>;
  return Uint8List.fromList([..._u32(8 + payload.length), ...t, ...payload]);
}

const xyz = [0xA9, 0x78, 0x79, 0x7A]; // ©xyz
List<int> str(String s) => utf8.encode(s);

/// Apple's ©xyz payload: 2-byte length, 2-byte language, ISO 6709 text.
List<int> xyzPayload(String iso) => [0, iso.length, 0x15, 0xC7, ...str(iso)];

Uint8List mp4({required List<int> moovChildren, bool moovFirst = true, bool bigMdat = false}) {
  final ftyp = box('ftyp', [...str('isom'), 0, 0, 2, 0, ...str('isomiso2mp41')]);
  final mdatPayload = List<int>.filled(64, 0x11);
  final Uint8List mdat = bigMdat
      ? Uint8List.fromList([0, 0, 0, 1, ...ascii.encode('mdat'),
          ...(Uint8List(8)..buffer.asByteData().setUint64(0, 16 + mdatPayload.length)), ...mdatPayload])
      : box('mdat', mdatPayload);
  final moov = box('moov', moovChildren);
  return Uint8List.fromList(moovFirst ? [...ftyp, ...moov, ...mdat] : [...ftyp, ...mdat, ...moov]);
}

Future<File> write(Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('mp4');
  addTearDown(() => dir.delete(recursive: true));
  return File('${dir.path}/v.mp4')..writeAsBytesSync(bytes);
}

bool contains(Uint8List hay, String needle) => latin1.decode(hay, allowInvalid: true).contains(needle);

void main() {
  test('moov/udta/©xyz (Android MediaMuxer) is neutralised in place', () async {
    final bytes = mp4(moovChildren: box('udta', box(xyz, xyzPayload('+05.5560-000.1970/'))));
    final f = await write(bytes);
    expect(await Mp4LocationStripper.strip(f), 1);
    final out = f.readAsBytesSync();
    expect(out.length, bytes.length, reason: 'size (and so every offset) unchanged');
    expect(contains(out, '+05.5560'), isFalse);
    expect(contains(out, 'free'), isTrue);
  });

  test('QuickTime keys and moov after a 64-bit mdat (iPhone): location gone, make kept (Review Focus 1)', () async {
    final keys = box('keys', [
      0, 0, 0, 0, ..._u32(2),
      ...box('mdta', str('com.apple.quicktime.location.ISO6709')),
      ...box('mdta', str('com.apple.quicktime.make')),
    ]);
    final ilst = box('ilst', [
      ...box(_u32(1), box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...str('+05.5560-000.1970+012.000/')])),
      ...box(_u32(2), box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...str('Apple')])),
    ]);
    final meta = box('meta', [...box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...str('mdta'), ...List.filled(12, 0)]), ...keys, ...ilst]);
    final bytes = mp4(moovChildren: meta, moovFirst: false, bigMdat: true);
    final f = await write(bytes);
    expect(await Mp4LocationStripper.strip(f), 1);
    final out = f.readAsBytesSync();
    expect(out.length, bytes.length);
    expect(contains(out, '+05.5560'), isFalse);
    expect(contains(out, 'Apple'), isTrue, reason: 'non-location metadata is left alone');
  });

  test('ISO meta (version + flags) under udta, and trak/udta, are both handled', () async {
    final isoMeta = box('meta', [0, 0, 0, 0, ...box('hdlr', List.filled(24, 0)), ...box('ilst', box(xyz, box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...str('+51.5050-000.1210/')])))]);
    final trak = box('trak', box('udta', box('loci', [0, 0, 0, 0, ...str('Somewhere'), 0])));
    final bytes = mp4(moovChildren: [...box('udta', isoMeta), ...trak]);
    final f = await write(bytes);
    expect(await Mp4LocationStripper.strip(f), 2);
    final out = f.readAsBytesSync();
    expect(contains(out, '+51.5050'), isFalse);
    expect(contains(out, 'Somewhere'), isFalse);
  });

  test('a clip with no location is left byte-for-byte alone', () async {
    final bytes = mp4(moovChildren: box('udta', box('name', str('holiday'))));
    final f = await write(bytes);
    expect(await Mp4LocationStripper.strip(f), 0);
    expect(f.readAsBytesSync(), bytes);
  });

  test('not an MP4, truncated, or empty: nothing changes, nothing throws', () async {
    for (final junk in [Uint8List(0), Uint8List.fromList(str('hello world')), mp4(moovChildren: box('udta', box(xyz, xyzPayload('+0')))).sublist(0, 30)]) {
      final f = await write(junk);
      expect(await Mp4LocationStripper.strip(f), 0);
      expect(f.readAsBytesSync(), junk);
    }
  });

  test('the video preparer strips the compressed output before measuring it', () {
    final src = File('lib/features/chat/domain/services/chat_video_preparer.dart').readAsStringSync();
    final strip = src.indexOf('Mp4LocationStripper.strip(outFile)');
    expect(strip, isNonNegative);
    expect(strip, lessThan(src.indexOf('await outFile.length()')));
  });
}
```

- [ ] **Step 2: Run it and confirm it fails.** `flutter test test/features/chat/mp4_location_stripper_test.dart`. Expected: compilation error.

- [ ] **Step 3: Implement**

```dart
// lib/features/chat/domain/services/mp4_location_stripper.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Removes where a video was recorded from an MP4/MOV, in place.
///
/// Phones write the capture location into the movie header: Android's
/// MediaMuxer as `moov/udta/©xyz`, iPhones as QuickTime metadata
/// (`moov/meta/keys` + `ilst`, key `com.apple.quicktime.location.*`), some
/// encoders as 3GPP `loci`. video_compress keeps them (iOS
/// AVAssetExportSession copies metadata by default).
///
/// Each location atom is renamed `free` and its payload zeroed. Nothing
/// moves, so the file size and every chunk offset (`stco`/`co64`) stay
/// valid. Anything unexpected leaves the file untouched; this never throws
/// and never fails a send.
abstract final class Mp4LocationStripper {
  static const _maxMoovBytes = 16 * 1024 * 1024;

  /// Returns how many location atoms were neutralised.
  static Future<int> strip(File file) async {
    RandomAccessFile? raf;
    try {
      // append mode opens read-write without truncating; writes below go
      // where setPosition puts them.
      raf = await file.open(mode: FileMode.append);
      final length = await raf.length();
      var at = 0;
      while (at + 8 <= length) {
        await raf.setPosition(at);
        final head = await raf.read(16);
        if (head.length < 8) return 0;
        final bd = ByteData.sublistView(Uint8List.fromList(head));
        var size = bd.getUint32(0);
        var header = 8;
        if (size == 1) {
          if (head.length < 16) return 0;
          size = bd.getUint64(8);
          header = 16;
        } else if (size == 0) {
          size = length - at;
        }
        if (size < header || at + size > length) return 0;
        if (_isType(head, 4, 'moov')) {
          if (size > _maxMoovBytes) return 0;
          await raf.setPosition(at);
          final moov = Uint8List.fromList(await raf.read(size));
          final n = _walk(moov, header, size);
          if (n > 0) {
            await raf.setPosition(at);
            await raf.writeFrom(moov);
            await raf.flush();
          }
          return n;
        }
        at += size;
      }
      return 0;
    } catch (_) {
      return 0;
    } finally {
      await raf?.close();
    }
  }

  /// Neutralises location atoms among the boxes in [start, end) of [b].
  static int stripBytes(Uint8List b) => _walk(b, 0, b.length);

  static int _walk(Uint8List b, int start, int end) {
    var n = 0;
    var i = start;
    while (i + 8 <= end) {
      final box = _box(b, i, end);
      if (box == null) break;
      final (size, header) = box;
      if (_isXyz(b, i + 4) || _isType(b, i + 4, 'loci')) {
        _neutralise(b, i, size, header);
        n++;
      } else if (_isType(b, i + 4, 'moov') || _isType(b, i + 4, 'trak') || _isType(b, i + 4, 'udta')) {
        n += _walk(b, i + header, i + size);
      } else if (_isType(b, i + 4, 'meta')) {
        var c = i + header;
        // ISO 'meta' is a full box (4 bytes version/flags); QuickTime's isn't.
        if (_box(b, c, i + size) == null || !_isPrintable(b, c + 4)) c += 4;
        n += _meta(b, c, i + size);
      }
      i += size;
    }
    return n;
  }

  /// Inside a meta box: QuickTime keys/ilst, and ©xyz items in an ilst.
  static int _meta(Uint8List b, int start, int end) {
    final locationKeys = <int>{};
    var n = 0;
    // First pass: which key indices name a location.
    var i = start;
    while (i + 8 <= end) {
      final box = _box(b, i, end);
      if (box == null) return n;
      final (size, header) = box;
      if (_isType(b, i + 4, 'keys')) {
        var k = i + header + 8; // version/flags, entry_count
        var index = 1;
        while (k + 8 <= i + size) {
          final ks = ByteData.sublistView(b, k, k + 4).getUint32(0);
          if (ks < 8 || k + ks > i + size) break;
          final name = latin1.decode(b.sublist(k + 8, k + ks), allowInvalid: true).toLowerCase();
          if (name.contains('location')) locationKeys.add(index);
          index++;
          k += ks;
        }
      }
      i += size;
    }
    // Second pass: neutralise matching ilst items (and any ©xyz item).
    i = start;
    while (i + 8 <= end) {
      final box = _box(b, i, end);
      if (box == null) return n;
      final (size, header) = box;
      if (_isType(b, i + 4, 'ilst')) {
        var j = i + header;
        while (j + 8 <= i + size) {
          final item = _box(b, j, i + size);
          if (item == null) break;
          final (isize, iheader) = item;
          final key = ByteData.sublistView(b, j + 4, j + 8).getUint32(0);
          if (locationKeys.contains(key) || _isXyz(b, j + 4)) {
            _neutralise(b, j, isize, iheader);
            n++;
          }
          j += isize;
        }
      }
      i += size;
    }
    return n;
  }

  /// (size, headerLength) of the box at [i], or null when it doesn't fit.
  static (int, int)? _box(Uint8List b, int i, int end) {
    if (i + 8 > end) return null;
    final bd = ByteData.sublistView(b, i, end);
    var size = bd.getUint32(0);
    var header = 8;
    if (size == 1) {
      if (i + 16 > end) return null;
      size = bd.getUint64(8);
      header = 16;
    } else if (size == 0) {
      size = end - i;
    }
    if (size < header || i + size > end) return null;
    return (size, header);
  }

  static void _neutralise(Uint8List b, int i, int size, int header) {
    b.setRange(i + 4, i + 8, ascii.encode('free'));
    b.fillRange(i + header, i + size, 0);
  }

  static bool _isType(List<int> b, int at, String t) =>
      b.length >= at + 4 &&
      b[at] == t.codeUnitAt(0) &&
      b[at + 1] == t.codeUnitAt(1) &&
      b[at + 2] == t.codeUnitAt(2) &&
      b[at + 3] == t.codeUnitAt(3);

  static bool _isXyz(List<int> b, int at) =>
      b.length >= at + 4 && b[at] == 0xA9 && b[at + 1] == 0x78 && b[at + 2] == 0x79 && b[at + 3] == 0x7A;

  static bool _isPrintable(List<int> b, int at) =>
      b.length >= at + 4 && [for (var k = 0; k < 4; k++) b[at + k]].every((c) => c >= 0x20 && c < 0x7F);
}
```

`chat_video_preparer.dart`:
- Add `import 'package:attune/features/chat/domain/services/mp4_location_stripper.dart';` in the import block, by hand, keeping the file's style.
- After `final outFile = compressed!.file!;`, add:

```dart
    // Where it was recorded stays on the phone (couple map spec §7): the
    // transcode keeps the source's location atoms; neutralise them in place.
    await Mp4LocationStripper.strip(outFile);
```

- [ ] **Step 4: Run it and confirm it passes,** together with `test/features/chat/chat_video_preparer_test.dart`.
- [ ] **Step 5: Ledger.**

---

### Task 2: Place lookups explain a missing permission and never prompt on their own

**Files:**
- Modify: `lib/features/couple_map/data/story_place_resolver.dart`, `lib/features/couple_map/presentation/camera/story_pin_controller.dart`, `lib/features/couple_map/presentation/camera/story_pin_toggle.dart`, `test/features/couple_map/support/fakes.dart`
- Test: `test/features/couple_map/story_pin_controller_test.dart` (add), `test/features/couple_map/story_pin_toggle_test.dart` (add)

**Interfaces:**
- Produces:
  - `enum StoryPlaceProblem { noPermission, notFound }`
  - `class StoryPlaceLookup { const StoryPlaceLookup.found(StoryPlaceDraft draft, {bool approximate = false}); const StoryPlaceLookup.failed(StoryPlaceProblem problem); final StoryPlaceDraft? draft; final bool approximate; final StoryPlaceProblem? problem; }`
  - `StoryPlaceResolver.resolve({required bool ask}) → Future<StoryPlaceLookup>`
  - `StoryPinNotice.noPermission`
  - `StoryPinController.approximate` (bool)
  - Fake: `FakeStoryPlaceResolver([StoryPlaceDraft? next])` with `problem`, `approximate`, and `asks` (`List<bool>`); `calls` stays

- [ ] **Step 1: Write the failing tests.** Add to `story_pin_controller_test.dart`:

```dart
  test('remembered on never prompts at camera open; only a tap may ask (Review Focus 2)', () async {
    final s = MemoryCoupleMapLocalStore();
    await writePinLastChoice(s, true);
    final r = FakeStoryPlaceResolver(_osu);
    final c = StoryPinController(store: s, resolver: r, paused: false);
    await c.init();
    expect(r.asks, [false]);
    await c.setOn(false);
    await c.setOn(true);
    expect(r.asks, [false, true]);
  });

  test('no permission: its own notice, nothing pinned', () async {
    final r = FakeStoryPlaceResolver()..problem = StoryPlaceProblem.noPermission;
    final c = StoryPinController(store: MemoryCoupleMapLocalStore(), resolver: r, paused: false);
    await c.init();
    await c.setOn(true);
    expect((c.on, c.notice), (true, StoryPinNotice.noPermission));
    expect(await c.placeForPost(), isNull);
  });

  test('iOS Precise Location off: pinned, and marked approximate', () async {
    final r = FakeStoryPlaceResolver(_osu)..approximate = true;
    final c = StoryPinController(store: MemoryCoupleMapLocalStore(), resolver: r, paused: false);
    await c.init();
    await c.setOn(true);
    expect(c.approximate, isTrue);
    expect((await c.placeForPost())?.label, 'Near Osu, Accra');
  });
```

Add to `story_pin_toggle_test.dart` (extend `_pump` with a `FakeStoryPlaceResolver? resolver` parameter, used instead of building one from `place`, and a `FakeSampler? sampler` that is already there):

```dart
  testWidgets('no permission: "Allow location…" opens settings', (t) async {
    final sampler = FakeSampler();
    await _pump(t, resolver: FakeStoryPlaceResolver()..problem = StoryPlaceProblem.noPermission, sampler: sampler);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Allow location for Attune to pin places'));
    await t.pumpAndSettle();
    expect(sampler.openedSettings, 1);
  });

  testWidgets('approximate: the preview says so', (t) async {
    await _pump(t, resolver: FakeStoryPlaceResolver(const StoryPlaceDraft(lat: 5.556, lng: -0.197, label: 'Near Osu, Accra'))..approximate = true);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Near Osu, Accra · approximate'), findsOneWidget);
  });
```

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

`story_place_resolver.dart`, replacing the interface and implementation:

```dart
enum StoryPlaceProblem { noPermission, notFound }

/// What a lookup found: a place (possibly approximate), or why not.
@immutable
class StoryPlaceLookup {
  const StoryPlaceLookup.found(StoryPlaceDraft this.draft, {this.approximate = false}) : problem = null;
  const StoryPlaceLookup.failed(StoryPlaceProblem this.problem) : draft = null, approximate = false;
  final StoryPlaceDraft? draft;
  final bool approximate;
  final StoryPlaceProblem? problem;
}

abstract class StoryPlaceResolver {
  /// [ask] lets the system permission prompt show. Only an explicit "on"
  /// tap asks; a remembered "on" at camera open never prompts (it would
  /// re-ask after a denial every time the camera opened).
  Future<StoryPlaceLookup> resolve({required bool ask});
}

class GeolocatorStoryPlaceResolver implements StoryPlaceResolver {
  @override
  Future<StoryPlaceLookup> resolve({required bool ask}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const StoryPlaceLookup.failed(StoryPlaceProblem.noPermission);
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask) {
        p = await Geolocator.requestPermission();
      }
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) {
        return const StoryPlaceLookup.failed(StoryPlaceProblem.noPermission);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: CoupleMapConfig.placeFixTimeout,
        ),
      );
      var approximate = false;
      try {
        approximate = await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced;
      } catch (_) {}
      String? neighbourhood;
      String? city;
      try {
        // The platform geocoder (Android Geocoder / iOS CLGeocoder): the
        // app calls no third-party HTTP API, though the OS may ask Google
        // or Apple.
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 10));
        final m = marks.isEmpty ? null : marks.first;
        neighbourhood = m?.subLocality;
        city = (m?.locality?.isNotEmpty ?? false) ? m!.locality : m?.subAdministrativeArea;
      } catch (_) {}
      final draft = StoryPlaceDraft(lat: pos.latitude, lng: pos.longitude,
          label: placeLabel(neighbourhood: neighbourhood, city: city));
      return draft.isValid
          ? StoryPlaceLookup.found(draft, approximate: approximate)
          : const StoryPlaceLookup.failed(StoryPlaceProblem.notFound);
    } catch (_) {
      return const StoryPlaceLookup.failed(StoryPlaceProblem.notFound);
    }
  }
}
```

(Add `import 'package:flutter/foundation.dart';` for `@immutable`.)

`story_pin_controller.dart`:
- `enum StoryPinNotice { paused, nearHome, notFound, noPermission }`.
- Field `bool _approximate = false;` with getter `bool get approximate => _approximate;`.
- `_lookupPlace({required bool remember})` gains `required bool ask` and calls `resolver.resolve(ask: ask)`:

```dart
    final lookup = await resolver.resolve(ask: ask);
    if (lookupId != _lookup || !_on) return;
    _resolving = false;
    final draft = lookup.draft;
    _place = draft;
    _approximate = lookup.approximate;
    if (draft == null) {
      _notice = lookup.problem == StoryPlaceProblem.noPermission
          ? StoryPinNotice.noPermission
          : StoryPinNotice.notFound;
    } else if (!_homeWarned) { …unchanged… } else { _notice = null; }
```

  (Rename the existing local `lookup` generation variable to `lookupId`.)
- `_init` calls `_lookupPlace(remember: false, ask: false)`.
- `_turnOn` (from `setOn(true)`) calls `_lookupPlace(remember: remember, ask: true)`.
- `setOn(false)` resets `_approximate = false`.

`story_pin_toggle.dart` subtitle switch:

```dart
    final sub = switch (c.notice) {
      StoryPinNotice.paused => 'Your area is paused',
      StoryPinNotice.nearHome => 'This looks near your home area',
      StoryPinNotice.notFound => "Couldn't find this place",
      StoryPinNotice.noPermission => 'Allow location for Attune to pin places',
      null => c.resolving
          ? 'Finding this place…'
          : (c.on && c.place != null
              ? (c.approximate ? '${c.place!.label} · approximate' : c.place!.label)
              : null),
    };
```

  When `c.notice == StoryPinNotice.noPermission`, wrap the subtitle `Text` in `GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => ref.read(presenceSamplerProvider).openSettings(), child: …)`. The Semantics label already includes the subtitle; add `onTap` to that `Semantics` only in this state.

`fakes.dart` `FakeStoryPlaceResolver`:

```dart
class FakeStoryPlaceResolver implements StoryPlaceResolver {
  FakeStoryPlaceResolver([this.next]);
  StoryPlaceDraft? next;
  StoryPlaceProblem? problem;
  bool approximate = false;
  int calls = 0;
  final asks = <bool>[];
  Completer<void>? hold;
  @override
  Future<StoryPlaceLookup> resolve({required bool ask}) async {
    calls++;
    asks.add(ask);
    await hold?.future;
    final p = problem;
    if (p != null) return StoryPlaceLookup.failed(p);
    final d = next;
    return d == null
        ? const StoryPlaceLookup.failed(StoryPlaceProblem.notFound)
        : StoryPlaceLookup.found(d, approximate: approximate);
  }
}
```

- [ ] **Step 4: Run them and confirm they pass:** `flutter test test/features/couple_map/ test/features/stories/story_camera_test.dart`.
- [ ] **Step 5: Ledger.**

---

### Task 3: The camera pill survives a failed post and fits small phones

**Files:**
- Modify: `lib/features/stories/presentation/screens/story_camera_screen.dart`, `lib/features/couple_map/presentation/camera/story_pin_toggle.dart`, `test/features/stories/story_camera_test.dart` (the `_FakeCaptureImagePreparer` gains `bool reject`)
- Test: `test/features/stories/story_camera_test.dart` (add), `test/features/couple_map/story_pin_toggle_test.dart` (add)

- [ ] **Step 1: Write the failing tests**

In `story_camera_test.dart`:
- `_FakeCaptureImagePreparer` gains `this.reject = false` (`final bool reject;`). At the top of `prepare`, after the gate: `if (reject) throw const CaptureImageRejected('media_compress_failed');`. Import `CaptureImageRejected` if it isn't visible.
- Add, in the file's style:

```dart
  testWidgets('couple map: a failed post keeps the same switch, with no second lookup (Review Focus 3)', (tester) async {
    final photoPath = await writeJpegFile(tester, 'photo.jpg');
    final videoPath = await writeFile(tester, 'clip.mp4');
    CameraPlatform.instance = _FakeCameraPlatform(videoPath: videoPath, photoPath: photoPath);
    final local = MemoryCoupleMapLocalStore();
    await writePinLastChoice(local, true);
    final resolver = FakeStoryPlaceResolver(const StoryPlaceDraft(lat: 5.556, lng: -0.197, label: 'Near Osu, Accra'));
    final h = buildContainer(extra: [
      coupleMapEnabledProvider.overrideWith((ref) async => true),
      presenceGatewayProvider.overrideWithValue(FakePresenceGateway({'couple_map_presence': (_) => const []})),
      presenceSamplerProvider.overrideWithValue(FakeSampler()),
      presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
      coupleMapLocalStoreProvider.overrideWithValue(local),
      storyPlaceResolverProvider.overrideWithValue(resolver),
    ]);
    await pumpToReady(tester, h.container, StoryCameraScreen(
      relationshipId: 'rel-1',
      videoPreparerFactory: () => _FakeChatVideoPreparer(),
      imagePreparerFactory: () => _FakeCaptureImagePreparer(reject: true),
      thumbnailPreparerFactory: () => _FakeCaptureImagePreparer(suffix: 'thumb'),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tapShutter(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Near Osu, Accra'), findsOneWidget, reason: 'the pill is back, same state');
    expect(resolver.calls, 1, reason: 'no second lookup or prompt');
  });
```

In `story_pin_toggle_test.dart`:

```dart
  testWidgets('fits a 320 dp screen: no overflow, title readable (Review Focus 5)', (t) async {
    t.view.physicalSize = const Size(192, 400); // the space between close and flip at 320 dp
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t, place: const StoryPlaceDraft(lat: 5.556, lng: -0.197, label: 'Near Osu, Accra'));
    expect(t.takeException(), isNull);
    expect(find.byIcon(Icons.place_outlined), findsNothing, reason: 'the icon gives way first');
    final title = t.renderObject<RenderParagraph>(find.text('Pin to our map'));
    expect(title.didExceedMaxLines, isFalse);
  });
```

(Import `package:flutter/rendering.dart` for `RenderParagraph`.)

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

`story_camera_screen.dart`: replace the `if (!_enqueuing) Positioned(...)` block with:

```dart
        // Couple map: "Pin to our map", between the close and flip buttons.
        // Kept mounted while a take is on its way (hidden and inert), so a
        // failed post brings back the same switch, with no second lookup
        // or permission prompt.
        Positioned(
          top: Spacing.xxl,
          left: 64,
          right: 64,
          child: Offstage(
            offstage: _enqueuing,
            child: IgnorePointer(
              ignoring: _enqueuing,
              child: Center(
                child: StoryPinToggle(
                  relationshipId: widget.relationshipId,
                  onController: (c) => _pin = c,
                ),
              ),
            ),
          ),
        ),
```

  Keep the `final pin = _pin;` capture: it's still right, and now doubly safe.

`story_pin_toggle.dart`:
- Raise `minHeight` from 44 to 48.
- Wrap the pill's `Row` in a `LayoutBuilder`. When `constraints.maxWidth < 220`, drop the leading icon and the gap after it, and use `TextStyle(fontSize: 13, …)` for the title:

```dart
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 220;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!compact) ...[
                      const Icon(Icons.place_outlined, color: Colors.white, size: 18),
                      const SizedBox(width: Spacing.sm),
                    ],
                    Flexible(child: /* the existing Column, title fontSize: compact ? 13 : 14 */),
                    Switch(value: c.on, onChanged: (v) => c.setOn(v)),
                  ],
                );
              },
            ),
```

- [ ] **Step 4: Run them and confirm they pass.**
- [ ] **Step 5: Ledger.**

---

### Task 4: The map stops flickering and follows theme and partner changes

**Files:**
- Modify: `lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart`, `lib/features/couple_map/presentation/screens/couple_map_tab.dart`, `lib/features/couple_map/presentation/widgets/distance_card.dart`
- Test: `test/features/couple_map/mapbox_wiring_test.dart` (add), `test/features/couple_map/couple_map_tab_test.dart` (add), `test/features/couple_map/distance_card_test.dart` (add)

- [ ] **Step 1: Write the failing tests**

`mapbox_wiring_test.dart`:

```dart
  test('presence areas update in place; layers are rebuilt only when the colour changes', () {
    final s = _src();
    final draw = s.substring(s.indexOf('Future<void> _draw('), s.indexOf('Future<void> fitTo('));
    expect(draw.contains('updateGeoJSON('), isTrue);
    expect(draw.contains('_areaColor'), isTrue);
  });

  test('dark is tracked before onReady (Review Focus 4)', () {
    final s = _src();
    final update = s.substring(s.indexOf('void didUpdateWidget('));
    expect(update.contains('widget.dark'), isTrue);
  });
```

`couple_map_tab_test.dart`:

```dart
  testWidgets('a partner who appears later is brought into view once', (t) async {
    final h = _Harness([_self]);
    await h.pump(t);
    expect(h.view.controller.fits, hasLength(1));
    h.rows = [_self, _partner()];
    ProviderScope.containerOf(t.element(find.byType(CoupleMapTab))).invalidate(coupleMapPresenceProvider('r1'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits, hasLength(2));
    expect(h.view.controller.fits.last.$1, hasLength(2));
    // A later refresh with the same people doesn't move the camera again.
    ProviderScope.containerOf(t.element(find.byType(CoupleMapTab))).invalidate(coupleMapPresenceProvider('r1'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits, hasLength(2));
  });

  testWidgets('a theme flip redraws story pins too (fills follow the theme)', (t) async {
    final h = _Harness([_self])..places = [storyPlaceRow('s1')];
    await h.pump(t);
    final before = h.view.controller.stories.length;
    h.themeMode = ThemeMode.dark;
    await t.pumpWidget(h._app());
    await t.pumpAndSettle();
    expect(h.view.controller.stories.length, greaterThan(before));
  });
```

`distance_card_test.dart`:

```dart
  testWidgets('a broken avatar URL shows initials quietly (no error report)', (t) async {
    await _pump(t, const DistanceCard(
      copy: DistanceCardCopy(headline: '8 hours by road', details: '', together: false),
      people: CoupleMapPeople(selfUrl: 'https://invalid.example/a.jpg', selfInitials: 'AM', partnerInitials: 'K', partnerName: 'Kofi'),
    ));
    final avatars = t.widgetList<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatars.any((a) => a.foregroundImage != null && a.onForegroundImageError != null), isTrue);
  });
```

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

`mapbox_couple_map_view.dart`:
- Add the field `int? _areaColor;`.
- In `_draw`, replace the unconditional remove/add of `_outline`/`_fill`/`_source` with:

```dart
    final style = map.style;
    final data = areasGeoJson(p.areas, together: p.together);
    final colour = p.areaColor.toARGB32();
    if (_areaColor == colour && await style.styleSourceExists(_source)) {
      // Same look, new areas: update the data in place (no flicker).
      final source = await style.getSource(_source);
      if (source is GeoJsonSource) await source.updateGeoJSON(data);
    } else {
      for (final layer in [_outline, _fill]) {
        if (await style.styleLayerExists(layer)) {
          await style.removeStyleLayer(layer);
        }
      }
      if (await style.styleSourceExists(_source)) {
        await style.removeStyleSource(_source);
      }
      await style.addSource(GeoJsonSource(id: _source, data: data));
      // (the two addLayer calls, unchanged)
      _areaColor = colour;
    }
```

- In `_styleLoaded`, set `_areaColor = null;` with the other resets.
- In `didUpdateWidget`, add:

```dart
    // A theme flip before onReady: the first style load must use it.
    if (old.dark != widget.dark) {
      _dark = widget.dark;
      final map = _map;
      if (map != null && _styleReady && _style == CoupleMapStyle.standard) {
        unawaited(map.style.setStyleImportConfigProperty('basemap', 'lightPreset', _dark ? 'night' : 'day'));
      }
    }
```

`couple_map_tab.dart`:
- Replace `bool _fitted = false;` with `final _fittedWho = <PresenceWho>{};`.
- In `_push`, replacing the `_fitted` block:

```dart
    // Fit when someone new is on the map (first open, or the partner
    // appearing later), never again for the same people.
    final who = {for (final a in areas) a.who};
    if (areas.isNotEmpty && !who.every(_fittedWho.contains)) {
      final first = _fittedWho.isEmpty;
      _fittedWho.addAll(who);
      await c.fitTo(
        [for (final a in areas) a.centre],
        animate: !first && !_reduceMotion,
      );
    }
```
- On load error, `_fittedWho.clear()` replaces `_fitted = false`.
- In the theme-flip post-frame callback, also `unawaited(_pushStories(_filtered(_allPlaces)));`.

`distance_card.dart` `_MiniAvatar`: add `onForegroundImageError: u == null || u.isEmpty ? null : (_, __) {},` with the comment `// Initials stay visible; a broken URL isn't an error worth reporting.`

- [ ] **Step 4: Run them and confirm they pass,** together with `test/features/couple_map/`.
- [ ] **Step 5: Ledger.**

---

### Task 5: The Sharing sheet's optimistic switch, and remove-all guarded

**Files:**
- Modify: `lib/features/couple_map/presentation/widgets/sharing_sheet.dart`
- Test: `test/features/couple_map/sharing_sheet_test.dart` (add)

- [ ] **Step 1: Write the failing tests**

```dart
  testWidgets('the switch moves at once while the call is in flight (no snap back)', (t) async {
    final gate = Completer<void>();
    await _pump(t, const [], handlers: {'start_presence': (_) => gate.future});
    await t.tap(find.byType(Switch).first);
    await t.pump();
    expect(t.widget<Switch>(find.byType(Switch).first).value, isTrue);
    gate.complete();
    await t.pumpAndSettle();
  });

  testWidgets('remove all: a double tap opens one dialog; the dialog has a short title', (t) async {
    final places = FakeStoryPlacesGateway({'clear_my_story_places': (_) => 1});
    await _pump(t, const [_self], placesGateway: places);
    await t.ensureVisible(find.text('Remove all my places'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove all my places'));
    await t.tap(find.text('Remove all my places'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Remove all your places?'), findsOneWidget);
    expect(find.text('Your stories stay.'), findsOneWidget);
  });
```

Update the existing remove-all test's expectation from the old one-sentence title to these two texts.

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**
- State `bool? _pendingOn;`. The toggle row's `toggleValue: _pendingOn ?? state.isOn`. In `onToggleChanged`, `setState(() => _pendingOn = v)` before `_run(...)`, and in `_run`'s `finally`, `if (mounted) setState(() => _pendingOn = null)`. (The invalidated read then shows the real state; a failure shows the error and snaps back to what is true.)
- `_removeAll`: `if (_busy) return; setState(() => _busy = true);` at the start and `if (mounted) setState(() => _busy = false);` in a `finally` (wrap the whole body). The dialog uses `title: const Text('Remove all your places?')` and `content: const Text('Your stories stay.')`.

- [ ] **Step 4: Run them and confirm they pass.**
- [ ] **Step 5: Ledger.**

---

### Task 6: Time zones are validated without scanning the catalogue

**Files:**
- Modify: `supabase/migrations/20261016100000_presence_v2.sql` (see Global Constraints for the already-deployed case), `supabase/tests/couple_map_presence_contracts.sql`

- [ ] **Step 1: Write the failing contract.** Append before `ROLLBACK;`:

```sql
-- C14. Time zones: IANA names only, checked without scanning pg_timezone_names.
DO $$
BEGIN
  IF NOT public.presence_tz_ok('Africa/Accra') OR NOT public.presence_tz_ok('UTC')
     OR NOT public.presence_tz_ok('America/Argentina/Buenos_Aires') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a real IANA zone was refused';
  END IF;
  IF public.presence_tz_ok('BST') OR public.presence_tz_ok('UTC+3') OR public.presence_tz_ok('Not/AZone')
     OR public.presence_tz_ok(NULL) OR public.presence_tz_ok('') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an abbreviation, POSIX string or unknown zone was accepted';
  END IF;
  IF position('pg_timezone_names' IN pg_get_functiondef('public.record_presence(uuid,double precision,double precision,double precision,text,text,text,text)'::regprocedure)) > 0
     OR position('pg_timezone_names' IN pg_get_functiondef('public.presence_offset_minutes(text)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: presence still scans pg_timezone_names';
  END IF;
END $$;
```

- [ ] **Step 2: Run it and confirm it fails.** `bash $SCRATCH/pg/run5.sh supabase/tests/couple_map_presence_contracts.sql`.

- [ ] **Step 3: Implement.** In the migration, before `record_presence`:

```sql
-- An IANA zone ("Africa/Accra", "UTC"), checked by trying it — no scan of
-- pg_timezone_names (tens of ms per call). Abbreviations like "BST" are
-- ambiguous and POSIX strings like "UTC+3" have the sign backwards, so
-- only Area/Location names (and UTC/GMT) are accepted.
CREATE OR REPLACE FUNCTION public.presence_tz_ok(p_tz text)
RETURNS boolean LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF p_tz IS NULL OR p_tz !~ '^([A-Za-z_]+(/[A-Za-z0-9_+-]+)+|UTC|GMT)$' THEN
    RETURN false;
  END IF;
  PERFORM now() AT TIME ZONE p_tz;
  RETURN true;
EXCEPTION WHEN invalid_parameter_value THEN
  RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.presence_tz_ok(text) FROM PUBLIC, anon, authenticated;
```

Then:
- in `record_presence`: `v_tz := CASE WHEN public.presence_tz_ok(p_timezone) THEN p_timezone END;`
- in `presence_offset_minutes`: `WHERE public.presence_tz_ok(p_tz)`

- [ ] **Step 4: Run it and confirm it passes,** together with every Phase 0 contract (C9 still stores `'BST'` as NULL) and the story places contracts on `run6.sh`.
- [ ] **Step 5: Mutation check.** Drop the regex line and see C14 (and C9) fail, then restore it.
- [ ] **Step 6: Ledger.**

---

### Task 7: Accessibility (48 dp targets, guideline checks in light and dark)

**Files:**
- Modify: `lib/features/couple_map/domain/couple_map_config.dart`, `lib/features/couple_map/presentation/widgets/glass_surface.dart`, `lib/features/couple_map/presentation/widgets/sharing_chip.dart`, `lib/features/couple_map/presentation/screens/couple_map_tab.dart`
- Test: `test/features/couple_map/accessibility_test.dart` (new), `test/features/couple_map/couple_map_tab_test.dart` (update the `ornamentTop` expectations, if any)

**Interfaces:**
- Produces:
  - `CoupleMapConfig.glassTarget = 48.0`, `glassGap = 4.0`, `glassGroupGap = 12.0`
  - `static double rightColumnBottom({required bool stories})`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/couple_map/accessibility_test.dart
// Spec §3.5 / checklist 5.6: every control on the map's surfaces meets the
// platform guidelines, in light and dark.
```

Reuse the tab harness by moving `_Harness`, `_self`, `_partner` and `_NoReminders` from `couple_map_tab_test.dart` into `test/features/couple_map/support/tab_harness.dart` (exported as `TabHarness`, `selfRow`, `partnerRow`), importing it in both files. That's a test-only refactor, so ledger it. Then:

```dart
void main() {
  Future<void> expectGuidelines(WidgetTester t) async {
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(textContrastGuideline));
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the map tab, with stories ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      final h = TabHarness([selfRow, partnerRow()])..themeMode = mode..places = [storyPlaceRow('s1')];
      await h.pump(t);
      await expectGuidelines(t);
      semantics.dispose();
    });

    testWidgets('the sharing sheet ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      final h = TabHarness([selfRow])..themeMode = mode;
      await h.pump(t);
      await t.tap(find.byType(SharingChip));
      await t.pumpAndSettle();
      await expectGuidelines(t);
      semantics.dispose();
    });

    testWidgets('the list sheet ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      final h = TabHarness([selfRow, partnerRow()])..themeMode = mode..places = [storyPlaceRow('s1')];
      await h.pump(t);
      await t.tap(find.byTooltip('List'));
      await t.pumpAndSettle();
      await expectGuidelines(t);
      semantics.dispose();
    });

    testWidgets('the not-sharing and offline cards ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      final h = TabHarness(const [])..themeMode = mode;
      await h.pump(t);
      await expectGuidelines(t);
      semantics.dispose();
    });
  }

  testWidgets('the camera pill over a dark viewfinder', (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(ProviderScope(
      overrides: [
        coupleMapEnabledProvider.overrideWith((ref) async => true),
        presenceGatewayProvider.overrideWithValue(FakePresenceGateway({'couple_map_presence': (_) => const []})),
        presenceSamplerProvider.overrideWithValue(FakeSampler()),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        coupleMapLocalStoreProvider.overrideWithValue(MemoryCoupleMapLocalStore()),
        storyPlaceResolverProvider.overrideWithValue(FakeStoryPlaceResolver(
          const StoryPlaceDraft(lat: 5.556, lng: -0.197, label: 'Near Osu, Accra'),
        )),
      ],
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: StoryPinToggle(relationshipId: 'r1', onController: (_) {})),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await expectGuidelines(t);
    semantics.dispose();
  });
}
```

Also add to `couple_map_tab_test.dart`: `expect(h.view.builtOrnamentTop, CoupleMapConfig.rightColumnBottom(stories: false))`, plus the `stories: true` variant in the stories test.

- [ ] **Step 2: Run it and confirm it fails** on `androidTapTargetGuideline`: the chip and glass buttons are 44 dp (confirmed by a probe while planning).

- [ ] **Step 3: Implement**

`couple_map_config.dart`:

```dart
  /// The glass buttons' hit area (Android 48 dp guideline); the visual
  /// circle inside stays [glassButtonSize] (44 dp).
  static const glassTarget = 48.0;

  /// Between two hit areas (8 dp between the visuals).
  static const glassGap = 4.0;

  /// Between the top group and the zoom pair (16 dp between the visuals).
  static const glassGroupGap = 12.0;

  /// Where the right-hand column ends, for the compass: top inset, the
  /// upper group (style, stories?, recentre, list), the group gap, the
  /// zoom pair, and a 16 dp margin.
  static double rightColumnBottom({required bool stories}) {
    final upper = stories ? 4 : 3;
    return 16 + upper * glassTarget + (upper - 1) * glassGap + glassGroupGap +
        2 * glassTarget + glassGap + 16;
  }
```

`glass_surface.dart` `GlassIconButton.build`: the outer `SizedBox.square(dimension: CoupleMapConfig.glassTarget)` holds a `Material(type: transparency)` + `InkWell(customBorder: CircleBorder(), onTap: onPressed)` filling the 48 dp, with `Center(child: SizedBox.square(dimension: size, child: GlassPanel(..., child: Icon(...))))` inside. The `Tooltip` and `Semantics` wrap the 48 dp box.

`sharing_chip.dart`: `minHeight: 48`.

`couple_map_tab.dart`:
- column gaps become `CoupleMapConfig.glassGap` (was `Spacing.sm`) and `CoupleMapConfig.glassGroupGap` (was `Spacing.md`);
- `ornamentTop: CoupleMapConfig.rightColumnBottom(stories: showStories)`;
- the chip's right inset becomes `Spacing.md + CoupleMapConfig.glassTarget + Spacing.sm`.

- [ ] **Step 4: Run it and confirm it passes,** together with all of `test/features/couple_map/`. Fix any further guideline failure the test reveals in the owning widget, and ledger each one.
- [ ] **Step 5: Ledger.**

---

### Task 8: Documentation

**Files:**
- Modify: `docs/superpowers/specs/2026-09-02-location-presence-design.md`, `docs/superpowers/specs/2026-10-16-couple-map-design.md`

- [ ] **Step 1:** Under `## 2. What this is NOT, and why` in the September spec, insert:

```markdown
> **Replaced (2026-10-16).** The "no partner map, no pin" ruling below was
> revisited with the owner and replaced by the couple map design
> (`docs/superpowers/specs/2026-10-16-couple-map-design.md`): the partner
> appears only as an approximate ~1 km area, with mutual opt-in, a silent
> symmetric pause, no timestamps, 8-hour staleness and purge on unlink.
> The reasoning below is kept: it is why those safeguards exist.
```

- [ ] **Step 2:** In the couple map spec:
  - §7: add a "Status" column marking Phase 0–3 as built (uncommitted, review fixes applied).
  - §10: append a short entry per phase: the date, the Fable verdict, and "Critical/Important fixed; minors in the phase ledger".
- [ ] **Step 3:** A source test confirms both docs: `test/features/couple_map/docs_test.dart` asserts the September spec contains `Replaced (2026-10-16)` and the couple map spec's §7 contains `Status`. (It's tiny, but it keeps the doc obligation from being silently dropped.)
- [ ] **Step 4: Ledger.**

---

## Final verification (Phase 3 exit)

1. Full `flutter test` is green; a flaky test is rerun three times and named.
2. `flutter analyze lib test 2>&1 | grep -E "^\s*(error|warning) "`: 0 errors, and nothing in touched files.
3. `git diff --numstat` on every pre-existing file matches its real change, with no format churn.
4. Contracts: `couple_map_presence` (C1–C14), `location_presence`, `story_places`, the story suites, `together_*` and `reminder_*`. All PASS on `run6.sh`.
5. Builds: `flutter build apk --debug` and `flutter build ios --debug --no-codesign`.
6. Coverage: the stripper ≥ 90 %, couple_map widgets ≥ 50 %.
7. Scans: secrets; a PII grep that also covers `mp4_location_stripper.dart`, which must log nothing.
8. A Fable review of the Phase 3 diff, then one fix pass.
9. **Device checks for the owner** (added to the existing list):
   - record a video with location on (iPhone and Android), send it, download it, and confirm `exiftool` or `ffprobe` shows no GPS while the video still plays;
   - deny location, then reopen the camera with the remembered "on": no prompt, and the "Allow location…" line shows;
   - Precise Location off, then "· approximate";
   - TalkBack and VoiceOver pass over the map tab, the sheet and the reel.

## Checklist v3.1 evidence map (Phase 3)

| Item | Where it's proven |
|---|---|
| 1.11 / 4.4 Privacy | Video location atoms neutralised (Task 1 tests); the stripper logs nothing (PII grep) |
| 1.3 Graceful degradation | Unparseable video left untouched and the send continues (Task 1); no permission explained (Task 2); a failed post keeps the switch (Task 3) |
| 2.1 Input sanitisation | `presence_tz_ok` (C14) |
| 3.x Performance | No catalogue scan per presence call (C14); presence data in place (Task 4) |
| 5.1 / 5.2 UX | Optimistic switch (Task 5); no flicker (Task 4); partner brought into view (Task 4) |
| 5.6 Accessibility | Guideline tests in light and dark (`ThemeData.light`/`dark`) across the tab, the sharing sheet (A7 `MergeSemantics`), the list sheet, the cards, the camera pill in three states (found, approximate, allowLocation; A2) and the reel place controls; plus a real text-contrast check on every `Text` (A8) |
| 6.1 / 6.4 Edge cases | 64-bit mdat, moov last, ISO vs QuickTime meta, truncated or empty files (Task 1); abbreviations and POSIX zones (C14) |
| 6.8 Mutation | Task 6 Step 5 |
