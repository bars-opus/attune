# Stories Wave 4: Rings and Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Conversations story rings and the calendar's story surfaces correct, fresh and private:
- every tap reaches the control under it;
- thumbnails are cached by storage key and removed when a story or a relationship goes;
- the rings never flash, go stale or look empty when offline;
- calendar rings open the right author's stories, with whole-day counts and visible errors.

**Architecture:** Client only. No migrations in this wave.
- **Caching.** One in-memory signed URL per storage key, reused for up to 540 s, replaces URL-keyed caching. Image bytes sit in the shared disk cache under the storage key.
- **Ring summary provider.** It gains:
  - a pager-style in-flight coalescer;
  - a timer that only fires while Attune is on screen, used for both backoff retries and expiry;
  - a last-known snapshot kept on this device;
  - a short "posted" hold that covers the gap between finalize and the next summary.
- **Day reel.** It learns an author filter, so each calendar ring plays only its own author's stories.

**Tech Stack:** Flutter, Riverpod 2.6.1 (`StateNotifier`, `FutureProvider.autoDispose.family`), cached_network_image 3.3.1 with flutter_cache_manager 3.3.1 (`DefaultCacheManager` through `ChatImageCache`), flutter_secure_storage, package:clock, flutter_test.

**Spec:** `docs/reviews/2026-10-23-stories-robustness-review.md` (Wave 4), with:
- `docs/reviews/2026-10-23-stories-review/03_rings.md` (H1, M1–M6, L1–L7);
- `04_lifecycle_memories.md` #4, #5, #6, #15;
- `05_security_privacy.md` #6;
- `06_standards_checklist.md` #16, #17, #20;
- `07a_verification_client.md` V10 and groups E and H.

Binding product spec: `lib/architecture/STORIES.md` §4.1, §5.1, §5.3, §5.5. Task 14 amends it.

## Global Constraints

- **Where to work.** The main working tree, on `main`.
  - The tree holds the user's own uncommitted edits plus the uncommitted Waves 1–3. Never revert, stage, stash, check out or reformat any of them.
  - **No commits.** Each task ends by running its tests.
- **Formatting.** Never run `dart format` on a file that existed before this plan; the repo uses an older formatter. Run `dart format <path>` only on files this plan creates.
- **Files that already carry uncommitted Wave 1–3 edits.** Edit these surgically and keep every existing change:
  - `story_reel_screen.dart`, `story_providers.dart`, `story_rings_row.dart`;
  - `story_outbox_controller.dart`, `story_outbox_notices.dart`, `story_outbox_wipe.dart`, `story_media_vault.dart`;
  - `reel_test_kit.dart`, `story_rings_test.dart`, `story_calendar_test.dart`;
  - `lib/architecture/STORIES.md`.
- **Tests first.** Write each test, run it, and see it fail for the stated reason before implementing.
- **UI standards.**
  - Use design tokens: `Spacing`, `IconSizes`, `Theme.of(context).colorScheme` / `theme.appColors`.
  - Any displayed date goes through `MyDateFormat`. None is planned.
  - Every tap target is at least 48 dp, and every control has semantics.
- **Libraries.** Riverpod only. No new dependencies: `cached_network_image`, `flutter_cache_manager`, `flutter_secure_storage` and `clock` are already direct dependencies.
- **Server.** No server migrations; they belong to Wave 5. No SQL is needed. If any check ever is, run it only against local `attune_spec3a`, never `attune_test`.
- **Goldens.** `test/features/stories/goldens/story_rings_{light,dark}.png` change only in Task 1 and Task 2. Regenerate them with `--update-goldens`, then open and look at them.
- **Signed URLs.** Never write them to disk. Reuse one for at most 540 s, in memory (`kStoryUrlReuseWindow`).
- **Timers in tests.** A `testWidgets` test that builds a bare `ProviderContainer` must close its subscriptions and call `container.dispose()` as the last line of the test body, not in `addTearDown`. The binding checks for pending timers before tear-downs run.
- **End state.** The whole suite (`flutter test`) passes, and `flutter analyze` is clean on every touched file.

## Rulings made in this plan (owner may override)

1. **K1 geometry.**
   - My ring keeps its 69 dp look. Its box grows to 83 dp on the end and bottom sides.
   - The `+` gets a 48 dp target centred on the drawn badge.
   - Inside the photo circle the reel wins, except within 14 dp of the badge's centre.
   - The gap to the partner ring shrinks by 14 dp, so the partner ring does not move.
   - Calendar rings no longer draw the inert `+`.
2. **E: thumbnail bytes.**
   - The bytes stay in the shared `DefaultCacheManager`, keyed by storage key. This is how chat and the couple map already work. Eviction and clearing go through the hardened `ChatImageCache`.
   - There is no dedicated cache manager: one would need a second test-safe store wrapper.
   - Quick exit and a relationship's pause, end or archive empty the shared image cache. Chat photos re-download once, which is a privacy-positive cross-feature change.
   - Sign-out already empties it.
3. **E: signed URLs.**
   - One signed URL per key, in memory, shared by the rings and the calendar for up to 540 s.
   - It is forgotten on account change, sign-out, quick exit, lifecycle change and delete.
   - It is never written to disk. STORIES.md §4.1 is amended.
   - Batch-signing a month's keys (`createSignedUrls`) is not done.
4. **M2 expiry.**
   - The client re-reads 1 s after the newest story's 24 h end (`newest_created_at + 24h`).
   - When the server gives an optional `next_expires_at`, it is used instead. Until Wave 5 returns it, a count drop from an older story's expiry waits for the next signal or resume.
5. **L6 coalescing.**
   - One fetch in flight per relationship, with at most one follow-up: the pager's F3 scheme, with no debounce timers.
   - This keeps the existing "signal re-reads at once" tests valid and adds no latency.
6. **M3 offline.**
   - The last-known summary (ids, counts and storage keys only) is kept in this device's keychain (`first_unlock_this_device`) or Android's encrypted prefs. The Android file is already excluded from backups.
   - It is shown while loading and after a failed load. A failed load also shows a Retry notice.
   - Pull-to-refresh on Conversations is **deferred** (owner call): it would wrap the reorderable home cards.
7. **M1.**
   - A "posted" hold, in memory, carries the posted thumbnail's bytes.
   - It lasts until a ring summary fetched after finalize lands, capped at 2 min.
8. **04 #4.**
   - The day reel gains `dayAuthorId`, a client-side filter. Wave 5's `p_author_id` would replace it.
   - The partner's day ring opens at their first story the viewer has not seen that day (the oldest when all are seen). My day ring opens at my oldest. STORIES.md §5.5 is amended.
9. **Day sheet counts.**
   - The union of `list_story_day_counts`, which is authoritative beyond page one, and the loaded items.
   - The larger count per author wins.
   - Unviewed counts come from the loaded items only.
10. **L2 copy.** The copy lives in `story_ring_copy.dart`. Extracting it to l10n stays on the existing open l10n gate (there is no l10n infrastructure yet).
11. **M6.**
    - Outbox records for any relationship other than the one shown surface as one grouped notice with Discard (and no Retry).
    - The notice also shows on Conversations when there is no active relationship.

## Review Focus

These are the inputs a person will hit that no spec line names, most likely first. Each has a test in the task that owns the code.

1. **The phone's clock is minutes ahead of or behind the server at a story's 24 h mark.** The ring drops the story within about a minute of server expiry, and never loops on refetches. Test: Task 5, "a phone clock ahead of the server re-checks each minute, then stops".
2. **A last-known snapshot from another account or relationship.** This happens on a shared phone, or after a new relationship follows an ending. It is never painted. Test: Task 6, "a snapshot from another account or relationship is never shown".
3. **Taps right at the photo and `+` boundary, in RTL, and on the posting ring.** Every tap reaches exactly one control: the photo's owner wherever the badge isn't drawn. Test: Task 1, the grid tests.
4. **A burst of change signals and per-item invalidations during one slow ring fetch.** At most one follow-up RPC. Test: Task 5, "a burst of signals during a slow ring fetch costs one more call".
5. **A thumbnail key whose signing always fails,** for example a story deleted under a mounted ring. Retries are bounded, then stop; never a tight loop. Test: Task 3, "a key whose signing fails is retried on a backoff, then left alone".

## File map

**Create:**
- `lib/features/stories/domain/story_ring_copy.dart`: ring labels and short copy.
- `lib/features/stories/domain/story_day_rings.dart`: per-author day rings, plus day-count thumbnail drops.
- `lib/features/stories/data/story_signed_url_cache.dart`: in-memory URL reuse and sign backoff.
- `lib/features/stories/data/story_ring_last_known_store.dart`: the snapshot, the secure and memory stores, and their provider.
- `lib/features/stories/data/story_device_wipe.dart`: `clearStoryDeviceCaches`.
- `lib/features/stories/presentation/providers/story_visible_refresh.dart`: re-runs a provider on a timer, only while Attune is on screen.
- `lib/features/stories/presentation/state/story_ring_refresh.dart`: the coalescer, expiry and retry timing, and dropped keys.
- `lib/features/stories/presentation/state/story_posted_hold.dart`: the posted hold.
- `lib/features/timeline/presentation/widgets/story_month_load_error.dart`: the month error row.

**Modify:**
- Story widgets and providers:
  - `story_ring.dart`;
  - `story_rings_row.dart`;
  - `story_outbox_notices.dart`;
  - `story_providers.dart`;
  - `story_reel_screen.dart`.
- Story data and state:
  - `story_read_repository.dart` (`StoryRingSummary`, `kStoryLifetime`);
  - `story_media_vault.dart`;
  - `story_outbox_controller.dart`;
  - `story_outbox_wipe.dart`.
- Timeline widgets: `calendar_day_sheet.dart`, `calendar_day_indicators.dart`, `calendar_strip.dart`.
- Elsewhere:
  - `conversations_screen.dart` (one line);
  - `quick_exit_service.dart`;
  - `relationship_lifecycle_providers.dart`;
  - `STORIES.md`.

**Tests (new):** under `test/features/stories/`, unless marked:
- `support/ring_test_kit.dart`;
- `story_ring_hit_test.dart`, `story_ring_copy_test.dart`;
- `story_signed_url_cache_test.dart`, `story_ring_thumbnail_test.dart`;
- `story_ring_refresh_test.dart`, `story_ring_last_known_test.dart`;
- `story_posted_hold_test.dart`, `story_orphaned_posts_test.dart`;
- `story_device_wipe_test.dart`, `story_reel_day_author_test.dart`;
- `story_day_rings_test.dart`, `story_reel_delete_coherence_test.dart`;
- `test/features/timeline/calendar_day_sheet_stories_test.dart`;
- `test/features/timeline/story_month_load_error_test.dart`.

## Pre-flight (no code)

- [ ] Run a baseline:

```bash
cd /Users/user/attune && flutter test test/features/stories test/features/timeline test/features/safety test/features/relationships test/features/couple_map 2>&1 | tail -5
```

Expected: all pass. Write down any failure already present, so it is never blamed on this wave.

---

### Task 1: My ring's photo opens my reel; the `+` has its own 48 dp target (K1, L4 mirror)

Fixes: 03 H1, 07a V10 (group H), and 03 L4 for the badge.

**Files:**
- Modify: `lib/features/stories/presentation/widgets/story_ring.dart`:
  - `StoryRing.build` and `_PlusBadge`;
  - new constants;
  - `showPlusBadge`, `storyPlusTargetContains` and `_PlusHitShape`.
- Modify: `lib/features/stories/presentation/widgets/story_rings_row.dart`: the ring row's height, cross-axis alignment and gap.
- Modify: `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart` (`_AuthorDayRing`, and the height of the ring list).
- Create: `test/features/stories/story_ring_hit_test.dart`
- Modify: `test/features/stories/story_rings_test.dart` (a new group, and regenerated goldens).
- Modify: `test/features/timeline/calendar_day_indicators_test.dart` (one new test).

**Interfaces:**
- Consumes: nothing new.
- Produces (in `story_ring.dart`):

```dart
const double kStoryRingOuterDiameter; // 69: photo + gap + stroke, both sides
const double kStoryRingBadgeDiameter; // 20: the drawn corner +
const double kStoryRingBadgeSlop;     // 14: on the badge, the + wins over the photo
const double kStoryRingPlusOverhang;  // 14: my ring's box past the ring, end and bottom
const double kStoryRingMineExtent;    // 83: the square my ring occupies with the +
bool storyPlusTargetContains(Offset local, {required TextDirection direction});
// StoryRing gains: final bool showPlusBadge; (default true; only used when isMine)
// ValueKeys: 'story-ring-visual' (the 69 dp ring), 'story-ring-plus-target' (48 dp),
//            'story-ring-plus-visual' (the drawn badge)
```

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_ring_hit_test.dart`:

```dart
// K1 (03 H1, 07a V10): on my own ring the photo opens my reel and only the
// `+` opens the camera. The `+` keeps a 48 dp target, hung outside the
// photo; inside the photo circle the reel wins except right on the badge.
//
// Geometry in dp from the ring's leading top corner (the ring is 69 dp: a
// 56 dp photo, 3 dp gap, 3.5 dp stroke): photo centre (34.5, 34.5), radius
// 28; badge centre (59, 59), drawn 20 dp, slop 14 dp; the badge's 48 dp
// target spans 35..83 on both axes. Literals on purpose: this file compiles
// and fails against the old layout.
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> _pumpMine(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  double? pendingProgress,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(40),
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: StoryRing(
                isMine: true,
                hasStories: true,
                segmentCount: 3,
                unviewedCount: 3,
                pendingProgress: pendingProgress,
                onTap: () => taps.add('reel'),
                onTapPlus: () => taps.add('camera'),
                semanticLabel: 'Your story, 3 items',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return taps;
}

/// Who must own a tap at [p] (leading-corner coordinates), or null within
/// about a dp of a boundary, where either answer is acceptable.
String? _owner(Offset p) {
  const photo = Offset(34.5, 34.5);
  const badge = Offset(59, 59);
  final toPhoto = (p - photo).distance;
  final toBadge = (p - badge).distance;
  final inTarget = p.dx > 36 && p.dx < 82 && p.dy > 36 && p.dy < 82;
  if (toBadge < 13) return 'camera';
  if (toPhoto < 27 && toBadge > 15) return 'reel';
  if (inTarget && toPhoto > 29) return 'camera';
  if (p.dx < 68 && p.dy < 68 && (p.dx < 34 || p.dy < 34)) return 'reel';
  return null;
}

Future<void> _expectEveryTapOwned(
  WidgetTester tester,
  List<String> taps,
  TextDirection direction,
) async {
  final rect = tester.getRect(find.byType(StoryRing));
  final rtl = direction == TextDirection.rtl;
  final wrong = <String>[];
  var reel = 0;
  var camera = 0;
  for (var y = 1.0; y < 83; y += 3) {
    for (var x = 1.0; x < 83; x += 3) {
      final want = _owner(Offset(x, y));
      if (want == null) continue;
      taps.clear();
      final at = rtl
          ? Offset(rect.right - x, rect.top + y)
          : Offset(rect.left + x, rect.top + y);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 1));
      final got = taps.isEmpty ? 'nothing' : taps.join(',');
      if (got != want) wrong.add('($x, $y): wanted $want, got $got');
      if (want == 'reel') {
        reel++;
      } else {
        camera++;
      }
    }
  }
  expect(wrong, isEmpty, reason: wrong.take(12).join('\n'));
  expect(reel, greaterThan(100));
  expect(camera, greaterThan(40));
}

