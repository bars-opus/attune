# 04 — Attachments & Media (photos, videos, voice, camera, view-once, deletion)

## Summary

The media pipeline is structurally strong: intent-gated uploads with server-side size/MIME validation, random unguessable storage keys, a private bucket whose SELECT policy is tied to the message row and relationship state, EXIF/GPS stripping for images and MP4 location atoms for video, a durable outbox that survives process death at every stage (raw → prepared → uploaded → inserted), and key-based (not URL-based) disk caching so signed-URL expiry does not break old images or posters. Against WhatsApp/iMessage it falls short in four user-visible ways that should be fixed before the two-phone test: (1) every photo is downscaled to ~500 px on its short edge by the generic picker before the chat preparer ever runs, so photos look soft; (2) a voice note stops the moment its bubble scrolls out of view; (3) a signed-URL resolution that fails once (e.g. opened offline) is cached as "broken" for the whole app session; (4) "Delete for everyone" nulls the row but leaves the photo/video/voice bytes in the bucket indefinitely. Upload UX (no %, no cancel, a stop glyph that does nothing), fixed square image bubbles, mandatory crop, single-image picks, and uncached voice/video replay are the main roughness items.

## Findings

### H-1: Chat photos are downscaled to ~500 px short edge (and re-encoded 3–4 times) before ChatImagePreparer runs
- Severity: High
- Confidence: Confirmed (traced through plugin source)
- Evidence:
  - `lib/features/chat/presentation/screens/chat_screen.dart:859-864` — `_attachImage` uses the generic `ImagePickerService.pickImage(crop: true, …)`.
  - `lib/core/services/media/image_picker_service.dart:40-45` — picker already re-encodes at `maxWidth: 1024, maxHeight: 1024, imageQuality: 85`.
  - `lib/core/services/media/image_picker_service.dart:63-74, 164-189` — after the (mandatory) crop, `_compressImage` calls `FlutterImageCompress.compressAndGetFile(..., quality: 80, minWidth: 500, minHeight: 500)`.
  - flutter_image_compress_common 1.0.6 `android/.../ext/BitmapCompressExt.kt:59-67` `calcScale = max(1, min(w/minWidth, h/minHeight))` and `ios/Classes/UIImage+scale.m:9-24` — both scale the image so its SHORTER edge becomes 500 px. A 4:3 photo leaves the picker at 667×500; a 16:9 at 889×500.
  - `lib/features/chat/domain/services/chat_image_preparer.dart:52,89-100` — `maxDimension = 1600` can never be reached; the preparer then re-encodes a 4th time at quality 82.
- Failure scenario: pick any 12 MP photo → crop → caption → send. Partner opens the full-screen viewer and pinch-zooms: the image is ~667×500, visibly soft/blocky on any modern phone. Sender's own thumbnail looks fine (220 px) so the loss is only noticed on the receiving side.
- WhatsApp/iMessage expectation: standard-quality photo ≈ 1600 px long edge; "HD" option higher.
- Fix: in `_attachImage` stop routing through `ImagePickerService.pickImage`; pick with `ImagePicker().pickImage(source: gallery)` with no `maxWidth/maxHeight/imageQuality` (or ≥ 2048/95) and hand the raw path to `sendImageMessage` — `ChatImagePreparer` already does the single resize-to-1600/compress-to-800 KB pass with EXIF stripping. If cropping stays, make it optional (edit button on `ImageCaptionScreen`) and skip `_compressImage` for chat.

### H-2: A voice note stops playing as soon as its bubble scrolls out of the list's cache extent
- Severity: High
- Confidence: Confirmed
- Evidence:
  - `lib/features/chat/presentation/widgets/voice_message_player.dart:50-81` — the `AudioPlayer` is owned by the bubble's `State`; `dispose()` disposes the player. No `AutomaticKeepAliveClientMixin`, no shared player/service.
  - `lib/features/chat/presentation/screens/chat_screen.dart:3298-3300` — plain `ListView.builder(reverse: true)` (default cacheExtent); the file's own comment at `:116-118` notes "ListView.builder recycles item State when a bubble scrolls out of cacheExtent".
  - Same shape for `VideoMessagePlayer` (`video_message_player.dart:86-92`), though video only plays full-screen so it is unaffected in practice.
