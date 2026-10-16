# Couple Map: where we are, and where our stories happened (Design)

**Status:** design approved in conversation (2026-10-15). A Fable adversarial review was folded in on 2026-10-15 (see §9). Waiting for the owner's review of this written spec.
**Replaces:** §2 ("no map of the partner") of `2026-09-02-location-presence-design.md`. Every other rule in that spec still holds: opt-in, silent stop, no cadence, and precision only where a person chose it. Those rules are restated below where they apply.
**Builds on:**
- Stories (`STORIES.md`, the calendar day views).
- Planning v2 (member time zones).
- Together (scenario lens, safety posture, quick exit).

**Quality bar:** each phase's spec section passes *Algorithm Quality Review Checklist v3.1* (`lib/architecture/algorithms/algorithm_quality_review_checklist.md`).

---

## 1. What this is

**Map** becomes the third tab of the couple's journal: **Planning | Calendar | Map**. It does three things:
1. **Where we are.** Each partner appears as an *approximate area*: an avatar over a soft circle at neighbourhood level, never a dot. A distance card shows how far apart you are, the place, the partner's local time, and the days until you're together.
2. **Where our stories happened.** A partner can pin a story to the map. Pinned stories appear at the exact place they were taken, as memories.
3. **Easy to steer.** Round buttons at the top right switch the map style, filter the stories (both, mine or my partner's), recentre on the two of you, and open an accessible list.

### 1.1 Why this shape (research, 2026-10-15)

**Market**
- **Zenly**, closed in 2023 while still loved, was valued for ambient presence and for Ghost mode, which could freeze or blur your location.
- **Snap Map** updates only when you open the app, drops your avatar after about 8 hours, and has a timed Ghost mode.
- **Bond Touch** shows only the partner's city and weather.
- **Glympse** and **Google Maps** time-box their shares or send reminders.
- **"Couple tracker" apps**, with route timelines and arrive/leave alerts, are the pattern to avoid.
- Distance features feel warm when they show:
  - the number shrinking;
  - a reunion countdown;
  - "it's 2 am for them".
- They feel creepy when they show:
  - a street address;
  - a history;
  - arrival pushes.

**Safety**
- Freed et al., *A Stalker's Paradise* (CHI 2018): most partner stalking is technically simple and uses access the abuser was given.
- Havron et al. (USENIX Security 2019) and the Clinic to End Tech Abuse: non-consensual location sharing is among the most common forms of tech abuse.
- Ofcom (2025): geolocation should be off by default.
- Apple Safety Check stops sharing in one step, and experts say that step should be quiet.

**Story maps**
- Instagram Map launched in August 2025 and drew a backlash. It placed posts that already had a location on a map, and profile-photo pins looked like live locations.
- Its October fixes:
  - a sharing indicator;
  - faces removed from post pins;
  - a preview before posting.
- We take all of these lessons:
  - opt in per story;
  - never backfill;
  - always show who can see you;
  - faceless pins;
  - preview before posting.

**Our own rules**
- ATTUNE_SOUL §1: "Not a surveillance tool." Data about how someone behaves is shown only to that person.
- ATTUNE_SOUL §8: never generate evidence against a partner.
- Permanent constraints: the discreet exit is non-negotiable.
- Together: no scorecards. Revoking deletes the data and tells the partner nothing.

**Why this reverses the September rule.** The September spec ruled out any partner map. This design reverses that on purpose, with these safeguards:
- **Precision:** the partner is never shown more precisely than about 1 km.
- **Sampling:** data is taken only when the app is opened.
- **No history:** nothing is kept, and no timestamps ever reach the device.
- **Leaving:** either partner can stop silently.

## 2. Owner rulings (binding)

1. **The partner is an approximate area.**
   - About 1 km, never a dot.
   - Updated only when that partner opens the app.
   - Hidden after 8 hours without an update.
   - Both partners must opt in.
   - **Pause** for 1 hour, 8 hours, or until resumed. It is silent and works both ways: while paused, you can't see your partner either.
   - When the partner is paused, stopped or stale, the other partner sees **one neutral line**.
   - Never a push notification.
2. **Pinned stories keep their exact place.**
   - A per-story **"Pin to our map"** switch at post time. It is off the first time, then remembers the author's last choice.
   - The author can unpin or delete at any time, which removes the place for good.
   - No backfill of older stories.
   - An optional **home-area warning**, stored on the device only.
3. **The map is Planning's third tab:** Planning | Calendar | Map.
4. **The Conversations "Together" card stays as it is** (days together and upcoming reminders). No distance line goes back there.

*Review note:* the reference image showed a green "online" dot. It is **not** built. The feed only updates when the app opens, so the dot would mean "opened Attune in the last 30 min". That is exactly the signal `20260931220000_partner_presence.sql` refused to show.

## 3. Experience

### 3.1 Layout (Material 3, light and dark)
- **The map** fills the screen. It uses Mapbox *Standard*, with its day/night preset following the theme, or *Standard Satellite*.
- **Top right:** round glass buttons, 44 dp, on a translucent surface (90 % `surface` with a hairline border; not blurred, because a blur over the Mapbox platform view is unreliable on Android and costly), each with a tooltip and a Semantics label.
  1. **Style:** map or satellite.
  2. **Stories:** cycles Both → Mine → Partner's. The icon shows the current choice. Hidden when no story is pinned.
  3. **Recentre:** fits both areas and the visible stories.
  4. **List:** the accessible alternative (§3.5).
- **Zoom:** two glass buttons under the top-right column (one column, so nothing overlaps on short screens), plus the Mapbox compass below them. The Mapbox logo and attribution stay visible above the distance card.
- **Top left: sharing chip.** It is always visible, so you always know who can see you.
  - States: *Off*, *Sharing my area with {partner}*, *Paused · 42 min*, *Paused*, *Location is off for Attune*.
  - Tapping it opens the **Sharing sheet**:
    - `BottomSheetHeader` with an `AppTextButton` "Done".
    - `InfoRowWidget` toggle "Share my approximate area".
    - Pause rows: 1 hour, 8 hours, Until I resume. A Resume row appears while paused.
    - **Remove all my places**, which deletes every place I pinned but keeps the stories.
- **Bottom: distance card.** A glass card with both avatars and a headline from `distanceCopy()`.
  - Details are joined with " · ", for example: "412 km apart · in Accra · 3:15 pm there · 12 days until you're together".
  - When together: "Together · Accra", with a warm accent.

### 3.2 Presence (approximate areas)
- **The pin.** An avatar over a translucent circle at least **1.6 km** across. The circle must cover a whole cell (about 1.1 km), corners included.
  - It is centred on the *server-snapped cell centre*, never on raw GPS.
- **No online dot and no timestamps.** The server returns only `freshness`, either `fresh` or `fading`.
  - *Fading* means one opacity step down to 0.5, after 4 hours.
  - After 8 hours, no row comes back at all.
  - Update times never reach the device.
- **Your own pin** also uses your cell, so both partners see the same kind of information.
- **Together** means both cells are the same or adjacent (no more than 1 cell apart).
- **Distance** is measured between cell centres and rounded:
  - to the nearest 5 km under 50 km;
  - to the nearest 10 km above 50 km;
  - never shown below "about 2 km".

### 3.3 Story places
- **Pins.** Round thumbnails with no dot, so they never read as live. They cluster as you zoom out; a cluster shows its newest story's thumbnail, slightly larger, with a count (Mapbox clusters can't stack several images; amended in Phase 2). Tapping opens every story under the finger, including stories pinned at the same spot.
- **Opening.** Tapping a pin or a cluster opens the story reel over those stories, oldest first.
- **"Remove from map"** is a second icon, shown only to the author, next to Delete. The reel has no overflow menu today; Delete is a top-left icon in `story_reel_screen.dart`.
- **Pinning.** At post time the camera shows a **"Pin to our map"** switch.
  - The place is looked up **only after the switch is turned on**, using the on-device `geocoding` package. No third-party call is made while the switch is off.
  - The label is previewed at neighbourhood level, for example "Near Osu, Accra".
  - If the optional home area is set and the story is within about 500 m of it, the camera shows "This looks near your home area" and the switch starts off for that story.
  - **While my area is paused**, the camera shows "Your area is paused" and the switch starts off.

