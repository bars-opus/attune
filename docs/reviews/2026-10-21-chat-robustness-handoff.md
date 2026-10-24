# Chat robustness program: handoff (2026-10-21)

All 43 issues from [2026-10-18-chat-robustness-review.md](2026-10-18-chat-robustness-review.md) are fixed across five plans (1a delivery/sync, 1b push/security, 2 media, 3 chat screen, 4 sounds/streaks). Each task was built test-first, reviewed, and fixed until the review was clean. Each plan then had a whole-plan review (Fable) and one fix pass.

- **Tests:** full suite **5028/5028 green twice in a row**. All of this program's SQL contracts pass on `attune_spec3a`, with mutation checks tripping.
- **Nothing is committed.** Everything is in main's working tree, on top of your own uncommitted work.

## 1. Deploy (owner), in this order

Use `supabase db push` for every migration. CLI 2.75 does not wrap a file in a transaction, so `20261019100100` (which needs one for its `LOCK TABLE`) now opens and commits its own.

### Step 0: pre-flight on the live database (read-only)
Run everything in step 0 of `.superpowers/sdd/2026-10-18-chat-w1b-push-security/final-review.md` § "Corrected owner deploy list":
- `auth.sessions.not_after` exists;
- `app_setting` URL and key are present;
- diff the live definitions of the four functions the migrations restate;
- dedupe row count;
- legacy push-token count.

Then the streak pre-check (it must return 0; otherwise run the one-off fix below first):
```sql
SELECT count(*) FROM public.messages m
WHERE EXISTS (SELECT 1 FROM public.streak_clips c WHERE c.message_id = m.id)
  AND m.media_type IS DISTINCT FROM 'streak';
-- if non-zero: UPDATE public.messages m SET media_type = 'streak'
--   WHERE EXISTS (SELECT 1 FROM public.streak_clips c WHERE c.message_id = m.id)
--     AND m.media_type IS DISTINCT FROM 'streak';
```

### Step 1: Xcode, Apple and OneSignal (one-time)
- In Xcode, turn on Push Notifications and Background Modes → Remote notifications.
- Upload the APNs .p8 key to OneSignal.
- Confirm the FCM credentials.
- In OneSignal:
  - leave **Identity Verification OFF**;
  - set up **no in-app push-prompt message**;
  - **never target a campaign by `external_id`**.
- Commit `project.pbxproj` together with the iOS files.

### Step 2: migrations (all `20261019*`, 26 files), before the new app build reaches a phone

**Plan 1a**
- `20261019100000` + `100010`. Apply 100000 with no chat open: its backfill sends one realtime UPDATE per row.
- `100100` + `100110`. Apply after the step-0 function diff.

**Plan 1b**
- `110000`, `110050`, `110200`, `110210`, `110220`, `110225`, `110300`, `110310`, `110320`, `110330`, `110335`, `110340`.

**Plan 2**
- `120000` (delete_message queues media; strips the legacy `message-media/` prefix), `120050`, `120100`, `120110`, `120115`, `120120` (intent cleanup via the deletion queue; the old body threw on hosted every hour).

**Plan 3**
- None.

**Plan 4**
- `140000` + `140010`: streak read RPC and replay-window gate.
- `140100` + `140110`: view-once hardening.
  - `first_read_at` anchor and storage-policy gate;
  - sweep cron every 10 minutes;
  - idempotent per-open spend;
  - a 10-minute media-deletion grace.
  - `140100` builds a partial index on `messages` without `CONCURRENTLY`, so push it at a quiet hour.

After pushing, run the verify queries:
- for 1a and 1b: the same final-review.md, steps 2 and 5;
- for streaks: the "hosted verify query" in `.superpowers/sdd/2026-10-18-chat-w4-sound-streaks/task-5b-report.md`. Expect `f|t|f` and the extra checks listed there, including `has_column_privilege('authenticated','public.messages','first_read_at','SELECT') = f`.

### Step 3: build and install the new app on both phones, and sign in
- **⚠️ Production flag:** after `140100`, app builds from before plan 4 cannot play streaks. They show "Couldn't load this streak" and nothing is spent. For production, ship these migrations together with a forced update. On dev (your two test accounts only) this costs nothing.
- Confirm one active `push_tokens` row per phone.

### Step 4: edge functions
```
supabase functions deploy process-chat-notification-outbox process-scheduled-notifications send-notification accept-invite
```
These share `_shared/push_queue.ts`. Deploy them only after step 3 is done on the test phones: from this moment, only registered devices receive pushes.
Note (2026-10-25): the forum functions (`activate-topics`, `forum-quiet-check`) were retired by Spec 3 and are no longer deployed, so they are not in this command. See `docs/superpowers/plans/2026-10-25-spec3-forum-removal-w1-w2.md`, Owner deploy checklist.

### Step 5: prod sanity
Use final-review.md step 5:
- cron jobs exist;
- outbox `done`;
- `sent`, not stuck in `processing`;
- the wake reports `woken`.

### After deploy: the dev wipe (still pending from earlier)
Run `scripts/wipe_all_chat_dev.sql` STEP 2 and STEP 3, then sign out and back in on both phones.

## 2. Two-phone test checklist

Run the original scripted conversation, plus these. Each item names the fix it checks.

**Delivery and sync**
- **Offline send:** turn on airplane mode, send 3 messages, kill the app, reopen it online. All 3 send, in order, without any tap.
- **Edits, deletes and reactions on old messages:** do this on a message more than 50 back. It appears on the other phone, and so does unpin/un-react.
- **Server-deleted rows:** none linger as ghosts.
- **Messages read while away:** a message received while you're in a game or the media screen is not marked Read until you return.
- **Draft restore:** restoring a draft doesn't show "typing…" to your partner.

**Push**
- **Speed:** a push arrives in 1–3 s, not up to 60 s.
- **Android 13+ prompt:** appears once, and never over the PIN screen.
- **Relationship Updates off:** chat pushes still arrive.
- **Sign out other devices:** C stops receiving at once.
- **Screenshot of a view-once video:** the notice appears centred on both phones and can't be edited or deleted.
- **Offline sign-out:** sign out offline, then open the app online. The old push stops.

**Media**
- **Full-resolution photos:** iPhone HEIC photos send as JPEG.
- **Uploads:** progress ring, cancel, retry, and cancel during automatic retries.
- **Stalled upload:** times out and becomes retryable.
- **Voice note:**
  - keeps playing while you scroll;
  - replays offline;
  - stops when deleted or when you leave the chat;
  - Android: Spotify resumes after the note *ends*. Pausing mid-note keeps Spotify paused until the note stops; that's a plugin limit, logged as a follow-up.
- **Video:** downloads with a ring and replays offline.
- **Delete for everyone:** the storage objects go, and the partner's cached copy goes too.
- **Sign-out:** clears queued photos, voice/video cache and the image cache. Avatars re-download.