- Failure scenario: tap play on a 2-minute voice note, scroll up to re-read earlier messages → audio cuts off within one screen-height of scrolling; scrolling back shows the bubble reset to 0:00. Also: receiving a burst of messages that pushes the bubble past the cache extent stops playback.
- WhatsApp/iMessage expectation: playback continues while scrolling; WhatsApp pins a mini-player in the header when the bubble leaves the viewport.
- Fix: move the `AudioPlayer` out of the widget into a Riverpod-owned `VoicePlaybackController` (singleton, keyed by messageId; expose position/state streams). `VoiceMessagePlayer` becomes a view of that controller. Stop playback in `ChatScreen.dispose`/route pop instead of bubble dispose. Minimum stop-gap: wrap the player row in `AutomaticKeepAliveClientMixin` while `_isPlaying` (keeps the State alive off-screen).

### H-3: A signed-URL resolution that fails once is cached for the entire app session → permanent broken image/poster until restart
- Severity: High
- Confidence: Confirmed
- Evidence:
  - `lib/features/chat/presentation/state/chat_state.dart:38-43` — `signedMediaUrlProvider` is `FutureProvider.family` (NOT autoDispose); nothing in `lib/` ever invalidates it.
  - `lib/features/chat/data/repositories/supabase_chat_repository.dart:415-444` — `_createSignedStorageUrl` swallows every exception and returns `null`.
  - `lib/features/chat/presentation/widgets/resolved_media_url.dart:49-61` — `data(null)` → `error` widget; `message_bubble.dart:1489-1521`, `image_viewer_screen.dart:167-189`, `chat_media_group.dart:244-260`, video poster at `message_bubble.dart:1820-1835` all route through it.
- Failure scenario: open the chat in a tunnel/airplane mode (warm cache) and scroll to a partner's photo that is not yet on disk → broken-image tile. Regain connectivity, pull to refresh, leave and re-enter the chat: still broken. Only a full app restart (or 10 minutes + a different key) recovers, because the provider is global and keyed on the storage key alone. Same for video posters and for the full-screen viewer.
- WhatsApp/iMessage expectation: media retries automatically when the network returns; a tap retries.
- Fix: make it `FutureProvider.autoDispose.family` and let `_createSignedStorageUrl` rethrow (so the provider is in `error`, which Riverpod does not cache past dispose), and in `ResolvedMediaUrl.error` render a tappable retry that calls `ref.invalidate(signedMediaUrlProvider(key))`. Also invalidate all family members on `ChatController.loadMessages` success after an offline period.

### H-4: "Delete for everyone" leaves the photo/video/voice bytes in the bucket indefinitely
- Severity: High (privacy / data retention)
- Confidence: Confirmed (live schema in attune_spec3a)
- Evidence:
  - `public.delete_message(uuid)` (live def; from `supabase/migrations/20260831120000_message_actions.sql` lineage) sets `media_url = NULL, media_thumbnail_url = NULL` and never calls `public.queue_media_deletion(...)`.
  - Only `messages_queue_media_before_delete` (BEFORE **DELETE**) queues media; it does not fire on this soft-delete UPDATE. `cleanup_expired_chat_media_intents()` only removes objects whose intent is still unused, so a consumed intent's object is never swept.
  - `supabase/functions/process-media-deletion-queue/index.ts` only drains what was queued.
- Failure scenario: send a photo, "Delete for everyone" within 5 minutes. The row shows "This message was deleted", but `storage.objects` still holds `chat-media/<key>.jpg` (and the 400 px `chat-thumbnails/...` copy) until the relationship is eventually purged. Any signed URL minted in the previous ≤10 minutes keeps working (signed URLs bypass RLS). A data-export/legal request would still find the file.
- WhatsApp/iMessage expectation: delete-for-everyone removes the media from the server.
- Fix: in `delete_message`, before the UPDATE, `PERFORM public.queue_media_deletion('message-media', media_url); PERFORM public.queue_media_deletion('message-media', media_thumbnail_url);` (read via the FOR UPDATE select already there). Add a contract test in `supabase/tests/message_edit_delete_contracts.sql` asserting `media_deletion_queue` gets both rows.