### 3.4 Empty and onboarding states

The server gives the same answer for every reason on the partner's side, so there is one rule:
- **My row absent** (I'm not sharing): "See how far apart you are — shares your neighbourhood, never your address". Tapping it opens the Sharing sheet.
- **My row present, no partner row** (the partner isn't sharing, is paused, stopped or stale, or I'm paused): "Just you on the map right now".
  - Never "waiting for your partner".
  - Never a reason.
- **Location is off for Attune** (my own device only): "Turn on location for Attune to share your area". Tapping it opens system settings.
- **The map can't load** (offline, Mapbox error): the list sheet opens in its place, showing the same lines.
- **No pinned stories:** no pins. After the first visit, a one-time hint: "Stories you pin from the camera appear here".

### 3.5 Accessibility
- **The list sheet:**
  - Presence rows first, for example "{Partner} · Accra · 3:15 pm there".
  - Then story places, newest day first: the label as the title and the date (`MyDateFormat`, never a time) as the subtitle. Each row opens the reel. (Amended in Phase 2.)
- **The map canvas** is excluded from semantics. Every control has a label.
- **Reduced motion:** the camera jumps instead of flying.

### 3.6 Quick exit and the privacy cover
- `AppPrivacyCover` already hides the whole tab when the app goes to the background.
- `QuickExitService.execute` also clears the map's device-local data:
  - the last pin choice;
  - the home area;
  - cached pin images;
  - **the Mapbox tile and style cache**, which holds the partner's area.
- Quick exit **does not** change server presence. A sudden disappearance would itself be a signal to a controlling partner. Leaving on purpose is the separate, silent "Off".

## 4. Safety model

### 4.1 Consent
- One switch per relationship: sharing is on if and only if a presence row exists.
- The chat-settings "Share my location" toggle and the map chip are the same switch.
- **Symmetric by construction.** The partner's area is returned only when both of these are true:
  - *my* row exists, is fresh, and isn't paused;
  - *theirs* is the same.

### 4.2 Pause
- Pause sets `paused_until` (`infinity` for "until I resume") **and clears the stored cell and city**.
- While either partner is paused, neither sees the other. The server returns *no row*, exactly as if the data were stale, so even a modified client learns nothing.
- The device stops sampling while paused. No push, no reason, no log.
- **When a pause ends**, the area comes back **only with the next fresh sample**, at the next app open. If it came back on its own, "reappeared without moving" would reveal the pause.

### 4.3 No history
- Exactly one row per (user, relationship), overwritten on every update.
- None of the following, ever:
  - arrive or leave events;
  - counters;
  - "last seen at";
  - nudges;
  - timestamps on the device;
  - a "closing in" tone, which would need yesterday's distance, i.e. history.

### 4.4 Leaving and retention
- **Off** deletes my row silently.
- **The relationship ending or being archived** purges both presence rows and every story place, through a trigger.
- **Presence retention:** an hourly cron deletes presence rows older than 7 days.
- **Places** live as long as their story, unless the author uses Remove from map or Remove all my places.
- **Re-pairing** creates a new relationship row, which starts fresh: a new opt-in and no old places. This is a deliberate exception to Together's "re-pairing keeps history", and it applies to location data only.

### 4.5 Why exact story places aren't a trail
- The author chooses each one, with a preview first.
- The author can remove one, or all of them, for good.
- The partner sees only places the author chose.
- Nothing is backfilled.
- Unlinking purges them.
- The home-area warning protects the most sensitive place, and pinning defaults off while paused.

### 4.6 Scenarios

| Scenario | What each person sees |
|---|---|
| Living together | One shared circle, "Together · Accra". No movement is visible during the day, because of cells, hysteresis and sampling only on app open |
| Long distance | Two circles in two cities, the rounded distance, their local time, and a reunion countdown from the calendar |
| Dating, living apart | "Nearby" tone; circles about 1.6 km across; nobody can tell the street |
| One partner wants out, or a coercive dynamic | Off deletes silently; pause looks like stale; resuming needs a new sample; quick exit leaves the server alone; unlink purges; the other side never sees *why* it stopped |
| Travelling | The area updates on the next app open. The trip shows only through stories the author pinned |
| Phone off, or app not opened | The pin fades after 4 hours and disappears at 8. No times are shown |

### 4.7 Checked against our rules
- **Not a surveillance tool** ✓: about 1 km precision with hysteresis, no history, no timestamps, samples only on app open, symmetric.
- **Behavioural data is self-facing** ✓: both partners see the same kind of information. The only freshness signal is a coarse fade, with no times or patterns.
- **No evidence against a partner** ✓: no history to export, places can be removed, unlinking purges.
- **Discreet exit** ✓: the privacy cover and quick exit both apply, including the tile cache.
- **No cadence** ✓: no streaks, counters or nudges.

## 5. Data model

### 5.1 `presence_v2` (Phase 0)

**`partner_presence` changes**
- Add `relationship_id` (FK, cascade) and `paused_until timestamptz`.
- **The primary key becomes `(user_id, relationship_id)`.**
- Raw coordinates are replaced by `cell_lat` / `cell_lng`, `numeric(6,3)`. These hold the snapped cell centre and can be null: pause clears them, and they stay null when only the city is known.
- `timezone` holds an IANA name. A name not found in `pg_timezone_names` (for example web's abbreviation) is stored as NULL rather than rejected.
- Existing rows are cleared. Nothing renders them today, and users opt in again.
- Direct INSERT and UPDATE are revoked. The policy letting each user SELECT and DELETE their own row stays.

**`presence_snap_cell(lat, lng)`**
- An IMMUTABLE, deterministic grid of about 1 km.
- Latitude step: 0.01°.
- Longitude step: `0.01 / greatest(cos(band), 0.2)`, where `band` is the **snapped latitude band**. Using the band rather than the raw latitude keeps the longitude index from drifting within a band.

**Hysteresis.** `record_presence` keeps the stored cell unless the new raw point is more than 300 m outside it. GPS noise at a cell boundary therefore never flips the pin, which would reveal movement and app opens. The Dart mirror compares values after `numeric(6,3)` rounding.

**Accuracy.** `record_presence` takes `p_accuracy_m`. If accuracy is worse than 2 km (for example iOS approximate location), it stores the city only, with no cell.

**RPCs** (SECURITY DEFINER)
- `record_presence(rel, lat, lng, accuracy_m, city, country, country_code, tz)`: checks membership, applies hysteresis and snapping, does nothing while paused, then upserts.
- `set_presence_pause(rel, until)`: up to 8 hours, or `infinity`. NULL resumes. Pausing clears the cell and city.
- `stop_presence(rel)`: deletes the row.
- `couple_map_presence(rel)`:
  - Returns a `self` row, and a `partner` row only under §4.1.
  - Columns: `who, cell_lat, cell_lng, city, country, utc_offset_minutes, freshness`, plus the rounded `distance_km` and a `together` flag.
  - **No timestamp column ever leaves the server.**
  - Uses the shared helper `presence_pair_visible(rel, uid)`.
- `partner_distance(rel)` is **retired**. Its only remaining consumer, Planning's dual clock, moves to `couple_map_presence.utc_offset_minutes`.

**Cleanup**
- Trigger `presence_purge_on_relationship_close` fires only on a change to `status <> 'active'` or to `chat_archived_at IS NOT NULL`.
- Cron `presence_purge_stale` runs hourly and deletes rows older than 7 days.

### 5.2 `story_places` (Phase 2)

**Table `story_places`**
- Columns: `story_item_id` (PK, FK, cascade), `relationship_id`, `author_id`, `lat`/`lng` (`numeric(9,6)`), `label` (120 characters max), `created_at`.
- RLS: members of an open relationship can read. No direct writes.

**`create_story_item(..., p_place jsonb default null)`**
- In **one migration**:
  1. create the 9-argument function;
  2. drop the 8-argument one;
  3. re-issue REVOKE/GRANT;
  4. run `NOTIFY pgrst, 'reload schema'`.
- PostgREST resolves older apps' 8-parameter calls to the new function, since `p_place` defaults to null, so nothing needs to ship at the same time. Keeping both versions would make calls ambiguous (PGRST203).
- The place is added only on a fresh insert, never on a replay.
- **A malformed `p_place` is dropped and the story still posts.** Rejecting it with INVALID_INPUT would put the outbox into `failedPermanent`. The client also validates before enqueueing.

**Other RPCs**
- `clear_story_place(id)` and `clear_my_story_places(rel)`: author only.
- `delete_story_item` also removes the place.
- `list_story_places(rel, author?, min_lat, min_lng, max_lat, max_lng, limit 500)`:
  - SECURITY INVOKER, joined to `story_items`, so RLS and `deleted_at` apply.
  - The bounding box is required. The Phase 2 client asks for the world box (newest 500), since a couple's pins fit easily; the box stays for later viewport fetching.

The unlink trigger also purges `story_places`.

### 5.3 Fixes folded in
- **Time zones.** `record_presence` stores an IANA zone from `TimezoneUtils.getDeviceTimezone()`. This fixes Planning's dual clock and gives the partner's local time.
- **EXIF.**
  - Phase 0: the pure-Dart image fallback in `CaptureImagePreparer` and `ChatImagePreparer` clears EXIF before encoding.
  - Phase 3: video container metadata is stripped.

## 6. Client architecture

### 6.1 `lib/features/location/` (the presence kernel)
- `presence_repository.dart`: record, pause, resume, stop, remove all my places, and fetch map presence, all through the RPCs.
- `presenceStateProvider`: off, sharing, or paused until a time.
- `partnerDistanceWithReunionProvider`: extracted from `partner_distance_row.dart`.
- **Sampling happens only while `presenceStateProvider` is "sharing"**, on tab open and on app resume via `AppLifecycleListener`. Nobody who hasn't opted in is ever asked for location.
  - It uses **`LocationAccuracy.medium`** (~100 m, Wi-Fi/cell, never GPS). Android's `low` is city-level (~10 km) and would rarely pass the 2 km cutoff; the server snaps to a ~1 km cell either way.
  - It sends `accuracy_m` with each sample.
- **Callers to migrate in Phase 0:**
  - `isSharingPresenceProvider` becomes `presenceStateProvider(rel)`.
  - The `chat_settings_static_rows.dart` toggle, which is disabled while there's no conversation.
  - `dual_clock_block_view.dart` switches to `utc_offset_minutes` and drops the `planningTimezoneOffsetProvider` hop.
  - The override in `test/features/planning/support/planning_test_app.dart`.
  - `location_wiring_test.dart`, which checks source strings, is rewritten to the new contract.
  - `DistanceTone.closing` and `kmClosedSinceYesterday` are removed.

### 6.2 `lib/features/couple_map/` (new)
- **domain/:** the map cell (mirrors the server's snapping, for tests), story place, and map state.
- **data/:** `story_places_repository.dart`.
- **presentation/providers/couple_map_providers.dart:** `storyPlacesProvider(StoryPlacesKey(rel))`, refetched on `storyChangeSignalProvider`; Mine / Partner's are filtered on the client from that one fetch (amended in Phase 2).
- **The map sits behind a seam, `CoupleMapController`**, with `setStyle`, `setPresence`, `setStories`, `fitTo`, `zoomBy` and story taps (`onStoriesTapped`).
  - `mapbox_couple_map_view.dart` uses `mapbox_maps_flutter` 2.24.
  - Story features go in a clustered `GeoJsonSource`. The filter rebuilds the source data, so cluster counts stay right.
  - The two avatars are point annotations rendered to `Uint8List`. The areas are a `FillLayer`.
  - Taps are found with `queryRenderedFeatures`.
  - A fake map view in `test/` records calls.
- **Widgets:** `glass_icon_button`, `sharing_chip`, `sharing_sheet`, `distance_card`, `couple_map_list_sheet`, `pin_image_renderer` (canvas to PNG, cached).
- **Screen:** `couple_map_tab`, added as the third tab in `planning_home_screen.dart`.

### 6.3 Mapbox setup
- Call `MapboxOptions.setAccessToken(Environment.mapboxAccessToken)` (from `lib/core/config/env.dart`) at bootstrap.
- Restrict the token to the app's bundle IDs.
- **Turn telemetry off.**
- **Never enable** the location component (the "you are here" puck), because it would draw your raw position.
- A Phase 0 spike confirms the iOS and Android builds. `mapbox_maps_flutter` is declared today but unused.
- **Dark mode:** the pin renderer and glass buttons take explicit theme tokens. Satellite ignores the theme by design.

### 6.4 Stories
- `StoryOutboxRecord` gains nullable place fields. `fromJson` tolerates them being absent, for records already queued.
- `finalizeStory` sends `p_place`.
- **The camera switch:**
  - Saved preference `story_pin_last_choice`, default off.
  - Starts off while paused or when near home.
  - The label is previewed only after the switch is turned on.
- New `StoryReelScreen.forPlaces` (named `forItems` in the first draft).

## 7. Phases

| # | What ships | Risk | Status |
|---|---|---|---|
| 0 Foundations | `presence_v2` with contracts; repository on RPCs; caller migration; IANA fix; 8-hour staleness; purge trigger and cron; EXIF image fix; Mapbox build spike | Existing presence rows are cleared (they aren't shown anywhere today) | Built; Fable fixes applied |
| 1 Map tab (presence) | Third tab; Mapbox view behind the seam; areas; style toggle; distance card; chip and sharing sheet; list sheet; empty states; dark mode | Mapbox token and build; blur performance | Built; Fable fixes applied |
| 2 Story places | `story_places` with contracts; pin switch and preview; **home-area warning**; outbox and finalize changes; clustered pins and filter; reel over a list; Remove from map; Remove all my places | Thumbnail fetch volume (500 cap, cached) | Built; Fable fixes applied |
| 3 Polish | Video metadata strip; accessibility audit; the September spec's §2 marked as replaced | Low | Built; Fable fixes applied |

Each phase gets its own plan and runs TDD on `main`. A Fable review and one fix pass follow each phase.

## 8. Verification

**SQL contracts** (run on the PG17 stub harness)
- `couple_map_presence_contracts.sql`:
  - symmetry;
  - pause looks the same as stale;
  - **resuming with no new sample returns no partner row**;
  - the 8-hour rule;
  - **no timestamp column leaves the server**;
  - deterministic snapping, and hysteresis;
  - accuracy worse than 2 km stores the city only;
  - raw coordinates are never stored;
  - the purge trigger fires only on close;
  - an outsider gets nothing.
- `story_places_contracts.sql`:
  - only the author can set or clear a place;
  - the partner can read places;
  - a deleted story hides its place;
  - a malformed place still posts the story;
  - no backfill;
  - the bounding-box cap;
  - the unlink purge;
  - "remove all" removes only my places.
- Mutation checks on the key rules.

**Flutter tests**
- **Unit tests:**
  - the snapping mirror and hysteresis;
  - freshness rendering;
  - distance rounding;
  - card segments;
  - the filter cycle;
  - outbox JSON, both with and without place fields;
  - no EXIF in output.
- **Widget tests with the fake map:**
  - three tabs;
  - chip states, including location turned off;
  - the sharing sheet calls the right RPCs;
  - the filter rebuilds the features;
  - tapping a pin opens the reel;
  - the list sheet, and the offline fallback;
  - one neutral line for every reason on the partner's side;
  - no sampling and no permission prompt when not sharing.

**Manual testing on two devices**
- Opt in and out.
- Pause from each side, and check that resuming shows nothing until the next app open.
- The unlink purge.
- Pin and unpin a story; Remove all my places.
- The home-area warning.
- iOS approximate location (Precise off) and Android coarse location.
- Dark mode.
- Quick exit, including the tile cache.

## 9. Algorithm Quality Review Checklist v3.1

Scope tags: `[ALL]`, `[SERVICE]` (the RPCs), `[MUTATION]`, `[ASYNC]` (the purge cron), `[UI]`, `[MOBILE]`. Skipped tags: `[FIN]` (no money involved) and `[UI-WEB]` (native mobile only, so 7.6 doesn't apply). Each phase's plan carries the evidence for its own items.

**Blocking (P0-U / P0-C)**

| # | How this design meets it | Evidence |
|---|---|---|
| 1.4 Authorization at every access | Every RPC re-checks membership of an open relationship via `presence_pair_visible` or `story_relationship_is_open` before touching any row. `list_story_places` is SECURITY INVOKER, so RLS applies on top. No table allows direct writes. | Contract tests: outsiders, ex-partners and anonymous callers get nothing |
| 1.5 Authentication | `auth.uid()` is required in every RPC; anonymous callers have EXECUTE revoked | Contract test: anon EXECUTE is denied |
| 2.1 Input sanitisation | Server-side checks on lat/lng ranges, `accuracy_m ≥ 0`, label at most 120 characters, a pause of at most 8 h or infinity, an IANA time zone (otherwise NULL), and a required, capped bounding box. Malformed values are dropped, never fatal to the story. | Contract tests for each bound; Dart tests for client-side validation |
| 2.2 Parameterised queries | PL/pgSQL only, with no dynamic SQL; the client uses PostgREST RPC parameters | Review; grep finds no `EXECUTE format` |
| 2.3 Constant-time secrets | Not applicable: no secrets are compared (the Mapbox token is only sent to Mapbox) | Skip noted |
| 2.4 Errors don't leak | RPCs raise only coded errors; the client maps every failure to plain copy ("Couldn't update your area. Try again.") | Widget tests trigger the failures |
| 2.5 Per-request resource limits | `list_story_places` caps at 500 rows with a bounding box; presence is at most 2 rows; pin images are cached with a size limit | Contract test for the cap |
| 2.6 Output sanitisation | Labels are rendered as plain `Text` and never interpolated into HTML or SQL | Review |
| 2.7–2.9 Secrets | The Mapbox token comes from `Environment` (`--dart-define` or gitignored `.env.json`), restricted to the app's bundle IDs; nothing is hard-coded | Secret scan; `.gitignore` check |
| 2.10 Resources released | Location streams, timers and the map controller are disposed with their widget or provider; the `AppLifecycleListener` is disposed | Widget tests dispose and verify; a leak check during the soak |
| 4.4 No PII in logs | **GPS coordinates, place labels and city names are never logged** on the client or the server. Logs carry only user and relationship UUIDs and error categories. | grep check plus a test that `LocationService` errors are logged without coordinates |
| 5.5 Nothing internal in the UI | Plain copy only, with no IDs or stack traces | Widget tests |
| 7.1–7.3 Dependency, SAST and secret scans | `mapbox_maps_flutter` 2.24 is checked for CVEs; `flutter analyze` (the line-start filter for errors and warnings) is clean on touched files; secret scan | Each phase's evidence |
| 7.5 TLS | Supabase and Mapbox are HTTPS only | Platform default |

**Required before merge (P1)**

| # | How |
|---|---|
| 1.1 / 2.18 Idempotency | `record_presence` is an upsert on `(user_id, relationship_id)`, so a repeated call has the same effect. Pause and stop are idempotent. `create_story_item` keeps its client id, and its replay path never touches places. `clear_*` are idempotent deletes. |
| 1.2 Timeouts | Location fix 20 s, on-device geocode 10 s, RPCs use the existing client timeout, Mapbox style load fails over to the list sheet |
| 1.6 / 2.16 Concurrency | One row per key with `ON CONFLICT DO UPDATE`, which is atomic. The two partners write separate rows. Pause racing with a record: `record_presence` checks `paused_until` inside the same statement. The purge trigger runs in the closing transaction. |
| 1.10 Rollback | Each RPC runs in a single transaction. The story place is inserted in the same transaction as the story. |
| 1.11 Privacy and retention | PII here is approximate cells, city, IANA zone, exact story places and labels. Presence rows are deleted after 7 days of staleness; places live with their story and are purged when the relationship closes. The data flow is in §4–§5. |
| 2.12–2.15 Bounded work | The pin image cache has a bounded LRU (64 entries); no unbounded loops; sampling is debounced to app open or resume |
| 3.10 No retrying permanent errors | Validation and authorisation errors aren't retried; the outbox keeps its classification |
| 6.1 Edge cases | Cell snapping at the poles, the antimeridian (±180) and the equator; latitude bands where cos(lat) falls to 0.2; DST changes in the offset; NULL time zone; accuracy exactly 2 km; a pause of exactly 8 h |
| 6.3 Concurrency tests | A two-session SQL test: pause and record racing, and both partners recording at once |
| 6.4 Negative tests | No partner row while paused or stale; no row after stop; no place after a failed or malformed post; a purge leaves nothing behind |
| 7.4 Least privilege | Direct INSERT/UPDATE are revoked; the RPCs are SECURITY DEFINER with `search_path` pinned; only `authenticated` gets EXECUTE |
| 7.7 Continuous scanning | Uses the repo's existing CI scans |
| 8.1 Rollback procedure | Tier 2: client changes ship behind the existing feature flag `couple_map_enabled` (default off), and SQL rollback is a down-migration with documented commands |
| 8.2 Smoke test | A post-deploy SQL smoke test: a fixture couple records, reads and pauses |

**Required before production (P2), where applicable**
- **1.3 Graceful degradation:** location denied, then a chip state; Mapbox down, then the list sheet; RPC failure, then the last good value with plain copy.
- **1.7 State:** stored in the database; the client holds no state beyond caches.
- **1.8 Complexity:** presence O(1); places O(k) for k ≤ 500 per bounding box; cell snapping O(1).
- **1.9 Consistency:** read-your-writes for your own row; the partner's view is eventually consistent within the 8 h staleness window.
- **3.1 Pagination:** the bounding box plus the 500-row cap.
- **3.3 Indexes:** the presence primary key; `story_places (relationship_id, lat, lng)`; EXPLAIN is attached to the Phase 0 and Phase 2 plans.
- **3.4 Cache:** a pin-image LRU keyed by thumbnail key. Signed URLs are not cached, following stories' existing rule.
- **3.7 / 3.8 Rate limiting:** `record_presence` ignores calls within 60 s of the last stored update for the same key. The client also debounces.
- **3.9 Retry:** the outbox keeps its existing backoff; presence doesn't retry (the next app open covers it).
- **4.1 / 4.5 Logs:** structured, at the right level, with no PII (4.4).
- **4.11 Configuration:** staleness 4 h / 8 h, hysteresis 300 m, accuracy cutoff 2 km, retention 7 days, rate limit 60 s and cap 500 are all named constants (SQL `presence_config()` and Dart `CoupleMapConfig`).
- **5.1 / 5.2 UX:** actionable copy everywhere; the map shows its loading state within 200 ms, and the distance card fills progressively.
- **6.2 Failure tests:** location timeout, permission denied, RPC error, Mapbox load failure.
- **6.7 Branch coverage:** domain ≥ 90% (snapping, freshness, rounding, copy), repositories ≥ 70%, widgets ≥ 50% via `flutter test --coverage`.
- **6.10 Soak and 6.11 load** (`[ASYNC]`/`[SERVICE]`): the purge cron is EXPLAINed and bounded by index; there is no long-running service. Justified as not applicable beyond that, because Supabase manages the service.

**Backlog (P3), noted**
- **6.5 Property tests:** "snap(snap(x)) == snap(x)" and "hysteresis never moves the cell for jitter ≤ 300 m".
- **6.8 Mutation checks:** on the key SQL rules, as already done for Together.
- **5.6 Accessibility:** the list sheet and labels; an audit in Phase 3.

## 10. Review log

**Fable adversarial review (2026-10-15).** Every finding was applied.
- **Critical:**
  - the green dot read as "last seen";
  - the end of a pause could be detected;
  - jitter at cell boundaries leaked movement;
  - the "closing" tone needed history;
  - one server answer was shown with two different copies.
- **Important:**
  - precise GPS and unconditional permission prompts;
  - Mapbox telemetry, the location puck, and the tile cache;
  - home pins would have shipped before the home warning;
  - an invalid place could kill a story;
  - the overload claim was backwards;
  - gaps in Phase 0 callers and contracts;
  - the web time zone;
  - the label preview's geocoding call;
  - places formed a permanent trail;
  - re-pairing.
- **Minor:**
  - the reel has no overflow menu;
  - the circle was smaller than a cell;
  - the "together" threshold;
  - retiring `partner_distance`;
  - retention cadence;
  - the offline state;
  - dark mode tokens.

**Implementation reviews (2026-10-15 to 10-18).** Each phase was built test-first on `main` (uncommitted) and reviewed by Fable:
- **Phase 0:** 0 Critical, 7 Important, all fixed.
- **Phase 1:** 0 Critical, 4 Important plus 1 re-graded, all fixed.
- **Phase 2:** 1 Critical and 4 Important, all fixed. The Critical was a pinned story losing its place when the camera pill hid.
- **Phase 3:** fixes recorded in its ledger.

Minors and owner-decision findings are listed in each phase's ledger under `.superpowers/sdd/`.
