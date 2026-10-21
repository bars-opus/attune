# 06 — Motion, sound, haptics, streaks, games-in-chat

## Summary
Motion is in good shape: arrivals are identity-based and play exactly once, cached history never animates on cold start, every primitive honours reduce-motion, controllers/overlays are disposed, and the composer→bubble / reply / reaction flights are robust to recycled rows. Sound is correct on the happy path (no double-fire across realtime + gap-fill, preloaded, toggle respected) but the audio-session choice very likely pauses the user's music on Android and loses the silent-switch guarantee on iOS after a voice note. Streak viewing has one genuine content-loss bug (a tap on the loading screen burns the only view) and a failed-upload state that lies. Games-in-chat is structurally sound (one row per session, sort_at ordering, cache/pagination/search all tolerate cards) but a partner's move produces no feedback and the card teleports. Nothing here loses or duplicates a message; 2 High, 7 Medium, 6 Low.

## Findings

### H-1: Tapping (or swiping back) while a streak is still loading burns the recipient's only view
- Severity: High (irreversible content loss for the recipient; sender gets a false "Opened" receipt)
- Confidence: Confirmed (traced client → RPC)
- Evidence: `lib/features/chat/presentation/screens/streak_viewer_screen.dart:255-268` (`PopScope.onPopInvokedWithResult` → `_finish()`, `GestureDetector(onTap: _finish)` wraps the whole Stack including the `CircularProgressIndicator` branch at :296); `:198-216` `_spendView()` calls `markViewed` unconditionally; `mark_streak_viewed` (live def in `attune_spec3a`, from `20260930120000_media_deletion_queue.sql`) stamps `viewed_at`, decrements, and at 0 queues the clips for deletion and deletes `streak_clips`.
- Failure scenario: recipient taps "Play" on a 1-view streak; `fetchClips` + `createSignedMediaUrl` + `VideoPlayerController.initialize()` take 2–3 s on mobile data; the black screen with a spinner reads as "nothing happened" so they tap it (or swipe back) → `_finish` → view spent, clips deleted. Bubble now says "Opened", sender sees "Opened", nobody ever saw the clip.
- WhatsApp/iMessage expectation: a view-once item is only consumed once the media is actually displayed; backing out of a still-loading viewer costs nothing.
- Fix: track `_hasPresented = true` when the first `setState` that shows a video/image runs (`_playAt` at :117-123 / :155-159). In `_finish`, if `!_hasPresented`, skip `_spendView` and `pop(null)`; the bubble already keeps its count when `left == null` (`message_bubble.dart:1690-1691`). Optionally add an explicit close affordance instead of whole-screen tap during loading.

