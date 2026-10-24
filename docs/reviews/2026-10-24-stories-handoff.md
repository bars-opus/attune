# Stories: handoff after the five-wave robustness program (2026-10-24)

Review: `docs/reviews/2026-10-23-stories-robustness-review.md` (evidence in `docs/reviews/2026-10-23-stories-review/`). Plans:
- `docs/superpowers/plans/2026-10-23-stories-wave1-reel.md`
- `docs/superpowers/plans/2026-10-23-stories-wave2-posting.md`
- `docs/superpowers/plans/2026-10-23-stories-wave3-app-shell.md`
- `docs/superpowers/plans/2026-10-23-stories-wave4-rings-calendar.md`
- `docs/superpowers/plans/2026-10-24-stories-wave5-server.md`

Each task was built test-first, reviewed and fixed until clean; each wave then had a whole-wave review and one fix pass. Ledgers (every ruling, verbatim): `.superpowers/sdd/2026-10-23-stories-wave{1-reel,2-posting,3-app-shell,4-rings-calendar}/progress.md` and `.superpowers/sdd/2026-10-24-stories-wave5-server/progress.md`.

**Nothing is committed or deployed.** Everything sits in main's working tree on top of your own uncommitted work. You commit and deploy.

The binding spec, `lib/architecture/STORIES.md`, now says what was built (Wave 5 Task 16 fixed the drift: retention, capture date, intent lifetimes, archival, monitoring that is not built, the after-an-ending path, export).

## What changed

### Wave 1 — Reel
- The reel follows the story on screen by its id. A refresh, a partner's delete or an expiry no longer moves Reply or Delete onto a different story, and a second Delete can no longer remove a story you never saw (the one Critical).
- A refresh keeps the story on screen: no spinner flash, and the reply keyboard stays up.
- The reel closes exactly once and never pops the screen underneath it.
- A story counts as seen only once the photo or video actually shows. A failed load shows Retry, with bounded retries and a 15 s limit on a video starting.
- You can delete from your own reel. The reel shows who posted and when, and the poster sees "Seen" when seen receipts are on.
- The reel opens at the first unseen story, with watched segments faded, and gives up looking after about 3 s.
- Typing a reply pauses the reel; dialogs pause it; quick exit never advances it. Dark-mode progress bars, a top scrim, and a Pause action for VoiceOver.
- Files: `story_reel_screen.dart`, `story_reel_header.dart` (new), `story_progress_bars.dart`, `story_providers.dart`, `message_bubble.dart`.

### Wave 2 — Posting
- An offline post waits and posts on reconnect, resume or restart. Only real refusals count toward the 5-strike cap.
- Uploads stream with byte progress and can be cancelled. Upload links are kept and re-made near expiry. A repeat upload that already landed counts as done.
- Share / Retake review before anything leaves the phone.
- Queued captures live in app-private storage per account, are excluded from backups, and are wiped on sign-out, quick exit and account switch. Nothing posts for an account that signed out.
- Camera: stories capture at full resolution (photos 1920 px long edge); a denied microphone still allows photos; clear error copy with Close and Open Settings; screen-reader labels; a take survives calls and Control Centre; a full 60 s take is accepted, and an oversize one is re-encoded at 960×540.
- Each failure says why, offers Retry only where it helps, and separates Cancel from Discard. A video that can't beat the connection stops with "too slow" instead of re-uploading forever.
- Chat (shared preparer): an untrimmed chat video now exports whole on Android, and real trims use a platform-aware helper.
- Files: `story_outbox_controller.dart`, `story_outbox_store.dart`, `story_outbox_record.dart`, `story_media_vault.dart` (new), `story_outbox_wipe.dart` (new), `story_outbox_triggers.dart` (new), `story_post_pipeline.dart` (new), `story_review_layer.dart` (new), `story_outbox_notices.dart`, `story_repository.dart`, `capture_camera_screen.dart`, `chat_video_preparer.dart`, `auth_provider.dart`, `safety_sign_out.dart`, `app.dart`, Android `backup_rules.xml` and `data_extraction_rules.xml`.

