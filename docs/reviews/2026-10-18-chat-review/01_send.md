# 01 — SENDING (tap send → durable on server → correct on both sides)

## Summary
The happy path is solid and spec-faithful: a client-generated `client_message_id`, an outbox row persisted before the network call, optimistic bubble first, server-side idempotency via `messages_sender_client_id_unique` with 23505 reconciliation, and downstream outboxes written inside the insert trigger. Where it falls short of WhatsApp/iMessage is the *offline and flaky-network* story: the queue gives up after 5 attempts (~15–30 s), nothing flushes it on reconnect/resume, the single retry timer can strand a queued item indefinitely, and one exception path leaves a message stuck at "sending". Several edge cases (over-long paste, read-only transitions, cold-start status restore) silently lose or freeze a message. All findings below are code-traced; none require the live backend.

## Findings

### H-1: Offline sends flip to "Failed" after ~15–30 s and are never auto-sent on reconnect
- Severity: High
- Confidence: Confirmed
- Evidence:
  - `lib/features/chat/presentation/state/chat_state.dart:281` `_maxAutomaticSendAttempts = 5`; `:2203-2204` `permanent = error.isPermanent || attempts >= 5`; `:2234-2236` backoff window `1 << attempts` s with equal jitter → waits of ~1–2, 2–4, 4–8, 8–16 s, then `failedPermanent`.
  - `flushOutbox()` is only invoked from `_init` (`:403`), the retry timer (`:2257`) and the busy re-run (`:1842`). No call on connectivity change, app resume, or realtime resubscribe. `lib/features/chat/presentation/providers/chat_experience_providers.dart:8-12` (`connectivity_plus`) feeds only the banner (`chat_screen.dart:1316`). The per-chat channel does emit an event on every `subscribed` after a reconnect (`supabase_chat_repository.dart:637-640`), but the handler (`chat_state.dart:510-531`) refetches and never flushes.
  - The controller is `autoDispose` with a 5-minute keepAlive (`chat_state.dart:244-253`, `chat_config.dart:20`); `dispose()` cancels `_retryTimer` (`:2675`). There is no app-level flusher (`grep readOutbox|flushOutbox lib/` → only chat_state/cache).
  - UI copy contradicts the behaviour: `chat_screen.dart:1796` "N messages queued. They will send when you reconnect."; `chat_error.dart:180` "Your message will send when you reconnect."
- Failure scenario: Airplane mode → send "On my way" → bubble shows clock, banner says it will send when you reconnect → ~20 s later bubble turns red "Failed" → leave airplane mode: nothing happens; user must find and tap each failed bubble. Variant: send while offline, back out of the chat, reconnect 6 min later → the message sits in the outbox until the chat is reopened.
- WhatsApp/iMessage expectation: a queued message stays queued (clock) for as long as it takes and goes out by itself the moment connectivity returns, even with the chat closed.
- Fix: (1) In `_handleSendFailure`, do not count `offline`/`unavailable` attempts toward the permanent cap (keep the cap for `unknown`), and clamp the backoff at 64 s indefinitely. (2) In the realtime handler (`:512`) and on `chatConnectivityProvider` becoming online, call `unawaited(flushOutbox())`. (3) Add `WidgetsBindingObserver` resume → `flushOutbox()` in `ChatScreen.didChangeAppLifecycleState` (`chat_screen.dart:213`). (4) Longer term: a `Provider`-level outbox drainer that `readOutbox(userId)` for all relationships on app resume/connectivity so sends complete with the screen closed.

### H-2: Single retry timer strands an earlier queued message as "Queued" forever
- Severity: High
- Confidence: Likely (traced; not executed)
- Evidence: `_handleSendFailure` always `_retryTimer?.cancel()` and re-arms for the *latest* failure only (`chat_state.dart:2253-2259`). `flushOutbox` skips items whose `nextAttemptAt` is still in the future and schedules nothing for them (`:1826-1829`). Only a *failure* schedules a timer. A `queued` bubble has no retry/remove affordance (`message_bubble.dart:2089` and `chat_screen.dart:3537-3555` gate `onRetry/onRemove` on `isFailed`).
- Failure scenario: offline; message A fails 3× (next attempt in ~6 s). User sends B → fails (next in ~1.5 s) → A's timer is cancelled, B's armed. Network returns. Timer fires at 1.5 s: A skipped (4.5 s away), B sends OK → no failure → no timer re-armed. A stays "Queued" (clock) with no way to retry or delete until the user sends something that fails, or the controller is evicted and the chat reopened. Same stranding whenever `_attemptSend` throws out of the flush loop (see H-3).
- WhatsApp/iMessage expectation: every queued item eventually sends; the user never has to babysit the queue.
- Fix: in `flushOutbox`, after the loop compute `min(nextAttemptAt)` over remaining non-permanent items and arm `_retryTimer` for it; in `_handleSendFailure` arm the timer for `min(existing deadline, new deadline)` instead of cancelling. Also give `MessageStatus.queued` bubbles the same long-press "Retry now / Delete" actions as failed ones.

