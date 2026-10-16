# Couple Distance Widget (Design)

**Status:** design approved in conversation (2026-10-16), medium size with the region map. Fable's adversarial review was folded in on 2026-10-16 (§10). Spec approved by the owner (2026-10-16). W1 (Dart) built 2026-10-16; see `docs/superpowers/plans/2026-10-16-couple-widget-w1.md`. W2 (native widgets + deep link) built 2026-10-16; see `docs/superpowers/plans/2026-10-16-couple-widget-w2.md`.
**Builds on:**
- Couple Map (`2026-10-16-couple-map-design.md`): presence, `distanceCopy()`, `withReunion`, the 8-hour rule, `couple_map_enabled`.
- Together Phase 8a (`2026-10-14-together-hub-design.md`): `home_widget` ^0.9.2, App Group `group.com.barsopus.attune`, the `TogetherWidgets` WidgetKit bundle, the Android `HomeWidgetProvider` pattern, and the discreet rule.

**Quality bar:** *Algorithm Quality Review Checklist v3.1* (§9).

---

## 1. What this is

A home-screen glance for couples who live apart: **how long until we're together, what time it is there, and how far apart we are**. The medium size adds a small region map with two soft glows and an arc between them.

The in-app version is the Map tab's distance card; this spec adds no second in-app surface. The Sharing sheet gains one toggle and a simple preview.

## 2. Rulings (binding)

Carried over from the Couple Map spec, and not reopened here:
- **The partner is an approximate area.** There is never a dot, and no position is drawn finer than a region (§3.3).
- **No timestamps about the partner.** The one time value on the device is `validUntilMs`, my own write time plus 3 h. It says nothing about when the partner updated (§4.4).
- **One neutral state for every reason** on the partner's side.
- **Never a push.**
- **Flag:** nothing renders unless `couple_map_enabled` is on. When the flag is off, the app clears the widget's data. The flag is cached per process, so this takes effect on the next cold start.

New for the widget:
1. **Off by default, per account on this phone.**
   - The owner turns it on in the Sharing sheet: "Show distance on my home screen".
   - Every clearing path (§6.4) also resets the opt-in, so after quick exit, sign-out or a new account, it stays off until chosen again.
2. **Discreet** (the Together Phase 8a rule).
   - No partner name, avatar, city or place name on the card.
   - **No app name on the card, in any state:** the off and empty states share one neutral card.
   - The how-to wording lives only in the widget gallery's description.
3. **The widget never samples location, and never touches the network.**
   - It shows only what the app last wrote to the App Group.
   - The app's extra resume read is a read; it never records my location (§4.1).
4. **It never shows a partner distance, clock or area more than 8 hours old**, measured from the partner's last update, and never one I couldn't see in the app (§4.2).
5. **Metres are never shown.** The wording follows `distanceCopy()`.

## 3. Experience

### 3.1 Sizes and copy (v1: home screen only)