### Wave 3 — App shell
- The privacy cover and the lock's return check no longer tear down the app. Open screens, sheets, dialogs, scroll positions, drafts, the reel and the camera survive Control Centre, calls, Face ID and app switches.
- One "Attune is on screen" signal. Every player, camera, recorder, sound and read receipt stops while Attune is not on screen.
- The keyboard and its predictions never show over the cover or in the app-switcher snapshot.
- Couple-map presence sampling, the 36 Questions poll, the session-game wait, the partner presence poll and YouTube in Planning notes all stop behind the cover.
- A held voice note that is interrupted is locked and paused, never sent and never lost.
- Screens that only refreshed by being rebuilt (appreciation jar, wins, quiet state) refresh on return.
- A notification tapped while Attune is hidden waits like a locked one. The 36 Questions answer screen stays above the keyboard.
- Files: `keep_mounted_cover.dart` (new), `app_content_visibility.dart` (new), `visible_only_playback.dart` (new), `app_privacy_cover.dart`, `safety_lock_gate.dart`, `app_shell.dart`, the chat, streak, ephemeral, video and voice screens and controllers, `understand_sheet.dart`, `relationship_lifecycle_watcher.dart`.

### Wave 4 — Rings and calendar
- Tapping your ring's photo opens the reel; the `+` has its own 48 dp target.
- Thumbnails are cached by storage key, with one signed URL per key reused for up to 540 s, and removed when a story or a relationship goes.
- The ring never flashes back to `+` after posting and never sticks grey. A partner's ring clears when its story expires. A cold start offline shows the last-known rings.
- Failed posts for another relationship show as one notice with Discard.
- Calendar: a month error with Retry; each day ring opens its own author's stories at the right one; counts beyond the first 50.
- Quick exit and a pause, end or archive empty the whole shared image cache (ruling below).
- Files: `story_ring.dart`, `story_rings_row.dart`, `story_signed_url_cache.dart` (new), `story_ring_last_known_store.dart` (new), `story_ring_refresh.dart` (new), `story_posted_hold.dart` (new), `story_device_wipe.dart` (new), `story_day_rings.dart`, `story_read_repository.dart`, `story_month_load_error.dart` (new), `calendar_day_sheet.dart`, `calendar_strip.dart`, `calendar_day_indicators.dart`, `conversations_screen.dart`, `quick_exit_service.dart`, `relationship_lifecycle_providers.dart`.