### H-2: On Android every send/receive chirp requests permanent audio focus — the user's music pauses and does not resume
- Severity: High (user-visible breakage of a very common scenario: chatting while listening to music/podcast)
- Confidence: Likely (confirmed from package source; not run on a device)
- Evidence: `lib/core/ui/feedback/sound_service.dart:118-120` sets `AudioContextConfig(respectSilence: true).build()` globally. In `audioplayers_platform_interface-7.1.1/lib/src/api/audio_context_config.dart:59` the default is `focus = AudioContextConfigFocus.gain`, and `buildAndroid()` (:86-99) maps that to `AndroidAudioFocus.gain` (= AUDIOFOCUS_GAIN, permanent) with `usageType: notificationRingtone`. Every `play()` (`sound_service.dart:159` `resume()`) therefore requests permanent focus; Spotify/YouTube Music receive AUDIOFOCUS_LOSS and stop for good.
- Failure scenario: Android user plays music, opens chat, sends "hi" → music stops; it stays stopped. Each received message while the chat is open does the same.
- WhatsApp/iMessage expectation: UI chirps mix with (or at most briefly duck) other audio; music never stops.
- Fix: `AudioContextConfig(respectSilence: true, focus: AudioContextConfigFocus.none)` in `preload()` (passes the package's own validation; iOS stays `ambient`, which is mixable by default). Keep `notificationRingtone` if you want chirps on the ring volume/DND, otherwise also pass `route`/usage for `media`.

### M-3: After a voice note plays, iOS chat sounds ignore the silent switch and interrupt other apps' audio
- Severity: Medium
- Confidence: Likely (AVAudioSession is process-global; audioplayers_darwin applies a per-player context to the shared session)
- Evidence: `lib/features/chat/presentation/widgets/voice_message_player.dart:140-142` calls `_player.setAudioContext(AudioContextConfig(respectSilence: false).build())` → category `playback`, no `mixWithOthers`. Nothing ever re-asserts the ambient context: `AudioPlayerSoundService.preload` runs once (`sound_service.dart:107-109` early-returns on `_ready`) and `play()` (:149-160) never sets a context.
- Failure scenario: phone on silent, user listens to one voice note; from then on every send/receive chirp plays audibly through the silent switch and pauses Spotify (playback category, non-mixable) until the app restarts.
- WhatsApp/iMessage expectation: voice notes play on silent (deliberate tap); UI chirps always respect the switch and never interrupt music.
- Fix: in `AudioPlayerSoundService.play`, call `player.setAudioContext(_ambientContext)` (cached `AudioContextConfig(respectSilence: true, focus: none).build()`) before `resume()`; or have `VoiceMessagePlayer` restore `AudioPlayer.global.setAudioContext(ambient)` on completion/stop/dispose.

### M-4: Typing indicator (and staged-game bar / reply strip / pause card) paint over the newest message instead of pushing the list up
- Severity: Medium (noticeable roughness; the newest bubble is hidden exactly when the partner is typing)
- Confidence: Likely (layout traced; not pixel-measured)
- Evidence: the list reserves a constant bottom padding — `chat_screen.dart:3005-3006` (`_messageListBottomReserve = 120`, `_messageListKeyboardBottomReserve = 64`), applied at :3368-3375. The bottom overlay is a `Positioned(bottom: 0)` transparent `Column` (`:1457-1465`) whose children are, in flow above `ChatTextField`: the typing `AnimatedSwitcher` with `Padding.fromLTRB(16, 30, 16, 8)` + a 29 px bubble (`:1467-1545`), `ReplyComposerPreview` (`:1548-1562`), `GameComposerBar` (`:1566-1580`, 40.h avatar + 2×Spacing.md padding), `PauseTimerCard` (`:1582-1587`). `ChatTextField` alone is ≈48 min-height + 6/8 padding + SafeArea (`chat_text_field.dart:1397, 1712`).
- Failure scenario: keyboard open (reserve 64 ≈ composer height), partner starts typing → a ≈67 px typing bubble is drawn directly over the bottom of the newest message. Same with a staged game (≈90 px bar) or a reply strip: the message you are replying to can be covered while you type. `message_list_padding_test.dart` only pins the constants, not the stack height.
- WhatsApp/iMessage expectation: typing indicator, reply strip and attachment staging all displace the transcript; nothing is painted over a message.
- Fix: measure the bottom column (wrap it in a `SizeChangedLayoutNotifier`/`GlobalKey` and store its height in a `ValueNotifier`) and use `height + 8` as the list's bottom padding; or render the typing indicator as a virtual index-0 row of the `ListView` (WhatsApp's model) so it lives inside the scroll geometry.

