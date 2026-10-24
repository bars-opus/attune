# Reviewer 6: product standard, UX polish and Checklist v3.1 (Stories)

## 1. Verdict

The backend is strong. The privacy model (RPC-only writes, private `viewed_at`, keyset reads, intent and finalize, fail-closed flag), the SQL contracts and the outbox state machine would hold up next to Snapchat, Instagram or WhatsApp. The client reel and posting experience do not yet meet that standard. I reproduced two defects with scratch probe tests:
- **Deleting a story from a calendar day reel desyncs the reel.** The deleted photo stays on screen. A second "Delete" permanently removes a different story the person never saw.
- **A first item that fails to load re-requests a signed URL every frame**, about 60 calls a second.

Four more issues break the standard. An offline post gives up after about 30 seconds and never retries by itself. The poster can never see "Seen", although the spec promises it. A shutter tap posts with no preview. The poster's own reel has no delete. Images start their 5-second timer, and are marked seen, before they have loaded. The checklist grade is **C+ (about 6.8/10)**. The feature does **not** pass the P0-U gate. For Stories itself, the blocker is 2.5 (the unbounded retry loop). Project-wide, 2.3, 7.1 and 7.3 also fail.

## 2. What is solid (evidence)

- **Security and privacy.** All 10 story SQL contract files hold on `attune_spec3a` (section C.6). Clients have SELECT only. Writes go through `SECURITY DEFINER` RPCs. `story_views.viewed_at` is unreadable. Reads are `SECURITY INVOKER`, so RLS stays the authority. There is no dynamic SQL in any `*stor*` migration (grep for `EXECUTE ` finds only grants).
- **Idempotent posting.** `client_story_id` is unique per author (`20260938010000_stories_schema.sql:63`). The outbox has bounded, jittered backoff (`story_outbox_controller.dart:409-411`). Permanent codes are not retried (`:399`). A failed post has a visible Retry or Discard (`story_rings_row.dart:342-380`).
- **Reel engineering.** A generation token guards every await (`story_reel_screen.dart:404,440,466`). Pause has two separate causes, a held finger and the app lifecycle (`:273-292,615-647`). There is a double-advance race test, keyset paging past page 50 (`:740-774`), and viewed segments render faded, not skipped.
- **Accessibility groundwork.** Ring tap targets are 48dp (`story_ring.dart:378`). Ring semantics are separated from the `+` badge (`:258-276,387-399`). Viewed arcs are thinner as well as fainter (WCAG 1.4.1, `story_ring.dart:582`). The reel has Semantics actions for next, previous and dismiss (`story_reel_screen.dart:1551-1575`) and announces "Story n of m" (`:430-435`). Ring motion respects reduce-motion (`story_ring.dart:434`). The ring goldens pass in light and dark.
- **Memories.** Expiry hides a story from the reel only. The calendar day row and day reel play expired items without recording a view (`story_reel_screen.dart:665-668`). A source-level wiring test guards the calendar row.
- **Tests.** `flutter test test/features/stories` plus the three timeline story tests and Together `memory_sheets_test`: **169 passed, 0 failed**. The coverage run, which adds `couple_map/story_reel_places_test`: **171 passed**. `flutter analyze` on the story code: no issues.

---

## A. Standards comparison: private two-person story

Severity is the size of the gap for a couple app. "Build" or "Skip" is my recommendation, checked against the permanent constraints and STORIES §7/§8. §7 rules out reactions, view counts beyond seen or not seen, highlights, chat trails, push on post and video downscaling. **§7 says nothing about creative tools**, so the skips below are product calls, not spec rulings.

