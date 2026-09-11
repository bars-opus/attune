# Stories — Plan C: Surfaces

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stories become visible and usable — two rings on the
conversations screen, a full-screen reel, the calendar's third source,
and replies that land in chat. Then the flag goes on.

**Architecture:** Pure client work on a backend already proven, plus one
small migration for `messages.story_item_id`. Reads go through Plan A's
four RPCs; Realtime is a refetch signal, never a second source of truth.

**Tech Stack:** Flutter, Riverpod, `video_player`, Supabase Realtime.

**Spec:** `docs/superpowers/specs/2026-09-11-stories-design.md`
**Depends on:** Plan A (RPCs) and Plan B (capture, outbox).

## Global Constraints

- **The reel is a NEW module.** The streak viewer is a single-item video
  player whose only gesture is `onTap → _finish()`. It stays unchanged;
  only its signed-media loading and `VideoPlayerController` patterns are
  reused (§5.2).
- Ring states, verbatim (§5.1):
  - **Mine, empty:** empty ring with `+` in the middle
  - **Mine, has stories:** newest thumbnail fills the circle, `+` badge
    bottom-right
  - **Partner's, empty:** renders **nothing at all** — never a
    placeholder
  - **Partner's, has stories:** newest thumbnail, ring around it
- The circle is **a thumbnail, never an avatar** (§5.1).
- **Absence of a ring row is not "do not draw mine."** `get_story_ring_summary`
  omits authors with zero active stories; the client draws its own ring
  from its own identity and uses the result only to FILL it. Deriving
  "should I draw mine" from row presence hides the `+` for every player
  who has not posted — which is every new player. (Recorded on the RPC
  in migration 20260938080000.)
- The ring is segmented, one arc per item, **capped at 12 arcs**; beyond
  that it is drawn solid (§8).
- **Realtime is a refetch signal.** On a `story_change_signals` bump the
  client invalidates the ring summary and the visible reel/day — it does
  not treat the payload as data. Also refetch on app resume and
  pull-to-refresh (§5.5).
- **Viewing marks a view only after a successful render**, and only for
  the partner's live story. `mark_story_viewed` refuses the author and
  refuses an expired story (§3.4).
- Paging is **keyset, never offset**, 50 per page (§5.5).
- Reels open at the **oldest** active item; viewed segments are faded,
  not skipped (§5.5).
- Replies snapshot **text only** (`quoted_text` = "Photo story" /
  "Video story"), never a thumbnail key — the key is the one the
  deletion queue removes (§5.4).
- Signed URLs last **600 seconds**; mint per request, never store
  (§4.1).

## The server contract (Plan A, live)

```
get_story_ring_summary(p_relationship_id)
list_active_story_items(p_relationship_id, p_author_id,
                        p_after_created_at, p_after_id, p_limit)   -- excludes expired
list_story_day_counts(p_relationship_id, p_start_on, p_end_on)
list_story_day_items(p_relationship_id, p_occurred_on,
                     p_after_created_at, p_after_id, p_limit)      -- INCLUDES expired
mark_story_viewed(p_story_item_id)
delete_story_item(p_story_item_id)        -- author only; works from an ended relationship
```

`p_limit` is capped at 50 server-side regardless of what is asked.

## File structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260939010000_story_replies.sql` | `messages.story_item_id` + validation trigger |
| `lib/features/stories/data/story_read_repository.dart` | The four read RPCs + signed URLs |
| `lib/features/stories/presentation/providers/story_providers.dart` | Ring summary, reel pages, Realtime signal |
| `lib/features/stories/presentation/widgets/story_ring.dart` | One ring: segments, thumbnail, `+` |
| `lib/features/stories/presentation/widgets/story_rings_row.dart` | The two-ring row |
| `lib/features/stories/presentation/screens/story_reel_screen.dart` | The reel |
| `lib/features/stories/presentation/widgets/story_progress_bars.dart` | Segmented progress |
| `lib/features/timeline/.../story_day_row.dart` | The calendar's third source |

## Test commands

```bash
flutter test test/features/stories
flutter analyze lib test
psql -q -d attune_test -f supabase/tests/story_reply_contracts.sql
```

---

### Task 1: `messages.story_item_id` and its validation trigger

**Files:**
- Create: `supabase/migrations/20260939010000_story_replies.sql`
- Create: `supabase/tests/story_reply_contracts.sql`

**Interfaces:**
- Produces: `messages.story_item_id uuid NULL REFERENCES story_items(id)
  ON DELETE SET NULL`, plus a `BEFORE INSERT` trigger.

Spec §5.4 chose a trigger over an RPC because **messages are inserted
directly today** — a reply RPC would route replies around the existing
chat outbox.

- [ ] **Step 1: Write the failing contract test**