### H-3: An exception inside the 23505 reconcile path escapes `_attemptSend` and freezes the message at "sending"
- Severity: High (stuck core-flow state; message *is* on the server, partner sees it, sender does not get a tick)
- Confidence: Confirmed (Dart semantics: a throw inside a `catch` clause is not handled by sibling clauses)
- Evidence: `chat_state.dart:2009-2017` — inside `on PostgrestException catch`, `await findMessageByClientId(...)` performs a new network round-trip. If it throws (SocketException/ClientException — exactly the flaky network that produced the lost-response retry in the first place) the error propagates past `_handleSendFailure` (`:2073`), through `finally` (`:2076`), out of `sendMessage` → `_sendDraftText` (`chat_screen.dart:746`) → `unawaited(_send())` as an unhandled async error. Consequences: outbox row left at `PendingSendState.sending` (written at `:1859-1863`), optimistic bubble stays `MessageStatus.sending`, `isSending` stays true, no retry timer. When reached via `flushOutbox`, the loop aborts and later items are not attempted this round.
- Failure scenario: poor signal; insert commits but the response is lost → retry → 23505 → the follow-up SELECT also times out → bubble shows a clock indefinitely while the partner already has the message. Only recovers after the controller is evicted (5 min away) or an app restart.
- WhatsApp/iMessage expectation: the clock resolves to a tick as soon as the network allows.
- Fix: move the reconcile into a helper `_reconcileDuplicate(pending)` wrapped in its own `try/catch` that funnels any error to `_handleSendFailure(..., ChatError.from(e))`; and make the generic `catch (error)` the outer guard by nesting the Postgrest handling inside it.

### M-1: Pasting a message over 10,000 characters silently destroys the draft
- Severity: Medium (user text lost without feedback)
- Confidence: Confirmed
- Evidence: `chat_screen.dart:719-727` clears the controller (`_controller.clear()`, which also persists an empty draft via `_onDraftChanged` `:338`) *before* calling `sendMessage`; `chat_state.dart:687` returns silently when `!Message.isValidContent(content)` (`message.dart:585-588`, 10,000 runes). No `maxLength`/`LengthLimitingTextInputFormatter` anywhere in `chat_text_field.dart` or `chat_screen.dart` (grep).
- Failure scenario: paste a long article (12k chars) → tap send → composer empties, no bubble, no error, draft gone.
- WhatsApp/iMessage expectation: either the field refuses further input at the limit or send is blocked with a visible reason; text is never dropped.
- Fix: in `_sendDraftText`, check `Message.isValidContent(trimmed)` before clearing and surface a SnackBar/inline error; additionally add `LengthLimitingTextInputFormatter(Message.maxContentRunes)` (character-aware) to the composer.

### M-2: Cold-start restore trusts the cached optimistic row over the outbox, so a failed message can reappear as "sending" with no retry
- Severity: Medium
- Confidence: Likely
- Evidence: `_mergeInitialMessages` (`chat_state.dart:2529-2547`) iterates `[...cached, ...restoredPending]` and only lets a *canonical* incoming row replace an existing one — a restored `_local_` row never replaces the cached `_local_` row. `Message.toJson` persists `status` (`message.dart` ~`:440`, `'status': status.name`), and `loadMessages`/`_catchUpFromCursor` write the full `state.messages` (including `_local_` rows) to the cache (`:563-566`, `:607-611`). `_handleSendFailure` updates only the outbox, never the message cache (`:2244-2272`).
- Failure scenario: send A on a poor connection → a partner message arrives (realtime → `loadMessages` → cache written with A at `sending`) → A then exhausts retries → `failedPermanent` in the outbox, red in the UI. Kill and reopen the app: A is restored from the cache as `sending` (clock), `flushOutbox` skips it (failedPermanent), and the bubble offers neither retry nor delete.
- WhatsApp/iMessage expectation: state survives restart exactly (failed stays failed with retry).
- Fix: in `_mergeInitialMessages` let a `_local_` row from `restoredPending` win over a cached `_local_` row with the same `clientMessageId` (the outbox is authoritative for pending state); also drop cached `_local_` rows with no outbox entry.