| Size | Platform | Layout |
|---|---|---|
| Small | iOS `systemSmall`, Android 2×2 | **Headline**, **caption**, and the **clock line** (when the headline isn't already the clock) |
| Medium | iOS `systemMedium`, Android 4×2 | Square region map on the left, with the same three lines on the right. Text only (the small layout, widened) when there's no map (§3.3) |

Lock-screen and accessory families are **not in v1**: their redaction depends on a user setting, and they are the one surface visible while the phone is locked. They can come later as W3, with their own review.

**Copy follows the app's hierarchy** (`distanceCopy()` and its rationale: for couples apart, lead with what changes, not the number). The only difference from the app is that the city and partner name are dropped (the discreet rule), so the km takes the caption.

| Tone (from `PartnerDistance`) | Headline | Caption | Clock line | Map |
|---|---|---|---|---|
| `together` | "Practically together" | none | none | no |
| `nearby` | `distanceCopy()` headline, e.g. "12 min away" | none | none | no |
| `sameCountry` | `distanceCopy()` headline, e.g. "7 hours by road" | "412 km apart" | "3:15pm there" if the offset differs from mine | if ≥ 100 km |
| `countdown` (via `withReunion`) | "12 days until you're together" / "Together tomorrow" / "Together today" | "412 km apart" | "3:15pm there" | yes |
| `distant` | the live clock, "3:15pm there" (as the app leads with it) | "5.1k km apart" | none (it's the headline) | yes |

- **The clock is live:** "3:15pm there" is the system's time formatter in the partner's fixed offset. Android's `TextClock` follows the phone's 12/24-hour setting ("3:15 PM"); that difference from the app's `formatClock` is accepted. *(Amended in W2, owner-approved:)* iOS draws the clock as one timeline entry per minute (WidgetKit has no live wall-clock text), shifting each instant by its own arithmetic so no time-zone environment is relied on.
- **The reunion** comes only from `withReunion` (km ≥ 800, the app's own gate). Once written, the reunion date is kept until that day passes, even after the distance part expires; it is calendar data, not location. A couple who are together never get a reunion countdown.

**The one neutral card:** a small heart glyph and "Nothing to show yet". It's used for:
- off;
- not opted in;
- no honest distance and no reunion;
- not sharing;
- flag off;
- after any clearing.

A remaining reunion with no distance shows the countdown alone ("12 days" / "until you're together").

**Widget gallery** (the only place with how-to wording):
- iOS `configurationDisplayName("Apart")`, `description("Time and distance between you two. Turn it on in Attune first.")`.
- Android: the same label and description, in `couple_widget_strings.xml`.

**Tapping** opens the app on Planning → Map (§6.5).

### 3.2 Look
- **System semantic colours** plus the app accent, like the Together widget. No palette is copied into the payload.
- **Background:**
  - iOS: `containerBackground(.fill.tertiary)` on 17+.
  - Android: a rounded surface with `@android:dimen/system_app_widget_background_radius` on 31+, 16 dp before.
- **Type:** the system fonts.
  - The headline scales down to fit: `minimumScaleFactor` 0.6 on iOS, `autoSizeTextType` on Android 26+.
  - Dynamic Type and font scale are honoured.
  - *(Amended in W2, owner-approved:)* the headline shrinks to fit (Android autoSize, iOS `minimumScaleFactor`). When the card is still too short, the bottom line (the clock line) is cut first, then the caption; vertical layouts clip from the bottom on both platforms.
- **iOS 18 tinted and clear modes** (`widgetRenderingMode != .fullColor`): the map is hidden and the text layout is used.
- **Placeholders:** `placeholder` and `getSnapshot` when `context.isPreview` use **sample data** ("Together tomorrow", "5.1k km apart"), never the real payload. The gallery is often shown over someone's shoulder.

### 3.3 The region map (medium only)

Drawn by the app from a **bundled world land outline** (Natural Earth 1:50m land, public domain; measured at ~60.7k points, ≈ 250 KB as int16), never by Mapbox, and written to the App Group as one PNG. That keeps the image free of tokens, the network, attribution, and Mapbox's tile cache.

**Shown only when** both areas are present and fresh (§4.2), the tone is `sameCountry`, `countdown` or `distant`, and the distance is **≥ 100 km**. Otherwise the medium size uses the text layout.

**Drawing rules:**
- **Projection:** Web Mercator, latitude clamped to ±80°.
  - The outline is stored **already projected** (int16 Mercator), so a render does no trigonometry.
  - Rings smaller than ~1 px at the render scale are skipped.
- **Antimeridian:** the partner's longitude is unwrapped to within ±180° of mine, so a Pacific couple's arc crosses the Pacific. Land copies at ±360° fill the frame.
- **Region grid:** each area is **snapped to a 0.5° grid** (~55 km) before drawing; the glows are drawn there, never at the cell. This is draw-only: distance and copy still use the cells.
- **Frame:** a square, fitting both snapped points inside the **central 50 %**, centred on their **midpoint**, never on either area.
  - **Minimum span: 600 km**, so a glow can't be read finer than the grid (~1.7 km per pixel at the minimum).
  - **Maximum span:** the world.
- **Image and crop:** **480 × 480 px**, shown with `.scaledToFill()` / `centerCrop`. Any widget pane from 1:1 to 2:1 keeps the central 50 % visible, so both glows always show.
- **Glows:** fixed screen size (20 pt radius, a soft radial gradient), never sized by geography. Mine is the accent and theirs the accent's companion tone. No avatars, labels or centre dot.
- **Arc:** curved and dashed, bowed toward the pole (a visual stand-in, not a geodesic).
- **Nothing else on the image:** no text, borders, roads, cities or labels.
- **One transparent PNG:**
  - land is a mid-grey at ~22 % opacity;
  - the sea is transparent, so the widget's own background shows through;
  - the glows and arc are opaque.

  That reads on light and dark without a second render.
- **Cache:** re-rendered only when the snapped points or the asset version change.

### 3.4 In the app: the Sharing sheet
- A new `InfoRowWidget` toggle, "Show distance on my home screen", below the pause rows, whenever the couple map is enabled.
- **When on**, a plain preview card shows the map image (if any) and the three lines, labelled "Your home screen shows roughly this". It isn't a pixel copy of the native widget. One instruction line follows:
  - iOS: "Touch and hold your home screen, tap +, then find Attune".
  - Android: "Touch and hold your home screen, tap Widgets, then find Attune".
- **Turning it off** clears the App Group data and deletes the image at once.
- The sheet's existing accessibility rules apply: a 48 dp target and a labelled toggle.

## 4. Safety model

### 4.1 When the app writes

The app writes **only if this account has opted in on this phone and the flag is on**. Two sources, one publisher:

1. **The presence provider's own refresh.** A one-line hook at the end of `coupleMapPresenceProvider`'s `refresh()` hands each emitted `CoupleMapPresence` to the publisher.
   - This is a shared-file edit to `presence_providers.dart` (regression risk: low; the hook is fire-and-forget and never throws).
   - **The publisher never `watch`es or `listen`s to the provider.** Keeping an `autoDispose` provider alive would make it record on every resume and every 15 minutes, which would change the sampling rule.
2. **A resume read.** On app open and resume, if the provider hasn't handed over anything in the last 5 minutes, the publisher calls `PresenceRepository.fetchMapPresence` once.
   - That is a read; **it never calls `record`**.
   - It doesn't retry: the next open covers it.

**State changes** also write straight away, from the new state: pause, resume, stop, start, the toggle, or the flag off. Reminder changes recompute the reunion.

**Ordering:** a generation counter. Every state-changing write (pause, stop, off, toggle off, flag off, sign-out) bumps it. A read that started under an older generation is discarded when it lands. Writes are serialised through one in-flight future.

### 4.2 Expiry: never older, never asymmetric

The server sends only per-row `freshness` (`fresh` < 4 h, `fading` 4–8 h), never update times.

- **The distance part** (headline and caption from distance, the clock offset, the map) is written **only when both my row and the partner's row are `fresh`**, and I'm sharing and not paused.
  - Because my own row is fresh, the partner can still see me for at least 4 more hours, longer than the widget's validity. So the widget is never one-sided.
- **Validity: 3 hours** from the write.
  - Worst case on iOS: under 4 h old at the write, plus 3 h, gives under 7 h. A timeline entry at `validUntil` switches the view without the extension running.
  - **Android:** `onUpdate` schedules `AlarmManager.setAndAllowWhileIdle(RTC, validUntil, …ACTION_APPWIDGET_UPDATE)`. It fires during Doze within ~15 minutes and needs no exact-alarm permission. It's replaced on every update and cancelled by `clear()`. The 30-minute `updatePeriodMillis` stays as a backstop. Worst case: under 4 h + 3 h + 15 min.
- **On expiry**, the view falls back to the reunion countdown if any, else the neutral card.
- **The expired data is removed on disk**, not just hidden, at the next app open (the publisher drops expired parts and deletes the image). Until then, it sits only in the App Group / app-private storage (§4.4).

### 4.3 Pause, stop and unlink
- **I pause or stop:** the generation is bumped and a write lands at once with no distance part.
- **My partner pauses or stops:** my widget keeps the last distance for at most its remaining validity (≤ 3 h), then falls back. It shows nothing new, only what the app already showed me, and the fallback looks exactly like staleness.
- **Quick exit, sign-out, account deletion, end relationship:** cleared on the device, and the opt-in is reset (§6.4). The server purge already removes presence.

### 4.4 What is stored on the device
- **`couple_widget_v1` (JSON):** `{v, headline?, caption?, clockOffsetMinutes?, validUntilMs?, reunionDate?}`.
  - Absent or `{v}` alone means the neutral card.
  - The reunion keeps its own date and the native side computes "N days".
  - **`validUntilMs` is the only time value.** It's my write time plus 3 h (a self-facing exception to "no timestamps").
- **The map image** is stored under the plugin's own key (`couple_widget_map`, written by `renderFlutterWidget`; `saveWidgetData(key, null)` deletes the file). The JSON doesn't repeat its path.
  - iOS resolves the file name against `containerURL(forSecurityApplicationGroupIdentifier:)` and never trusts a stored absolute path.
- **Never stored:** coordinates, cell ids, city, country, partner name, avatar, relationship id, or user id. The image holds only the 0.5°-snapped region.
- **Who can read it:**
  - iOS: the App Group, readable only by this app's targets (the WidgetKit extension and the Share Extension).
  - Android: app-private `HomeWidgetPreferences` and `files/home_widget/`.
- **Android backup:** both are **excluded** in `backup_rules.xml` and `data_extraction_rules.xml`, so a cloud backup never carries them.

### 4.5 Scenarios

| Scenario | What the widget shows |
|---|---|
| Long distance with a reunion | "12 days until you're together" · "5.1k km apart" · "3:15pm there"; medium shows the region map |
| Long distance, no reunion | "3:15pm there" · "5.1k km apart"; region map |
| Living together | "Practically together"; no number, no map, never a countdown |
| Same city, apart in the day | "12 min away"; nothing updates without an app open, and cells don't resolve streets |
| Travel | The next app open (by either) updates it; between opens it can only expire, never move |
| Partner pauses | The old distance for ≤ 3 h, then the countdown or the neutral card, indistinguishable from stale |
| I haven't opened the app in 5 h | My row is `fading`, so no distance is written at the next resume read until I'm fresh again (the Map tab records) |
| Someone glancing at an unlocked phone | No name, place or app name; a time, a distance and a region at most |
| Locked phone | **Android:** home-screen only (`widgetCategory = home_screen`), never on the keyguard; no redaction exists, which is why the card is discreet. **iOS:** home screen and, if the user puts it there, StandBy. `privacySensitive()` redacts only when the "Allow access when locked" setting for widgets is off; we don't rely on it |
| Quick exit, sign-out, new account on the same phone | Cleared, and the opt-in reset; the next person never inherits "on" |
| Flag turned off server-side | Cleared on the next cold start; until then it can only expire |

### 4.6 Checked against our rules
- **ATTUNE_SOUL §1/§8 and the permanent constraints:** no history, no counters (never "days apart"), no streaks, no nudges. A countdown *to* being together is allowed; a count of time apart is not.
- **Couple Map §2:** approximate, no dot, no partner timestamps, one neutral state, never a push.

## 5. Data
No server changes and no migration. The widget reads only what `couple_map_presence` and the reminders list already return.

## 6. Client architecture

### 6.1 Dart: `lib/features/couple_map/widget/` (new)
- **`domain/couple_widget_payload.dart`:** builds the payload from `CoupleMapPresence` + `PartnerDistance?` (after `withReunion`) + the kept reunion + now. **Pure, fully unit tested.** It owns:
  - the both-fresh rule;
  - the 3 h validity;
  - the copy table (§3.1, reusing `distanceCopy()` / `formatKm()`);
  - the "show map?" rule;
  - dropping expired parts.
- **`domain/region_frame.dart`:** 0.5° snapping, antimeridian unwrap, midpoint square frame, central-50 % fit, 600 km minimum, world cap. Pure, with property tests.
- **`data/world_outline.dart`:** loads `assets/geo/land_50m_merc.bin`, int16 projected rings, ≤ 400 KB.
  - It's generated by a committed script, `tool/build_land_outline.dart`, from Natural Earth GeoJSON.
  - `assets/geo/README.md` states the source and the public-domain licence.
- **`presentation/region_map_painter.dart`:** a `CustomPainter` for land, glows and arc. It's rendered with `HomeWidget.renderFlutterWidget`, which needs the live engine, so renders happen only in the foreground. It's reused by the in-app preview.
  - A render can't be cancelled. Above a 2 s budget, the payload is written without the map (text layout), and a late render's result is discarded by the generation check.
- **`data/couple_widget_sync.dart`:** like `TogetherWidgetSync`, it never throws, and reuses the `WidgetStore` seam.
  - `publishIfEnabled` re-reads the opt-in from storage.
  - `clear({resetOptIn})`.
  - Key `couple_widget_v1`; iOS kind `CoupleWidget`; Android `com.barsopus.attune.CoupleWidgetProvider`.
- **`presentation/couple_widget_publisher.dart`:** owns the hook target, the resume read, the debounce, the generation counter and the kept reunion. Mounted once at the app shell; it never watches the presence provider (§4.1).

### 6.2 iOS: `ios/TogetherWidget/`
- `CoupleWidget.swift` is added to the existing `TogetherWidgets` bundle. There is no new target, and the App Group is already enabled. Deployment target 14.0, so 15/16/17/18 APIs get `#available` guards.
- **Small and medium views.** A timeline with entries at now, at `validUntil`, and at the next local midnight (for the countdown); policy `.after(next)`.
- **Clock:** `Text(date, style: .time)` with `.environment(\.timeZone, TimeZone(secondsFromGMT: offset*60))`.
- **Accessibility:** `privacySensitive()` on the content, as a best effort (§4.5); `accessibilityHidden(true)` on the map; one combined `accessibilityLabel`, e.g. "12 days until you're together. 5,100 kilometres apart. 3:15 pm there."

### 6.3 Android
- **Files:** `CoupleWidgetProvider.kt` (`HomeWidgetProvider`), `couple_widget_small.xml`, `couple_widget_medium.xml` and `couple_widget_info.xml`.
  - The info file sets `updatePeriodMillis = 1800000`, `targetCellWidth`/`targetCellHeight`, the resize bounds and `widgetCategory = home_screen`.
- **Layouts:** on API 31+, `RemoteViews(Map<SizeF, RemoteViews>)` gives small and medium by size. Before 31, the choice comes from `OPTION_APPWIDGET_MIN_WIDTH` in `onUpdate` and `onAppWidgetOptionsChanged` (map at ≥ 250 dp).
- **Clock:** `TextClock` with `setTimeZone("GMT±hh:mm")` via `RemoteViews.setString`.
- **Map:** `setImageViewBitmap`, decoded from the app-private file with `inSampleSize`. Never `setImageViewUri`, because the launcher can't read app-private files.
- **Accessibility** *(amended in W2, owner-approved):* there's no combined description on the root, because a live `TextClock` can't sit inside a static description. TalkBack reads the lines in order, and the map image is `importantForAccessibility="no"`. iOS combines the lines with `.accessibilityElement(children: .combine)`, live time included.
- **Expiry:** the `setAndAllowWhileIdle` alarm from §4.2.
- **Tests:** a pure `currentPayload(raw, now)` companion, unit tested like `TogetherWidgetProvider.currentLines`.

### 6.4 Clearing
`CoupleWidgetSync.clear(resetOptIn: true)` writes `{v}`, deletes the image (`saveWidgetData(couple_widget_map, null)`), cancels the Android alarm through an `updateWidget` broadcast, and resets `couple_widget_enabled`. It's called:
- **first** in `clearCoupleMapDeviceData()` (quick exit), ahead of the Mapbox cache clear, so it's broadcast before Android quick exit leaves at 300 ms;
- from `clearTogetherDeviceSurfaces()` (sign-out, account deletion, end relationship, Together with no relationship);
- from the Sharing-sheet toggle turned off.

On flag off, the publisher calls `clear(resetOptIn: false)`, so a temporary flag-off doesn't lose the choice.

*Noted, out of scope:* `TogetherWidgetSync.clear()` doesn't reset `together_widget_enabled`. That's the same inheritance issue for the Together widget, recorded for its owner.

### 6.5 Opening the Map tab
- **Today, no such link exists:**
  - `/planning` needs its relationship id from `extra`;
  - `PlanningHomeScreen` always opens tab 0;
  - `_handleDeepLink` handles only auth and invite.
- **W2 adds** (shared files, flagged: `main.dart`, `app_router.dart`, `planning_home_screen.dart`):
  - **The URL:** `attune://planning?tab=map` (amended in W2, owner-approved). No relationship id is ever in it, and there's no `homeWidget` item: home_widget's iOS app-delegate hook would claim such a URL. app_links alone delivers it on both platforms; on Android, the plugin's launch intent carries it as data.
  - **Flag off:** the tap opens the app without navigating.
  - **A cold-start link arrives twice** (app_links' initial link plus its stream): one open at a time.
  - **One handler, app_links**, on both platforms. home_widget's launch callback isn't used, so the link isn't handled twice.
  - **A `planning` branch in `_handleDeepLink`:**
    - resolve `currentRelationshipIdProvider`;
    - require the flag;
    - **do nothing if the current route is quick exit's neutral screen**, signed out, or unpaired.
  - **`PlanningHomeScreen(initialTab:)`**, defaulting to 0, so existing callers are unchanged.

## 7. Phases

| # | What ships | Risk |
|---|---|---|
| W1 (built) | Payload, region frame, outline asset and script, painter, sync, publisher (hook + resume read + generation), Sharing-sheet toggle and preview, clearing and opt-in reset, Android backup excludes | The shared-file hook in `presence_providers.dart`; render time on low-end Android (benchmark: ≤ 150 ms to paint, off the first frame) |
| W2 (built) | iOS `CoupleWidget` (small, medium) in the existing bundle; Android provider, layouts and expiry alarm; the deep link (§6.5) | Native code verified by build, Kotlin unit tests and device checks; the routing edits are shared files |

Each phase gets its own plan, runs TDD on `main`, and gets a Fable review and one fix pass.

## 8. Verification

**Dart unit tests**

*Payload:*
- both fresh → distance with a 3 h `validUntil`;
- **either row fading → no distance**;
- paused, off, or no own row → no distance;
- `together` / `nearby` → no km, no clock, no map;
- every row of the §3.1 copy table, checked against `distanceCopy()`;
- reunion only via `withReunion` (km ≥ 800);
- a kept reunion expires after its day;
- expired parts are dropped;
- **no coordinate, city, name or id anywhere in the JSON** (a recursive scan against the inputs).

*Region frame:*
- snapping and midpoint centring;
- the 600 km minimum;
- the antimeridian (Auckland–Los Angeles; Fiji either side of 180°);
- the polar clamp;
- antipodal and identical snapped points.
- Properties: the glows stay inside the central 50 %; the frame never centres on one area; the span is never under 600 km.

*Sync:* publishes only when opted in (read from storage); `clear` deletes the image and resets the opt-in; it never throws without the plugin.

*Publisher:*
- the resume read **never calls `record`**;
- the publisher never keeps the presence provider alive (a test asserts the provider is disposed with the Map tab unmounted);
- at most one read per 5 minutes;
- **a pause during an in-flight read: the read's result is discarded** (concurrency test);
- the flag off clears without resetting the opt-in;
- a render timeout gives the text layout.

**Widget tests**
- The Sharing-sheet toggle and the preview.
- Painter goldens: far apart, crossing the Pacific, the world view, the 600 km minimum, on light and dark backgrounds.
- Accessibility guidelines on the sheet additions.

**Native**
- Kotlin unit tests for `currentPayload`: expiry, neutral, malformed JSON, unknown `v`.
- `flutter build apk --debug` and `flutter build ios --debug --no-codesign` both succeed.

**Manual (two devices)**
- Add both sizes on both platforms.
- The partner pauses: the widget drops within 3 h. On Android, leave the phone idle overnight and check it drops on time (Doze).
- I pause: it drops at once.
- Quick exit, sign-out (then sign in as another account), and end relationship each clear it and reset the opt-in.
- Flag off clears it on a cold start.
- Dark mode, iOS tinted mode, Dynamic Type at its largest, Android font scale 2.0, VoiceOver and TalkBack.
- Tapping opens Map; tapping after quick exit stays on the neutral screen.
- iOS StandBy with the default "Allow access when locked" setting: note what shows.

## 9. Algorithm Quality Review Checklist v3.1

Scope tags: `[ALL]`, `[UI]`, `[MOBILE]`. Skipped: `[SERVICE]`, `[MUTATION]`, `[ASYNC]` (no server changes; the only network use is the existing read), `[FIN]`, `[UI-WEB]`.

**Blocking (P0-U / P0-C)**

| # | How this design meets it | Evidence |
|---|---|---|
| 1.4 Authorization | No new access. The read is the existing `couple_map_presence` RPC under the caller's session. The extensions hold no token and make no calls | Grep: no network or Supabase import in the Swift and Kotlin |
| 1.5 Authentication | Unchanged; sign-out clears and resets the opt-in | Clearing test |
| 2.1 Input sanitisation | Native code parses defensively: malformed JSON or an unknown `v` gives the neutral card. iOS resolves the image against the container, never a stored path | Kotlin unit tests; Swift decode fallback |
| 2.4 Errors don't leak | Sync never throws; only fixed states are shown | Unit tests |
| 2.5 Resource limits | One 480×480 PNG, re-rendered only on a cache-key change; a read at most every 5 min; outline ≤ 400 KB; small rings culled | Debounce and cache-key tests; asset size check |
| 2.10 Resources released | The lifecycle listener is disposed with the publisher; the Android alarm is replaced or cancelled; bitmaps are decoded with `inSampleSize` | Widget test disposes the publisher; Kotlin test |
| 4.4 No PII in logs | **No coordinates, places, cities or names are logged, and none are in the payload or image metadata** | Payload scan test; grep |
| 5.5 Nothing internal in the UI | Fixed copy only | Tests |
| 7.1–7.3 Scans | No new dependency; analyzer filter clean; the Natural Earth licence is noted | Phase evidence |

**Required before merge (P1)**
- **1.1 Idempotency:** a write is a full payload replace; `clear` is idempotent.
- **1.2 Timeouts:** the read uses the client timeout. The render has a 2 s budget; it can't be cancelled, so its late result is dropped by the generation check.
- **1.6 / 2.16 Concurrency:** the generation counter plus one serialised writer (§4.1).
- **1.11 Privacy:** §4.4 is the full inventory. Expired parts are hidden at `validUntil` and deleted at the next app open. Android backup is excluded. Every clearing path and the opt-in reset are covered.
- **2.12–2.15 Bounded work:** one render per cache-key change; ~60k projected points with culling; no loops beyond the outline's rings; renders only in the foreground.
- **3.10 No retrying permanent errors:** the resume read doesn't retry.
- **6.1 Edge cases:** the antimeridian, poles, antipodes, identical points, DST in the offset (refreshed each write, ≤ 3 h), the countdown's midnight rollover, a reunion today.
- **6.3 Concurrency tests:** pause during an in-flight read; a render finishing after a clear.
- **6.4 Negative tests:** no distance when either row is fading, when paused or off, when not opted in, or when the flag is off; nothing after clear.
- **7.7 Continuous scanning:** the repo's existing CI.
- **8.1 Rollback:** the flag off clears on the next cold start. The native widgets remain and show the neutral card.

**Required before production (P2)**
- **1.3 Graceful degradation:** render failure, asset missing or slow render gives the text layout; a missing plugin does nothing.
- **1.8 Complexity:** O(points) per render, cached; O(1) per write.
- **3.4 Cache:** the PNG cache key (snapped points, asset version).
- **4.1 / 4.5 Logs:** failures logged by category only (`widget_render_failed`, `widget_read_failed`), never with values.
- **4.11 Configuration:** 3 h validity, 100 km map threshold, 0.5° grid, 600 km span, central 50 %, 5 min debounce, 480 px, 2 s render budget — all in `CoupleWidgetConfig`.
- **5.1 / 5.6 UX and accessibility:** one combined label, a hidden image, Dynamic Type, tinted mode, contrast on both backgrounds.
- **6.2 Failure tests:** render failure, asset missing, plugin missing, read error.
- **6.7 Coverage:** domain ≥ 90 %, sync and publisher ≥ 70 %.
- **6.9 Performance:** a benchmark test for the painter (≤ 150 ms on the CI host as a proxy; device check on a low-end Android).

**Backlog (P3)**
- **6.5 Property tests:** the region-frame invariants (§8).
- **6.8 Mutation checks:** the both-fresh rule, the 3 h validity, the map threshold, and the generation discard.

## 10. Review log

**Fable adversarial review (2026-10-16).** Every finding was applied.

**Critical**
- **C1.** Android Doze could defer `updatePeriodMillis` for hours, breaking the 8-hour rule. Fixed with a `setAndAllowWhileIdle` alarm at `validUntil` (§4.2, §6.3).

**Important**
- **I1.** The off card named the app. Off and empty now share one neutral card; the how-to lives only in the gallery description.
- **I2.** The copy inverted `distanceCopy()`'s hierarchy. The app's hierarchy is adopted; only the city and name are dropped (§3.1).
- **I3.** A countdown without the km ≥ 800 gate. The reunion now comes only via `withReunion`, and is kept until its date.
- **I4.** The resume read could show the partner while my own row was fading. Both rows must now be `fresh`.
- **I5.** A pause could be overwritten by an older read. Fixed with the generation counter, plus a concurrency test.
- **I6.** A shell publisher watching the provider would have kept it alive, changing sampling. Replaced by a hook inside `refresh()` plus a read-only resume read.
- **I7.** The deep link didn't exist. W2 now scopes a real handler, `initialTab`, a single handler, and the neutral-screen guard.
- **I8.** A 2:1 crop could cut off a glow. Now a square image with the central-50 % fit.
- **I9.** iOS lock-screen redaction depends on a setting. Accessory families are cut from v1, and the dependency is stated.
- **I10.** The opt-in survived sign-out. Clearing now resets the opt-in.
- **I11.** Checklist gaps: storage lifetime, flag caching, the uncancellable render, missing P1/P2 items, Android backup. All fixed.

**Minor**
- M1: bitmap, not URI; sized `RemoteViews` on 31+.
- M2: the plugin's image key, and iOS container resolution.
- M3: the `validUntilMs` exception stated.
- M4: the clock is part of the distance part, and freshness is per row.
- M5: `TextClock` format accepted.
- M6: preview and placeholder use sample data.
- M7: clear runs first in quick exit, with a broadcast.
- M8: the outline is pre-projected, with ring culling.
- M9: Android keyguard and redaction stated.
- M10: the "on foot" example dropped.

**Scope cuts:** accessory families (to W3), the colour payload, light and dark image pairs (now one transparent PNG), the Android pin button, and the pixel-exact in-app preview.