| Area | Attune today (evidence) | Snapchat / Instagram / WhatsApp | Gap | Recommendation |
|---|---|---|---|---|
| Photo capture | Tap for photo, `takePicture()`, with a 300ms tap/hold split (`capture_camera_screen.dart:166,464-475`) | All three: tap for photo | None | Done |
| Video length | Hold for video, up to 60s, hands-free lock (`capture_camera_screen.dart:587`, spec §8) | SC 60s; IG 60s per segment; WA about 60s | None | Done |
| Front/back camera | Flip, also works mid-recording (`capture_camera_screen.dart:850`), but no accessible label | All three | Low (a11y) | Add a tooltip (finding 12) |
| Flash | None | All three: back flash plus front "screen flash" | Medium | **Build** in the shared camera (flag the streak regression risk; additive control) |
| Zoom | None (no pinch, no slide-while-holding) | All three: pinch, and slide up while recording | Low | **Build** pinch-zoom (cheap, shared module) |
| Gallery upload | None. Images come only from the in-app camera | All three allow camera-roll upload | Medium | **Build**, as "post a recent photo". Note `occurred_on` is the posting date (§3.5), so the copy must say it posts today |
| Text caption | None | All three | Medium | **Build** a plain text caption: one optional line, stored as data, not burned into pixels. It is the cheapest warmth win |
| Drawing / stickers / filters / music | None | SC and IG: all; WA: draw, stickers, text | Low for a two-person ambient record | **Skip** for now: cost, plus music licensing. Revisit drawing later |
| Pre-post review | **None. A capture posts as soon as the shutter is released** (`story_camera_screen.dart:174-251`; comment at `:378-379`: "the outbox queue is the review") | All three show a preview with Send/Discard | **High** (finding 5) | **Build** a review step: preview plus "Share to {partner}" / retake |
| Posting progress | Pending ring with a coarse 4-step progress and a spinning arc (`story_rings_row.dart:54-67`; `story_ring.dart:408-475`) | IG/WA: posting ring; SC: "Sending…" | None | Done |
| Posting failure / retry | Notice row with Retry/Discard (`story_rings_row.dart:342-380`). **Gives up after 5 tries, about 30s offline, with no auto-retry when the connection returns** (finding 3). Discard needs no confirmation (finding 14) | IG/WA: keep retrying until online; tap to retry | High | Fix (findings 3, 14) |
| Multiple items | Unlimited. Segmented ring capped at 12 arcs; reel pages of 50 | All three | None (finding 20 is a small arc-order nit) | Done |
| Ring states | Mine: empty with "+", posting, has stories. Partner: hidden when empty; bright or faded for unseen or seen. Failed: notice row | IG/WA: unseen gradient, seen grey, posting, failed red | None | Done. Consider a name label under each ring (finding 24) |
| Reel gestures | Tap right/left, hold to pause (200ms), swipe-down dismiss (threshold only; the card does not follow the finger) (`story_reel_screen.dart:1508-1590`) | Same, plus the card follows the drag; hold hides the UI | Low (finding 18) | Polish |
| Progress bars / auto-advance | Segmented bars; 5s per image; videos run their length. **The timer starts before the image has loaded** (finding 6). **Dark-mode fill is #121212 on black** (finding 10) | All three; the timer waits for the media | Medium | Fix (6, 10) |
| Who / when header | **None.** The reel shows no author and no "3h ago". A day reel mixes both partners with no label (`_ReelBody`, `:1253-1376`) | All three show poster name and relative time | Medium (finding 8) | **Build** |
| Mute / sound | No mute toggle. Video always plays sound. iOS silent-switch behaviour unverified (finding 25) | IG: mute toggle and respects silent switch; WA/SC similar | Medium | **Build** a mute toggle; verify the silent switch on device |
| Captions / alt text | None (no caption data exists) | IG has auto-captions for speech | Low | Skip until text captions exist |
| Replies | Text reply composer on partner items; the trigger validates and normalises it to "Photo story"/"Video story". Bypasses the chat outbox (`story_reel_screen.dart:1055-1063` calls `sendTextMessage`, a direct insert). The reply bubble has **no thumbnail**, and tapping it opens the day reel at item 1, **not the replied story** (finding 15) | IG/WA: the reply bubble shows the story thumbnail; a tap opens that exact story | Medium | Fix (15) |
| Quick reactions | None (§7: "No reactions") | IG/WA: one-tap emoji reactions on a story | Medium for a couple app (low-effort warmth) | **Owner decision.** I recommend a row of 4–6 quick emoji that sends a normal story-reply message: no counter, no metric, same trigger path. This keeps §7's intent (no counts, no pressure) and every permanent constraint. If the owner keeps §7 literally, skip |
| Seen indicator to poster | **None.** `StoryItem.hasBeenViewed` is fetched but never rendered for the author; my ring and my calendar ring draw every segment bright (`story_rings_row.dart:161`, `calendar_day_sheet.dart:313`). Spec §5.2 line 681 promises "The poster's own reel shows whether each item has been seen" | WA/IG: "Seen by" per item; SC: viewer list | **High** (finding 4) | **Build** a per-item "Seen" / "Not seen yet" chip in the poster's reel (boolean only, never a time) |
| Delete own item | **Only from a calendar day reel.** The poster's own active reel has no delete (`story_reel_screen.dart:1146-1148`: `perItemAuthor` is false for the author reel). The day-reel delete has the Critical desync (finding 1) | All three: delete from your own story viewer | **High / Critical** | Fix (1, 5) |
| Save to camera roll | None, and the capture is never saved locally after posting | IG/SC: save your own story; WA: no | Medium | **Build** "Save" for **own items only**. Saving the partner's item: skip, or owner decision (consent) |
| Expiry and after | Expires from the reel at 24h by server time; stays forever in the calendar (day row plus day reel, expired playback, no view recorded) | SC Memories / IG Archive: private archive, opt-in | **Attune is ahead** | Consider showing past stories in Together "On this day" (it currently reads no `story_items`) |
| Push when partner posts | None (§7/§8) | WA: none; IG/SC: optional, off by default | None | **Skip** (consistent with §7: ambient, no pressure) |
| Screenshot notice | None. `screenshot_detection_service.dart` exists but is used only by the ephemeral viewer | SC notifies; IG/WA don't | None | **Skip.** Stories are permanent in the calendar and exportable, so a screenshot alert adds surveillance pressure and protects nothing (and is unreliable on Android) |
| Accessibility | Good ring and reel semantics. But images auto-advance with no way to pause for screen-reader users (finding 11), the shutter has no label (finding 12), and there is no l10n (finding 19) | IG: VoiceOver pauses autoplay; labelled controls | Medium | Fix (11, 12, 19) |

---

## B. UX polish across the feature

