# 07b: adversarial verification of reports 04, 05 and 06 (Critical/High plus two Mediums)

Verifier B, 2026-10-23. Read-only on the repo. I traced every cited path in source and tried to refute each finding. I ran one probe widget test (`zz_verify_b_privacy_cover_probe_test.dart`). It was written in `scratchpad/verify_b/`, copied into `test/` for a single `flutter test` run, and deleted right after. Afterwards `git status --porcelain test/` showed only the five entries that were already there before I started. I needed no SQL: every server claim in scope could be settled from the migration and edge-function source.

**Probe result.** The probe uses `MaterialApp.router`, a GoRouter, and the real `AppPrivacyCover` in `builder`. It pushes a GoRouter page `/chat`, raises a counter in it to 1, then `Navigator.push`es a pageless route. Then it sends inactive → resumed.

| Cover | Pageless route after resume | GoRouter page after resume | State re-inits |
|---|---|---|---|
| Real `AppPrivacyCover` | **0** (gone) | present, but **reset** (counter back to 0) | 2 |
| Candidate fix: `Stack` + `Offstage` + `TickerMode` + `ExcludeSemantics` | 1 (kept) | counter still 1 | 0 |

With the candidate fix, the secret text could not be found while the cover was up.

## 1. Verification table

| ID | Source(s) | Issue | Verdict | Final sev | Evidence of verification | Root-cause group |
|---|---|---|---|---|---|---|
| V1 | 06 #1, **dup of 02 #1** (also 02 #4, #16) | Deleting in a day reel or places reel desyncs the reel by index. The deleted media stays on screen, and a second Delete permanently removes an unseen story | CONFIRMED | **Critical** | <ul><li>`story_reel_screen.dart:943-948`: no step-off unless the deleted item was the last.</li><li>`:1135-1143`: `currentItem = items[clampedIndex]` comes from the *refreshed* list.</li><li>`_ReelBody` gets `signedUrl: _currentSignedUrl`, which is still the deleted item's URL (still valid for up to 600 s).</li><li>The auto-start guard needs `!_rendered`, so nothing restarts.</li><li>Both 02 and 06 reproduced this with probes.</li></ul>Not refutable: the confirm dialog cannot tell the person which item it targets. Reachable today only from calendar or map reels, because the author reel has no delete. Fixing V6 first would expose it on the main path. | G1 |
| V2 | 06 #2, **dup of 02 #5** | A first item that fails to sign or initialise restarts itself in an endless loop | CONFIRMED | High | <ul><li>A `signedUrl == null` result, or a video `initialize()` throw, ends with `_loadingItem=false, _rendered=false` (`:444-465`).</li><li>That makes the build guard at `:1130` true again, so a post-frame `_startItem` runs. Each pass also re-announces "Story 1 of N".</li><li>`signMediaUrl` swallows every error into `null` (`story_read_repository.dart:545+`).</li></ul>The probe's "61 calls/s" came from an instant fake. On a device, the rate is bounded by the time it takes to fail: offline fails fast, so the rate is near frame rate; a missing object costs one round trip, so about 3–10/s. A video failure builds a new `VideoPlayerController` on every pass. | G2 |
| V3 | 06 #3, **dup of 01 #1** (01 #3 is the same classifier) | An offline post gives up after about 15–30 s. Nothing retries it on reconnect, on resume or after a restart | CONFIRMED | High | <ul><li>`story_outbox_controller.dart:112`: cap of 5.</li><li>`:409-411`: windows of 2, 4, 8 and 16 s with equal jitter.</li><li>`:399`: `attempts >= 5` makes the record `permanent`.</li><li>`:180`: flush skips `failedPermanent`.</li><li>The doc at `:166` promises "a connectivity-restored listener". `grep connectivity\|onResume lib/features/stories` finds none for the outbox.</li><li>`story_repository.dart:195-203`: every Storage refusal (403/413) also becomes `network`.</li></ul>The capture is not lost: Retry and Discard stay visible. | G3 |
| V4 | 06 #4, **dup of 02 #10** | The poster never sees "Seen" on their own items | CONFIRMED (spec gap), **re-graded** | **Medium** (was High) | <ul><li>`hasBeenViewed` is read only by `calendar_day_sheet.dart:313`, which ignores it for own items. The reel never reads it.</li><li>STORIES.md:681 promises the indicator.</li><li>Seen receipts are **off by default** (`20261017120000_seen_receipts.sql:100-104`, "default off wins"). For most couples the server masks the value anyway.</li></ul>A missing opt-in feature does no harm to anyone. | G4 |
| V5 | 06 #5a, **dup of 01 #7** | No pre-post review: a shutter tap posts straight away | CONFIRMED (by design) | High | `story_camera_screen.dart:164-176`, with the comment "there is no review sheet here (spec §6.1: the outbox queue itself … is the review)". Combined with V6 and the missing cancel (01 #13), an accidental capture cannot be withdrawn before the partner can see it. Owner ruling against spec §6.1. | G5 |
| V6 | 04 #2, 06 #5b, **dup of 02 #9** | The author cannot delete from their own active reel | CONFIRMED | High | <ul><li>`story_reel_screen.dart:1145-1147`: `perItemAuthor = occurredOn != null \|\| _placesMode` and `canDeleteCurrent = perItemAuthor && isAuthor`. The block comment cites spec §5.3 as intent.</li><li>A workaround exists: today's date in the calendar opens the day sheet, which offers delete. It is not discoverable, and the partner may watch first.</li><li>**Must ship after G1**, or V1 moves onto the main path.</li></ul> | G1 / G6 |
| V7 | 05 #1 | The privacy cover unmounts the whole Navigator on every *inactive* | CONFIRMED on iOS (probe plus code). PLAUSIBLE on Android (needs a device) | High (scope wider than reported) | See §1a below | G7 |
| V8 | 04 #1 (the Medium-in-scope "export sorts story media last") | Export walks story media last, behind a 12-part cap. After an ending, export is the only way out | CONFIRMED | High | See §1b below | G8 |
| V9 | 05 #2, **dup of 01 #11** (the Medium-in-scope "outbox survives sign-out") | The story outbox and its capture files survive sign-out and quick exit | CONFIRMED, **not underrated** | Medium | See §1c below | G9 |
| V10 | 06 C.1 / #22 | `requireServiceRole` compares the secret with `!==` (checklist 2.3) | CONFIRMED | Low (but a P0-U gate item) | `supabase/functions/_shared/attune_auth.ts:43`: `token !== requireEnv("SUPABASE_SERVICE_ROLE_KEY")`. There is no `timingSafeEqual` anywhere under `supabase/functions`. The edge function is reached over the network, so a timing attack is theoretical but not excluded. | G10 |