### M-5: A partner's game move gives zero feedback — the card silently teleports, while the trail animates in the middle of history
- Severity: Medium
- Confidence: Confirmed (migration + client traced)
- Evidence: `move_game_card` (live def; `20260932180000_game_card_moves_sides.sql`) keeps the card's `id`/`client_message_id`/`created_at` and only rewrites `sender_id` + `sort_at`; `leave_game_trail` inserts a NEW row with a fresh `client_message_id` at the card's OLD `sort_at`. Client: `message_arrival_tracker.dart:42` keys arrivals on client ids → the moved card is never an "arrival" (no `MakeRoom`/`SettleIn`, `chat_screen.dart:3449-3454, 3660-3690`), whereas the trail IS (it is new) and animates wherever it lands; `chat_state.dart:631-650 _maybeReceiveHaptic` picks the newest partner message by `createdAt`, so the moved card (old `createdAt`) never triggers the receive haptic/sound; `_mergeMessages` (:2414-2418) deliberately lets games re-sort to the new `sort_at`.
- Failure scenario: A and B chat after sending a Snakes invite; B plays a move. On A's open chat the card jumps from mid-history to the bottom and flips sides with no motion, sound or haptic; simultaneously a "Snakes and Ladders" trail line slides/fades into place 20 messages up (and shimmers if it is first-of-day) where A isn't looking. If the game is older than the first page, the trail isn't even fetched until a scroll-back.
- WhatsApp/iMessage expectation: a partner's move arrives like a new message — settles in at the bottom with the receive sound/haptic; nothing animates off-screen.
- Fix: (a) in `_maybeReceiveHaptic` compare on `(sortAt, id)` of partner-owned rows instead of `createdAt`; (b) in `MessageArrivalTracker.sync` also report a known id whose position moved ahead of the previous newest id (pass `(clientId, sortAt)` pairs) and never report a new id whose `sortAt` is older than the newest already seen (the trail); (c) consider having the trigger stamp the card's `created_at`-independent "moved_at" so the client can show a tiny "Your move"/"Their move" header. Server side, the trail could be inserted with `sort_at = v_card.sort_at - interval '1 microsecond'` to guarantee it sorts just above the card's old slot (today the two rows tie on `sort_at` and order falls to id).

### M-6: A failed streak upload keeps spinning "Sending…" under a "Failed — Retry" footer
- Severity: Medium (stuck/contradictory state in a core send flow)
- Confidence: Confirmed
- Evidence: `message_bubble.dart:1663-1664` passes `isSending: message.id.startsWith('_local_')` to `StreakBubble`; `StreakBubble` (`streak_bubble.dart:61-81`) has no failed state and shows a `CircularProgressIndicator` + "Sending…". A failed row keeps its `_local_` id with `MessageStatus.failed` (`message.dart:512`), and the footer simultaneously offers retry/remove (`message_bubble.dart:388-391`, `_MessageMeta`).
- Failure scenario: airplane mode → record a streak → send → after `_maxAutomaticSendAttempts` the row is failed: bubble body spins "Sending…" forever while the footer says it failed.
- WhatsApp/iMessage expectation: a failed media send shows a clear "not sent" state with a retry affordance, never a spinner.
- Fix: `isSending: message.id.startsWith('_local_') && !message.isFailed` and add an `isFailed` branch to `StreakBubble` ("Not sent", tap → `onRetry`).

### M-7: A message that arrives while the user is scrolled up animates minutes later, under their finger, when they scroll back down
- Severity: Medium (jank / wrong-time animation)
- Confidence: Likely
- Evidence: arrivals are queued in `_pendingArrivalIds` (`chat_screen.dart:3012, 3067-3074`) and consumed only inside `itemBuilder` (:3449-3454). A row that is not built when it arrives stays pending indefinitely; when it is finally built, `MakeRoom(animate: true)` grows its slot from 0 (:3658-3661) and `SettleIn` slides it, plus `Shimmer` if first-of-day (:3620-3627).
- Failure scenario: user is 3 screens up re-reading; partner sends two messages; two minutes later the user flings to the bottom — two rows open their slots mid-fling (the scroll offset jumps by their heights) and settle in as if they had just arrived.
- WhatsApp/iMessage expectation: messages that arrived while you were away are simply there; a "new messages" pill/arrow invites you down.
- Fix: in `_syncArrivals`, if `scrollController.hasClients && position.pixels > position.viewportDimension * 0.5`, add the ids to `animatedMessageIds` instead of `_pendingArrivalIds` (treat as seen) and surface a scroll-to-bottom pill; alternatively time-box pending ids (drop after ~800 ms).