| Area | State | Evidence / notes |
|---|---|---|
| Motion (M3, `lib/core/ui/motion`) | Partial | The ring row uses `SettleIn` (`conversations_screen.dart:124-127`). The pending ring spins and respects reduce-motion. The reel opens with a plain `MaterialPageRoute` (`conversations_screen.dart:256-266`): no zoom or hero from the ring, the swipe-down does not follow the finger (`story_reel_screen.dart:1581-1590`), images pop in with no fade (`:1650`), and there is no tap feedback on the rings (`story_ring.dart:271` is a bare `GestureDetector`). Finding 18 |
| Reduce motion | Pass | `reduceMotionOf` on the ring (`story_ring.dart:165,236`). Reel progress stops animating under `disableAnimations` (`story_reel_screen.dart:578-607`). It reads `MediaQuery` directly, which is equivalent to `reduceMotionOf` (`reduce_motion.dart`) |
| Haptics (`hapticsProvider`) | Camera only | Camera: selection when recording starts and medium on lock (`capture_camera_screen.dart:383,393,916`). No haptic on post success or failure, hold-to-pause, delete, or reply sent. Finding 24 (Low) |
| Sounds | None | The story adapter plays no sounds (spec §6 says "each owns its own sounds"). Acceptable for an ambient feature; a soft "posted" cue is optional |
| Empty states | Pass (by design) | Partner ring hidden when empty (§5.1); my ring shows "+"; the calendar row is hidden on empty days; the reel says "No stories to show." Odd case: tapping my ring while only a pending post exists opens that empty reel (finding 17) |
| Loading | Adequate | The ring summary shows an empty ring while loading (deliberate, so "+" is never hidden), but the partner ring pops in and the row shifts. The reel shows a white spinner. Thumbnails use a surface-colour placeholder (`story_ring.dart:320`) and flash on every refetch (finding 16) |
| Error copy | Plain but not warm or actionable | "Your story could not be posted." (`story_rings_row.dart:361`): no reason and no "it's saved on your phone". "That could not be posted." (`story_camera_screen.dart:275`). "Couldn't load this story." has no Retry (`story_reel_screen.dart:1718`). "Could not delete this story." (`:924`). The camera permission text says "**streak**" in the story flow and is a dead end (finding 13). Finding 19 |
| Dark mode | One bug | Ring goldens pass in both themes. **The reel progress fill uses `onPrimary`, which is `#121212` in dark mode** (`story_progress_bars.dart:67`, `app_colors.dart:95`, `app_theme.dart:261`), on a black background (finding 10) |
| Large text | Pass | The ring row is icon-only at a fixed height. The failed notice wraps in an `Expanded` (`story_rings_row.dart:359`). Reel text is minimal. The day row has a 48dp minimum height |
| RTL | N/A today | The app ships de/en/es/fr/it/pt (`lib/i10n`), with no RTL locale. If one is added: tap zones are physical (`story_reel_screen.dart:1525`), the bar fill uses `Alignment.centerLeft` (not directional), and the announcement is hard-coded `TextDirection.ltr` (`:433`) |
| iPad width | Pass | The ring row sits inside `AppContentWidth.padded` (`conversations_screen.dart:110-113`). The reel and camera are full-bleed, `BoxFit.contain` and cover-crop |
| Semantics | Mostly pass | Rings, `+`, reel actions, close, delete and remove-place tooltips are present, and a couple-map a11y test meets the tap-target and label guidelines for reel controls. Gaps: the shutter (`streak_record_button.dart`, no Semantics at all) and flip (`capture_camera_screen.dart:846-858`, no tooltip) have no label; the reel's "double-tap and hold to pause" hint is false (finding 11); "Your partner's stories" should use the partner's name (`calendar_day_sheet.dart:333`, couple-name wording rule) |
| Localisation | Fail (project-wide) | Every story string is hard-coded English; there is no `AppLocalizations` use in `lib/features/stories` |

---

## C. Algorithm Quality Review Checklist v3.1: whole Stories feature

Scope tags that apply: [ALL] [SERVICE] (RPCs, edge function) [ASYNC] (archival worker, cleanup cron) [MUTATION] [UI] [MOBILE]. Not applicable: [FIN], and [UI-WEB] (native only).

### C.1 P0-U (Universal Blocking)

| # | Result | Evidence |
|---|---|---|
| 1.4 Authorization at every access | PASS | RLS SELECT only; every mutation RPC checks membership plus ACTIVE/unarchived; storage policies are isolated. `story_security`, `story_rpc` and `story_storage_policy_isolation` contracts all hold |
| 1.5 Authentication | PASS | RPCs key on `auth.uid()`; anon EXECUTE is revoked (places contract P1); the worker uses `requireServiceRole` |
| 2.1 Input sanitization | PASS | DB CHECKs on dimensions, duration (500ms–60s; image NULL), 24h expiry and unique keys; finalize validates the stored object's MIME and size; `story_place_parse` drops malformed input (`20261017100000_story_places.sql`); label 1–120 chars |
| 2.2 Parameterized queries | PASS | No dynamic `EXECUTE` in any story migration; the client uses the RPC/PostgREST builders |
| 2.3 Constant-time secret compare | **FAIL** (shared, Low) | `requireServiceRole` uses `token !== requireEnv("SUPABASE_SERVICE_ROLE_KEY")` (`supabase/functions/_shared/attune_auth.ts:43`), which process-story-archival relies on (finding 22) |
| 2.4 Errors don't leak | PASS | RPCs raise generic codes (`UNAVAILABLE`, …); the worker returns only a 120-char error code; the client maps to `StoryApiError.message` |
| 2.5 Resource limits | **FAIL** | Server side passes: `p_limit` capped at 50, 120 intents/hour, 20 live intents, 25MB/5MB, archival batch `LEAST(...,200)`. **Client: unbounded per-frame retry loop** in the reel (finding 2; probe measured 61 sign calls in about 1s) |
| 2.7 No hardcoded secrets | PASS | None in story code or migrations; the cron key comes from `app_setting()` / Vault (`20260938130000`) |
| 2.8 Secrets from env/vault | PASS | `requireEnv`, Vault |
| 2.9 .env ignored | PASS | `.gitignore:37-42` |
| 2.10 Resources released | PASS | Video player, ticker, ended subscription and lifecycle listener disposed (`story_reel_screen.dart:1018-1028`); camera controller disposed; old player disposed on every item switch (`:398-402`) |
| 4.4 No PII in logs | PASS | Only `ChatLog.diagnostic`, debug-only (`chat_log.dart:43-45`); no coordinates, labels or names logged; the worker logs nothing |
| 5.5 No internal info in UI | PASS | All user copy is generic; no codes or ids shown |
| 7.1 Dependency scan | **FAIL** (project-wide) | `.github/workflows/tests.yml` runs analyze and tests only; there is no dependabot or audit |
| 7.2 Static analysis | PASS | `flutter analyze` on the story code: "No issues found"; CI fails on analyzer errors |
| 7.3 Secret scan | **FAIL** (project-wide) | No gitleaks or trufflehog in CI (a manual grep of story files finds nothing) |
| 7.5 TLS | PASS | Supabase HTTPS/WSS only; signed URLs are https |
| 2.19–2.21 | N/A | Not financial |