**Chat screen**
- **"Go to message":** works from reply quote, pinned, starred, search and media. It lands and flashes even when the target isn't loaded, including a deleted pinned message. Touching the list cancels it.
- **"Edited":** the label shows, and long-press → Edit history works.
- **Bottom overlays:** typing, reply strip and staged game never cover the newest message. At the bottom the list glides; scrolled up, nothing moves.
- **Arrivals while scrolled up:** the row you're reading doesn't move.
- **Pill and divider:** the pill shows "N new", and only partner messages count; game moves don't. "N unread messages" appears on a push open too.
- **Ticks:** shown on the newest own message and own group ends. "Delivered" arrives on push receipt when the partner app is open or the push is tapped. A fully closed app needs a native extension, which is a follow-up.
- **Links:** tappable; Copy link works; Wikipedia-style `(…)` URLs work; long URLs wrap.
- **Over-limit paste:** a paste over 10,000 characters keeps your draft whole and trims only the paste. The edit dialog is guarded the same way.
- **Performance and looks:**
  - low-end Android: no typing jank while a long draft grows (profiling item);
  - the flash ring may overlap a grouped neighbour by up to 2.5 px — check it looks fine;
  - toggling reduce motion keeps composer focus.

**Sounds, streaks and games**
- **Android chirps:** music keeps playing.
- **iOS chirps:** respect the silent switch, including after a voice note.
- **Streak loading:** tap or back out while it loads → no view spent. A stalled video → "Couldn't load", no audio after closing.
- **Streak window:** a streak opened and then left 30+ min reads "Opened" and refuses to play. A streak fetched but never seen (open it on airplane mode, back out, wait 40 min) reads "Expired" on both phones.
- **Cold start offline:** with an unopened streak in history, both rows read "Play", not "Expired".
- **Failed streak upload:** shows "Not sent" with one Retry, and the screen reader announces it once.
- **Double-tap a streak:** one viewer, one view.
- **Game moves:** a partner move settles in with one light tap and no chirp. A partner invite chirps and taps. My own moves are silent.
- **Reduce motion:** the typing bubble and the record disc appear without animation.
- **Emoji picker:** picking from the full picker gives one tap.

## 3. Owner decisions and flags
- **Forced update for streaks (production):** see step 3.
- **Phone numbers and emails** aren't tappable yet (only `http/https`). WhatsApp makes them tappable; this would be a follow-up with a `tel:`/`mailto:` allow-list.
- **Preview labels for pause/appreciation messages:** not added. Want them?
- **`streak_view_spends`** isn't in the Spec 3c "Download my data" export. Your call.
- **True background "delivered":** needs an iOS Notification Service Extension and an Android NotificationServiceExtension.
- **Android voice pause holding focus:** a plugin limit, follow-up.
- **i18n:** chat is hard-coded English. New strings are whole sentences, ready for the app-wide l10n gate; the list is in `.superpowers/sdd/2026-10-18-chat-w3-chat-screen/preflight.md` §4 plus each task report's "new strings".

## 4. Follow-ups outside this program (found along the way)
- Local SQL harness hygiene (fixture collisions or leftover state). These fail on `attune_spec3a` and are unrelated to chat:
  - `ai_*` contracts;
  - `story_places`, `story_read`, `story_security`;
  - `couple_map_presence` ("clients can write presence directly");
  - `together_events` ("couple_events readable directly");
  - `reminder_delivery` (grants drift);
  - `game_message_contracts` (leftover phone fixture).
- Deno type-check fails in `_shared/ai_session_context.test.ts` (`utcOffsetMinutes` not in `ApprovalDigestInput`).
- 9 analyzer warnings in the untouched `chat_couples_locked_screen.dart`, plus 2 in `circular_documentation_container.dart` and `profile_avatar.dart`.
- The This or That reminder push never sends (games session).
- `planning_recent_test` fails between 00:00 and 03:00 (midnight boundary).
- The plan 2 note: a staged file isn't promoted if the chat closes mid-settlement (falls back to the signed URL).

## 5. Every ruling made on your behalf

Verbatim from the five ledgers, in order. Each gives what was decided, why, and what it costs if wrong. Deferred minors follow each plan.

### Plan 1a — delivery & sync

**Rulings**