### M-1: Storage RLS SELECT policy does a sequential scan over all messages for every signed URL / download
- Severity: Medium (performance; grows with total message count across all couples)
- Confidence: Confirmed
- Evidence:
  - Policy `message_media_select_relationship_members` (live): `EXISTS (SELECT 1 FROM messages m WHERE (m.media_url = objects.name OR m.media_thumbnail_url = objects.name) AND relationship_chat_open(m.relationship_id))`.
  - `pg_indexes` for `public.messages` (live): no index on `media_url` or `media_thumbnail_url`.
  - Every `createSignedUrl` (repository `:429-431`) and every media GET goes through this policy; `_hydrateMessages` fans out one call per media row (`:943-957`), poster prewarm up to 24 per open (`chat_poster_prewarmer.dart:92`).
- Failure scenario: a media-rich chat open = dozens of full-table scans of `messages` on the DB; at 1M+ rows this is hundreds of ms each and signing a page of 50 images takes seconds (worse on Ghana-class networks the spec targets).
- WhatsApp/iMessage expectation: instant thumbnails.
- Fix: `CREATE INDEX idx_messages_media_url ON messages(media_url) WHERE media_url IS NOT NULL; CREATE INDEX idx_messages_media_thumbnail_url ON messages(media_thumbnail_url) WHERE media_thumbnail_url IS NOT NULL;` and split the OR into two EXISTS so both indexes are used. Consider batching with `createSignedUrls` (plural) in `_hydrateMessages`.

### M-2: Every picked chat photo leaves a permanent, never-deleted copy in Documents/shop_images (iCloud-backed-up on iOS)
- Severity: Medium (privacy + disk growth)
- Confidence: Confirmed
- Evidence: `image_picker_service.dart:81-99` copies the picked file into `getApplicationDocumentsDirectory()/shop_images/<ts>.jpg`; nothing in `lib/features/chat` deletes it (`removeFailedMessage` deliberately keeps `requiresPreparation` paths, `chat_state.dart:1540-1544`; `_settleAcknowledgedMedia` only deletes staging paths it knows).
- Failure scenario: send 200 photos over a few months → ~200 × 300 KB unreferenced JPEGs in Documents, included in iCloud/Android backups, surviving "Delete for everyone" and chapter deletion.
- WhatsApp/iMessage expectation: no stray copies outside the media cache.
- Fix: covered by H-1's fix (bypass `ImagePickerService` for chat). Otherwise delete the `shop_images` copy after `_cropImage` returns.

### M-3: Cron misregistration — stale-lease recovery and expired-intent cleanup never run
- Severity: Medium (orphaned storage objects; stuck media/notification/safety jobs never recovered)
- Confidence: Confirmed (migration + live cron.job)
- Evidence: `supabase/migrations/20260907120000_register_scheduled_jobs.sql:157-167` registers `recover-stale-chat-workers` and `cleanup-expired-chat-media` both as `invoke_edge_function('process-chat-media')`. `supabase/functions/process-chat-media/index.ts` never calls `recover_stale_chat_worker_leases()` or `cleanup_expired_chat_media_intents()`. Live `cron.job` confirms all three jobs run the same function.
- Failure scenario: (a) user kills the app between `createMediaUploadIntent` + upload and the row insert (or any upload failure after a new intent): the object stays in `message-media` forever (not referenced by any row, so unreachable, but billed and retained). (b) An edge-function crash mid-job leaves `message_media_processing_outbox` (and the notification/safety outboxes) rows in `processing` forever — flag for the notification reviewer.
- Fix: change the two jobs to `SELECT public.recover_stale_chat_worker_leases();` and `SELECT public.cleanup_expired_chat_media_intents();` (both are SECURITY DEFINER SQL functions; no edge call needed).

### M-4: Sender can "burn" their own view-once video; server does not forbid it
- Severity: Medium
- Confidence: Likely (code confirmed; entry point currently unreachable — see note)
- Evidence: `mark_video_viewed` (live) only checks relationship membership, not `sender_id <> auth.uid()`; `message_bubble.dart:1705-1740` lets `isMine` ephemeral bubbles open `EphemeralVideoViewerScreen`, whose tap/complete calls `markVideoViewed` (`ephemeral_video_viewer_screen.dart:151-181`) → media deleted, `viewed_at` set → partner sees "Video expired" without ever watching. Note: `chat_screen.dart:953-959` now routes the camera button to the streak camera, and no code pushes `'ephemeralCamera'`, so new view-once videos cannot be created today; `mark_streak_viewed` handles the sender correctly.
- Fix: in `mark_video_viewed` add `AND sender_id <> v_user_id` (return silently) and in the bubble gate the tap on `!message.isMine`, mirroring the streak bubble.