### M-8: The 30-minute streak replay window is enforced only after the extra replay has already played
- Severity: Medium (a privacy rule the sender was told about is bypassed once)
- Confidence: Confirmed (order of operations traced)
- Evidence: `streak_viewer_screen.dart:76-92` `fetchClips` → `:100-127` signs and plays the clip → only on finish `:198-216` calls `mark_streak_viewed`, whose `ELSIF v_viewed_at < now() - interval '30 minutes'` branch destroys the clips and returns 0 (live def). `streak_clips_members_read` RLS and `fetchClips` (`streak_repository.dart:103-113`) don't consider the window, and `createSignedMediaUrl` signs any existing key.
- Failure scenario: sender allowed replays (budget 3); recipient watches once at 10:00, then opens it again at 11:30 — the clip plays in full, and only afterwards the server says "expired" and deletes it. The bubble read "Play 2x" the whole time (no client-side window check).
- WhatsApp/iMessage expectation: an expired view-once/replay item refuses to open at all.
- Fix: gate the read: a `SECURITY DEFINER` RPC (`streak_clips_for_viewing(p_message_id)`) that returns rows only when the budget > 0 and `viewed_at IS NULL OR viewed_at > now() - 30 min` (and expires server-side otherwise), used by `fetchClips`; mirror the window on the bubble (`viewedAt` is already on the row) so it reads "Opened" after 30 min without a tap.

### M-9: Timestamp-reveal drag rebuilds every visible MessageBubble on each pointer delta
- Severity: Medium (120 Hz jank risk on media/game-heavy screens)
- Confidence: Possible (not profiled)
- Evidence: each row is `ValueListenableBuilder<double>(valueListenable: _timestampRevealOffset, builder: (…) => MessageBubble(…))` (`chat_screen.dart:3480-3484`), so every pointer move during the left-swipe rebuilds the whole bubble: `IntrinsicWidth` (double layout, `message_bubble.dart:444`), the nested `Stack`/`UniversalBubble`, reaction adornments, and for game rows a `ConsumerWidget` with `ref.watch` (`game_message_bubble.dart:120`).
- Failure scenario: swipe left to peek at timestamps on a screen with a media group and two game cards — frame times climb visibly on mid-range Android.
- WhatsApp/iMessage expectation: the reveal is a cheap translate of already-laid-out rows.
- Fix: keep the bubble subtree constant and apply the reveal with an `AnimatedBuilder` that only wraps the `Transform.translate` + the `_RevealTimestamp` column (pass `timestampRevealOffset` via an `InheritedNotifier` read by those two leaves), so `MessageBubble` itself is not rebuilt per delta.

### L-10: Haptics are inconsistent — none on long-press menu or reaction pick
- Severity: Low
- Confidence: Confirmed
- Evidence: swipe-to-reply fires `HapticFeedback.lightImpact()` at threshold (`universal_bubble.dart:862-864`); send `light` (`chat_screen.dart:367`), receive `selection` (`chat_state.dart:644`), game sent `selection` (`chat_screen.dart:1010`), voice/streak capture `medium`/`light`. No haptic anywhere in `message_bubble.dart`/`message_actions_sheet.dart` for long-press open or reaction selection (grep), and the reaction flight/landing is purely visual.
- Failure scenario: long-press a bubble → menu + snapshot appear silently; pick ❤️ → flight + splash with no tactile beat.
- WhatsApp/iMessage expectation: haptic on long-press menu open and on choosing a reaction.
- Fix: `hapticsProvider.light()` where `UniversalBubble` invokes `onLongPress` (`:655`), `selection()` in the reaction picker's tap handler before `onReact`.

### L-11: Reduce-motion gaps in three places
- Severity: Low
- Confidence: Confirmed
- Evidence: typing `AnimatedSwitcher` fixed 260/180 ms with a `ScaleTransition` (`chat_screen.dart:1481-1530`); `StreakRecordButton` entrance tweens (`streak_record_button.dart:155-183`); `_scrollToLatest` 250 ms and `Scrollable.ensureVisible` 400 ms (`chat_screen.dart:1296-1303, 609-614`). Everything else checks `reduceMotionOf`.
- Failure scenario: with iOS Reduce Motion on, the typing bubble still pops/scales and the record disc still springs.
- WhatsApp/iMessage expectation: no scale/spring motion under Reduce Motion.
- Fix: `Duration.zero` / `jumpTo` under `reduceMotionOf(context)` at those sites.

