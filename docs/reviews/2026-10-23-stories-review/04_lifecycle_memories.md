# Stories review 04: the 24-hour lifecycle and calendar memories

Reviewer 4 of 6, 2026-10-23. Read-only. Evidence comes from source, two Flutter test files run locally (20/20 pass), and SQL contracts run against `attune_spec3a`. In that database `story_maintenance`, `story_rpc`, `story_schema`, `story_seen_state` and `together_story` passed. `story_read` and `story_security` hit a scratch-DB fixture collision on `users_phone_key`, and `story_places` hit a local-grants artefact (finding 18). I also read `cron.job` on the scratch DB and ran one time-zone demonstration query.

## 1. Verdict

The core of the 24-hour lifecycle is solid.
- **Expiry:** it is purely structural. One server-side predicate, `expires_at > now()`, gates the ring summary, the active reel and view marking. Nothing deletes on expiry.
- **One row per story:** the reel and the calendar read the same row, so expiry and deletion cannot leave the two out of step.
- **Deletion:** soft and hard deletes both queue every object through the Storage-API drain.
- **Crons:** they are registered and call the right functions.

Expired stories do show on the poster's day for both partners. They show with a thumbnail and they still play after archival, because the archived rendition becomes `media_key` and the storage policy authorizes it.

The weak points sit around that core:
- **Getting memories out:** this is the most serious gap. The story camera keeps no local copy. In-app access to stories closes the moment a relationship is paused or ended. Export is then the only way out, and it puts story media last behind a ~480 MB cap. The files also have no extension.
- **Deleting a fresh story:** an author cannot delete a story they just posted from their own reel. Deletion exists only in the calendar.
- **Dating:** `occurred_on` and the 24-hour window come from finalize time, not capture time. An offline or slow upload near midnight lands on the wrong day.
- **Archival:**
  - It is throughput-capped at 20 images an hour.
  - Portrait images, which are most stories, never reach the 1600 px target.
  - It does not check the new rendition before an irreversible swap.
  - The alerts and metrics the spec says exist are not implemented.
- **Calendar:** reads fail silently, and both rings on a day open the same reel from its first item.

## 2. What is solid (with evidence)

- **Expiry hides and never deletes.**
  - All active reads filter `expires_at > now()` on the server: `list_active_story_items` and `get_story_ring_summary` (`20261017140000_story_seen_state.sql:31-62, 98-128`), and `mark_story_viewed` (§3.4).
  - Day reads have no expiry filter: `list_story_day_items` (`20261017140000:64-96`) and `list_story_day_counts` (`20260951010000:43-94`).
  - No job touches a row at expiry. `cleanup_expired_story_media_intents` touches only intents. Archival only swaps a key.
  - The client never re-derives expiry (`story_reel_screen.dart:654-664`), so device clock skew cannot affect it.
- **The 24-hour window is DST-safe.** `CHECK (expires_at = created_at + interval '24 hours')` (`20260938010000_stories_schema.sql:60-61`) uses an exact 24-hour interval, not `'1 day'`. One captured `v_now` sets `created_at`, `expires_at` and `occurred_on` (`20260938120000_stories_finalize_race_fix.sql:231-255`).
- **`occurred_on` is frozen at insert from a clamped offset.**
  - The server clamps it with `greatest(-840, least(840, …))` (`20260938120000:231`).
  - The offset sign is correct: Dart `timeZoneOffset` is positive east of UTC, and the server adds it.
  - The client sends dates as `YYYY-MM-DD` strings (`story_read_repository.dart` `listDayCounts`/`listDayItems` `dateOnly`), and the response is parsed back to local midnight, so there is no UTC day shift on the client.
- **Deleting removes the story from every surface at once.**
  - Both day RPCs exclude `deleted_at` rows: through RLS (`20260938020000_stories_rls.sql` `story_items_read_members`) or inline (`20261017140000:87`).
  - The storage SELECT policy refuses to sign a deleted story's keys (`20260940120000_story_storage_policy_isolation.sql:46-60`).
  - The signal bump refreshes rings, counts and open reels (`story_providers.dart` `storyDayCountsProvider` / `storyDayItemsProvider` listen to `storyChangeSignalProvider`).
  - The signal table is now in the Realtime publication (`20261018130500_story_signals_realtime.sql`).