- Task 1: review approved (opus). Ruling: minor-1 (missing mutation checks for worker-only no-bump, messages/reactions DEFAULT, updated_at SELECT grant) is a Global-Constraints requirement ("mutation check for each key rule") → fix now — cost if wrong: one small extra round. Ruling: minor-2 (column-drift guard on trigger tuple) fix now — protects the cursor against future columns — cost: small. Task 1: minor (deferred): index lacks id tiebreak (relationship_id, updated_at, id) — revisit in Task 3.
- Task 2: review (opus) Needs fixes — Important: headline rule (insert must not write relationships) has no mutation check (plan-mandated by Global Constraints). Ruling: also fix cheap minors now (REVOKE ALL before grants + privilege assertion; RLS outsider mutation check; LOCK TABLE messages IN SHARE MODE before seed; complete column comment; stale DATING_CHAT_SAFETY_SPEC lines) — files are new/undeployed, cost small.
- Task 3: Ruling: fix minors 1 (.or membership defense-in-depth in getConversation), 2 (ChatLog.d on ensureRealtimeConnected failure), 3 (chunk getMessagesByIds ids to <=100 per request — backfill bursts can name hundreds of ids), 5 (ChatChannelLoader: null/error → friendly unavailable state instead of infinite spinner) — real failure modes, cheap — cost if wrong: one extra round.
- Task 4: Ruling: I1 fix = server-only sync cursor advanced from repository responses (updated_at), persisted per relationship in the cache, paging until exhausted (also fixes minor-2 200-row cap) — brief text said "server timestamps only", so this restores the spec intent — cost: small extra cache field. Ruling: I2 fix despite plan omission (spec #6 requires the deletion to persist). Ruling: also fix minors 1 (gate _onlyLoadedSpan on "server page landed"), 3 (auto-chain older page when it adds no new ids, bounded), 6 (_catchUpFromCursor returns whether it loaded first page; handler skips duplicate), 7 (tests: isOlderThanCursor equality, loadMore knownBefore race).
- Task 4: Ruling: implementer concern (>200 rows sharing one updated_at — e.g. bulk mark-read — stalls the cursor) is real → extend fix round 1 with an (updated_at, id) tuple cursor + afterId on getMessagesChangedSince — cost: one interface addition to Task 3's method.
- Task 4: fix round 1/5 (7 addressed, 1 new Important open — cursor stalls when >~1000 rows fall in the 30 s overlap window; trees 911c01f..86fe82d). Ruling: round 2 also fixes minors NB2 (short-read limit), NB3 (purge race re-persisting cursor), NB4 (one cache write per sync, cursor persisted after it) — cheap, same function.
- Task 4: Ruling: accept implementer trade-off — overlap re-read capped at one read (≤200 rows) per sync; a late-committing change deep inside a >200-row 30 s window could be missed by the cursor — realtime UPDATE frames + first-page reconcile still deliver it — cost if wrong: a rare missed edit on an old row until next page view.
- Task 4: fix round 2/5 (3 addressed, 1 open — purge race on seed path: first page in flight across purge re-seeds cursor; plus out-of-scope-but-privacy: loadMessages/loadMoreMessages in flight across account change writes previous account's history back into cache → Ruling: fix in round 3 with epoch captured before the request on all page paths — cost small; trees 86fe82d..3dce9fe)
- Task 5: implemented (DONE_WITH_CONCERNS). Ruling: brief Design 3 is binding — media upload/preparation runs outside the FIFO queue, only the message insert takes its place among waiting items, so a text typed during a long upload sends immediately (WhatsApp behaviour; spec §4.2 "one logical message at a time" applies to inserts) — cost if wrong: media may land after later texts on the partner's phone (same as WhatsApp). Sent back to implementer before review.
- Task 5: Ruling I2: spec §4.2 "only server rejections count toward the cap" governs over the brief's literal rule — PostgrestExceptions carrying a SQLSTATE (P0001, 22xxx, 23xxx≠23505, 42xxx≠42501) count toward the cap (category unknown); only HTTP 5xx/gateway/network stay uncapped — cost if wrong: a transient server-side raise could fail a message after 5 attempts (user can retry).
- Task 5: Ruling: also fix minors (dead-cache fallback stuck-clock, timer-less catch paths in settle/flush, failure path stale pending overwriting persisted key, stale failedPermanent outbox rows shadowed by canonical rows) — robustness of the core feature; cost small.
- Task 5: fix round 1/5 (8 addressed, 0 open; trees 8202b19..f0a8c10). Ruling: one more round for 5 minors that each leave a bubble stuck (failedPermanent streak carve-out, PGRST/4xx uncapped clock, _sendWithoutOutbox 42501 read-only copy, retryMessage unguarded readOutbox, image/video dead-cache stuck at sending) — core-feature robustness, cheap.
- Task 6: Ruling: also fix minors 1 (_refreshAgain re-run via refreshQuietly for current user), 2 (refreshQuietly doc/behaviour), 3 (markAsRead list refresh only when receipts off), 4 (delivered/flush skip after purge test), 5 (_isBuilt gap: don't drop inbox when !_isBuilt; subscribe from cached ids in catch path) + verify a messageDelete-by-id removes the row (Task 4 coverage) — cheap, all in the same files.
- Task 6: Ruling: accept M3 alternative (refreshSoon coalescing — client can't know receipts setting from mark_conversation_read) — cost: none functionally. Accept M4 test as backstop coverage (purge also archives).
- Task 6: fix round 1/5 (8 addressed, 0 open; trees 5af0187..4475458). Ruling: round 2 for 3 delivery-delay minors (multi-page changes-since under one 20 s bound never progresses on slow links; touched ids not re-queued when refreshMessagesByIds fails; trailing inbox debounce starvation → add max-wait) — cost small. _init delivered guard → Task 7 (already carried).
- Task 7: review (opus) Needs fixes — I1: unbounded _insertMessage swallows all triggers while hung (bound it; 23505 reconcile prevents dupes); I2: drainer never drains on cold start/sign-in. Ruling: also fix M1 (offline banner with queued count wins over load-failure banner while offline), M2 (archived-skip drainer test), M4 (drainer awaits woken controller's open before flush). M3 (fixed sleeps) deferred.
- Task 8: review (opus) Approved. Ruling: fix minors 1 (resume-while-covered test), 2 (popup clause test), 3 (AppRouteObserver keeps lastPushedRoute accurate on didPop/didRemove/didReplace), 5 (GoRouter wiring test), 6 (setUp reset) + doc note for 4 — cheap, prevents silent regressions of #10.
- Task 10: implemented (DONE_WITH_CONCERNS). Ruling C1: accept — outbox writes/readOutbox/writeMessages keep throwing (Task 5/7 dead-cache engine + cursor rule depend on it). Ruling C2: spec §16 "preserve recoverable queue" governs over the brief — delete+recreate only for corruption (SQLITE_NOTADB 26 / SQLITE_CORRUPT 11); locked/busy (5/6) retried with short backoff; any other open/schema failure → in-memory session WITHOUT deleting the file — cost if wrong: a truly broken non-corrupt file keeps the app on in-memory cache each launch (still works, no history offline). Ruling C3: putOutbox must throw when the cipher is null (no silent skip) so the engine's honest dead-cache path applies — cost: none.
- Task 10: review (opus) Needs fixes — I1: degraded session's clearAll/purge never reach the kept disk file (sign-out privacy); I2: purge callers (_purgeRelationshipLocalState, _handleAccountChange) abort purge + UI reset when readOutbox throws. Ruling: fix both (I1 = best-effort disk reset + persisted 'wipe on next open' tombstone if reset fails); also minors 1/3 comments, 2 ChatLog event on degrade, 4 doc placement, 5 capture debugPrint in failure-path tests.
- Task 10: fix round 2/5 (7 addressed, 0 open; trees 259abcd..d62842f). Ruling: round 3 for sign-out hang/init race (single-flight init + bounded wipe/reopen), unremovable marker → fail open, and mounted re-check after await in _refreshConversation archived/null branches — user-facing robustness, cheap.
- Task 10: Ruling: accept trade-off — after a timed-out sign-out wipe, the marker wipes the store on next launch even if the late clear finished, possibly losing the next account's queued sends from that session — privacy over convenience, extremely rare — cost if wrong: a rare lost queued message after a slow sign-out.
- Final: Ruling: fix C1, I1 and minors M1 (catch unawaited writeMessages), M2 (no double reads on open), M3 (backoff on unreadable outbox), M4 (bound loadMoreMessages), M5 (bounds scale with request count; page catch-up with cap), M6 (account switch → controller re-init/invalidateSelf), M7 (select updated_at in _messageColumns for exact seed), M8 (NativeDatabase.createInBackground) in ONE fix wave — owner wants everything robust. M9 → owner deploy step (diff live enqueue_message_downstream_work before db push). M10 harmless.
- Final: Ruling (declined-to-judge 1): RLS-empty first page wiping local history on seal/30-day window/archive is correct per Spec 3a (closed chats must not stay readable) — keep — cost if wrong: history disappears when a chat closes (intended).
- Final: Ruling (2): _replaceOptimistic keeps device-time slot for the session → carry to plan 3 (message ordering).
- Final: Ruling (3): ephemeral_video_viewer screenshot notice outside outbox → plan 1b Task 10.
- Final: Ruling (4): _uploadMediaPhase stall timeout → plan 2 Task 9.
- Final: Ruling (5): messages DELETE frames dropped under REPLICA IDENTITY DEFAULT — deliberate privacy; soft deletes arrive as UPDATEs, hard deletes via reconcile — keep.
- Final: Ruling (6): plain-text sync cursor (timestamp+id, no content) acceptable — keep.
- Final: Ruling (7): ChatLog.diagnostic prints Postgrest/Storage exceptions intact — carry to the program-end review (check whether exception text can echo message content; logs are debug-gated).
- Final: Ruling (8): markRelationshipDelivered per list refresh — idempotent RPC, keep.
- Final: Ruling (9): page pushed from inside an open sheet not seen by RouteAware — documented, no path exists — keep.
- Final: Ruling (10): owner's unrelated work — out of scope.
- Final fix wave: done HEAD=9e65c5e842ba51ad499cb178a448255e37ec249a; full suite 4258/4258. DEPLOY ORDER (owner): migrations 20261019100000 + 20261019100010 must be live before this app build ships (all message reads select updated_at). Extra fix: releaseChannel closing stream under rebuilt controller. Ruling: accept M5 per-page catch-up bound (hung page holds batch 2x timeout) and M2 window trade-off (pin/header change in sub-second open window waits for next frame) — cost if wrong: a few seconds' delay in rare cases. Possible flaky test: chat_controller_test "receipts off … not re-marked" (real-time wait) — watch.
- Final: Ruling: targeted residual fix for R1 + R2 despite the "one fix wave" rule — R1 guards a cross-account write with no other coverage; R2 hits exactly the owner's manual test (chat wiped → starts empty) — cost: one small extra round.

**Deferred minors**

- Task 1: review approved (opus). Ruling: minor-1 (missing mutation checks for worker-only no-bump, messages/reactions DEFAULT, updated_at SELECT grant) is a Global-Constraints requirement ("mutation check for each key rule") → fix now — cost if wrong: one small extra round. Ruling: minor-2 (column-drift guard on trigger tuple) fix now — protects the cursor against future columns — cost: small. Task 1: minor (deferred): index lacks id tiebreak (relationship_id, updated_at, id) — revisit in Task 3.
- Task 1: minor (deferred): drift guard matches NEW.col/OLD.col textually (a comment mention would pass)
- Task 2: minor (deferred): counter row is still a per-relationship hot row lock (realtime echo gone; serialisation remains) — acceptable at couple scale.
- Task 3: minor (deferred): source-slice test brittleness (brief-mandated); staging check of %2B-encoded keyset timestamp and prod relationships RLS (owner/manual).
- Task 3: minor (deferred): chat_channel_loader/app_router circular import; new loader copy hard-coded English (chat l10n gate item)
- Task 4: minor (deferred): overlapping loadMessages stale response can transiently re-add a dropped row (pre-existing race, heals next sync); catch-up-failure gap (pre-existing) — point Task 6 / final review at these.
- Task 4: minor (deferred): commit() failure inside read catch replaces original read error (diagnostics only)
- Task 5: implemented incl. ruling fix HEAD=8202b195846eb3e5fc90e5a905203fc759502aa5; minor (deferred): crash between video upload and poster upload → video sent without poster
- Task 5: minor (deferred): staging media not deleted when M4 drops an outbox row; bare 401/403 PostgrestException now capped (expired JWT PGRST301 stays uncapped)
- Task 7: minor (deferred): account-switch drain can wait up to ~100 s behind previous account's stale whenOpened wait (correctness holds)
- Task 9: review (sonnet) Approved. Task 9: minor (deferred): test could also assert later edit persisted / restore doesn't re-write draft.
- Task 10: minor (deferred): worst-case sign-out hold ~2x clearAllBound (6 s) after a timed-out clear

### Plan 1b — push & security

**Rulings**

- | Cross-plan: T10 ↔ plan 1a | ChatRepository.sendTextMessage signature change vs 1a's rewritten send path (_insertMessage, _sendWithoutOutbox, reconcile) | Ruling: implementer must adapt against CURRENT code; carry 1a ledger note re ephemeral_video_viewer_screen.dart:125 direct sendTextMessage (likely the screenshot notice T10 replaces) |
- | Cross-plan: T2/T8 ↔ plan 1a T10 | sign-out path: OneSignal logout/unregister (T8) vs ChatCacheService.clearAll in AuthNotifier._exclusive (1a T10, bounded 3 s) | Ruling: T8 must keep sign-out bounded overall (its own 3 s unregister timeout) and not reorder the cache wipe after a possibly-hanging network call |
- Task 2: review (opus) Needs fixes — Important: permission prompt can appear over the quick-exit decoy (Spec 2 safety). Ruling: fix + minors (once-per-run test with denying fake; PushSdk.initialize → Future<void> awaited — departs from brief's void signature, justified: errors unhandled + permission read before init — cost: none; outdated comment). Postponed ask happens on the next trigger (lock/auth/resume), not on leaving the decoy.
- Task 5: review (opus) Approved. #14 verified for native messages (per-insert pg_net kick + wake: ~1–3 s). Ruling: I1 dead stale-lease recovery cron → carried to plan 2 Task 2 (#24 re-registers recover_stale_chat_worker_leases) — cost if wrong: crash-stranded pushes lost until plan 2 deploys (same deploy batch). Ruling: fix now I2 (wake timeoutMs → 3000 to fit pg_net's ~5 s), I3 (reaction outbox rows get the same per-insert pg_net kick — new migration in 1b range), minor 2 (dedupedByData guard), minor 3 (behavioural processJob retry test). Minor 1 (one wake per cron batch) and 4 (sender backlog order) deferred.
- Task 5: Ruling (product): a re-react / changed emoji to the same message does not send a second push (Task 4 one-push-per-outbox-id); a still-pending first push may carry the old emoji (seconds) — calmer couples-app behaviour — cost if wrong: owner may prefer a push per change (small follow-up).
- Task 6: implemented HEAD=44f72b2f557f43b57476eea6ed292351d148984b. Ruling: accept residual — knowing another user's subscription id lets a caller move that device to themselves (denial of that device's pushes; no content read; ids not exposed) — cost if wrong: targeted push DoS by someone who obtains a device id. DEPLOY: apply 110200/110210 in the same deploy as Task 7's sender change. Carry to Task 8: remove/route savePushToken/removePushToken (direct table writes now denied).
- Task 6: review (opus) Approved. DEPLOY ORDER (owner, from plan): install new app build on phones FIRST, then 110200/110210 + Task 7 sender in one sitting. Ruling: quick round for minor 3 (has_any_column_privilege check for anon/authenticated + mutation) and minor 2 (comment the belt-and-braces guard) — security test gap, cheap.
- Task 7: review (opus) Approved. Ruling: fix all 5 minors now (partial-400 prune-then-retry; intersect invalid ids with targeted (case-insensitive); OneSignal body idempotency_key; assert prune patch; silence expected console.error) — delivery/security/duplicate-push robustness. Carry to Task 8: _syncSubscription must re-register on optedIn change (OS opt-out/in recovery).
- Task 7: fix round 1/5 (5 addressed, 0 open; trees 75bc402..9f13dad). Ruling: residual (OneSignal may cache a 400 under the idempotency key) closed by deriving the key from job id + sorted target set (same targets → same key; pruned retry → new key) — strictly safe since a 400 sends nothing.
- Task 8: Ruling: fix Critical (init completer + opt-out on signed-out attach), Important, all minors (releasedFor check first; cancelRelease on failed sign-out; break auth↔onesignal import cycle via a sign-out hook provider; safety fallback test; try/finally debugPrint). Ruling: ALSO close the revoked-session gap — "sign out other devices" (Spec 2) must deactivate the user's other push subscriptions server-side immediately (new RPC keeping the caller's subscription id; migration in 1b range) — safety feature, privacy — cost: one small RPC + client call.
- Task 8: Ruling: close revoked-session re-register gap now — register_push_subscription must refuse when the caller's JWT session (auth.jwt()->>'session_id') no longer exists in auth.sessions (redefine via CREATE OR REPLACE in 110220, Task 6 RPC not yet deployed) — cost: none if session_id claim present; verify local auth.sessions shape.
- Task 8: fix round 1/5 (10 addressed, 0 open; trees 7a4ae3a..e5607af). Ruling: round 2 for the 4 new minors + out-of-scope deferred-permission opt-in (all privacy/delivery races, small).
- Task 8: Ruling: accept narrow residual — a timed-out sign-out-others deactivate landing after this phone's re-register silences it until next app start — cost: rare missed pushes on the owner's own phone after sign-out-others.
- Task 9: review (opus) Needs fixes — CRITICAL: edit_message has no is_system_notice check → caller edits their own screenshot notice (or planning goal notice) into a forged official line. Ruling: also block delete_message ("delete for everyone") on system notices — the screenshotter must not be able to hide the screenshot notice — cost if wrong: a member can't remove a notice line (acceptable; notices are server facts). Also fix minors 1 (comment/test wording) and 2 (display_name → username → 'Someone' fallback).
- Final: Ruling: fix wave = I1 (anon-callable release_push_subscription(p_subscription_id) deactivating that one id + persisted owed release retried on next start), M1 (sender answers 202 + EdgeRuntime.waitUntil loop), M2 (enqueuePush reports whether a row exists; no wasted wake), M4 (_unregisteredKey reset at _onSignedIn), M5 (tighten push_tokens platform CHECK, drop 'web'), M7 (NOTIFICATION_ENGINE.md + CHAT_SYSTEM_SPEC.md §9). M3 + stale-processing sweeper for scheduled_notifications → carried to plan 2 Task 2 contract. M6 → owner deploy step (row count). M8 accepted. I2 → owner deploy list from final-review.md (copied into the program hand-off).
- Final: Ruling (declined 1–9): Spec 7 hide-a-period hiding a notice — other feature, keep; per-conversation mute — no such concept, keep; This or That reminder — games session carry; stuck processing/dead cron — plan 2 T2; OneSignal.login alias — harmless (sender ignores alias), owner rule: no dashboard campaigns by external_id; screenshot notice outside outbox — accepted (best-effort RPC); badges/grouping — out of wave (needs iOS NSE, owner follow-up); authStateProvider seed plumbing — keep; owner's unrelated work — out of scope.
- Final fix wave re-review: all ADDRESSED; residual minors: _register capture-order wait cycle (one line), stale 'thirteen' migration count + missing anon release verify line in final-review.md. Ruling: fix both (trivial; a deadlock, however unlikely, leaves a device unregistered for the run). Residual accepted: cold-start + offline + app closed before online → no owed release (local opt-out only).
- Final residuals: fixed (capture-order deadlock RED→GREEN test; doc count 16 + anon verify line). Ruling: accepted on the implementer's RED→GREEN evidence without a further re-review — one-line change plus doc text — cost if wrong: minimal. HEAD=e0c672198dc0ce6edaa795d79ca24beb00eb5f2b; full suite 4352/4352.

**Deferred minors**

- Task 1: review (sonnet) Approved. minor (deferred): pbx guard test checks string presence only (Runner wired in all 3 configs today).
- Task 2: minor (deferred): second initialize() during attach() would re-register listeners (single call site; latent)
- Task 3: review (sonnet) Approved. ⚠️ paused-relationship push block: worker suppresses status != active (paused included) + quiet guard trigger — resolved. minor (deferred): source-text tests brittle.
- Task 4: review (sonnet) Approved. minor (deferred): dedupe DELETE untested with seeded duplicates; quadratic self-join only matters on huge tables (owner: check live row counts before deploy; dev is tiny).
- Task 8: minor (deferred): stale _unregisteredKey could skip a server unregister in a triple-coincidence case (device still opted out locally) — one-line reset at release start; include in plan 1b final review.
- Task 10: review (sonnet) Approved. minor (deferred): unused `user` var (null guard only); brittle source-text guard (brief-mandated).

### Plan 2 — media

**Rulings**

- | T9 ↔ plan 1a outbox | streaming uploader (progress/cancel/retry) vs 1a's _uploadOutsideQueue/_uploadMediaPhase/_runUpload (media upload outside FIFO, purge-epoch + senderId guards, persisted uploadedMediaKey, backoff) | Ruling: T9 must integrate with the CURRENT 1a upload path (not the pre-1a shape the plan assumed); carry 1a ledger requirement: uploads need stall detection/timeout → retryable (a hung upload must not stay 'uploading' forever) |
- | T1 ↔ plan 1b T9 | T1 redefines delete_message from 20260950110000 | CONFLICT: plan 1b's 20261019110320_system_notice_immutable.sql already redefined delete_message (refuses system notices). Ruling: T1 must redefine from the 110320 definition and keep the system-notice refusal (and edit_message untouched) — cost if wrong: re-opens notice deletion (#19) |
- Task 2: implemented HEAD=a5bd4739b21130eeb867982862d1fd16148ce30e. Ruling: accept deviation 120050 (one-time retire of rows stuck in processing > 1 h so the revived recovery doesn't send weeks-old pushes/reminders) — cost if wrong: those stale notifications are never sent (intended). Triage started for failing reminder_delivery/together_events contracts.
- Triage: reminder_delivery + together_events contract failures = local harness drift (local_pg_grants.sql blanket GRANT re-opens couple_events / couple_family_members, which have no *_grants.sql replay file); pre-existing, unrelated to 202610191* migrations; prod unaffected. Ruling: out of chat scope → owner follow-up (add 2 grants files for Together tables + \i lines; 8 older grants files not replayed listed in triage). Added \i for 20261019120115 grants.
- Task 2: review (opus) Approved. Ruling: fix minor 1 now (AbortSignal.timeout ~30 s on the OneSignal call → retryable error; closes lease/fetch overlap). Minors 2–5 accepted (no backfill of push_queued_at; two-session lock test; report wording; NULL processing_started_at theoretical).
- Task 3: implemented (DONE_WITH_CONCERNS). Ruling: Android HEIC picks must be converted to JPEG at full resolution (WhatsApp accepts HEIC) — not rejected — fix before review; cost: re-encode once on Android HEIC only.
- Task 3: Ruling: fix I1, I2 and minors 1 (probe in isolate), 2 (inSampleSize/downscale-on-decode for native ladder), 3 (discard on !mounted), 4 (picker errors caught → plain error + discard), 5 (doc placement), 6 (reject undecodable inside the isolate), 8 (_unsavedSends purge discards sources); minor 7 → stage picks in an app-support subdir (not OS-purgeable) with the same ownership cleanup (spec §16 preserve recoverable queue). Ruling: accept iOS JPEG double-encode (image_picker_ios always re-encodes) — cost: slight extra compression on iOS.
- Task 3: Ruling: also move the prepared upload file (_tempTargetPath) out of OS temp into the app-support staging area with cleanup after upload is acknowledged/removed/purged — same durability rule (offline queue must survive OS cache purge) — cost: small, shared path touched carefully.
- Task 3: Ruling: accept residual — an in-memory-only held send (outbox write failed) is invisible to the sweep (only matters if one session stays open >7 days with it unsent and a new photo is picked).
- Task 3: fix round 1/5 (12 addressed, 1 new Important — staging folders included in Android Auto Backup/device transfer + iOS iCloud backup; 3 minors). Ruling: round 2 fixes backup exclusion (Android XML excludes for chat_picks/ + chat_prepared/; iOS exclude-from-backup flag for both folders AND the encrypted chat cache sqlite as defence-in-depth), purge/rejection orphans, rooted ownsPath, lenient JPEG walker. PNG/WebP orientation gap accepted (rare, pre-existing behaviour).
- Task 5: review (opus) Needs fixes — I1 photo streak gets video copy. Ruling: fix I1 + minors 1 (413 size-specific copy per media kind), 2 (storage 403 → unknown: counts toward cap, retried with fresh intent up to 5, not permanent — expired intent/JWT mid-upload recovers), 3 (_holdUnsaved forMedia test).
- Task 5: fix round 1/5 (4 addressed, 0 open; trees 49ca6f4..5a07305). Ruling: accept trade-off — a genuine storage-policy 403 fails after ~2 min of capped retries instead of at once.
- Task 6: review (opus) Needs fixes — CRITICAL success-after-dispose throws + leaves timer that disposes later live members (voice re-sign regression); IMPORTANT refresh not tied to token expiry (repo cache hands back near-expiry URLs; refresh rebuild doesn't forceRefresh). Ruling: fix both + bound 'keep last good URL' by real expiresAt (show retry once expired) + minors 3 (contextual retry label per media kind) and 4 (visual retry glyph).
- Task 7: implemented HEAD=f971297166a6c218480b53a9de59b3c5e75db406. Ruling: concern 1 (note started on media screen continues in chat until chat is left) acceptable. Concerns 2 (stop keyed to owning chat instance), 3 (speed chip ≥48 dp target), 4 (network stall → buffering state, auto-resume, not 'paused') to fix after review.
- Task 7: review (opus) Needs fixes — I1 finished note can't replay (ReleaseMode.release); I2 note outlives deleted/purged/hidden bubble; I3 whole-state watch rebuilds every voice bubble per frame; I4 speed chip target + layout jump + double semantics; I5 buffering stall becomes hard pause (plan-mandated). Ruling: fix all I1–I5 (I5: remote → loading ring keeps isPlaying, demote after 8 s; local → 1.5 s) + all minors 1–8 + stop on account change (listen currentUserProvider).
- Task 7: Ruling: accept (a) idle voice bubbles ~4 dp taller (reserved speed-chip slot, no jump), (b) remote note during a phone call shows loading ring up to 8 s before paused.
- Task 7: Ruling: accept speed-chip 48×48 hit area overlapping the waveform's last 48 dp while the chip shows (tap = speed, drag = seek) — cost: a tap-seek to the very end needs a drag.
- Ruling: fix round 1 takes I1 + minors 1,2,3,4,5,7 — owner wants everything robust before manual testing; each is cheap and user-visible — cost if wrong: one extra fix round.
- Ruling: minor 2 (byte bound) built as a 1 GB total-bytes budget tracked in the ownership index, oldest evicted first — count×25 MB could reach ~10 GB on Android — cost if wrong: earlier re-downloads of old media.
- Ruling: minor 6 (backup guard source-only) left as is — the location test covers it — cost if wrong: a refactor could move the DB unnoticed.
- Ruling: minor 8 (video first play waits for the full download) kept — WhatsApp also downloads before play, ring shows real progress, owner told — cost if wrong: slow first play of big videos on bad links; device check.
- Ruling: fix round 2 takes voice-only 8 s overall cap, touch-on-voice-hit, and an orphan-partial sweep (on cache init + after a failed download) — privacy (deleted message bytes) and a 28 s dead tap are user-visible — cost if wrong: one more small round.
- Ruling: fix round 1 takes I1, I2, minors 3-9 — all cheap, user-visible or hygiene — minor 10 (cancel from rebuilt controller) parked: rare, purge-guarded — cost if wrong: one uncancellable upload after a rebuild.
- Ruling: minor 7 response bound → 60 s (idle bound stays 20 s) — slow links drain buffers after last chunk handoff — cost if wrong: a dead server reply takes 60 s to surface.
- Ruling: used intents are NOT pruned (old behaviour kept) — chapters/account deletion read them to find orphans — cost if wrong: intent table grows by one row per media send.
- Ruling: Task 9 round 2 = expired-intent re-upload + _handlePreparationFailure dispose guard; re-review covers rounds 1+2 together — saves one review seat — cost if wrong: a larger re-review diff.
- Ruling: round 3 = N1 (check findMessageByClientId before re-upload) + N2 + N3 + audit ref-after-await in the send path (_attemptSend last-defence catch) — owner wants robust; same bug class as R2-2 — cost if wrong: small.
- Final: Ruling: I3 fixed in this wave (not deferred) — owner bar: nothing survives sign-out/delete; one-line cost — cost if wrong: none.
- Final: Ruling: fix wave takes I1-I3 + M1,M2,M3,M4,M6,M7,M8; M4 edits the undeployed 20261019120000 migration in place (plan 2 migrations not yet pushed) — cost if wrong: if it was already applied on hosted, a follow-up migration is needed (files are untracked and on the pending deploy list, so not applied on hosted).
- Final: Ruling: residual pass takes N1, N2, N3 + imageCache.clear()/clearLiveImages() on sign-out + M3 `_index = null` after timed-out clear + _onStore listener once — all 1–3 lines, two touch the owner's sign-out device check — cost if wrong: one small extra pass (skill's "one fix pass" bent deliberately; owner bar is everything fixed).

**Deferred minors**

- Task 1: review (sonnet) Approved. minor (deferred): garbled header comment + dropped rationale comments in 20261019120000; total-count queue assertion.
- Task 4: review (sonnet) Approved. minor (deferred): optional deny-list for image-only ISO-BMFF brands (heic/heix/mif1/avif) to keep precise media_type_unsupported (they fail later as media_decode_failed).
- Task 7: minor (deferred): sub-tick notes' completion ignored → shown paused; stale tick could mark new generation advanced (negligible).
- Final: minor (deferred): M5 byte-budget over-count after cache-manager's own evictions → earlier evictions only (harmless); LRU may delete a playing file (POSIX keeps it open).
- Final: minor (deferred): M8 treats transient FileSystemException (EMFILE) as permanent; dead-cache in-memory send lost on ceiling eviction (as on any eviction); ChatImageCache zone edge.

### Plan 3 — chat screen

**Rulings**

- Ruling: T1 also flips message_bubble_test.dart:252/:274 (pin old no-"edited" behaviour) — they encode the regression — cost if wrong: none.
- Ruling: T5 unknown-dimension images keep Plan 2's 2× display-width decode (1320 px cap test stays); known portrait → width, landscape → height; group tiles decode to 300 pt (long side), no LayoutBuilder — Plan 2 protection for optimistic rows wins — cost if wrong: slightly larger decode for unknown-size rows.
- Ruling: T13 wraps getMessagesByIds lookup in _bounded; reuses existing harness getMessagesError — a hung lookup must not leave the "Finding that message…" chip forever — cost if wrong: none.
- Ruling: T3 adds the over-limit guard to _sendStagedGame too — same draft-destruction class — cost if wrong: none.
- Ruling: T14 diff hygiene diffs against the plan-3 BASE tree snapshot, not HEAD — everything is uncommitted — cost if wrong: none.
- Ruling: carry "message ordering" → T9 Step 2b: keep the device-time slot at ack, snap to server order on next genuine arrival (anchoring makes the reorder safe) — clock-ahead phones otherwise keep own bubble below a later partner reply — cost if wrong: a visible reorder on arrival.
- Ruling: l10n — plan 3 extracts nothing (chat is hard-coded English app-wide except one screen; ARBs hand-maintained ×6); new strings written as whole sentences / one plural function; list goes to the app-wide l10n gate (preflight.md lists them) — cost if wrong: one extraction pass later.
- Ruling: T12 adjusts to Spec 2 safety-lock deferral in OneSignal listeners and skips the ack when signed out; T7 keeps CrossAxisAlignment.start — current code — cost if wrong: none.
- Ruling: fix round 1 takes I1-I3 + minors 4-7 (6 = edit dialog gets the same formatter + refusal, keeps text) — owner wants everything; 6 is the same draft-loss class — cost if wrong: none.
- Ruling: fix round 1 = I1 (tween padding at bottom ~220 ms easeOutCubic, zero under reduce motion; scrolled up keeps snap+hold) + cut typing indicator top padding 30→8 (Plan 4 keys the switcher, not its padding — note for Plan 4) + minors 3,5,6,7 (remove the pointless setState if nothing reads it) — cost if wrong: small.
- Ruling: minor 2 (rebuild cost) → device profiling check, not code now — a notifier saves only the outer build; the real fix (CustomScrollView + SliverPadding listenable) collides with T9 — cost if wrong: typing jank on low-end Android, fix later.
- Ruling: round 1 = I1 (re-issue driven animateTo from corrected pixels in applyNewDimensions; clear memo for non-driven activities; non-uniform-height per-frame smoothness test) + minors 2, 3, 5 (floor on canonical rows only) — cost if wrong: small.
- Ruling: Minor-5 extension accepted — a row still optimistic when a genuine arrival lands takes server order at its ack (one-row swap in a brand-new chat) — server order wins, consistent with the Step 2b ruling — cost if wrong: one visible swap at ack in that narrow case.
- Ruling: round 1 = I-1 (getConversation fetches the real unread count via _fetchUnreadCount; loader test) + M-1..M-4 — owner wants everything; push open is the primary path — cost if wrong: one RPC per push open.
- Ruling: T12 stamps delivered on push tap and foreground display only; true background receipt needs native extensions (iOS Notification Service Extension, Android NotificationServiceExtension) — owner follow-up, outside this wave — cost: "delivered" lags until the push is opened or the app foregrounds.
- Task 11: implementer DONE (+1432); snapshot 48a1acc14e1508345d85bba0d39174b6284a6662; package review-t11.diff. FLAG: implementer changed T9 smoothness-test fixture to partner-only senders because own group-end ticks (taller rows) tipped the D>0 stall threshold = Fable's residual one-frame slowdown. Ruling: restore the fixture (mixed heights must stay covered) and implement Fable's optional cure (arm ChatListAnchor inside correctBy) by the T9 implementer after the T11 review — cost if wrong: one more round on the scroll controller.
- Ruling: I2 — controller ruling wins over the brief: failed/timed-out lookup → "Couldn't find that message." immediately, no blind paging — a by-id lookup failure means the network is bad; blind paging on a bad link is the worst case — cost if wrong: an offline jump to a message the server has fails instead of searching.
- Ruling: round 1 = I1 + I2 + minors 3, 4 (distinct copy for "too far back"), 7. Minor 6 (paint-only highlight in shared UniversalBubble) → final wave polish. 5/8 device / accepted.
- Task 13: re-review 1 → all addressed. Flake risk: overlap + cancelJump tests use real Future.delayed(20ms) as 'in flight' → move to fakeAsync / pump-until-call-count. Ruling: fix now (round 2, tests only) — suite reliability for the plan-3 final run — cost if wrong: none.
- Final: Ruling: I-1 fixed by applying the post-open cutoff only on the late placement path (not a 5-min skew allowance) — the normal path's first server page is already a post-count snapshot — cost if wrong: late path still skew-sensitive (offline open only).
- Final: Ruling: fix wave takes I-1, I-2 + every minor and carried item in final-fix-list.md (16 items) — owner wants everything fixed — cost if wrong: a larger wave; one scoped re-review follows.
- Final: Ruling: round 2 = item 1 (revert growth; no-layout padded hit proxy; "Edit history" in the long-press sheet for edited rows) + item 12 (MakeRoom ClipRect clipBehavior none when factor == 1) — design quality is first-class — cost if wrong: small.
- Final: Ruling: round 2 accepted without a third review — two local items, each RED→GREEN with mutation evidence, after a scoped Fable re-review that specified the exact fixes — cost if wrong: a cosmetic issue found on device.

**Deferred minors**

- Final: minor (deferred): M-5 reserve-glide per-frame list rebuild (device profiling first; CustomScrollView+SliverPadding listenable refactor if needed); M-9 cold-start push-tap ack waits for session restore.
- Final: minor (deferred): staged-file promotion skipped on mid-settlement close (Plan 2 follow-up); trailing '_' URL trim nit.
- Final: minor (deferred): chat_w2_final_fixes_test "I1 sign-out staging wipe" load flake (passes alone) — harden with a poll in plan 4's final wave.

### Plan 4 — sounds, streaks, games

**Rulings**

- Ruling R1: fake audio-session override added up front in buildChatContainer + the 4 voice test files; _releaseSession non-throwing (catch + log) — real port throws MissingPluginException on the test host — cost if wrong: none.
- Ruling R2: T3 acquire in _playSource, release in _stopNow/pause/_onComplete/_onEnginePlaying(false)/_fail/dispose; `catch (error)` never `catch (_)` (kept source test) — current Plan-2 controller shape — cost if wrong: none.
- Ruling R3: T7 changes only the arrival set in _syncArrivals; Plan 3's Task 10 block and `&& _atNewestEnd()` kept byte-for-byte — the plan's snippet would regress Plan 3 — cost if wrong: none.
- Ruling R4: partner game-card move while scrolled up → device check (anchoring should hold) — cost if wrong: a visible shift.
- Ruling R5(a): T10 rescoped — open/quick-reaction haptics already exist in focused_action_menu; add only a selection() for a full-picker pick + a no-double-fire test — avoids double haptics and touching a shared core widget — cost if wrong: none.
- Ruling R6: T11 "accepted" = passed the over-limit guard and entered the outbox (Plan 1a semantics); staged game chirps after send() returns a session id — cost if wrong: none.
- Ruling R7: T9 edits only the typing switcher and record button (Plan 3 owns _scrollToLatest/_tryEnsureMessageVisible).
- Ruling R8: T1–T4, T13, T5 SQL/repo/util and T9 record-button part may run during the plan-3 fix wave; T5 bubble line, T6–T12 screen parts wait for it.
- Ruling: round 1 = I1 + M1 (generation/state re-check after the borrow) + M4 + M5. M2 → owner device check + follow-up (pausing must keep position; changing the Android player context mid-note risks a re-prepare). M3 accepted (pre-existing heal-once semantics).
- Ruling: round 1 = I1 (hold from first frame; spinner while loading; load timeout → error text) + minors 3, 4, 5, 7. Minor 6 (message_bubble.dart) deferred until the plan-3 fix wave lands (file conflict), then done in plan 4's final wave — cost if wrong: double-tap burns a view until then.
- Ruling: Issue 2 becomes Task 5b after Task 5 (server): per-open idempotency key on the spend RPC + spend fired at presentation + sign all clips up front + await stored result in _finish — view-once privacy is a hard product rule; new migration in the 1400xx range — cost if wrong: one extra migration + task.
- Task 5: BASE tree 7d920d6148ddab2d834dcdbc4434a8e9c53b6cc5. Ruling: split — SQL + repository + util + their tests now; the message_bubble line deferred until the plan-3 fix wave lands (file conflict) — cost if wrong: none (bubble line is display only).
- Task 4: fix round 1 DONE (streak 42/42); snapshot ecc0cb4b687a44e5fdaedb812a655ee83384f58b; package review-t4-fix1.diff. Ruling: a clip-1 failure does not try clip 2 (nothing seen yet; moving on would spend on an unseen first clip) — cost if wrong: a multi-clip streak with a broken first clip stays unopenable until retry.
- Ruling: Task 5b (new, after Task 4 lands) = one migration in 1401xx: storage SELECT streak window clause (sender strict), pg_cron sweep (guarded) + partial index, RPC requires live streak (media_type='streak', not deleted), idempotent per-open spend (open token/idempotency key on mark_streak_viewed or a new RPC), fix the 20261019140000 comment; contracts with mutation checks; client: spend fired at presentation with the open token, sign all clips up front, await stored result in _finish; M-2 MockClient RPC test; M-3 single boundary convention; M-4 contract precision. — view-once privacy is a hard rule — cost: one more migration + task.
- Task 6: review (sonnet) Approved. Important (a11y): label bakes 'Double tap to retry' (double announcement) → round 1 = button semantics label 'Streak not sent' + onTapHint 'Retry'; read-only (null onRetry) copy 'Not sent'; larger hit target. Ruling: fix now — accessibility is first-class — cost: none.
- Ruling: I-1 via a new `first_read_at` column as the window anchor (COALESCE(viewed_at, first_read_at)) in the read RPC, table policy, storage policy, spend RPC, sweep and the Dart util — keeps "Opened" an honest presentation receipt — cost: one column + five touch points in the undeployed 140100 migration.
- Ruling: round 1 = I-1 + M-1 (spend on an unattached streak charges nothing) + M-2 (pop after ~2 s; retry settles in background). M-3 → owner deploy pre-check query; M-4 → owner call.
- Ruling: storage policy recipient branch also requires the window to have started (first_read_at IS NOT NULL OR viewed_at IS NOT NULL) — closes the raw-key path; dev has only the owner's two test accounts, so old-client loss costs nothing now — OWNER FLAG for production: clients older than the Task 5 read RPC lose streak playback until updated (ship with/after a forced update).
- Ruling: window anchor = LEAST(viewed_at, first_read_at) (strictly the first read) in all five places — closes the ~1 h stretch — cost: none.
- Ruling: double-tap in-flight guard in message_bubble streak onTap done now by the 5b agent (file currently free) — closes the two-viewers double spend — cost: none.
- Task 7: review (opus) → Needs fixes: I-1 partner's new game invite now silent (receive fold skips game cards; first sight = baseline). chat_screen.dart collateral check CLEAN. Minors M-1 baseline guards not fully redundant (comment the path), M-2 double haptic in one frame, M-3 one tap after offline open (accept), M-4 real-time waits. Ruling: round 1 = I-1 + M-1 comment + M-2 single haptic + M-4 deflake; M-3 accepted (device note).
- Task 6: fix round 1 DONE (report section; semantics 'Streak not sent' + onTapHint 'Retry'; read-only copy 'Not sent'; _MinHitTarget 44 px with no layout growth; RED→GREEN; 50 pass). Ruling: accepted without a further review — three small a11y items specified exactly by the review, each RED→GREEN — cost if wrong: a cosmetic issue on device.
- Final: Ruling: fix wave takes I-1, M-1..M-3 + every carried item (final-fix-list.md, 15 items) — owner wants everything — cost if wrong: one scoped re-review.
- Final: Ruling: M-2 — moved game cards don't count toward the "N new" pill (activity, not a new message); new invites do — cost if wrong: owner may want moves counted.
- Final: Ruling: B-1 fixed by the controller directly (two lines + one field) without another review — exact fix specified by the re-review, RED→GREEN — cost if wrong: none.

**Deferred minors**