```sql
-- A reply cannot quote another couple's story. The trigger is the only
-- gate: messages are inserted directly, so there is no RPC to check it.
-- Also: quoted_text is SERVER-SET from the media type, so a client
-- cannot write arbitrary text into a story quote.
```

Assert:
1. A member replying to their own couple's live story succeeds, and
   `quoted_text` is overwritten to 'Photo story' or 'Video story'.
2. Quoting a story from a DIFFERENT relationship is refused.
3. Quoting a deleted story is refused.
4. Quoting from an ENDED or archived relationship is refused.
5. Soft-deleting the story afterwards leaves the message intact with its
   `quoted_text` (the reply must still read sensibly).
6. A HARD delete sets `story_item_id` to NULL and keeps `quoted_text`.

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Write the migration**

Per §5.4. The trigger requires a live story in the same ACTIVE,
unarchived relationship, requires the sender to be a member, and
overwrites `quoted_text` from the story's media type. A mismatch raises
the same generic unavailable error — never an existence oracle.

- [ ] **Step 4: Apply and re-run.** Expected: all six hold.

- [ ] **Step 5: Mutation-test**

Remove the relationship-match check → contract 2 fails. Remove the
`quoted_text` overwrite → contract 1 fails.

- [ ] **Step 6: Regression check** — messages is the chat's core table:

```bash
psql -q -d attune_test -f supabase/tests/chat_system_contracts.sql
psql -q -d attune_test -f supabase/tests/game_message_contracts.sql
```

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260939010000_story_replies.sql \
        supabase/tests/story_reply_contracts.sql
git commit -m "feat(stories): replies quote a story, validated by trigger"
```

---

### Task 2: The read repository and providers

**Files:**
- Create: `lib/features/stories/data/story_read_repository.dart`
- Create: `lib/features/stories/presentation/providers/story_providers.dart`
- Test: `test/features/stories/story_read_repository_test.dart`

**Interfaces:**
- Produces: `storyRingSummaryProvider(relationshipId)`,
  `storyReelPagesProvider(...)`, `storyDayCountsProvider(...)`,
  `storyDayItemsProvider(...)`, and a Realtime subscription to
  `story_change_signals`.

- [ ] **Step 1: Write the failing tests**

```dart
test('a signal bump invalidates the ring summary and the visible reel', () {
  // Realtime is a REFETCH SIGNAL, not data. The payload is ignored;
  // the client re-reads through the RPCs, which are the authority.
});

test('paging uses the last item as the cursor, never an offset', () {
  // An insert between pages must append, not duplicate or skip.
});

