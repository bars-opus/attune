# 05 — Server security and privacy (reviewer 5 of 6)

Scope: every story migration (latest definition of each function/policy), storage bucket and policies, realtime publication, replies, story places, deletion/purge/account deletion, export; client sign-out, quick exit, PIN lock, app-switcher cover, device caches and backups, screenshots. Method: read the migrations, queried the live catalog of the scratch DB `attune_spec3a`, ran every story contract file, and ran my own BEGIN…ROLLBACK probes as partner A, partner B, a third user C (a member of a different active couple) and anon. I also ran one scratch widget test against the real `AppPrivacyCover`. Nothing in the repo was changed.

## 1. Verdict

The server boundary is strong. I found no way for anyone outside the couple to read, list, sign, forge, reply to or change a story, its media, its place or its view state. A third user gets zero rows or the same generic `UNAVAILABLE`/`FORBIDDEN` from every table, RPC and storage path, for a real id and a made-up one alike. Clients cannot write anything directly. The private `viewed_at` is unreachable. While seen-receipts are off, the author learns nothing about views. Deletion, account deletion and relationship purge all queue the media, thumbnail and archive key through `media_deletion_queue`. I found **no Critical issue**.

The weak points are on the client and in how the layers interact:
- **High:** the global privacy cover tears down the whole Navigator every time the app goes inactive. On iOS, any Control Centre pull, incoming call, Face ID prompt or permission prompt therefore closes the story camera, the reel and the calendar reel. A capture that is still being prepared is dropped without any message.
- **Medium:** the story outbox (pending captures, with plaintext media in tmp) survives sign-out and is not excluded from backups, unlike chat's equivalent.
- **Medium:** once a relationship ends, an author keeps the right to delete their stories but has no way to list them.
- The rest are Low: a membership oracle in a helper granted to clients, no size/MIME limits on the bucket, device thumbnail-cache residue, and local test-harness drift.

## 2. What is solid (with evidence)

- **RLS everywhere, read-only to clients.** Catalog: RLS is on for `story_items`, `story_views`, `story_change_signals`, `story_media_upload_intents`, `story_media_processing_outbox` and `story_places`.
  - `story_items`: `authenticated` has column SELECT only, on an allowlist that excludes `has_been_viewed` and `seen_shown` (`20261017140100_story_items_column_grants.sql:10-16`; verified in `information_schema.column_privileges`).
  - `story_views`, the intents table and the processing outbox: no grant at all (`20260938100000_stories_table_grants.sql:46-53`).
  - Probe as B: UPDATE and DELETE on `story_items` → `insufficient_privilege`. SELECT on `story_views.viewed_at` and on `story_items.has_been_viewed` → denied.
- **SECURITY DEFINER hygiene.**
  - Live query: 0 SECURITY DEFINER functions in `public` without a pinned `search_path`.
  - 0 story definer bodies reference an unqualified table (regex over `pg_get_functiondef`). `pg_temp` is not on the path, but every relation is schema-qualified, so it cannot be shadowed.
  - Internal helpers (`bump_story_signal`, `queue_story_media_deletion`, `create_story_item_core`, `story_place_parse`, `story_archive_key`, `story_intent_*`) have no `authenticated`/`anon` EXECUTE (catalog ACLs; `20260938110000_stories_helper_grants.sql`).
  - The 8-argument finalize overload is gone (`20261017100000_story_places.sql:55-58`).
- **No existence oracles in the RPCs.** Probe as C, real id vs random uuid:
  - `mark_story_viewed` and `delete_story_item` return the identical `UNAVAILABLE` payload.
  - `create_story_upload_intent` returns the identical `FORBIDDEN`.
  - `clear_story_place` returns void, and `clear_my_story_places` returns 0.
  - A story reply naming a foreign story id and one naming a nonexistent id both raise the same `Story unavailable` (`20260939010000_story_replies.sql:81-102`).