### M-3: New sends bypass the FIFO queue, so a later message can overtake an earlier queued one and the two phones show different orders
- Severity: Medium
- Confidence: Likely
- Evidence: `sendMessage` (and every media send) calls `_attemptSend(pending)` directly (`chat_state.dart:727`) regardless of older `queued` items; `flushOutbox` is the only FIFO path (`:1816-1838`, SQLite `ORDER BY created_at ASC`, `chat_cache_backend_io.dart:134-135`). Server order is `sort_at = created_at = now()` at insert (`messages_default_sort_at`). The sender keeps the optimistic slot (`_replaceOptimistic` `:2503-2520`, `presentationSortAt` preserved in `_mergeMessages` `:2413-2418`, comparator `:2356-2360`), the partner sorts by server `sort_at`.
- Failure scenario: brief outage → A fails and is queued with a 2–4 s backoff → connectivity returns → user types B → B inserts immediately → A inserts 3 s later. Sender sees A above B; partner sees B above A. After the sender restarts the app (`presentationSortAt` is not persisted — `toJson` only has `sortAt`) their own list also flips to B-then-A.
- WhatsApp/iMessage expectation: messages from one device leave in the order they were composed.
- Fix: in `sendMessage`/media sends, if the outbox for this relationship has any non-permanent item older than this one (or `_isFlushing`), `putOutbox` the new item and call `flushOutbox()` instead of `_attemptSend` directly, so the flush delivers in enqueue order (Spec 4.2 "one logical message at a time per relationship in enqueue order").

### M-4: Queued messages freeze permanently when the relationship becomes read-only (ended/paused)
- Severity: Medium
- Confidence: Confirmed
- Evidence: `flushOutbox` returns at `!state.conversation.canSend` (`chat_state.dart:1800`); `_restorePendingMessages` restores them as `queued`/`sending` (`:2550-2590`); `canSend` is `status == 'active'` (`supabase_chat_repository.dart:94-98`, `conversation.dart:114`); retry/remove exist only for `isFailed` (`chat_screen.dart:3537-3555`). Server insert policy `messages_insert_sender_active` requires `status='active'`, so the rows can never send.
- Failure scenario: two texts queued offline → partner ends (or pauses) the relationship → chat opens read-only with two clock bubbles that never change and cannot be removed; they come back on every restart. Spec 16 says "Queue stops; message remains unsent" and 4.3 says "explain that the message was not sent" — nothing explains it.
- WhatsApp/iMessage expectation: a clear "not sent" state the user can dismiss.
- Fix: when `_refreshConversation` (or `_init`) finds `!canSend` and the outbox is non-empty, mark those items `failedPermanent` with `lastErrorCategory = relationshipInactive`, flip the bubbles to `failed`, and show the read-only banner reason; allow remove on them.