### L-12: Send sound/haptic fire before validation and are skipped on alternate send paths
- Severity: Low (one edge case loses text)
- Confidence: Confirmed
- Evidence: `_send()` plays the chirp and haptic (`chat_screen.dart:367-370`) before `_sendDraftText` clears the controller (:719) and `sendMessage` returns silently when `!Message.isValidContent` (`chat_state.dart:683`; limit `maxContentRunes = 10000`, `message.dart:13`); `ChatTextField` sets no `maxLength`. Translator "send original/rewrite" (`:1273-1280`) and the staged-game caption (`:992-995`) call `_sendDraftText` directly — no chirp/haptic; `_sendStagedGame` itself plays only `selection()` on success. `StreakCameraScreen` plays `streakSend` (`:243`) even when `sendStreakMessage` bails on `canSend`/missing file.
- Failure scenario: paste a 12 k-character message, tap send → "sent" chirp, composer empties, nothing is sent and nothing says so.
- WhatsApp/iMessage expectation: the send sound means the message was accepted; a too-long message is refused before clearing.
- Fix: move the chirp/haptic into `_sendDraftText` after a local `Message.isValidContent` check (and keep the text in the composer on failure); add `maxLength: Message.maxContentRunes` with `MaxLengthEnforcement`; play the send chirp in `_sendStagedGame` on success.

### L-13: Game card has no offline/error state and mislabels in read-only transcripts
- Severity: Low
- Confidence: Confirmed
- Evidence: `game_message_bubble.dart:150-153` label is "…" whenever `session.valueOrNull == null` (loading OR `.stream()` error), `:160-164` `isOpenable` false in that state, so the card is inert; `fallbackLabel` only feeds the title. `message_bubble.dart:1645` passes `viewerId: viewerId ?? ''` — `currentUserId` is null for read-only/ended conversations (`chat_screen.dart:3579-3583`), so `gameCardLabel` renders "You lost"/"$partner's move" regardless of who the viewer is.
- Failure scenario: cold start offline from the encrypted cache — every game card shows "…" and ignores taps with no explanation; in Previous Relationships a game you won reads "You lost".
- WhatsApp/iMessage expectation: an offline card still shows its last known state and opens.
- Fix: on `session.hasError` (or `!isOnline`) render `fallbackLabel` + "Tap to open" and allow the tap (route by `gameType` from the last known state or a cached label); pass the real user id for read-only transcripts (actions are gated separately by `canOpenActions`).