### M-5: Upload phase has no progress, no cancel, is non-resumable — and the busy ring shows a stop glyph that does nothing
- Severity: Medium
- Confidence: Confirmed
- Evidence: `supabase_chat_repository.dart:372-384` single-shot `storage.upload(File)` (storage_client 2.5.5 reads the whole 25 MB file with `readAsBytesSync`, `fetch.dart:111`, on the UI isolate); `message_bubble.dart:1524-1534` indeterminate `_MediaBusyOverlay`; `video_message_thumbnail.dart:382-414` draws `Icons.stop_rounded` inside the ring while `onTap` is null during prepare (`message_bubble.dart:1808-1811`); no `StorageRetryController`/cancel API anywhere in `lib/features/chat`. A failed upload restarts from byte 0 with a fresh intent; after 5 attempts (`chat_state.dart:281`, backoff ≤ ~30 s total) it goes `failedPermanent`.
- Failure scenario: send a 20 MB video on 3G; a 2-minute indeterminate spinner with a "stop" icon that ignores taps; walk through a dead spot → the whole upload restarts; three dead spots → "Message not sent. Tap to retry" and no auto-resume when back online.
- WhatsApp/iMessage expectation: determinate % ring, tap-to-cancel, resumes after reconnect.
- Fix: (1) replace the stop glyph with a progress-only ring until cancel exists, or implement cancel (`StorageRetryController` + remove outbox row). (2) Use `uploadBinary` with a streamed `http.Client` (or TUS via `tus_client` against `/storage/v1/upload/resumable`) to get progress + resumability. (3) Trigger `flushOutbox()` on connectivity-restored and app-resumed (none exists in `chat_state.dart`).

### M-6: Voice and video bytes are never cached locally — every replay re-downloads
- Severity: Medium
- Confidence: Confirmed
- Evidence: `voice_message_player.dart:126-143` plays `UrlSource(signedUrl)` directly; `video_message_player.dart:201-204` `VideoPlayerController.networkUrl`. Only images/posters use `CachedNetworkImage`/`DefaultCacheManager`. Sender keeps the local file only until the 30-day/200-object `DefaultCacheManager` eviction.
- Failure scenario: partner replays a 3-minute voice note five times = five downloads; playback start latency each time; offline → "That voice message could not play".
- WhatsApp/iMessage expectation: downloaded once, plays offline afterwards.
- Fix: download through `DefaultCacheManager().getSingleFile(url, key: mediaKey)` (same key scheme as posters) and play `DeviceFileSource`/`VideoPlayerController.file`; show the download ring on first play.

### M-7: Voice player ignores OS interruptions/state changes; no speed control; no earpiece
- Severity: Medium
- Confidence: Likely
- Evidence: `voice_message_player.dart:56-72` subscribes only to `onPositionChanged` and `onPlayerComplete`, never `onPlayerStateChanged`; no `WidgetsBindingObserver`; no `setPlaybackRate`; no proximity/earpiece routing anywhere in `lib/` (grep).
- Failure scenario: a phone call or Siri interrupts playback → audio stops but the bubble keeps the pause icon and the knob frozen; tapping once "pauses" (no-op), second tap restarts from the old position. Long notes cannot be sped up.
- WhatsApp/iMessage expectation: UI follows actual state; 1×/1.5×/2× toggle; earpiece when phone is raised.
- Fix: listen to `onPlayerStateChanged` and set `_isPlaying = state == PlayerState.playing`; add a playback-rate chip (audioplayers `setPlaybackRate`); earpiece is optional polish.

### M-8: Image bubbles are a fixed 220×220 center-crop; no dimensions persisted for images
- Severity: Medium (visual quality)
- Confidence: Confirmed
- Evidence: `message_bubble.dart:1481-1511` `width: 220, height: 220, fit: BoxFit.cover`; `sendImageMessage` (`chat_state.dart:757-777`) never sets `mediaWidth/mediaHeight` though the columns exist and the video path uses them.
- Failure scenario: portrait photos lose top/bottom, panoramas lose both sides; the Hero flight into the viewer visibly changes shape.
- WhatsApp/iMessage expectation: bubble keeps the photo's aspect ratio (clamped), full-bleed.
- Fix: have `ChatImagePreparer` return width/height, persist via the existing `media_width/media_height` columns, and size the tile with `AspectRatio` clamped to [0.5, 1.91] like `VideoMessageThumbnail`.