### C.2 P0-C (Contextual Blocking)

| # | Result | Evidence |
|---|---|---|
| 2.6 Output sanitization | PASS | No HTML or log output. Quote text is server-overwritten to "Photo story"/"Video story" (§5.4 trigger). The place label is rendered as a Flutter `Text` (no injection surface) |
| 7.6 CSRF/CORS | N/A | Native mobile only; the worker is service-role and cron-invoked |

### C.3 P1 (High)

| # | Result | Evidence |
|---|---|---|
| 1.1 Idempotency keys | PASS | `client_story_id` unique `(author_id, client_story_id)`; reply `client_message_id` |
| 1.2 Timeouts | PARTIAL | Client: 30s on every gateway call (`story_read_repository.dart:397-405`). Worker: no timeout on storage download, transform or upload (`process-story-archival/index.ts`) (finding 23) |
| 1.6 Concurrency documented | PASS | Generation epochs, mounted guards, flush coalescing (`story_outbox_controller.dart:170-197`), finalize race fix migration. *But see finding 1: list mutation during viewing is not handled* |
| 1.10 Compensating paths | PASS | Expired intent leads to re-intent and re-upload (`story_outbox_controller.dart:390-403`); orphan cleanup queues objects; the hard-delete trigger enqueues storage |
| 1.11 Privacy assessed | PASS | Private `viewed_at`, boolean-only exposure, per-post opt-in place, retention "forever unless deleted" stated (§7), export and deletion covered |
| 2.11 Connection pooling | PASS | Single `SupabaseClient`; one channel per relationship, reused (`watchChangeSignal`) |
| 2.12 Bounded tasks | PASS | One flush at a time plus one queued; one preload per item |
| 2.13 Cleanup on cancel | PASS | Generation check after every await; player disposed if it arrives late (`story_reel_screen.dart:466-469`) |
| 2.14 Memory bounded | PASS | Pages accumulate only as the viewer advances; `_markedItemIds` lives per screen; no cache maps |
| 2.15 Cooperative yielding | PASS | No CPU loops; the ticker runs every 100ms |
| 2.16 Shared state protected | PASS (with gap) | Async races are guarded, but the index-based current item goes out of sync when the list changes (finding 1) |
| 2.18 Idempotent mutations | PASS | Finalize retry returns one story; `mark_story_viewed` repeat is a no-op (seen-state contract); delete is tombstoned |
| 3.10 No retry on permanent errors | **FAIL** | The outbox passes (`:399`). **The reel retries a permanently missing or undecodable first item every frame** (finding 2) |
| 3.12 Graceful shutdown | N/A | Short-lived edge function; mobile lifecycle handled (pause/resume) |
| 6.1 Edge cases | PASS | ±840 offset and midnight tests (SQL); 12-segment cap; unviewed clamp; empty partner ring; page 51 |
| 6.3 Concurrency tested | PASS | `raceAdvanceForTest`, concurrent flush, finalize race (SQL) |
| 6.4 Negative tests | PARTIAL | Good: failed media does not mark viewed; a refused store write does not pop. Missing: delete mid-list (finding 1), a failing first item does not loop (finding 2), an image that fails to load does not mark viewed (finding 6) |
| 7.4 Least privilege | PASS | Column-level grants, helper grants revoked, places table SELECT only |
| 7.7 Continuous security scan | **FAIL** (project-wide) | No scanner in CI |
| 8.1 Rollback | PARTIAL | Server-side `stories` flag is fail-closed (§8) and can be flipped off; no written rollback runbook found for the story migrations or worker |
| 8.2 Prod smoke tests | NOT EVIDENCED | No automated prod smoke; manual two-device test is pending per project memory |
| 2.22 | N/A | Not financial |

### C.4 P2 (Medium)