- **The delete RPC is correct.** It row-locks, checks authorship and is idempotent. It queues media, thumbnail and the archive key (delayed 600 s) in the same transaction, and closes the processing outbox row (`20260938140000_stories_archival_dead_letter_fix.sql` `delete_story_item`). `queue_story_media_deletion` re-arms on conflict (`20260938070000:72-96`). `story_places` rows are dropped on soft delete (`20261017100000:113-126`).
- **Hard deletes queue media too.** The `BEFORE DELETE` trigger queues three keys per row for relationship purge, account-deletion cascade or maintenance (`20260938070000:304-329`). Contract 7 of `story_rpc_contracts.sql` (lines 1495-1555) proves the cascade queues all four objects plus the archive keys, and it passed on `attune_spec3a`.
- **The relationship purge covers story storage.** `relationship_queue_storage` queues `story-media/<rel>/%` and unused intents. The trigger covers `story-archive/<id>.jpg`, which lives outside that prefix (`20261018110000_chapters_deletion.sql:126-150`).
- **Account deletion covers story storage.** `prepare_account_deletion` queues the person's unused story intents, and the author's `story_items` cascade through the trigger (`20261018110000:205-273`).
- **Archival is ordered correctly.**
  - Order: upload the rendition, then swap the key only where `deleted_at IS NULL AND downscaled_at IS NULL` still holds, then queue the old key with a 600 s delay, then bump the signal (`20260938090000` `complete_story_archival`). A zero-row swap queues the new key instead.
  - The archive key is computed by the database function, not rebuilt in TypeScript (`process-story-archival/index.ts:56-63`).
  - Archived images still play because the archive key becomes `media_key`, which the storage policy authorizes.
  - Thumbnails are never touched, so calendar avatars never break.
- **Crons are registered and correct** (checked in `cron.job` on `attune_spec3a`):

  | Job | Schedule | Calls |
  |---|---|---|
  | `cleanup-expired-story-media-intents` | `33 * * * *` | `cleanup_expired_story_media_intents()` directly |
  | `invoke-story-archival` | `38 * * * *` | `invoke_edge_function('process-story-archival')`; the retired-GUC bug was fixed in `20260938130000` |
  | `drain-media-deletion-queue` | `*/10` | `invoke_edge_function('process-media-deletion-queue')`; the original `current_setting('app.settings…')` registration in `20260930130000` was replaced by `20260931120000_vault_backed_settings.sql:124-131` |
  | `purge_archived_relationships` | daily | its own function |
  | `close_relationship_windows` | hourly | its own function |

  Physical removal always goes through the Storage API (`process-media-deletion-queue/index.ts`). No story path deletes from `storage.objects` directly.
- **Calendar wiring and expired playback are tested.** `story_calendar_test.dart` and `story_calendar_wiring_test.dart` pass 20/20. They cover:
  - an expired item absent from the author reel but present in day mode;
  - a mixed-author day marking only the partner's items;
  - delete being author-only.

## 3. Findings