### 1a. V7 evidence: the privacy cover

- **Wiring.** `app.dart:85-90` passes `MaterialApp.router(builder:)`'s `child`, which is the Router and its Navigator, into `appShell`. In `app_shell.dart:20-40` the order is `SafetyLockGate` → `AppPrivacyCover` → … → child.
- **Mechanism.** `app_privacy_cover.dart:63-70` *returns a `ColoredBox` instead of* the child on `inactive`, `hidden` and `paused`. That unmounts the Router subtree, `appNavigatorKey` included. The GlobalKey cannot carry the subtree across frames.
- **What the probe shows.**
  - Pageless routes are destroyed. That covers the story camera and the reel (`conversations_screen.dart:236-266`), the calendar reel (`story_day_row.dart:53`, `calendar_day_sheet.dart:207`), and the story-quote reel (`message_bubble.dart:115`).
  - GoRouter pages, such as the chat screen (`context.push(RouteNames.chatScreen)`), are rebuilt from the delegate **with fresh State**.
- **The comment in the file is false.** It says "removed from the tree entirely", but Offstage already guarantees the snapshot shows only the cover.
- **The code knows about the teardown.** `safety_lock_controller.dart:118` says: "AppPrivacyCover unmounts the app's subtree whenever it goes inactive". `message_bubble.dart:1897-1900` handles "a Navigator torn down before the viewer was ever built".
- **iOS triggers.** `willResignActive` maps to `inactive`: Control Centre, Notification Centre, incoming call, Face ID, and system permission alerts. On the first use of the story camera, the camera and microphone permission alert therefore closes the camera.
- **Capture drop.** `story_camera_screen.dart:204` has `if (!mounted) return;` after `confirmSend`, so a take captured just before the blip is never queued and no message is shown.
- **A second, unreported teardown.** `SafetyLockGate` (`safety_lock_gate.dart:30-34, 71-73`, together with `safety_lock_controller.dart:166-169`) sets `checking` on **every** resume after a hide, PIN or no PIN, and in that state also returns a bare `ColoredBox` in place of the child. So a plain app switch tears down the Navigator a second time.
- **Chat is affected too.** The chat screen survives as a page, but its scroll position and State reset. Every pageless route above it closes: message info, the Ask Attune and Understand sheets, the streak viewer, and dialogs and bottom sheets. Drafts survive because they are persisted (`chat_screen.dart:455-480`).

### 1b. V8 evidence: export order

