# Stories robustness review — 2026-10-23

Six parallel reviewers (posting, watching, rings, lifecycle and memories, security and privacy, standards and checklist), then two adversarial verifiers covering every Critical and High. Evidence, scenarios and fix designs: `docs/reviews/2026-10-23-stories-review/01…06`; verification: `07a_verification_client.md`, `07b_verification_server.md`. Read-only review; no code changed.

## Verdict

**The server is solid. The client is not yet at the Snapchat, Instagram or WhatsApp standard.** Nobody outside the couple can read, list, sign, forge, reply to or change a story, its media, its place or its seen state. Expiry is a single server-side `expires_at > now()` check, nothing is deleted on expiry, and expired stories still show and play from the calendar for both partners. The weak parts are on the phone:
- **The reel tracks the playing story by position, not identity.** That causes one Critical data-loss bug and several misdirected replies and deletes.
- **The outbox gives up on offline posts after about 30 seconds.**
- **The shared camera captures at 640×480.**
- **The app shell tears down the whole navigator every time the app goes inactive.** That includes Control Centre, a call, Face ID and permission prompts.

**Algorithm Quality Review Checklist v3.1:** fails gate P0-U on 2.5 (story-specific), 2.3, 7.1 and 7.3 (the last three are shared or project-wide), and fails P1 on 3.10, 2.16, 2.13 and mobile lifecycle. Overall about **C (6.3/10)**: Robust 5, User-aware 5, the remaining dimensions as reviewer 6 scored them.

**Tests today:**
- 169/169 Flutter tests for stories and timeline pass. Line coverage on story files is 78%, but the two repositories sit at 16–21%.
- 7/10 story SQL contracts pass as-is on `attune_spec3a`. The other 3 fail for harness reasons and pass once those are fixed:
  - `story_read` and `story_security`: duplicate fixture phone numbers;
  - `story_places`: the local grants script never replays its REVOKE.

**Counts after deduplication and verification:** 1 Critical, 19 High, about 40 Medium, about 45 Low. Nothing was refuted. Four were downgraded from High to Medium:
- seen chip;
- preload cache;
- open-at-oldest;
- Storage error classification.

One was upgraded from Medium to High: tapping the photo while typing a reply.

## Critical and High (verified)

| # | Issue | Sev | Where | Fix group |
|---|---|---|---|---|
| 1 | **Delete in a day or map reel leaves the deleted story on screen; a second Delete removes a story the person never saw** (both probes reproduced it) | Critical | `story_reel_screen.dart:943-948, 1135-1144` | R1 |
| 2 | Any refresh (partner deletes, oldest item expires, resume) shifts the index, so Reply, Delete and the progress bars target a different story | High | `:1136-1144, 472-475` | R1 |
| 3 | Tapping the photo while typing a reply navigates and un-pauses. The reel then auto-advances while they type, and the reply quotes the wrong story | High (from Medium) | `:417`, shared pause flag | R1 |
| 4 | Every change signal blanks the open reel and the day view to a spinner, and drops the reply keyboard | High | `story_providers.dart:239` | R2 |
| 5 | The last photo's ticker keeps popping after close. Coming from chat, calendar or the map, it pops **two** screens underneath, or any open dialog | High | `:589-598, 870-873` | R3 |
| 6 | If the first item fails to load, it restarts every frame (sign calls, new VideoPlayerControllers) | High | `:1130-1135, 444-465` | R4 |
| 7 | A photo is marked seen, and its 5 s timer starts, once its URL is signed, before any bytes arrive. A failed load still counts as seen (breaks spec §5.2) | High | `:492-503` | R4 |
| 8 | An author cannot delete from their own reel (only from the calendar). Ship only after R1 | High | `:1145-1148` | R5 |
| 9 | Tapping the centre of my own ring opens the camera (134 of 232 tap points) | High | `story_ring.dart:194-207` | K1 |
| 10 | An offline post goes permanently failed after about 23 s. Nothing retries on reconnect, resume or restart | High | `story_outbox_controller.dart:112, 180, 399` | P1 |
| 11 | An upload that times out is retried against the same key; the 409 is read as "network", so large videos on slow links never post | High (409 timing: device check) | `story_repository.dart:182-247` | P1 |
| 12 | Stories capture at 640×480 on iOS (`ResolutionPreset.medium`) | High | `capture_camera_screen.dart:201` | P3 |
| 13 | A denied microphone blocks photos too. The error says "streak" and has no way out | High | `:187-193, 205, 707` | P3 |
| 14 | No review before posting: the shutter shares at once (spec §6.1 by design; owner ruling) | High | `story_camera_screen.dart:164-176` | P4 |
| 15 | A full 60 s take is likely rejected as too long | High if a device confirms | `chat_video_preparer.dart:197, 235` | P3 |
| 16 | **The privacy cover and the safety lock swap out the whole Router** on inactive and on every resume. Story camera, reel and calendar reel close; chat loses its scroll, sheets and dialogs; a capture still preparing is dropped | High (core shell) | `app_privacy_cover.dart:63-70`, `safety_lock_gate.dart:71-73` | S1 |
| 17 | Export walks story media last, behind a 12-part cap. After an ending, export is the only way out, so stories are lost for couples with a lot of chat media | High | `20261018120000_data_export.sql:428-437`, `parts.ts:39` | D1 |
| 18 | The reel shows no author and no time; the day reel mixes both partners unlabelled | High by standard (Medium in 06) | reel overlay | R6 |
| 19 | Story outbox and capture files survive sign-out and quick exit, and are not excluded from backups (encrypted payload, so hygiene, not a breach) | Medium (kept) | `auth_provider.dart:157-235` | P2 |

