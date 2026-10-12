# Review: Planning v2 Notes & pins (feat/planning-notes-pins: fe8ea2f2, eacaf235 on 045c12ab)

How this was checked:
- Baseline: `flutter test test/features/planning/v2` passes 111/111. All 7 v2 SQL contract files pass; each runs inside BEGIN/ROLLBACK.
- SQL repros are in scratchpad/rv/overflow.sql, run with BEGIN/ROLLBACK on attune_planning.
- Dart repros are in scratchpad/proj/test/features/planning/v2/review_{pins_paging,rollback_clobber,undo_after_leave}_test.dart. They run in a scratch project whose lib is symlinked to the worktree. The worktree was not modified.

### Strengths
- **Lock order holds.**
  - `pin_planning_entry` locks the category FOR UPDATE, then the entry FOR UPDATE.
  - `restore_planning_entry` locks the category FOR SHARE, then the entry FOR UPDATE, then updates items and blocks while holding the entry lock.
  - Both follow category -> entry -> block -> item. I checked them against delete_planning_category (which now locks entries first), duplicate, create, reset_template, ensure_starters and every block/item RPC, and found no cycle.
  - The 20-pin count runs as a new READ COMMITTED statement after the category lock is held. It therefore sees a pin the other partner just committed, so two partners cannot both take the 20th pin.
- **Restore matches on the delete's own deleted_at.**
  - A block the couple deleted earlier stays deleted (contract 10).
  - Restore refuses when the category has been deleted, and it serializes correctly against a concurrent category delete (FOR SHARE vs FOR UPDATE).
  - Items under an earlier-deleted block come back the same way they did before (consistent with M9).
- **The seeding fix is correct.**
  - A new couple gets keys V, l, t, x, z, zV, zl, so Notes is first. Checked in a rolled-back transaction.
  - An existing couple gets Notes at key_between(NULL, min), so P1 review finding M2 is closed.
- **The server never returns a pinned plan twice.** Pinned plans are kept out of the keyset stream on the server side.
- **The swipe handling is safe.**
  - Flutter checks `mounted` after confirmDismiss, so when the optimistic move disposes the swiped tile, nothing is called on it.
  - onDismissed removes the row synchronously.
  - Undo still works after the user has left the screen (verified: the restore is sent and nothing rebuilds after disposal).
- **Accessibility and Notes handling are done right.**
  - Long-press and screen-reader custom actions both offer Pin and Delete.
  - Notes has no template menu items.
  - Notes is detected by seed_key rather than by name, so renaming it is safe.

### Issues

#### Critical
None.

#### Important

**I1. Undo can push a category past the 20-pin cap, and the 21st pinned plan then disappears from the list. (VERIFIED)**
- Where:
  - `supabase/migrations/20261012200600_planning_v2_notes_and_pins.sql:233-261`: `restore_planning_entry` keeps `pinned_at` and never checks the limit.
  - `:183`: the pinned group is `LIMIT 20`.
  - `:166`: `entries` excludes every pinned row.
- Scenario: the category has 20 pins. The user swipes a pinned plan to delete it (19 pins left), pins another plan (20 again), then taps Undo. Now 21 live plans are pinned.
- Effect: the plan with the oldest pin appears in neither `pinned` nor `entries`. It stays hidden until the user happens to unpin something else.
- Repro (overflow.sql, rolled back): `live pinned after undo: 21`, `pinned group: 20, entries: 1, total live non-template: 22`, `restored entry in pinned? f  in entries? f`.
- Fix (either option):
  - In restore, keep the pin only if the category still has fewer than 20 pins under the lock; otherwise null `pinned_at`.
  - Or clear `pinned_at` in delete_planning_entry.
- Add a contract case for this.

**I2. Optimistic pin and delete overwrite each other and the paging state, because they write back whole-state snapshots. (VERIFIED)**
- Where (`lib/features/planning/v2/presentation/planning_v2_providers.dart`):
  - `loadMore` (125-136) writes `[...s.entries, ...page.entries]` from the snapshot it took before awaiting the page.
  - `copyWith` (93-106) resets `loadingMore` to false by default.
  - `togglePin` and `delete` (141-175) roll back to the whole `before` snapshot.
- Repros (scratch tests, all fail against this branch):
  - A: delete a plan while page 2 is loading. When the page lands, the deleted plan reappears (`Expected: false, Actual: true`). This survives the signal refetch whenever the page lands after it.
  - B: pin a plan while page 2 is loading. `loadingMore` drops to false, and the scroll listener fires loadMore again on any ScrollNotification. The same cursor is fetched twice (`has length of <2>`), so page 2 is appended twice.
  - C: unpin an old pinned plan, then load the next page. The plan shows twice: optimistically at the top, and again at its activity position.
  - D: a pin refused with limit_reached while a delete of plan B was in flight rolls back to `before`. B reappears although the server deleted it (`Actual: ['A', 'B']`).