test('a signed URL is minted per request and never cached past its TTL', () {
  // 600s. A stored URL outlives the deletion it is supposed to respect.
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement.** Reuse `createSignedMediaUrl`'s caching shape
      from `supabase_chat_repository.dart` (`_signedUrlTtl` is 600s).

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/stories/data/story_read_repository.dart \
        lib/features/stories/presentation/providers/story_providers.dart \
        test/features/stories/story_read_repository_test.dart
git commit -m "feat(stories): read repository and refetch-signal providers"
```

---

### Task 3: The rings

**Files:**
- Create: `lib/features/stories/presentation/widgets/story_ring.dart`
- Create: `lib/features/stories/presentation/widgets/story_rings_row.dart`
- Modify: `lib/features/chat/presentation/screens/conversations_screen.dart`
- Test: `test/features/stories/story_rings_test.dart`

**Interfaces:**
- Consumes: `storyRingSummaryProvider` (Task 2), `storyOutboxProvider`
  (Plan B) for the pending tile.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('my empty ring still renders, with a +', (tester) async {
  // The summary omits authors with zero stories. Deriving "draw mine"
  // from row presence hides the + for every player who has not posted.
});

testWidgets('an empty partner ring renders NOTHING', (tester) async {
  // Not a placeholder. A placeholder reads as "they have something."
});

testWidgets('the circle shows a thumbnail, never an avatar', (tester) async {
  // With an audience of one, a face tells you nothing you do not know.
});

testWidgets('segments cap at 12 arcs', (tester) async {
  // Thirty hairlines read as a solid circle anyway.
});

testWidgets('a pending outbox item shows progress on my ring', (tester) async {
  // Spec §6.1 — the capture is visible before it is posted.
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement.** The row goes ABOVE the conversation tile,
      per §5.1 and the reference image.

- [ ] **Step 4: Render a golden and LOOK at it**

```dart
await expectLater(find.byType(StoryRingsRow),
    matchesGoldenFile('story_rings_light.png'));
```
Render both themes and read the PNGs. A ring is a visual object; a
passing widget test says nothing about whether it looks right.

- [ ] **Step 5: Commit**

```bash
git add lib/features/stories/presentation/widgets/ \
        lib/features/chat/presentation/screens/conversations_screen.dart \
        test/features/stories/story_rings_test.dart
git commit -m "feat(stories): two rings above the conversation"
```

---

### Task 4: The reel

**Files:**
- Create: `lib/features/stories/presentation/screens/story_reel_screen.dart`
- Create: `lib/features/stories/presentation/widgets/story_progress_bars.dart`
- Test: `test/features/stories/story_reel_test.dart`

**Interfaces:**
- Consumes: `storyReelPagesProvider`, `mark_story_viewed`.

This is the largest new widget in the feature. The streak viewer
contributes only its signed-media loading and controller patterns.

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('tap right advances, tap left goes back', (tester) async {});

testWidgets('hold pauses, release resumes', (tester) async {});

testWidgets('swipe down dismisses', (tester) async {});

testWidgets('an image holds for 5 seconds, a video runs its length', (
  tester,
) async {
  // A photo has no natural duration to drive the progress bar.
});

testWidgets('a view is marked only AFTER a successful render', (tester) async {
  // Marking on open would count a story the viewer never saw.
});

testWidgets('backgrounding mid-item pauses rather than skipping', (
  tester,
) async {});

testWidgets('the reel opens at the OLDEST active item', (tester) async {
  // Viewed segments are faded, not skipped (§5.5).
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement.** Segmented progress bars, the gesture set,
      an image timer, lifecycle pause/resume, next-item preloading.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/stories/presentation/screens/story_reel_screen.dart \
        lib/features/stories/presentation/widgets/story_progress_bars.dart \
        test/features/stories/story_reel_test.dart
git commit -m "feat(stories): the reel — segments, gestures, mixed media"
```

---

### Task 5: The calendar's third source

**Files:**
- Create: `lib/features/timeline/presentation/widgets/story_day_row.dart`
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart`
- Test: `test/features/stories/story_calendar_test.dart`

**Interfaces:**
- Consumes: `storyDayCountsProvider`, `storyDayItemsProvider`.

The timeline already merges events and reminders; stories are a third
source merged at read time, never copied (§3.1).

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('a day with stories shows a row with its count', (tester) async {});

testWidgets('an EXPIRED story still opens from its calendar day', (
  tester,
) async {
  // THE FEATURE'S CENTRAL PROMISE. list_story_day_items includes
  // expired rows; list_active_story_items does not. Same row, two
  // surfaces.
});

testWidgets('only the author sees delete, and it warns it is permanent', (
  tester,
) async {
  // delete_story_item is author-only server-side; the UI must not
  // offer an action that will be refused.
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run the tests, plus the timeline's existing suite.**

- [ ] **Step 5: Commit**

```bash
git add lib/features/timeline/ test/features/stories/story_calendar_test.dart
git commit -m "feat(stories): the calendar keeps what the reel lets go"
```

---

### Task 6: Replies, and turning the flag on

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart`
- Test: `test/features/stories/story_reply_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('replying from the reel composes a message quoting the story', (
  tester,
) async {});

testWidgets('a reply to a DELETED story still reads sensibly', (tester) async {
  // quoted_text survives; tapping says "Story no longer available"
  // rather than opening an empty reel.
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** the quote rendering and tap-through.

- [ ] **Step 4: FULL verification, everything**

```bash
scripts/local_pg_setup.sh
for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f"; done
bash scripts/concurrency/story_races.sh
flutter test test/features/stories
flutter test test/features/chat
flutter test test/features/games
flutter analyze lib test
```
Expected: all SQL suites green; stories green; chat at its 19 known
pre-existing failures; games green; 0 analyzer errors.

- [ ] **Step 5: Turn the flag on**

```sql
-- supabase/migrations/20260939020000_stories_enable.sql
UPDATE public.feature_flags SET enabled = true WHERE key = 'stories';
```

This is the LAST step of the LAST task, deliberately. Everything before
it is dark.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_bubble.dart \
        lib/features/stories/ \
        supabase/migrations/20260939020000_stories_enable.sql \
        test/features/stories/story_reply_test.dart
git commit -m "feat(stories): replies land in chat, and the flag goes on"
```

---

## Plan C completion criteria

From spec §12, the parts this plan owns:

- [ ] New stories are visible only to the two members of an active,
      unarchived relationship.
- [ ] The partner's first successful active-reel render changes seen
      state; no caller can retrieve the exact view timestamp.
- [ ] The reel expires from server time while the same row stays
      playable from its calendar day.
- [ ] Rings, calendar counts and reels recover from missed Realtime
      events by refetching canonical server reads.
- [ ] Story replies cannot cross relationships and remain
      understandable after their story becomes unavailable.
- [ ] Existing streak capture/view/replay behaviour passes unchanged.
- [ ] The `stories` flag is ON and the feature is reachable.