| # | Issue | Sev | Evidence (file:line) | Scenario | Fix design |
|---|---|---|---|---|---|
| 1 | Story memories can be impossible to take out. The export lists media sorted by bucket name, so `story-media` comes last after journal, message and planning media. The total is capped at 12 parts × (150 files / 40 MB), about 480 MB and 1,800 files. Meanwhile the capture's local file is deleted after posting, and in-app story access closes at `paused`/`ended`. | High | `20261018120000_data_export.sql:412, 435-437` (ORDER BY bucket); `build-data-exports/parts.ts:38-39`; `bundle.ts:17`; `story_outbox_controller.dart:336`; Spec 3a plan R3-3 (stories closed at `ended`, "reachable through export") | A couple with a year of chat photos and videos ends the relationship. One partner taps Download my data inside the 30-day window. Chat media fills the budget, and every story video and photo is listed as `over_limit`. A second export repeats the same order. After the window the stories are gone for good, because no copy exists on the phone. | <ul><li>Give each media class its own budget, or walk stories first. Stories are the only class with no on-device copy.</li><li>Raise `maxParts`, or offer a stories-only export.</li><li>Add a per-item "Save to phone" in the day reel (see §5).</li><li>Have `export_relationship` say how many stories were left out.</li></ul> |
| 2 | An author cannot delete a story from their own active reel. Delete is offered only in day/places mode. | High | `story_reel_screen.dart:1137-1148` (`perItemAuthor = occurredOn != null \|\| _placesMode`); `story_calendar_test.dart` asserts "author-mode never shows delete" | I post the wrong photo, open my ring to remove it and find no delete. My partner watches it before I find Timeline → that date → day sheet → delete. | <ul><li>Set `canDeleteCurrent = isAuthor` in author mode as well. The RPC is already author-only and idempotent.</li><li>After delete, refresh `storyReelPagesProvider`, and close the reel if it is now empty.</li><li>Update the test that pins the current behaviour.</li></ul> |
| 3 | `occurred_on` and the 24-hour window use the server's finalize time, combined with the device offset captured earlier. An offline or slow post, or a retry, near midnight files the memory on the wrong day. A capture in one zone finalized after travel mixes the old offset with the new instant. | Med | `story_outbox_controller.dart:44-48, 318-329`; `20260938120000:231-233`; `story_camera_screen.dart:206-220` (offset and `createdAt` read at capture) | A 25 MB video captured at 23:59 on our anniversary uploads for 40 s and files on the next day. A photo taken offline at a Saturday-night festival and posted Sunday morning appears on Sunday. | <ul><li>Send `p_captured_at` (record `createdAt`, UTC) to `create_story_item`.</li><li>On the server, clamp it to `[now() - 72h, now()]`, then compute `occurred_on` from `captured_at` plus the offset.</li><li>Keep `expires_at = now() + 24h`, so the reel still gets a full window.</li><li>Update STORIES.md §6.1 to match.</li></ul> |
| 4 | The day sheet's per-author rings both open the same whole-day reel at item 0. Its count and author grouping come only from the first page (≤ 50 items). | Med | `calendar_day_sheet.dart:205-216` (`_openReel` ignores author), `:228-279` (count = `items.length`, rings from page 1 only) | I tap my partner's ring on a day we both posted and my own five stories play first. On a day where I posted 50 in the morning, my partner's ring is missing and the label says "50 stories". | <ul><li>Add an optional `p_author_id` to `list_story_day_items` and an `authorId` on `StoryReelScreen.forDay`.</li><li>Take the count and author list from `list_story_day_counts`, which is already per author with `day_item_count`.</li></ul> |
| 5 | Calendar story reads fail silently. Loading and error both render nothing, with no retry. | Med | `calendar_day_sheet.dart:228` (`items == null \|\| items.isEmpty → SizedBox.shrink`); `story_day_row.dart` `StoryDayCountRow` (`counts == null → shrink`); `calendar_day_indicators.dart:198-201` (`valueOrNull` → `[]`) | On a flaky network I open last year's anniversary. There are no avatars on the grid and no stories in the sheet, so it looks like the memory was deleted. Nothing tells me to retry. | <ul><li>Branch on `AsyncValue.hasError`: show an inline "Couldn't load stories · Retry" row that calls `ref.invalidate(...)`.</li><li>Show a small skeleton while loading.</li></ul> |
| 6 | Calendar thumbnails make one signed-URL Storage call per cell per build, and cache images by URL. The signed token changes on every call, so `CachedNetworkImage` never hits disk across opens, and `autoDispose` re-mints the URL on every month change. | Med | `calendar_day_indicators.dart:226-247`; `story_providers.dart` `storyMediaSignedUrlProvider` (`autoDispose`); `story_read_repository.dart` `signMediaUrl` (no cache) | Swiping back and forth through a year of months fires dozens of signing requests and re-downloads every thumbnail each time. Avatars pop in late, and the work costs battery and bandwidth. | <ul><li>Set `cacheKey: storageKey` on `CachedNetworkImage`; the security boundary is the URL, not the cached bytes.</li><li>Batch-sign a month's thumbnail keys with `createSignedUrls`.</li><li>Keep the provider alive for about 9 minutes (`ref.keepAlive` plus a timer, below the 600 s TTL).</li></ul> |
| 7 | Archival resizes by width only. Portrait images (1440×2560), which are most stories, keep a 2560 px long edge, or are upscaled to 1600 px wide if the service enlarges (Needs verification). That breaks the spec's "1600px long edge", and storage savings mostly fail to arrive. | Med | `process-story-archival/index.ts:78-84` (`transform: { width: 1600, resize: "contain" }`); STORIES.md §4.4 | Every vertical story gets a re-encode at roughly the same pixel size, or grows larger. | <ul><li>Have the claim RPC return `media_width`/`media_height`.</li><li>Request `{width: 1600}` when width ≥ height, else `{height: 1600}`.</li><li>Skip, mark done, and delete nothing when the long edge is already ≤ 1600.</li></ul> |
| 8 | Archival runs an irreversible swap with no check on the new rendition. Any truthy `Blob` is uploaded and swapped in, and the original is queued for deletion 600 s later. | Med (Needs verification) | `process-story-archival/index.ts:86-99` (no size, type or dimension check), `complete_story_archival` in `20260938090000` | If the transform service ever returns an empty, truncated or non-image body with a success status, that memory permanently becomes a broken image 10 minutes later. | <ul><li>Require `bytes.byteLength > 0`, `image.type` starting with `image/`, and a decodable JPEG header before calling `complete_story_archival`.</li><li>Lengthen the old key's `not_before` to around 7 days, so a bad batch can be reverted from the queue.</li></ul> |
| 9 | Archival throughput is capped at 20 images an hour (480 a day) across the whole user base. | Med | `process-story-archival/index.ts:27` (`DEFAULT_LIMIT = 20`); cron `38 * * * *`; `invoke_edge_function` sends `'{}'` (`20260931120000:85-93`) | Once couples post more than 480 photo stories a day in total, the backlog grows without bound and originals are never downscaled. Separately, it is unverified whether pg_net's 5 s request timeout cuts the function short. | <ul><li>Claim in a loop until the batch comes back empty or a ~50 s budget runs out.</li><li>Schedule every 10 minutes.</li><li>Log processed, failed and remaining backlog per run.</li></ul> |
| 10 | The spec says story operations are monitored and alerted. None of that is built: no dead-letter alert, no queue-age > 30 min alert, no aggregate bytes/day metric. | Med | STORIES.md §4.4 ("raise an operational alert"), §4.5 ("Monitoring alerts when the oldest pending row is more than 30 minutes old"), §9 and §12 acceptance; no matching code in `supabase/` (`grep dead_letter\|alert\|metric`) | If image transformations are disabled or failing, every job dead-letters silently. A deletion drain failing on credentials leaves deleted stories' objects in the bucket with no signal. | <ul><li>Add a service-role `story_ops_health()` returning: dead-letter count, oldest pending archival `available_at`, oldest unstamped `media_deletion_queue` row per bucket, and `sum(metadata->>'size')` for `story-media`.</li><li>Run a cron that raises through the project's existing ops channel.</li><li>Otherwise, correct the spec text.</li></ul> |
| 11 | Pause and End make the whole story calendar vanish at once, for both partners. Stories are "class B" (`status = 'active'`). The partner's stories are never exportable. The confirm copy mentions only chat. | Med (owner ruling) | `20260938020000_stories_rls.sql:7-21` (`story_relationship_is_open` requires `status='active'`); Spec 3a plan R3-3 and its verbatim Pause/End copy | I pause our space to cool off and every memory disappears from the calendar. The copy said only "Chat becomes read-only". At an ending, my partner's stories of us are gone with no warning. | <ul><li>Either let story reads follow `relationship_chat_open_for` (read-only window, delete still author-only),</li><li>or change the Pause/End copy to say "Stories and the calendar close while paused/ended; download your own stories first".</li></ul> |
| 12 | Exported story videos, and images under 24 hours old, have no file extension. Keys end in `-media`. | Med | `20260938040000_stories_intent_rpc.sql:182-184`; `20261018120000_data_export.sql:18-22, 155, 412` | The downloaded ZIP holds `media/my_stories/3f9a…` files that phones and computers will not open as video. | In `export_file_name`'s story branch, derive the extension from `media_type` (`.mp4`, `.jpg`) instead of the key. |
| 13 | `occurred_on` depends on the session `TimeZone`: `(timestamptz + interval)::date`. It is correct only while the database runs in UTC. The contract test computes its expected value the same way, so it cannot catch this. | Low | `20260938120000:233`; `story_rpc_contracts.sql:540-541`; demo on `attune_spec3a`: under `SET timezone='Asia/Tokyo'` the same instant and offset give 2026-10-24 instead of 2026-10-23 | If the role or database time zone ever changes (role config, a self-hosted move), every story files a day off for part of the day. | Use `((v_now AT TIME ZONE 'UTC') + make_interval(mins => v_offset))::date`, or `SET timezone = 'UTC'` on the function. Test against a non-UTC session. |
| 14 | `fail_story_archival` has no state guard, and claim ignores `deleted_at`. A worker that fails after `delete_story_item` set the job to `done` puts it back to `pending`. It then fails 5 times and dead-letters, which is the noise the dead-letter fix meant to remove. An archive object uploaded in that window can be orphaned outside the purge prefix. | Low | `20260938090000` `fail_story_archival` (`WHERE story_item_id = p_story_id`), `claim_story_archival_batch` (no join to `story_items`) | An author deletes a photo story in the minute the hourly worker is processing it. The ops view shows a spurious dead letter. | <ul><li>Fail only `WHERE state = 'processing'`.</li><li>Have claim join `story_items` and skip `deleted_at IS NOT NULL`, marking those done.</li></ul> |
| 15 | The ring is not refreshed when its last story expires while the app is in the foreground. There is no timer at the next `expires_at`. | Low | `story_providers.dart` `storyRingSummaryProvider` (refetches on signal or resume only); `get_story_ring_summary` returns no expiry | The partner's ring stays lit after expiry. Tapping it opens the empty state. | Return `min(expires_at)` from the summary and schedule `ref.invalidateSelf()` at that instant. |
| 16 | A view that renders just after expiry is never recorded, because the check is `expires_at > now()` at mark time. | Low | STORIES.md §3.4; `story_reel_screen.dart:665-676` | My partner opens my story 5 s before it expires. It renders after expiry and I see "not seen", even though they watched it. | Allow a short grace window (e.g. `expires_at > now() - interval '10 minutes'`) only when the item was fetched from the active reel. |
| 17 | Spec drift. §2/§7 say "retention is forever unless the author deletes", but Spec 3b purges 12 months after archive. §8 says ex-partners keep a delete right, but there is no UI to reach it after an ending. §4.4, §9 and §12 claim monitoring that does not exist. | Low | STORIES.md §2, §7, §8, §12 versus `20261018110000:153-197` | People and copy rely on a promise the system no longer makes. | Update STORIES.md to describe the archive-purge lifecycle and the real ops state. |
| 18 | Test and harness gaps. <ul><li>`account_deletion_contracts.sql` never asserts that story media is queued on the `deleteUser` cascade.</li><li>`scripts/local_pg_grants.sql` does not replay the `story_places` revoke, so `story_places_contracts.sql` fails locally ("clients can write story_places directly"), because the local grants do not match production.</li><li>`story_read` and `story_security` contracts collide on `users_phone_key` in the scratch DB.</li></ul> | Low | Runs on `attune_spec3a`; `has_table_privilege('authenticated','public.story_places','INSERT') = t` locally | A real grant regression on `story_places` would not be caught locally. | <ul><li>Add a story assertion to the account-deletion contract.</li><li>Add a `story_places` grants block to the replay.</li><li>Randomize fixture phone numbers.</li></ul> |
| 19 | Story place pins are purged at `ended`, before the 30-day export window, so exported stories never carry their place. | Low | `20261018160000_sync_fixes.sql:16-19` versus `20261018120000:156` | The ending partner downloads their stories and every `place` is null. | Purge pins at archive, which is when the window closes, or document that places are excluded after an ending. |
| 20 | In a long-distance couple, a story is filed on the poster's civil date. The partner sees it on a date that differs from when they watched it, and the reel shows no time. | Low | STORIES.md §3.5; `story_reel_screen.dart` (no timestamp rendered) | A Tokyo partner posts Monday 08:00. The New York partner watched it Sunday evening and cannot find it under Sunday. | Show "Posted Mon 08:00 (their time)" in the day reel through `MyDateFormat`. Optionally show a small cross-date hint in the day sheet. |