- Who hits it: anyone with 30 or more plans in a category who swipes while a page is loading or a pin is in flight. Notes will reach 30 plans quickly (see m1).
- The realtime signal refetch usually corrects it, but not when the stale write lands after that refetch.
- Fix:
  - Apply mutations and page appends to the current `state.valueOrNull`, not to a snapshot.
  - De-dupe appended entries by id, and drop ids that are already pinned.
  - Make `copyWith` keep `loadingMore` unless it is set explicitly.
  - Roll back a failed action by reversing only that action (put that one entry back), not by restoring the whole snapshot.

#### Minor

**m1. Backing out of a new note leaves an empty "New note" plan behind.**
- Every accidental "+ New note" tap persists a blank note, because `_newNote` (category_screen.dart:61) creates it before the editor opens.
- `_newNote` also has no in-flight guard, so a double tap on the FAB creates two notes and pushes two screens (from reading the code).
- Suggestion: when the editor closes without a save and the note is still untitled and empty, delete it.

**m2. The 21st pin shows the wrong message. (VERIFIED, test D)**
- The snackbar says "That is over the limit. Make it shorter and try again." because `planning_v2_error.dart:101` has no case for `pinned_per_category`.
- Add a case such as "You can pin up to 20 plans here. Unpin one first."

**m3. Undo moves the plan to the top and shows the partner a "new" dot.**
- Restore calls `planning_v2_touch_entry` (migration:258), so the restored plan does not return to its old position.
- Restoring `last_activity_*` unchanged would make Undo a true undo.

**m4. Restore accepts any deleted plan up to purge time (30 days or more), not just a recent delete.**
- An old restore can race the nightly purge. The purge deletes items, then blocks, then entries; restore locks the entry, then the items. That is a possible deadlock at the 30-day boundary (unverified).
- Suggestion: bound restore to recent deletes, e.g. `deleted_at > now() - interval '1 day'`.

**m5. `pin_planning_entry` takes the category lock as FOR UPDATE where FOR NO KEY UPDATE would do.**
- FOR UPDATE also conflicts with FK KEY SHARE, so each pin briefly blocks entry inserts and `mark_planning_category_seen` in that category.
- FOR NO KEY UPDATE serializes the pin count just as well.

**m6. The new-note title can overwrite a partner's change.**
- `_titleNewNote` (text_editor_screen.dart) decides from the cached title, then calls `rename`, which sends the cached `status`.
- If the partner renamed the note or marked it done before the signal refetch, that change is overwritten. The window is small.

**m7. Some list states look wrong while a pin is in flight.**
- When an unpin leaves the tile at the same index (e.g. unpinning the last of several pins), the tile stays slid off-screen until the RPC returns.
- There is no header or divider between the Pinned group and the unpinned plans.
- Long-press gives no haptic feedback (GestureDetector rather than InkWell.onLongPress).

**m8. On iOS, swipe-right-to-delete sits next to the back-swipe gesture.**
- A back-swipe that starts just outside the ~20px edge zone deletes a block or plan instead (Undo exists). Unverified on a device.

**m9. Older clients would lose pinned plans from view.**
- `list_planning_entries` now leaves pinned plans out of `entries`. A client built from P1 main would not see them at all.
- This is harmless only while v2 stays preview-only; keep it that way until the client ships.

### Declined to judge
- `planning_v2_concurrency.sh` case 6: not run, because the script commits fixtures and needs `local_pg_setup.sh`, both outside my rules. The reasoning above covers it.
- Exact RTL swipe semantics: Dismissible directions follow text direction. That is consistent, but the product intent for RTL is unspecified.

### Verdict
Ready to merge: with fixes. The SQL locking and seeding are sound. Fix I1 (a one-line server change plus a contract case) and I2 (the provider snapshot handling) first, and ideally m2.

---

## Executor's disposition (2026-10-12)

- **I1 fixed.** Restore drops a pin that no longer fits under the cap, counted under the category FOR UPDATE lock. Contract 10b failed (RED) before the fix and passes (GREEN) after.
- **I2 fixed.** List edits apply to the current state; appended pages are de-duplicated; flags are kept; a failure reverts only the plan it touched. Four race tests held open with Completers failed before the fix and pass after.
- **m2 upgraded and fixed.** The 21st pin has its own message (test failed before, passes after).
- **m1 upgraded and fixed.** An untouched new note is discarded when the editor closes without a save, and a double-tap creates one note. Both tests failed first; the double-tap test was rewritten after it passed vacuously.
- **Deferred:**
  - m3: Undo touches activity, so the restored plan moves to the top and lights the partner's dot.
  - m4: restore is not limited to recent deletes; a purge-race deadlock is possible (unverified).
  - m5: pin takes FOR UPDATE where FOR NO KEY UPDATE would do.
  - m6: auto-title can overwrite a partner's concurrent rename.
  - m7: visual polish (slid-off tile during unpin, no divider, no haptics).
  - m8: iOS back-swipe vs swipe-right delete (unverified; Undo exists).
  - m9: P1-built clients don't see pinned plans (fine while v2 is preview-only).