void main() {
  testWidgets('a tap in the middle of my photo opens my reel, not the camera', (
    tester,
  ) async {
    final taps = await _pumpMine(tester);
    await tester.tapAt(
      tester.getTopLeft(find.byType(StoryRing)) + const Offset(34.5, 34.5),
    );
    expect(taps, ['reel']);
  });

  testWidgets('a tap on the drawn + opens the camera', (tester) async {
    final taps = await _pumpMine(tester);
    await tester.tapAt(
      tester.getTopLeft(find.byType(StoryRing)) + const Offset(59, 59),
    );
    expect(taps, ['camera']);
  });

  testWidgets('every tap on my ring reaches exactly the control under it', (
    tester,
  ) async {
    final taps = await _pumpMine(tester);
    await _expectEveryTapOwned(tester, taps, TextDirection.ltr);
  });

  testWidgets('right to left, the + and its target mirror (Review Focus 3)', (
    tester,
  ) async {
    final taps = await _pumpMine(tester, direction: TextDirection.rtl);
    await _expectEveryTapOwned(tester, taps, TextDirection.rtl);
  });

  testWidgets('the posting ring routes taps the same way (Review Focus 3)', (
    tester,
  ) async {
    final taps = await _pumpMine(tester, pendingProgress: 0.4);
    await _expectEveryTapOwned(tester, taps, TextDirection.ltr);
  });

  testWidgets('the + and the ring are separate buttons; the + is 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpMine(tester);
    final plus = tester.getSemantics(find.bySemanticsLabel('Add to your story'));
    final ring = tester.getSemantics(find.bySemanticsLabel('Your story, 3 items'));
    expect(plus.rect.size, const Size(48, 48));
    expect(ring.rect.size, const Size(69, 69));
    expect(plus.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(ring.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}
```

In `test/features/stories/story_rings_test.dart`, add this group inside `main()`, after the group `'the + badge has its own semantics node…'`:

```dart
  group('both callbacks wired (07a V10)', () {
    testWidgets('the photo opens my reel and the + opens the camera', (
      tester,
    ) async {
      var reel = 0;
      var camera = 0;
      await tester.pumpWidget(
        await _harness(
          noThumbnails: true,
          summary: [_summary(authorId: _myId, activeCount: 2, unviewedCount: 2)],
          onOpenMine: () => reel++,
          onCapture: () => camera++,
        ),
      );
      await tester.pumpAndSettle();
      final corner = tester.getTopLeft(
        find.byKey(const ValueKey('story-ring-mine')),
      );
      await tester.tapAt(corner + const Offset(34.5, 34.5));
      expect((reel, camera), (1, 0));
      await tester.tapAt(corner + const Offset(59, 59));
      expect((reel, camera), (1, 1));
    });

    testWidgets('the partner ring stays 85 dp after mine, tops aligned', (
      tester,
    ) async {
      await tester.pumpWidget(
        await _harness(
          noThumbnails: true,
          summary: [
            _summary(authorId: _myId, activeCount: 2, unviewedCount: 2),
            _summary(authorId: _partnerId, activeCount: 1, unviewedCount: 1),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final mine = tester.getTopLeft(find.byKey(const ValueKey('story-ring-mine')));
      final theirs = tester.getTopLeft(
        find.byKey(const ValueKey('story-ring-partner')),
      );
      expect(theirs.dx - mine.dx, 85);
      expect(theirs.dy, mine.dy);
    });
  });
```

In `test/features/timeline/calendar_day_indicators_test.dart`, inside `group('CalendarDaySheet', …)`, add:

```dart
    testWidgets('my ring on a past day draws no + (a capture would post today)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final gateway = _FakeGateway(dayItems: [_item(id: 's1', authorId: _myId)]);
      await tester.pumpWidget(
        _wrap(
          CalendarDaySheet(
            relationshipId: _relationshipId,
            date: _day,
            events: const [],
            reminders: const [],
            planningEntries: const [],
          ),
          gateway,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Add to your story'), findsNothing);
      handle.dispose();
    });
```

- [ ] **Step 2: Run them and watch them fail.**

```bash
flutter test test/features/stories/story_ring_hit_test.dart test/features/stories/story_rings_test.dart test/features/timeline/calendar_day_indicators_test.dart
```

Expected: FAIL.
- "a tap in the middle of my photo": `['camera']`.
- The three grid tests list wrong taps; points past 69 dp get "nothing".
- The rings-row test: `(0, 1)`.
- The calendar test finds the `+`.
- The tests for "the drawn +", the semantics sizes and the 85 dp spacing already pass. They are guards.

- [ ] **Step 3: Implement the geometry in `story_ring.dart`.**

Add `import 'package:flutter/rendering.dart';`. Under `kStoryRingMaxSegments`, add:

```dart
/// The ring's own square: the photo, the gap and the stroke on each side.
const double kStoryRingOuterDiameter =
    kStoryRingThumbnailDiameter + 2 * (kStoryRingGap + kStoryRingStrokeWidth);

/// The drawn corner `+` on my ring.
const double kStoryRingBadgeDiameter = 20;

/// Within this distance of the badge's centre a tap is the badge's, even
/// over the photo: the drawn `+` and 4 dp.
const double kStoryRingBadgeSlop = kStoryRingBadgeDiameter / 2 + 4;

/// How far my ring's box reaches past the ring on the end and bottom
/// sides, so the `+`'s 48 dp target (centred on the drawn badge) lies
/// mostly outside the photo (07a V10).
const double kStoryRingPlusOverhang =
    kMinInteractiveDimension / 2 - kStoryRingBadgeDiameter / 2;

/// The square my ring occupies when it draws the `+`.
const double kStoryRingMineExtent =
    kStoryRingOuterDiameter + kStoryRingPlusOverhang;

/// Whether [local], a point in the `+` target's own 48 dp box, belongs to
/// the `+` (07a V10). On the drawn badge it always does; over the photo it
/// does not, so the photo opens the reel; elsewhere in the box it does.
bool storyPlusTargetContains(Offset local, {required TextDirection direction}) {
  const box = kMinInteractiveDimension;
  if (local.dx < 0 || local.dy < 0 || local.dx > box || local.dy > box) {
    return false;
  }
  const badge = Offset(box / 2, box / 2);
  if ((local - badge).distance <= kStoryRingBadgeSlop) return true;
  // The target starts 35 dp into the ring on both axes, so the photo's
  // centre sits half a dp before the box (mirrored right to left).
  const inset = kStoryRingOuterDiameter / 2 - (kStoryRingMineExtent - box);
  final photo = Offset(
    direction == TextDirection.ltr ? inset : box - inset,
    inset,
  );
  return (local - photo).distance > kStoryRingThumbnailDiameter / 2;
}
```

Add the field and parameter to `StoryRing`. Put `this.showPlusBadge = true,` after `this.onTapPlus,` in the constructor, then add the field:

```dart
  /// Draws my `+` (only when [isMine]). The calendar passes false: a past
  /// day's ring has no camera, and a drawn `+` that does nothing misleads.
  final bool showPlusBadge;
```

Replace the whole `build` method of `StoryRing` with:

```dart
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion = reduceMotionOf(context);

    // Mine, empty: the outline (or the posting sweep) with the `+` in the
    // middle. The `+` is the whole control, so there is no ring button to
    // label (a second node with the same label read it twice).
    if (isMine && !hasStories) {
      return SizedBox.square(
        dimension: showPlusBadge ? kStoryRingMineExtent : kStoryRingOuterDiameter,
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox.square(
            dimension: kStoryRingOuterDiameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (pendingProgress == null)
                  CustomPaint(
                    size: const Size.square(kStoryRingOuterDiameter),
                    painter: _EmptyRingPainter(
                      color: colorScheme.outline,
                      strokeWidth: kStoryRingStrokeWidth,
                    ),
                  )
                else
                  _PendingRing(
                    progress: pendingProgress!,
                    diameter: kStoryRingOuterDiameter,
                    strokeWidth: kStoryRingStrokeWidth,
                    color: colorScheme.primary,
                    reduceMotion: reduceMotion,
                  ),
                if (showPlusBadge)
                  _PlusBadge(
                    centered: true,
                    colorScheme: colorScheme,
                    onTap: onTapPlus,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final ring = Semantics(
      container: true,
      label: semanticLabel,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          key: const ValueKey('story-ring-visual'),
          dimension: kStoryRingOuterDiameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (pendingProgress != null)
                _PendingRing(
                  progress: pendingProgress!,
                  diameter: kStoryRingOuterDiameter,
                  strokeWidth: kStoryRingStrokeWidth,
                  color: colorScheme.primary,
                  reduceMotion: reduceMotion,
                )
              else
                CustomPaint(
                  size: const Size.square(kStoryRingOuterDiameter),
                  painter: _SegmentedRingPainter(
                    segmentCount: _cappedSegments,
                    unviewedCount: math.min(unviewedCount, _cappedSegments),
                    solid: _solid,
                    brightColor: colorScheme.primary,
                    // 0.4: checked against rendered goldens in both themes
                    // (light mode's green washes out first).
                    fadedColor: colorScheme.primary.withValues(alpha: 0.4),
                    strokeWidth: kStoryRingStrokeWidth,
                  ),
                ),
              _Thumbnail(
                diameter: kStoryRingThumbnailDiameter,
                hasStories: hasStories,
                thumbnailUrl: thumbnailUrl,
                localThumbnailPath: localThumbnailPath,
                isMine: isMine,
                colorScheme: colorScheme,
              ),
            ],
          ),
        ),
      ),
    );
    if (!isMine || !showPlusBadge) return ring;

    // My ring with the corner `+`: the ring at the leading top, the `+`'s
    // 48 dp target at the trailing bottom, hanging [kStoryRingPlusOverhang]
    // past the ring. The target refuses taps over the photo
    // ([storyPlusTargetContains]); those fall through to the ring.
    return SizedBox.square(
      dimension: kStoryRingMineExtent,
      child: Stack(
        children: [
          PositionedDirectional(start: 0, top: 0, child: ring),
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: _PlusBadge(colorScheme: colorScheme, onTap: onTapPlus),
          ),
        ],
      ),
    );
  }
```

Replace `_PlusBadge` and add `_PlusHitShape` below it:

```dart
class _PlusBadge extends StatelessWidget {
  const _PlusBadge({
    this.centered = false,
    required this.colorScheme,
    this.onTap,
  });

  final bool centered;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visualSize = centered ? 28.0 : kStoryRingBadgeDiameter;
    final visual = Container(
      key: const ValueKey('story-ring-plus-visual'),
      width: visualSize,
      height: visualSize,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
        border:
            centered ? null : Border.all(color: colorScheme.surface, width: 2),
      ),
      child: Icon(
        Icons.add,
        size: centered ? 18 : 14,
        color: colorScheme.onPrimary,
      ),
    );
    // Material's 48 dp minimum target with the small badge centred in it,
    // the IconButton pattern. Its own semantics node, separate from the
    // ring's (the camera is a different control from the reel).
    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.square(
        key: const ValueKey('story-ring-plus-target'),
        dimension: kMinInteractiveDimension,
        child: Center(child: visual),
      ),
    );
    return Semantics(
      container: true,
      label: 'Add to your story',
      button: true,
      child: centered
          ? button
          : _PlusHitShape(direction: Directionality.of(context), child: button),
    );
  }
}

/// Lets the `+` target refuse the photo's taps (07a V10).
class _PlusHitShape extends SingleChildRenderObjectWidget {
  const _PlusHitShape({required this.direction, required super.child});

  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlusHitShape(direction);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPlusHitShape renderObject,
  ) {
    renderObject.direction = direction;
  }
}

class _RenderPlusHitShape extends RenderProxyBox {
  _RenderPlusHitShape(this.direction);

  TextDirection direction;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!storyPlusTargetContains(position, direction: direction)) return false;
    return super.hitTest(result, position: position);
  }
}
```

In the file header, replace "a `+` badge bottom-right" with: "a `+` badge at the bottom end, whose 48 dp target hangs outside the ring (07a V10)". Leave `_Thumbnail` and the painters as they are.

- [ ] **Step 4: Lay out the row (`story_rings_row.dart`).** Replace the fixed-height ring row:

```dart
          SizedBox(
            height: kStoryRingMineExtent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                myRing,
                if (showPartnerRing) ...[
                  // My ring's box already reaches kStoryRingPlusOverhang
                  // past the ring for the `+` target, so the gap gives it
                  // back: the partner ring stays Spacing.md from mine.
                  const SizedBox(width: Spacing.md - kStoryRingPlusOverhang),
```

Keep the rest of that `Row` and the comment about the empty partner ring.

- [ ] **Step 5: Calendar (`calendar_day_sheet.dart`).**
  - In `_StoriesSection`, set the ring list's `SizedBox` `height:` to `kStoryRingOuterDiameter + 4`.
  - In `_AuthorDayRing`, pass `showPlusBadge: false` to `StoryRing`.
  - Replace the `// No + affordance in the calendar…` comment with: `// No + on a past day: a capture posts to today (showPlusBadge: false).`

- [ ] **Step 6: Run the tests.** Use the same command as Step 2. Expected: PASS, except the two goldens, which now show the new layout.

- [ ] **Step 7: Regenerate the goldens and look at them.**

```bash
flutter test --update-goldens test/features/stories/story_rings_test.dart --plain-name 'story rings row'
```

Open `test/features/stories/goldens/story_rings_light.png` and `story_rings_dark.png` with the Read tool, and check:
- My ring still has the badge at its bottom end.
- The partner ring is 85 dp from mine, with the tops aligned.
- Nothing is clipped.
- The row is 10 dp taller than before.

- [ ] **Step 8: Run the neighbours.**

```bash
flutter test test/features/stories test/features/timeline
```

Expected: PASS. This includes the existing tests "the + badge hit target is at least 44dp" and "tapping the ring label fires onOpenMine".

---

### Task 2: Arcs in playback order; ring labels with counts (L3, L2; 06 #20)

**Files:**
- Create: `lib/features/stories/domain/story_ring_copy.dart`
- Modify: `story_ring.dart` (the `_SegmentedRingPainter` loop and its doc; `_PlusBadge` label)
- Modify: `story_rings_row.dart` (labels)
- Modify: `calendar_day_sheet.dart` (the `_AuthorDayRing` label)
- Create: `test/features/stories/story_ring_copy_test.dart`
- Modify: `test/features/stories/story_rings_test.dart`: the existing pixel test, a new test, a label test, and the goldens.

**Interfaces:**
- Produces (in `story_ring_copy.dart`):

```dart
const String storyRingAddLabel; // 'Add to your story'
String storyRingMineLabel(int active);                 // 'Your story, 3 items'
String storyRingPostingLabel(int posted);              // 'Your story, posting, 2 posted'
String storyRingPartnerLabel(String name, {required int active, required int unviewed});
String storyDayRingLabel({required bool mine, required int count, String? partnerName});
```

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_ring_copy_test.dart`:

```dart
import 'package:attune/features/stories/domain/story_ring_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the partner ring says how many are new (03 L2)', () {
    expect(
      storyRingPartnerLabel('Ama', active: 5, unviewed: 3),
      "Ama's story, 3 new of 5",
    );
    expect(
      storyRingPartnerLabel('Ama', active: 5, unviewed: 0),
      "Ama's story, 5 items, all seen",
    );
    expect(
      storyRingPartnerLabel('Ama', active: 1, unviewed: 4),
      "Ama's story, 1 new of 1",
    );
  });

  test('my ring keeps its count while posting', () {
    expect(storyRingMineLabel(1), 'Your story, 1 item');
    expect(storyRingMineLabel(3), 'Your story, 3 items');
    expect(storyRingPostingLabel(0), 'Your story, posting');
    expect(storyRingPostingLabel(2), 'Your story, posting, 2 posted');
  });

  test('a calendar day names whose stories they are', () {
    expect(
      storyDayRingLabel(mine: true, count: 2),
      'Your stories from this day, 2 items',
    );
    expect(
      storyDayRingLabel(mine: false, count: 1, partnerName: 'Kofi'),
      "Kofi's stories from this day, 1 item",
    );
    expect(
      storyDayRingLabel(mine: false, count: 3),
      "Your partner's stories from this day, 3 items",
    );
  });
}
```

In `story_rings_test.dart`:
- Add `import 'dart:math' as math;`.
- Add this helper above `_TestPainterInfo`:

```dart
/// The midpoint of arc [index] of [count] (painted clockwise from 12
/// o'clock with the painter's 0.12 rad gaps), in a [size] square.
Offset _arcMidpoint(int index, int count, double size) {
  const gap = 0.12;
  final per = (2 * math.pi - gap * count) / count;
  final angle = -math.pi / 2 + index * (per + gap) + per / 2;
  final r = (size - kStoryRingStrokeWidth) / 2;
  return Offset(size / 2 + r * math.cos(angle), size / 2 + r * math.sin(angle));
}
```

In the existing test `'faded segments are ACTUALLY PAINTED at a lower alpha…'`, replace the two sample lines (`final brightPixel = pixelAt(size.width ~/ 2, 2);` and `final fadedPixel = pixelAt(…, size.height.toInt() - 3);`) with:

```dart
        // 1 of 4 unviewed: oldest-first clockwise (03 L3), so arcs 0–2 are
        // the seen ones and arc 3, the newest, is bright.
        final b = _arcMidpoint(3, 4, size.width);
        final f = _arcMidpoint(1, 4, size.width);
        final brightPixel = pixelAt(b.dx.round(), b.dy.round());
        final fadedPixel = pixelAt(f.dx.round(), f.dy.round());
