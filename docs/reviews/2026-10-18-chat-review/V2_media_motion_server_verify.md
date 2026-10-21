# V2 — Adversarial verification: 04 media, 06 motion/sound, 07 server/push, 05 H-2

Method: every finding re-traced from source (lib/, supabase/functions, pub cache plugin sources: flutter_image_compress_common 1.0.6, audioplayers_android 5.2.1, audioplayers_darwin 6.4.0, audioplayers_platform_interface 7.1.1, onesignal_flutter 5.5.1) and the live scratch schema `attune_spec3a` (pg_get_functiondef, pg_trigger, pg_policies, column_privileges, cron.job). No edits, no tests run, no .env read.

## Verified

### 04 H-1 — Chat photos downscaled to ~500 px short edge — CONFIRMED, High
- `chat_screen.dart:115` `_imagePicker = ImagePickerService()`; `:860-864` `pickImage(fromCamera:false, crop:true, lockAspectRatio:false)`.
- `image_picker_service.dart:40-45` picker re-encodes at 1024/1024/q85; `:63-70` crop then `_compressImage`; `:175-181` `FlutterImageCompress.compressAndGetFile(quality:80, minWidth:500, minHeight:500)`.
- Plugin semantics (pubspec.lock: flutter_image_compress 2.4.0 → common 1.0.6): Android `BitmapCompressExt.kt:59-67` `calcScale = max(1, min(w/500, h/500))` used by `CommonHandler.kt:75`; iOS `UIImage+scale.m:9-24` scales so the SHORT edge becomes 500. 1024×768 → 667×500; square crop → 500×500.
- `chat_image_preparer.dart` `maxDimension = 1600` is unreachable; 4th re-encode at q82.
- Fix: in `_attachImage` call `ImagePicker().pickImage(source: gallery)` with no maxWidth/maxHeight/imageQuality (or ≥2048/q95), optional crop, hand the path to `sendImageMessage`; leave `ChatImagePreparer` as the single resize/strip pass. Do NOT touch `ImagePickerService` (used by profile/shop flows).
- Test: unit test on `ChatImagePreparer` with a 4000×3000 fixture asserting output long edge == 1600; plus a widget test that `_attachImage` never calls `ImagePickerService.pickImage` (inject a fake picker).

### 04 H-2 — Voice note stops when its bubble leaves cacheExtent — CONFIRMED, High
- `voice_message_player.dart:50-51` `AudioPlayer` owned by widget State; `:74-81` `dispose()` disposes the player. No keep-alive, no shared controller.
- `chat_screen.dart:3298` plain `ListView.builder(reverse:true)` with default cacheExtent (250 px); the file's own comment `:116-118` acknowledges State recycling.
- Spec `docs/superpowers/specs/2026-08-15-voice-messages-design.md:55` only requires "leaving the chat screen stops playback"; it says nothing about scrolling — so this is not a product decision, it is an artefact of where the player lives.
- Fix: Riverpod-owned `VoicePlaybackController` (single `AudioPlayer`, keyed by messageId, exposes position/state); `VoiceMessagePlayer` becomes a view; stop in the chat route's dispose (keeps the spec rule). Stop-gap: `AutomaticKeepAliveClientMixin` with `wantKeepAlive = _isPlaying`.
- Test: `voice_message_player_test.dart` — start playback, scroll the enclosing list by 2 viewports, assert the player is still playing / position not reset.

### 04 H-3 — Failed signed-URL resolution cached for the app session — CONFIRMED, High
- `chat_state.dart:38-43` `signedMediaUrlProvider` is `FutureProvider.family` (not autoDispose); grep over lib/ finds zero `invalidate`/`refresh` of it; `chatRepositoryProvider` (`:28`) is never invalidated either.
- `supabase_chat_repository.dart:415-444` `_createSignedStorageUrl` catches every exception per candidate and returns `null` — the provider lands in `data(null)`, which Riverpod keeps forever.
- Pages load with `resolveMediaUrls:false` (`:209, :256`), so `Message.signedMediaUrl` is null for list rows; `resolved_media_url.dart:51-53` `url ?? signedMediaUrl` therefore has no fallback → `error` widget. Same for voice: `message_bubble.dart:1596-1600` reads `signedMediaUrlProvider(mediaKey).future` → cached null → "That voice message could not play" on every tap until restart.
- Fix: `FutureProvider.autoDispose.family`; let `createSignedMediaUrl` throw when all candidates fail (so the provider is in `error`, not `data(null)`); `ResolvedMediaUrl.error` → tappable retry calling `ref.invalidate(signedMediaUrlProvider(key))`; on `ChatController.loadMessages` success after an error, invalidate the family.
- Test: ProviderContainer test — fake repository throws once then returns a URL; assert second read (after invalidate / re-mount) yields the URL.