### M-9: Attach flow friction — mandatory crop on every photo, single image per send, double trim for videos
- Severity: Medium
- Confidence: Confirmed
- Evidence: `chat_screen.dart:860-864` `crop: true` (image_cropper with hard-coded `Colors.deepOrange` toolbar, `image_picker_service.dart:141-147`); `pickImage` is single-select; `pickVideo(maxDuration: 5 min)` (`image_picker_service.dart:110-113`) makes iOS present Apple's trimmer before the app's own `VideoTrimScreen`.
- WhatsApp/iMessage expectation: pick (multi) → preview/caption → send; crop is an optional edit.
- Fix: drop `crop: true` (add an optional crop button on `ImageCaptionScreen`), use `pickMultiImage` and queue N `sendImageMessage` calls (the `ChatMediaGroup` album UI already exists), remove `maxDuration` from the picker.

### M-10: Valid MP4s with uncommon `ftyp` brands are rejected as "not supported"
- Severity: Medium (edge case)
- Confidence: Possible
- Evidence: `chat_video_preparer.dart:109-120` accepts only `isom, mp42, avc1, M4V , qt  `; files with major brand `mp41`, `iso2`, `iso5`, `iso6`, `hev1`, `3gp5`, `dash`, `f4v ` (ffmpeg `-movflags`, HEVC exports, some screen recorders/downloaders) are refused before `VideoCompress` even sees them.
- Fix: accept any `ftyp` box (the transcode step normalizes the container anyway) or extend the list; keep rejecting only non-ISO-BMFF files.

### M-11: Any StorageException is treated as a permanent "That image could not be sent" — including 5xx and for voice/video
- Severity: Medium
- Confidence: Confirmed
- Evidence: `chat_error.dart:83-89` → `mediaRejected` → `isPermanent` (`:47-52`); copy at `:171-172` always says "image". Storage 500/502/503 responses arrive as `StorageException(statusCode:'5xx')`.
- Failure scenario: a 503 from storage during a voice-note upload → bubble marked failed immediately, banner "That image could not be sent. Try a different one."
- Fix: in `ChatError.from`, map `StorageException` with `statusCode` ≥ 500 (or non-numeric) to `unavailable`, 400/413/415/403 to `mediaRejected`; make the copy media-type aware.

### L-1: Server thumbnail pipeline is dead weight (and likely failing on non-Pro plans)
- Severity: Low
- Confidence: Likely
- Evidence: `process-chat-media/index.ts:27-33` downloads with `transform: {width: 400}` (Supabase image transformations are a paid feature; failure → 5 attempts → dead_letter). Even when it succeeds the bubble ignores it: `ResolvedMediaUrl` prefers `mediaKey` (full image) over the thumbnail-bearing `signedMediaUrl` (`resolved_media_url.dart:45-53`, `message_bubble.dart:1489-1491`), and `CachedNetworkImage` is keyed on `mediaKey`.
- Fix: either pass `mediaKey: message.mediaThumbnailKey ?? message.mediaKey` in the bubble (and keep full key for the viewer), or delete the worker + trigger. Images are ≤ 800 KB so the saving is modest.

### L-2: Outbox staging lives in the OS temp directory
- Severity: Low
- Confidence: Confirmed
- Evidence: `chat_image_preparer.dart:182-193`, `chat_video_preparer.dart:354-364`, `voice_recorder_service.dart:120-124` all write to `getTemporaryDirectory()`; `PendingSend.localMediaPath` points there across restarts.
- Failure scenario: iOS purges `tmp/` under storage pressure while the app is killed with a queued media send → on restart the bubble is restored, then fails with "no longer available".
- Fix: stage under `getApplicationSupportDirectory()/chat_outbox/` and delete in `_settleAcknowledgedMedia`/`removeFailedMessage` as today.