- **Relationship state.** `story_relationship_is_open` requires `status='active' AND chat_archived_at IS NULL` (`20260938020000_stories_rls.sql:17-23`); stories are "Class B (active-only)" per the Spec 3 map.
  - Probe: while paused, B sees 0 story rows and 0 storage objects. Ended and archived are covered by `story_security_contracts`.
  - Story places now survive a pause and are purged only at end/archive (`20261018160000_sync_fixes.sql:9-21`). Probe: after the pause, 1 place was kept; after the end, 0 places.
- **Storage.** The bucket is private and kept private on replay (`20260938030000_stories_storage.sql:31-33`).
  - The latest SELECT policy (`20260940120000_story_storage_policy_isolation.sql:45-60`) requires a live (`deleted_at IS NULL`) story in an open relationship, evaluated under the caller's own RLS, or the caller's own unconsumed, unexpired intent.
  - INSERT requires the caller's own active intent. There is no UPDATE or DELETE policy, so a finalized object can never be overwritten.
  - Probe: C sees 0 `story-media` objects and B sees 2. `list()` is bounded by the same policy, so listing reveals nothing that RLS doesn't already show.
  - Signed URLs are 600 s, minted on every request and never cached (`story_read_repository.dart:379, 547-551`).
- **Finalize cannot be forged.** Keys, author, media type, `occurred_on` and expiry are all derived server-side. Both intents are locked `FOR UPDATE` and must match requester, relationship and kind. Size and MIME come from server-written `storage.objects.metadata`. The idempotent retry race is fixed (`20260938120000_stories_finalize_race_fix.sql:89-269`).
- **View-time privacy (§3.4).**
  - The list RPCs mask the author-side seen flag unless seen-receipts are effective (`20261017140000_story_seen_state.sql:44-48, 77-81`).
  - `mark_story_viewed` bumps the realtime signal only while receipts are on (`:181-183`).
  - `story_items` is not in `supabase_realtime`; only `story_change_signals (relationship_id, version, updated_at)` is (`pg_publication_tables`), under the member-only policy. Probe: with receipts off, B viewed → A saw `has_been_viewed=f` and the signal version stayed at 1.
  - Expired stories opened from the calendar record no view (probe: `UNAVAILABLE`).
- **Replies cannot point at another couple's story.** The BEFORE INSERT trigger checks the same relationship, an active member and a non-deleted story. `quoted_text` is server-normalized. `messages` has no client UPDATE privilege or policy, so `story_item_id` cannot be re-pointed after insert (catalog: no UPDATE column privileges on `messages` for `authenticated`).
- **Places are opt-in and per-post.** The client sends `p_place` only when the pin pill is on (`story_pin_controller.dart:71-78`). It never prompts unprompted (`:96-101`) and warns once near home (`:155-163`). The server stores a place only on a fresh insert behind `couple_map_enabled` (`20261017100000_story_places.sql:78-91`), drops it on soft delete (`:107-119`), and only the author can clear it (`:123-145`).
- **Deletion really removes media.**
  - `delete_story_item` stamps the row and, in the same transaction, re-arms media, thumbnail and archive key (archive delayed by the URL TTL) and closes the outbox job (`20260938140000_stories_archival_dead_letter_fix.sql:111-158`). Probe after the end: 3 queue rows.
  - A hard delete fires `stories_enqueue_media_before_hard_delete` (`20260938070000_stories_delete_rpc.sql:307-329`).
  - Account deletion probe: `prepare_account_deletion` followed by `DELETE auth.users` → 0 story rows, all 3 keys queued, relationship ended with `user_a = null`.
  - The relationship purge also sweeps the `story-media/<rel>/` prefix and orphaned intents (`20261018110000_chapters_deletion.sql:126-147`).
  - Nothing deletes `storage.objects` directly; the Storage API drains the queue.