### 04 H-4 — delete_message leaves media bytes in the bucket — CONFIRMED, High (privacy)
- Latest definition is `20260950110000_ai_assist_message_edit_delete_split.sql` (live body checked): `UPDATE messages SET content=NULL, media_url=NULL, media_type=NULL, media_thumbnail_url=NULL, deleted_at=now() …` — no `queue_media_deletion`.
- Live triggers on `public.messages` (10 total): the only media-queuing one is `messages_queue_media_before_delete` BEFORE DELETE; nothing fires on UPDATE OF media_url.
- `cleanup_expired_chat_media_intents()` (live) deletes objects only where `intents.used_at IS NULL` — a consumed intent's object is never swept. Signed URLs minted ≤10 min earlier keep working.
- Fix: in `delete_message`, extend the locking SELECT to also read `media_url, media_thumbnail_url`, then `PERFORM public.queue_media_deletion('message-media', v_media_url); PERFORM … (v_thumb)` after a successful UPDATE (inside the same transaction). Alternative: a BEFORE UPDATE OF media_url trigger that queues `OLD.media_url` when `NEW.media_url IS NULL` (covers any future soft-delete path).
- Test: `supabase/tests/message_edit_delete_contracts.sql` — insert image message, call `delete_message`, assert 2 rows in `media_deletion_queue` for the two keys.

### 04 M — orphan Documents/shop_images copies — CONFIRMED, Medium
- `image_picker_service.dart:49-52, 81-99` copies every pick to `Documents/shop_images/<ts>.jpg`; `ImageFileService` (the only other reference, `image_file_service.dart:11`) is not called anywhere in lib/. Nothing in chat deletes it. Fixed for free by the H-1 fix.
- Test: after `_attachImage`, assert no new file under `shop_images`.

### 04 M — upload busy ring shows a stop glyph that does nothing — CONFIRMED, Medium (misleading affordance)
- `video_message_thumbnail.dart:398-413` `Icons.stop_rounded` inside the ring; `message_bubble.dart:1775` `isBusy = isPreparing || isSending`, `:1808-1811` `onTap` null while preparing and `onVideoTap` (play) while uploading — there is no cancel path. Fix: drop the glyph until cancel exists.

### 04 M — strict ftyp allowlist — PARTLY, Low
- `chat_video_preparer.dart:109-120` accepts only `isom, mp42, avc1, M4V , qt  `. Rejects valid `mp41`, `iso2/iso5/iso6`, `hev1`, `3gp*`. Real but rare for camera-roll clips (iOS → `qt  `/`mp42`, Android → `mp42`/`isom`). Fix: any `ftyp` box → `video/mp4` (transcode normalises the container).

### 04 M — StorageException always permanent — CONFIRMED, Medium
- `lib/features/chat/utils/chat_error.dart:83-89` every `StorageException` → `mediaRejected`; `:47-52` `isPermanent` includes `mediaRejected`; `:177` copy always says "That image could not be sent". A 5xx on a voice/video upload fails the send immediately with the wrong wording. Fix: map `statusCode` ≥500/non-numeric → `unavailable` (retryable); copy by media type.

### 06 H-1 — Tap/back while a streak is loading spends the only view — CONFIRMED, High
- `streak_viewer_screen.dart:240-249` `PopScope(canPop:false, onPopInvokedWithResult → _finish)` and `GestureDetector(onTap: _finish)` wrap the whole Stack including the spinner branch (`:287-288`); `:181-184` `_finish → _spendView → markViewed` unconditionally; `_viewSpent` is set before the RPC. Nothing records whether media ever painted. Note `:111-116` also spends on `signed == null` (already unavailable).
- Fix: `bool _hasPresented` set in the two `setState`s that show media (`:124-128`, `:161-165`); in `_finish`, if `!_hasPresented` → `_close()` only (pop null; bubble keeps count per `message_bubble.dart:1690-1691`).
- Test: add to `streak_viewer_states_test.dart` — fake repo whose `fetchClips` never completes; tap; assert `markViewed` not called and route popped with null.