- `20261018120000_data_export.sql:428-437` orders by `(bucket, object_name)`. Alphabetically, `journal-media` < `message-media` < `planning-media` < `story-media`, so story media always comes last.
- `parts.ts:39`: `maxParts: 12`. `:142`: `lastPart` counts **all** parts, including the data part and the chat parts.
- `bundle.ts:17`: each part takes at most 150 files and 40 MB. That leaves at most about 11 × 40 MB for media, and less once chat pages take parts.
- The remainder is marked `over_limit` (`parts.ts:202-205`). It is listed in `media_not_included.txt`, so the loss is disclosed, not silent.
- In-app access closes at pause/end (`story_relationship_is_open` requires `active`). `export_open_relationships` uses `relationship_chat_open_for`, which is the 30-day window. The local file is deleted on success (`story_outbox_controller.dart:336-337`).
- A second export walks the same order.
- Not refutable. A memory is permanently out of the person's reach after the window, or after the 12-month purge.

### 1c. V9 evidence: outbox after sign-out

- `auth_provider.dart:157-235` signs out without touching the story outbox.
- `StoryOutboxStore.clearAll` (`story_outbox_store.dart:174`) has no caller.
- The database is `getApplicationSupportDirectory()/attune_story_outbox.sqlite` (`story_outbox_backend_io.dart:62`). It is never passed to `BackupExclusion`, which is used only by chat (`chat_cache_backend_io.dart:183`, `chat_image_picker.dart:407`).
- Rows are keyed by `user_id` (`:51-57`, `readAll WHERE user_id = ?`). When the same account signs in again, the controller (constructor `flush()`) posts the queued story without asking.

Why it is not underrated:
- The payload is AES-GCM under a this-device-only Keychain key, so a backup restored on another device cannot read it. A backup leaks only `user_id`, `client_story_id` and `created_at`.
- The captures sit in `tmp/`, which is not backed up and is sandboxed.
- The residue is plaintext captures on the device until the OS purges `tmp/`, plus an auto-post that the person did originally ask for.
- That is a real gap in sign-out and quick-exit hygiene, but it is not a breach.

**Counts.** CONFIRMED 9 (V7 is CONFIRMED on iOS; its Android half is PLAUSIBLE and needs a device). REFUTED 0. One re-grade: V4, High → Medium. Six of the ten are duplicates of findings in 01 or 02 (V1–V6); V9 also duplicates 01 #11.

## 2. Root-cause groups and minimal fix designs