- **Export** includes only the person's own non-deleted stories and their places, never the partner's and never view timestamps (`20261018120000_data_export.sql:151-160, 412-414`).
- **anon has nothing.** Probe: `story_items`, the list RPCs, `mark_story_viewed`, `story_relationship_is_open` and `story_change_signals` are all `insufficient_privilege`.
- **Client.**
  - The PIN gate replaces the entire tree, quick exit routes to the decoy, and the app-switcher cover hides content (`app_shell.dart:20-43`).
  - Captures live in `getTemporaryDirectory()`, which is not backed up (`story_camera_screen.dart:351-360`).
  - The outbox payload is AES-GCM with a this-device-only Keychain key (`chat_cache_cipher.dart:47`).
  - Sign-out empties `DefaultCacheManager` and the in-memory ImageCache, which hold the ring thumbnails (`auth_provider.dart:189-207`).
  - Story read providers are `autoDispose` and every read is re-authorized server-side.

### Contract runs on `attune_spec3a`

| File | Result | Note |
|---|---|---|
| story_maintenance_contracts | PASS | |
| story_reply_contracts | PASS | |
| story_rpc_contracts | PASS | |
| story_schema_contracts | PASS | |
| story_seen_state_contracts | PASS | |
| story_storage_policy_isolation_contracts | PASS | |
| together_story_contracts | PASS | Not story media; this is the Together "Our story" layer, with no `story_items` reference |
| story_read_contracts | FAIL (fixture) → PASS | `:33 users_phone_key (+15559990001)`: the phone already belongs to `b2000000-…000a` on this DB. A scratch copy with substituted phones passes |
| story_security_contracts | FAIL (fixture) → PASS | Same collision at `:21`; the substituted copy passes |
| story_places_contracts | FAIL (harness drift) → PASS | `:68 CONTRACT VIOLATED: clients can write story_places directly`. Locally `authenticated=arwd, anon=r` because `scripts/local_pg_grants.sql` never replays the story_places REVOKE. With the production grants replayed inside the transaction, it passes. RLS still blocks the write (probe: "new row violates row-level security policy") |
| account_deletion_contracts, relationship_purge_contracts | PASS | Account deletion has no story assertion; my probe covered it (above) |

## 3. Findings

