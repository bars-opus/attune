# Couple Distance Widget — W2 (native widgets + deep link) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The home-screen widgets that display W1's payload:
- iOS `CoupleWidget` (small and medium) in the existing `TogetherWidgets` bundle;
- Android `CoupleWidgetProvider` (2×2 and 4×2), with an expiry alarm that survives Doze;
- a tap that opens Planning → Map.

**Architecture:**
- **Shared test vectors.** A Dart test writes the payload → view cases from W1's `resolveCoupleWidget` into a JSON fixture. The Kotlin `CoupleWidgetModel` (JUnit) and Swift `CoupleWidgetModel` (`swiftc` check binary) are tested against that same file, so all three resolvers agree.
- **Native views.** They only bind the model's output. The live clock is the platform's own: `TextClock` on Android, `Text(date, style: .time)` on iOS.
- **The tap.** Both platforms launch `attune://planning?tab=map`. app_links delivers it to `_handleDeepLink`, which calls a tested `openPlanningFromLink`. That pushes `/planning?tab=map`, and `PlanningHomeScreen(initialTab:)` jumps to the Map tab once the flag-gated tab exists.

**Tech Stack:**
- Kotlin 2.1.20, AGP 8.7, minSdk 24, compileSdk 36, `home_widget` 0.9.2+1 (`HomeWidgetProvider`, `HomeWidgetLaunchIntent`, `HomeWidgetPlugin.getData`).
- SwiftUI/WidgetKit (TogetherWidget target, iOS 14.0), the `xcodeproj` Ruby gem.
- Flutter/GoRouter/Riverpod, app_links 6.4.1.

**Spec:** `docs/superpowers/specs/2026-10-16-couple-distance-widget-design.md` (§3, §4, §6.2, §6.3, §6.5, W2 row of §7). Builds on W1: `docs/superpowers/plans/2026-10-16-couple-widget-w1.md` (built, uncommitted).

## Global Constraints

**How we work**
- Work directly on `main`. **No commits or pushes**: ledger lines instead.
- Write each test first and watch it fail.
- **Never `dart format` a pre-existing file.** Format only files this plan creates.
- **Snapshot every shared file** into `$WS/snapshots/` before editing, and `diff -u` it afterwards. Here `$WS` = `.superpowers/sdd/2026-10-16-couple-widget-w2`.
- Analyzer gate on touched Dart: `flutter analyze <files> 2>&1 | grep -E "^\s*(error|warning) "` prints nothing.

**Shared files touched** (each a surgical edit; ledger its regression risk)
- `android/app/build.gradle.kts` (test-only dependencies)
- `android/app/src/main/AndroidManifest.xml` (one `<receiver>`)
- `ios/Runner.xcodeproj/project.pbxproj` (two file refs, via the script)
- `ios/TogetherWidget/TogetherWidget.swift` (one bundle line)
- `lib/home/widgets/tabs_with_content.dart` (re-notify the controller after a tab-count change)
- `lib/features/planning/presentation/screens/planning_home_screen.dart` (`initialTab`, map-content seam)
- `lib/app/routing/app_router.dart` (`/planning` reads `?tab=`)
- `lib/main.dart` (one deep-link branch + helper)

**Native code must not**
- Use the network, Supabase, or any token. Extensions only read the App Group / `HomeWidgetPreferences`.
- Log anything: no `Log.`, `print`, `NSLog` or `os_log` in the new native files.
- Show any partner name, city, place or app name on the card.

**Keys and names (verbatim, must match W1)**
- Payload key `couple_widget_v1`; image key `couple_widget_map`.
- App Group `group.com.barsopus.attune`.
- iOS kind `CoupleWidget`; Android class `com.barsopus.attune.CoupleWidgetProvider`.
- The image file lives at `<App Group container>/home_widget/<name>` on iOS, and `<filesDir>/home_widget/<name>` on Android.

**Copy (verbatim)**
- Gallery name "Apart"; description "Time and distance between you two. Turn it on in Attune first."
- Neutral "Nothing to show yet".
- Countdown: "Together today", "Together tomorrow", "{n} days until you're together"; with no distance, "{n} days" / "until you're together".
- Clock suffix " there".

**Link**
- `attune://planning?tab=map`, with no ids and no `homeWidget` query item.
- Ruling, recorded in Task 8's spec amendment: the plugin's iOS app-delegate hook claims any URL carrying `homeWidget`. A plain URL reaches only app_links.

**Behaviour**
- **Expiry:** distance until `validUntilMs`, then countdown or neutral. Android: `AlarmManager.setAndAllowWhileIdle(RTC, nextChange, …)`, plus `updatePeriodMillis = 1800000` as a backstop. iOS: timeline entries at now and at the next change, policy `.after(next)`.
- **Countdown** ticks at local midnight with no app write: midnight is a "next change" whenever a reunion date is present.

## Review Focus

1. **The map file is missing or unreadable while the payload has a distance** (cleared mid-render, iOS reinstall changed the container, a corrupt PNG). Expected: the text layout, no crash. `isWidgetFile` rejecting missing or outside paths is pinned by Task 2's JVM test. Android `loadMap` returning null on any failure, and iOS's nil image, are covered by code reading plus the device check (Android APIs aren't on the JVM).
2. **Midnight passes with a reunion counting down and the app closed.** Expected: "12 days…" becomes "11 days…" on its own. Pinned in Tasks 2 and 4 (`nextChange` returns midnight whenever a reunion is present).
3. **The widget is tapped while signed out, unpaired, on quick exit's neutral screen, or already on Planning.** Expected: no navigation. Pinned in Task 7 (deep-link tests).
4. **Half-hour and negative partner offsets** (India +5:30, Newfoundland −3:30). Expected: the clock shows their real local time.
   - Android: pinned by Task 2 (`zoneId`) and Task 1 (a −210 vector).
   - iOS: `ClockText` shifts the instant by its own arithmetic and doesn't rely on the environment's time zone. That's checked on a simulator in Task 5, Step 4 with offset 330.
5. **The Map tab appears only after the flag loads** (async), so the jump must wait for it. Expected: the link still lands on Map. Pinned in Task 6 (the flag override is async, so the test exercises the late tab).

---

## File Structure

| File | Responsibility |
|---|---|
| `test/features/couple_map/widget/couple_widget_vectors_test.dart` (new) | Generates and verifies the shared vectors from W1's Dart resolver |
| `test/features/couple_map/widget/fixtures/couple_widget_vectors.json` (new, generated) | The vectors all three platforms test against |
| `android/app/src/main/kotlin/com/barsopus/attune/CoupleWidgetModel.kt` (new) | Pure resolver, next change, zone id, file check (JVM-testable) |
| `android/app/src/test/kotlin/com/barsopus/attune/CoupleWidgetModelTest.kt` (new) | JUnit against the vectors |
| `android/app/src/main/kotlin/com/barsopus/attune/CoupleWidgetProvider.kt` (new) | Binds views, loads the map, schedules expiry |
| `android/app/src/main/res/layout/couple_widget_small.xml`, `couple_widget_medium.xml` (new) | The two layouts |
| `android/app/src/main/res/xml/couple_widget_info.xml` (new) | Provider info |
| `android/app/src/main/res/values/couple_widget_strings.xml`, `values/couple_widget_colors.xml`, `values-night/couple_widget_colors.xml` (new) | Copy and colours |
| `android/app/src/main/res/drawable/couple_widget_bg.xml`, `drawable-v31/couple_widget_bg.xml`, `drawable/couple_widget_heart.xml` (new) | Background (system radius on 31+) and neutral glyph |
| `ios/TogetherWidget/CoupleWidgetModel.swift` (new) | Pure resolver (Foundation only) |
| `ios/TogetherWidgetChecks/main.swift` (new, not in any target) | `swiftc` check against the vectors |
| `ios/TogetherWidget/CoupleWidget.swift` (new) | Provider, views, widget |
| `lib/features/couple_map/widget/presentation/widget_deep_link.dart` (new) | `planningTabFromLink`, `openPlanningFromLink` |
| `test/features/couple_map/widget/widget_deep_link_test.dart` (new) | Deep-link tests |
| `test/home/tabs_with_content_controller_test.dart` (new) | The re-notify test |

---

### Task 1: Shared view vectors (Dart is the reference)

**Files:**
- Create: `test/features/couple_map/widget/couple_widget_vectors_test.dart`
- Create (generated in Step 3): `test/features/couple_map/widget/fixtures/couple_widget_vectors.json`

**Interfaces:**
- Consumes: `CoupleWidgetPayload`, `resolveCoupleWidget`, `neutralHeadline`, `dateKey` (W1 `couple_widget_payload.dart`); `formatClock` (`distance_copy.dart`).
- Produces the fixture: `{nowMs, today: "2026-10-16", neutralHeadline, vectors: [{name, payload: String|null, expect: {headline: String|null, headlineIsClock, caption: String|null, clockLine, clockOffsetMinutes: int|null, neutral, showMap}}]}`.
  - `headline` is null when the headline is the live clock.
  - `clockOffsetMinutes` is set only when a clock is shown.
  - `showMap` = the distance part is live and the view isn't neutral.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/couple_map/widget/couple_widget_vectors_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:flutter_test/flutter_test.dart';

const fixturePath =
    'test/features/couple_map/widget/fixtures/couple_widget_vectors.json';

/// Noon UTC: the same calendar date in every zone from UTC-11 to UTC+11
/// (a machine at UTC+12/+13 fails the first test; regenerate there with care).
final nowMs = DateTime.utc(2026, 10, 16, 12).millisecondsSinceEpoch;
const today = '2026-10-16';

int at(Duration d) => nowMs + d.inMilliseconds;
String p(Map<String, Object> m) => jsonEncode({'v': 1, ...m});
final live = at(const Duration(hours: 1));
final gone = at(const Duration(minutes: -1));

final cases = <(String, String?)>[
  ('null payload', null),
  ('malformed', '{'),
  ('unknown version', '{"v":2,"headline":"x"}'),
  ('empty', '{"v":1}'),
  ('together', p({'headline': 'Practically together', 'validUntilMs': live})),
  ('nearby', p({'headline': '15 min away', 'validUntilMs': live})),
  (
    'same country with clock line',
    p({
      'headline': '8 hours by road',
      'caption': '400 km apart',
      'clockOffsetMinutes': 60,
      'clockLine': true,
      'validUntilMs': live,
    }),
  ),
  (
    'same country, same zone',
    p({'headline': '8 hours by road', 'caption': '400 km apart', 'validUntilMs': live}),
  ),
  (
    'distant clock headline',
    p({
      'headlineIsClock': true,
      'caption': '5.1k km apart',
      'clockOffsetMinutes': 330,
      'validUntilMs': live,
    }),
  ),
  (
    'distant clock headline, negative half hour',
    p({
      'headlineIsClock': true,
      'caption': '9.2k km apart',
      'clockOffsetMinutes': -210,
      'validUntilMs': live,
    }),
  ),
  ('distant without offset', p({'headline': '5.1k km apart', 'validUntilMs': live})),
  (
    'countdown 12 days with clock line',
    p({
      'caption': '5.1k km apart',
      'clockOffsetMinutes': 60,
      'clockLine': true,
      'validUntilMs': live,
      'reunionDate': '2026-10-28',
    }),
  ),
  (
    'countdown tomorrow',
    p({'caption': '5.1k km apart', 'validUntilMs': live, 'reunionDate': '2026-10-17'}),
  ),
  (
    'countdown today',
    p({'caption': '5.1k km apart', 'validUntilMs': live, 'reunionDate': '2026-10-16'}),
  ),
  (
    'expired distance, reunion in 12 days',
    p({'caption': '5.1k km apart', 'validUntilMs': gone, 'reunionDate': '2026-10-28'}),
  ),
  (
    'expired distance, reunion tomorrow',
    p({'caption': '5.1k km apart', 'validUntilMs': gone, 'reunionDate': '2026-10-17'}),
  ),
  ('expired distance alone', p({'headline': '8 hours by road', 'validUntilMs': gone})),
  ('valid until exactly now', p({'headline': 'x', 'validUntilMs': nowMs})),
  ('past reunion', p({'reunionDate': '2026-10-15'})),
  ('malformed reunion date', p({'reunionDate': 'soon'})),
  ('clock headline without offset', p({'headlineIsClock': true, 'validUntilMs': live})),
];

Map<String, Object?> expectFor(String? raw) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final stored = CoupleWidgetPayload.decode(raw);
  final cur = stored.current(now);
  final v = resolveCoupleWidget(stored, now);
  final off = cur.clockOffsetMinutes;
  final clock =
      off == null
          ? null
          : '${formatClock(now.toUtc().add(Duration(minutes: off)))} there';
  final headlineIsClock = clock != null && v.headline == clock;
  final clockLine = v.clockLine != null;
  return {
    'headline': headlineIsClock ? null : v.headline,
    'headlineIsClock': headlineIsClock,
    'caption': v.caption,
    'clockLine': clockLine,
    'clockOffsetMinutes': headlineIsClock || clockLine ? off : null,
    'neutral': v.neutral,
    'showMap': cur.hasDistance && !v.neutral,
  };
}

