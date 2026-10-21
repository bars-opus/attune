# 03 — Local cache, persistence & cold start

Scope: `lib/features/chat/data/cache/*`, the cache call sites in `chat_state.dart` / `chat_screen.dart` / `conversations_screen.dart` / `auth_provider.dart`, media file caching in the chat widgets, Android backup rules, and the `messages` schema in the scratch DB (`attune_spec3a`).

## Summary

The foundation is sound and better than most: an AES-256-GCM-encrypted SQLite cache with the key in the platform keystore, a durable outbox written *before* any network call (including upload keys and the raw-source preparation stage), cache-first paint for both the conversation list and the chat with a silent background refresh, and an incoming-wins merge that keeps reactions/edits across restarts. Kill-mid-send and kill-mid-sync are safe (whole-blob upserts, outbox persisted first).

What stops it being WhatsApp-level is **reconciliation, not storage**: the cache is a per-conversation JSON blob that is only ever *merged into*, never trimmed against the server. Server-side deletes (including the owner's "delete everything" before testing) leave permanent ghosts until sign-out, and any edit/delete/reaction to a message older than the newest 50 rows never reaches the other phone. Cold-start robustness has two real gaps (unguarded DB/keystore init in `main()`; offline cold start skips the outbox flush), and all SQLite + pure-Dart AES work runs on the UI isolate (drafts on every keystroke). Received voice notes and videos are never cached to disk.

## Findings

### H-1: Server-deleted messages become permanent local ghosts — fresh fetch merges, never removes
- Severity: High
- Confidence: Confirmed (code + DB)
- Evidence:
  - `lib/features/chat/presentation/state/chat_state.dart:2395-2475` `_mergeMessages` seeds `byId` from `state.messages` and overlays `incoming`; nothing is ever removed. `loadMessages` (`:541-566`) calls `_mergeMessages(messages)` then `writeMessages(state.messages)` — so an empty/shorter server page re-persists the stale rows. `_appendOlderMessages` (`:2477-2485`) only adds unknown ids.
  - Realtime cannot rescue it: `public.messages` has `relreplident = 'd'` (DEFAULT) in `attune_spec3a`, and `watchConversationEvents` filters on `relationship_id=eq.<id>`; a Postgres DELETE event only carries the PK under default replica identity, so the filtered channel never fires for a hard delete.
  - Hard deletes exist in product paths, not just ops: `delete_chat_import` / `20261018160000_sync_fixes.sql:43` (`DELETE FROM public.messages WHERE import_job_id = ...`), `messages_game_session_id_fkey ON DELETE CASCADE`, `messages_relationship_id_fkey ON DELETE CASCADE`.
  - Purge happens only on `clearAll()` at sign-out (`auth_provider.dart:131-137`) or when the relationship disappears/archives (`chat_state.dart:470-500`).
- Failure scenario: Owner runs `DELETE FROM messages` (or deletes a WhatsApp import) → both phones open the chat → every old message is still there, forever; pull-to-refresh, restart, reconnect all re-merge and re-write the same ghosts. Partner replies → new row appears *under* the ghosts. Only sign-out/sign-in clears it. During the manual two-phone test this will look like "sync is broken".
- WhatsApp/iMessage expectation: what the server no longer has is gone on the next open.
- Fix: make the fetched page authoritative for its own window. In `loadMessages` (first page) and `loadMoreMessages`: let `window = fresh.isEmpty ? all canonical rows : canonical rows with sortAt >= fresh.last.sortAt` (for `loadMore`: rows between the cursor and `older.last.sortAt`); drop any canonical (non-`_local_`) row in that window whose id is not in `fresh`, keep `_local_` rows. One helper `_reconcileWindow(List<Message> fresh, {ChatMessageCursor? before})` used by both, then `writeMessages`. Optional server side: `ALTER TABLE public.messages REPLICA IDENTITY FULL` so filtered DELETE events are delivered live (cost: larger WAL on updates).

### H-2: Edits / deletes / reactions / receipts on messages older than the newest 50 never reach the other phone
- Severity: High
- Confidence: Confirmed
- Evidence: realtime handler (`chat_state.dart:506-535`) runs `_catchUpFromCursor()` (newer-than-cursor only, `:574-614`) then `loadMessages(silent: true)` (first `messagePageSize` = 50 rows, `chat_config.dart:17`). Rows 51–200 come from the on-disk cache (`chat_cache_service.dart:11`, 200 cap) and `_appendOlderMessages` (`:2477-2485`) skips ids already present, so paging back never refreshes them either. Reactions are hydrated per page (`supabase_chat_repository.dart:924-931`), so they share the same path.
- Failure scenario: Active couple with >50 messages today. Partner long-presses a photo from this morning (60 messages back) and reacts ❤️, or deletes/edits it → your phone shows nothing, and keeps showing nothing after restart (the stale row is in your 200-row cache and is re-written every sync). The same applies to the sender's own ticks: a delivered/read receipt UPDATE on an older message is never pulled. It self-heals only after the row ages out of the 200-row cache *and* you re-page, or after sign-out.
- WhatsApp/iMessage expectation: a reaction or deletion shows up live wherever the message is.
- Fix: (a) same `_reconcileWindow` as H-1 with incoming-wins on `loadMoreMessages`, and (b) on each realtime event fetch the touched rows: `watchConversationEvents` already receives the row payload (UPDATE events include the full new record); surface the `id` on the stream and have the handler call a new `repository.getMessagesByIds([...])` (one `in` query with `_hydrateMessages`) merged via `_mergeMessages`. Debounce ids into one query per 250 ms window like the existing refresh debounce.

### H-3: Cache init is unguarded in `main()` — a corrupted/locked DB or a hung keystore means the app never starts
- Severity: High (app does not open; unrecoverable without reinstall)
- Confidence: Confirmed gap (probability: Possible)
- Evidence: `lib/main.dart:45-46` `await chatCache.init()` before `runApp`; `chat_cache_service.dart:39-47` guards only the cipher, not `_backend.init()`; `chat_cache_backend_io.dart:29-70` opens the file and runs `PRAGMA journal_mode = WAL` + 4 `CREATE TABLE`s with no try/catch; `ChatCacheCipher.create()` (`chat_cache_cipher.dart:43-61`) awaits `storage.read` with no timeout, although `main.dart:86` already applies a 3 s timeout to the keystore for the safety lock because of "a hung keystore (seen on some Samsung phones)". Spec `CHAT_SYSTEM_SPEC.md:1067` requires "Drift migration/corruption fails → Rebuild read cache from server; preserve recoverable queue".
  - Runtime variant: `ChatController._init` (`chat_state.dart:349-356`) `await`s `readMessages` first; `ChatState.initial` has `isLoading: true` (`:2709-2721`). Any SQLite exception there (disk I/O, `SQLITE_BUSY`, `SQLITE_FULL`) aborts `_init` before `_subscribeToRealtime`/`loadMessages`, leaving the chat on a spinner for the controller's lifetime (5 min keep-alive).
- Failure scenario: Phone runs out of storage / app is killed during a WAL checkpoint / sqlite file truncated → next launch: white screen, no error, every launch. Or Samsung keystore hangs → splash forever. Or a transient `SQLITE_BUSY` on open → chat never loads.
- WhatsApp/iMessage expectation: a broken local DB is rebuilt silently; the app always opens.
- Fix: in `ChatCacheService.init()` wrap `_backend.init()` in try/catch; on `SqliteException` delete `attune_chat_cache.sqlite{,-wal,-shm}` and retry once; on second failure fall back to the in-memory backend (`chat_cache_backend_stub.dart`) so every call is a no-op instead of a throw. Wrap `ChatCacheCipher.create()` in `.timeout(const Duration(seconds: 3))`. In `ChatController._init`, wrap the two cache reads in try/catch → `[]`, and in `ChatCacheService` catch backend exceptions in `readMessages/readOutbox/readConversations/readDraft` (return empty) so a runtime SQLite error degrades to a cache miss.

### H-4: Offline cold start aborts `_init` before the outbox flush — queued messages from the previous session are never sent on reconnect
- Severity: High (stuck "queued" messages)
- Confidence: Confirmed by trace (Likely that `getConversations` throws rather than returns offline — it is a plain PostgREST select, so a `SocketException`/`ClientException` propagates)
- Evidence: `chat_state.dart:371-379`: `final conversationRefresh = _refreshConversation(); await loadMessages(...); await conversationRefresh;` — `loadMessages` catches internally, `_refreshConversation` (`:470-500`) does not; the rethrow at `await conversationRefresh` skips `:380-403` including `flushOutbox()` (`:403`). The only other flush triggers are the backoff timer set after a *failed attempt in this session* (`:2253-2257`) and a manual `retryMessage`; the realtime handler (`:506-535`), which does fire a synthetic event on every (re)subscribe (`supabase_chat_repository.dart:637-640`), never calls `flushOutbox()`.
- Failure scenario: Last night, three messages were typed with no signal and the app was swiped away. Morning, still in airplane mode: open app → chat → messages show with the clock icon (good). Turn airplane mode off, stay in the chat: nothing is sent — ever, while that controller lives. They go only after leaving the chat for >5 min and re-entering online, or after tapping each one. Also skipped: `_refreshPinnedMessages`, `_refreshStarredMessageIds`, `_markPartnerMessagesDelivered`.
- WhatsApp/iMessage expectation: the moment the network returns, queued messages go out in order with no interaction.
- Fix: in `_init`, `try { await conversationRefresh; } catch (_) {}` (header metadata is best-effort) so `flushOutbox()` always runs; add `unawaited(flushOutbox())` at the end of the realtime debounce handler (it is already serialized by `_isFlushing`, so the extra call is cheap and makes "subscribed after reconnect" the flush trigger it should be).

### M-1: All SQLite I/O and AES-GCM run synchronously on the UI isolate — drafts are encrypted and fsync'd on every keystroke
- Severity: Medium (jank, worst on mid/low-end Android)
- Confidence: Confirmed by code (timing not measured on device)
- Evidence: `chat_cache_backend_io.dart:34` `NativeDatabase(file)` — not `NativeDatabase.createInBackground` (available in drift 2.31.0, `native.dart:160`), so every `customStatement` executes on the main isolate; no `PRAGMA synchronous`, so WAL commits fsync (default FULL). `chat_screen.dart:229-230` `_onDraftChanged` → `_persistDraft()` with no debounce → `writeDraft` → `ChatCacheCipher.encryptString` (pure-Dart pointycastle GCM) + upsert per keystroke. `writeMessages` serialises and encrypts up to 200 messages and is called twice per realtime event (`_catchUpFromCursor` `:600` and `loadMessages` `:560`) plus on every send success (`:1995`, `:2060`, `:2181`).
- Failure scenario: Typing fast in a long chat while messages arrive → periodic dropped frames; on a slow eMMC device each keystroke includes an fsync.
- WhatsApp/iMessage expectation: typing never stutters; persistence is off the UI thread.
- Fix: `NativeDatabase.createInBackground(file)` (one-line change, API identical); `PRAGMA synchronous = NORMAL` after WAL (safe: WAL+NORMAL loses at most the last transaction on power loss, never corrupts); debounce `_persistDraft` ~400 ms and flush in `deactivate()`; optionally move `jsonEncode`+encrypt into `compute()`.

### M-2: Received voice notes and videos are never cached to disk; chat photos share the app-wide 200-object image cache
- Severity: Medium
- Confidence: Confirmed
- Evidence: `voice_message_player.dart:124-134` plays `UrlSource(signedUrl)` for every tap; `video_message_player.dart:200-204` `VideoPlayerController.networkUrl` for anything not the sender's local file; no `CacheManager`/`getSingleFile`/temp-file download anywhere in `lib/features/chat` for audio/video (grep). Images/posters use `CachedNetworkImage(cacheKey: mediaKey)` (`message_bubble.dart:1498-1508`, `chat_media_group.dart:250-252`) through `DefaultCacheManager`, whose defaults are `maxNrOfCacheObjects: 200`, `stalePeriod: 30 days` (flutter_cache_manager 3.3.1 `_config_io.dart:16-17`) — shared with avatars, stories, map pins, etc. No custom `CacheManager` config exists in `lib/`.
- Failure scenario: Replay a 1-minute voice note → full re-download each time; on the train with no signal, every received voice note and video says "could not play"; a photo-heavy week pushes older chat photos out of the 200-object cache so scrolling back re-downloads them (and re-signs URLs).
- WhatsApp/iMessage expectation: media is downloaded once and plays offline forever after.
- Fix: one `CacheManager(Config('attune_chat_media', maxNrOfCacheObjects: 5000, stalePeriod: Duration(days: 365)))` in `chat_state.dart` providers; `resolveAudioUrl` → `getSingleFile(url, key: mediaKey)` and play `DeviceFileSource`; same for video (`VideoPlayerController.file`); prefetch audio on arrival (small files). Point `CachedNetworkImage`/poster prewarmer at the same manager.

### M-3: Sign-out does not remove decrypted media files or the image cache (Spec 2.2)
- Severity: Medium (privacy residue on a shared/handed-over phone)
- Confidence: Confirmed
- Evidence: `auth_provider.dart:131-137` → `clearAll()`; `chat_cache_backend_io.dart:227-235` deletes rows only. Outbox rows reference plaintext files (`PendingSend.localMediaPath/localThumbnailPath`, voice recordings, compressed images/videos) and cached `Message.localMediaPath` (`message.dart:407`); none are deleted at sign-out, unlike the archive/account-change paths which do delete them (`chat_state.dart:2592-2605`, `2625-2650`). No `emptyCache()`/`removeFile(` call exists in `lib/` (grep), so flutter_cache_manager keeps every downloaded chat photo and poster after sign-out. Account deletion goes through the same `signOut()` (`delete_account_action.dart:54`).
- Failure scenario: User signs out (or deletes the account) and lends the phone; files under the app's support/temp directories still hold their sent photos/voice notes in plaintext and every received photo in the image cache.
- WhatsApp/iMessage expectation: logging out leaves no readable chat media behind.
- Fix: in `ChatCacheService.clearAll()` first `readOutbox(all users)` + read each `chat_messages` blob, collect `localMediaPath`/`localThumbnailPath`, delete the files, then clear rows (needs a `readAllOutbox()` backend method or a `listUsers()`); in `signOut()` also `await chatMediaCacheManager.emptyCache()` (or `DefaultCacheManager().emptyCache()` until M-2 introduces a dedicated one).

### M-4: A keystore read failure silently disables all persistence for the session, including the outbox, and never self-heals
- Severity: Medium (silent message loss on restart; retry button does nothing)
- Confidence: Likely
- Evidence: `chat_cache_service.dart:43-47` catches any `ChatCacheCipher.create()` error and sets `_cipher = null`; thereafter `putOutbox` returns without writing (`:147-150`), `readOutbox` yields `[]`. `retryMessage` (`chat_state.dart:1468-1485`) looks the item up in the outbox and `return`s when absent; `flushOutbox` has nothing to flush. The corrupt key is never deleted/regenerated (`chat_cache_cipher.dart:51-60` only handles "missing" and "wrong length"). flutter_secure_storage 9.x with `encryptedSharedPreferences: true` is known to throw (not return null) after an Android keystore reset/OS restore.
- Failure scenario: Phone restored or keystore reset → every launch: no history before network, drafts don't survive, a message sent with no signal shows "queued", app restart → bubble gone, never sent; tapping Retry on a failed message does nothing. No log, no banner.
- WhatsApp/iMessage expectation: local storage problems are self-repaired; a queued message is never dropped silently.
- Fix: in `ChatCacheCipher.create()` catch the read error → `storage.delete(key)` → generate a new key (the cache is rebuildable; the queue was unreadable anyway). In `ChatCacheService`, when `_cipher == null` keep an in-memory map for the outbox so retry/flush still work within the session, and emit one `ChatLog.diagnostic`.

### M-5: Restoring a saved draft fires the typing indicator to the partner
- Severity: Medium (visible to the partner, every open of a chat with a draft)
- Confidence: Confirmed
- Evidence: `chat_screen.dart:168-170` attaches `_onDraftChanged` then schedules `_restoreDraft`; the plain-draft branch (`:327-331`) sets `_controller.value` with the listener still attached (only the `initialDraft` branch removes it, `:318-323`) → `_onDraftChanged` (`:229-235`) → `typingController.onComposingChanged(true)` → `typing_controller.dart:43-49` `_sendTyping(true)` + throttle. It also re-encrypts and re-writes the identical draft.
- Failure scenario: You typed "hey, about tonight…" yesterday and left. Partner is in the chat; you merely open it → they see "typing…" for the throttle window although you haven't touched the keyboard.
- WhatsApp/iMessage expectation: typing shows only when typing.
- Fix: in `_restoreDraft` wrap both assignments in `removeListener/addListener` as the `given` branch already does.

### M-6: Offline attempts count toward the 5-attempt cap, so a queued message turns "failed" after ~1–2 minutes without signal
- Severity: Medium (cross-area with sending; included because the `failedPermanent` state is persisted to the outbox and survives restart)
- Confidence: Confirmed
- Evidence: `chat_state.dart:2203-2205` `permanent = error.isPermanent || attempts >= _maxAutomaticSendAttempts` (5); `ChatError.isPermanent` (`chat_error.dart:46-51`) correctly excludes `offline`, but the attempt cap does not; backoff windows 2^1..2^5 s (`:2229-2231`) → the fifth failure lands within roughly 60–120 s. `flushOutbox` skips `failedPermanent` (`:1818-1820`), so after a restart (`_restorePendingMessages` `:2586`) the bubble is a red "failed" needing a tap per message.
- Failure scenario: Type 5 messages on a flight → within two minutes all five are "failed"; on landing nothing sends until each is tapped.
- WhatsApp/iMessage expectation: a message typed offline waits with a clock indefinitely and sends itself.
- Fix: do not increment `attempts` (or do not count toward the cap) when `error.category == ChatErrorCategory.offline`; keep the capped backoff; let the reconnect flush (H-4 fix) pick them up.

### L-1: Outbox overflow silently discards the oldest queued sends
- Severity: Low (rare: >100 queued) / Confidence: Confirmed
- Evidence: `chat_cache_service.dart:12,158-168` evicts the oldest rows past 100 with no UI signal; the evicted message's bubble stays "queued" in memory (not in the outbox, so never flushed, not removable since it isn't `failed`), and vanishes on restart; its staged media file is orphaned.
- Fix: refuse the enqueue (surface "too many unsent messages") or raise the cap to e.g. 1000 and mark evicted items failed in state + delete their staged files.