### Wave 5 — Server
- Download my data walks your story media first, names story files `.jpg` or `.mp4`, and `media_not_included.txt` says how many stories did not fit. Exports in flight at deploy are restarted in the new order.
- Archival downsizes portrait photos by the long edge, checks each rendition before the swap, and runs every 5 minutes while work waits.
- A story is filed on the day it was taken (capture time, corrected for the phone's clock, clamped to the last 7 days). The 24-hour ring window still starts at posting.
- The bucket refuses files over 25 MB or not JPEG/MP4. The service-role check is constant-time (in `attune_auth.ts`, and now in `compute-pulse` and `generate-verdict`, which had their own `===` checks). The membership helper can no longer be used as an oracle. Upload-link limits are serialized per person, and video and thumbnail links last 60 minutes.
- The ring query has an index. The ring clears on the server's clock (`server_now`, `next_expires_at`). Day reads filter by author on the server, and day rings know per-author unseen counts.
- After an ending: Download my data → "Your stories from past chapters" lists your own stories from paused or ended spaces and deletes them (200 per call).
- Pause and End sheets say that stories close too; the manual says so.
- Every story SQL contract runs green as shipped (fixture phones, story_places grants replay).
- Files: 11 migrations (below), 8 new contracts, `_shared/attune_auth.ts`, `process-story-archival/archival.ts` (new) + `index.ts`, `build-data-exports/bundle.ts`, `scripts/local_pg_grants.sql`, `story_repository.dart`, `story_outbox_controller.dart`, `story_read_repository.dart`, `story_ring_refresh.dart`, `story_providers.dart`, `story_reel_screen.dart`, `story_day_rings.dart`, `calendar_day_sheet.dart`, `past_story_chapters_repository.dart` (new), `past_chapter_stories_screen.dart` (new), `data_export_screen.dart`, `pause_relationship_action.dart`, `end_relationship_action.dart`, `confirmation_dialog.dart` (shared), `relationship_lifecycle_docs.dart`, `privacy_data_docs.dart`.

Waves 1–4 have no migrations and no edge-function changes.

## Deploy, in this order

### 0. Pre-flight
Before pushing, check that production is missing exactly these 11 files and nothing else:
- `supabase migration list`: the remote column is empty for exactly the 11 files below, and every earlier local file is applied remotely. If an earlier file is missing remotely, or the remote has a version not in `supabase/migrations`, stop and sort that out first (`db push` would refuse with "insert before the last migration", or push more than this list).
- `supabase db push --dry-run`: lists exactly the 11 files below, in this order.

### 1. Migrations
`supabase db push` applies them in filename order. All are idempotent; the ones that need a transaction open and commit their own.

Four files set a 5 s `lock_timeout`, so they give up rather than queue app traffic behind a long transaction: `20261024100200` (policy swaps on `storage.objects` and three story tables), `20261024100400` (ring index), `20261024100600` (archival index) and `20261024100700` (`ALTER TABLE data_export_jobs`). Under load one may fail with `canceling statement due to lock timeout`. That is safe: the file rolls back whole (100400 is a single statement), nothing after it was applied, and re-running `supabase db push` resumes from that file. Re-run at a quieter moment if it repeats.

```
20261024100000_story_places_grants.sql
20261024100100_story_media_bucket_limits.sql
20261024100110_story_intent_hardening.sql
20261024100200_story_membership_for_me.sql   (5 s lock_timeout; if it times out, re-run the push)
20261024100300_story_capture_date.sql
20261024100400_story_ring_index.sql          (5 s lock_timeout; if it times out, re-run the push)
20261024100410_story_ring_summary_expiry.sql
20261024100500_story_day_reads_by_author.sql
20261024100600_story_archival_v2.sql         (new cron: invoke-story-archival, */5; 5 s lock_timeout; if it times out, re-run the push)
20261024100700_story_export_order.sql        (restarts in-flight exports; expect 0 to a few; 5 s lock_timeout; if it times out, re-run the push)
20261024100800_my_closed_story_items.sql
```

There is no `20261024100710`: the plan's "keep place pins until archive" was rejected (see Owner decisions).

### 2. PostgREST schema reload
Right after the push: `NOTIFY pgrst, 'reload schema';` (or Dashboard → API → Reload schema). Until it reloads, the re-created functions can answer `PGRST202`. Old clients keep working (every new parameter has a default). A new client falls back: a session that hit the window stops sending the capture time for 10 minutes (its stories in that time are filed on the posting date), then tries again. The past-chapters entry draws nothing until the reload.

### 3. Edge functions, right after the migrations
Deploy `process-story-archival` first, within the 5-minute cron cycle: it needs `skip_story_archival` and the new claim columns. (The old worker keeps working against the new SQL, but still resizes by width.)

The 18 service-role functions with the constant-time check: 16 that bundle `_shared/attune_auth.ts`, plus `compute-pulse` and `generate-verdict`, which now compare the service key with its `constantTimeEqual`:
```
supabase functions deploy process-story-archival build-data-exports \
  compute-pulse generate-verdict \
  activate-topics analyse-message analyse-session evaluate-ask2-eligibility \
  forum-quiet-check process-chat-media process-chat-notification-outbox \
  process-chat-safety-outbox process-dating-photo process-media-deletion-queue \
  process-relationship-avatar process-scheduled-notifications \
  process-truth-answer-safety send-notification
```
Optional, to keep every bundle identical (they import the file but don't use the changed check): `accept-invite ai-assist ai-sessions ai-together ai-understand calendar-feed create-relationship-invite delete-account end-relationship generate-thirty-six-reflection get-export-url planning-link-preview translate-conflict upload-dating-photo verify-dating-profile`, and the 3 that bundle it indirectly (through `_shared/gemini_json.ts` → `user_scoped_client.ts` / `ai_provider_ledger.ts`): `analyse-journal-entry generate-healing-portrait generate-healing-post-mortem`. With the 18 above that is all 36 functions whose bundle contains `attune_auth.ts`.

### 4. Client build (Waves 1–5)
After steps 1–3. An older client keeps working against the new server; the new client falls back on `PGRST202` against an older one.

### 5. No backfill
Existing stories keep their dates. Pending archival jobs are picked up by the new worker on its next 5-minute run.

### 6. After deploy
- `select schedule from cron.job where jobname = 'invoke-story-archival';` → `*/5 * * * *`, one row.
- `select count(*) from public.data_export_jobs where error = 'restarted';` → the handful restarted at deploy. A restarted job does not count toward the three-a-day export rule (`export_next_allowed` skips `error = 'restarted'`).
- Watch one archival run's log line: `{"fn":"process-story-archival",...}` with counts and codes only.

## Staging checks (hosted only; the local harness can't show these)
- **Bucket 413/415:** the dashboard shows `story-media` at 25 MB with `image/jpeg, video/mp4`. A 30 MB mp4 upload answers 413, a PNG or WebP answers 415, and the app shows the "too large" or "type" reason, not a retry loop.
- **Storage 403/409 bodies:** a second upload to the same key answers a `Duplicate` body with `statusCode "409"` (the app treats it as already uploaded); an upload to an expired or foreign key answers 403 (the app re-makes the link). Confirm the hosted body shape matches what `StoryApiError.fromFailure` reads.
- **PGRST202 window:** after the reload, `create_story_item` with `p_captured_at`/`p_client_now`, `list_story_day_items` with `p_author_id`, `get_story_ring_summary` (with `server_now`) and `list_my_closed_story_chapters` all resolve (no `PGRST202`). If you catch a call between push and reload, it should answer `PGRST202` and the new client should fall back without losing the post.
- **Archival:** a portrait photo story, after 24 hours, has an archived object 1600 px tall.

## Owner decisions pending
1. **iOS `video_compress` ignores a trim when the video has sound** (`SwiftVideoCompressPlugin` returns the whole asset; the time range is set only without audio). Trimmed chat videos with sound export whole on iOS. Stories are unaffected (always whole-source). **Recommendation:** a small patched copy of the plugin (path dependency) that applies the time range with audio. (Wave 2.)
2. **`ChatError` checks a PostgREST message before its code**, so a refusal whose message contains "rate" is treated as rate-limited and never strikes. The fix belongs in chat. (Wave 2.)
3. **Confirm or reverse the Wave 5 rulings** (each is cheap to reverse before deploy):
   - `occurred_on` from capture time, clamped to 7 days, corrected for the phone's clock and floored at the relationship's start; the 24-hour window still runs from posting. Reverse: a one-line change to `created_at`/`expires_at` plus the CHECK.
   - Video media and every thumbnail upload link last 60 minutes (images 15). Cost: an abandoned thumbnail slot holds an object up to an hour.
   - The original's deletion stays 600 s after the swap (the signed-URL lifetime), because each rendition is now validated first. The review's 7-day delay would keep a deleted story's original for a week.
   - Exports in flight at deploy are replaced by a fresh job (the old one fails `restarted`).
   - The left-out story count lives in `media_not_included.txt` (last part); README (part 1) points to it. Moving README to the last part would always make two ZIPs.
   - "Your stories from past chapters" shows date and kind only, no thumbnails (Storage stays closed after an ending).
   - Place pins are still purged at an ending (sync audit C-2 kept, a safety ruling), so an export of an ended relationship carries its stories without places. The plan's "keep pins until archive" was rejected.
4. **The whole shared image cache is emptied on quick exit and on a pause, end or archive** (Wave 4 ruling), not just story bytes. Chat and map photos re-download once. Privacy wins; you may reverse it.
5. **Not built, your call:** story ops alerts and the bytes/day metric (dead letters, queue age; 04 #10); batch signing a month's thumbnails (04 #6); a short view grace window just after expiry (04 #16); CI dependency and secret scanners (checklist 7.1/7.3, project-wide); the review's Later list (gallery upload, captions, flash and zoom, save to phone, mute, quick emoji replies).

## Owner notes (behaviour changes to know about)
- The shared `ConfirmationDialog` now scrolls its message and has 48 dp buttons (8 dp taller) everywhere in the app.
- Android chat trims report the actual exported duration, up to about 2 s over the chosen window (Android trims on whole seconds).
- A brief blip (Control Centre, a permission alert) no longer re-checks the relationship status. Only a full return through the lock, a cold start or an unlock does.
- The 20-open-upload-links cap now interacts with 60-minute video links: a few struck videos can hit it for up to an hour. It backs off and heals; nothing is lost.

## Device checklist (all five waves, merged)
One line each. W1–W5 is the wave that added the check. Release-like build, two phones.

### iOS only
- [ ] W1 VoiceOver: "Pause story" is in the Actions rotor, "Paused"/"Playing" are announced, the hint says to use the Pause story action, and the byline reads "Kofi, 3 hours ago" ("You, …" on your own).
- [ ] W1 Small iPhone (SE class) at the largest Dynamic Type: your own seen story from a calendar day shows only the eye icon, the name stays readable, VoiceOver says "Seen by <partner>"; at default size the word "Seen" is back.
- [ ] W2 Review loop of a video take plays from the loudspeaker (PlayAndRecord); note behaviour with the mute switch on.
- [ ] W2 Backups: `xattr -p com.apple.metadata:com_apple_backup_excludeItem` is set on `story_outbox/` and `attune_story_outbox.sqlite`.
- [ ] W2 Microphone: WithoutPrompt on a reopen and Screen Time restricted both still allow photos; record whether toggling the mic in Settings terminates the app.
- [ ] W2 First-launch camera prompt: exactly one session, and a live preview after Allow.
- [ ] W2 960×540 re-encode: measure size and time on an iPhone.
- [ ] W2 Trimmed chat video with sound: confirm it exports whole (owner decision 1).
- [ ] W3 Type in the chat composer, swipe to the app switcher: no keyboard or QuickType bar on the card; back in Attune the keyboard returns with the draft and caret.
- [ ] W3 PIN "every open": the keyboard never flashes over the checking cover and is not up after unlock.
- [ ] W3 Mic indicator: the orange dot goes off after a Control Centre pull mid-recording.
- [ ] W3 36 Questions answer, 3 lines, keyboard up, on an SE-class and a 6.1" iPhone: Skip and Submit stay visible and the field scrolls into view.

### Android only
- [ ] W1 TalkBack: the reel's hint still says double-tap and hold.
- [ ] W2 Backups: `adb shell bmgr backupnow` excludes the story outbox folder and database.
- [ ] W2 Microphone "Don't ask again": the viewfinder still comes up and photos work; pulling the notification shade shows no microphone dialog.
- [ ] W2 Untrimmed chat video, ephemeral video and streak play at full length; a trimmed 5–15 s chat video plays about 5–15 s (up to ~1 s longer at each end).
- [ ] W3 Gboard suggestions never show over the cover or in the recents snapshot; after dismissing the keyboard with Back, switching away and back opens no keyboard on its own.
- [ ] W3 YouTube in a Planning note: after a swipe home there is no background audio.
- [ ] W3 Mic indicator goes off after a notification-shade pull mid-recording.

### Both platforms

**Reel**
- [ ] W1 A real video: buffering spinner; a mid-play network drop gives Retry; the 15 s start limit holds on a throttled link.
- [ ] W1 Triple-tap quick exit from inside the reel: only the decoy shows, and the reel did not advance.
- [ ] W1 Dark mode: the progress bars are visible.
- [ ] W1 Delete from your own ring's reel (including your last story): Home's ring updates at once.
- [ ] W1 A bright or white photo: bars, byline, Seen, Delete and Close stay readable; the scrim fades with no hard edge under the notch or Dynamic Island.
- [ ] W1 On a stalled link, a partner reel whose first page is all seen opens at the oldest within about 3 s.

**Posting and the outbox**
- [ ] W2 Airplane mode → photo → Share: "Waiting for a connection…"; still queued after 5 minutes; posts within seconds of the network returning, without opening Conversations.
- [ ] W2+W5 A 60 s video on a slow link (Network Link Conditioner, 1 Mbps / 3G): byte progress, posts within an hour, not "too slow" at 13 minutes.
- [ ] W2 Background for 20 minutes mid-upload, then return: it re-makes the link and posts.
- [ ] W2 Cancel during upload: nothing posts, files and row gone. On a slow finalize no Cancel is offered; a late Cancel says it has already posted.
- [ ] W2 A failed record says its reason, offers Retry only where it helps (not "too large" or "no longer on this phone"), and Discard asks first.
- [ ] W2 Lock the phone or trigger the cover right after Share: it still posts. Backgrounding during a video prepare keeps the take with "Couldn't prepare that video…"; Share then works.
- [ ] W2 Pin on with a slow or no GPS fix: posts after about 3 s with no place and says so.
- [ ] W2 Sign out with a story queued: nothing in `story_outbox/`, no row; sign in again: nothing auto-posts. Sign out right after sharing a long video and sign in as another account: nothing posts for the old one.
- [ ] W5 An oversize file (a 30 MB mp4 pushed by a debug build) is refused at upload (413) and shows the "too large" reason.
- [ ] W5 A photo taken at 23:55 offline and posted at 00:10 shows on the day it was taken, for both partners.

**Review step and shared camera**
- [ ] W2 Photo: full-bleed review → Share leaves the camera and the ring shows it pending; Retake gives a live viewfinder; X asks "Discard this photo?".
- [ ] W2 Video review loops with sound over the live camera; Share posts the 960×540 step-down when needed.
- [ ] W2 While "Sharing…" shows there is no X and Back does nothing; the pin state survives review and Retake; a rejected take shows a reason, then a live camera.
- [ ] W2 Battery and heat: leave the review open for 60 s.
- [ ] W2 30, 45 and 60 s full-resolution takes on an iPhone and a mid-range Android: note whether it re-encoded, the final size (≤ 25 MB), transcode and preview start-up time; no file left after a refusal.
- [ ] W2 A full-minute hold shares and finalizes at `duration_ms = 60000` (file 60–62 s) and plays fully; a 0.8 s clip shares.
- [ ] W2 Mic denied on the first prompt: viewfinder up, tap takes a photo, hold shows the Settings snackbar; allowing in Settings lets a hold record with sound without reopening. Streaks show Close and Open Settings.
- [ ] W2 Camera denied (stories and streaks): Close leaves, Open Settings opens settings, no "streak" copy in stories; allowing brings the camera back.
- [ ] W2 Low storage, 10 s hold: "Could not save that recording.", the viewfinder returns, the next hold records.
- [ ] W2 Mid-hold call, Control Centre, home swipe, app switcher or notification shade (stories and streaks): the take reaches review, no "Could not save", the viewfinder is live on return.
- [ ] W2 A resume during a FaceTime or WhatsApp call recovers or shows Close (record which); after the call the viewfinder returns.
- [ ] W2 Screen reader: shutter reads "Take photo, hold for video, button" and a double-tap takes one photo (nothing during a send); "Switch camera"; review order preview → Retake → Share → Close; "Sharing…" and each rings notice are announced.
- [ ] W2 Photos are 1920 px on the long edge (≤ 2560 px, ≤ 5 MB) and look sharp full screen.
- [ ] W2 Small phone (320 dp) at the largest text: review's Share and Retake stack with words whole; rings-row notice actions move under the message.

**App shell (cover, lock, interruptions)**
- [ ] W3 Control Centre over a partner's reel (resumes on the same story), the camera (comes back live), a story review and a streak review (take kept, sound stops, loops again on return; with the lock, waits for unlock).
- [ ] W3 First story camera use: camera, mic and location alerts appear over the camera, which stays open.
- [ ] W3 Incoming call during a reel video, streak clip, ephemeral clip, inline chat video and voice note: all silent; viewers carry on afterwards, inline video and voice note wait for a tap. An ephemeral clip is not marked viewed while paused.
- [ ] W3 Recording a voice note: locked + Control Centre pauses and keeps it; held + call locks and pauses, never sends; held + home swipe stays locked; the first mic alert during a hold doesn't cut it.
- [ ] W3 App switch and back, no PIN: chat scroll, an open actions sheet, Ask Attune's draft and a typed composer are kept; safe area and keyboard insets unchanged.
- [ ] W3 PIN "every open", leave from a playing reel and return: no sound or camera indicator before the PIN; no "Seen" until unlocked; no fresh location for the partner until unlock; no 36 Questions polling while covered.
- [ ] W3 Quick exit from the reel, the camera review and a sheet: only the decoy; a blip keeps the decoy; with a PIN the next return shows only the PIN.
- [ ] W3 PIN "every open", background, tap a chat notification: PIN first, then the destination opens once.
- [ ] W3 App-switcher thumbnail shows only the neutral cover, including on the couple-map tab (no map tiles) and on web views; on return the map is live, not black.
- [ ] W3 After 10+ minutes away (partner changes things): Chat, Together, Planning, Timeline, story rings, Home, appreciation jar, wins and quiet state are fresh; report whether Pulse and the journal are stale; realtime resumes.
- [ ] W3 Partner ends while this phone is backgrounded: the ending sheet shows on the next real return, not on a Control Centre pull.
- [ ] W3 VoiceOver / TalkBack: after a return focus lands in the app; nothing reads while covered.
- [ ] W3 Understand sheet open, Control Centre and back: still open, says the read was cleared; "Read it again" asks once.
- [ ] W3 No game, streak or chat sound plays behind the cover or during the PIN check.
- [ ] W3 YouTube in a Planning note: Control Centre or a call stops the sound at once; back, a tap plays again.
- [ ] W3 A short call during the 20 s session-game wait: back on the wait, not bounced to chat.
- [ ] W3 Keyboard up, then Control Centre or Face ID: the keyboard dips and returns (note if janky).

**Rings and calendar**
- [ ] W4 Tap the centre of your ring → reel; tap `+` → camera; near the badge edge → exactly one. Same in an RTL locale (Arabic): `+` bottom-left, targets mirrored.
- [ ] W4 Airplane mode at cold start: last-known thumbnails plus "Couldn't refresh" with Retry. Cold start online: disk thumbnail crossfades to network with no grey flash.
- [ ] W4 First story on a slow link: no `+` flash, and no grey blink when the posted hold releases.
- [ ] W4 Tap a ring whose only story is still posting: "Still posting" shows (and is announced), no empty reel.
- [ ] W4 Screen reader reads ring counts ("Ama's story, 2 new of 5" / "Your story, 3 items").
- [ ] W4+W5 Leave Conversations open past a story's 24 h mark: the partner ring clears within about a minute; with the phone clock 5 minutes behind, it still clears on time.
- [ ] W4 A landscape story's thumbnail is sharp on the ring and the 14 dp calendar avatar on a 3x phone.
- [ ] W4 Spacing about 12 dp under the rings; a notice brings its own gap; the stuck-post notice shows on Conversations with no active relationship; light and dark.
- [ ] W4 Delete from your reel and from a calendar day reel: month count and day sheet update in place; the key is gone from `libCachedImageData`. A partner's delete is gone after the next ring or month read.
- [ ] W4 Calendar: the partner's day ring doesn't flicker dim then bright; month-row Retry shows it is loading.
- [ ] W4+W5 A day with more than 50 stories: my ring opens on my stories, deleting one while paging steps to the next, and the partner's day ring stays bright for unseen ones beyond the first 50.

**Privacy wipes and lifecycle**
- [ ] W4 Quick exit, then reopen: no story thumbnails cached, no last-known rings painted.
- [ ] W4 Pause, end or archive: story thumbnails and last-known rings are gone; chat and map photos re-download once.
- [ ] W4 Sign out, sign in as another account, cold start offline: the previous account's rings never show.
- [ ] W5 End a space: Download my data shows "Your stories from past chapters"; Delete all removes them; a new download no longer has them. Within 30 days the confirm says "download your data first"; after, it says they can't be downloaded.
- [ ] W5 Pause and End confirm sheets show the stories sentence without clipping at the largest text on a 320 dp phone; the buttons are 48 dp.

**Export**
- [ ] W5 Download my data on an account with lots of chat media: story files come first and open as photos and videos (`.jpg`/`.mp4`); `media_not_included.txt` says how many stories were left out, if any. An ended space's stories have no places.

## Deferred minors (from the ledgers)

### Wave 1 — Reel
- The dialog `removeRoute` branch leaves the push future uncompleted (harmless); `_close()` bails if the reel's own route is also covered.
- Auto-retry while paused can mark seen while backgrounded (clock paused); a hung video init future; failure UI before player dispose; a stray onEnded after a playback error; photos have no load deadline; the kit's loadBuffer override.
- The quick-exit tap block spans the full width rather than the detector's 72 dp centre column.
- A loadMore error never ends the first-unseen search (it re-fetches within the 3 s budget); places step-off after a slow RPC (mostly removed); the reel runs under a covering non-reel route; `_onItemsChanged` ignores `_closing` / reconciles under the Delete dialog.
- The map byline date has no year for past-year stories; a manual tap during a slow map-reel Delete can jump back.

### Wave 2 — Posting
- (Chat-owned) `ChatError` checks the PostgREST message before the code (owner decision 2).
- Non-permission camera failures still read "needs camera access" (streak copy kept; button hidden).
- Each return from a broken camera briefly clears the error screen.

### Wave 3 — App shell
- On cold start the visibility signal reads visible for one frame while locked (nothing is mounted).
- A touch cancelled while a recording is still starting counts as a release; the sound provider wiring has no test of its own.
- `topic_impression_tracker` logs a forum impression after 2 s or more under the cover (the partner never sees it); a one-time emoji animation can be used up during a no-PIN lock check (milliseconds).

### Wave 4 — Rings and calendar
- The couple map signs story thumbnails outside the shared per-key cache.
- Quick exit can't clear the in-memory posted holds (no container); they are never painted on the decoy.
- A partner's delete of a past story is evicted from disk only if that month was opened this session. (The clock-behind case is fixed by Wave 5's `server_now`.)
- A real change signalled within 250 ms of a return's re-read waits for the next signal or resume; the sign-out wipe does not invalidate on-screen URL providers (the session can still sign).

### Wave 5 — Server
- `fail_story_archival` has no lease token (a signature change would break the old worker during the rollout).
- Story export names and the cursor come from `media_key`, so an archival swap mid-export can mismatch or skip one file. Name by story id later.
- The past-chapters list shows at most 1,000 stories per chapter (Delete all still removes every one, 200 per call).
- `ConfirmationDialog.show` never completes when dismissed by tapping outside (harmless where used here: nothing has started).
- An archival run can outlast the 5-minute lease; a reclaimed job is safe but costs a second transform. Watch for dead letters or duplicate work.

## Test evidence
Final run, 2026-10-24, on the full five-wave tree:
- **Flutter, whole suite:** `flutter test` → **+5612, All tests passed!** (log: `.superpowers/sdd/2026-10-24-stories-wave5-server/full-suite.log`). Before Wave 5 it was +5559; after Waves 1–4, +5153 / +5345 / +5432 / +5559.
- **Analyzer:** `flutter analyze lib` → 0 errors.
- **SQL contracts on `attune_spec3a`:** all 18 story contracts PASS (10 existing + 8 new: after_ending, archival, capture_date, day_reads, export, hardening, membership, ring_summary; plus together_story) and all 5 related contracts PASS (data_export, sync_fixes, account_deletion, relationship_purge, chapter_canary). Before Wave 5, 7 of 10 story contracts passed. Each Wave 5 contract was seen failing first, and its mutations are caught.
- **Deno:** `process-story-archival` 17/17, `build-data-exports` 22/22, `_shared/attune_auth.test.ts` 3/3. Every other function directory matches its pre-Wave-5 baseline; the failures that predate this program are unchanged (analyse-message 3, analyse-session 2, ai-assist 1, translate-conflict 5; ai-sessions fails its type-check on `callMapbox`; `_shared/ai_session_context.test.ts` type-check).
- **Final fix pass (M1–M4, M6–M8):** `flutter test` → **+5614, All tests passed!** (log: `full-suite-2.log`); 23/23 contracts PASS; Deno `compute-pulse` 81/81, `generate-verdict` 29/29, `process-story-archival` 17/17, `build-data-exports` 22/22, `_shared/attune_auth.test.ts` 3/3. Lock probes: with `storage.objects` / `data_export_jobs` held by another session, 100200 and 100700 now fail in 5 s with `lock timeout` (before: waited indefinitely).
- **Tree:** nothing staged; nothing committed or deployed.