Counts: Critical 0, High 2, Medium 10, Low 8.

## 4. Algorithm Quality Review Checklist v3.1, for this area

| ID | Result | Evidence |
|---|---|---|
| 1.1 / 2.18 Idempotency | Pass | `(author_id, client_story_id)` finalize plus race fix; `delete_story_item` idempotent and re-arming; deterministic archive key with conditional swap. |
| 1.4 / 1.5 AuthZ / AuthN | Pass | Every story read gates on `story_relationship_is_open(…, auth.uid())`; storage SELECT policy needs a live row; delete is author-only; worker uses `requireServiceRole`. |
| 1.6 / 2.16 Concurrency | Pass with a Low | Row lock in delete and complete; `FOR UPDATE SKIP LOCKED` claim; 5-minute lease. Finding 14 is a state-guard gap. |
| 1.10 Compensation | Pass | Zero-row swap queues the new key; tombstone and queue in one transaction; hard-delete trigger. |
| 1.11 Privacy / retention | Partial | Retention is defined (forever while active; 12-month purge after archive). Spec text is stale (finding 17). Places purged at end (finding 19). |
| 1.12 Cost budget | Fail | Video kept permanently, no aggregate metric, archival throughput cap (findings 9, 10). |
| 2.5 Resource limits | Pass | `p_limit` capped at 50; day counts bounded to a range; export per-part budget. |
| 2.14 Memory growth | Partial | `media_deletion_queue` keeps stamped rows forever (audit by design); thumbnail URLs never cached (finding 6). |
| 3.1 Pagination | Pass with Medium | Keyset everywhere, but the day sheet's count and rings use page 1 only (finding 4). |
| 3.2 N+1 | Fail | One signing call per calendar cell (finding 6). |
| 3.3 Indexes | Pass with note | `idx_story_calendar` and `idx_story_media_jobs_claim` exist. The video close-out UPDATE in claim has no partial index (hourly scan of `story_items`). |
| 3.7 Backpressure | Fail | Fixed 20 per hour archival (finding 9). |
| 3.9 / 3.10 Retry | Pass | Outbox backoff with jitter; archival 5 attempts then dead letter; deletion drain retries unstamped rows. |
| 4.6–4.10 Metrics / alerts | Fail | None implemented despite the spec (finding 10). |
| 4.14 Dead letter | Partial | The state exists. There is no view, alert or replay. |
| 5.1 Actionable errors | Fail | Calendar reads fail silently (finding 5). |
| 5.2 / 5.3 Latency / progressive | Partial | Grid avatars wait on per-cell signing (finding 6). |
| 6.1 Edge cases (time zone) | Partial | ±840 tested. Session time zone and capture-versus-finalize midnight are not tested (findings 3, 13). |
| 6.3 Concurrency tests | Pass | `story_rpc_contracts` and `story_maintenance_contracts` race and crash cases; `scripts/concurrency/story_races.sh`. |
| 6.4 Negative tests | Pass | The expired item is absent from the author reel; delete is author-only; non-delete is pinned. |
| 6.13 Docs | Partial | Thorough, but drifted (finding 17). |
| 2.19–2.23 Financial | N/A | |
| 7.6 CSRF / CORS | N/A | Native-mobile only. |