### M-5: If the realtime echo beats the insert response, an outgoing image/video bubble loses its local file and flashes to a network load
- Severity: Medium (visual jank on the sender's own media send)
- Confidence: Possible (needs the insert response to lag the realtime event by > 250 ms debounce + one catch-up RTT)
- Evidence: `_mergeMessages` carries `localMediaPath` forward only from `existing` (keyed by server id) — `chat_state.dart:2447-2450` — not from `existingByClient`; the de-dup pass then drops the `_local_` row (`:2460-2475`). When `_attemptSend` later returns, `_replaceOptimistic` finds no `_local_` row and returns the list unchanged (`:2514-2517`), discarding `_canonicalWithLocalHandoff`'s local paths. Only `_settleAcknowledgedMedia` (`:2144-2160`) restores a local path after `cacheLocalFile` completes.
- Failure scenario: send a photo on a slow uplink; realtime INSERT arrives first → bubble swaps from the local image to a shimmer/network fetch of the signed URL → later snaps back to the cached local copy.
- WhatsApp/iMessage expectation: the sent photo never visibly reloads.
- Fix: in `_mergeMessages` use `presentationSource` (not just `existing`) as the `localMediaPath`/`localThumbnailPath` carry-forward source; and in `_replaceOptimistic`, when the canonical id already exists, overlay `localMediaPath/localThumbnailPath` from `resolved` onto it.

### L-1: Racing a send against a pause/end shows the wrong copy and a dead Retry
- Severity: Low
- Confidence: Confirmed
- Evidence: RLS insert violation returns `42501` → `ChatErrorCategory.unauthenticated` (`chat_error.dart:139`) → banner "You no longer have access to this conversation." (`:181`) even for a pause; the failed bubble keeps `onRetry`, and `retryMessage` does not check `canSend` (`chat_state.dart:1470-1511`), so retry just fails again.
- Fix: in `_categorizePostgrest`, for `42501` with message containing `row-level security` on an insert, map to `relationshipInactive` when the refreshed conversation is read-only; hide retry when `!canSend`.

### L-2: `is_system_notice` is client-insertable
- Severity: Low (security hygiene; flag to the security/RLS reviewer)
- Confidence: Confirmed
- Evidence: `information_schema.column_privileges` on `attune_spec3a` lists `is_system_notice` in the `authenticated` INSERT grant; no BEFORE INSERT trigger guards it (unlike `pause`/`appreciation` guards); no client path sets `isSystemNotice: true` (grep). A modified client could post italic "system" lines (`message_bubble.dart:1421-1429`).
- Fix: revoke `is_system_notice` from the client INSERT grant, or add a guard trigger like `messages_pause_guard`.

### L-3: Clock skew moves the sender's own bubble on the next merge
- Severity: Low
- Confidence: Possible
- Evidence: optimistic `sortAt/presentationSortAt = DateTime.now()` (`message.dart:284`, `chat_state.dart:694`); `_mergeMessages` re-sorts by `presentationSortAt` (`:2453`, `:2356-2360`). A device clock behind the server drops the just-sent message below newer partner messages on the next realtime merge; on restart it snaps to server order.
- Fix: on `_replaceOptimistic`, set `presentationSortAt` to `max(optimistic, canonical.sortAt)` if the canonical is newer than the newest visible row, or simply pin new optimistic rows at the top until acknowledged.

## Done well
- Idempotency is real: `messages_sender_client_id_unique (sender_id, client_message_id)`, 23505 → `findMessageByClientId` reconcile, covered by `chat_controller_test` ("23505 duplicate reconciles") and `chat_edge_cases_test` ("Double tap / request replay", "Commit succeeds, response lost").
- Outbox is persisted before the network call and before every upload step; uploaded storage keys are persisted so a retry never re-uploads (`_attemptSend` `:1859-1892`). Restart restores `sending` rows and re-attempts them.
- Optimistic bubble is published before any disk I/O (`sendMessage` `:716-727`); canonical row is written to the cache on success and on 23505 reconcile, and `removeFailedMessage` rewrites the cache.
- Double-tap is safe: `_handleSend` reads `_hasText` from the controller and `_sendDraftText` clears synchronously before the first await; keyboard `onSubmitted` uses the same path.
- Whitespace-only is rejected client (`isValidContent` trim) and server (`messages_payload_present` btrim); length limit is consistent (10,000 runes vs `char_length` ≤ 10,000).
- Replies: `validate_message_reply_before_insert` (SECURITY DEFINER) enforces same-relationship; quoted text is truncated to 60 chars (limit 200); replying to a `_local_` row is blocked; `reply_to_message_id`/`quoted_text` survive in `PendingSend` and restart.
- Composer insertions (repair tray, apology, support chips, start-conversation, Together `initialDraft`) only append to the composer and never auto-send; `initialDraft` is applied once in `_restoreDraft` without triggering the draft listener.
- Downstream work (safety outbox, notification outbox, message_count) is written inside the AFTER INSERT trigger with `ON CONFLICT DO NOTHING`; grants are column-scoped and client cannot write timestamps/receipts.
- Flush is serialised (`_isFlushing`, `_inFlightClientIds`) so overlapping triggers cannot double-send.

## Not verified
- Real-device behaviour under iOS background suspension / Android Doze (timers paused, websocket dropped) — only inferable from code; it strengthens H-1.
- `ChatCacheService._encrypt` returns null when `_cipher` is null, in which case `putOutbox` silently does nothing (outbox not durable). I did not determine on which platforms/boot states the cipher can be null.
- Two devices for the same user: by design each device has its own outbox and v4 ids; no conflict path found, but not exercised.
- Emoji-only / RTL rendering and the Together "How did it go?" entry point beyond `initialDraft` handling (belongs to display/Together areas).
- Server-side rate limiting: none exists for `messages` inserts (no trigger; `ChatError` maps 429 but nothing emits it). The spec does not require one, so not filed as a finding.
- Staged-game sends (`_sendStagedGame`) were out of scope per the brief.