| # | Issue | Sev | Evidence (file:line) | Scenario | Fix design |
|---|---|---|---|---|---|
| 1 | **The privacy cover destroys every pushed story screen on any iOS inactive transition** | High | `lib/core/services/app_privacy_cover.dart:63-68` returns a `ColoredBox` *instead of* the child, which unmounts the Router and Navigator. The story camera and reel are pageless `MaterialPageRoute`s (`conversations_screen.dart:237, 257`), as is the calendar reel (`story_day_row.dart:54`, `calendar_day_sheet.dart:208`). The camera drops an in-flight capture at `story_camera_screen.dart:204` (`if (!mounted) return;`). Reproduced with a scratch widget test (real `AppPrivacyCover` + GoRouter + pushed route): after inactive → resumed, the pushed route was gone (`REEL after resume: 0`). The reel's own lifecycle pause/resume logic (`story_reel_screen.dart:342-344`, spec §5.2 "CRITICAL bug … fixed") is therefore dead in the real app; it was only ever tested without the cover | (a) Person is watching the partner's reel → pulls down Control Centre, gets a call, or Face ID re-prompts → returns to the Conversations screen, reel closed, position lost. (b) First use of the story camera → iOS camera, mic or location prompt (the pin pill) makes the app inactive → the camera closes behind the prompt. (c) Person takes a photo and swipes Notification Center while it prepares → the screen is disposed after `confirmSend` → the story is never queued and no message is shown. Android: Needs verification (window-focus loss also reports `inactive` on recent Flutter) | Keep the child mounted and stop painting it: `Stack(children: [Offstage(offstage: _obscured, child: TickerMode(enabled: !_obscured, child: ExcludeSemantics(excluding: _obscured, child: widget.child))), if (_obscured) cover])`. Offstage does not paint, so the OS snapshot still shows only the cover, and the existing "finder cannot see secret" test stays valid with `skipOffstage`. Add a regression test: a pushed route survives inactive → resumed. **Shared core widget: re-run the app_privacy_cover, understand_sheet, assistant_notice and quick-exit tests.** Separately, make `_prepareAndEnqueue` enqueue even if unmounted (the record does not need the widget) |
| 2 | **Story outbox and capture files survive sign-out, quick exit and backups** | Medium | Sign-out wipes chat's queue, staging, media and image caches but has no story outbox step (`lib/features/auth/providers/auth_provider.dart:157-235`). `StoryOutboxStore.clearAll()` has no caller (`story_outbox_store.dart:174`). The outbox DB lives in App Support (`story_outbox_backend_io.dart:62`) and is never passed to `BackupExclusion.exclude` (chat does this at `chat_cache_backend_io.dart:183`). It is also absent from `android/app/src/main/res/xml/backup_rules.xml` and `data_extraction_rules.xml`. Captured JPEG/MP4 files sit in plaintext in tmp until posted or discarded | Person queues a story offline, then signs out, or quick-exits without a PIN (`safety_lock_controller.dart:191-194` → signed out) believing they have left. The photo stays on disk. When the account signs in again on that phone, the outbox resumes and posts it to the partner without asking. The encrypted outbox rows (plus plaintext `user_id`/`client_story_id`/`created_at`) go into iCloud and Android backups | In `signOut()`'s `wipeQueue`, add `storyOutboxStore.readAll`/`clearAll` and delete each record's `localMediaPath`/`localThumbnailPath`, best-effort and bounded like chat's staging wipe, and invalidate `storyOutboxProvider`. Call `BackupExclusion.exclude` on `attune_story_outbox.sqlite` (+`-wal`/`-shm`). Add the same three files to both Android XMLs. Consider a "post queued stories?" prompt after a quick-exit return |
| 3 | **After a relationship ends, the author cannot find their own stories to delete them** | Medium | `delete_story_item` deliberately skips the membership check (`20260938140000_stories_archival_dead_letter_fix.sql:96-105`), but every reader requires an *active* relationship (`20260938020000_stories_rls.sql:35-40`; list RPCs in `20261017140000_story_seen_state.sql:54, 87`). Probe: after the end, A sees 0 of their own rows while `delete_story_item(id)` succeeds. There is no client path. Media is retained until `purge_archived_relationships` (12 months after archive; `20261018110000_chapters_deletion.sql:165-182`) | After a breakup a person wants their intimate story photos gone. Spec §3.3 says "an author never loses the right to remove their own retained media", but there is no list and no button. Their only options are to wait 12+ months or delete the whole account. The ex cannot see the photos, so this is retention, not exposure | Add an author-only definer RPC `delete_my_story_items(p_relationship_id)` (author = `auth.uid()`, any status, generic result, same three-key enqueue per row via a shared helper), plus a "Delete my stories from this chapter" action on the ended-relationship / chapter screen. Alternatively, offer it in the ending sheet (`RelationshipLifecycleWatcher`) |
| 4 | **`story_relationship_is_open(rel, user)` is a membership/status oracle** | Low | Granted to `authenticated` with a caller-chosen `p_user` (`20260938020000_stories_rls.sql:7-29`; kept by `20260938110000_stories_helper_grants.sql:15-18`), so it is exposed through PostgREST `/rpc`. Probe as C: `story_relationship_is_open(<A·B rel>, <A>)` → `t` | Anyone who knows a relationship uuid and a user uuid (for example an ex holding the old relationship id and their ex's user id) can learn whether that pairing is currently active, paused or ended. That breaks the stated "no existence oracle" contract. It needs two uuids, hence Low | Add `story_relationship_is_open_for_me(p_relationship_id)`, which uses `auth.uid()` internally, and point the four policies at it (`story_items`, `story_change_signals`, `story_places`, `story-media` SELECT). Revoke the 2-argument version from `authenticated`; definer callers keep it |
| 5 | **The bucket has no size or MIME ceiling; limits are checked only at finalize** | Low | The bucket is inserted with only `(id, name, public)` (`20260938030000_stories_storage.sql:31-33`). The INSERT policy checks only the intent (`20260940120000…:37-43`). Size and MIME are enforced only in `create_story_item_core` (`20260938120000…:187-217`) | A modified client holds 20 open intents and uploads up to the project-wide cap to each, refreshing every 15 minutes (120 calls/h). That is GBs of junk per hour per account until the hourly sweep plus queue drain removes it. Cost only, not privacy | In the bucket upsert, set `file_size_limit = 26214400` and `allowed_mime_types = '{image/jpeg,video/mp4}'` (ON CONFLICT DO UPDATE, like `public`). Keep the per-intent check for the 5 MB / 800 KB tiers |
| 6 | **Ring thumbnails persist in the device disk cache after a story is deleted or the relationship ends** | Low | `CachedNetworkImage(imageUrl: url)` with no `cacheKey` (`lib/features/stories/presentation/widgets/story_ring.dart:316`) stores every freshly signed URL as a new `DefaultCacheManager` entry. Nothing evicts on delete or relationship close; only sign-out empties it | Partner deletes a story, or the couple ends → the thumbnail bytes stay in Caches until stale eviction. They cannot be reached in the UI, but on-device residue contradicts "deleting removes it". The cache also grows by one entry per signed URL minted (every refresh) | Pass `cacheKey: thumbnailKey` (as couple map does, `couple_map_tab.dart:151`). On a `story_change_signals` bump, `removeFile` keys that are no longer listed. On relationship close (`RelationshipLifecycleWatcher`), clear story keys, or simply empty the cache |
| 7 | **A quick-exit triple-tap inside the reel also drives the reel** | Low (Needs verification on device) | The quick-exit band is a translucent `Listener` over the top 56 pt (`triple_tap_detector.dart:58-84`). The reel's single `GestureDetector` covers the full screen (`story_reel_screen.dart:1552-1579`) | Person triple-taps to quick-exit while viewing → the same taps advance up to three items before the decoy appears. Each item that renders is marked viewed and, with receipts on, shows as seen to the author | Have the reel ignore taps whose `localPosition.dy` falls inside `MediaQuery.paddingOf(context).top + kToolbarHeight`, or defer `markViewed` by about 300 ms and cancel it if quick exit fires |
| 8 | **Local harness drift: story_places grants are not replayed** | Low | `scripts/local_pg_grants.sql:42-59, 141-143` replays stories, replies and story_items column grants, but not `20261017100000_story_places.sql:19-20`. Catalog: `story_places authenticated=arwd, anon=r` | `story_places_contracts.sql:68` fails on every local rebuild, so the contract cannot catch a real regression. Production is unaffected (the migration REVOKE stands) | Move the story_places REVOKE/GRANT into `2026101710xxxx_story_places_grants.sql` and `\i` it in `local_pg_grants.sql` after the blanket grant |
| 9 | **Two security contracts collide on fixture phones** | Low | `story_security_contracts.sql:17-21` and `story_read_contracts.sql:~29-33` insert `+15559990001…3` with `ON CONFLICT (id)`. On `attune_spec3a` those phones already belong to `b2000000-…000a/b/c/d` | Both core security contracts abort before any assertion runs, so a reviewer sees "FAIL" and has to work out whether it is real | Use per-file phone ranges, or `ON CONFLICT DO NOTHING` without a target. Add a CI check that each contract file uses unique fixture phones |

Counts: Critical 0 · High 1 · Medium 2 · Low 6.

## 4. Checklist v3.1 notes (this area)

| ID | Status | Evidence |
|---|---|---|
| 1.4 Authorization at every access point | PASS | Policy on every table plus the storage SELECT/INSERT. Definer RPCs re-check membership or authorship (`mark_story_viewed :158-165`, finalize `:104`, delete `:101-105`). The reply trigger re-checks the story's own relationship |
| 1.5 Authentication | PASS | Every RPC derives the actor from `auth.uid()` and returns `UNAUTHORIZED` on null. anon has no EXECUTE (probe) |
| 1.6 Concurrency | PASS | Intents and story rows locked `FOR UPDATE`; finalize race fixed; `SKIP LOCKED` in the sweeps |
| 1.10 Compensation on partial failure | PASS | The tombstone and the three-key enqueue commit in one transaction. The hard-delete trigger and relationship purge queue storage before deleting rows |
| 1.11 Privacy impact and retention | PARTIAL | `viewed_at` is private, places are opt-in, export covers own data only. Gaps: an author cannot delete after an ending (#3); on-device outbox and cache residue (#2, #6) |
| 2.1 Input sanitization | PASS | Kind/type/MIME allowlists, clamped offset, `story_place_parse` drops malformed input, `p_limit` capped at 50/500 |
| 2.2 Parameterized queries | PASS | Static SQL only; storage keys are built from uuid/hex, never from client strings |
| 2.4 Error messages don't leak | PASS (one Low) | Generic `UNAVAILABLE`/`FORBIDDEN` and an identical trigger message for real vs fake ids. The exception is the helper oracle (#4) |
| 2.5 Resource limits | PARTIAL | 20 open / 120 per hour intent caps, row caps, per-intent byte ceilings at finalize. No bucket-level ceiling (#5) |
| 2.10 / 2.13 Resource cleanup on cancel | FAIL (client) | A capture is dropped when the camera is unmounted mid-prepare (#1c) |
| 2.14 Bounded caches | PARTIAL | Signed URLs are not cached, but disk-cache entries are keyed per signed URL (#6) |
| 2.18 Idempotent mutations | PASS | `(author_id, client_story_id)`; idempotent delete and view |
| 5.5 No internal info in UI | PASS | House error shape; no raw database messages |
| 6.4 Negative tests | PASS (with harness caveats) | The contracts are written as attacks; three files fail locally only for fixture or grant-replay reasons (#8, #9) |
| 7.4 Least privilege | PASS (one Low) | Service-role-only maintenance RPCs, no client grants on private tables, helpers revoked. `story_relationship_is_open` is over-granted (#4) |
| 7.5 TLS | N/A here | Supabase-managed |
| 7.6 CSRF/CORS | N/A | Native mobile only |
| 2.7-2.9, 7.1-7.3, 7.7 | Not assessed | Outside this area (no secrets appear in the story code read) |

## 5. Standards gap (two-person private story)

- **Interruptions don't lose your place.** Snapchat, Instagram and WhatsApp keep the viewer open across Control Centre, calls and permission prompts, and pick up where you left off. Attune closes it (#1). This is the most noticeable gap.
- **Screenshot awareness.** Snapchat tells the poster when a story is screenshotted; WhatsApp blocks screenshots of view-once media; Instagram does neither for stories. Attune already has `ScreenshotDetectionService` and `send_screenshot_notice` for chat view-once (`ephemeral_video_viewer_screen.dart:69`), but the reel has nothing. Because Attune stories persist in the calendar, a notice matters less than in Snapchat. A "they took a screenshot" mark on the author's own reel (behind the seen-receipts setting) would still meet the expectation people bring from Snapchat. Product decision.
- **Delete-everything control.** Snapchat and Instagram let you delete any of your past stories and memories at any time. Attune loses that path once a relationship ends (#3).
- **Clean sign-out.** All three apps drop unsent drafts and uploads tied to an account on logout. Attune keeps queued story captures across sign-out (#2).
- No gap on audience control, view privacy or link sharing. With an audience of exactly one, Attune's model (private bucket, short-lived signed URLs, opt-in exact location, seen-state behind a mutual setting) is stricter than all three.