### L-14: Conversations preview and search treat game cards/trails as plain text
- Severity: Low (no breakage of pagination/cache; cosmetic)
- Confidence: Confirmed
- Evidence: `conversation_preview.dart:23-28` labels only image/video/audio/streak; `game`, `game_trail`, `place` fall through to `message.content` (the game's display name, written by `post_game_message`). `_fetchLastMessage` orders by `sort_at` (`supabase_chat_repository.dart:872-878`) so a moved card correctly becomes the last message, but the row then reads just "Snakes and Ladders" (and identically for each trail). `searchMessages` is `ilike('content', …)` on all rows (`:1108-1114`), so card + every trail row match "snakes".
- Failure scenario: Conversations list shows "Snakes and Ladders" with no hint it is a game or whose move it is; search "snakes" lists 5 identical "Snakes and Ladders" hits, 4 of them trails.
- WhatsApp/iMessage expectation: "🎮 Snakes and Ladders — your move"-style preview; trails not searchable.
- Fix: add `'game': 'Game'` / `'game_trail'` (skip or "Game") / `'place'` labels in `conversationPreviewText`; `.neq('media_type', 'game_trail')` in `searchMessages`.

### L-15: "Expressive moments" is respected but barely perceptible
- Severity: Low
- Confidence: Confirmed
- Evidence: `chatExpressivenessProvider` is read in exactly one place (`chat_screen.dart:3184-3185`) and only changes the first-of-day shimmer period (1600→1100 ms, `:3620-3627`) and the reconnect cascade step (35→70 ms per row, `:3634-3640`; tokens in `motion_tokens.dart:34-40`). Settings copy promises "A little more life in chat animations" (`settings_screen.dart:132-135`). "Thankful for you" phrasing is correctly threaded to `showAppreciationSheet` (`chat_screen.dart:1635`).
- Failure scenario: user toggles Expressive on and sends/receives normal messages — nothing visibly changes.
- WhatsApp/iMessage expectation: n/a (polish); a toggle should do something you can see.
- Fix: either widen what the flag drives (emoji-arrival scale/sparkles in `LiveMessageMotion`, reaction landing splash radius, typing-bubble pop) or soften the copy to "Slightly livelier first-of-day and catch-up animations".

## Done well
- Arrival animation is identity-based (`MessageArrivalTracker`), baselines on the first settled snapshot (`ChatState.initial.isLoading = true`, so a cold start never animates history), filters pagination pages, and `_animatedMessageIds` is a screen-lifetime ledger so recycled rows never replay. `MakeRoom` + `SettleIn` open the slot by the real content height — the displacement reads exactly like iMessage.
- Payload flights (send, reply to/from composer, reaction, staged game) wait for the real destination rect, fall back gracefully, hide the real bubble while flying, and clean up with `mounted`/epoch guards; overlays remove themselves; every `AnimationController` in the area is disposed.
- Receive sound/haptic cannot double-fire across `_catchUpFromCursor` + `loadMessages` (shared `_lastPartnerMessageId`), excludes own/optimistic/initial-history rows, and is gated on `_isViewActive` (route current + foreground), so a backgrounded chat is silent and the push carries the sound. Send chirp is preloaded at app start with low-latency players and fails silently.
- Reduce-motion is honoured by every motion primitive (`SettleIn`, `MakeRoom`, `Shimmer`, `GlowPulse`, `BreathingDots`, flights, landing, `LiveMessageMotion`, emoji artwork, header drawer, composer tweens). `Shimmer`/`GlowPulse` are bounded moments, not perpetual tickers.
- Typing: throttled broadcasts, 5 s auto-expiry, inactivity decay, own-echo ignored, stop sent on dispose.
- Games: staging never touches the server until Send; the idempotency key survives retries; caption-first ordering; failure keeps the game staged with a message; one row per session (unique partial index) streamed live from sessions + rounds with autoDispose + 30 s keep-alive; `sort_at` keyset pagination and the encrypted cache (`sortAt`, `gameSessionId` serialised) handle moved cards correctly.
- Streaks: budget is server-owned through `mark_streak_viewed` (sender replays never spend; spend-once guard; media deletion queued), the bubble reveals nothing pre-open, retry re-attaches a missing clip without re-uploading, and the camera pops immediately with the upload behind the optimistic bubble. The streak COUNTER was fully removed (Spec 1b; `20261017190000_drop_chat_streak_counter.sql`; no client references remain) — only the streak camera remains, so there is no midnight/time-zone logic left to get wrong.

## Not verified
- Device audio behaviour (H-2, M-3) was established from the audioplayers 6.6 / platform_interface 7.1.1 source and AVAudioSession semantics, not by running on hardware.
- Pixel-level overlap in M-4 was reasoned from the widget tree and constants; no widget test was run to measure it.
- Realtime channel pressure: each visible game card opens two `.stream()` channels; a game-dense transcript could approach Realtime's per-client channel limit. Not measured.
- Whether OneSignal plays a sound for a foregrounded app on the Conversations screen (chat not open) — outside this area.
- No `flutter test` was run; findings are from code and schema reading (local `attune_spec3a` for triggers, RLS, function bodies, publication membership).