| # | Result | Evidence |
|---|---|---|
| 1.3 Graceful degradation | PASS | Ring renders without the summary; the flag gates new intents only; maintenance failure affects cost, never expiry (§12) |
| 1.7 Stateless / affinity | PASS | Server state in the DB; client outbox durable and encrypted |
| 1.8 Complexity documented | PARTIAL | Paging bounds documented (§5.5); no explicit Big-O notes |
| 1.9 Consistency model | PASS | "Realtime is a refetch signal, canonical reads" (§5.5) |
| 2.17 Side effects isolated | PASS | Gateways are abstract; reel player behind `StoryItemPlayer` |
| 3.1 Pagination | PASS | Keyset, capped at 50 |
| 3.2 No N+1 | PASS (mostly) | Ring summary is one RPC. The reel signs each item's URL on demand (expected) |
| 3.3 Indexes | PASS | `idx_story_reel (relationship_id, author_id, created_at, id) WHERE deleted_at IS NULL`; `idx_story_calendar`; places indexes. The places contract shows `Index Scan using story_places_author_idx` |
| 3.4 Cache strategy | PARTIAL | "Never cache signed URLs" is documented, but its side effects are not: the preload is wasted (finding 7) and thumbnails re-download (finding 16) |
| 3.7 Backpressure | PASS | Intent caps; worker batch cap |
| 3.8 Rate limiting tested | PASS | `RATE_LIMITED` path in the RPC contracts; the client treats it as retryable |
| 3.9 Backoff + jitter | PARTIAL | Outbox: equal jitter, 1–64s. But the async budget stops after 5 attempts (about 30s) with no connectivity or resume trigger (finding 3), and the reel loop has no backoff (finding 2) |
| 4.1 Structured logs | FAIL | The worker emits no logs; the client logs only debug output |
| 4.2 Correlation ID | N/A / FAIL | None. `client_story_id` could serve |
| 4.5 Log levels | N/A | Almost no logging |
| 4.6 / 4.7 RED / resource metrics | PARTIAL | §12 says the processing and deletion queues expose backlog age and failure metrics (maintenance contracts hold); no dashboard evidence |
| 4.9 / 4.10 Alerts + tested | NOT EVIDENCED | Queue-age alert described (§11 step 11); no alert config or runbook found |
| 4.11 Configurable thresholds | PARTIAL | Named constants (`kStoryImageHoldDuration`, `_maxAutomaticAttempts`, TTL 600s), but hard-coded |
| 4.12 / 4.13 Health / readiness | N/A | No long-running service |
| 5.1 Actionable errors | FAIL | No reason or next step on most errors (finding 19); the permission text names the wrong feature with no Settings link (finding 13) |
| 5.2 First feedback ≤ 200ms | PASS | Spinner on reel open; pending ring immediately on capture |
| 6.2 Failure scenarios tested | PASS | Network, keystore unavailable, expired intent, lost finalize, rejected transcode |
| 6.7 Coverage | **FAIL** | Branch coverage is not emitted by the Dart VM here (BRF 0). Line coverage across story files is **78% (1429/1828)**. Adapters are below 70%: `story_read_repository.dart` 16% and `story_repository.dart` 21%, because the gateways are faked. Reel 85%, outbox controller 95%, ring 95% |
| 6.9–6.12 Benchmark / soak / load / chaos | NOT EVIDENCED | None for stories |
| 6.13 Documentation | PASS (with drift) | STORIES.md is thorough. §13 says `story_change_signals` was never published, but `20261018130500` fixed that; §5.2's seen-indicator claim is untrue (finding 21) |
| 6.14 Runbooks | FAIL | None found for archival or deletion queue alerts |
| 8.3 / 8.4 / 9.2 | NOT EVIDENCED | Post-deploy metrics; the checklist changelog has not been updated since 2026-05-21 |
| 2.23 | N/A | |

### C.5 P3 (noted)

Mutation testing was used during the build (§5.1 notes two bugs caught that way). There are no property tests. A DLQ exists for archival (`fail_story_archival`, plus the dead-letter fix migration `20260938140000`). Accessibility (5.6) is partial: findings 11 and 12. Progressive loading (5.3): the reel shows a spinner, and images have no progressive or placeholder thumbnail even though the thumbnail is already fetched for the ring.

### C.6 Testing evidence (run 2026-10-23)

- **Flutter.** `flutter test test/features/stories test/features/timeline/calendar_day_sheet_empty_test.dart test/features/timeline/calendar_all_months_test.dart test/features/timeline/calendar_day_indicators_test.dart test/features/together/memory_sheets_test.dart`: **+169, all passed, exit 0**. The coverage run adds `couple_map/story_reel_places_test.dart`: **+171, all passed**. `test/features/stories/failures/*.png` are stale, git-ignored golden diffs from 2026-09-19; the goldens pass now.
- **SQL on `attune_spec3a`**, using `psql -X -v ON_ERROR_STOP=1 -f`; every file ends in ROLLBACK:

| File | As shipped | Diagnosis |
|---|---|---|
| story_maintenance | held | |
| story_reply | held | |
| story_rpc | held | |
| story_schema | held | |
| story_seen_state | held | |
| story_storage_policy_isolation | held | |
| together_story | held | |
| story_read | `users_phone_key` duplicate +15559990001 | **Fixture collision**: scratch rows `b2000000-…000a…d` from another suite already hold those phones. A scratchpad copy with remapped phones: **"all six contracts held"** |
| story_security | same duplicate phone | Same collision. Remapped copy: **"all held"** |
| story_places | `CONTRACT VIOLATED: clients can write story_places directly` | **Harness artefact, not production.** The scratch DB's blanket `local_pg_grants.sql` (`GRANT … ON ALL TABLES … TO authenticated`) runs after migrations and overrides `REVOKE ALL` / `GRANT SELECT` at `20261017100000_story_places.sql:19-20`. RLS has only a SELECT policy, so writes would still be refused. A scratchpad copy that re-applies the migration's grants inside the transaction **held every check** (finding 26: the contract is red on every local run, which hides real regressions) |

- **Scratch probes** (in my scratchpad, not the repo): `reel_loop_probe_test.dart` reproduced finding 2 with **61 `signMediaUrl` calls in about 1s**. `reel_delete_probe_test.dart` reproduced finding 1: after deleting A, the screen still shows A; a second Delete removes **B**; the reel then plays B's (deleted) media.

### C.7 Grade

| Dimension | Score | Why |
|---|---|---|
| Secure | 8.5 | Exemplary RLS/RPC model; deductions for 2.3 and no CI scanners (project-wide) |
| Robust | 6 | Delete desync (data loss), reel hot loop, offline give-up |
| Scalable | 8 | Keyset, caps, indexes; wasted preload and thumbnail re-downloads |
| Maintainable | 8 | Excellent docs; spec drift; low adapter coverage |
| Observable | 5 | Worker silent; no alerts or runbooks evidenced |
| User-aware | 5.5 | Standard-breaking gaps: seen, review, own delete, who/when, a11y |