## Fix plan (waves)

Each wave is test-first on main, then an opus review and a fix pass. Nothing is committed without the owner.

**Wave 1 — Reel (story viewer).** Fixes #1–8 and #18, plus these Mediums:
- seen chip for the poster;
- modal pause during dialogs;
- empty-after-refresh state;
- video failure UI with retry;
- the 50-item page boundary;
- reply idempotency and timeout;
- screen-reader pause;
- dark-mode progress bars;
- resume at the first unseen story, with watched segments faded;
- a story reply opens the replied story;
- quick exit not advancing the reel.

The groups:
- **R1:** track the current item by id; a separate composer pause.
- **R2:** keep data during refresh (`copyWithPrevious`).
- **R3:** one-shot completion and close latch.
- **R4:** a per-item load state; mark seen on first decoded frame; bounded retry.
- **R5:** own-reel delete (after R1).
- **R6:** author and time labels.

**Wave 2 — Posting.**
- **P1, outbox like chat's:**
  - network errors never count toward the cap;
  - flush on resume and reconnect;
  - classify Storage errors;
  - re-mint near expiry;
  - persist intents;
  - start the outbox at app level;
  - media in app-private storage;
  - cancel in flight;
  - confirm Discard.
- **P2:** wipe on sign-out, quick exit and account switch, and exclude from backups.
- **P3, shared camera:**
  - an embedder resolution (stories `veryHigh`, streaks unchanged);
  - fall back to no audio;
  - embedder error copy with Close and Settings;
  - accessibility labels;
  - lifecycle;
  - the 60 s tolerance.
  - Regression gate: `capture_camera_test` and `streak_camera_contract_test`.
- **P4:** a preview step (Share / Retake) in the story adapter only, and enqueue survives unmount.

**Wave 3 — App shell (S1).**
- Keep the child mounted behind the cover: `Offstage` + `TickerMode` + `ExcludeSemantics`. The PIN lock stays a full replacement.
- Audit media players and the camera so they pause themselves.
- Re-run the privacy-cover, safety-lock, quick-exit and Understand-sheet tests, and add a test that a pushed route survives inactive → resumed.

**Wave 4 — Rings and calendar.**
- **K1:** move the `+` hit box off the thumbnail.
- **E:** cache by storage key, not signed URL.
- **Ring:**
  - no flash back to `+` after posting;
  - expiry timer;
  - cold-start offline shows the last known state;
  - no sticky grey circle;
  - failed posts for other relationships surface.
- **Calendar:**
  - error and retry;
  - per-author rings open at the right item;
  - counts beyond page 1.

**Wave 5 — Server.**
- **D1:** stories first in export, and video extensions.
- **Archival:**
  - resize by long edge;
  - validate before swap;
  - higher throughput;
  - fetch timeouts;
  - state guard.
- **Story date:** `occurred_on` from capture time; time-zone safe.
- **Hardening:**
  - bucket size and MIME limits;
  - constant-time service-role compare (shared, so run every worker test);
  - lock down the `story_relationship_is_open` oracle;
  - intent rate-limit serialization.
- **After an ending:** a way for an author to list and delete their stories.
- **Harness:** fix the fixture phones and the grants replay.

**Later (standards adds; owner call):**
- gallery upload;
- text caption;
- flash and zoom;
- save my story to the phone;
- mute toggle;
- quick emoji replies sent as ordinary replies (spec §7 rules out reactions);
- CI dependency and secret scanning (project-wide P0-U 7.1/7.3).

## Owner rulings (recommended defaults, used unless overridden)

1. **Review before posting:** yes, Share / Retake, as all three reference apps do. This overrides spec §6.1.
2. **Delete from your own reel:** yes, after R1.
3. **Open at the first unseen story, with watched segments faded:** yes. This overrides STORIES.md:788's "open at oldest".
4. **Pause and End hide the whole story calendar for both partners:** keep the behaviour for now, and make the confirm copy say stories go too.
5. **Quick emoji replies:** not now.
6. **"Seen" shown to the poster:** build it as the spec says. It only shows when seen receipts are on.

## Standards gap (summary)

**Has today:**
- private, two-person;
- 24 h rings;
- a full-screen reel with hold to pause and tap to skip;
- replies into chat;
- seen state;
- a calendar memory afterwards. The memory is a differentiator; none of the three keep stories on a shared calendar.

**Missing against the references:**
- a review before posting;
- deleting your own story from the reel;
- name and time in the viewer;
- resuming where you left off;
- "Seen" shown to the poster;
- full-resolution capture;
- reliable offline posting;
- keeping your place through interruptions;
- gallery upload;
- captions;
- flash and zoom;
- saving to the phone;
- a mute button;
- stories in "On this day" and Our story.