### 06 H-2 — Android chirps request permanent audio focus — CONFIRMED (code), High on Android
- `sound_service.dart:118-120` `AudioContextConfig(respectSilence:true).build()` → `audio_context_config.dart:59` default `focus = gain` → `buildAndroid()` `:94-95` `AndroidAudioFocus.gain` with `usageType notificationRingtone`.
- `WrappedPlayer.kt:211-224` every `play()/resume()` → `focusManager.maybeRequestAudioFocus()` → `FocusManager.kt` `requestAudioFocus(listener, STREAM_MUSIC, AUDIOFOCUS_GAIN)`; focus is abandoned on completion (`onCompletion → stop → handleStop`) but the music app has already received AUDIOFOCUS_LOSS (permanent) — Spotify/YT Music do not resume after LOSS.
- The comment at `sound_service.dart:111-117` reasons only about iOS ambient; it is wrong for Android.
- Fix: `AudioContextConfig(respectSilence:true, focus: AudioContextConfigFocus.none)` (passes `validateIOS`; iOS stays ambient).
- Test: `send_sound_test.dart` — assert the global context passed to `setAudioContext` has `android.audioFocus == AndroidAudioFocus.none`. Device check still worthwhile.

### 06 M-3 — iOS audio session after a voice note — CONFIRMED, Medium
- `voice_message_player.dart:140-142` per-player `setAudioContext(AudioContextConfig(respectSilence:false))` → category `playback`, no `mixWithOthers`.
- `AudioplayersDarwinPlugin.swift:303-320`: per-player `setAudioContext` logs "iOS does not allow for player-specific audio contexts; will set the global audio context instead" and calls `globalContext.apply()` → `AVAudioSession.sharedInstance().setCategory` (`AudioContext.swift:28-33`). Nothing re-applies ambient: `preload()` early-returns on `_ready` (`sound_service.dart:108`), `play()` sets no context.
- Fix: cache an ambient context in `AudioPlayerSoundService` and `await player.setAudioContext(ambient)` before `resume()` (or restore `AudioPlayer.global.setAudioContext(ambient)` in the voice player's complete/pause/dispose).

### 06 M-4 — Bottom overlay paints over the newest message — CONFIRMED (geometry), Medium
- List padding is constant: `chat_screen.dart:3006-3007` (120 / 64), applied `:3315-3322`; nothing measures the overlay (no `SizeChangedLayoutNotifier`/height notifier in the file). The overlay is `Positioned(bottom:0)` Column `:1457-1465` holding typing switcher, `ReplyComposerPreview` `:1552`, `GameComposerBar` `:1567`, `PauseTimerCard` `:1583`, then the composer (`chat_text_field.dart:1396` padding 6/8 + ~48 field + SafeArea) ≈ 62 px + inset — already the whole 64 px keyboard reserve. Any extra strip overlaps the newest bubble.
- Fix: measure the overlay column (GlobalKey + post-frame, or `SizeChangedLayoutNotifier`) into a `ValueNotifier<double>` and use it (+8) as the list's bottom padding.
- Test: widget test with partner typing + keyboard inset; assert the newest bubble's bottom edge is above the typing indicator's top edge.

### 07 H-2 — Chat push waits for the once-a-minute cron — CONFIRMED, High
- `enqueue_message_downstream_work()` (live) does `net.http_post` only to `process-chat-safety-outbox` and `process-chat-notification-outbox`.
- `process-chat-notification-outbox/index.ts:237-254` only INSERTs a `scheduled_notifications` row (status pending, scheduled_for now) and finalises; no call to `process-scheduled-notifications`, no OneSignal.
- Live triggers on `scheduled_notifications`: only `quiet_guard` and `copy_guard` (no pg_net). Only invoker of `process-scheduled-notifications` is `cron.job` `* * * * *` (live cron list; migration 20260907120000:129-131). Grep of supabase/functions for the function name finds only the comment in `push_queue.ts:5`.
- Fix (minimal): after the successful scheduled insert in the outbox worker, fire-and-forget `fetch(${SUPABASE_URL}/functions/v1/process-scheduled-notifications, {service-role headers})`; keep cron as sweeper. Claims are atomic so a concurrent run is safe. (DB alternative: AFTER INSERT trigger on `scheduled_notifications` WHEN status='pending' AND scheduled_for<=now() calling `public.invoke_edge_function('process-scheduled-notifications')` inside EXCEPTION WHEN OTHERS.)
- Test: Deno test for the outbox handler asserting the kick fetch is issued (mock fetch) after insert; p95 send→push under 5 s on device.

### 07 H-3 — OneSignal external_id without identity verification — PARTLY (code confirmed, dashboard unknown), High if IV is off
- `onesignal_service.dart:86, :129` `OneSignal.login(user.id)` with no JWT; `onesignal_push.ts` targets `include_aliases.external_id`. onesignal_flutter 5.5.1 exposes `loginWithJWT(externalId, jwt)` (`onesignal_flutter.dart:75`); no edge function mints an identity token (grep supabase/functions for identity/jwt → none).
- Inference the reviewer missed: if Identity Verification WERE enabled, `login(id)` without a JWT would fail to attach the alias and no chat push would ever target the user — so either IV is off (exposure real) or push is already broken. Either way action is required.
- Fix: edge function signing `{sub: user.id}` with the OneSignal identity key after sign-in → `OneSignal.loginWithJWT(userId, jwt)`; enable IV in the dashboard at the same time.
- Test: integration — login without JWT must be rejected by OneSignal once IV is on.

### 07 M — duplicate push on worker retry — CONFIRMED (possible path), Medium
- `index.ts:237-254` inserts `scheduled_notifications` without `source_key`; `:269-273` any error (including a failed `finalizeJob`) resets the job to pending; `process-scheduled-notifications/index.ts:51` `idempotencyKey: String(job.id)` is per scheduled row, so a second row = second push. `scheduled_notifications_source_key_idx` (unique WHERE source_key IS NOT NULL, live) exists and is unused by this path.
- Fix: `source_key: 'chat_outbox:' + outboxId` and treat 23505 as success (as `push_queue.ts enqueuePush` already does).

### 07 M — Android 13+ never asked for notification permission — CONFIRMED in code, High if device confirms
- `onesignal_service.dart:29-31` `requestPermission(true)` only `if (Platform.isIOS)`; no other call site in lib/. `AndroidManifest.xml:45-48` comment claims the service requests it on startup — contradiction. OneSignal SDK 5 does not auto-prompt on Android 13 (requestPermission is the only prompt path in the plugin). Fix: call `requestPermission(true)` on both platforms after sign-in.
- Test: first launch on Android 14 shows the system dialog.

### 07 M — "Relationship Updates" toggle disables chat pushes — CONFIRMED, Medium
- `index.ts:159-182` suppresses when `booking_reminders_enabled === false`; `notification_config.dart:232-234` binds that column to the toggle labelled "Relationship Updates". Fix: gate on `push_enabled` only (or add `chat_messages_enabled`).

### 07 M — client can insert `is_system_notice = true` — CONFIRMED, Medium
- `information_schema.column_privileges` (live): `authenticated` has INSERT on `messages.is_system_notice`; `messages_insert_sender_active` WITH CHECK only requires `sender_id = auth.uid()` + active unarchived relationship; no trigger function body in `public` references `is_system_notice`. Fix: revoke the column grant; route the screenshot notice (`supabase_chat_repository.dart:317`) through a SECURITY DEFINER RPC.
- Test: SQL contract — as authenticated, INSERT with is_system_notice=true must fail.

### 05 H-2 — Edited marker hidden: NOT a documented product decision — CONFIRMED regression, High
- `git log -S'showEdited'` → single commit f29007b6 "fix(chat): make video handling robust — rotation, expired URLs, pending state". Its message lists three video root causes and never mentions edits; the diff added the `showEdited` flag and passed `false` at the only call site while reworking the footer ("only for the few visible footer markers that should remain" — `_MessageMeta` doc comment).
- The test expectation `find.text('edited'), findsNothing` was introduced by 4d1d52c5 "wip: chat media, voice recorder UX, permissions, relationship sync" (a wip commit), replacing 218331f3's `findsOneWidget`. No spec, ADR or test comment records a decision.
- Spec `docs/superpowers/specs/2026-08-13-message-actions-design.md:38-39` (decision 2: history kept, not just a tag) and `:342-346` "Edited label + history view: when editedAt != null render a small 'edited' label … tap opens history" still require it. `CHAT_SYSTEM_SPEC.md` has no contrary statement.
- Fix: `showEdited: message.editedAt != null` and force `hasVisibleFooter` true when edited (or render the label inline after the text); flip the test back to `findsOneWidget`.

## Refuted / downgraded
- 04 M ftyp allowlist: downgraded to Low — real but rare brands; no camera-roll clip from iOS/Android stock cameras is affected.
- 07 M-3 duplicate push: stays Medium but requires a failure between the scheduled insert and `finalizeJob`; dedupe index already exists, fix is one field.
- 04 H-2: the spec's "stops when leaving the screen" rule is deliberate; only the scroll-out behaviour is a defect — fix must preserve the route-pop stop.
- Nothing was refuted outright: every High in 04/06/07/05-H2 traced to real code or live schema. Confidence caveats remain only where hardware/dashboard is needed (06 H-2 device audio, 07 H-3 dashboard IV, 07 M-5 Android 14 prompt).