**Overall: C+ (about 6.8/10).** It does not pass the P0-U gate (2.5 story-specific; 2.3, 7.1 and 7.3 project-wide) or the P1 gate (3.10; partial 6.4).

---

## 3. Findings

| # | Issue | Sev | Evidence (file:line) | Scenario | Fix design |
|---|---|---|---|---|---|
| 1 | Deleting a story in a calendar day reel desyncs the reel by index. The deleted media stays on screen, delete and reply target a different story, and the ticker advances on the stale list | **Critical** | `story_reel_screen.dart:944-964` (no restart unless it was the last item), `:1136-1154` (`currentItem = items[_index]` from the *new* list), `:564-597` (ticker holds the *old* `items`), `:707-713`. Probe output above | A person opens yesterday's 3 stories and deletes the first. The same photo is still showing, so they think it failed and tap Delete again. Story **B**, which they never saw, is permanently deleted, and the reel then plays B's deleted media. The same root cause: if the partner deletes an item while the viewer is watching (signal refetch), a reply attaches to the wrong story | Track the current item by **id**, not index. In `build`, re-resolve `_index` from `_currentItemId` whenever `items` changes. If the id has vanished, call `_startItem(items, min(oldIndex, len-1))` (or close if empty), as `_stepOffPlaceItem` already does for places (`:1007-1016`). Pass `currentItem.id` into delete and reply from the media actually showing. Add a widget test: delete the first of three, then assert the media and the delete target are B |
| 2 | A first item that fails to sign or initialise re-starts every frame (hot loop) | High | `story_reel_screen.dart:1131-1135` (auto-start condition `_index==0 && !_loadingItem && !_rendered && _player==null` is true again after a failure), `:442-451`, `:457-465` | Offline, or the first story's object is missing or archived. The partner opens the ring and the app calls Storage about 60 times a second; for a video it builds a new `VideoPlayerController` each time. The screen flickers between spinner and broken glyph, drains the battery and can hit Storage rate limits | Use a one-shot `_autoStarted` flag instead of state inference. On a load failure, set `_itemFailed` and show "Couldn't load this one. Tap to skip / Retry". Auto-skip after N seconds with backoff, never per frame |
| 3 | Offline posting gives up after about 30s, with no retry on connectivity or resume, and restart skips it | High | `story_outbox_controller.dart:112` (5 attempts), `:409-411` (1–16s windows), `:399` (permanent at the ceiling), `:180` (flush skips `failedPermanent`). The doc at `:166` claims "a connectivity-restored listener"; none exists (`grep connectivity lib/features/stories`) | Someone posts on the underground. Within about 30s the ring shows "Your story could not be posted." When signal returns, nothing happens, and even an app restart does not retry. This breaks §12 acceptance 1 ("posts exactly once after connectivity returns") | Treat network errors as never-permanent for the async queue: cap the backoff at 6h (checklist 3.9), with no attempt ceiling for `network`. Flush on connectivity-restored (the chat outbox's listener) and on `AppLifecycleListener.onResume`. Keep the attempt ceiling only for `RATE_LIMITED` and finalize `UNAVAILABLE`. Copy: "Waiting for a connection. We'll post it." |
| 4 | Poster has no "Seen" indicator anywhere | High | `story_read_repository.dart` `StoryItem.hasBeenViewed` (author meaning: the partner saw it) is never read by the reel; `story_rings_row.dart:161` and `calendar_day_sheet.dart:313` force mine all-bright. Spec §5.2 line 681 promises it | A person posts a photo for their partner and has no way to know whether it was seen. That is the one metric a two-person story has, and every reference app shows it | In the own reel and own day items, render a small chip from `hasBeenViewed`: "Seen" / "Not seen yet". Boolean only, never a time (keeps §3.4). Optionally fade my ring segments once the partner has seen them. Add a widget test |
| 5 | No pre-post review, and no delete in the poster's own active reel | High | `story_camera_screen.dart:174-251` (capture → `confirmSend` → enqueue → pop), `:378-379`; `story_reel_screen.dart:1146-1148` (`canDeleteCurrent` needs `perItemAuthor`, false for the author reel) | A person taps the shutter by accident, or takes a bad shot. It is instantly shared with the partner. Opening their own ring to remove it shows no delete; they must find the date in the calendar | (a) Add a review step in the story adapter (`isReviewing: true` on the embedded camera plus a preview with "Share" / retake), so the outbox is not the review. (b) Allow delete in the own active reel: `canDeleteCurrent = isAuthor` in every mode, reusing `_confirmAndDelete` *after* the finding 1 fix |
| 6 | Images are marked seen and the 5s timer starts before the image has loaded; a failed image load still marks seen | Medium | `story_reel_screen.dart:491-503` (`_rendered=true`, `_startTicker`, `_maybeMarkViewed` immediately after signing); `:1650-1654` (`Image.network` loads afterwards; `errorBuilder` is ignored) | On a slow connection the partner sees a blank screen for 4s and the photo for 1s, or never, and the poster's ring records "seen". This contradicts §5.2 "after … renders successfully" | Gate on the first frame: use `Image.network(frameBuilder:)` or resolve an `ImageStream` and start the ticker and mark viewed on the first `ImageInfo`. On `onError` show the failed state and don't mark viewed. Add a test with a failing image provider |
| 7 | Next-image preload is ineffective: it mints a different signed URL than the one later displayed | Medium | `story_reel_screen.dart:526-558` (preload: `signMediaUrl` → `precacheImage(NetworkImage(url))`); `:439` mints again on display; `story_read_repository.dart:545-555` never reuses a URL | Every image downloads twice (preload plus display), and the display still waits on the network. Reels feel slower than IG/WA on mobile data | Keep the preloaded URL in a screen-local `Map<itemId, (url, mintedAt)>` and use it if it is younger than about 9 minutes (under the 600s TTL, so §4.5's bound is unchanged). Or key the image cache by `mediaKey` (a custom `ImageProvider` key) |
| 8 | Reel shows no author and no time; the day reel mixes both partners unlabelled | Medium | `_ReelBody` `story_reel_screen.dart:1253-1376` (only bars, close, delete and reply) | In a calendar day with both partners' stories, a person cannot tell whose is whose, or when any of them was posted | Add a header under the bars: partner's name or "You" plus a relative time ("3h", or the time of day for calendar items), from `authorId` and `createdAt`. Use `MyDateFormat` (date format standard) and the couple-name wording rule |
| 9 | Video load failure shows a blank black screen; the reel error state has no Retry | Medium | `story_reel_screen.dart:1630-1646` (no player leads to a `ColoredBox` black, with no message); `:1707-1735` (`_ErrorState` is close only) | A video fails to initialise: black screen, frozen bar, no explanation. A failed page load offers only X | Use a shared `_ItemFailed` overlay ("Couldn't play this story", Retry / Next). Give `_ErrorState` a Retry that invalidates the pages provider |
| 10 | Progress bars are near-invisible in dark mode | Medium | `story_progress_bars.dart:67` (`fillColor: colorScheme.onPrimary`); `app_theme.dart:261` with `app_colors.dart:95` (dark `white` = `0xFF121212`) | In dark theme, the fill is near-black on a black reel over a 35% white track. Finished segments disappear, so the bars read backwards | The reel is always black, so use `Colors.white` for the fill (and white at 0.35 for the track), independent of theme. Add a dark-theme golden for the bars |
| 11 | Screen-reader users cannot pause auto-advancing images; the hint says they can | Medium | `story_reel_screen.dart:1566-1574` (hint "double-tap and hold to pause"; the `onLongPress` action calls start then end at once); no `MediaQuery.accessibleNavigation` check | A VoiceOver user is still hearing the controls when the photo moves on after 5s. They can never pause (WCAG 2.2.2) | When `MediaQuery.of(context).accessibleNavigation` is true, don't auto-advance images (wait for the next action). Make `onLongPress` toggle `_heldPaused`. Fix the hint text |
| 12 | Shutter and flip-camera have no accessible label (shared camera) | Medium | `streak_record_button.dart` (no `Semantics` anywhere); `capture_camera_screen.dart:846-858` (flip `IconButton` without `tooltip`) | A VoiceOver user cannot find or identify the capture button or the camera switch, in stories and streaks alike | Add `Semantics(button: true, label: 'Take photo, hold for video')` around the record button and `tooltip: 'Switch camera'`. **Regression risk:** shared with streaks, so keep `streak_camera_contract_test` green; the change is additive (semantics only) |
| 13 | Camera permission error says "streak" in the story flow, and is a dead end | Medium | `capture_camera_screen.dart:191-192` ('Attune needs camera access to record a **streak**.'), `:707-709` (bare `Scaffold` + `Text`, with no close or Settings) | A person who denied camera access taps "+" and sees streak copy, with no button to leave or fix it | Let the embedder pass the copy (destination-neutral module, §6). Add a close button and "Open Settings" (`app_settings` / `openAppSettings`). Include microphone wording for video |
| 14 | "Discard" on a failed story deletes the only copy, in one tap, next to Retry | Medium | `story_rings_row.dart:367-374` | A person aims for Retry, hits Discard, and the photo is gone. It was never saved to the camera roll | Confirm Discard ("Discard this photo? It hasn't been posted."), or use an undo SnackBar that delays the file delete. Show the capture's thumbnail in the notice so the person knows which one it is |
| 15 | A story reply opens the day reel at its first item, not the replied story; the quote shows no thumbnail | Medium | `message_bubble.dart:115-123` (`StoryReelScreen.forDay` with no start item); `:596-602` (text-only "Photo story") | A partner replies "haha" to the 4th story of the day. The poster taps the quote and must click through stories 1–3, with no thumbnail to say which story it was | Add `initialItemId` to `StoryReelScreen.forDay` and seek to it once loaded (page until found). Render the live thumbnail in the quote after `getReplyTarget` succeeds (§5.4 already allows this) |
| 16 | Ring thumbnail re-downloads and flashes on every summary refetch; the disk cache keeps one-off private URLs | Low | `story_ring.dart:315-324` (`CachedNetworkImage(imageUrl: url)` with no `cacheKey`); `story_rings_row.dart:249-251,308-310` (a new signed URL on each refetch, including every app resume) | Each return to the app makes the rings blink to grey before the photo reloads. Old thumbnails of deleted stories stay in the cache directory until eviction | Use `cacheKey: thumbnailKey` and `useOldImageOnUrlChange: true`. Evict the cache entry on delete; consider a short `stalePeriod` for the story cache (privacy) |
| 17 | Tapping my ring while only a pending post exists opens an empty reel | Low | `story_rings_row.dart:180` (`onTap` wired when `myPending != null`) leads to the reel's "No stories to show." | Right after posting the first ever story, a person taps their ring and gets an empty black screen | When `mySegmentCount == 0`, make a tap show a small "Posting…" toast, or preview the local file. Don't open the server reel |
| 18 | Reel motion polish | Low | `story_reel_screen.dart:1581-1590` (dismiss is threshold-only), `:1650` (no image fade), `conversations_screen.dart:256-266` (default page route), `story_ring.dart:271` (no press feedback) | The reel feels abrupt next to IG/WA: it doesn't follow the finger, has no zoom from the ring, and images pop in | Use a drag-follow translate and scale with spring-back (`MotionTokens`), a ring-to-reel fade or zoom route, a 150ms image fade, and a scale-press on rings. Gate all of it on reduce-motion. Hide the chrome while held |
| 19 | Error copy is terse and not actionable; no l10n | Low | `story_rings_row.dart:361`, `story_camera_screen.dart:242,275`, `story_reel_screen.dart:924,1080,1718`; no `AppLocalizations` in `lib/features/stories` while the app ships 6 locales | French users see English story UI. Failures don't say why or what happens next | Rewrite warmly and actionably ("No connection. We'll keep trying." / "Couldn't delete. Try again."). Extract to ARB along with the chat l10n gate item |
| 20 | Ring arcs don't follow chronology: bright (unseen) arcs are drawn first | Low | `story_ring.dart:613-616` (`i < unviewedCount` bright, from 12 o'clock) | Partner posts 3 and I've seen the oldest 2. The ring shows the *first* arc bright, the opposite of playback order (WA paints seen arcs first) | Paint `i < segmentCount - unviewedCount` faded, then the bright ones, so the arcs mirror oldest-first playback |
| 21 | Spec drift | Low | STORIES.md §13 (claims `story_change_signals` is unpublished; `20261018130500_story_signals_realtime.sql` publishes it); §5.2:681 (seen indicator, which is not built) | A future reviewer trusts the spec and misjudges the realtime and seen behaviour | Update §13 (resolved, cite the migration). Either build finding 4 or mark the §5.2 line as pending |
| 22 | Service-role check is not constant-time (checklist 2.3) | Low | `supabase/functions/_shared/attune_auth.ts:43` (`token !== requireEnv(...)`) | A theoretical timing oracle on the worker's auth. Practically remote, but a P0-U checklist failure for every service-role function | Compare SHA-256 digests with `crypto.subtle.timingSafeEqual` (Deno std `timingSafeEqual`). Shared file, so it affects all workers: run their tests |
| 23 | Archival worker has no fetch timeouts and no logs | Low | `supabase/functions/process-story-archival/index.ts` (download, transform and upload have no `AbortSignal`; no `console` output) | A hung storage transform holds the invocation until the platform kills it, the lease expires and the job retries, and nothing in the logs explains why | Per-call `AbortSignal.timeout(20_000)`. One structured JSON log per batch (`{processed, failed, codes}`) using story ids only |
| 24 | Small polish gaps | Low | No haptics on post, fail, hold or delete (grep finds no `hapticsProvider` in `lib/features/stories`); no name labels under rings (`story_rings_row.dart:206-219`); reply hint "Reply to story..." (`story_reel_screen.dart:1423`) | The feature feels less tactile and personal than the rest of the app | Light haptic on hold-pause and on post finalised, a warning haptic on failure. Optional "You" / partner name labels. Hint "Reply to {name}…" |
| 25 | Video sound has no mute toggle; iOS silent-switch behaviour unverified (**Needs verification**) | Medium | `story_reel_screen.dart:109-111` (`VideoPlayerController.networkUrl(uri)`, no `VideoPlayerOptions`, no volume control) | Someone opens their partner's video story in a quiet place and it plays aloud, possibly even with the ringer off (video_player's default iOS playback category) | Add a mute toggle (remembered per device) and respect the silent switch (start muted when the ringer is off, as IG does). Verify on device |
| 26 | `story_places` contract is red on every local run because of the harness blanket grant | Low | `supabase/tests/story_places_contracts.sql:47-54` against scratch `local_pg_grants.sql:19`; migration `20261017100000_story_places.sql:19-20` is correct | A real regression in the places grants would be indistinguishable from the always-red local run | Do what `stories_table_grants` and `story_reply_grants` do: move the places REVOKE/GRANT into a grants migration that the harness replays after its blanket grant. Or have the contract re-assert the migration grants under `BEGIN` before checking |