### L-2: One unparsable message drops the whole conversation cache; `maxCachedMessages` config is dead
- Severity: Low / Confidence: Confirmed
- Evidence: `chat_cache_service.dart:65-74` wraps the entire `jsonDecode(...).map(Message.fromJson)` in one try → `[]`; `Message.fromJson` is strict (`MessageStatus.values.byName`, `DateTime.parse`), so an app downgrade or a new enum value nulls the cold-start paint for that chat. `chat_config.dart:7` `maxCachedMessages` is never read; the service hardcodes 200 (`:11`). No schema version/`user_version` is stored (`chat_cache_backend_io.dart:17`, `allTables = []`) — fine while the payload is JSON, but a future column change has no migration hook.
- Fix: parse per entry and skip bad ones; use `chatConfig.maxCachedMessages`; set `PRAGMA user_version = 1` now so a later migration has something to branch on.

### L-3: Draft persists text only — reply context, staged game and staged media are lost on restart
- Severity: Low / Confidence: Confirmed
- Evidence: `writeDraft` stores a string (`chat_cache_service.dart:189-202`); reply-to and the game/media composer state live only in providers.
- Fix: persist a small JSON draft `{text, replyToMessageId, quotedText}`; staged media can stay session-only.

## Done well

- Encryption design: AES-256-GCM, random nonce, versioned `acc1` envelope, key in Keychain (`first_unlock_this_device`) / Android Keystore, index columns content-free; Android Auto Backup and device-transfer exclude the DB and secure-storage prefs (`backup_rules.xml`, `data_extraction_rules.xml`). Tamper/garbage decrypts to a cache miss, never a crash (`chat_cache_cipher_test.dart`).
- Durable outbox is written before the network (`_attemptSend` `:1857-1863`), persists `uploadedMediaKey/uploadedThumbnailKey` and the `requiresPreparation` stage, so kill-mid-upload / kill-mid-compression resume without re-uploading or losing the bubble.
- Whole-blob `INSERT … ON CONFLICT DO UPDATE` writes are atomic; WAL mode; kill-mid-write cannot half-persist a message list.
- Cold start paints from cache for both the conversation list (`ConversationsNotifier.build`, with `hasValue` fallback in the screen so background refreshes never flash a spinner) and the chat (`_init` publishes cached + restored-pending rows before any network, then `loadMessages(silent: true)`).
- Merge is incoming-wins with `localMediaPath` carry-forward and view-once/streak paths never persisted (`message.dart:407-409`); `removeFailedMessage` rewrites the cache so dismissed failures don't resurrect.
- Signed URLs are not persisted (`Message.toJson` stores keys only) and `ResolvedMediaUrl` re-signs through the repository's memory cache — a restored row never shows an expired image.
- Per-user keying on every table; `clearAll()` on sign-out; `_handleAccountChange` and archive paths purge rows *and* staged files.
- Keyset pagination on `(sort_at DESC, id DESC)` matches `messages_relationship_sort_idx`; reversed `ListView.builder` keeps scroll position when prepending. 200-row cap bounds the blob size.
- Image/poster caching keyed by `mediaKey` (not the volatile signed URL), with a poster prewarm so video tiles don't pop.

## Not verified

- Live Supabase project settings (realtime publication filters, RLS on realtime) — only the scratch DB schema/`relreplident` was inspected; H-1's conclusion does not depend on it because the client merge never removes rows anyway.
- On-device timings for pointycastle AES + synchronous SQLite (M-1) — reasoned from the code path, not profiled.
- Exact flutter_secure_storage failure behaviour per OEM (M-4) — based on the known Android `EncryptedSharedPreferences` failure mode; not reproduced.
- iOS: `Application Support` is included in iCloud backup; the restored ciphertext is undecryptable on another device (key is `this_device`), so this is benign — not tested.
- No Flutter tests were run; existing cache tests (`chat_cache_cipher_test`, `send_persists_to_cache_test`, `chat_edge_cases_test` account switch) do not cover corruption, server-side deletion, or offline cold start.