## 5. Standards gap (Snapchat / Instagram / WhatsApp, two-person relevant only)

- **Delete from your own story viewer.** All three apps offer it in the viewer itself (finding 2).
- **Save a story or memory to the phone.** Snapchat and Instagram both let you save a story to your device. Attune has no save or share in the reel (`share_plus` is a dependency but unused here), and it deletes the capture's local file after posting. The server copy is the only copy, so finding 1 hits harder.
- **Full-quality memories.** Snapchat Memories keep the original. Attune permanently downsizes images to quality 80 at the 24-hour mark, with no opt-out.
- **Resurfacing ("On this day", Flashbacks, Memories).** Together's `list_together_on_this_day` and the "Our story" archive (`20261014150000_together_story.sql`) read only `timeline_events` and `couple_events`, never `story_items`. The feature's main memory source never resurfaces.
  - Fix: add a `'story'` `item_kind` with `thumbnail_key`, opening `StoryReelScreen.forDay`.
- **Archive browsing.** Instagram's Story Archive is a scrollable thumbnail grid. Attune has only the month grid's 14 px avatars and a per-day sheet. There is no list or grid of all memories.
- **Time label in the viewer.** Snapchat, Instagram and WhatsApp show "3h" or the date. The Attune reel shows no posting time, so a memory viewed months later has no date or time on it (finding 20).
- **Per-person playback from a day.** Tapping a person plays that person's stories (finding 4).
- **Reconciled chapters.** If the same two people pair again, the earlier chapter's memories stay under the old relationship id and are purged 12 months after archive. That is a product decision, but no IG or Snapchat user loses their archive by re-following someone.