**Counts: Critical 1 · High 4 · Medium 11 · Low 10 (26 total).**

## 4. Checklist notes (summary)

- **P0-U:** PASS 1.4, 1.5, 2.1, 2.2, 2.4, 2.7, 2.8, 2.9, 2.10, 4.4, 5.5, 7.2, 7.5. FAIL 2.5 (finding 2, story-specific), 2.3 (finding 22, shared), 7.1 and 7.3 (no CI scanners, project-wide). N/A 2.19–2.21.
- **P0-C:** PASS 2.6. N/A 7.6.
- **P1:** FAIL 3.10 and 7.7. PARTIAL 1.2, 6.4, 8.1. Not evidenced 8.2. The rest pass.
- **P2:** FAIL 4.1, 5.1, 6.7 (adapters 16–21% line coverage; branch coverage unavailable), 6.14. Several are not evidenced (alerts, soak, load, chaos).
- **Grade C+ (about 6.8/10).** Clearing it needs findings 1, 2, 3 and 6 fixed with tests, plus the project-wide 2.3, 7.1 and 7.3.

## 5. Standards gap (two-person-relevant only; detail in section A)

Must have, matching all three apps: a seen indicator for the poster; a pre-post preview; delete from your own story viewer; the timer starting only once media has loaded; who and when on each item; a mute toggle; reliable offline posting that finishes when the connection returns; story replies that open the exact story, with a thumbnail.

Should have: gallery upload of recent media, a text caption, flash and pinch-zoom, saving your own story to the camera roll, and quick emoji replies (owner ruling against §7; I recommend them as reply messages, not counters).

Deliberately skip: push on post, screenshot notice, drawing, stickers, filters and music, and horizontal swipe between authors (there are only two rings).