String encodeVectors() =>
    '${const JsonEncoder.withIndent('  ').convert({
      'nowMs': nowMs,
      'today': today,
      'neutralHeadline': neutralHeadline,
      'vectors': [
        for (final (name, raw) in cases) {'name': name, 'payload': raw, 'expect': expectFor(raw)},
      ],
    })}\n';

void main() {
  test("the machine's date at nowMs is the fixture's today", () {
    expect(dateKey(DateTime.fromMillisecondsSinceEpoch(nowMs)), today);
  });

  test('native resolvers share these vectors (regenerate: UPDATE_VECTORS=1)', () {
    final file = File(fixturePath);
    final fresh = encodeVectors();
    if (Platform.environment['UPDATE_VECTORS'] == '1') {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(fresh);
    }
    expect(file.existsSync(), isTrue, reason: 'run once with UPDATE_VECTORS=1');
    expect(file.readAsStringSync(), fresh);
  });

  test('the vectors cover every view shape', () {
    final vs = ((jsonDecode(encodeVectors()) as Map)['vectors'] as List)
        .map((v) => (v as Map)['expect'] as Map)
        .toList();
    expect(vs.any((e) => e['neutral'] == true), isTrue);
    expect(vs.any((e) => e['headlineIsClock'] == true), isTrue);
    expect(vs.any((e) => e['clockLine'] == true), isTrue);
    expect(vs.any((e) => e['showMap'] == true), isTrue);
    expect(vs.any((e) => e['showMap'] == false && e['neutral'] == false), isTrue);
    expect(vs.any((e) => e['clockOffsetMinutes'] == -210), isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/couple_map/widget/couple_widget_vectors_test.dart`
Expected: "native resolvers share these vectors" FAILS ("run once with UPDATE_VECTORS=1"); the other two pass.

- [ ] **Step 3: Generate the fixture, then read it**

Run: `UPDATE_VECTORS=1 flutter test test/features/couple_map/widget/couple_widget_vectors_test.dart`, then open the JSON. Check by eye:
- "countdown tomorrow" → headline "Together tomorrow" with showMap true;
- "expired distance, reunion in 12 days" → "12 days" + "until you're together";
- "past reunion" → neutral;
- "valid until exactly now" → neutral.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/features/couple_map/widget/couple_widget_vectors_test.dart`
Expected: 3/3 pass.

- [ ] **Step 5: Format the new test file and ledger**

---

### Task 2: Kotlin model + JUnit (Android)

**Files:**
- Modify: `android/app/build.gradle.kts`. Append a `dependencies {}` block; the file has none today.
- Create: `android/app/src/main/kotlin/com/barsopus/attune/CoupleWidgetModel.kt`
- Create: `android/app/src/test/kotlin/com/barsopus/attune/CoupleWidgetModelTest.kt`

**Interfaces:**
- Consumes: the Task 1 fixture, read at `../../test/features/couple_map/widget/fixtures/couple_widget_vectors.json` (Gradle unit tests run with the working directory `android/app`).
- Produces:
  - `data class CoupleWidgetView(headline: String?, headlineIsClock: Boolean, caption: String?, clockLine: Boolean, clockOffsetMinutes: Int?, neutral: Boolean, showMap: Boolean)`
  - `object CoupleWidgetModel`:
    - `NEUTRAL_HEADLINE`;
    - `resolve(raw: String?, nowMs: Long, today: Long): CoupleWidgetView`;
    - `nextChangeMs(raw: String?, nowMs: Long, nextMidnightMs: Long): Long?`;
    - `epochDay(year: Int, month: Int, day: Int): Long`;
    - `zoneId(offsetMinutes: Int): String`;
    - `isWidgetFile(path: String?, filesDir: File): Boolean`.

- [ ] **Step 1: Add test-only dependencies (snapshot the file first)**

Append to `android/app/build.gradle.kts`:
```kotlin

// JVM unit tests for the home-screen widget's pure logic (widget spec §8).
// org.json is the real library: Android's stub throws in plain JVM tests.
dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
```

- [ ] **Step 2: Write the failing test**

```kotlin
// android/app/src/test/kotlin/com/barsopus/attune/CoupleWidgetModelTest.kt
package com.barsopus.attune

import java.io.File
import java.nio.file.Files
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors Dart's resolveCoupleWidget through the shared vectors (widget spec §8). */
class CoupleWidgetModelTest {
    private val fixture = JSONObject(
        File("../../test/features/couple_map/widget/fixtures/couple_widget_vectors.json").readText(),
    )
    private val nowMs = fixture.getLong("nowMs")
    private val today = fixture.getString("today").split("-").let {
        CoupleWidgetModel.epochDay(it[0].toInt(), it[1].toInt(), it[2].toInt())
    }

    private fun JSONObject.str(key: String): String? = if (isNull(key)) null else getString(key)

    @Test
    fun matchesTheDartVectors() {
        val vectors = fixture.getJSONArray("vectors")
        assertTrue(vectors.length() >= 20)
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            val e = v.getJSONObject("expect")
            val name = v.getString("name")
            val got = CoupleWidgetModel.resolve(v.str("payload"), nowMs, today)
            assertEquals(name, e.str("headline"), got.headline)
            assertEquals(name, e.getBoolean("headlineIsClock"), got.headlineIsClock)
            assertEquals(name, e.str("caption"), got.caption)
            assertEquals(name, e.getBoolean("clockLine"), got.clockLine)
            assertEquals(
                name,
                if (e.isNull("clockOffsetMinutes")) null else e.getInt("clockOffsetMinutes"),
                got.clockOffsetMinutes,
            )
            assertEquals(name, e.getBoolean("neutral"), got.neutral)
            assertEquals(name, e.getBoolean("showMap"), got.showMap)
        }
    }

    @Test
    fun neutralCopyMatchesDart() {
        assertEquals(fixture.getString("neutralHeadline"), CoupleWidgetModel.NEUTRAL_HEADLINE)
    }

    @Test
    fun epochDays() {
        assertEquals(0L, CoupleWidgetModel.epochDay(1970, 1, 1))
        assertEquals(20742L, CoupleWidgetModel.epochDay(2026, 10, 16))
        assertEquals(19782L, CoupleWidgetModel.epochDay(2024, 2, 29))
    }

    @Test
    fun nextChangeIsTheEarlierOfExpiryAndMidnight() {
        val both = """{"v":1,"validUntilMs":5000,"reunionDate":"2026-10-28"}"""
        assertEquals(5000L, CoupleWidgetModel.nextChangeMs(both, 1000, 9000))
        val late = """{"v":1,"validUntilMs":9000,"reunionDate":"2026-10-28"}"""
        assertEquals(5000L, CoupleWidgetModel.nextChangeMs(late, 1000, 5000))
        assertNull(CoupleWidgetModel.nextChangeMs("""{"v":1}""", 1000, 5000))
        assertNull(CoupleWidgetModel.nextChangeMs("""{"v":1,"validUntilMs":500}""", 1000, 5000))
        assertNull(CoupleWidgetModel.nextChangeMs("{", 1000, 5000))
        assertNull(CoupleWidgetModel.nextChangeMs(null, 1000, 5000))
    }

    @Test
    fun zoneIdsForTextClock() {
        assertEquals("GMT+05:30", CoupleWidgetModel.zoneId(330))
        assertEquals("GMT-03:30", CoupleWidgetModel.zoneId(-210))
        assertEquals("GMT+00:00", CoupleWidgetModel.zoneId(0))
        assertEquals("GMT+14:00", CoupleWidgetModel.zoneId(840))
    }

    @Test
    fun onlyFilesInsideOurWidgetFolderAreRead() {
        val files = Files.createTempDirectory("files").toFile()
        val folder = File(files, "home_widget").apply { mkdirs() }
        val map = File(folder, "couple_widget_map.png").apply { writeBytes(byteArrayOf(1)) }
        assertTrue(CoupleWidgetModel.isWidgetFile(map.path, files))
        assertFalse(CoupleWidgetModel.isWidgetFile(File(folder, "missing.png").path, files))
        assertFalse(CoupleWidgetModel.isWidgetFile(File(files, "elsewhere.png").apply { writeBytes(byteArrayOf(1)) }.path, files))
        assertFalse(CoupleWidgetModel.isWidgetFile("${folder.path}/../elsewhere.png", files))
        assertFalse(CoupleWidgetModel.isWidgetFile(null, files))
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.barsopus.attune.CoupleWidgetModelTest 2>&1 | tail -15`
Expected: compilation FAILS with an unresolved reference to `CoupleWidgetModel` (Kotlin 2.1 prints `Unresolved reference 'CoupleWidgetModel'.`).

If Gradle reports no tests found, the Kotlin plugin isn't picking up `src/test/kotlin`. Then move the file to `android/app/src/test/java/com/barsopus/attune/` (Kotlin compiles from `java/` dirs too) and ledger it as a ruling.

- [ ] **Step 4: Write the model**

```kotlin
// android/app/src/main/kotlin/com/barsopus/attune/CoupleWidgetModel.kt
package com.barsopus.attune

import java.io.File
import java.util.Locale
import org.json.JSONObject

/**
 * What the distance widget shows (widget spec §3.1). Mirrors Dart's
 * resolveCoupleWidget; the live clock is a TextClock, so only its offset and
 * slot are returned. Pure: unit tested on the JVM against the shared vectors.
 */
data class CoupleWidgetView(
    val headline: String?,
    val headlineIsClock: Boolean,
    val caption: String?,
    val clockLine: Boolean,
    val clockOffsetMinutes: Int?,
    val neutral: Boolean,
    val showMap: Boolean,
)

object CoupleWidgetModel {
    const val NEUTRAL_HEADLINE = "Nothing to show yet"

    private val NEUTRAL = CoupleWidgetView(NEUTRAL_HEADLINE, false, null, false, null, true, false)

    private class Payload(
        val headline: String?,
        val headlineIsClock: Boolean,
        val caption: String?,
        val clockOffsetMinutes: Int?,
        val clockLine: Boolean,
        val validUntilMs: Long?,
        val reunionDate: String?,
    )

    private fun JSONObject.text(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null

    private fun parse(raw: String?): Payload? = try {
        if (raw == null) {
            null
        } else {
            val o = JSONObject(raw)
            if ((o.opt("v") as? Int) != 1) {
                null
            } else {
                Payload(
                    headline = o.text("headline"),
                    headlineIsClock = o.optBoolean("headlineIsClock", false),
                    caption = o.text("caption"),
                    clockOffsetMinutes = if (o.has("clockOffsetMinutes")) o.getInt("clockOffsetMinutes") else null,
                    clockLine = o.optBoolean("clockLine", false),
                    validUntilMs = if (o.has("validUntilMs")) o.getLong("validUntilMs") else null,
                    reunionDate = o.text("reunionDate"),
                )
            }
        }
    } catch (_: Exception) {
        null
    }

    /** Days since 1970-01-01 for a civil date (Hinnant); no java.time on minSdk 24. */
    fun epochDay(year: Int, month: Int, day: Int): Long {
        val y = if (month <= 2) year - 1 else year
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val mp = (month + 9) % 12
        val doy = (153 * mp + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097L + doe - 719468
    }

    private fun epochDay(date: String): Long? {
        val parts = date.split("-")
        if (parts.size != 3) return null
        val y = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        val d = parts[2].toIntOrNull() ?: return null
        return epochDay(y, m, d)
    }

    private fun countdown(days: Long) = when (days) {
        0L -> "Together today"
        1L -> "Together tomorrow"
        else -> "$days days until you're together"
    }

    fun resolve(raw: String?, nowMs: Long, today: Long): CoupleWidgetView {
        val p = parse(raw) ?: return NEUTRAL
        val live = p.validUntilMs != null && p.validUntilMs > nowMs
        val days = p.reunionDate?.let { epochDay(it) }?.let { it - today }?.takeIf { it >= 0 }
        val off = p.clockOffsetMinutes
        val clockLine = p.clockLine && off != null
        if (live) {
            if (days != null) {
                return CoupleWidgetView(countdown(days), false, p.caption, clockLine, if (clockLine) off else null, false, true)
            }
            if (p.headlineIsClock && off != null) {
                return CoupleWidgetView(null, true, p.caption, false, off, false, true)
            }
            if (p.headline != null) {
                return CoupleWidgetView(p.headline, false, p.caption, clockLine, if (clockLine) off else null, false, true)
            }
        }
        if (days != null) {
            return if (days <= 1) {
                CoupleWidgetView(countdown(days), false, null, false, null, false, false)
            } else {
                CoupleWidgetView("$days days", false, "until you're together", false, null, false, false)
            }
        }
        return NEUTRAL
    }

    /** When the view next changes by itself: the distance expiring, or local
     * midnight while a reunion counts down (spec §4.2). */
    fun nextChangeMs(raw: String?, nowMs: Long, nextMidnightMs: Long): Long? {
        val p = parse(raw) ?: return null
        val candidates = mutableListOf<Long>()
        p.validUntilMs?.takeIf { it > nowMs }?.let { candidates += it }
        if (p.reunionDate != null) candidates += nextMidnightMs
        return candidates.minOrNull()
    }

    /** "GMT+05:30": a TextClock zone id for a fixed offset. */
    fun zoneId(offsetMinutes: Int): String {
        val sign = if (offsetMinutes < 0) "-" else "+"
        val abs = kotlin.math.abs(offsetMinutes)
        return String.format(Locale.ROOT, "GMT%s%02d:%02d", sign, abs / 60, abs % 60)
    }

    /** Only an existing file inside our own home_widget folder (spec §4.4, checklist 2.1). */
    fun isWidgetFile(path: String?, filesDir: File): Boolean = try {
        if (path == null) {
            false
        } else {
            val file = File(path).canonicalFile
            val folder = File(filesDir, "home_widget").canonicalFile
            file.isFile && file.parentFile == folder
        }
    } catch (_: Exception) {
        false
    }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.barsopus.attune.CoupleWidgetModelTest 2>&1 | tail -15`
Expected: `BUILD SUCCESSFUL`, with 6 tests passed (check `android/app/build/test-results/testDebugUnitTest/*.xml`).

- [ ] **Step 6: Snapshot-diff `build.gradle.kts` (only the appended block) and ledger**

---

### Task 3: Android provider, layouts and expiry alarm

**Files:**
- Create: `CoupleWidgetProvider.kt`; layouts `couple_widget_small.xml`, `couple_widget_medium.xml`; `xml/couple_widget_info.xml`; `values/couple_widget_strings.xml`; `values/couple_widget_colors.xml`; `values-night/couple_widget_colors.xml`; `drawable/couple_widget_bg.xml`, `drawable-v31/couple_widget_bg.xml`, `drawable/couple_widget_heart.xml`
- Modify: `android/app/src/main/AndroidManifest.xml` (one receiver, after the TogetherWidgetProvider receiver)

**Interfaces:**
- Consumes: `CoupleWidgetModel` (Task 2); `HomeWidgetProvider`, `HomeWidgetPlugin.getData(context)`, `HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)`.
- Produces: `com.barsopus.attune.CoupleWidgetProvider`. This is the class W1's `updateWidget(qualifiedAndroidName:)` names.

- [ ] **Step 1: Write the resources**

```xml
<!-- android/app/src/main/res/values/couple_widget_strings.xml -->
<resources>
    <string name="couple_widget_name">Apart</string>
    <string name="couple_widget_description">Time and distance between you two. Turn it on in Attune first.</string>
    <string name="couple_widget_neutral">Nothing to show yet</string>
</resources>
```

```xml
<!-- android/app/src/main/res/values/couple_widget_colors.xml -->
<resources>
    <color name="couple_widget_bg">#FFFFFFFF</color>
    <color name="couple_widget_text_primary">#FF1D1D1F</color>
    <!-- 6.05:1 on the background (WCAG AA for small text). -->
    <color name="couple_widget_text_secondary">#FF5F6368</color>
</resources>
```

```xml
<!-- android/app/src/main/res/values-night/couple_widget_colors.xml -->
<resources>
    <color name="couple_widget_bg">#FF1C1C1E</color>
    <color name="couple_widget_text_primary">#FFF2F2F7</color>
    <!-- 8.09:1 on the background. -->
    <color name="couple_widget_text_secondary">#FFB0B3B8</color>
</resources>
```

```xml
<!-- android/app/src/main/res/drawable/couple_widget_bg.xml -->
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="@color/couple_widget_bg" />
    <corners android:radius="16dp" />
</shape>
```

```xml
<!-- android/app/src/main/res/drawable-v31/couple_widget_bg.xml -->
<!-- Android 12+: the launcher's own widget corner radius (spec §3.2). -->
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="@color/couple_widget_bg" />
    <corners android:radius="@android:dimen/system_app_widget_background_radius" />
</shape>
```

```xml
<!-- android/app/src/main/res/drawable/couple_widget_heart.xml -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24"
    android:tint="@color/couple_widget_text_secondary">
    <path android:fillColor="@android:color/white"
        android:pathData="M16.5,3c-1.74,0 -3.41,0.81 -4.5,2.09C10.91,3.81 9.24,3 7.5,3 4.42,3 2,5.42 2,8.5c0,3.78 3.4,6.86 8.55,11.54L12,21.35l1.45,-1.32C18.6,15.36 22,12.28 22,8.5 22,5.42 19.58,3 16.5,3zM12.1,18.55l-0.1,0.1 -0.1,-0.1C7.14,14.24 4,11.39 4,8.5 4,6.5 5.5,5 7.5,5c1.54,0 3.04,0.99 3.57,2.36h1.87C13.46,5.99 14.96,5 16.5,5c2,0 3.5,1.5 3.5,3.5 0,2.89 -3.14,5.74 -7.9,10.05z" />
</vector>
```

```xml
<!-- android/app/src/main/res/xml/couple_widget_info.xml -->
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="110dp"
    android:minHeight="110dp"
    android:minResizeWidth="110dp"
    android:minResizeHeight="110dp"
    android:targetCellWidth="2"
    android:targetCellHeight="2"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/couple_widget_small"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:description="@string/couple_widget_description" />
```

```xml
<!-- android/app/src/main/res/layout/couple_widget_small.xml -->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/couple_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center_vertical"
    android:padding="14dp"
    android:background="@drawable/couple_widget_bg">

    <!-- Visible until the first update: never a blank card. -->
    <LinearLayout
        android:id="@+id/couple_neutral"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical">
        <ImageView
            android:layout_width="18dp"
            android:layout_height="18dp"
            android:src="@drawable/couple_widget_heart"
            android:importantForAccessibility="no" />
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="6dp"
            android:text="@string/couple_widget_neutral"
            android:textSize="14sp"
            android:textColor="@color/couple_widget_text_secondary" />
    </LinearLayout>

    <!-- Fills the space left and shrinks to fit (autoSize, API 26+; spec
         §3.2), so large font scales shrink the headline, not cut it. -->
    <TextView
        android:id="@+id/couple_headline"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:gravity="bottom|start"
        android:maxLines="2"
        android:ellipsize="end"
        android:autoSizeTextType="uniform"
        android:autoSizeMinTextSize="12sp"
        android:autoSizeMaxTextSize="20sp"
        android:textStyle="bold"
        android:textColor="@color/couple_widget_text_primary"
        android:visibility="gone" />

    <TextClock
        android:id="@+id/couple_headline_clock"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:maxLines="1"
        android:format12Hour="h:mm a 'there'"
        android:format24Hour="HH:mm 'there'"
        android:textSize="18sp"
        android:textStyle="bold"
        android:textColor="@color/couple_widget_text_primary"
        android:visibility="gone" />

    <TextView
        android:id="@+id/couple_caption"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="2dp"
        android:maxLines="1"
        android:ellipsize="end"
        android:textSize="13sp"
        android:textColor="@color/couple_widget_text_secondary"
        android:visibility="gone" />

    <TextClock
        android:id="@+id/couple_clock_line"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:maxLines="1"
        android:format12Hour="h:mm a 'there'"
        android:format24Hour="HH:mm 'there'"
        android:textSize="13sp"
        android:textColor="@color/couple_widget_text_secondary"
        android:visibility="gone" />
</LinearLayout>
```

```xml
<!-- android/app/src/main/res/layout/couple_widget_medium.xml -->
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/couple_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="horizontal"
    android:gravity="center_vertical"
    android:padding="12dp"
    android:background="@drawable/couple_widget_bg">

    <!-- The region map (spec §3.3): decorative, never read aloud. -->
    <ImageView
        android:id="@+id/couple_map"
        android:layout_width="0dp"
        android:layout_height="match_parent"
        android:layout_weight="5"
        android:layout_marginEnd="12dp"
        android:scaleType="centerCrop"
        android:importantForAccessibility="no"
        android:visibility="gone" />

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="match_parent"
        android:layout_weight="6"
        android:gravity="center_vertical"
        android:orientation="vertical">

        <LinearLayout
            android:id="@+id/couple_neutral"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical">
            <ImageView
                android:layout_width="18dp"
                android:layout_height="18dp"
                android:src="@drawable/couple_widget_heart"
                android:importantForAccessibility="no" />
            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_marginStart="6dp"
                android:text="@string/couple_widget_neutral"
                android:textSize="14sp"
                android:textColor="@color/couple_widget_text_secondary" />
        </LinearLayout>

        <!-- Fills the space left and shrinks to fit (autoSize, API 26+; spec
             §3.2), so large font scales shrink the headline, not cut it. -->
        <TextView
            android:id="@+id/couple_headline"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:gravity="bottom|start"
            android:maxLines="2"
            android:ellipsize="end"
            android:autoSizeTextType="uniform"
            android:autoSizeMinTextSize="12sp"
            android:autoSizeMaxTextSize="20sp"
            android:textStyle="bold"
            android:textColor="@color/couple_widget_text_primary"
            android:visibility="gone" />

        <TextClock
            android:id="@+id/couple_headline_clock"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:maxLines="1"
            android:format12Hour="h:mm a 'there'"
            android:format24Hour="HH:mm 'there'"
            android:textSize="18sp"
            android:textStyle="bold"
            android:textColor="@color/couple_widget_text_primary"
            android:visibility="gone" />

        <TextView
            android:id="@+id/couple_caption"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="2dp"
            android:maxLines="1"
            android:ellipsize="end"
            android:textSize="13sp"
            android:textColor="@color/couple_widget_text_secondary"
            android:visibility="gone" />

        <TextClock
            android:id="@+id/couple_clock_line"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:maxLines="1"
            android:format12Hour="h:mm a 'there'"
            android:format24Hour="HH:mm 'there'"
            android:textSize="13sp"
            android:textColor="@color/couple_widget_text_secondary"
            android:visibility="gone" />
    </LinearLayout>
</LinearLayout>
```

- [ ] **Step 2: Write the provider**

```kotlin
// android/app/src/main/kotlin/com/barsopus/attune/CoupleWidgetProvider.kt
package com.barsopus.attune

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * The distance widget (widget spec §3, §6.3). Shows only what the app wrote;
 * never touches the network; no names, places or app words on the card. An
 * alarm at the next change (expiry or midnight) keeps it honest through Doze.
 */
class CoupleWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        render(context, appWidgetManager, appWidgetIds, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    override fun onDisabled(context: Context) {
        cancelExpiry(context)
        super.onDisabled(context)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
        data: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        val cal = Calendar.getInstance()
        val today = CoupleWidgetModel.epochDay(
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
        )
        val raw = data.getString(PAYLOAD_KEY, null)
        val view = CoupleWidgetModel.resolve(raw, now, today)
        val map = if (view.showMap) loadMap(context, data.getString(MAP_KEY, null)) else null
        ids.forEach { id -> manager.updateAppWidget(id, build(context, manager, id, view, map)) }
        val next = CoupleWidgetModel.nextChangeMs(raw, now, nextMidnight(cal))
        if (next == null) {
            cancelExpiry(context)
        } else {
            val all = manager.getAppWidgetIds(ComponentName(context, CoupleWidgetProvider::class.java))
            scheduleExpiry(context, all, next)
        }
    }

    private fun build(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        view: CoupleWidgetView,
        map: Bitmap?,
    ): RemoteViews {
        val small = bind(context, RemoteViews(context.packageName, R.layout.couple_widget_small), view, null, false)
        val medium = bind(context, RemoteViews(context.packageName, R.layout.couple_widget_medium), view, map, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(
                mapOf(
                    SizeF(110f, 110f) to small,
                    SizeF(MEDIUM_MIN_WIDTH_DP, 110f) to medium,
                ),
            )
        }
        val minWidth = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        return if (minWidth >= MEDIUM_MIN_WIDTH_DP) medium else small
    }

    private fun bind(
        context: Context,
        views: RemoteViews,
        view: CoupleWidgetView,
        map: Bitmap?,
        hasMapSlot: Boolean,
    ): RemoteViews = views.apply {
        setOnClickPendingIntent(
            R.id.couple_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(DEEP_LINK)),
        )
        setViewVisibility(R.id.couple_neutral, if (view.neutral) View.VISIBLE else View.GONE)
        showText(R.id.couple_headline, if (view.neutral) null else view.headline)
        setViewVisibility(R.id.couple_headline_clock, if (view.headlineIsClock) View.VISIBLE else View.GONE)
        showText(R.id.couple_caption, view.caption)
        setViewVisibility(R.id.couple_clock_line, if (view.clockLine) View.VISIBLE else View.GONE)
        view.clockOffsetMinutes?.let { offset ->
            val zone = CoupleWidgetModel.zoneId(offset)
            setString(R.id.couple_headline_clock, "setTimeZone", zone)
            setString(R.id.couple_clock_line, "setTimeZone", zone)
        }
        if (hasMapSlot) {
            if (map != null) {
                setImageViewBitmap(R.id.couple_map, map)
                setViewVisibility(R.id.couple_map, View.VISIBLE)
            } else {
                setViewVisibility(R.id.couple_map, View.GONE)
            }
        }
    }

    private fun RemoteViews.showText(id: Int, text: String?) {
        setViewVisibility(id, if (text == null) View.GONE else View.VISIBLE)
        if (text != null) setTextViewText(id, text)
    }

    /** Decoded small (≤ 480 px) from our own folder only; null on any problem. */
    private fun loadMap(context: Context, path: String?): Bitmap? = try {
        if (!CoupleWidgetModel.isWidgetFile(path, context.filesDir)) {
            null
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= MAP_MAX_PX) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        }
    } catch (_: Exception) {
        null
    }

    private fun nextMidnight(now: Calendar): Long = (now.clone() as Calendar).apply {
        add(Calendar.DAY_OF_MONTH, 1)
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun expiryIntent(context: Context, ids: IntArray?): PendingIntent {
        val intent = Intent(context, CoupleWidgetProvider::class.java)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
        if (ids != null) intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        return PendingIntent.getBroadcast(
            context,
            EXPIRY_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** RTC (not a wakeup): fires in Doze maintenance or when the phone wakes,
     * before the home screen is seen; no exact-alarm permission (spec §4.2). */
    private fun scheduleExpiry(context: Context, ids: IntArray, at: Long) {
        context.getSystemService(AlarmManager::class.java)
            ?.setAndAllowWhileIdle(AlarmManager.RTC, at, expiryIntent(context, ids))
    }

    private fun cancelExpiry(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(expiryIntent(context, null))
    }

    companion object {
        const val PAYLOAD_KEY = "couple_widget_v1"
        const val MAP_KEY = "couple_widget_map"
        const val DEEP_LINK = "attune://planning?tab=map"
        const val MEDIUM_MIN_WIDTH_DP = 250f
        const val MAP_MAX_PX = 480
        const val EXPIRY_REQUEST = 4201
    }
}
```

- [ ] **Step 3: Register the receiver (snapshot the manifest first)**

Insert directly after the existing `TogetherWidgetProvider` `</receiver>`:
```xml
        <!-- The distance widget (widget spec §6.3). -->
        <receiver
            android:name=".CoupleWidgetProvider"
            android:exported="true"
            android:label="@string/couple_widget_name">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/couple_widget_info" />
        </receiver>
```

- [ ] **Step 4: Build and lint the Android side**

Run: `flutter build apk --debug 2>&1 | tail -5`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

Run: `cd android && ./gradlew :app:lintDebug 2>&1 | grep -iE "CoupleWidget|couple_widget" | head`
Expected: no errors naming the new files. Ignore the command's exit code: lint also fails on unrelated, pre-existing issues and is slow. Warnings about API-level attributes (`autoSize*` on 24–25) are noted in the ledger, not fixed.

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.barsopus.attune.CoupleWidgetModelTest 2>&1 | tail -3`
Expected: still green.

- [ ] **Step 5: Privacy grep, then ledger**

Run: `grep -nE "Log\.|println|URL\(|OkHttp|supabase" android/app/src/main/kotlin/com/barsopus/attune/CoupleWidget*.kt`
Expected: no output.

In the ledger, record the manifest snapshot diff (only the receiver) and that the provider is verified by build + Kotlin tests + device checks. There's no emulator, as in Together Phase 8a.

---

### Task 4: Swift model + `swiftc` check (iOS)

**Files:**
- Create: `ios/TogetherWidget/CoupleWidgetModel.swift`
- Create: `ios/TogetherWidgetChecks/main.swift` (not added to any Xcode target)

**Interfaces:**
- Consumes: the Task 1 fixture.
- Produces:
  - `struct CoupleWidgetView: Equatable` (same fields as Kotlin);
  - `enum CoupleWidgetModel`:
    - `neutralHeadline`, `neutral`;
    - `resolve(_ raw: String?, nowMs: Double, today: Int) -> CoupleWidgetView`;
    - `nextChange(_ raw: String?, nowMs: Double, nextMidnightMs: Double) -> Double?`;
    - `epochDay(_ y: Int, _ m: Int, _ d: Int) -> Int`.

- [ ] **Step 1: Write the failing check**

```swift
// ios/TogetherWidgetChecks/main.swift
// Checks CoupleWidgetModel against the Dart vectors (widget spec §8). Not part
// of any Xcode target: run with
//   xcrun swiftc -o "$WS/swiftcheck" ios/TogetherWidget/CoupleWidgetModel.swift ios/TogetherWidgetChecks/main.swift
//   "$WS/swiftcheck" test/features/couple_map/widget/fixtures/couple_widget_vectors.json
import Foundation

let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fixture = try! JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
let nowMs = (fixture["nowMs"] as! NSNumber).doubleValue
let todayParts = (fixture["today"] as! String).split(separator: "-").map { Int($0)! }
let today = CoupleWidgetModel.epochDay(todayParts[0], todayParts[1], todayParts[2])

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
  if !ok {
    failures += 1
    print("FAIL \(name) \(detail)")
  }
}

check("neutral copy", fixture["neutralHeadline"] as? String == CoupleWidgetModel.neutralHeadline)
let vectors = fixture["vectors"] as! [[String: Any]]
check("vector count", vectors.count >= 20, "\(vectors.count)")
for v in vectors {
  let name = v["name"] as! String
  let e = v["expect"] as! [String: Any]
  let got = CoupleWidgetModel.resolve(v["payload"] as? String, nowMs: nowMs, today: today)
  check(name, got.headline == e["headline"] as? String, "headline \(String(describing: got.headline))")
  check(name, got.headlineIsClock == (e["headlineIsClock"] as! Bool), "headlineIsClock")
  check(name, got.caption == e["caption"] as? String, "caption \(String(describing: got.caption))")
  check(name, got.clockLine == (e["clockLine"] as! Bool), "clockLine")
  check(name, got.clockOffsetMinutes == (e["clockOffsetMinutes"] as? NSNumber)?.intValue, "offset")
  check(name, got.neutral == (e["neutral"] as! Bool), "neutral")
  check(name, got.showMap == (e["showMap"] as! Bool), "showMap")
}

check("epoch 1970", CoupleWidgetModel.epochDay(1970, 1, 1) == 0)
check("epoch 2026-10-16", CoupleWidgetModel.epochDay(2026, 10, 16) == 20742)
check("epoch leap day", CoupleWidgetModel.epochDay(2024, 2, 29) == 19782)

let both = "{\"v\":1,\"validUntilMs\":5000,\"reunionDate\":\"2026-10-28\"}"
check("next: expiry first", CoupleWidgetModel.nextChange(both, nowMs: 1000, nextMidnightMs: 9000) == 5000)
let late = "{\"v\":1,\"validUntilMs\":9000,\"reunionDate\":\"2026-10-28\"}"
check("next: midnight first", CoupleWidgetModel.nextChange(late, nowMs: 1000, nextMidnightMs: 5000) == 5000)
check("next: nothing", CoupleWidgetModel.nextChange("{\"v\":1}", nowMs: 1000, nextMidnightMs: 5000) == nil)
check("next: past expiry", CoupleWidgetModel.nextChange("{\"v\":1,\"validUntilMs\":500}", nowMs: 1000, nextMidnightMs: 5000) == nil)
check("next: malformed", CoupleWidgetModel.nextChange("{", nowMs: 1000, nextMidnightMs: 5000) == nil)

if failures > 0 {
  print("\(failures) failure(s)")
  exit(1)
}
print("all swift widget checks passed")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcrun swiftc -o "$WS/swiftcheck" ios/TogetherWidget/CoupleWidgetModel.swift ios/TogetherWidgetChecks/main.swift 2>&1 | tail -3`
Expected: FAIL, with "no such file" for `CoupleWidgetModel.swift`.

- [ ] **Step 3: Write the model**

```swift
// ios/TogetherWidget/CoupleWidgetModel.swift
// The distance widget's view model (widget spec §3.1, §6.2). Mirrors Dart's
// resolveCoupleWidget; the live clock is SwiftUI's own, so only its offset and
// slot are returned. Foundation only: checked with swiftc against the vectors.
import Foundation

struct CoupleWidgetView: Equatable {
  let headline: String?
  let headlineIsClock: Bool
  let caption: String?
  let clockLine: Bool
  let clockOffsetMinutes: Int?
  let neutral: Bool
  let showMap: Bool
}

enum CoupleWidgetModel {
  static let neutralHeadline = "Nothing to show yet"
  static let neutral = CoupleWidgetView(
    headline: neutralHeadline, headlineIsClock: false, caption: nil,
    clockLine: false, clockOffsetMinutes: nil, neutral: true, showMap: false)

  private struct Payload: Decodable {
    let v: Int
    let headline: String?
    let headlineIsClock: Bool?
    let caption: String?
    let clockOffsetMinutes: Int?
    let clockLine: Bool?
    let validUntilMs: Double?
    let reunionDate: String?
  }

  private static func parse(_ raw: String?) -> Payload? {
    guard let data = raw?.data(using: .utf8),
          let payload = try? JSONDecoder().decode(Payload.self, from: data),
          payload.v == 1
    else { return nil }
    return payload
  }

  /// Days since 1970-01-01 for a civil date (Hinnant), calendar-free.
  static func epochDay(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (month + 9) % 12
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
  }

  private static func epochDay(_ date: String) -> Int? {
    let parts = date.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
    else { return nil }
    return epochDay(y, m, d)
  }

  private static func countdown(_ days: Int) -> String {
    switch days {
    case 0: return "Together today"
    case 1: return "Together tomorrow"
    default: return "\(days) days until you're together"
    }
  }

  static func resolve(_ raw: String?, nowMs: Double, today: Int) -> CoupleWidgetView {
    guard let p = parse(raw) else { return neutral }
    let live = p.validUntilMs.map { $0 > nowMs } ?? false
    var days: Int?
    if let date = p.reunionDate, let day = epochDay(date), day - today >= 0 {
      days = day - today
    }
    let off = p.clockOffsetMinutes
    let clockLine = (p.clockLine ?? false) && off != nil
    if live {
      if let days = days {
        return CoupleWidgetView(
          headline: countdown(days), headlineIsClock: false, caption: p.caption,
          clockLine: clockLine, clockOffsetMinutes: clockLine ? off : nil,
          neutral: false, showMap: true)
      }
      if p.headlineIsClock == true, let off = off {
        return CoupleWidgetView(
          headline: nil, headlineIsClock: true, caption: p.caption,
          clockLine: false, clockOffsetMinutes: off, neutral: false, showMap: true)
      }
      if let headline = p.headline {
        return CoupleWidgetView(
          headline: headline, headlineIsClock: false, caption: p.caption,
          clockLine: clockLine, clockOffsetMinutes: clockLine ? off : nil,
          neutral: false, showMap: true)
      }
    }
    if let days = days {
      return days <= 1
        ? CoupleWidgetView(
          headline: countdown(days), headlineIsClock: false, caption: nil,
          clockLine: false, clockOffsetMinutes: nil, neutral: false, showMap: false)
        : CoupleWidgetView(
          headline: "\(days) days", headlineIsClock: false,
          caption: "until you're together", clockLine: false,
          clockOffsetMinutes: nil, neutral: false, showMap: false)
    }
    return neutral
  }

  /// When the view next changes by itself: the distance expiring, or local
  /// midnight while a reunion counts down (spec §4.2).
  static func nextChange(_ raw: String?, nowMs: Double, nextMidnightMs: Double) -> Double? {
    guard let p = parse(raw) else { return nil }
    var candidates: [Double] = []
    if let until = p.validUntilMs, until > nowMs { candidates.append(until) }
    if p.reunionDate != nil { candidates.append(nextMidnightMs) }
    return candidates.min()
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `xcrun swiftc -o "$WS/swiftcheck" ios/TogetherWidget/CoupleWidgetModel.swift ios/TogetherWidgetChecks/main.swift && "$WS/swiftcheck" test/features/couple_map/widget/fixtures/couple_widget_vectors.json`
Expected: `all swift widget checks passed`, exit 0.

- [ ] **Step 5: Ledger**

---

### Task 5: iOS widget views, bundle entry and Xcode target

**Files:**
- Create: `ios/TogetherWidget/CoupleWidget.swift`
- Modify: `ios/TogetherWidget/TogetherWidget.swift` (add `CoupleWidget()` to `TogetherWidgets`)
- Modify (via script): `ios/Runner.xcodeproj/project.pbxproj`
- Create (scratchpad): `add_couple_widget.rb`

**Interfaces:**
- Consumes: `CoupleWidgetModel`, `CoupleWidgetView` (Task 4).
- Produces: widget kind `CoupleWidget`. This is what W1's `HomeWidget.updateWidget(iOSName: 'CoupleWidget')` reloads.

- [ ] **Step 1: Write the widget**

```swift
// ios/TogetherWidget/CoupleWidget.swift
// The distance widget (widget spec §3, §6.2). Shows only what the app wrote to
// the App Group; never touches the network; no names, places or app words.
import SwiftUI
import UIKit
import WidgetKit

private let coupleAppGroup = "group.com.barsopus.attune"
private let couplePayloadKey = "couple_widget_v1"
private let coupleMapKey = "couple_widget_map"
private let coupleLink = URL(string: "attune://planning?tab=map")!

struct CoupleEntry: TimelineEntry {
  let date: Date
  let view: CoupleWidgetView
  let map: UIImage?
}

private func dayNumber(_ date: Date) -> Int {
  let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
  return CoupleWidgetModel.epochDay(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
}

private func loadRaw() -> String? {
  UserDefaults(suiteName: coupleAppGroup)?.string(forKey: couplePayloadKey)
}

/// The image by file name inside our own container; a stored absolute path
/// is never trusted (it changes with a reinstall; spec §4.4).
private func loadMap() -> UIImage? {
  guard let stored = UserDefaults(suiteName: coupleAppGroup)?.string(forKey: coupleMapKey),
        let container = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: coupleAppGroup)
  else { return nil }
  let name = (stored as NSString).lastPathComponent
  let url = container.appendingPathComponent("home_widget").appendingPathComponent(name)
  return UIImage(contentsOfFile: url.path)
}

private func makeEntry(at date: Date, raw: String?, map: UIImage?) -> CoupleEntry {
  let view = CoupleWidgetModel.resolve(
    raw, nowMs: date.timeIntervalSince1970 * 1000, today: dayNumber(date))
  return CoupleEntry(date: date, view: view, map: view.showMap ? map : nil)
}

/// The gallery and placeholders show sample lines, never the real ones: the
/// gallery is often seen over someone's shoulder (spec §3.2).
private let sampleEntry = CoupleEntry(
  date: Date(),
  view: CoupleWidgetView(
    headline: "Together tomorrow", headlineIsClock: false, caption: "5.1k km apart",
    clockLine: false, clockOffsetMinutes: nil, neutral: false, showMap: false),
  map: nil)

struct CoupleProvider: TimelineProvider {
  func placeholder(in context: Context) -> CoupleEntry { sampleEntry }

  func getSnapshot(in context: Context, completion: @escaping (CoupleEntry) -> Void) {
    if context.isPreview {
      completion(sampleEntry)
      return
    }
    completion(makeEntry(at: Date(), raw: loadRaw(), map: loadMap()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CoupleEntry>) -> Void) {
    let now = Date()
    let raw = loadRaw()
    let map = loadMap()
    // Calendar arithmetic, not +24 h: the fall-back day is 25 hours long.
    let midnight = Calendar.current.date(
      byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
      ?? now.addingTimeInterval(86_400)
    let nextMs = CoupleWidgetModel.nextChange(
      raw, nowMs: now.timeIntervalSince1970 * 1000,
      nextMidnightMs: midnight.timeIntervalSince1970 * 1000)
    let next = nextMs.map { Date(timeIntervalSince1970: $0 / 1000) }
    let first = makeEntry(at: now, raw: raw, map: map)
    // Text(date, style: .time) is a fixed time, not a ticking clock: while a
    // clock shows, one entry per minute for the next hour, then reload
    // (spec §3.1). Otherwise only the change points (expiry, midnight).
    var dates: [Date] = []
    let policy: TimelineReloadPolicy
    if first.view.headlineIsClock || first.view.clockLine {
      let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
      let horizon = minute.addingTimeInterval(3_600)
      for i in 1...60 { dates.append(minute.addingTimeInterval(Double(i) * 60)) }
      if let next = next, next < horizon { dates.append(next) }
      policy = .after(horizon)
    } else if let next = next {
      dates.append(next)
      policy = .after(next)
    } else {
      policy = .never
    }
    let later = Array(Set(dates.filter { $0 > now })).sorted()
    completion(Timeline(entries: [first] + later.map { makeEntry(at: $0, raw: raw, map: map) }, policy: policy))
  }
}

/// The partner's wall time as fixed text: the entry's instant moved by the
/// gap between their offset and this phone's, so the phone's own formatter
/// (12/24 h, locale) prints their time. No reliance on the environment's
/// time zone (spec §3.1; Review Focus 4).
private struct ClockText: View {
  let date: Date
  let offsetMinutes: Int

  var body: some View {
    let shift = TimeInterval(offsetMinutes * 60 - TimeZone.current.secondsFromGMT(for: date))
    return Text(date.addingTimeInterval(shift), style: .time) + Text(" there")
  }
}

private struct CoupleLines: View {
  let entry: CoupleEntry

  var body: some View {
    let v = entry.view
    VStack(alignment: .leading, spacing: 4) {
      if v.neutral {
        HStack(spacing: 6) {
          Image(systemName: "heart").foregroundColor(.secondary)
          Text(CoupleWidgetModel.neutralHeadline)
            .font(.subheadline).foregroundColor(.secondary).lineLimit(2)
        }
      } else {
        if v.headlineIsClock, let off = v.clockOffsetMinutes {
          ClockText(date: entry.date, offsetMinutes: off)
            .font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
        } else if let headline = v.headline {
          Text(headline)
            .font(.title3.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.6)
        }
        if let caption = v.caption {
          Text(caption).font(.caption).foregroundColor(.secondary).lineLimit(1)
        }
        if v.clockLine, let off = v.clockOffsetMinutes {
          ClockText(date: entry.date, offsetMinutes: off)
            .font(.caption).foregroundColor(.secondary).lineLimit(1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    // One spoken sentence, the live time included (spec §6.2).
    .accessibilityElement(children: .combine)
    .modifier(CouplePrivacy())
  }
}

private struct MapSlot: View {
  let image: UIImage

  var body: some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFill()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .accessibilityHidden(true)
  }
}

/// Tinted and clear home screens (iOS 18) would flatten the image to a slab:
/// there, the text layout only (spec §3.2).
private struct FullColorOnly<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    if #available(iOSApplicationExtension 16.0, *) {
      FullColorGate(content: content)
    } else {
      content()
    }
  }
}

@available(iOSApplicationExtension 16.0, *)
private struct FullColorGate<Content: View>: View {
  @Environment(\.widgetRenderingMode) private var mode
  let content: () -> Content

  var body: some View {
    if mode == .fullColor { content() }
  }
}

struct CoupleWidgetContent: View {
  @Environment(\.widgetFamily) private var family
  let entry: CoupleEntry

  var body: some View {
    Group {
      if family == .systemMedium, let map = entry.map {
        HStack(spacing: 12) {
          FullColorOnly { MapSlot(image: map).frame(width: 130) }
          CoupleLines(entry: entry)
        }
      } else {
        CoupleLines(entry: entry)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .widgetURL(coupleLink)
    .modifier(CoupleBackground())
  }
}

/// Best effort only: iOS redacts this on a locked phone just when the user
/// turned off widget access while locked (spec §4.5).
private struct CouplePrivacy: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 15.0, *) {
      content.privacySensitive()
    } else {
      content
    }
  }
}

private struct CoupleBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(.fill.tertiary, for: .widget)
    } else {
      content.padding()
    }
  }
}

struct CoupleWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CoupleWidget", provider: CoupleProvider()) { entry in
      CoupleWidgetContent(entry: entry)
    }
    .configurationDisplayName("Apart")
    .description("Time and distance between you two. Turn it on in Attune first.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
```

- [ ] **Step 2: Add it to the bundle (snapshot `TogetherWidget.swift` first)**

In `ios/TogetherWidget/TogetherWidget.swift`, inside `struct TogetherWidgets`, add one line after `TogetherWidget()`:
```swift
    CoupleWidget()
```

- [ ] **Step 3: Add both files to the TogetherWidget target (snapshot `project.pbxproj` first)**

```ruby
# scratchpad/add_couple_widget.rb
# Adds the distance widget's two Swift files to the TogetherWidget target
# (same pattern as Together Phase 8c's add_live_activity.rb).
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
widget = project.targets.find { |t| t.name == 'TogetherWidget' } or abort('no TogetherWidget target')
group = project.main_group['TogetherWidget'] or abort('no TogetherWidget group')
abort('already added') if group.files.any? { |f| f.path == 'CoupleWidget.swift' }
refs = %w[CoupleWidgetModel.swift CoupleWidget.swift].map { |name| group.new_reference(name) }
widget.add_file_references(refs)
project.save
puts 'added CoupleWidgetModel.swift and CoupleWidget.swift to TogetherWidget'
```
Run: `GEM_HOME=/opt/homebrew/lib/ruby/gems/3.4.0 ruby "$SCRATCH/add_couple_widget.rb"`
Then: `diff -u "$WS/snapshots/project.pbxproj" ios/Runner.xcodeproj/project.pbxproj | grep -E "^[+-][^+-]"`
Expected: only new PBXBuildFile, PBXFileReference, group-children and Sources entries for the two files. Nothing removed apart from re-serialisation of the changed lists.

- [ ] **Step 4: Build iOS**

Run: `flutter build ios --debug --no-codesign 2>&1 | tail -5`
Expected: `✓ Built build/ios/iphoneos/Runner.app`.

If the Swift compiler rejects an API at the extension's 14.0 deployment target, fix it with an `#available` guard. Ledger each guard as a ruling.

Then a simulator check of the clock (Review Focus 4):
1. Run the app on an iOS simulator (`flutter run -d <simulator>`), opt in, and add the widget.
2. Write a test payload into the App Group from a debug Dart console:
   `HomeWidget.saveWidgetData('couple_widget_v1', '{"v":1,"headlineIsClock":true,"caption":"5.1k km apart","clockOffsetMinutes":330,"validUntilMs":<now+3600000>}')`, then `updateWidget`.
3. Confirm the headline equals UTC + 5:30, not the simulator's clock, and ticks each minute.

Record the result in the ledger. If no simulator is available, ledger it as a device check for the owner.

- [ ] **Step 5: Re-run the swift check and the privacy grep, then ledger**

Run the Task 4 check again (still green). Then:
`grep -nE "URLSession|NSLog|os_log|print\(" ios/TogetherWidget/CoupleWidget*.swift`
Expected: no output.

---

### Task 6: Planning opens on a requested tab

**Files:**
- Modify: `lib/home/widgets/tabs_with_content.dart` (`didUpdateWidget`: re-notify `onControllerCreated`)
- Modify: `lib/features/planning/presentation/screens/planning_home_screen.dart`:
  - `PlanningHomeTab`, `planningTabFromQuery`;
  - `initialTab`;
  - `planningMapTabBuilderProvider`;
  - jumping on the controller.
- Modify: `lib/app/routing/app_router.dart` (`/planning` builder reads `?tab=`)
- Test: `test/home/tabs_with_content_controller_test.dart` (new); additions to `test/features/planning/planning_home_screen_test.dart`

**Interfaces:**
- Produces:
  - `enum PlanningHomeTab { planning, calendar, map }`
  - `PlanningHomeTab planningTabFromQuery(String? value)` (unknown or null → `planning`)
  - `PlanningHomeScreen({required String relationshipId, PlanningHomeTab initialTab = PlanningHomeTab.planning})`
  - `final planningMapTabBuilderProvider = Provider<Widget Function(String relationshipId)>`

- [ ] **Step 1: Write the failing tests**

```dart
// test/home/tabs_with_content_controller_test.dart
import 'package:attune/core/widgets/app_tabs.dart';
import 'package:attune/home/widgets/tabs_with_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(int count, void Function(TabController) onController) =>
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, __) => MaterialApp(
            home: Scaffold(
              body: TabsWithContent(
                tabs: [
                  for (var i = 0; i < count; i++)
                    AppTabItem(label: 'Tab $i', content: Text('Page $i')),
                ],
                initialIndex: 0,
                showContent: true,
                onControllerCreated: onController,
              ),
            ),
          ),
    );

void main() {
  testWidgets('a rebuilt controller (tab count changed) is handed over too', (
    t,
  ) async {
    final got = <TabController>[];
    await t.pumpWidget(_app(2, got.add));
    await t.pump();
    await t.pumpWidget(_app(3, got.add));
    await t.pump();
    expect(got, hasLength(2));
    expect(got.last.length, 3);
    // The new one works: moving it shows the third page.
    got.last.index = 2;
    await t.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
  });
}
```

Additions to `test/features/planning/planning_home_screen_test.dart`. Add the imports `package:flutter_riverpod/flutter_riverpod.dart` (if not already present) and `planning_home_screen.dart`'s new names (same import). Then:
```dart
  testWidgets('opened from the distance widget, Planning lands on Map once the flag loads', (tester) async {
    await tester.pumpWidget(planningTestApp(
      _gateway(),
      ProviderScope(
        overrides: [
          planningMapTabBuilderProvider.overrideWithValue((rel) => Text('map for $rel')),
        ],
        child: const PlanningHomeScreen(relationshipId: 'r1', initialTab: PlanningHomeTab.map),
      ),
      mapEnabled: true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('map for r1'), findsOneWidget);
  });

  testWidgets('asked for Map with the flag off, Planning stays on its first tab', (tester) async {
    await tester.pumpWidget(planningTestApp(
      _gateway(),
      const PlanningHomeScreen(relationshipId: 'r1', initialTab: PlanningHomeTab.map),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget);
  });

  test('the ?tab= query maps to a tab; anything else is Planning', () {
    expect(planningTabFromQuery('map'), PlanningHomeTab.map);
    expect(planningTabFromQuery('calendar'), PlanningHomeTab.calendar);
    expect(planningTabFromQuery('planning'), PlanningHomeTab.planning);
    expect(planningTabFromQuery('bogus'), PlanningHomeTab.planning);
    expect(planningTabFromQuery(null), PlanningHomeTab.planning);
  });

  test('the /planning route passes ?tab= through', () {
    final source = File('lib/app/routing/app_router.dart').readAsStringSync();
    expect(source.contains("planningTabFromQuery(state.uri.queryParameters['tab'])"), isTrue);
  });
```
(Add `import 'dart:io';` for the last test if it isn't there.)

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/home/tabs_with_content_controller_test.dart test/features/planning/planning_home_screen_test.dart`
Expected:
- the controller test FAILS (`got` has length 1);
- the planning file fails to compile ("Undefined name 'planningMapTabBuilderProvider'" / "'PlanningHomeTab'").

- [ ] **Step 3: Re-notify in `TabsWithContent` (snapshot first; re-read the file)**

In `didUpdateWidget`, inside the `if (oldWidget.tabs.length != widget.tabs.length) { … }` block, after `_tabController.addListener(_onTabControllerChanged);`, add:
```dart
      // Hand over the new controller too: the old one was just disposed, and
      // Planning uses it to open on a tab that appears late (widget §6.5).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onControllerCreated?.call(_tabController);
      });
```

- [ ] **Step 4: Edit `PlanningHomeScreen` (snapshot first; re-read the file)**

Add above the widget class:
```dart
/// Planning's tabs, in order (the Map tab exists only with the flag on).
enum PlanningHomeTab { planning, calendar, map }

/// `?tab=` from a link: anything unknown opens Planning's first tab.
PlanningHomeTab planningTabFromQuery(String? value) =>
    PlanningHomeTab.values.asNameMap()[value] ?? PlanningHomeTab.planning;

/// Builds the Map tab's content (a seam: tests swap the Mapbox view out).
final planningMapTabBuilderProvider =
    Provider<Widget Function(String relationshipId)>(
      (ref) => (relationshipId) => CoupleMapTab(relationshipId: relationshipId),
    );
```
Change the constructor and field:
```dart
  const PlanningHomeScreen({
    super.key,
    required this.relationshipId,
    this.initialTab = PlanningHomeTab.planning,
  });
  final String relationshipId;

  /// Where to open: the distance widget opens Map (widget spec §6.5).
  final PlanningHomeTab initialTab;
```
In the State class, add:
```dart
  bool _openedInitialTab = false;

  /// The Map tab appears once the flag loads, so the jump waits for a
  /// controller that has it (TabsWithContent hands over each new one).
  void _openInitialTab(TabController controller) {
    if (_openedInitialTab) return;
    final index = widget.initialTab.index;
    if (index == 0) {
      _openedInitialTab = true;
      return;
    }
    if (index < controller.length) {
      controller.index = index;
      _openedInitialTab = true;
    }
  }
```
In `build`, change the Map tab's content from `CoupleMapTab(relationshipId: widget.relationshipId)` to:
```dart
          content: ref.watch(planningMapTabBuilderProvider)(widget.relationshipId),
```
Then add `onControllerCreated: _openInitialTab,` to the `TabsWithContent(...)` arguments, next to `initialIndex: 0,`.

Confirm the class is a `ConsumerStatefulWidget` (it watches `coupleMapEnabledProvider`), so `ref` exists in `build`.

- [ ] **Step 5: Pass `?tab=` in the router (snapshot first; re-read the block)**

In `lib/app/routing/app_router.dart`, change the `/planning` builder's return:
```dart
      return PlanningHomeScreen(
        relationshipId: relationshipId,
        // The distance widget's link asks for Map (widget spec §6.5).
        initialTab: planningTabFromQuery(state.uri.queryParameters['tab']),
      );
```
`planningTabFromQuery` comes from the same `planning_home_screen.dart` import the router already uses for `PlanningHomeScreen`. If that import has a `show` clause, add the name to it.

- [ ] **Step 6: Run the tests and the shared-widget regression gate**

Run: `flutter test test/home/ test/features/planning/ test/login_profile_test.dart`
Expected: all pass. `test/login_profile_test.dart` covers the login screen, the other `onControllerCreated` user.

- [ ] **Step 7: Snapshot-diff the three shared files, format only the new test, analyze, ledger**

Risk notes:
- `TabsWithContent`: low. A second callback fires only when the tab count changes; login stores the latest controller, which is now the live one rather than a disposed one.
- Planning: low. The default tab is unchanged.

---

### Task 7: The deep link

**Files:**
- Create: `lib/features/couple_map/widget/presentation/widget_deep_link.dart`
- Modify: `lib/main.dart` (one branch in `_handleDeepLink` + `_openPlanningWhenReady`)
- Test: `test/features/couple_map/widget/widget_deep_link_test.dart`

**Interfaces:**
- Consumes: `PlanningHomeTab`, `planningTabFromQuery` (Task 6); `RouteNames` (`lib/app/routing/app_router.dart`); `waitForRouterSettled()` (app_router.dart); `currentRelationshipIdProvider` (`lib/features/planning/presentation/planning_providers.dart`); `coupleMapEnabledProvider`.
- Produces:
  - `const coupleWidgetLink = 'attune://planning?tab=map'`
  - `PlanningHomeTab? planningTabFromLink(Uri uri)`
  - `Future<bool> openPlanningFromLink(GoRouter router, PlanningHomeTab tab, {required bool Function() signedIn, required Future<String?> Function() relationshipId, required Future<bool> Function() mapEnabled})`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/widget/widget_deep_link_test.dart
import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/couple_map/widget/presentation/widget_deep_link.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart'
    show PlanningHomeTab;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<GoRouter> pump(WidgetTester t, {String initial = '/'}) async {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Text('home')),
      GoRoute(
        path: RouteNames.neutralScreen,
        builder: (_, __) => const Text('neutral'),
      ),
      GoRoute(
        path: RouteNames.planning,
        builder:
            (_, s) => Text('planning ${s.extra} ${s.uri.queryParameters['tab']}'),
      ),
    ],
  );
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
  await t.pumpAndSettle();
  return router;
}

Future<bool> open(
  GoRouter r, {
  bool signedIn = true,
  Future<String?> Function()? rel,
  bool flag = true,
}) => openPlanningFromLink(
  r,
  PlanningHomeTab.map,
  signedIn: () => signedIn,
  relationshipId: rel ?? () async => 'r1',
  mapEnabled: () async => flag,
);

void main() {
  test('reads only attune://planning links', () {
    expect(planningTabFromLink(Uri.parse(coupleWidgetLink)), PlanningHomeTab.map);
    expect(planningTabFromLink(Uri.parse('attune://planning')), PlanningHomeTab.planning);
    expect(planningTabFromLink(Uri.parse('attune://planning?tab=bogus')), PlanningHomeTab.planning);
    expect(planningTabFromLink(Uri.parse('attune://invite?code=abc')), isNull);
    expect(planningTabFromLink(Uri.parse('https://planning?tab=map')), isNull);
    expect(planningTabFromLink(Uri.parse('attune://auth/callback')), isNull);
  });

  test('the link carries no ids and no homeWidget item (spec §6.5)', () {
    final uri = Uri.parse(coupleWidgetLink);
    expect(uri.queryParameters.keys, ['tab']);
  });

  testWidgets('a signed-in, paired person lands on Planning → Map', (t) async {
    final r = await pump(t);
    expect(await open(r), isTrue);
    await t.pumpAndSettle();
    expect(find.text('planning r1 map'), findsOneWidget);
  });

  testWidgets('never over quick exit\'s neutral screen (Review Focus 3)', (t) async {
    final r = await pump(t, initial: RouteNames.neutralScreen);
    expect(await open(r), isFalse);
    await t.pumpAndSettle();
    expect(find.text('neutral'), findsOneWidget);
  });

  testWidgets('quick exit during the lookup still wins', (t) async {
    final r = await pump(t);
    final gate = Completer<String?>();
    final pending = open(r, rel: () => gate.future);
    r.go(RouteNames.neutralScreen);
    await t.pumpAndSettle();
    gate.complete('r1');
    expect(await pending, isFalse);
    await t.pumpAndSettle();
    expect(find.text('neutral'), findsOneWidget);
  });

  testWidgets('signed out, unpaired, a failing lookup, or the flag off: nothing', (t) async {
    final r = await pump(t);
    expect(await open(r, signedIn: false), isFalse);
    expect(await open(r, rel: () async => null), isFalse);
    expect(await open(r, rel: () async => throw Exception('offline')), isFalse);
    expect(await open(r, flag: false), isFalse);
    await t.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the same link twice at once (cold start) pushes once', (t) async {
    final r = await pump(t);
    final gate = Completer<String?>();
    final first = open(r, rel: () => gate.future);
    final second = open(r);
    gate.complete('r1');
    expect(await first, isTrue);
    expect(await second, isFalse);
    await t.pumpAndSettle();
    expect(
      r.routerDelegate.currentConfiguration.matches
          .where((m) => m.matchedLocation == RouteNames.planning)
          .length,
      1,
    );
  });

  testWidgets('already on Planning: no second copy pushed', (t) async {
    final r = await pump(t, initial: RouteNames.planning);
    expect(await open(r), isFalse);
  });

  test('main.dart routes planning links before invites', () {
    final source = File('lib/main.dart').readAsStringSync();
    final handler = source.substring(source.indexOf('void _handleDeepLink'));
    expect(handler.indexOf('planningTabFromLink(uri)'), greaterThan(-1));
    expect(
      handler.indexOf('planningTabFromLink(uri)'),
      lessThan(handler.indexOf('_extractInviteCode(uri)')),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/couple_map/widget/widget_deep_link_test.dart`
Expected: FAIL to compile (`widget_deep_link.dart` doesn't exist).

- [ ] **Step 3: Write the link helpers**

```dart
// lib/features/couple_map/widget/presentation/widget_deep_link.dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart'
    show PlanningHomeTab, planningTabFromQuery;
import 'package:go_router/go_router.dart';

/// The distance widget's tap (widget spec §6.5). No ids: the app resolves
/// the couple itself. No `homeWidget` item: home_widget's iOS app-delegate
/// hook would claim it; app_links alone delivers this one.
const coupleWidgetLink = 'attune://planning?tab=map';

/// The Planning tab a link asks for, or null if it isn't a Planning link.
PlanningHomeTab? planningTabFromLink(Uri uri) {
  if (uri.scheme != 'attune' || uri.host != 'planning') return null;
  return planningTabFromQuery(uri.queryParameters['tab']);
}

/// Opens Planning on [tab] for a signed-in, paired person. Never over quick
/// exit's neutral screen (checked again after every await), never a second
/// copy, never with the flag off. True when it navigated.
Future<bool> openPlanningFromLink(
  GoRouter router,
  PlanningHomeTab tab, {
  required bool Function() signedIn,
  required Future<String?> Function() relationshipId,
  required Future<bool> Function() mapEnabled,
}) async {
  // app_links delivers a cold-start link twice (getInitialLink and the
  // stream): one open at a time.
  if (_opening) return false;
  _opening = true;
  try {
    return await _open(router, tab, signedIn, relationshipId, mapEnabled);
  } finally {
    _opening = false;
  }
}

bool _opening = false;

Future<bool> _open(
  GoRouter router,
  PlanningHomeTab tab,
  bool Function() signedIn,
  Future<String?> Function() relationshipId,
  Future<bool> Function() mapEnabled,
) async {
  String path() => router.routerDelegate.currentConfiguration.uri.path;
  bool blocked() =>
      !signedIn() ||
      path() == RouteNames.neutralScreen ||
      path() == RouteNames.planning;
  if (blocked()) return false;
  final String? rel;
  final bool flag;
  try {
    rel = await relationshipId();
    flag = await mapEnabled();
  } catch (_) {
    return false;
  }
  if (rel == null || !flag || blocked()) return false;
  router.push('${RouteNames.planning}?tab=${tab.name}', extra: rel);
  return true;
}
```

- [ ] **Step 4: Wire it in `main.dart` (snapshot first; re-read `_handleDeepLink`)**

Add the imports:
```dart
import 'package:attune/features/couple_map/widget/presentation/widget_deep_link.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart'
    show coupleMapEnabledProvider;
import 'package:attune/features/planning/presentation/planning_providers.dart'
    as planning show currentRelationshipIdProvider;
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart'
    show PlanningHomeTab;
```
In `_handleDeepLink`, after the auth-callback `return;` block and before `final inviteCode = …`:
```dart
  final planningTab = planningTabFromLink(uri);
  if (planningTab != null) {
    debugPrint('[deep-link] planning link detected.');
    unawaited(_openPlanningWhenReady(planningTab));
    return;
  }
```
Add after `_navigateToOnboardingWhenReady`:
```dart
/// The distance widget's tap (widget spec §6.5): Planning → Map, once the
/// router has settled, for a signed-in, paired person only.
Future<void> _openPlanningWhenReady(PlanningHomeTab tab) async {
  try {
    final context = await waitForRouterSettled();
    if (context == null || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await openPlanningFromLink(
      GoRouter.of(context),
      tab,
      signedIn: () => Supabase.instance.client.auth.currentUser != null,
      // Fresh, not cached: after a sign-out the cached id is the last account's.
      relationshipId:
          () => container.refresh(planning.currentRelationshipIdProvider.future),
      mapEnabled: () => container.read(coupleMapEnabledProvider.future),
    );
  } catch (error) {
    // Quiet, like the auth callback: a link must never crash the app.
    debugPrint('[deep-link] planning link failed: ${error.runtimeType}');
  }
}
```

- [ ] **Step 5: Run the tests and verify they pass**

Run: `flutter test test/features/couple_map/widget/widget_deep_link_test.dart`
Expected: all pass. Then snapshot-diff `lib/main.dart`: only the four imports, the branch and the helper. Format the two new files only; run the analyzer on them and on `lib/main.dart`.

- [ ] **Step 6: Ledger**

`main.dart` risk: low. The new branch only matches `attune://planning…`; auth callbacks and invites are untouched and checked first or after.

---

### Task 8: Spec amendments, evidence, builds, full suite, final review

**Files:**
- Modify: `docs/superpowers/specs/2026-10-16-couple-distance-widget-design.md` (§6.3, §6.5, §7, status)
- Modify: the W2 ledger

- [ ] **Step 1: Amend the spec**

**§6.5 "The URL":** replace with `attune://planning?tab=map`. No relationship id is ever in it. There's no `homeWidget` item either: home_widget's iOS app-delegate hook would claim such a URL. app_links alone delivers it on both platforms; on Android, the plugin's launch intent carries it as data.

**§6.5:** add a line: "with the flag off, the tap opens the app without navigating."

**§6.3, accessibility line:** Android has no combined description on the root, because a live `TextClock` can't sit inside a static description. TalkBack reads the lines in order, and the map image is `importantForAccessibility="no"`. iOS combines the lines with `.accessibilityElement(children: .combine)`, live time included.

**§3.2, the drop order line:** replace it with: "the headline shrinks to fit (Android autoSize, iOS `minimumScaleFactor`); when the card is still too short, the bottom line (the clock line) is cut first, then the caption". Vertical layouts clip from the bottom on both platforms.

**§3.1, the clock:** add "iOS draws the clock as per-minute timeline entries (WidgetKit has no live wall-clock text); Android uses a live `TextClock`."

**Owner decisions:** these amendments are the executor's rulings, made because the binding spec could not be built as written. Flag each one in the final message as an owner decision:
- the §6.5 URL without `homeWidget`;
- Android with no combined description;
- the drop order;
- the iOS clock.

**§7:** mark the W2 row "(built)". Extend the status line with "W2 built 2026-10-16; see `docs/superpowers/plans/2026-10-16-couple-widget-w2.md`."

- [ ] **Step 2: Run the full suite, both builds and every native check**

Run: `flutter test > "$WS/full.txt" 2>&1; tail -c 300 "$WS/full.txt"`
Expected: `All tests passed!`. Record the count.

Run: `flutter build apk --debug` and `flutter build ios --debug --no-codesign`
Expected: both succeed.

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.barsopus.attune.CoupleWidgetModelTest` and the swift check (Task 4, Step 4).
Expected: both green.

- [ ] **Step 3: Write the checklist v3.1 evidence into the ledger**

| Item | Evidence |
|---|---|
| 1.4 | Greps: no network, Supabase or token use in the new Kotlin/Swift (Tasks 3, 5) |
| 2.1 | Malformed / unknown-version / malformed-date vectors give neutral; `isWidgetFile` (path outside, `..`, missing); iOS resolves the file name against the container |
| 2.4 | Every parse path catches and gives neutral; `loadMap` catches and gives null |
| 2.5 / 2.10 | Bitmap decoded with `inSampleSize` ≤ 480 px; the alarm replaced each render and cancelled in `onDisabled` and when nothing expires; one PendingIntent request code |
| 4.4 | No log calls in the new native files (greps) |
| 5.5 | Fixed copy only |
| 6.1 | Half-hour and negative offsets, leap-day epoch, midnight next-change, validUntil == now, past and malformed reunion dates |
| 6.4 | Signed-out / unpaired / neutral-screen / flag-off / already-on-Planning deep-link tests |
| 7.1–7.3 | Only test-scoped deps added (junit, org.json); analyzer clean |
| 8.1 | Flag off: the Dart publisher clears (W1), and the widget then shows neutral |

Known, ledgered as minors, not fixed here:
- Dart's `daysUntil` (`reunion.dart`) uses `Duration.inDays` and under-counts by one across a spring-forward, while Kotlin and Swift count calendar days. That's a pre-existing W1/reunion divergence for the owner.
- `nextChange` keeps a nightly midnight alarm while a past reunion date is still stored. The app's `dropExpired` removes it at the next open.

- [ ] **Step 4: Device checklist (for the owner, from spec §8, recorded in the ledger)**

1. Add both sizes on iOS and Android.
2. Distance, clock and countdown match the app.
3. Partner pauses: the widget drops within 3 h, including Android left idle overnight.
4. Midnight ticks the countdown.
5. Tap opens Planning → Map; after quick exit it opens the neutral screen; signed out, it just opens the app.
6. Dark mode; iOS tinted mode (no map); largest Dynamic Type / font scale 2.0.
7. VoiceOver and TalkBack.
8. iOS StandBy with the default lock setting.

- [ ] **Step 5: Final Fable review, then one fix pass**

The final Fable review uses the review package (new files in full, shared files as snapshot diffs), this plan's Review Focus verbatim, and the ledger's rulings. Then one fix pass, each fix proved by a test that failed first.

---

## Self-review (done while writing)

**Spec coverage**

| Spec section | Task |
|---|---|
| §3.1 sizes and copy | Tasks 1–5 |
| §3.2 look (system colours, tinted mode, sample data) | Tasks 3, 5 |
| §3.3 map display | Tasks 3, 5 |
| §4.2 expiry, Doze alarm, iOS timeline | Tasks 2–5 |
| §4.4 file resolution | Tasks 2, 3, 5 |
| §6.2 iOS | Tasks 4–5 |
| §6.3 Android | Tasks 2–3 |
| §6.5 deep link | Tasks 6–7 |
| §8 native tests | Tasks 2, 4 |
| §8 builds | Tasks 3, 5, 8 |

The accessory families stay out (W3 in the spec).

**Placeholders:** none. Every file's full content is given; the conditional steps (`src/test/java` fallback, `#available` guards) say exactly what to do and require a ruling.

**Type consistency:** these names are used identically across tasks:
- `CoupleWidgetView` fields: `headline`, `headlineIsClock`, `caption`, `clockLine`, `clockOffsetMinutes`, `neutral`, `showMap`.
- `resolve(raw, nowMs, today)`, `nextChangeMs` / `nextChange`, `epochDay`, `zoneId`, `isWidgetFile`.
- `PlanningHomeTab`, `planningTabFromQuery`, `planningMapTabBuilderProvider`, `openPlanningFromLink`, `coupleWidgetLink`.

## Plan review (Fable, 2026-10-16) — all applied

**Critical**
- **C1.** The regression command named a missing `test/features/auth/`. It now uses `test/login_profile_test.dart`.

**Important**
- **I1.** On iOS, `Text(date, style: .time)` is fixed text and the time-zone override is undocumented. The clock is now per-minute timeline entries over a self-shifted instant, plus a simulator check with offset 330.
- **I2.** Two Android breaches of spec §3.2. Added the system corner radius on 31+ (`drawable-v31`) and autoSize on the headline (weighted height).
- **I3.** A cold-start link is delivered twice. Added a single-flight guard and a "twice at once pushes once" test.
- **I4.** The contrast figures were wrong. Corrected to 6.05:1 and 8.09:1.
- **I5.** The iOS midnight broke on the 25-hour day. It now uses calendar arithmetic.

**Minor**
- **M1.** The spec amendments are flagged as owner decisions.
- **M2.** The deep-link helper is wrapped in a try.
- **M3.** The time-zone range for `today` is noted.
- **M4.** The `daysUntil` DST divergence is ledgered for the owner.
- **M5.** The drop-order amendment is added.
- **M6.** The parsers are stricter: Swift dates, Kotlin `v`.
- **M7.** The plan now says to ignore lint's exit code.
- **M8.** The K2 error wording is fixed.
- **M9.** The past-reunion midnight alarm is noted.
- **M10.** The Review Focus 1 wording now matches what's tested.