### L-3: Media cache eviction makes old media (including the sender's own) re-download
- Severity: Low
- Confidence: Confirmed
- Evidence: `DefaultCacheManager` defaults (200 objects / 30 days) used by `chat_poster_prewarmer.dart:76-78`, `video_message_thumbnail.dart:231`, `CachedNetworkImage` sites. Sender files are promoted into this same cache (`chat_state.dart:2152-2159`).
- Fix: a dedicated `CacheManager(Config('chat_media', maxNrOfCacheObjects: 5000, stalePeriod: 365 days))`.

### L-4: Ephemeral/streak viewers rely on best-effort screenshot detection only
- Severity: Low (design)
- Confidence: Confirmed
- Evidence: `screenshot_detection_service.dart` (ContentObserver/notification based); no `FLAG_SECURE`/secure-window usage anywhere; recipient can screen-record freely.
- Fix: acceptable parity with Snapchat; consider `FLAG_SECURE` on Android for the streak/ephemeral routes.

## Done well
- Upload authorization is intent-based (`create_chat_media_upload_intent` → RLS INSERT by intent → `validate_message_media_before_insert` checks object size/MIME against the consumed intent, FOR UPDATE, per-type ceilings 800 KB/1.2 MB/25 MB). Keys are 16 random bytes; no path guessing. Bucket is private; UPDATE has no policy (no overwrite).
- Server-authoritative feature flags per media type (`chat_image_sharing`, `chat_voice_messages`, `chat_video_sharing`, `chat_ephemeral_video`); client flags are presentation only.
- EXIF/GPS stripped on images (`keepExif: false`, Dart fallback clears `exif`), MP4 location atoms neutralised (`Mp4LocationStripper`), magic-byte MIME sniffing, decompression-bomb cap; dedicated tests exist (`chat_image_preparer_exif_test.dart`, `mp4_location_stripper_test.dart`).
- Durable outbox stages: raw (`requiresPreparation`) → prepared → `uploadedMediaKey`/`uploadedThumbnailKey` → inserted; a restart resumes at the right stage without re-uploading; 23505 reconciliation reuses the key; thumbnail upload failure is non-fatal for a video.
- Signed-URL expiry handled correctly: resolution is by stable key, `CachedNetworkImage`/poster cache keyed on storage key, video re-signs on init failure, voice signs on play. Sender's local bytes are promoted into the same key-based cache so optimistic → canonical is flash-free.
- Video: poster extracted before transcode so the bubble shows a real frame instantly with a determinate compress ring; rotation-corrected dimensions; one-at-a-time playback with cross-media pause; expired-URL retry with a visible "tap to retry" state.
- Voice recording UX: scrim shown before the permission sheet, denied-permission snackbar with Settings deep link, slide-left-to-cancel with haptic rising edge, swipe-up lock with pause/resume/delete, release-during-start handled, 5-minute auto-stop latched idempotently, pause time excluded from duration, waveform sampled live and resampled to 100 points.
- View-once (ephemeral video) and streaks: server nulls `media_url` and queues the object AND poster for deletion; sender-side local files are deleted after send and on cross-device expiry; `mark_streak_viewed` distinguishes sender replay from recipient view and enforces the 30-minute window.
- `media_deletion_queue` is an audit trail with `not_before`; the drain function groups per bucket and leaves failures for retry.

## Not verified
- Actual output dimensions from `flutter_image_compress` on-device (H-1 traced from the plugin's Kotlin/Obj-C source in the pub cache, not run on a phone); `video_compress` output bitrate/size for 3-minute 720p clips vs the 25 MB ceiling.
- Whether the hosted project's plan supports Supabase image transformations (L-1) and whether `process-chat-media` dead-letters in production.
- Behaviour of the `record` plugin when a phone call arrives mid-recording (file truncation vs. `durationMs` from wall clock) — needs a device test; code shows no interruption handling.
- audioplayers/AVAudioSession behaviour when the app is backgrounded during voice playback (no background-audio entitlement found; likely pauses, UI state then stale per M-7).
- Realtime UPDATE delivery of `media_thumbnail_url` from the worker and the resulting re-render were not traced end-to-end (bubble ignores it anyway, L-1).
- I did not run `flutter test` for the media suites (read-only review); `test/features/chat/` contains preparer, player, thumbnail, outbox, streak and ephemeral tests that should still pass after the fixes above.