```

Update that test's comment lines that say "index 0 … is bright" to "arc 3 (newest) is bright; arcs 0–2 are faded". Then add, in the same group:

```dart
    testWidgets('the seen arcs come first clockwise, as the reel plays (03 L3)', (
      tester,
    ) async {
      await tester.pumpWidget(
        await _harness(
          noThumbnails: true,
          summary: [
            _summary(authorId: _myId, activeCount: 0, unviewedCount: 0),
            _summary(authorId: _partnerId, activeCount: 3, unviewedCount: 1),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final painter = _findSegmentedCustomPainter(tester, 'story-ring-partner')!;
      const size = Size(69, 69);
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), size);
        final image = await recorder.endRecording().toImage(69, 69);
        return image.toByteData(format: ui.ImageByteFormat.rawRgba);
      });
      int alphaAt(Offset p) =>
          bytes!.buffer.asUint8List()[(p.dy.round() * 69 + p.dx.round()) * 4 + 3];
      final oldest = alphaAt(_arcMidpoint(0, 3, 69));
      final newest = alphaAt(_arcMidpoint(2, 3, 69));
      expect(oldest, greaterThan(0));
      expect(oldest, lessThan(newest));
    });

    testWidgets("the partner ring's label counts what is new (03 L2)", (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        await _harness(
          noThumbnails: true,
          summary: [
            _summary(authorId: _partnerId, activeCount: 6, unviewedCount: 2),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel("Alex's story, 2 new of 6"), findsOneWidget);
      handle.dispose();
    });
```

- [ ] **Step 2: Run them and watch them fail.**

```bash
flutter test test/features/stories/story_ring_copy_test.dart test/features/stories/story_rings_test.dart
```

Expected: FAIL.
- The copy test does not compile: there is no `story_ring_copy.dart` yet.
- The pixel tests fail: `oldest` is brighter than `newest`.
- The label is "Alex's story, new".

- [ ] **Step 3: Create `lib/features/stories/domain/story_ring_copy.dart`.**

```dart
/// Screen-reader labels and short copy for the story rings (03 L2). Kept
/// in one place so the open l10n extraction gate can lift them together.
library;

String _items(int n) => n == 1 ? '1 item' : '$n items';

/// The `+` (camera) on my ring.
const String storyRingAddLabel = 'Add to your story';

/// My ring with posted stories: "Your story, 3 items".
String storyRingMineLabel(int active) => 'Your story, ${_items(active)}';

/// My ring while a story posts: "Your story, posting, 2 posted".
String storyRingPostingLabel(int posted) =>
    posted > 0 ? 'Your story, posting, $posted posted' : 'Your story, posting';

/// The partner's ring: "Ama's story, 2 new of 5", or, all seen,
/// "Ama's story, 5 items, all seen".
String storyRingPartnerLabel(
  String name, {
  required int active,
  required int unviewed,
}) {
  final fresh = unviewed.clamp(0, active);
  return fresh == 0
      ? "$name's story, ${_items(active)}, all seen"
      : "$name's story, $fresh new of $active";
}

/// A calendar day's ring: "Your stories from this day, 2 items".
String storyDayRingLabel({
  required bool mine,
  required int count,
  String? partnerName,
}) {
  final whose = mine ? 'Your' : "${partnerName ?? 'Your partner'}'s";
  return '$whose stories from this day, ${_items(count)}';
}
```

Run `dart format lib/features/stories/domain/story_ring_copy.dart test/features/stories/story_ring_copy_test.dart`.

- [ ] **Step 4: Paint in playback order.** In `_SegmentedRingPainter.paint`, replace the loop with:

```dart
    // Oldest first, clockwise from 12 o'clock, like the reel's bars: the
    // seen (older) arcs first, then the new ones (03 L3, 06 #20).
    final seen = segmentCount - unviewedCount;
    for (var i = 0; i < segmentCount; i++) {
      final paint = i < seen ? fadedPaint : brightPaint;
      canvas.drawArc(rect, start, perSegment, false, paint);
      start += perSegment + _gapRadians;
    }
```

In the class doc, replace "(drawn first, at the top, going clockwise)" with "(drawn last, ending at the top: arcs run oldest first clockwise)".

- [ ] **Step 5: Use the copy.**
  - In `story_ring.dart` `_PlusBadge`: `label: storyRingAddLabel,`, and import the copy file.
  - In `story_rings_row.dart`:
    - the `StoryRing` built for pending or empty gets `semanticLabel: myPending != null ? storyRingPostingLabel(mySegmentCount) : storyRingAddLabel`;
    - `_PartnerRing` gets `semanticLabel: storyRingPartnerLabel(partnerName, active: summary.activeCount, unviewed: summary.unviewedCount)`;
    - `_MineRing` gets `semanticLabel: storyRingMineLabel(segmentCount)`.
  - In `calendar_day_sheet.dart` `_AuthorDayRing`: `semanticLabel: storyDayRingLabel(mine: isMine, count: items.length)`.

- [ ] **Step 6: Run the tests.** Use the Step 2 command. Expected: PASS, except the goldens: the partner's arcs moved.

- [ ] **Step 7: Regenerate the goldens and look.**

```bash
flutter test --update-goldens test/features/stories/story_rings_test.dart --plain-name 'story rings row'
```

Open both PNGs and check: the partner ring (6 items, 2 new) shows four faded arcs from 12 o'clock clockwise, then two bright arcs ending at 12 o'clock.

- [ ] **Step 8: Run the neighbours.**

```bash
flutter test test/features/stories test/features/timeline
```

---

### Task 3: One signed URL per key, reused; failed signing retries (E, M5)

Fixes: 03 M5, the URL half of 03 M4, the signing half of 04 #6, and 07a V7/E (for rings and calendar).

**Files:**
- Create: `lib/features/stories/data/story_signed_url_cache.dart`
- Create: `lib/features/stories/presentation/providers/story_visible_refresh.dart`
- Modify: `lib/features/stories/presentation/providers/story_providers.dart`:
  - `storySignedUrlCacheProvider`;
  - `StoryMediaEvictor` and `storyMediaEvictorProvider`;
  - `storyMediaSignedUrlProvider`.
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart:89` (`kStorySignedUrlReuse` becomes an alias).
- Create: `test/features/stories/support/ring_test_kit.dart`
- Create: `test/features/stories/story_signed_url_cache_test.dart`
- Modify: `test/features/stories/story_read_repository_test.dart`: replace the test `'a signed URL is minted per request and never cached past its TTL…'`.

**Interfaces:**
- Consumes: `appContentVisibleProvider` (Wave 3), `chatImageCacheProvider`, `StoryReadGateway.signMediaUrl`.
- Produces:

```dart
// story_signed_url_cache.dart
const Duration kStoryUrlReuseWindow;          // 540 s
const int kStorySignMaxAutoRetries;           // 4
Duration storySignRetryDelay(int failures);   // 2, 4, 8, 16 s (cap 32)
class StorySignFailure implements Exception { final String storageKey; }
class StorySignedUrlCache {
  String? fresh(String storageKey);
  void put(String storageKey, String url);
  int recordFailure(String storageKey);
  void evict(Iterable<String> storageKeys);
  void clear();
  void dispose();
  static void clearEveryLiveCache();
}
// story_visible_refresh.dart
class StoryVisibleRefresh { StoryVisibleRefresh(Ref ref); bool disposed; void after(Duration delay); }
// story_providers.dart
final storySignedUrlCacheProvider;            // Provider<StorySignedUrlCache>
class StoryMediaEvictor { Future<void> evict(Iterable<String> storageKeys); }
final storyMediaEvictorProvider;              // Provider<StoryMediaEvictor>
final storyMediaSignedUrlProvider;            // unchanged type: FutureProvider.autoDispose.family<String?, String>
```

- Test kit (`ring_test_kit.dart`) produces: `ringMe`, `ringPartner`, `ringRel`, `ringUser`, `RingGateway`, `ringRow(...)`, `FixedVisibility`, `NoopImageCache`, `RecordingEvictor`, `ringContainer(...)`.

- [ ] **Step 1: Create the test kit** `test/features/stories/support/ring_test_kit.dart`:

```dart
// Shared doubles for the Wave 4 ring and calendar suites.
import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const ringMe = 'me-1';
const ringPartner = 'partner-1';
const ringRel = 'rel-1';

const ringUser = User(
  id: ringMe,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

StoryRingSummary ringRow({
  String author = ringPartner,
  int active = 1,
  int unviewed = 1,
  String? key,
  DateTime? newest,
}) => StoryRingSummary(
  authorId: author,
  activeCount: active,
  unviewedCount: unviewed,
  newestThumbnailKey: key ?? 'story-media/$author-thumb.jpg',
  newestCreatedAt: newest ?? clock.now().subtract(const Duration(hours: 1)),
);

/// Server truth a test can change, then announce with [emitSignal].
class RingGateway implements StoryReadGateway {
  RingGateway({List<StoryRingSummary> summary = const []})
    : summary = [...summary];

  List<StoryRingSummary> summary;
  Object? summaryError;
  Completer<void>? summaryGate;
  int summaryCalls = 0;

  /// key -> URL; a key mapped to null fails to sign. Unlisted keys sign
  /// as https://signed.example/<key>.
  final Map<String, String?> urls = {};
  final List<String> signCalls = [];

  List<StoryDayCount> dayCounts = [];
  Object? dayCountsError;
  Completer<void>? dayCountsGate;
  int dayCountCalls = 0;

  List<StoryItem> dayItems = [];
  Object? dayItemsError;
  Completer<void>? dayItemsGate;
  int dayItemCalls = 0;

  final _signals = StreamController<void>.broadcast();
  void emitSignal() => _signals.add(null);

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async {
    summaryCalls++;
    final gate = summaryGate;
    if (gate != null) await gate.future;
    final error = summaryError;
    if (error != null) throw error;
    return List.of(summary);
  }

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    signCalls.add(storageKey);
    return urls.containsKey(storageKey)
        ? urls[storageKey]
        : 'https://signed.example/$storageKey';
  }

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async {
    dayCountCalls++;
    final gate = dayCountsGate;
    if (gate != null) await gate.future;
    final error = dayCountsError;
    if (error != null) throw error;
    return List.of(dayCounts);
  }

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) async {
    dayItemCalls++;
    final gate = dayItemsGate;
    if (gate != null) await gate.future;
    final error = dayItemsError;
    if (error != null) throw error;
    return StoryItemPage(items: List.of(dayItems), nextCursor: null);
  }

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  @override
  Future<void> markViewed({required String storyItemId}) async {}

  @override
  Future<void> deleteItem({required String storyItemId}) async {}

  @override
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async => null;

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      _signals.stream;

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

/// Attune's content visibility under the test's control.
class FixedVisibility extends AppContentVisibility {
  FixedVisibility([this._initial = true]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool visible) => state = visible;
}

class NoopImageCache implements ChatImageCache {
  final removed = <String>[];
  int clears = 0;

  @override
  Future<void> clear() async => clears++;

  @override
  Future<void> removeKeys(Iterable<String> keys) async => removed.addAll(keys);
}

class RecordingEvictor implements StoryMediaEvictor {
  final evicted = <String>[];

  @override
  Future<void> evict(Iterable<String> storageKeys) async =>
      evicted.addAll(storageKeys);
}

ProviderContainer ringContainer(
  RingGateway gateway, {
  NoopImageCache? images,
  List<Override> overrides = const [],
}) => ProviderContainer(
  overrides: [
    currentUserProvider.overrideWithValue(ringUser),
    storyReadGatewayProvider.overrideWithValue(gateway),
    chatImageCacheProvider.overrideWithValue(images ?? NoopImageCache()),
    appContentVisibleProvider.overrideWith(FixedVisibility.new),
    ...overrides,
  ],
);

FixedVisibility visibilityOf(ProviderContainer c) =>
    c.read(appContentVisibleProvider.notifier) as FixedVisibility;
```

If `User` has no const constructor, change `const ringUser` to `final ringUser`.

- [ ] **Step 2: Write the failing tests.** Create `test/features/stories/story_signed_url_cache_test.dart`:

```dart
// E + M5 (03 M4/M5, 04 #6, 07a E): one signed URL per storage key, reused
// for 540 s in memory and shared by the rings and the calendar; a failed
// signing retries on a backoff, only while Attune is on screen.
import 'package:attune/features/stories/data/story_signed_url_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

void main() {
  group('StorySignedUrlCache', () {
    test('a URL is reused for 540 s, then forgotten', () {
      var now = DateTime.utc(2026, 10, 24, 9);
      withClock(Clock(() => now), () {
        final cache = StorySignedUrlCache();
        cache.put('k', 'u1');
        now = now.add(const Duration(seconds: 539));
        expect(cache.fresh('k'), 'u1');
        now = now.add(const Duration(seconds: 1));
        expect(cache.fresh('k'), isNull);
        cache.dispose();
      });
    });

    test('evict and clearEveryLiveCache forget URLs', () {
      final a = StorySignedUrlCache()..put('k1', 'u1')..put('k2', 'u2');
      final b = StorySignedUrlCache()..put('k3', 'u3');
      a.evict(['k1']);
      expect(a.fresh('k1'), isNull);
      expect(a.fresh('k2'), 'u2');
      StorySignedUrlCache.clearEveryLiveCache();
      expect(a.fresh('k2'), isNull);
      expect(b.fresh('k3'), isNull);
      a.dispose();
      b.dispose();
    });
  });

  group('storyMediaSignedUrlProvider', () {
    testWidgets('a key read twice within 540 s is signed once', (tester) async {
      final gateway = RingGateway();
      final c = ringContainer(gateway);
      final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
      await tester.pump();
      c.invalidate(storyMediaSignedUrlProvider('k'));
      await tester.pump();
      expect(gateway.signCalls, ['k']);
      expect(
        c.read(storyMediaSignedUrlProvider('k')).valueOrNull,
        'https://signed.example/k',
      );
      sub.close();
      c.dispose();
    });

    testWidgets(
      'a key whose signing fails is retried on a backoff, then left alone '
      '(Review Focus 5)',
      (tester) async {
        final gateway = RingGateway()..urls['k'] = null;
        final c = ringContainer(gateway);
        final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
        await tester.pump();
        expect(gateway.signCalls.length, 1);
        expect(c.read(storyMediaSignedUrlProvider('k')).hasError, isTrue);
        for (final seconds in [2, 4, 8, 16]) {
          await tester.pump(Duration(seconds: seconds));
          await tester.pump();
        }
        expect(gateway.signCalls.length, 1 + kStorySignMaxAutoRetries);
        await tester.pump(const Duration(minutes: 10));
        expect(gateway.signCalls.length, 1 + kStorySignMaxAutoRetries);
        sub.close();
        c.dispose();
      },
    );

    testWidgets('a retry due while Attune is hidden waits until it is back', (
      tester,
    ) async {
      final gateway = RingGateway()..urls['k'] = null;
      final c = ringContainer(gateway);
      final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
      await tester.pump();
      visibilityOf(c).set(false);
      gateway.urls['k'] = 'https://signed.example/k2';
      await tester.pump(const Duration(seconds: 3));
      expect(gateway.signCalls.length, 1);
      visibilityOf(c).set(true);
      await tester.pump();
      await tester.pump();
      expect(gateway.signCalls.length, 2);
      expect(
        c.read(storyMediaSignedUrlProvider('k')).valueOrNull,
        'https://signed.example/k2',
      );
      sub.close();
      c.dispose();
    });

    testWidgets('evicting a key signs it afresh and removes its bytes', (
      tester,
    ) async {
      final gateway = RingGateway();
      final images = NoopImageCache();
      final c = ringContainer(gateway, images: images);
      final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
      await tester.pump();
      await c.read(storyMediaEvictorProvider).evict(['k', '']);
      c.invalidate(storyMediaSignedUrlProvider('k'));
      await tester.pump();
      expect(gateway.signCalls, ['k', 'k']);
      expect(images.removed, ['k']);
      sub.close();
      c.dispose();
    });
  });
}
```


In `test/features/stories/story_read_repository_test.dart`, replace the body of the test `'a signed URL is minted per request and never cached past its TTL — two requests for the same key each reach the gateway'`, and rename it:

```dart
    test(
      'a signed URL is reused for the same key while under 540 s old, then '
      'minted again (STORIES.md §4.1 as amended, Wave 4)',
      () async {
        var now = DateTime.utc(2026, 10, 24, 9);
        await withClock(Clock(() => now), () async {
          final gateway = _FakeStoryReadGateway();
          final container = _buildContainer(gateway);
          addTearDown(container.dispose);
          const key = 'story-media/x.jpg';
          final first = await container.read(
            storyMediaSignedUrlProvider(key).future,
          );
          container.invalidate(storyMediaSignedUrlProvider(key));
          final reused = await container.read(
            storyMediaSignedUrlProvider(key).future,
          );
          expect(gateway.signMediaUrlCallCount, 1);
          expect(reused, first);
          now = now.add(kStoryUrlReuseWindow);
          container.invalidate(storyMediaSignedUrlProvider(key));
          final second = await container.read(
            storyMediaSignedUrlProvider(key).future,
          );
          expect(gateway.signMediaUrlCallCount, 2);
          expect(second, isNot(equals(first)));
        });
      },
    );
```

Add the imports `package:clock/clock.dart` and `package:attune/features/stories/data/story_signed_url_cache.dart`. Leave the next test (the production repository has no cache map) unchanged: the cache lives in the provider layer.

- [ ] **Step 3: Run them and watch them fail.**

```bash
flutter test test/features/stories/story_signed_url_cache_test.dart test/features/stories/story_read_repository_test.dart
```

Expected: FAIL to compile. `story_signed_url_cache.dart`, `StoryMediaEvictor` and `kStoryUrlReuseWindow` do not exist yet.

- [ ] **Step 4: Create `lib/features/stories/data/story_signed_url_cache.dart`.**

```dart
/// Signed URLs for story media, by storage key, held in memory only
/// (STORIES.md §4.1 as amended in Wave 4). The rings and the calendar share
/// one URL per key while it is under [kStoryUrlReuseWindow] old, so a
/// rebuild, a month swipe or a second ring does not sign again. Never
/// written to disk; forgotten on sign-out and account change (a new
/// instance per account), quick exit and a relationship's pause or end
/// ([clearEveryLiveCache]), and when a story is deleted ([evict]).
library;

import 'package:clock/clock.dart';

/// Under the 600 s TTL with a minute to spare, the same window the reel
/// uses for its own screen-local reuse.
const Duration kStoryUrlReuseWindow = Duration(seconds: 540);

/// Automatic re-signs after a failure, before waiting for a rebuild.
const int kStorySignMaxAutoRetries = 4;

/// 2, 4, 8, 16 s (capped at 32 s).
Duration storySignRetryDelay(int failures) =>
    Duration(seconds: 2 << (failures - 1).clamp(0, 4));

/// A key that could not be signed (refused, offline or timed out). Carries
/// the key for callers; never logged.
class StorySignFailure implements Exception {
  const StorySignFailure(this.storageKey);
  final String storageKey;

  @override
  String toString() => 'StorySignFailure';
}

class StorySignedUrlCache {
  StorySignedUrlCache() {
    _live.add(this);
  }

  static final Set<StorySignedUrlCache> _live = {};

  final Map<String, ({String url, DateTime mintedAt})> _urls = {};
  final Map<String, int> _failures = {};

  /// The URL minted for [storageKey] under [kStoryUrlReuseWindow] ago.
  String? fresh(String storageKey) {
    final entry = _urls[storageKey];
    if (entry == null) return null;
    if (clock.now().difference(entry.mintedAt) >= kStoryUrlReuseWindow) {
      _urls.remove(storageKey);
      return null;
    }
    return entry.url;
  }

  void put(String storageKey, String url) {
    _urls[storageKey] = (url: url, mintedAt: clock.now());
    _failures.remove(storageKey);
  }

  /// One more failed signing for [storageKey]; returns the total so far.
  int recordFailure(String storageKey) =>
      _failures[storageKey] = (_failures[storageKey] ?? 0) + 1;

  void evict(Iterable<String> storageKeys) {
    for (final key in storageKeys) {
      _urls.remove(key);
      _failures.remove(key);
    }
  }

  void clear() {
    _urls.clear();
    _failures.clear();
  }

  void dispose() {
    clear();
    _live.remove(this);
  }

  /// Quick exit and a relationship's pause or end run with no provider
  /// container in hand: every cache still alive forgets everything.
  static void clearEveryLiveCache() {
    for (final cache in _live) {
      cache.clear();
    }
  }
}
```

- [ ] **Step 5: Create `lib/features/stories/presentation/providers/story_visible_refresh.dart`.**

```dart
import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Re-runs the provider that owns [_ref] after a delay, but only while
/// Attune's content is on screen (stories Wave 3): a timer that comes due
/// behind the privacy cover or the Safety lock waits for the next return
/// instead of fetching for nobody. One pending timer per provider build,
/// cancelled with the build.
class StoryVisibleRefresh {
  StoryVisibleRefresh(this._ref) {
    _ref.onDispose(() {
      disposed = true;
      _timer?.cancel();
    });
    _ref.listen<bool>(appContentVisibleProvider, (previous, next) {
      if (next && _dueWhileHidden && !disposed) {
        _dueWhileHidden = false;
        _ref.invalidateSelf();
      }
    });
  }

  final Ref _ref;
  Timer? _timer;
  bool _dueWhileHidden = false;

  /// True once this build was replaced or disposed. Work that finishes
  /// after that must schedule nothing and record nothing.
  bool disposed = false;

  void after(Duration delay) {
    if (disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (disposed) return;
      if (_ref.read(appContentVisibleProvider)) {
        _ref.invalidateSelf();
      } else {
        _dueWhileHidden = true;
      }
    });
  }
}
```

Run `dart format` on the two new lib files and the two new test files.

- [ ] **Step 6: Wire the providers (`story_providers.dart`).**

Add these imports:
- `package:attune/features/chat/domain/services/chat_image_cache.dart`;
- `package:attune/features/stories/data/story_signed_url_cache.dart`;
- `package:attune/features/stories/presentation/providers/story_visible_refresh.dart`.

Replace `storyMediaSignedUrlProvider` and its doc with:

```dart
/// In-memory signed URLs by storage key (STORIES.md §4.1 as amended, Wave
/// 4). A new, empty instance per signed-in account.
final storySignedUrlCacheProvider = Provider<StorySignedUrlCache>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final cache = StorySignedUrlCache();
  ref.onDispose(cache.dispose);
  return cache;
});

/// Forgets a story's media on this phone: its signed URLs and its image
/// bytes in the shared disk cache (both keyed by storage key; 05 #6).
/// Never throws.
class StoryMediaEvictor {
  StoryMediaEvictor(this._ref);
  final Ref _ref;

  Future<void> evict(Iterable<String> storageKeys) async {
    final keys = {
      for (final key in storageKeys)
        if (key.isNotEmpty) key,
    };
    if (keys.isEmpty) return;
    _ref.read(storySignedUrlCacheProvider).evict(keys);
    await _ref.read(chatImageCacheProvider).removeKeys(keys);
  }
}

final storyMediaEvictorProvider = Provider<StoryMediaEvictor>(
  StoryMediaEvictor.new,
);

/// A signed URL for [storageKey]. Reuses the one minted under 540 s ago
/// (rings and calendar share it; it is never stored on disk). A failed
/// signing is an error, not a silent null, and retries itself on a backoff
/// while Attune is on screen (03 M5), at most [kStorySignMaxAutoRetries]
/// times; a rebuild after that tries again.
final storyMediaSignedUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, storageKey) async {
      final cache = ref.watch(storySignedUrlCacheProvider);
      final gateway = ref.watch(storyReadGatewayProvider);
      final reused = cache.fresh(storageKey);
      if (reused != null) return reused;
      final refresh = StoryVisibleRefresh(ref);
      String? url;
      try {
        url = await gateway.signMediaUrl(storageKey);
      } catch (_) {
        url = null;
      }
      if (refresh.disposed) return url;
      if (url == null) {
        final failures = cache.recordFailure(storageKey);
        if (failures <= kStorySignMaxAutoRetries) {
          refresh.after(storySignRetryDelay(failures));
        }
        throw StorySignFailure(storageKey);
      }
      cache.put(storageKey, url);
      return url;
    });
```

- [ ] **Step 7: One window, one constant.** At `story_reel_screen.dart:89`, replace `const Duration kStorySignedUrlReuse = Duration(seconds: 540);` with:

```dart
const Duration kStorySignedUrlReuse = kStoryUrlReuseWindow;
```

Add `import 'package:attune/features/stories/data/story_signed_url_cache.dart';`. Change nothing else in the reel.

- [ ] **Step 8: Run the tests.** Use the Step 3 command. Expected: PASS.

- [ ] **Step 9: Run the neighbours.**

```bash
flutter test test/features/stories test/features/timeline test/features/couple_map
```

Expected: PASS. Ring and calendar tests whose fakes sign to null now see bounded retries; nothing in them counts signing calls.

---

### Task 4: Thumbnails drawn from the disk cache by key, decoded at display size (E widgets, L5; 04 #6, 06 #16)

**Files:**
- Modify: `story_ring.dart`:
  - `StoryRing.thumbnailCacheKey`;
  - `_Thumbnail`;
  - the new `StoryKeyCachedImage`, `storyCachedThumbnailOnDisk` and `debugStoryCachedThumbnail`.
- Modify: `story_rings_row.dart` (`_MineRing` and `_PartnerRing` pass the key).
- Modify: `calendar_day_sheet.dart` (`_AuthorDayRing` passes the key).
- Modify: `calendar_day_indicators.dart` (`_StoryAvatar`).
- Modify: `test/features/stories/support/ring_test_kit.dart` (`HangingStoryGateway`, `pumpRings`, `mineRing`).
- Create: `test/features/stories/story_ring_thumbnail_test.dart`

**Interfaces:**
- Consumes: `storyMediaSignedUrlProvider` (Task 3).
- Produces:

```dart
// story_ring.dart
// StoryRing gains: final String? thumbnailCacheKey;
class StoryKeyCachedImage extends StatefulWidget {
  const StoryKeyCachedImage({super.key, required String storageKey, required int decodeWidth, required Widget fallback});
}
Future<File?> storyCachedThumbnailOnDisk(String storageKey);
@visibleForTesting Future<File?> Function(String storageKey) debugStoryCachedThumbnail; // defaults to the above
// ring_test_kit.dart
Future<void> pumpRings(WidgetTester tester, RingGateway gateway, {List<StoryOutboxRecord> outbox, VoidCallback? onOpenMine, VoidCallback? onOpenPartner, VoidCallback? onCapture, List<Override> overrides, TextDirection direction, double width, double textScale, String relationshipId});
StoryRing mineRing(WidgetTester tester);
class HangingStoryGateway implements StoryGateway;
```

- [ ] **Step 1: Extend the kit.** Append to `ring_test_kit.dart`. Add imports:
- `package:attune/app/theme/app_theme.dart`;
- `package:attune/features/chat/data/repositories/chat_media_uploader.dart` (`show ChatUploadCancelToken`);
- `package:attune/features/stories/data/story_outbox_backend_stub.dart` (`as stub`);
- `package:attune/features/stories/data/story_outbox_record.dart`;
- `package:attune/features/stories/data/story_outbox_store.dart`;
- `package:attune/features/stories/data/story_repository.dart`;
- `package:attune/features/stories/presentation/state/story_outbox_controller.dart`;
- `package:attune/features/stories/presentation/widgets/story_ring.dart`;
- `package:attune/features/stories/presentation/widgets/story_rings_row.dart`;
- `package:flutter/material.dart`;
- `package:flutter_test/flutter_test.dart`.

Then append:

```dart
/// Every outbox call hangs: seeded records stay in the state given.
class HangingStoryGateway implements StoryGateway {
  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) => Completer<StoryUploadIntent>().future;

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) => Completer<void>().future;

  @override
  Future<StoryFinalizeResult> finalizeStory({
    required String relationshipId,
    required String clientStoryId,
    required String mediaIntentId,
    required String thumbnailIntentId,
    required int mediaWidth,
    required int mediaHeight,
    int? durationMs,
    required int utcOffsetMinutes,
    Map<String, dynamic>? place,
  }) => Completer<StoryFinalizeResult>().future;
}

Future<void> pumpRings(
  WidgetTester tester,
  RingGateway gateway, {
  List<StoryOutboxRecord> outbox = const [],
  VoidCallback? onOpenMine,
  VoidCallback? onOpenPartner,
  VoidCallback? onCapture,
  List<Override> overrides = const [],
  TextDirection direction = TextDirection.ltr,
  double width = 400,
  double textScale = 1,
  String relationshipId = ringRel,
}) async {
  final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
  for (final record in outbox) {
    await store.put(ringMe, record);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(ringUser),
        storyReadGatewayProvider.overrideWithValue(gateway),
        storyOutboxStoreProvider.overrideWithValue(store),
        storyGatewayProvider.overrideWithValue(HangingStoryGateway()),
        chatImageCacheProvider.overrideWithValue(NoopImageCache()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Directionality(
          textDirection: direction,
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    child: StoryRingsRow(
                      relationshipId: relationshipId,
                      partnerId: ringPartner,
                      partnerName: 'Ama',
                      onOpenMine: onOpenMine,
                      onOpenPartner: onOpenPartner,
                      onCapture: onCapture,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// My ring's StoryRing, whichever wrapper carries the key.
StoryRing mineRing(WidgetTester tester) {
  final keyed = find.byKey(const ValueKey('story-ring-mine'));
  final widget = tester.widget(keyed);
  if (widget is StoryRing) return widget;
  return tester.widget<StoryRing>(
    find.descendant(of: keyed, matching: find.byType(StoryRing)),
  );
}
```

- [ ] **Step 2: Write the failing tests.** Create `test/features/stories/story_ring_thumbnail_test.dart`:

```dart
// E (03 M4, 04 #6, 06 #16, 05 #6) + L5: ring and calendar thumbnails are
// cached under their storage key (a re-signed URL never re-downloads),
// fall back to the copy already on disk when signing fails, and decode at
// the size they are shown.
import 'dart:io';

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

const _key = 'story-media/partner-1-thumb.jpg';
final _day = DateTime(2026, 6, 15);

Widget _calendarHost(RingGateway gateway, Widget child) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWithValue(ringUser),
    storyReadGatewayProvider.overrideWithValue(gateway),
    chatImageCacheProvider.overrideWithValue(NoopImageCache()),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  tearDown(() => debugStoryCachedThumbnail = storyCachedThumbnailOnDisk);

  testWidgets('the partner ring keys its image by storage key, at display size', (
    tester,
  ) async {
    await pumpRings(tester, RingGateway(summary: [ringRow(key: _key)]));
    final image = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byKey(const ValueKey('story-ring-partner')),
        matching: find.byType(CachedNetworkImage),
      ),
    );
    expect(image.cacheKey, _key);
    expect(image.useOldImageOnUrlChange, isTrue);
    expect(
      image.memCacheWidth,
      (kStoryRingThumbnailDiameter * tester.view.devicePixelRatio).round(),
    );
  });

  testWidgets('when signing fails, the ring shows the copy already on disk', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ring-thumb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/t.jpg')..writeAsBytesSync([0]);
    debugStoryCachedThumbnail = (key) async => key == _key ? file : null;
    final gateway = RingGateway(summary: [ringRow(key: _key)])
      ..urls[_key] = null;
    await pumpRings(tester, gateway);
    await tester.pump();
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('story-ring-partner')),
        matching: find.byType(Image),
      ),
    );
    final provider = image.image as ResizeImage;
    expect((provider.imageProvider as FileImage).file.path, file.path);
  });

  testWidgets('a calendar date avatar keys its image by storage key', (
    tester,
  ) async {
    final gateway = RingGateway()
      ..dayCounts = [
        StoryDayCount(
          occurredOn: _day,
          itemCount: 1,
          authorId: ringPartner,
          newestThumbnailKey: _key,
          newestCreatedAt: _day,
        ),
      ];
    await tester.pumpWidget(
      _calendarHost(
        gateway,
        CalendarDayIndicators(
          relationshipId: ringRel,
          date: _day,
          eventTypes: const [],
          reminderTypes: const [],
          hasUpcoming: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, _key);
    expect(
      image.memCacheWidth,
      (kCalendarStoryAvatarDiameter * tester.view.devicePixelRatio).round(),
    );
  });

  testWidgets("a day sheet ring keys its image by the newest story's key", (
    tester,
  ) async {
    final gateway = RingGateway()
      ..dayItems = [
        StoryItem(
          id: 's1',
          clientStoryId: 'c1',
          relationshipId: ringRel,
          authorId: ringPartner,
          mediaType: 'image',
          mediaKey: 'story-media/s1.jpg',
          thumbnailKey: _key,
          mediaWidth: 1080,
          mediaHeight: 1920,
          occurredOn: _day,
          createdAt: _day,
          expiresAt: _day.add(const Duration(hours: 24)),
          hasBeenViewed: false,
        ),
      ];
    await tester.pumpWidget(
      _calendarHost(
        gateway,
        CalendarDaySheet(
          relationshipId: ringRel,
          date: _day,
          events: const [],
          reminders: const [],
          planningEntries: const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, _key);
  });
}
```

Check `CalendarDayIndicators`' constructor parameters against `calendar_day_indicators.dart` and use its real names. The test needs `relationshipId`, `date` and empty event and reminder data.

- [ ] **Step 3: Run it and watch it fail.**

```bash
flutter test test/features/stories/story_ring_thumbnail_test.dart
```

Expected: FAIL to compile, because `debugStoryCachedThumbnail` and `storyCachedThumbnailOnDisk` do not exist yet. Once they exist, the assertions fail with `cacheKey == null` and `memCacheWidth == null`.

- [ ] **Step 4: Implement in `story_ring.dart`.**

Add the imports `dart:async` and `package:flutter_cache_manager/flutter_cache_manager.dart`.

Add the constructor parameter `this.thumbnailCacheKey,` after `this.thumbnailUrl,`, and the field:

```dart
  /// The thumbnail's storage key: what its bytes are cached under, so a
  /// re-signed URL never re-downloads (E), and what is drawn from disk when
  /// there is no URL yet or signing failed.
  final String? thumbnailCacheKey;
```

Replace `_Thumbnail` and its call site, which becomes `_Thumbnail(diameter: kStoryRingThumbnailDiameter, thumbnailUrl: thumbnailUrl, thumbnailCacheKey: thumbnailCacheKey, localThumbnailPath: localThumbnailPath, colorScheme: colorScheme)`:

```dart
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.diameter,
    required this.thumbnailUrl,
    required this.thumbnailCacheKey,
    required this.localThumbnailPath,
    required this.colorScheme,
  });

  final double diameter;
  final String? thumbnailUrl;
  final String? thumbnailCacheKey;
  final String? localThumbnailPath;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final neutral = ColoredBox(color: colorScheme.surfaceContainerHighest);
    // Decoded at the size shown, not the 400 px file (03 L5).
    final decodeWidth =
        (diameter * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 3)).round();
    final localPath = localThumbnailPath;
    final url = thumbnailUrl;
    final key = thumbnailCacheKey;
    final Widget image;
    if (localPath != null && localPath.isNotEmpty) {
      // A pending capture: app-private storage, never a URL (spec §6.1).
      image = Image.file(
        File(localPath),
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        errorBuilder: (_, __, ___) => neutral,
      );
    } else if (url != null && url.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: url,
        // Bytes under the storage key, never the URL (STORIES.md §4.1).
        cacheKey: key,
        useOldImageOnUrlChange: true,
        memCacheWidth: decodeWidth,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => neutral,
        errorWidget: (_, __, ___) => neutral,
      );
    } else if (key != null && key.isNotEmpty) {
      // No URL yet, or signing failed: what is already on disk (03 M5).
      image = StoryKeyCachedImage(
        storageKey: key,
        decodeWidth: decodeWidth,
        fallback: neutral,
      );
    } else {
      image = neutral;
    }
    return ClipOval(
      child: SizedBox(width: diameter, height: diameter, child: image),
    );
  }
}

/// Finds a thumbnail already in the shared image cache under its storage
/// key. Never throws: on a host with no cache store it answers null.
Future<File?> storyCachedThumbnailOnDisk(String storageKey) {
  final found = Completer<File?>();
  runZonedGuarded(
    () async {
      final info = await DefaultCacheManager().getFileFromCache(storageKey);
      if (!found.isCompleted) {
        found.complete(info == null ? null : File(info.file.path));
      }
    },
    (_, __) {
      if (!found.isCompleted) found.complete(null);
    },
  );
  return found.future;
}

/// What [StoryKeyCachedImage] uses to look up the disk. Tests replace it.
@visibleForTesting
Future<File?> Function(String storageKey) debugStoryCachedThumbnail =
    storyCachedThumbnailOnDisk;

/// A story thumbnail drawn from disk by its storage key, or [fallback].
class StoryKeyCachedImage extends StatefulWidget {
  const StoryKeyCachedImage({
    super.key,
    required this.storageKey,
    required this.decodeWidth,
    required this.fallback,
  });

  final String storageKey;
  final int decodeWidth;
  final Widget fallback;

  @override
  State<StoryKeyCachedImage> createState() => _StoryKeyCachedImageState();
}

class _StoryKeyCachedImageState extends State<StoryKeyCachedImage> {
  File? _file;
  int _lookup = 0;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void didUpdateWidget(StoryKeyCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storageKey != widget.storageKey) {
      _file = null;
      _find();
    }
  }

  void _find() {
    final ticket = ++_lookup;
    debugStoryCachedThumbnail(widget.storageKey).then((file) {
      if (mounted && ticket == _lookup && file != null) {
        setState(() => _file = file);
      }
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return widget.fallback;
    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: widget.decodeWidth,
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }
}
```

- [ ] **Step 5: Pass the keys.**
  - In `story_rings_row.dart`, `_PartnerRing` and `_MineRing` pass `thumbnailCacheKey: summary.newestThumbnailKey`.
  - In `calendar_day_sheet.dart`, `_AuthorDayRing` passes `thumbnailCacheKey: newest.thumbnailKey`.
  - In `calendar_day_indicators.dart` `_StoryAvatar`, replace the `ClipOval` child expression with:

```dart
        child:
            (url == null || url.isEmpty)
                ? ((key == null || key.isEmpty)
                    ? ColoredBox(color: colorScheme.surfaceContainerHighest)
                    : StoryKeyCachedImage(
                      storageKey: key,
                      decodeWidth: decodeWidth,
                      fallback: ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                      ),
                    ))
                : CachedNetworkImage(
                  imageUrl: url,
                  cacheKey: key,
                  useOldImageOnUrlChange: true,
                  memCacheWidth: decodeWidth,
                  fit: BoxFit.cover,
                  placeholder:
                      (_, __) => ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                      ),
                  errorWidget:
                      (_, __, ___) => ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                      ),
                ),
```

    Above the `return`, add:

```dart
    final decodeWidth =
        (kCalendarStoryAvatarDiameter *
                (MediaQuery.maybeDevicePixelRatioOf(context) ?? 3))
            .round();
```

    Then import `story_ring.dart` for `StoryKeyCachedImage`. Keep this file's existing older-formatter style by hand; do not run `dart format` on it.

- [ ] **Step 6: Run it.** Use the Step 3 command. Expected: PASS. Then run `dart format` on the new test file and on `ring_test_kit.dart`.

- [ ] **Step 7: Run the neighbours.**

```bash
flutter test test/features/stories test/features/timeline
```

Expected: PASS, with the goldens unchanged (the fallback paints the same neutral fill). If any suite shows an uncaught `path_provider` error from the disk lookup, set `debugStoryCachedThumbnail = (_) async => null;` in that file's `setUp`, and note which file in the task report.

---

### Task 5: The ring summary refreshes itself: coalesced, retried, expiring, evicting (L6, M2, M3 retry, E ring drops)

Fixes:
- 03 M2 and L6;
- 04 #15;
- the retry half of 03 M3 (checklist 3.9/3.10);
- the partner-delete half of 05 #6.

**Files:**
- Modify: `lib/features/stories/data/story_read_repository.dart`:
  - add `kStoryLifetime`;
  - add `StoryRingSummary.nextExpiresAt`, and parse `next_expires_at` when present.
- Create: `lib/features/stories/presentation/state/story_ring_refresh.dart`
- Modify: `story_providers.dart` (`storyRingSummaryProvider`)
- Modify: `test/features/stories/support/ring_test_kit.dart` (`ringRow(nextExpiresAt:)`)
- Create: `test/features/stories/story_ring_refresh_test.dart`

**Interfaces:**
- Consumes: `StoryVisibleRefresh`, `storyMediaEvictorProvider` (Task 3).
- Produces:

```dart
// story_read_repository.dart
const Duration kStoryLifetime; // 24 h, the server's expires_at = created_at + 24h
// StoryRingSummary gains: final DateTime? nextExpiresAt; (optional ctor arg; row 'next_expires_at')
// story_ring_refresh.dart
const int kStoryRingMaxAutoRetries; // 6
Duration storyRingRetryDelay(int failures); // 2, 4, 8, 16, 32, 60 s
Duration? storyRingExpiryDelay(Iterable<StoryRingSummary> rows, DateTime now);
Set<String> storyRingDroppedThumbnailKeys(Map<String, StoryRingSummary> previous, Map<String, StoryRingSummary> next, DateTime now);
class StoryRingFetch { final List<StoryRingSummary> rows; final DateTime startedAt; }
class StoryRingFetchCoalescer {
  Future<StoryRingFetch> run(String relationshipId, Future<List<StoryRingSummary>> Function() fetch);
  int recordFailure(String relationshipId); void resetFailures(String relationshipId);
  Map<String, StoryRingSummary>? previous(String relationshipId);
  void remember(String relationshipId, Map<String, StoryRingSummary> map);
}
final storyRingFetchCoalescerProvider; // Provider<StoryRingFetchCoalescer>, new per account
```

- [ ] **Step 1: Kit.** In `ring_test_kit.dart`, give `ringRow` the parameter `DateTime? nextExpiresAt` and pass it through as `nextExpiresAt: nextExpiresAt`. The file stops compiling until Step 4, which is expected.

- [ ] **Step 2: Write the failing tests.** Create `test/features/stories/story_ring_refresh_test.dart`:

```dart
// 03 M2/L6, 04 #15: the ring summary has one fetch in flight with at most
// one follow-up, retries a failed read on a backoff, re-reads when its
// newest story expires, waits while Attune is hidden, and evicts the
// thumbnail of a story the partner deleted.
import 'dart:async';

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_ring_refresh.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

void main() {
  group('storyRingExpiryDelay', () {
    final now = DateTime.utc(2026, 10, 24, 12);

    test('the newest story ending soon is due a second after its end', () {
      final rows = [ringRow(newest: now.subtract(const Duration(hours: 23, minutes: 59)))];
      expect(storyRingExpiryDelay(rows, now), const Duration(minutes: 1, seconds: 1));
    });

    test("the server's next_expires_at wins when present", () {
      final rows = [
        ringRow(
          newest: now.subtract(const Duration(hours: 1)),
          nextExpiresAt: now.add(const Duration(minutes: 5)),
        ),
      ];
      expect(storyRingExpiryDelay(rows, now), const Duration(minutes: 5, seconds: 1));
    });

    test('past by the phone clock but still listed: re-check in a minute, '
        'for ten minutes at most', () {
      final skewed = [ringRow(newest: now.subtract(const Duration(hours: 24, minutes: 3)))];
      expect(storyRingExpiryDelay(skewed, now), const Duration(minutes: 1));
      final stale = [ringRow(newest: now.subtract(const Duration(hours: 25)))];
      expect(storyRingExpiryDelay(stale, now), isNull);
      expect(storyRingExpiryDelay(const [], now), isNull);
    });
  });

  group('storyRingDroppedThumbnailKeys', () {
    final now = DateTime.utc(2026, 10, 24, 12);
    StoryRingSummary row(String key, Duration age, {int active = 1}) =>
        ringRow(key: key, active: active, newest: now.subtract(age));

    test('a deleted newest story drops its key; a newer post does not', () {
      final before = {ringPartner: row('b', const Duration(hours: 1), active: 2)};
      expect(
        storyRingDroppedThumbnailKeys(before, {ringPartner: row('a', const Duration(hours: 2))}, now),
        {'b'},
      );
      expect(
        storyRingDroppedThumbnailKeys(before, {ringPartner: row('c', Duration.zero, active: 3)}, now),
        isEmpty,
      );
    });

    test('an author gone before 24 h deleted it; after 24 h it only expired', () {
      expect(
        storyRingDroppedThumbnailKeys({ringPartner: row('b', const Duration(hours: 1))}, {}, now),
        {'b'},
      );
      expect(
        storyRingDroppedThumbnailKeys({ringPartner: row('b', const Duration(hours: 25))}, {}, now),
        isEmpty,
      );
    });
  });

  group('StoryRingFetchCoalescer', () {
    test('calls during a slow fetch share one follow-up (Review Focus 4)', () async {
      final coalescer = StoryRingFetchCoalescer();
      final gates = <Completer<List<StoryRingSummary>>>[];
      Future<List<StoryRingSummary>> fetch() {
        final gate = Completer<List<StoryRingSummary>>();
        gates.add(gate);
        return gate.future;
      }

      final first = coalescer.run('r', fetch);
      final followers = [for (var i = 0; i < 3; i++) coalescer.run('r', fetch)];
      expect(gates.length, 1);
      gates[0].complete(const []);
      await first;
      await pumpEventQueue();
      expect(gates.length, 2);
      gates[1].complete([ringRow()]);
      final results = await Future.wait(followers);
      expect(results.map((f) => f.rows.length), [1, 1, 1]);
      expect(gates.length, 2);
    });

    test('a failed fetch still runs the follow-up; a later call starts anew', () async {
      final coalescer = StoryRingFetchCoalescer();
      var calls = 0;
      Future<List<StoryRingSummary>> fetch() async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return const [];
      }

      final first = coalescer.run('r', fetch);
      final follower = coalescer.run('r', fetch);
      await expectLater(first, throwsStateError);
      await follower;
      expect(calls, 2);
      await coalescer.run('r', fetch);
      expect(calls, 3);
    });
  });

  group('storyRingSummaryProvider', () {
    testWidgets('re-reads when its newest story expires on screen (03 M2, 04 #15)', (
      tester,
    ) async {
      final gateway = RingGateway(
        summary: [ringRow(newest: clock.now().subtract(const Duration(hours: 23, minutes: 59)))],
      );
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump();
      expect(gateway.summaryCalls, 1);
      gateway.summary = [];
      await tester.pump(const Duration(seconds: 59));
      expect(gateway.summaryCalls, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(gateway.summaryCalls, 2);
      expect(c.read(storyRingSummaryProvider(ringRel)).valueOrNull, isEmpty);
      sub.close();
      c.dispose();
    });

    testWidgets('an expiry due while hidden waits for Attune to be back', (
      tester,
    ) async {
      final gateway = RingGateway(
        summary: [ringRow(newest: clock.now().subtract(const Duration(hours: 23, minutes: 59)))],
      );
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump();
      visibilityOf(c).set(false);
      await tester.pump(const Duration(minutes: 2));
      expect(gateway.summaryCalls, 1);
      visibilityOf(c).set(true);
      await tester.pump();
      await tester.pump();
      expect(gateway.summaryCalls, 2);
      sub.close();
      c.dispose();
    });

    testWidgets('a phone clock ahead of the server re-checks each minute, then '
        'stops (Review Focus 1)', (tester) async {
      final gateway = RingGateway(
        summary: [ringRow(newest: clock.now().subtract(const Duration(hours: 24, seconds: 30)))],
      );
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(gateway.summaryCalls, 2);
      await tester.pump(const Duration(minutes: 12));
      final settled = gateway.summaryCalls;
      expect(settled, lessThanOrEqualTo(12));
      await tester.pump(const Duration(minutes: 30));
      expect(gateway.summaryCalls, settled);
      sub.close();
      c.dispose();
    });

    testWidgets('a failed load retries on a backoff and stops after six', (
      tester,
    ) async {
      final gateway = RingGateway()..summaryError = StateError('offline');
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump();
      expect(gateway.summaryCalls, 1);
      for (final seconds in [2, 4, 8, 16, 32, 60]) {
        await tester.pump(Duration(seconds: seconds));
        await tester.pump();
      }
      expect(gateway.summaryCalls, 1 + kStoryRingMaxAutoRetries);
      await tester.pump(const Duration(minutes: 5));
      expect(gateway.summaryCalls, 1 + kStoryRingMaxAutoRetries);
      gateway.summaryError = null;
      c.invalidate(storyRingSummaryProvider(ringRel));
      await tester.pump();
      await tester.pump();
      expect(c.read(storyRingSummaryProvider(ringRel)).hasValue, isTrue);
      sub.close();
      c.dispose();
    });

    testWidgets('a burst of signals during a slow ring fetch costs one more '
        'call (Review Focus 4)', (tester) async {
      final gateway = RingGateway(summary: [ringRow()])
        ..summaryGate = Completer<void>();
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        gateway.emitSignal();
        await tester.pump();
      }
      c.invalidate(storyRingSummaryProvider(ringRel));
      await tester.pump();
      expect(gateway.summaryCalls, 1);
      final gate = gateway.summaryGate!;
      gateway.summaryGate = null;
      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(gateway.summaryCalls, 2);
      sub.close();
      c.dispose();
    });

    testWidgets('a re-read showing the partner deleted their newest story '
        'evicts its thumbnail (05 #6)', (tester) async {
      final now = clock.now();
      final evictor = RecordingEvictor();
      final gateway = RingGateway(
        summary: [ringRow(active: 2, key: 'b', newest: now.subtract(const Duration(hours: 1)))],
      );
      final c = ringContainer(
        gateway,
        overrides: [storyMediaEvictorProvider.overrideWithValue(evictor)],
      );
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump();
      gateway.summary = [ringRow(key: 'a', newest: now.subtract(const Duration(hours: 2)))];
      gateway.emitSignal();
      await tester.pump();
      await tester.pump();
      expect(evictor.evicted, ['b']);
      sub.close();
      c.dispose();
    });
  });

  test('next_expires_at is read when the server sends it', () {
    final row = StoryRingSummary.fromRow({
      'author_id': 'a',
      'active_count': 2,
      'unviewed_count': 1,
      'newest_thumbnail_key': 'k',
      'newest_created_at': '2026-10-24T10:00:00Z',
      'next_expires_at': '2026-10-24T11:00:00Z',
    });
    expect(row.nextExpiresAt, DateTime.utc(2026, 10, 24, 11));
    final legacy = StoryRingSummary.fromRow({
      'author_id': 'a',
      'active_count': 1,
      'unviewed_count': 0,
      'newest_thumbnail_key': 'k',
      'newest_created_at': '2026-10-24T10:00:00Z',
    });
    expect(legacy.nextExpiresAt, isNull);
  });
}
```

- [ ] **Step 3: Run it and watch it fail.**

```bash
flutter test test/features/stories/story_ring_refresh_test.dart
```

Expected: FAIL to compile, because `story_ring_refresh.dart`, `nextExpiresAt` and `kStoryLifetime` do not exist yet.

- [ ] **Step 4: Repository additions** (`story_read_repository.dart`, additive).

Above `class StoryRingSummary`, add:

```dart
/// How long a story stays in the reel: `expires_at = created_at + 24h` is a
/// CHECK on the table (STORIES.md §3.2). Used only to schedule a re-read
/// or to drop stale cached rows, never to decide expiry.
const Duration kStoryLifetime = Duration(hours: 24);
```

In `StoryRingSummary`:
- add `this.nextExpiresAt,` to the constructor;
- add the field `final DateTime? nextExpiresAt;` with a doc: "The soonest `expires_at` among this author's active stories, once the server returns it (Wave 5); null before".
- in `fromRow`, add:

```dart
      nextExpiresAt: row['next_expires_at'] == null
          ? null
          : DateTime.parse('${row['next_expires_at']}'),
```

- [ ] **Step 5: Create `lib/features/stories/presentation/state/story_ring_refresh.dart`.**

```dart
/// How the Conversations ring summary stays current without wasting calls
/// (03 M2, M3, L6; 04 #15): one fetch in flight per relationship with at
/// most one follow-up, a backoff after failures, a re-read when the newest
/// story expires, and which thumbnails a re-read shows were deleted.
library;

import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Automatic re-reads after a failed load before waiting for a signal,
/// a resume or Retry.
const int kStoryRingMaxAutoRetries = 6;

/// 2, 4, 8, 16, 32, then 60 s.
Duration storyRingRetryDelay(int failures) {
  final seconds = 2 << (failures - 1).clamp(0, 5);
  return Duration(seconds: seconds > 60 ? 60 : seconds);
}

const Duration kStoryRingExpirySlack = Duration(seconds: 1);
const Duration kStoryRingSkewRecheck = Duration(minutes: 1);
const Duration kStoryRingSkewWindow = Duration(minutes: 10);

/// When to re-read so a story leaves the ring once it expires (03 M2):
/// a second after the soonest end the summary knows (the server's
/// `next_expires_at`, else the newest story's 24 h end). A row already past
/// that end by the phone's clock but still listed by the server means the
/// clock runs ahead: look again each minute for ten minutes, then leave it
/// to the next signal or resume (Review Focus 1). Null when nothing is due.
Duration? storyRingExpiryDelay(Iterable<StoryRingSummary> rows, DateTime now) {
  DateTime? soonest;
  for (final row in rows) {
    if (row.activeCount <= 0) continue;
    final at = row.nextExpiresAt ?? row.newestCreatedAt.add(kStoryLifetime);
    if (soonest == null || at.isBefore(soonest)) soonest = at;
  }
  if (soonest == null) return null;
  final wait = soonest.difference(now) + kStoryRingExpirySlack;
  if (wait > Duration.zero) return wait;
  return -wait <= kStoryRingSkewWindow ? kStoryRingSkewRecheck : null;
}

/// Thumbnail keys a re-read shows were deleted (05 #6): an author's newest
/// key that changed to an older story's, or an author gone before their
/// newest story's 24 h ran out. A key replaced by a newer post, or gone
/// because it expired (it is still a calendar memory), is kept.
Set<String> storyRingDroppedThumbnailKeys(
  Map<String, StoryRingSummary> previous,
  Map<String, StoryRingSummary> next,
  DateTime now,
) {
  final dropped = <String>{};
  previous.forEach((author, before) {
    final after = next[author];
    if (after != null) {
      if (after.newestThumbnailKey == before.newestThumbnailKey) return;
      if (after.newestCreatedAt.isAfter(before.newestCreatedAt)) return;
    } else if (!before.newestCreatedAt.add(kStoryLifetime).isAfter(now)) {
      return;
    }
    dropped.add(before.newestThumbnailKey);
  });
  return dropped;
}

@immutable
class StoryRingFetch {
  const StoryRingFetch({required this.rows, required this.startedAt});
  final List<StoryRingSummary> rows;

  /// When the RPC was issued: a hold set before this is answered by it.
  final DateTime startedAt;
}

/// Per relationship: the fetch in flight, the one follow-up queued behind
/// it, the failure count and the last good map. Outlives the autoDispose
/// summary provider; a new one per account.
class StoryRingFetchCoalescer {
  final Map<String, Future<StoryRingFetch>> _inFlight = {};
  final Map<String, Future<StoryRingFetch>> _followUp = {};
  final Map<String, int> _failures = {};
  final Map<String, Map<String, StoryRingSummary>> _last = {};

  /// Runs [fetch], or joins work already queued: a call while a fetch is in
  /// flight waits for exactly one more fetch that starts after it, shared
  /// by every caller that arrives meanwhile (the pager's F3 scheme; no
  /// timers, so a lone signal still re-reads at once).
  Future<StoryRingFetch> run(
    String relationshipId,
    Future<List<StoryRingSummary>> Function() fetch,
  ) {
    final queued = _followUp[relationshipId];
    if (queued != null) return queued;
    final running = _inFlight[relationshipId];
    if (running == null) return _start(relationshipId, fetch);
    return _followUp[relationshipId] = running
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) {
          _followUp.remove(relationshipId);
          return _start(relationshipId, fetch);
        });
  }

  Future<StoryRingFetch> _start(
    String relationshipId,
    Future<List<StoryRingSummary>> Function() fetch,
  ) {
    final startedAt = clock.now();
    final future = Future.sync(
      fetch,
    ).then((rows) => StoryRingFetch(rows: rows, startedAt: startedAt));
    _inFlight[relationshipId] = future;
    void settle() {
      if (identical(_inFlight[relationshipId], future)) {
        _inFlight.remove(relationshipId);
      }
    }

    unawaited(future.then<void>((_) => settle(), onError: (Object _) => settle()));
    return future;
  }

  int recordFailure(String relationshipId) =>
      _failures[relationshipId] = (_failures[relationshipId] ?? 0) + 1;

  void resetFailures(String relationshipId) => _failures.remove(relationshipId);

  Map<String, StoryRingSummary>? previous(String relationshipId) =>
      _last[relationshipId];

  void remember(String relationshipId, Map<String, StoryRingSummary> map) =>
      _last[relationshipId] = map;
}

final storyRingFetchCoalescerProvider = Provider<StoryRingFetchCoalescer>((
  ref,
) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return StoryRingFetchCoalescer();
});
```

- [ ] **Step 6: Rewrite `storyRingSummaryProvider`** (`story_providers.dart`).

Add imports for `package:attune/features/stories/presentation/state/story_ring_refresh.dart` and `package:clock/clock.dart`. Keep the existing doc comment and append: "Wave 4: coalesced, retried, re-read at expiry, and evicts deleted thumbnails (story_ring_refresh.dart)." Replace the body:

```dart
final storyRingSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, StoryRingSummary>, String>((ref, relationshipId) async {
      ref.watch(storyChangeSignalProvider(relationshipId));
      final gateway = ref.watch(storyReadGatewayProvider);
      final coalescer = ref.watch(storyRingFetchCoalescerProvider);
      final refresh = StoryVisibleRefresh(ref);

      final StoryRingFetch fetch;
      try {
        fetch = await coalescer.run(
          relationshipId,
          () => gateway.getRingSummary(relationshipId: relationshipId),
        );
      } catch (_) {
        if (!refresh.disposed) {
          final failures = coalescer.recordFailure(relationshipId);
          if (failures <= kStoryRingMaxAutoRetries) {
            refresh.after(storyRingRetryDelay(failures));
          }
        }
        rethrow;
      }
      final map = {for (final row in fetch.rows) row.authorId: row};
      // A superseded build shares the live build's result: only the live
      // one records, schedules or evicts.
      if (refresh.disposed) return map;

      coalescer.resetFailures(relationshipId);
      final now = clock.now();
      final previous = coalescer.previous(relationshipId);
      coalescer.remember(relationshipId, map);
      if (previous != null) {
        final dropped = storyRingDroppedThumbnailKeys(previous, map, now);
        if (dropped.isNotEmpty) {
          unawaited(ref.read(storyMediaEvictorProvider).evict(dropped));
        }
      }
      final expiry = storyRingExpiryDelay(fetch.rows, now);
      if (expiry != null) refresh.after(expiry);
      return map;
    });
```

Run `dart format` on the new lib and test files.

- [ ] **Step 7: Run it.** Use the Step 3 command. Expected: PASS.

- [ ] **Step 8: Run the neighbours.**

```bash
flutter test test/features/stories test/features/timeline
```

Expected: PASS. This includes the existing `story_read_repository_test` "the signal must trigger a RE-READ of the ring summary", which counts 2 calls; with no overlap, the coalescer fetches at once. It also includes `story_reel_test`'s "at least one more fetch after the view".

---

### Task 6: The last-known rings, painted offline and after a failed load (M3)

Fixes: 03 M3 (checklist 1.3 and 5.1).

**Files:**
- Modify: `story_read_repository.dart` (`StoryRingSummary.toRow`)
- Create: `lib/features/stories/data/story_ring_last_known_store.dart`
- Modify: `story_ring_refresh.dart` (`storyRingRowsDiffer`)
- Modify: `story_providers.dart` (the write after success, and `storyRingLastKnownProvider`)
- Modify: `story_ring_copy.dart` (`storyRingsLoadErrorCopy`)
- Modify: `story_outbox_notices.dart` (`StoryRingsLoadErrorNotice`)
- Modify: `story_rings_row.dart`
- Modify: `ring_test_kit.dart`: `ringContainer` and `pumpRings` take `StoryRingLastKnownStore? lastKnown`, defaulting to a memory store.
- Create: `test/features/stories/story_ring_last_known_test.dart`

**Interfaces:**
- Consumes: `storyRingSummaryProvider` (Task 5), `storyRingFetchCoalescerProvider`.
- Produces:

```dart
// story_read_repository.dart
Map<String, Object?> StoryRingSummary.toRow();
// story_ring_last_known_store.dart
class StoryRingSnapshot { userId, relationshipId, savedAt, rows; toJson(); static StoryRingSnapshot? fromJson(Object?);
  Map<String, StoryRingSummary>? usableFor({required String userId, required String relationshipId, required DateTime now}); }
abstract class StoryRingLastKnownStore { Future<StoryRingSnapshot?> read(); Future<void> write(StoryRingSnapshot s); Future<void> clear(); }
class SecureStoryRingLastKnownStore implements StoryRingLastKnownStore;
class MemoryStoryRingLastKnownStore implements StoryRingLastKnownStore { StoryRingSnapshot? value; int writes; }
final storyRingLastKnownStoreProvider; // Provider<StoryRingLastKnownStore>
// story_ring_refresh.dart
bool storyRingRowsDiffer(Map<String, StoryRingSummary> a, Map<String, StoryRingSummary> b);
// story_providers.dart
final storyRingLastKnownProvider; // FutureProvider.autoDispose.family<Map<String, StoryRingSummary>?, String>
// story_ring_copy.dart
String storyRingsLoadErrorCopy({required bool showingLastKnown});
// story_outbox_notices.dart
class StoryRingsLoadErrorNotice extends StatelessWidget { const StoryRingsLoadErrorNotice({super.key, required bool showingLastKnown, required VoidCallback onRetry}); }
```

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_ring_last_known_test.dart`:

```dart
// 03 M3: a cold start offline, or a failed first read, paints the last
// rings this phone saw (ids, counts and storage keys only) instead of "Add
// to your story" and no partner ring, and says the read failed, with Retry.
import 'dart:async';

import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

StoryRingSnapshot _snapshot({
  String userId = ringMe,
  String relationshipId = ringRel,
  Duration age = const Duration(minutes: 5),
}) {
  final now = clock.now();
  return StoryRingSnapshot(
    userId: userId,
    relationshipId: relationshipId,
    savedAt: now.subtract(age),
    rows: [
      ringRow(author: ringMe, active: 3, unviewed: 0),
      ringRow(author: ringPartner, active: 2, unviewed: 2),
    ],
  );
}

void main() {
  group('StoryRingSnapshot', () {
    test('round-trips through JSON without URLs', () {
      final snapshot = _snapshot();
      final json = snapshot.toJson();
      expect(json.toString().contains('http'), isFalse);
      final back = StoryRingSnapshot.fromJson(json)!;
      expect(back.userId, ringMe);
      expect(back.rows.map((r) => r.activeCount), [3, 2]);
      expect(StoryRingSnapshot.fromJson('garbage'), isNull);
    });

    test('a snapshot from another account or relationship is never shown '
        '(Review Focus 2)', () {
      final now = clock.now();
      expect(
        _snapshot(userId: 'someone-else').usableFor(userId: ringMe, relationshipId: ringRel, now: now),
        isNull,
      );
      expect(
        _snapshot(relationshipId: 'old-rel').usableFor(userId: ringMe, relationshipId: ringRel, now: now),
        isNull,
      );
      expect(
        _snapshot(age: const Duration(hours: 25)).usableFor(userId: ringMe, relationshipId: ringRel, now: now),
        isNull,
      );
    });

    test('rows whose newest story is over a day old are dropped', () {
      final now = clock.now();
      final snapshot = StoryRingSnapshot(
        userId: ringMe,
        relationshipId: ringRel,
        savedAt: now,
        rows: [ringRow(newest: now.subtract(const Duration(hours: 25)))],
      );
      expect(
        snapshot.usableFor(userId: ringMe, relationshipId: ringRel, now: now),
        isEmpty,
      );
    });
  });

  testWidgets('a good read is saved once, and not rewritten unchanged', (
    tester,
  ) async {
    final store = MemoryStoryRingLastKnownStore();
    final gateway = RingGateway(summary: [ringRow()]);
    final c = ringContainer(gateway, lastKnown: store);
    final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
    await tester.pump();
    await tester.pump();
    expect(store.value!.rows.single.authorId, ringPartner);
    gateway.emitSignal();
    await tester.pump();
    await tester.pump();
    expect(store.writes, 1);
    sub.close();
    c.dispose();
  });

  testWidgets('while the first read is in flight, the last rings show', (
    tester,
  ) async {
    final gateway = RingGateway()..summaryGate = Completer<void>();
    await pumpRings(
      tester,
      gateway,
      lastKnown: MemoryStoryRingLastKnownStore()..value = _snapshot(),
    );
    await tester.pump();
    expect(mineRing(tester).segmentCount, 3);
    expect(find.byKey(const ValueKey('story-ring-partner')), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
  });

  testWidgets('a failed read keeps the last rings and offers Retry', (
    tester,
  ) async {
    final gateway = RingGateway()..summaryError = StateError('offline');
    await pumpRings(
      tester,
      gateway,
      lastKnown: MemoryStoryRingLastKnownStore()..value = _snapshot(),
    );
    await tester.pump();
    expect(find.text("Showing your last stories. Couldn't refresh."), findsOneWidget);
    expect(find.byKey(const ValueKey('story-ring-partner')), findsOneWidget);
    gateway
      ..summaryError = null
      ..summary = [ringRow()];
    final before = gateway.summaryCalls;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(gateway.summaryCalls, before + 1);
    expect(find.textContaining("Couldn't"), findsNothing);
  });

  testWidgets('a failed read with nothing saved says so', (tester) async {
    final gateway = RingGateway()..summaryError = StateError('offline');
    await pumpRings(tester, gateway);
    await tester.pump();
    expect(find.text("Couldn't load stories."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
```

Update the kit before running:
- give `ringContainer` and `pumpRings` the parameter `StoryRingLastKnownStore? lastKnown`;
- add `storyRingLastKnownStoreProvider.overrideWithValue(lastKnown ?? MemoryStoryRingLastKnownStore())` to both override lists;
- import `story_ring_last_known_store.dart`.

The kit will not compile until Step 3.

- [ ] **Step 2: Run it and watch it fail.**

```bash
flutter test test/features/stories/story_ring_last_known_test.dart
```

Expected: FAIL to compile, because `story_ring_last_known_store.dart` does not exist yet.

- [ ] **Step 3: `toRow` and the store.** Add to `StoryRingSummary`:

```dart
  /// The RPC row shape, for this phone's last-known snapshot (keys, never
  /// URLs).
  Map<String, Object?> toRow() => {
    'author_id': authorId,
    'active_count': activeCount,
    'unviewed_count': unviewedCount,
    'newest_thumbnail_key': newestThumbnailKey,
    'newest_created_at': newestCreatedAt.toUtc().toIso8601String(),
    if (nextExpiresAt != null)
      'next_expires_at': nextExpiresAt!.toUtc().toIso8601String(),
  };
```

Create `lib/features/stories/data/story_ring_last_known_store.dart`:

```dart
/// The last rings this phone saw (03 M3), so a cold start offline or a
/// failed first read paints them instead of "Add to your story". Holds ids,
/// counts, timestamps and storage keys only, never a URL. This device only
/// (Keychain `first_unlock_this_device`; Android encrypted prefs, already
/// excluded from backups). Cleared on sign-out, account switch, quick exit
/// and a relationship's pause, end or archive (story_device_wipe.dart).
library;

import 'dart:convert';

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoryRingSnapshot {
  const StoryRingSnapshot({
    required this.userId,
    required this.relationshipId,
    required this.savedAt,
    required this.rows,
  });

  final String userId;
  final String relationshipId;
  final DateTime savedAt;
  final List<StoryRingSummary> rows;

  Map<String, Object?> toJson() => {
    'v': 1,
    'user_id': userId,
    'relationship_id': relationshipId,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'rows': [for (final row in rows) row.toRow()],
  };

  static StoryRingSnapshot? fromJson(Object? json) {
    try {
      final map = Map<String, dynamic>.from(json! as Map);
      if (map['v'] != 1) return null;
      return StoryRingSnapshot(
        userId: '${map['user_id']}',
        relationshipId: '${map['relationship_id']}',
        savedAt: DateTime.parse('${map['saved_at']}'),
        rows: [
          for (final row in map['rows'] as List)
            StoryRingSummary.fromRow(Map<String, dynamic>.from(row as Map)),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// What may still be painted for [userId]'s [relationshipId] ring at
  /// [now]: rows whose newest story is under 24 h old. Null when the
  /// snapshot is someone else's, another relationship's, or over a day old.
  Map<String, StoryRingSummary>? usableFor({
    required String userId,
    required String relationshipId,
    required DateTime now,
  }) {
    if (userId != this.userId || relationshipId != this.relationshipId) {
      return null;
    }
    if (now.difference(savedAt) >= kStoryLifetime) return null;
    return {
      for (final row in rows)
        if (row.newestCreatedAt.add(kStoryLifetime).isAfter(now))
          row.authorId: row,
    };
  }
}

abstract class StoryRingLastKnownStore {
  Future<StoryRingSnapshot?> read();
  Future<void> write(StoryRingSnapshot snapshot);
  Future<void> clear();
}

class SecureStoryRingLastKnownStore implements StoryRingLastKnownStore {
  static const String storageKey = 'story_ring_last_known_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<StoryRingSnapshot?> read() async {
    try {
      final raw = await _storage.read(key: storageKey);
      return raw == null ? null : StoryRingSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(StoryRingSnapshot snapshot) async {
    try {
      await _storage.write(key: storageKey, value: jsonEncode(snapshot.toJson()));
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: storageKey);
    } catch (_) {}
  }
}

class MemoryStoryRingLastKnownStore implements StoryRingLastKnownStore {
  StoryRingSnapshot? value;
  int writes = 0;

  @override
  Future<StoryRingSnapshot?> read() async => value;

  @override
  Future<void> write(StoryRingSnapshot snapshot) async {
    writes++;
    value = snapshot;
  }

  @override
  Future<void> clear() async => value = null;
}

final storyRingLastKnownStoreProvider = Provider<StoryRingLastKnownStore>(
  (_) => SecureStoryRingLastKnownStore(),
);
```

- [ ] **Step 4: Save after a good read** (`story_providers.dart`).

Import `dart:convert` in `story_ring_refresh.dart`, and add there:

```dart
/// Whether two ring maps differ in anything the snapshot stores.
bool storyRingRowsDiffer(
  Map<String, StoryRingSummary> a,
  Map<String, StoryRingSummary> b,
) {
  String encode(Map<String, StoryRingSummary> m) => jsonEncode([
    for (final key in m.keys.toList()..sort()) m[key]!.toRow(),
  ]);
  return encode(a) != encode(b);
}
```

In `storyRingSummaryProvider`, right after `coalescer.remember(relationshipId, map);`, insert:

```dart
      // 03 M3: the last rings this phone saw, for a cold start offline.
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null &&
          (previous == null || storyRingRowsDiffer(previous, map))) {
        unawaited(
          ref.read(storyRingLastKnownStoreProvider).write(
            StoryRingSnapshot(
              userId: userId,
              relationshipId: relationshipId,
              savedAt: now,
              rows: fetch.rows,
            ),
          ),
        );
      }
```

Add, after the summary provider:

```dart
/// The rings to paint while this session's first read is in flight or has
/// failed (03 M3): the snapshot, if it is this account's and this
/// relationship's and under a day old.
final storyRingLastKnownProvider = FutureProvider.autoDispose
    .family<Map<String, StoryRingSummary>?, String>((ref, relationshipId) async {
      final userId = ref.watch(currentUserProvider.select((u) => u?.id));
      if (userId == null) return null;
      final snapshot = await ref.watch(storyRingLastKnownStoreProvider).read();
      return snapshot?.usableFor(
        userId: userId,
        relationshipId: relationshipId,
        now: clock.now(),
      );
    });
```

Import `story_ring_last_known_store.dart`.

- [ ] **Step 5: Copy and notice.** Add to `story_ring_copy.dart`:

```dart
/// Under the rings when a read failed (03 M3).
String storyRingsLoadErrorCopy({required bool showingLastKnown}) =>
    showingLastKnown
        ? "Showing your last stories. Couldn't refresh."
        : "Couldn't load stories.";
```

Add to `story_outbox_notices.dart`, importing `story_ring_copy.dart`:

```dart
/// Under the rings when their read failed (03 M3): says whether the rings
/// above are the last known ones, and offers Retry.
class StoryRingsLoadErrorNotice extends StatelessWidget {
  const StoryRingsLoadErrorNotice({
    super.key,
    required this.showingLastKnown,
    required this.onRetry,
  });

  final bool showingLastKnown;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _NoticeRow(
    icon: Icons.cloud_off_rounded,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    text: storyRingsLoadErrorCopy(showingLastKnown: showingLastKnown),
    actions: [_NoticeAction(label: 'Retry', onPressed: onRetry)],
  );
}
```

- [ ] **Step 6: The row** (`story_rings_row.dart`).

Import `story_ring_refresh.dart` and `story_ring_copy.dart`. Replace:

```dart
    final summaries = summariesAsync.valueOrNull ?? const {};
```

and its comment with:

```dart
    // 03 M3: until this session's first read lands, or when it fails,
    // paint the last rings this phone saw, and say so if the read failed.
    final live = summariesAsync.valueOrNull;
    final lastKnown = live == null
        ? ref.watch(storyRingLastKnownProvider(relationshipId)).valueOrNull
        : null;
    final summaries = live ?? lastKnown ?? const <String, StoryRingSummary>{};
    final loadFailed = live == null && summariesAsync.hasError;
```

In the `Column` children, directly after the ring `SizedBox`, add:

```dart
          if (loadFailed)
            StoryRingsLoadErrorNotice(
              showingLastKnown: lastKnown?.isNotEmpty ?? false,
              onRetry: () {
                ref
                    .read(storyRingFetchCoalescerProvider)
                    .resetFailures(relationshipId);
                ref.invalidate(storyRingSummaryProvider(relationshipId));
              },
            ),
```

- [ ] **Step 7: Run it.** Use the Step 2 command. Expected: PASS. Run `dart format` on the new lib and test files.

- [ ] **Step 8: Run the neighbours.**

```bash
flutter test test/features/stories test/features/timeline
```

Expected: PASS. Existing tests that do not override the store use the secure store. Its platform call fails in tests and is swallowed, so they see no snapshot.

---

### Task 7: The posted story never flashes back to `+`; a posting-only ring does not open an empty reel (M1, L1)

Fixes: 03 M1, 03 L1, 06 #17.

**Files:**
- Create: `lib/features/stories/presentation/state/story_posted_hold.dart`
- Modify: `lib/features/stories/data/story_media_vault.dart` (`readThumbnailBytes`)
- Modify: `lib/features/stories/presentation/state/story_outbox_controller.dart` (finalize success, around `:648–653`)
- Modify: `story_providers.dart` (release after a good read)
- Modify: `story_ring.dart` (`localThumbnailBytes`)
- Modify: `story_rings_row.dart` (the ring for mine)
- Modify: `story_ring_copy.dart` (`storyRingStillPostingCopy`)
- Create: `test/features/stories/story_posted_hold_test.dart`

**Interfaces:**
- Consumes: `StoryRingFetch.startedAt` (Task 5); `outbox_fakes.dart` (`outboxHarness`, `outboxRecord`, `forceOnce`).
- Produces:

```dart
// story_posted_hold.dart
const Duration kStoryPostedHoldCap; // 2 min
@immutable class StoryPostedHold { relationshipId, clientStoryId, heldAt, Uint8List? thumbnailBytes; }
class StoryPostedHolds extends StateNotifier<List<StoryPostedHold>> {
  void hold(StoryPostedHold hold);
  void releaseFetchedSince(String relationshipId, DateTime fetchStartedAt);
}
final storyPostedHoldsProvider; // StateNotifierProvider<StoryPostedHolds, List<StoryPostedHold>>
// story_media_vault.dart
Future<Uint8List?> StoryMediaVault.readThumbnailBytes(StoryOutboxRecord record);
// story_ring.dart: StoryRing gains final Uint8List? localThumbnailBytes;
// story_ring_copy.dart
const String storyRingStillPostingCopy; // "Still posting. It'll be here in a moment."
```

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_posted_hold_test.dart`:

```dart
// 03 M1: between finalize and the next ring summary, my ring keeps showing
// the story I just posted instead of flashing back to `+`. 03 L1: tapping
// a ring whose only story is still posting says so instead of opening an
// empty reel.
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/presentation/state/story_posted_hold.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/outbox_fakes.dart';
import 'support/ring_test_kit.dart';

void main() {
  test('a story that posts leaves a hold carrying its thumbnail', () async {
    final dir = await Directory.systemTemp.createTemp('hold');
    addTearDown(() => dir.delete(recursive: true));
    final h = outboxHarness();
    addTearDown(h.container.dispose);
    await h.store.put(outboxUserId, outboxRecord(dir));
    await forceOnce(h);
    final hold = h.container.read(storyPostedHoldsProvider).single;
    expect(hold.clientStoryId, 'cid-1');
    expect(hold.relationshipId, 'rel-1');
    expect(hold.thumbnailBytes, [4, 5]);
  });

  testWidgets('a hold is released only by a read issued after it, or by the cap', (
    tester,
  ) async {
    final holds = StoryPostedHolds();
    final heldAt = clock.now();
    holds.hold(StoryPostedHold(relationshipId: 'r', clientStoryId: 'c', heldAt: heldAt));
    holds.releaseFetchedSince('r', heldAt.subtract(const Duration(seconds: 1)));
    expect(holds.state, hasLength(1));
    holds.releaseFetchedSince('other', heldAt);
    expect(holds.state, hasLength(1));
    holds.releaseFetchedSince('r', heldAt);
    expect(holds.state, isEmpty);
    holds.hold(StoryPostedHold(relationshipId: 'r', clientStoryId: 'd', heldAt: clock.now()));
    await tester.pump(kStoryPostedHoldCap);
    expect(holds.state, isEmpty);
    holds.dispose();
  });

  testWidgets('my ring keeps the posted story until the summary has it', (
    tester,
  ) async {
    final gateway = RingGateway();
    final holds = StoryPostedHolds();
    await pumpRings(
      tester,
      gateway,
      overrides: [storyPostedHoldsProvider.overrideWith((_) => holds)],
    );
    holds.hold(
      StoryPostedHold(
        relationshipId: ringRel,
        clientStoryId: 'c1',
        heldAt: clock.now(),
        thumbnailBytes: Uint8List.fromList([1, 2, 3]),
      ),
    );
    await tester.pump();
    expect(mineRing(tester).hasStories, isTrue);
    expect(mineRing(tester).segmentCount, 1);
    expect(mineRing(tester).localThumbnailBytes, isNotNull);

    gateway.summary = [ringRow(author: ringMe, active: 1, unviewed: 0)];
    gateway.emitSignal();
    await tester.pump();
    await tester.pump();
    expect(holds.state, isEmpty);
    expect(mineRing(tester).segmentCount, 1);
    expect(mineRing(tester).thumbnailUrl, isNotNull);
  });

  testWidgets('tapping a ring that is only posting says so (03 L1)', (
    tester,
  ) async {
    var opened = 0;
    await pumpRings(
      tester,
      RingGateway(),
      onOpenMine: () => opened++,
      outbox: [
        StoryOutboxRecord(
          clientStoryId: 'p1',
          relationshipId: ringRel,
          localMediaPath: '/tmp/none-media.jpg',
          localThumbnailPath: '',
          mediaType: CapturedMediaType.image,
          mimeType: 'image/jpeg',
          width: 1080,
          height: 1920,
          utcOffsetMinutes: 0,
          state: StoryOutboxState.uploadingMedia,
          createdAt: DateTime.utc(2026, 10, 24, 8),
        ),
      ],
    );
    await tester.pump();
    final corner = tester.getTopLeft(find.byKey(const ValueKey('story-ring-mine')));
    await tester.tapAt(corner + const Offset(34.5, 34.5));
    await tester.pump();
    expect(opened, 0);
    expect(find.text("Still posting. It'll be here in a moment."), findsOneWidget);
  });
}
```

Notes:
- `pumpRings` already overrides some providers. Overriding `storyPostedHoldsProvider` via `overrides` is fine because the kit does not override it.
- The widget tests never pump for 2 minutes with a hold set, except the cap test. That test owns its notifier and disposes it.

- [ ] **Step 2: Run it and watch it fail.**

```bash
flutter test test/features/stories/story_posted_hold_test.dart
```

Expected: FAIL to compile, because `story_posted_hold.dart` does not exist yet.

- [ ] **Step 3: Create `lib/features/stories/presentation/state/story_posted_hold.dart`.**

```dart
/// A story that just posted, kept on my ring until a ring summary issued
/// after it arrives (03 M1). Finalize removes the outbox row and the local
/// capture at once, but the summary only learns of the post on its next
/// read; without this the ring flashed back to `+` (or to the previous
/// story) in between, and stayed there while realtime was down. In memory
/// only, with the thumbnail's bytes (the file is already gone), and never
/// longer than [kStoryPostedHoldCap].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Duration kStoryPostedHoldCap = Duration(minutes: 2);

@immutable
class StoryPostedHold {
  const StoryPostedHold({
    required this.relationshipId,
    required this.clientStoryId,
    required this.heldAt,
    this.thumbnailBytes,
  });

  final String relationshipId;
  final String clientStoryId;
  final DateTime heldAt;
  final Uint8List? thumbnailBytes;
}

class StoryPostedHolds extends StateNotifier<List<StoryPostedHold>> {
  StoryPostedHolds() : super(const []);

  final Map<String, Timer> _caps = {};

  void hold(StoryPostedHold hold) {
    if (!mounted) return;
    state = [
      for (final h in state)
        if (h.clientStoryId != hold.clientStoryId) h,
      hold,
    ];
    _caps.remove(hold.clientStoryId)?.cancel();
    _caps[hold.clientStoryId] = Timer(
      kStoryPostedHoldCap,
      () => _drop((h) => h.clientStoryId == hold.clientStoryId),
    );
  }

  /// A ring read for [relationshipId] issued at [fetchStartedAt] landed:
  /// every hold set at or before then is answered by it.
  void releaseFetchedSince(String relationshipId, DateTime fetchStartedAt) =>
      _drop(
        (h) =>
            h.relationshipId == relationshipId &&
            !h.heldAt.isAfter(fetchStartedAt),
      );

  void _drop(bool Function(StoryPostedHold hold) test) {
    if (!mounted) return;
    final gone = state.where(test).toList();
    if (gone.isEmpty) return;
    for (final hold in gone) {
      _caps.remove(hold.clientStoryId)?.cancel();
    }
    state = [
      for (final h in state)
        if (!test(h)) h,
    ];
  }

  @override
  void dispose() {
    for (final timer in _caps.values) {
      timer.cancel();
    }
    _caps.clear();
    super.dispose();
  }
}

/// Per account: a new, empty list on every sign-in.
final storyPostedHoldsProvider =
    StateNotifierProvider<StoryPostedHolds, List<StoryPostedHold>>((ref) {
      ref.watch(currentUserProvider.select((u) => u?.id));
      return StoryPostedHolds();
    });
```

- [ ] **Step 4: Vault.** Add to `StoryMediaVault`, importing `dart:typed_data`:

```dart
  /// The record's thumbnail bytes, for the ring's posted hold (03 M1), or
  /// null when missing, unreadable or over 512 KB. Never throws.
  Future<Uint8List?> readThumbnailBytes(StoryOutboxRecord record) async {
    try {
      final path = await resolve(record.localThumbnailPath);
      if (path.isEmpty) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.length > 512 * 1024 ? null : bytes;
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 5: Controller.** In `story_outbox_controller.dart`, import `story_posted_hold.dart` and `package:attune/features/stories/presentation/providers/story_providers.dart`. Replace the success block after `if (_halt(epoch, id)) return;` that follows `finalizeStory`:

```dart
        // Success — whether this call created the story or landed on an
        // existing one via the idempotency key, the outcome for the
        // client is identical: the story exists, stop posting it.
        // 03 M1: keep it on my ring until a summary issued after now lands.
        final thumbnailBytes = await _vault.readThumbnailBytes(current);
        if (_halt(epoch, id)) return;
        _ref
            .read(storyPostedHoldsProvider.notifier)
            .hold(
              StoryPostedHold(
                relationshipId: current.relationshipId,
                clientStoryId: current.clientStoryId,
                heldAt: clock.now(),
                thumbnailBytes: thumbnailBytes,
              ),
            );
        await _vault.deleteFor(current);
        await _store.remove(_userId, current.clientStoryId);
        await _refreshState();
        // The realtime signal can be missed: ask for the summary now.
        _ref.invalidate(storyRingSummaryProvider(current.relationshipId));
```

- [ ] **Step 6: Release.** In `storyRingSummaryProvider`, right after `coalescer.resetFailures(relationshipId);`, insert:

```dart
      ref
          .read(storyPostedHoldsProvider.notifier)
          .releaseFetchedSince(relationshipId, fetch.startedAt);
```

Import `story_posted_hold.dart`.

- [ ] **Step 7: Ring bytes.** In `StoryRing`, add `this.localThumbnailBytes,` after `this.localThumbnailPath,`, plus the field:

```dart
  /// The thumbnail of a story that just posted (03 M1), in memory: its
  /// local file is already deleted and the summary may not know it yet.
  final Uint8List? localThumbnailBytes;
```

Pass it to `_Thumbnail` (a new `localThumbnailBytes` field). In `_Thumbnail.build`, after the `localPath` branch, add:

```dart
    } else if (localThumbnailBytes != null) {
      image = Image.memory(
        localThumbnailBytes!,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => neutral,
      );
```

Import `dart:typed_data`.

- [ ] **Step 8: The row.** Add to `story_ring_copy.dart`:

```dart
/// A ring whose only story is still posting (03 L1).
const String storyRingStillPostingCopy =
    "Still posting. It'll be here in a moment.";
```

In `story_rings_row.dart`, import `story_posted_hold.dart`. After `final uploadProgress = …;`, add:

```dart
    StoryPostedHold? myHold;
    for (final hold in ref.watch(storyPostedHoldsProvider)) {
      if (hold.relationshipId == relationshipId) myHold = hold;
    }
```

Replace the `final myRing = …;` expression, including the `myUnviewedCount` lines above it, with:

```dart
    final Widget myRing;
    if (myPending == null && myHold != null) {
      // 03 M1: posted, and the summary has not caught up yet.
      final count = mySegmentCount + 1;
      myRing = StoryRing(
        key: const ValueKey('story-ring-mine'),
        isMine: true,
        hasStories: true,
        segmentCount: count,
        unviewedCount: count,
        localThumbnailBytes: myHold.thumbnailBytes,
        onTap: onOpenMine,
        onTapPlus: onCapture,
        semanticLabel: storyRingMineLabel(count),
      );
    } else if (myPending == null && mySegmentCount > 0) {
      myRing = _MineRing(
        key: const ValueKey('story-ring-mine'),
        summary: mySummary!,
        onTap: onOpenMine,
        onTapPlus: onCapture,
      );
    } else {
      // My own segments are always bright: unviewed_count on my own row is
      // the partner's view of me (StoryRingSummary), never mine.
      final pending = myPending;
      myRing = StoryRing(
        key: const ValueKey('story-ring-mine'),
        isMine: true,
        hasStories: pending != null || mySegmentCount > 0,
        segmentCount: mySegmentCount,
        unviewedCount: mySegmentCount,
        localThumbnailPath: pending?.localThumbnailPath,
        pendingProgress: pending == null
            ? null
            : _pendingProgressFor(
                pending.state,
                mediaFraction: uploadProgress[pending.clientStoryId],
              ),
        // 03 L1: with nothing on the server yet there is no reel to open.
        onTap: pending == null
            ? null
            : mySegmentCount > 0
            ? onOpenMine
            : () => _showStillPosting(context),
        onTapPlus: onCapture,
        semanticLabel: pending != null
            ? storyRingPostingLabel(mySegmentCount)
            : storyRingAddLabel,
      );
    }
```

Keep the long comment that explained why `unviewedCount` mirrors `segmentCount`, shortened as above. Add this method to `StoryRingsRow`:

```dart
  void _showStillPosting(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(storyRingStillPostingCopy)));
  }
```

- [ ] **Step 9: Run it.** Use the Step 2 command. Expected: PASS. Run `dart format` on the new files.

- [ ] **Step 10: Run the neighbours.**

```bash
flutter test test/features/stories
```

Expected: PASS, including every outbox suite. The hold is additive; the record is still removed at once.

---

### Task 8: Posts stuck for a previous relationship have a surface (M6)

Fixes: 03 M6 (spec §6.1 "never silently disappears").

**Files:**
- Modify: `story_ring_copy.dart` (orphan copy)
- Modify: `story_outbox_notices.dart` (`StoryOrphanedPostsNotice`)
- Modify: `story_rings_row.dart` (one line)
- Modify: `lib/features/chat/presentation/screens/conversations_screen.dart` (one line when there is no active relationship)
- Create: `test/features/stories/story_orphaned_posts_test.dart`

**Interfaces:**
- Consumes: `storyOutboxProvider`, `StoryOutboxController.discard` and `.cancel` (Wave 2).
- Produces:

```dart
String storyOrphanedPostsCopy(int count);
class StoryOrphanedPostsNotice extends ConsumerWidget { const StoryOrphanedPostsNotice({super.key, required String? activeRelationshipId}); }
```

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_orphaned_posts_test.dart`:

```dart
// 03 M6: a story queued for a relationship that is no longer the one shown
// (ended, archived) can never post. It used to sit on the phone with no
// surface anywhere; it now gets one grouped notice with Discard.
import 'dart:io';

import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

StoryOutboxRecord _record(String id, String relationshipId, StoryOutboxState state) =>
    StoryOutboxRecord(
      clientStoryId: id,
      relationshipId: relationshipId,
      localMediaPath: '/tmp/$id-media.jpg',
      localThumbnailPath: '',
      mediaType: CapturedMediaType.image,
      mimeType: 'image/jpeg',
      width: 1080,
      height: 1920,
      utcOffsetMinutes: 0,
      state: state,
      createdAt: DateTime.utc(2026, 10, 20, 8),
    );

void main() {
  testWidgets("a failed post for a previous relationship says so and can go", (
    tester,
  ) async {
    await pumpRings(
      tester,
      RingGateway(),
      outbox: [_record('o1', 'rel-old', StoryOutboxState.failedPermanent)],
    );
    await tester.pump();
    expect(
      find.text("A story for a previous relationship couldn't be posted."),
      findsOneWidget,
    );
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this story?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('previous relationship'), findsNothing);
  });

  testWidgets('two of them are one notice, counted', (tester) async {
    await pumpRings(
      tester,
      RingGateway(),
      outbox: [
        _record('o1', 'rel-old', StoryOutboxState.failedPermanent),
        _record('o2', 'rel-older', StoryOutboxState.failedPermanent),
      ],
    );
    await tester.pump();
    expect(
      find.text("2 stories for a previous relationship couldn't be posted."),
      findsOneWidget,
    );
  });

  testWidgets("this relationship's own failed post is not an orphan", (
    tester,
  ) async {
    await pumpRings(
      tester,
      RingGateway(),
      outbox: [_record('f1', ringRel, StoryOutboxState.failedPermanent)],
    );
    await tester.pump();
    expect(find.textContaining('previous relationship'), findsNothing);
  });

  test('Conversations shows the notice when there is no active relationship', () {
    final screen = File(
      'lib/features/chat/presentation/screens/conversations_screen.dart',
    ).readAsStringSync();
    expect(
      screen.contains('StoryOrphanedPostsNotice(activeRelationshipId: null)'),
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run it and watch it fail.**

```bash
flutter test test/features/stories/story_orphaned_posts_test.dart
```

Expected: FAIL. The orphan text is absent, and the source check is false.

- [ ] **Step 3: Copy and notice.** Add to `story_ring_copy.dart`:

```dart
/// Stories queued for a relationship that is not the one shown (03 M6).
String storyOrphanedPostsCopy(int count) => count == 1
    ? "A story for a previous relationship couldn't be posted."
    : "$count stories for a previous relationship couldn't be posted.";
```

Add to `story_outbox_notices.dart`:

```dart
/// Outbox records for any relationship other than [activeRelationshipId]
/// (03 M6): they can never post, so they get one grouped line with
/// Discard. No Retry, because there is nowhere to post them.
class StoryOrphanedPostsNotice extends ConsumerWidget {
  const StoryOrphanedPostsNotice({
    super.key,
    required this.activeRelationshipId,
  });

  /// The relationship the rings show, or null when there is none.
  final String? activeRelationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orphans = [
      for (final record in ref.watch(storyOutboxProvider))
        if (record.relationshipId != activeRelationshipId) record,
    ];
    if (orphans.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(storyOutboxProvider.notifier);
    final one = orphans.length == 1;
    return _NoticeRow(
      icon: Icons.error_outline_rounded,
      color: Theme.of(context).colorScheme.error,
      text: storyOrphanedPostsCopy(orphans.length),
      actions: [
        _NoticeAction(
          label: 'Discard',
          onPressed: () async {
            final ok = await _confirm(
              context,
              title: one ? 'Discard this story?' : 'Discard these stories?',
              body: one
                  ? "It hasn't been posted, and it can't be recovered."
                  : "They haven't been posted, and they can't be recovered.",
              keep: 'Keep',
              destroy: 'Discard',
            );
            if (!ok) return;
            for (final record in orphans) {
              if (record.state == StoryOutboxState.failedPermanent) {
                await notifier.discard(record.clientStoryId);
              } else {
                await notifier.cancel(record.clientStoryId);
              }
            }
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Place it.**
  - In `story_rings_row.dart`, add `StoryOrphanedPostsNotice(activeRelationshipId: relationshipId),` to the `Column` after the `for (final failed in myFailed)` line.
  - In `conversations_screen.dart`, inside the `ListView`'s `children`, directly before the `SettleIn(… duration: _settleFor(1) …)` card, add:

```dart
                    // 03 M6: a story queued for a previous relationship has
                    // nowhere else to say it could not post.
                    if (filtered.isEmpty)
                      const StoryOrphanedPostsNotice(activeRelationshipId: null),
```

    Import `package:attune/features/stories/presentation/widgets/story_outbox_notices.dart`. Change nothing else on this screen, and do not run `dart format` on it.

- [ ] **Step 5: Run it.** Use the Step 2 command. Expected: PASS. Run `dart format` on the new test file.

- [ ] **Step 6: Run the neighbours.**

```bash
flutter test test/features/stories test/features/chat/presentation
```

Expected: PASS.

---

### Task 9: Story data leaves the phone on sign-out, quick exit and a relationship's pause, end or archive (05 #6)

**Files:**
- Create: `lib/features/stories/data/story_device_wipe.dart`
- Modify: `lib/features/stories/data/story_outbox_wipe.dart` (a cache step running beside rows and files)
- Modify: `lib/features/safety/domain/services/quick_exit_service.dart`
- Modify: `lib/features/relationships/presentation/relationship_lifecycle_providers.dart`
- Create: `test/features/stories/story_device_wipe_test.dart`

**Interfaces:**
- Consumes:
  - `StorySignedUrlCache.clearEveryLiveCache` (Task 3);
  - `StoryRingLastKnownStore` and `SecureStoryRingLastKnownStore` (Task 6);
  - `ChatImageCache.clear`.
- Produces:

```dart
// story_device_wipe.dart
Future<void> clearStoryDeviceCaches({bool includeImages = true, ChatImageCache? images, StoryRingLastKnownStore? lastKnown});
// story_outbox_wipe.dart
StoryOutboxWiper(Ref ref, {Duration bound, Future<void> Function()? clearCaches});
// quick_exit_service.dart
@visibleForTesting static Future<void> Function() QuickExitService.clearStories; // = clearStoryDeviceCaches
// relationship_lifecycle_providers.dart
Future<void> clearLifecycleDeviceSurfaces({Future<void> Function() together, Future<void> Function() stories});
```

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_device_wipe_test.dart`:

```dart
// 05 #6: story thumbnails, signed URLs and the last-known rings leave the
// phone on sign-out, account switch, quick exit and a relationship's pause,
// end or archive.
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_outbox_wipe.dart';
import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/data/story_signed_url_cache.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ring_test_kit.dart';

class _ThrowingImages implements ChatImageCache {
  @override
  Future<void> clear() async => throw StateError('store gone');
  @override
  Future<void> removeKeys(Iterable<String> keys) async {}
}

void main() {
  test('clearing forgets URLs, empties the image cache and the snapshot', () async {
    final urls = StorySignedUrlCache()..put('k', 'u');
    addTearDown(urls.dispose);
    final images = NoopImageCache();
    final lastKnown = MemoryStoryRingLastKnownStore()
      ..value = StoryRingSnapshot(
        userId: ringMe,
        relationshipId: ringRel,
        savedAt: DateTime.now(),
        rows: const [],
      );
    await clearStoryDeviceCaches(images: images, lastKnown: lastKnown);
    expect(urls.fresh('k'), isNull);
    expect(images.clears, 1);
    expect(lastKnown.value, isNull);
  });

  test('without images, and a failing image step skips nothing', () async {
    final images = NoopImageCache();
    final lastKnown = MemoryStoryRingLastKnownStore()
      ..value = StoryRingSnapshot(
        userId: ringMe,
        relationshipId: ringRel,
        savedAt: DateTime.now(),
        rows: const [],
      );
    await clearStoryDeviceCaches(includeImages: false, images: images, lastKnown: lastKnown);
    expect(images.clears, 0);
    expect(lastKnown.value, isNull);
    lastKnown.value = StoryRingSnapshot(
      userId: ringMe,
      relationshipId: ringRel,
      savedAt: DateTime.now(),
      rows: const [],
    );
    await clearStoryDeviceCaches(images: _ThrowingImages(), lastKnown: lastKnown);
    expect(lastKnown.value, isNull);
  });

  test('sign-out and account switch run the cache step', () async {
    final dir = await Directory.systemTemp.createTemp('wipe');
    addTearDown(() => dir.delete(recursive: true));
    var clears = 0;
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(ringUser),
        storyOutboxStoreProvider.overrideWithValue(
          StoryOutboxStore.forTesting(stub.createStoryOutboxBackend()),
        ),
        storyMediaVaultProvider.overrideWithValue(
          StoryMediaVault(supportDirectory: () async => dir),
        ),
      ],
    );
    addTearDown(container.dispose);
    final wiper = StoryOutboxWiper(
      container.read(_refProvider),
      clearCaches: () async => clears++,
    );
    await wiper.wipeAll();
    await wiper.wipeExcept(ringMe);
    expect(clears, 2);
  });

  testWidgets('quick exit clears the story caches', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    var cleared = 0;
    QuickExitService.clearStories = () async => cleared++;
    QuickExitService.exitOverride = () async {};
    addTearDown(() {
      QuickExitService.clearStories = clearStoryDeviceCaches;
      QuickExitService.exitOverride = null;
    });
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
        GoRoute(
          path: '/neutralScreen',
          name: 'neutralScreen',
          builder: (_, __) => const Text('DECOY'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.runAsync(() => QuickExitService.executeWithRouter(router));
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });

  test("a relationship's change clears Together and stories, each on its own", () async {
    final calls = <String>[];
    await clearLifecycleDeviceSurfaces(
      together: () async {
        calls.add('together');
        throw StateError('widget gone');
      },
      stories: () async => calls.add('stories'),
    );
    expect(calls, ['together', 'stories']);
    final source = File(
      'lib/features/relationships/presentation/relationship_lifecycle_providers.dart',
    ).readAsStringSync();
    expect(source.contains('clearLifecycleDeviceSurfaces'), isTrue);
  });
}
```

`StoryOutboxWiper` takes a `Ref`. Hand it one through a provider: add `final _refProvider = Provider<Ref>((ref) => ref);` at the top level of this test file.

- [ ] **Step 2: Run it and watch it fail.**

```bash
flutter test test/features/stories/story_device_wipe_test.dart
```

Expected: FAIL to compile, because `story_device_wipe.dart`, `clearCaches`, `clearStories` and `clearLifecycleDeviceSurfaces` do not exist yet.

- [ ] **Step 3: Create `lib/features/stories/data/story_device_wipe.dart`.**

```dart
/// What stories keep on this phone outside the outbox (05 #6): signed URLs
/// in memory, thumbnails in the shared image cache, and the last-known
/// rings snapshot. Quick exit and a relationship's pause, end or archive
/// clear all three. Sign-out passes `includeImages: false`, because it
/// already empties the image cache (auth_provider.dart wipeImages). Never
/// throws; each part on its own.
library;

import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/data/story_signed_url_cache.dart';

Future<void> clearStoryDeviceCaches({
  bool includeImages = true,
  ChatImageCache? images,
  StoryRingLastKnownStore? lastKnown,
}) async {
  StorySignedUrlCache.clearEveryLiveCache();
  await Future.wait([
    if (includeImages) _quietly(() => (images ?? ChatImageCache()).clear()),
    _quietly(() => (lastKnown ?? SecureStoryRingLastKnownStore()).clear()),
  ]);
}

Future<void> _quietly(Future<void> Function() step) async {
  try {
    await step();
  } catch (_) {}
}
```

- [ ] **Step 4: The wiper** (`story_outbox_wipe.dart`). Import `story_device_wipe.dart` and `story_ring_last_known_store.dart`. Change the constructor and add the field:

```dart
  StoryOutboxWiper(
    this._ref, {
    this.bound = const Duration(seconds: 3),
    Future<void> Function()? clearCaches,
  }) : _clearCaches = clearCaches;

  /// Signed URLs and the last-known rings (05 #6). Test seam.
  final Future<void> Function()? _clearCaches;

  Future<void> _caches() =>
      (_clearCaches ??
          () => clearStoryDeviceCaches(
            includeImages: false,
            lastKnown: _ref.read(storyRingLastKnownStoreProvider),
          ))();
```

In `_run`, start the cache step first, so it shares the one bound and runs beside the rows and the files, and await it last:

```dart
    final caches = _caches().timeout(bound).catchError((Object e) {
      debugPrint('⚠️ [STORIES] cache wipe failed: ${e.runtimeType}');
    });
    // … the existing rows and files steps, unchanged …
    await caches;
```

Update the class doc to read: "rows, capture files, and the story caches (signed URLs and last-known rings)".

- [ ] **Step 5: Quick exit.** In `quick_exit_service.dart`, import `package:attune/features/stories/data/story_device_wipe.dart`, then add below `exitOverride`:

```dart
  /// Story thumbnails, signed URLs and the last-known rings (05 #6).
  @visibleForTesting
  static Future<void> Function() clearStories = clearStoryDeviceCaches;
```

In `_run`, after `unawaited(clearCoupleMapDeviceData());`:

```dart
    // Story thumbnails sit in the shared image cache; empty it, with the
    // story URLs and rings snapshot (05 #6).
    unawaited(clearStories().catchError((Object _) {}));
```

The existing wiring test bans `http`, `Supabase`, `analytics`, `debugPrint` and `log(` from this file; none is added.

- [ ] **Step 6: Lifecycle.** In `relationship_lifecycle_providers.dart`, import `story_device_wipe.dart` and replace `lifecycleClearSurfacesProvider`:

```dart
/// The home-screen card, lock-screen plan and calendar copy (F1 (6)), and
/// since stories Wave 4 the story caches on this phone (05 #6).
final lifecycleClearSurfacesProvider = Provider<Future<void> Function()>(
  (_) => () => clearLifecycleDeviceSurfaces(),
);

/// Each part on its own: a failure in one never skips the other.
Future<void> clearLifecycleDeviceSurfaces({
  Future<void> Function() together = clearTogetherDeviceSurfaces,
  Future<void> Function() stories = clearStoryDeviceCaches,
}) async {
  try {
    await together();
  } catch (_) {}
  try {
    await stories();
  } catch (_) {}
}
```

Keep the original one-line doc's wording, and append the Wave 4 sentence as above.

- [ ] **Step 7: Run it.** Use the Step 2 command. Expected: PASS. Run `dart format` on the two new files.

- [ ] **Step 8: Run the neighbours.**

```bash
flutter test test/features/stories test/features/safety test/features/relationships test/features/auth
```

Expected: PASS. If `quick_exit_service_test.dart` flakes on the real image cache, add `QuickExitService.clearStories = () async {};` to that test's setup and restore it in `addTearDown`. Report it if so.

---

### Task 10: A calendar day's ring plays only its author's stories (04 #4, reel side)

**Files:**
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart`:
  - the `forDay` constructor gains `dayAuthorId`;
  - `_visible`, `_buildLoaded`, `_advanceAtEndOfPage` and `_resolveStartIndex` change;
  - add the new `_fillAuthorPage`.
- Modify: `test/features/stories/support/reel_test_kit.dart` (`kitReel` and `pumpReel` take `dayAuthorId`)
- Create: `test/features/stories/story_reel_day_author_test.dart`

**Interfaces:**
- Consumes: `kStoryStartSearchMaxPages`, `_pagerHasMore` and `_pagerLoadMore` (Wave 1).
- Produces: `StoryReelScreen.forDay({…, String? dayAuthorId})` and the field `final String? dayAuthorId;`, which is null in the other constructors.

- [ ] **Step 1: Kit.** In `reel_test_kit.dart`:
  - give `kitReel` and `pumpReel` the parameter `String? dayAuthorId`;
  - pass it through from `pumpReel` to `kitReel`;
  - pass `dayAuthorId: dayAuthorId` in the `KitMode.day` case.

- [ ] **Step 2: Write the failing tests.** Create `test/features/stories/story_reel_day_author_test.dart`:

```dart
// 04 #4: each per-author ring on a calendar day opens that author's
// stories only: the partner's at the first one I have not seen, mine at
// my oldest. Until Wave 5 adds p_author_id, the reel filters the day's
// pages itself, so an author whose stories start on a later page still
// opens on them.
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

List<StoryItem> _day(List<(String, String, bool)> spec) {
  final base = DateTime.now().toUtc().subtract(const Duration(days: 3));
  return [
    for (var i = 0; i < spec.length; i++)
      kitItem(
        spec[i].$1,
        author: spec[i].$2,
        createdAt: base.add(Duration(minutes: i)),
        viewed: spec[i].$3,
      ),
  ];
}

void main() {
  testWidgets("the partner's ring plays only the partner's stories", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('m2', kitMe, false),
        ('p2', kitPartner, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'p1');
    expect(bars(tester), (index: 0, count: 2));
    await tapRight(tester);
    expect(shownItemId(tester), 'p2');
  });

  testWidgets("the partner's ring opens at the first story I have not seen", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, true),
        ('m1', kitMe, false),
        ('p2', kitPartner, false),
        ('p3', kitPartner, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'p2');
    expect(bars(tester), (index: 1, count: 3));
  });

  testWidgets('my ring opens at my oldest story that day', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, false),
        ('m1', kitMe, true),
        ('m2', kitMe, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'm1');
    expect(bars(tester), (index: 0, count: 2));
  });

  testWidgets("an author whose stories start on a later page still opens on them", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('m2', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
      ]),
    )..pageSize = 2;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    await settle(tester);
    expect(shownItemId(tester), 'p1');
  });

  testWidgets("advancing skips pages with none of the author's stories", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, false),
        ('m1', kitMe, false),
        ('m2', kitMe, false),
        ('m3', kitMe, false),
        ('p2', kitPartner, false),
      ]),
    )..pageSize = 2;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'p1');
    await tapRight(tester);
    await settle(tester);
    expect(shownItemId(tester), 'p2');
  });
}
```

- [ ] **Step 3: Run it and watch it fail.**

```bash
flutter test test/features/stories/story_reel_day_author_test.dart
```

Expected: FAIL to compile: there is no `dayAuthorId` parameter yet.

- [ ] **Step 4: Implement in `story_reel_screen.dart`.**

1. In `StoryReelScreen.forDay`, add `this.dayAuthorId,` after `this.initialStoryItemId,`. In the author-mode and places constructors' initializer lists, add `dayAuthorId = null`. Add the field after `initialStoryItemId`:

```dart
  /// Day mode for one author's ring on the calendar (04 #4): only that
  /// author's stories play. Null plays the whole day. Filtered here until
  /// Wave 5's `list_story_day_items(p_author_id)`.
  final String? dayAuthorId;
```

2. Replace `_visible`:

```dart
  List<StoryItem> _visible(List<StoryItem> raw) {
    final author = widget.dayAuthorId;
    if (_removedIds.isEmpty && author == null) return raw;
    return raw
        .where(
          (i) =>
              !_removedIds.contains(i.id) &&
              (author == null || i.authorId == author),
        )
        .toList();
  }
```

3. Next to `_advancingPage`, add `bool _authorFillStarted = false;` and `bool _authorFillDone = false;`, then this method:

```dart
  /// One author's ring on a busy day: their stories may start pages in.
  /// Pages forward once, at most [kStoryStartSearchMaxPages], then lets the
  /// empty state speak if there are still none.
  void _fillAuthorPage() {
    if (_authorFillStarted) return;
    _authorFillStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        for (var page = 0; page < kStoryStartSearchMaxPages; page++) {
          if (!mounted || _liveItems().isNotEmpty || !_pagerHasMore()) break;
          await _pagerLoadMore();
        }
      } catch (_) {
        // A failed page leaves the empty state to say there is nothing.
      } finally {
        _authorFillDone = true;
        if (mounted) setState(() {});
      }
    });
  }
```

4. In `_buildLoaded`, replace `if (items.isEmpty) return _EmptyState(onClose: _close);` with:

```dart
    if (items.isEmpty) {
      // One author's ring: page forward once before saying there is
      // nothing; the spinner holds only while that single run pages.
      if (widget.dayAuthorId != null && !_authorFillDone) {
        if (!_pagerHasMore()) return _EmptyState(onClose: _close);
        _fillAuthorPage();
        return const _CenteredSpinner();
      }
      return _EmptyState(onClose: _close);
    }
```

5. In `_advanceAtEndOfPage`, replace `for (var pass = 0; pass < 2; pass++) {` with:

```dart
      // One author's day ring may need several pages to reach their next
      // story (04 #4); the whole day needs at most two passes.
      final passes = widget.dayAuthorId == null ? 2 : kStoryStartSearchMaxPages;
      for (var pass = 0; pass < passes; pass++) {
```

6. In `_resolveStartIndex`, replace the `firstUnseen` computation with:

```dart
    final myId = ref.read(currentUserProvider)?.id;
    // The partner's ring on a calendar day opens where the partner's
    // active reel would: their first story I have not seen (04 #4).
    final partnerDayRing =
        widget.occurredOn != null &&
        widget.dayAuthorId != null &&
        widget.dayAuthorId != myId;
    final firstUnseen =
        targetId == null &&
        ((widget.occurredOn == null && !_placesMode && !widget.isOwnReel) ||
            partnerDayRing);
```

Update the class doc's opening rules to mention the day ring.

- [ ] **Step 5: Run it.** Use the Step 3 command. Expected: PASS. Run `dart format` on the new test file.

- [ ] **Step 6: Run the neighbours.**

```bash
flutter test test/features/stories test/features/couple_map
```

Expected: PASS: every Wave 1 reel suite, including day-mode reply starts.

---

### Task 11: The day sheet: whole-day counts, per-author rings that open their author, errors with Retry (04 #4, #5)

**Files:**
- Create: `lib/features/stories/domain/story_day_rings.dart`
- Modify: `story_providers.dart` (the factory `StoryDayRangeKey.month`)
- Modify: `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart`: `_StoriesSection` and `_AuthorDayRing`, plus the new `_StoriesLoading` and `_StoriesLoadError`.
- Create: `test/features/stories/story_day_rings_test.dart`
- Create: `test/features/timeline/calendar_day_sheet_stories_test.dart`

**Interfaces:**
- Consumes: `StoryReelScreen.forDay(dayAuthorId:)` (Task 10), `storyDayRingLabel` (Task 2), `thumbnailCacheKey` (Task 4).
- Produces:

```dart
// story_day_rings.dart
@immutable class StoryDayAuthorRing { final String authorId; final int count; final int unviewed; final String? thumbnailKey; }
({int total, List<StoryDayAuthorRing> rings}) storyDayAuthorRings({required DateTime day, required List<StoryDayCount>? counts, required List<StoryItem>? items, required String? myId});
// story_providers.dart
factory StoryDayRangeKey.month({required String relationshipId, required DateTime day});
```

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_day_rings_test.dart`:

```dart
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/domain/story_day_rings.dart';
import 'package:flutter_test/flutter_test.dart';

final _day = DateTime(2026, 6, 15);

StoryItem _item(String id, String author, {bool viewed = false}) => StoryItem(
  id: id,
  clientStoryId: 'c-$id',
  relationshipId: 'rel-1',
  authorId: author,
  mediaType: 'image',
  mediaKey: 'story-media/$id.jpg',
  thumbnailKey: 'story-media/$id-thumb.jpg',
  mediaWidth: 1080,
  mediaHeight: 1920,
  occurredOn: _day,
  createdAt: _day,
  expiresAt: _day.add(const Duration(hours: 24)),
  hasBeenViewed: viewed,
);

StoryDayCount _count(String author, int n, int day, {String? key}) => StoryDayCount(
  occurredOn: _day,
  authorId: author,
  itemCount: n,
  dayItemCount: day,
  newestThumbnailKey: key ?? 'story-media/$author-newest.jpg',
  newestCreatedAt: _day,
);

void main() {
  test('counts and authors come from the whole day, not the first page (04 #4)', () {
    final result = storyDayAuthorRings(
      day: _day,
      counts: [_count('me', 50, 60), _count('partner', 10, 60)],
      items: [for (var i = 0; i < 50; i++) _item('m$i', 'me')],
      myId: 'me',
    );
    expect(result.total, 60);
    expect(result.rings.map((r) => (r.authorId, r.count)), [('me', 50), ('partner', 10)]);
    expect(result.rings.last.thumbnailKey, 'story-media/partner-newest.jpg');
  });

  test('loaded items still draw the rings when the counts failed', () {
    final result = storyDayAuthorRings(
      day: _day,
      counts: null,
      items: [_item('p1', 'partner', viewed: true), _item('m1', 'me'), _item('p2', 'partner')],
      myId: 'me',
    );
    expect(result.total, 3);
    expect(result.rings.map((r) => r.authorId), ['me', 'partner']);
    expect(result.rings.first.unviewed, 1);
    expect(result.rings.last.unviewed, 1);
    expect(result.rings.last.thumbnailKey, 'story-media/p2-thumb.jpg');
  });

  test('nothing that day, nothing drawn', () {
    final result = storyDayAuthorRings(day: _day, counts: const [], items: const [], myId: 'me');
    expect(result.rings, isEmpty);
    expect(result.total, 0);
  });
}
```

Create `test/features/timeline/calendar_day_sheet_stories_test.dart`:

```dart
// 04 #4/#5: the day sheet counts the whole day, opens each author's own
// stories, says when it could not load them (with Retry), and shows a
// placeholder while loading.
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show partnerNameProvider;
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../stories/support/ring_test_kit.dart';

final _day = DateTime(2026, 6, 15);

StoryDayCount _count(String author, int n, int day) => StoryDayCount(
  occurredOn: _day,
  authorId: author,
  itemCount: n,
  dayItemCount: day,
  newestThumbnailKey: 'story-media/$author-newest.jpg',
  newestCreatedAt: _day,
);

Future<void> _openSheet(WidgetTester tester, RingGateway gateway) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(ringUser),
        storyReadGatewayProvider.overrideWithValue(gateway),
        chatImageCacheProvider.overrideWithValue(NoopImageCache()),
        partnerNameProvider.overrideWith((ref) async => 'Kofi'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCalendarDaySheet(
                context: context,
                relationshipId: ringRel,
                date: _day,
                events: const [],
                reminders: const [],
                planningEntries: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets("the sheet counts the whole day and names the partner's ring", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final gateway = RingGateway()
      ..dayCounts = [_count(ringMe, 50, 60), _count(ringPartner, 10, 60)];
    await _openSheet(tester, gateway);
    expect(find.text('60 stories'), findsOneWidget);
    final partner = tester.widget<StoryRing>(
      find.descendant(
        of: find.byKey(const ValueKey('day-story-ring-$ringPartner')),
        matching: find.byType(StoryRing),
      ),
    );
    expect(partner.segmentCount, 10);
    expect(
      find.bySemanticsLabel("Kofi's stories from this day, 10 items"),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets("tapping the partner's ring opens only the partner's stories", (
    tester,
  ) async {
    final gateway = RingGateway()
      ..dayCounts = [_count(ringMe, 2, 3), _count(ringPartner, 1, 3)];
    await _openSheet(tester, gateway);
    await tester.tap(find.byKey(const ValueKey('day-story-ring-$ringPartner')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final reel = tester.widget<StoryReelScreen>(find.byType(StoryReelScreen));
    expect(reel.dayAuthorId, ringPartner);
    expect(reel.occurredOn, _day);
  });

  testWidgets("when the day's stories fail to load, it says so and retries", (
    tester,
  ) async {
    final gateway = RingGateway()
      ..dayCountsError = StateError('offline')
      ..dayItemsError = StateError('offline');
    await _openSheet(tester, gateway);
    await tester.pump();
    expect(find.text("Couldn't load this day's stories."), findsOneWidget);
    gateway
      ..dayCountsError = null
      ..dayItemsError = null
      ..dayCounts = [_count(ringPartner, 1, 1)];
    final counts = gateway.dayCountCalls;
    final items = gateway.dayItemCalls;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(gateway.dayCountCalls, counts + 1);
    expect(gateway.dayItemCalls, items + 1);
    expect(find.text('1 story'), findsOneWidget);
  });

  testWidgets('while loading, a placeholder holds the place', (tester) async {
    final handle = tester.ensureSemantics();
    final gateway = RingGateway()
      ..dayCountsGate = Completer<void>()
      ..dayItemsGate = Completer<void>();
    await _openSheet(tester, gateway);
    expect(find.bySemanticsLabel('Loading stories'), findsOneWidget);
    gateway.dayCountsGate!.complete();
    gateway.dayItemsGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel('Loading stories'), findsNothing);
    handle.dispose();
  });
}
```

- [ ] **Step 2: Run them and watch them fail.**

```bash
flutter test test/features/stories/story_day_rings_test.dart test/features/timeline/calendar_day_sheet_stories_test.dart
```

Expected: FAIL. `story_day_rings.dart` does not compile. The sheet tests fail: the count reads 0 and no rings are drawn (the counts are ignored), the reel's `dayAuthorId` is null, and there is no error row and no placeholder.

- [ ] **Step 3: Create `lib/features/stories/domain/story_day_rings.dart`.**

```dart
/// One ring per author who posted on a calendar day (04 #4). Authors,
/// counts and the newest thumbnail come from `list_story_day_counts`,
/// which covers the whole day, not just the first page of
/// `list_story_day_items`. The loaded items fill in when the counts are
/// missing, and supply the partner's unviewed count (a count the RPC does
/// not return). The larger count per author wins.
library;

import 'dart:math' as math;

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter/foundation.dart';

@immutable
class StoryDayAuthorRing {
  const StoryDayAuthorRing({
    required this.authorId,
    required this.count,
    required this.unviewed,
    required this.thumbnailKey,
  });

  final String authorId;
  final int count;
  final int unviewed;
  final String? thumbnailKey;
}

({int total, List<StoryDayAuthorRing> rings}) storyDayAuthorRings({
  required DateTime day,
  required List<StoryDayCount>? counts,
  required List<StoryItem>? items,
  required String? myId,
}) {
  bool sameDay(DateTime d) =>
      d.year == day.year && d.month == day.month && d.day == day.day;
  final countRows = [
    for (final c in counts ?? const <StoryDayCount>[])
      if (sameDay(c.occurredOn)) c,
  ];
  final counted = {
    for (final c in countRows)
      if (c.authorId != null && c.itemCount > 0) c.authorId!: c,
  };
  final loaded = <String, List<StoryItem>>{};
  for (final item in items ?? const <StoryItem>[]) {
    loaded.putIfAbsent(item.authorId, () => []).add(item);
  }
  // Mine first, as on the Conversations rings.
  final authors = {...counted.keys, ...loaded.keys}.toList()
    ..sort((x, y) {
      if (x == myId) return -1;
      if (y == myId) return 1;
      return x.compareTo(y);
    });
  final rings = <StoryDayAuthorRing>[
    for (final author in authors)
      () {
        final row = counted[author];
        final theirs = loaded[author] ?? const <StoryItem>[];
        final count = math.max(row?.itemCount ?? 0, theirs.length);
        // My own "viewed" means my partner saw it: my ring is all bright.
        final unviewed = author == myId
            ? count
            : theirs.where((i) => !i.hasBeenViewed).length.clamp(0, count);
        return StoryDayAuthorRing(
          authorId: author,
          count: count,
          unviewed: unviewed,
          thumbnailKey:
              row?.newestThumbnailKey ??
              (theirs.isEmpty ? null : theirs.last.thumbnailKey),
        );
      }(),
  ];
  final dayTotal = countRows.isEmpty ? 0 : countRows.first.dayItemCount;
  final ringTotal = rings.fold<int>(0, (sum, r) => sum + r.count);
  return (total: math.max(dayTotal, ringTotal), rings: rings);
}
```

- [ ] **Step 4: The month key.** In `StoryDayRangeKey` (`story_providers.dart`), add after the constructor:

```dart
  /// The calendar month around [day]: the key the date grid, the day sheet
  /// and the reel's delete share.
  factory StoryDayRangeKey.month({
    required String relationshipId,
    required DateTime day,
  }) => StoryDayRangeKey(
    relationshipId: relationshipId,
    startOn: DateTime(day.year, day.month, 1),
    endOn: DateTime(day.year, day.month + 1, 0),
  );
```

- [ ] **Step 5: The sheet** (`calendar_day_sheet.dart`). Import:
- `dart:async`;
- `package:attune/app/theme/design_tokens.dart`;
- `story_day_rings.dart`;
- `story_ring_copy.dart`.

Replace the `_StoriesSection` doc, `_openReel` and `build`, and `_AuthorDayRing`, with:

```dart
/// The day's stories as one ring per author, matching the Conversations
/// rings, each opening that author's own stories (04 #4). Counts come from
/// the whole day (`list_story_day_counts`), not the first page; expired
/// stories are included (spec §1/§3.2). A failed read says so, with Retry
/// (04 #5); a read in flight holds the place.
class _StoriesSection extends ConsumerWidget {
  const _StoriesSection({required this.relationshipId, required this.date});

  final String relationshipId;
  final DateTime date;

  void _openReel(BuildContext context, String authorId) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => StoryReelScreen.forDay(
              relationshipId: relationshipId,
              occurredOn: date,
              dayAuthorId: authorId,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final dayKey = StoryDayKey(relationshipId: relationshipId, occurredOn: date);
    final monthKey = StoryDayRangeKey.month(
      relationshipId: relationshipId,
      day: date,
    );
    final itemsAsync = ref.watch(storyDayItemsProvider(dayKey));
    final countsAsync = ref.watch(storyDayCountsProvider(monthKey));
    final day = storyDayAuthorRings(
      day: date,
      counts: countsAsync.valueOrNull,
      items: itemsAsync.valueOrNull,
      myId: myId,
    );

    if (day.rings.isEmpty) {
      final known = countsAsync.hasValue || itemsAsync.hasValue;
      if (known) return const SizedBox.shrink();
      if (countsAsync.isLoading || itemsAsync.isLoading) {
        return const _StoriesLoading();
      }
      return _StoriesLoadError(
        onRetry: () {
          ref.invalidate(storyDayCountsProvider(monthKey));
          unawaited(ref.read(storyDayItemsProvider(dayKey).notifier).refresh());
        },
      );
    }

    final partnerName =
        day.rings.any((r) => r.authorId != myId)
            ? ref.watch(quiz_providers.partnerNameProvider).valueOrNull
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          day.total == 1 ? '1 story' : '${day.total} stories',
          style: textTheme.labelLarge,
        ),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: kStoryRingOuterDiameter + 4,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: day.rings.length,
            separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
            itemBuilder: (_, index) {
              final ring = day.rings[index];
              return _AuthorDayRing(
                key: ValueKey('day-story-ring-${ring.authorId}'),
                ring: ring,
                isMine: ring.authorId == myId,
                partnerName: partnerName,
                onTap: () => _openReel(context, ring.authorId),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// One author's ring for one calendar day.
class _AuthorDayRing extends ConsumerWidget {
  const _AuthorDayRing({
    super.key,
    required this.ring,
    required this.isMine,
    required this.partnerName,
    required this.onTap,
  });

  final StoryDayAuthorRing ring;
  final bool isMine;
  final String? partnerName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ring.thumbnailKey;
    final url =
        key == null
            ? null
            : ref.watch(storyMediaSignedUrlProvider(key)).valueOrNull;
    return StoryRing(
      isMine: isMine,
      hasStories: true,
      // No + on a past day: a capture posts to today.
      showPlusBadge: false,
      segmentCount: ring.count,
      unviewedCount: ring.unviewed,
      thumbnailUrl: url,
      thumbnailCacheKey: key,
      onTap: onTap,
      semanticLabel: storyDayRingLabel(
        mine: isMine,
        count: ring.count,
        partnerName: partnerName,
      ),
    );
  }
}

/// A read in flight: one neutral ring in the place the rings will take.
class _StoriesLoading extends StatelessWidget {
  const _StoriesLoading();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Loading stories',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            width: kStoryRingOuterDiameter,
            height: kStoryRingOuterDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ),
    );
  }
}

/// The day's stories could not be read (04 #5): say so, offer Retry.
class _StoriesLoadError extends StatelessWidget {
  const _StoriesLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline_rounded,
                size: IconSizes.sm,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                "Couldn't load this day's stories.",
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
```

The wiring test requires the string `storyDayItemsProvider(` to stay in this file; it does. Do not run `dart format` on this file; match its older style by hand.

- [ ] **Step 6: Run them.** Use the Step 2 command. Expected: PASS. Run `dart format` on the new files.

- [ ] **Step 7: Run the neighbours.**

```bash
flutter test test/features/timeline test/features/stories
```

Expected: PASS. The existing `CalendarDaySheet` tests give items and no counts; the union keeps them green ("3 stories", two rings, my ring all bright).

---

### Task 12: The calendar month says when its stories failed to load; past-day deletions leave the disk (04 #5 grid, 05 #6)

**Files:**
- Create: `lib/features/timeline/presentation/widgets/story_month_load_error.dart`
- Modify: `lib/features/timeline/presentation/widgets/calendar_strip.dart` (one insertion)
- Modify: `story_day_rings.dart` (`storyDayCountDroppedKeys`)
- Modify: `story_providers.dart` (`storyDayCountsMemoProvider`, and eviction in `storyDayCountsProvider`)
- Create: `test/features/timeline/story_month_load_error_test.dart`
- Modify: `test/features/stories/story_day_rings_test.dart` (append)

**Interfaces:**
- Consumes: `StoryDayRangeKey.month` (Task 11), `storyMediaEvictorProvider` (Task 3).
- Produces:

```dart
class StoryMonthLoadErrorRow extends ConsumerWidget { const StoryMonthLoadErrorRow({super.key, required String relationshipId, required DateTime month}); }
Set<String> storyDayCountDroppedKeys(List<StoryDayCount>? previous, List<StoryDayCount> next);
final storyDayCountsMemoProvider; // Provider<Map<StoryDayRangeKey, List<StoryDayCount>>>, new per account
```

- [ ] **Step 1: Write the failing tests.** Append to `story_day_rings_test.dart`:

```dart
  test('a past day whose newest story went loses its thumbnail key (05 #6)', () {
    final before = [_count('partner', 2, 2, key: 'b')];
    final deleted = [
      StoryDayCount(
        occurredOn: _day,
        authorId: 'partner',
        itemCount: 1,
        dayItemCount: 1,
        newestThumbnailKey: 'a',
        newestCreatedAt: _day.subtract(const Duration(hours: 1)),
      ),
    ];
    expect(storyDayCountDroppedKeys(before, deleted), {'b'});
    expect(storyDayCountDroppedKeys(before, const []), {'b'});
    final newer = [
      StoryDayCount(
        occurredOn: _day,
        authorId: 'partner',
        itemCount: 3,
        dayItemCount: 3,
        newestThumbnailKey: 'c',
        newestCreatedAt: _day.add(const Duration(hours: 1)),
      ),
    ];
    expect(storyDayCountDroppedKeys(before, newer), isEmpty);
    expect(storyDayCountDroppedKeys(null, deleted), isEmpty);
  });
```

Create `test/features/timeline/story_month_load_error_test.dart`:

```dart
// 04 #5: a calendar month whose story counts failed used to look like a
// month with no stories. It now says so, with Retry.
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/story_month_load_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../stories/support/ring_test_kit.dart';

Future<void> _pump(WidgetTester tester, RingGateway gateway) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(ringUser),
        storyReadGatewayProvider.overrideWithValue(gateway),
        chatImageCacheProvider.overrideWithValue(NoopImageCache()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: StoryMonthLoadErrorRow(
            relationshipId: ringRel,
            month: DateTime(2026, 6, 1),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a failed month says so and retries', (tester) async {
    final gateway = RingGateway()..dayCountsError = StateError('offline');
    await _pump(tester, gateway);
    expect(find.text("Couldn't load this month's stories."), findsOneWidget);
    gateway.dayCountsError = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(gateway.dayCountCalls, 2);
    expect(find.text("Couldn't load this month's stories."), findsNothing);
  });

  testWidgets('a loaded month shows nothing extra', (tester) async {
    final gateway = RingGateway()
      ..dayCounts = [
        StoryDayCount(occurredOn: DateTime(2026, 6, 3), itemCount: 1, authorId: ringPartner),
      ];
    await _pump(tester, gateway);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a re-read that shows a past story deleted evicts its thumbnail', (
    tester,
  ) async {
    final evictor = RecordingEvictor();
    final gateway = RingGateway()
      ..dayCounts = [
        StoryDayCount(
          occurredOn: DateTime(2026, 6, 3),
          itemCount: 1,
          authorId: ringPartner,
          newestThumbnailKey: 'gone',
          newestCreatedAt: DateTime(2026, 6, 3, 9),
        ),
      ];
    final c = ringContainer(
      gateway,
      overrides: [storyMediaEvictorProvider.overrideWithValue(evictor)],
    );
    final key = StoryDayRangeKey.month(relationshipId: ringRel, day: DateTime(2026, 6, 1));
    final sub = c.listen(storyDayCountsProvider(key), (_, __) {});
    await tester.pump();
    gateway.dayCounts = [];
    gateway.emitSignal();
    await tester.pump();
    await tester.pump();
    expect(evictor.evicted, ['gone']);
    sub.close();
    c.dispose();
  });
}
```

- [ ] **Step 2: Run them and watch them fail.**

```bash
flutter test test/features/stories/story_day_rings_test.dart test/features/timeline/story_month_load_error_test.dart
```

Expected: FAIL to compile, because `storyDayCountDroppedKeys` and `story_month_load_error.dart` do not exist yet.

- [ ] **Step 3: The drop rule.** Append to `story_day_rings.dart`:

```dart
/// Newest-thumbnail keys a month re-read no longer shows, other than ones
/// a newer story that day replaced: a past story the partner deleted
/// (05 #6). Its bytes leave the disk cache.
Set<String> storyDayCountDroppedKeys(
  List<StoryDayCount>? previous,
  List<StoryDayCount> next,
) {
  if (previous == null) return const {};
  String slot(StoryDayCount c) =>
      '${c.occurredOn.year}-${c.occurredOn.month}-${c.occurredOn.day}'
      '|${c.authorId}';
  final bySlot = {for (final c in next) slot(c): c};
  final kept = {
    for (final c in next)
      if (c.newestThumbnailKey != null) c.newestThumbnailKey!,
  };
  final dropped = <String>{};
  for (final before in previous) {
    final key = before.newestThumbnailKey;
    if (key == null || kept.contains(key)) continue;
    final after = bySlot[slot(before)]?.newestCreatedAt;
    final was = before.newestCreatedAt;
    final replacedByNewer = after != null && was != null && after.isAfter(was);
    if (!replacedByNewer) dropped.add(key);
  }
  return dropped;
}
```

- [ ] **Step 4: Providers.** In `story_providers.dart`, import `story_day_rings.dart`, add above `storyDayCountsProvider`:

```dart
/// The last day counts read per month this session, to tell which past
/// stories a re-read shows deleted (05 #6). A new, empty map per account.
final storyDayCountsMemoProvider =
    Provider<Map<StoryDayRangeKey, List<StoryDayCount>>>((ref) {
      ref.watch(currentUserProvider.select((u) => u?.id));
      return {};
    });
```

Replace the body of `storyDayCountsProvider`:

```dart
      ref.watch(storyChangeSignalProvider(key.relationshipId));
      final gateway = ref.watch(storyReadGatewayProvider);
      final memo = ref.watch(storyDayCountsMemoProvider);
      final counts = await gateway.listDayCounts(
        relationshipId: key.relationshipId,
        startOn: key.startOn,
        endOn: key.endOn,
      );
      final dropped = storyDayCountDroppedKeys(memo[key], counts);
      memo[key] = counts;
      if (dropped.isNotEmpty) {
        unawaited(ref.read(storyMediaEvictorProvider).evict(dropped));
      }
      return counts;
```

- [ ] **Step 5: Create `lib/features/timeline/presentation/widgets/story_month_load_error.dart`.**

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Under a calendar month whose story counts could not be read (04 #5):
/// the date cells then have no story avatars, which looked like a month
/// without stories. Reads the same provider key as the cells, so it costs
/// no extra call. Nothing when the counts loaded, or while they load.
class StoryMonthLoadErrorRow extends ConsumerWidget {
  const StoryMonthLoadErrorRow({
    super.key,
    required this.relationshipId,
    required this.month,
  });

  final String relationshipId;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = StoryDayRangeKey.month(
      relationshipId: relationshipId,
      day: month,
    );
    final counts = ref.watch(storyDayCountsProvider(key));
    if (!counts.hasError || counts.hasValue) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline_rounded,
                size: IconSizes.sm,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                "Couldn't load this month's stories.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(storyDayCountsProvider(key)),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Place it.** In `calendar_strip.dart`, directly before the line `        // A key to what is actually on screen this month, not a static`, insert:

```dart
        // 04 #5: a month whose story counts failed says so.
        if (relationshipId != null)
          StoryMonthLoadErrorRow(
            relationshipId: relationshipId!,
            month: focusedMonth,
          ),
```

Add the import. Do not run `dart format` on this file.

- [ ] **Step 7: Run them.** Use the Step 2 command. Expected: PASS. Run `dart format` on the new files.

- [ ] **Step 8: Run the neighbours.**

```bash
flutter test test/features/timeline test/features/stories
```

---

### Task 13: Deleting from the reel clears its media from the phone and refreshes the calendar (E, coherence with the reel)

**Files:**
- Modify: `story_reel_screen.dart` (`_confirmAndDelete`, after the existing `container.invalidate(storyRingSummaryProvider(…))`)
- Modify: `test/features/stories/support/reel_test_kit.dart` (a `dayCountCalls` counter in `ScriptedReelGateway.listDayCounts`)
- Create: `test/features/stories/story_reel_delete_coherence_test.dart`

**Interfaces:**
- Consumes: `storyMediaEvictorProvider` (Task 3), `StoryDayRangeKey.month` (Task 11).
- Produces: nothing new.

- [ ] **Step 1: Kit.** In `ScriptedReelGateway`, add `int dayCountCalls = 0;`, and make `listDayCounts` increment it before returning `const []`.

- [ ] **Step 2: Write the failing test.** Create `test/features/stories/story_reel_delete_coherence_test.dart`:

```dart
// 05 #6 + coherence: deleting my story from the reel removes its thumbnail
// and media from this phone's caches and re-reads the calendar month, not
// only the Home ring.
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';
import 'support/ring_test_kit.dart' show NoopImageCache;

void main() {
  testWidgets('deleting my story evicts its media and refreshes its month', (
    tester,
  ) async {
    final images = NoopImageCache();
    final gateway = ScriptedReelGateway(
      active: kitItems(['m1', 'm2'], author: kitMe),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.ownReel,
      hold: const Duration(seconds: 30),
      extraOverrides: [chatImageCacheProvider.overrideWithValue(images)],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StoryReelScreen)),
    );
    final month = StoryDayRangeKey.month(relationshipId: kitRel, day: kitDay);
    final sub = container.listen(storyDayCountsProvider(month), (_, __) {});
    await settle(tester);
    final before = gateway.dayCountCalls;

    await confirmDelete(tester);
    await settle(tester);

    expect(images.removed, containsAll(['story-media/m1-thumb.jpg', 'story-media/m1.jpg']));
    expect(gateway.dayCountCalls, before + 1);
    sub.close();
  });
}
```

`kitItems` sets `occurredOn: kitDay` on every item, so the month key matches.

- [ ] **Step 3: Run it and watch it fail.**

```bash
flutter test test/features/stories/story_reel_delete_coherence_test.dart
```

Expected: FAIL. `images.removed` is empty, and the count is unchanged.

- [ ] **Step 4: Implement.** In `_confirmAndDelete`, directly after `container.invalidate(storyRingSummaryProvider(widget.relationshipId));`, add:

```dart
    // Wave 4 (05 #6): the story's media leaves this phone's caches, and
    // the calendar month re-reads, as the ring does: the signal can be
    // missed.
    unawaited(
      container
          .read(storyMediaEvictorProvider)
          .evict([item.thumbnailKey, item.mediaKey]),
    );
    container.invalidate(
      storyDayCountsProvider(
        StoryDayRangeKey.month(
          relationshipId: widget.relationshipId,
          day: item.occurredOn,
        ),
      ),
    );
```

- [ ] **Step 5: Run it.** Use the Step 3 command. Expected: PASS. Run `dart format` on the new test file.

- [ ] **Step 6: Run the neighbours.**

```bash
flutter test test/features/stories test/features/couple_map
```

Expected: PASS: every reel delete test, and places mode.

---

### Task 14: The spec says what was built; the whole suite passes

**Files:**
- Modify: `lib/architecture/STORIES.md` (§4.1, §5.1, §5.3, §5.5; additive edits that keep the Wave 1–3 text).

- [ ] **Step 1: §4.1.** Replace the paragraph that begins "The one exception is the reel (Wave 1, 2026-10-23)." and ends "so the §4.5 window is unchanged." with:

> Two exceptions, both in memory only.
>
> - **The reel** (Wave 1, 2026-10-23). It may reuse a URL it minted itself for the same storage key while that URL is under 540 seconds old, and only while the reel screen is open. So the photo it preloads is the photo it shows, and stepping back does not re-sign.
> - **The rings and the calendar** (since Wave 4). They share one in-memory URL per storage key under the same 540-second rule. That URL is forgotten:
>   - on sign-out and account switch;
>   - on quick exit;
>   - on a relationship's pause, end or archive;
>   - when the story is deleted.
>
> No URL is ever written to disk, and none outlives its 600-second TTL, so the §4.5 window is unchanged.
>
> Image bytes are not URLs. Ring and calendar thumbnails are cached on disk in the app's shared image cache under their storage key, never under the URL, so a re-signed URL does not re-download. Those bytes are removed:
> - when the author deletes the story;
> - when a ring or calendar-month re-read shows the partner deleted it;
> - with the whole image cache on quick exit and on a relationship's pause, end or archive. Sign-out already empties it.

- [ ] **Step 2: §5.1.** Append after the paragraph ending "and asks before Discard (§6.1).":

> **Wave 4 (2026-10-24).**
>
> - **Taps.** On my ring the photo opens my reel and only the `+` opens the camera. The `+` keeps a 48 dp target, centred on the drawn badge and hung outside the photo. My ring's box is 14 dp larger on the end and bottom sides for it, and mirrors right to left.
> - **Arcs.** They run oldest first, clockwise from 12 o'clock, as the reel plays: seen arcs first, new ones last.
> - **Labels.** Screen readers hear counts: "Ama's story, 2 new of 5".
> - **After posting.** A posted story stays on my ring until a summary read after it arrives, so the ring never flashes back to `+`. A ring whose only story is still posting says so when tapped, instead of opening an empty reel.
> - **Offline and failed loads.** Until this session's first read lands, or when it fails, the rings show the last ones this phone saw: ids, counts and storage keys only, kept on this device and cleared with the caches above. A failed read is said under the rings, with Retry.
> - **Stuck posts.** A story queued for a previous relationship, which can never post, gets one notice with Discard.

- [ ] **Step 3: §5.3.** Append:

> **Calendar day rings (Wave 4).**
>
> - **One author each.** Each author's ring on a day plays that author's stories only. Until `list_story_day_items` takes an author, the reel filters the day's pages itself.
> - **Counts.** Counts and authors come from `list_story_day_counts`, so a day with more than one page counts every story.
> - **Errors.** A day or month whose stories could not be read says so, with Retry, instead of looking empty.

- [ ] **Step 4: §5.5.**
  - Replace the sentence "Your own reel, a calendar day and the map open at the oldest item." with: "Your own reel, a calendar day and the map open at the oldest item. A calendar day's ring for the partner plays only the partner's stories that day, and opens at the first one the viewer has not seen (Wave 4)."
  - Append to the realtime paragraph:

> **Ring summary refresh (Wave 4).**
>
> - **One fetch at a time.** The ring summary has one fetch in flight per relationship, with at most one follow-up, so a burst of signals costs one more call.
> - **Retries.** A failed read retries on a backoff (2 s doubling to 60 s, six times), only while Attune is on screen.
> - **Expiry.** The ring re-reads one second after its newest story's 24 hours end, so a story leaves the ring with the app open.
> - **Wave 5.** It adds `next_expires_at`, which the client already reads, so an older story's expiry also refreshes the count.

- [ ] **Step 5: Analyze the touched files.**

```bash
flutter analyze lib/features/stories lib/features/timeline lib/features/safety/domain/services/quick_exit_service.dart lib/features/relationships/presentation/relationship_lifecycle_providers.dart lib/features/chat/presentation/screens/conversations_screen.dart test/features/stories test/features/timeline
```

Expected: no new issues. Fix any that this wave introduced; leave existing ones alone.

- [ ] **Step 6: Run the whole suite.**

```bash
flutter test 2>&1 | tail -15
```

Expected: all pass, apart from any failure recorded in Pre-flight as already present. Do not commit.

- [ ] **Step 7: Hand the owner the device checks.** These cannot be tested in Dart:
  - On a phone, tap the centre of my ring, then the `+`.
  - The same in an RTL locale (Arabic).
  - Airplane mode at cold start: the rings show last-known thumbnails from disk, plus the "Couldn't refresh" line.
  - Leave Conversations open past a story's 24 h mark (or set the clock): the partner ring clears within about a minute.
  - Post a first story on a slow link: no `+` flash.
  - Delete a story, then check the app's Caches/`libCachedImageData` for its key.
  - Quick exit, then reopen: no story thumbnails are cached.

## Server dependencies (Wave 5, not built here)

- **03 L7 (ring query index).** Add a partial index on `story_items (relationship_id, expires_at) WHERE deleted_at IS NULL`, or rewrite the predicate on `created_at` with its own index. Then `EXPLAIN` at volume.
- **03 M2 completion.** `get_story_ring_summary` should return `next_expires_at` (the minimum `expires_at` per author), and optionally `server_now`. The client already parses `next_expires_at` and prefers it (Task 5).
- **04 #4 completion.** `list_story_day_items(p_author_id)` would replace the client-side filter of Task 10. `list_story_day_counts` could return a per-author unviewed count, so the day rings' brightness is exact beyond page one.
- **Optional, from 04 #6.** Batch-sign a month's thumbnail keys (Storage `createSignedUrls`). This is client and Storage work, not a migration. It is deferred, because the per-key reuse and the key-based disk cache already remove most of the cost.

## Execution note

The tasks depend on each other's interfaces:
- Tasks 3 → 5 → 6 → 7 share the summary provider.
- Task 10 → 11 share the reel's `dayAuthorId`.

They also touch shared files: `story_providers.dart`, `story_rings_row.dart`, `story_reel_screen.dart` and the kits. **Subagent-driven execution is recommended,** with a fresh reviewer per task, so each review can check the uncommitted Wave 1–3 edits were kept. Finish with an opus whole-wave review.