| Group | Fix (one line) | Shared/core? |
|---|---|---|
| G1 Reel identity by index (V1, V6 prerequisite, 02 #4, #16) | Track `_currentItemId`. On every `items` change, re-resolve the index. If the id has vanished, `_startItem(items, min(oldIndex, len-1))`, or close when empty, and stop the player and ticker. Delete and reply use the item that is actually shown. | No (stories only) |
| G2 Inferred auto-start (V2) | Replace the state-inferred guard with a one-shot `_autoStarted` flag. Add an explicit `_itemFailed` state with "Couldn't load · Retry / Next", and never restart per frame. | No |
| G3 Outbox retry policy (V3, 01 #3) | <ul><li>`network` errors get no attempt ceiling: backoff capped at 6 h, with jitter.</li><li>Flush on `AppLifecycleListener.onResume` and on connectivity-restored (reuse the source behind the chat drainer).</li><li>Classify `StorageException` 400/403/413 as permanent or re-intent instead of `network`.</li></ul> | Low risk: reads a shared connectivity provider only |
| G4 Seen chip (V4) | In the own reel, render "Seen" / "Not seen yet" from `hasBeenViewed`, only when receipts are effective (the server already masks it). | No |
| G5 Pre-post review (V5) | Add a preview step in the **story adapter** (`story_camera_screen.dart`) with Share and Retake before `enqueueLocally`. Do not change `CaptureCameraScreen`'s contract. | **Yes, if done through the shared `CaptureCameraScreen.isReviewing`** (streaks). Keep it in the adapter, or keep `streak_camera_contract_test` green. |
| G6 Own-reel delete (V6) | `canDeleteCurrent = isAuthor` in every mode. After delete, refresh `storyReelPagesProvider` and close when empty. Update the test that pins "author-mode never shows delete". **Ship only after G1.** | No |
| G7 Root shell swaps the child out (V7) | In `AppPrivacyCover`, and in `SafetyLockGate`'s `checking` branch, keep the child mounted: `Stack[Offstage(offstage: obscured, child: TickerMode(enabled: !obscured, child: ExcludeSemantics(excluding: obscured, child: child))), if (obscured) cover]`. Keep `locked` as a full replacement. Make `_prepareAndEnqueue` enqueue without `mounted`. | **YES: core shell above every route.** See the regression notes below the table. |
| G8 Export order (V8) | <ul><li>Rank story media first, e.g. `ORDER BY class_rank, bucket, object_name`. Because the keyset cursor is `(bucket, name)`, either add the rank to the cursor and job row, or give stories a reserved per-class budget.</li><li>Say in the README how many stories were left out.</li></ul> | **Shared with export (Spec 3c).** In-flight jobs hold old cursors: migrate or restart queued jobs. |
| G9 Sign-out wipe (V9) | <ul><li>In `signOut()`'s `wipeQueue`, add `storyOutboxStore.readAll` → delete each record's local files → `clearAll`, in its own try, bounded like the chat staging wipe.</li><li>`BackupExclusion.exclude` the outbox DB plus `-wal` and `-shm`.</li><li>Add the same three files to both Android backup XMLs.</li></ul> | **Shared: `auth_provider.dart`.** Additive and in its own try. Re-run the sign-out tests. |
| G10 Constant-time compare (V10) | Hash both tokens with SHA-256 and compare with `timingSafeEqual` in `_shared/attune_auth.ts`. | **Shared by every service-role edge function.** Run each worker's tests. |

**G7 regression risks** (checked against current code):
1. The camera controller would now survive inactive and background. `CaptureCameraScreen` has no lifecycle handling (01 #15), so the preview may freeze or go black on resume. Add a camera pause/re-init on lifecycle in the same change.
2. A media player without its own lifecycle pause would keep playing audio behind the cover. The story reel has one (`story_reel_screen.dart:342-344`, which becomes live after this fix). Audit the chat video, ephemeral viewer and voice playback.
3. The Understand sheet would stay open with its result cleared. It clears through its own listener (`ai_assistant_providers.dart:230-234`), so the open sheet needs an idle state.
4. Notification taps during `checking` now find a mounted Navigator. Keep `shouldDeferNotificationTap` keyed on lock state.
5. Re-run these tests:
   - `app_privacy_cover_test`: it still passes, because finders skip offstage widgets by default.
   - `understand_sheet_test:355-385`.
   - `assistant_notice_test`.
   - The safety-lock and quick-exit tests.
   - Add one new test: a pushed route survives inactive → resumed.

## 3. Checklist v3.1 grade re-check (06: C+, fails P0-U 2.5 and P1 3.10; 2.3 at `attune_auth.ts:43`)

The checklist defines no letter grades. Its gates are binary: a P0-U failure means "code review cannot begin" (`algorithm_quality_review_checklist.md:54`). Reviewer 6's letter grade is their own synthesis.

**Confirmed failures**

| Item | Gate | Evidence |
|---|---|---|
| 2.3 | P0-U | `attune_auth.ts:43` uses `!==`. Confirmed. |
| 2.5 | P0-U | The unbounded iteration in V2 is confirmed. Server-side it is also partial: the `story-media` bucket has no `file_size_limit` or `allowed_mime_types` (05 #5, 01 #17). |
| 7.1 / 7.3 | P0-U | `.github/workflows/tests.yml` is the only workflow. It runs analyze, flutter tests and SQL contracts. There is no dependabot, gitleaks or trufflehog. |
| 3.10 | P1 | Confirmed on **two** causes: the reel retries a permanently missing object (V2), and the outbox retries Storage 4xx as `network` (01 #3). Reviewer 6 marked the outbox side as passing, which is wrong. |

**Adjustments: P1 items 06 marked PASS that should FAIL**

| Item | Why it fails |
|---|---|
| 2.16 Shared mutable state protected | A list changing under an index causes Critical data loss (V1). |
| 2.13 Cleanup on cancellation | When the camera is unmounted mid-prepare, the capture is dropped (V7, 05). |
| [MOBILE] lifecycle | The app-wide teardown in V7. |
| 1.11 Privacy | It is partial, not pass: outbox residue (V9), and no way to delete stories after an ending (05 #3). |

**Grade.** I adjust it to **C (about 6.3/10)**: Robust 5 (V1, V2, V3, V7) and User-aware 5. The other dimensions stay as 06 scored them.

**Gate verdict.** Stories fail P0-U (2.5 is story-specific; 2.3, 7.1 and 7.3 are shared or project-wide). They also fail P1 on 3.10, 2.16, 2.13 and 7.7.

**To clear the gates:** fix G1, G2, G3 and G7 with regression tests, plus G10, a bucket size and MIME ceiling, and CI dependency and secret scanners.
