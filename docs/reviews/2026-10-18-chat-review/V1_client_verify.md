# V1 — Adversarial verification of client-side findings (01, 02, 03, 05)

Method: every finding below was re-traced in the working tree (read-only). Where a claim rests on framework semantics (Dart try/catch, Flutter `deactivate`, Riverpod 2 `onDispose`, Supabase/walrus DELETE filtering) the semantics were checked against what the code actually relies on. Scratch DB `attune_spec3a` was queried read-only for `relreplident`, publication membership and RPC bodies. No existing test in `test/features/chat/` covers any of the confirmed items (grep for flushOutbox-after-realtime, offline attempt cap, reconcile throw, deactivate-on-push, draft-restore typing, starred invalidation, jump-to-unbuilt-row: none).

Line numbers refer to `lib/features/chat/presentation/state/chat_state.dart` (CS), `lib/features/chat/presentation/screens/chat_screen.dart` (SCR), `lib/features/chat/data/repositories/supabase_chat_repository.dart` (REPO) unless stated.

## Root causes (merged)

### RC-1 — The outbox has exactly one flush trigger (`_init`) plus a per-failure timer; nothing flushes on reconnect, connectivity return, resume, or when `_init` dies offline
- Covers: 01 H-1 (the "never auto-sent on reconnect" half), 02 H-3, 03 H-4, 02 M-4 (same cause, not in my list).
- Verdict: CONFIRMED.
- Corrected severity: **Critical by user effect for the two-phone test** (a message typed in airplane mode is never sent without a manual tap; with RC-2 it also turns red). Keep as High if "data not lost, only stuck" is the bar.
- Evidence:
  - CS:371-378 `final conversationRefresh = _refreshConversation(); await loadMessages(...); await conversationRefresh;` — `_refreshConversation` (CS:478-500) has no try/catch; it calls `getConversation` → `getConversations` (REPO:155-163, REPO:54-138), a plain PostgREST select that throws offline. The rethrow at CS:378 skips CS:383-403, including `unawaited(flushOutbox())` at CS:403. `_init()` is fire-and-forget from the constructor (CS:302), so the error is an unhandled async error, not a crash.
  - Realtime handler CS:512-530: `_refreshConversation`, `_catchUpFromCursor`, `loadMessages`, `_markPartnerMessagesDelivered`, `_refreshPinnedMessages`, `markAsReadDebounced`, bump — **no `flushOutbox()`**, even though REPO:637-640 emits an event on every `subscribed` (i.e. on every resubscribe after reconnect) — the perfect "network is back" signal is already wired and unused for sends.
  - `grep -rn flushOutbox lib` → only CS (403, 1797, 1842, 2257). `chatConnectivityProvider` (`lib/features/chat/presentation/providers/chat_experience_providers.dart:7-15`) is consumed only at SCR:1316 for the "Offline" label. No `WidgetsBindingObserver` resume path calls the notifier (SCR:213-216 only syncs view-active). No `RouteObserver`/`observers:` anywhere in `lib/app`, `lib/core`.
  - Retry timer exists only after a failure in this session (CS:2253-2259); restored `queued` rows from a previous session (CS:2550-2590) get no timer. `dispose()` cancels it (CS:2675); controller is evicted 5 min after leaving (CS:246-253, `chat_config.dart:20`).
  - UI promises the opposite: SCR:1796 "They will send when you reconnect."; `chat_error.dart:166-167`.
- Refutation attempts: looked for any other caller of `readOutbox`/`retryMessage` (only SCR:3543 manual tap), any app-level drainer (`story_outbox_controller.dart` has its own, chat has none), `supabase_flutter` resume → `forceRejoin` → `subscribed` → handler — real, but the handler does not flush. Nothing compensates.
- Minimal fix:
  1. CS `_init`: `try { await conversationRefresh; } catch (e) { ChatLog.e(...); }` so CS:383-403 always run (header metadata is best-effort; `loadMessages` already self-guards).
  2. CS realtime handler: append `unawaited(flushOutbox());` after `_refreshPinnedMessages()`; `_isFlushing` already serialises it. This alone makes every reconnect a flush.
  3. CS constructor: `ref.listen<AsyncValue<bool>>(chatConnectivityProvider, (p, n) { if (p?.valueOrNull == false && n.valueOrNull == true) { unawaited(_catchUpFromCursor()); unawaited(loadMessages(silent: true)); unawaited(flushOutbox()); } });` (covers the no-lifecycle-change case where the socket takes 25-45 s to notice).
  4. Optional (closed-chat sends): a small `Provider` that on `AppLifecycleState.resumed`/connectivity-true reads `readOutbox(userId)` and instantiates `chatControllerProvider` for each relationship with queued rows.
- Test that proves it (`chat_controller_test.dart`, harness `ChatTestHarness`): seed `cache.putOutbox(user, PendingSend(queued, text:'x'))`; make `repo.getConversations` throw `SocketException` once; build controller; `await pump`; expect `b.state.messages.single.status == queued` and `repo.sendCallCount == 0`. Then let `getConversations` succeed and call `repo.emitRealtime()`; pump 300 ms; expect `repo.sendCallCount == 1` and status `sent`. A second test: controller built online, `sendTextMessage` throws `SocketException` → `emitRealtime()` → expect a new send attempt (proves the handler flush).

### RC-2 — Offline failures count toward the 5-attempt permanent cap, so a queued message turns red after ~15-30 s without signal
- Covers: 01 H-1 (the "flip to Failed" half), 03 M-6.
- Verdict: CONFIRMED (03's "60-120 s" figure is wrong; 01's 15-30 s is right).
- Corrected severity: High (with RC-1 unfixed it is the visible symptom of Critical).
- Evidence: CS:2203-2204 `permanent = error.isPermanent || attempts >= _maxAutomaticSendAttempts` (5, CS:281). `ChatError.isPermanent` (`lib/features/chat/utils/chat_error.dart:46-51`) correctly excludes `offline`, but the cap does not discriminate. Windows CS:2229-2231: `1 << attempts.clamp(1,6)` → waits 1-2, 2-4, 4-8, 8-16 s; the 5th failure → `failedPermanent`, `nextAttemptAt = null` (CS:2238-2245), `flushOutbox` skips it forever (CS:1818-1820). `SocketException`/`TimeoutException` → `offline` (chat_error.dart:61-63) and http `ClientException: Failed host lookup`/`Connection failed` → `offline` via the text match (chat_error.dart:101-110), so the fix below catches the real cases.
- Minimal fix (CS `_handleSendFailure`): keep incrementing `attempts` for backoff, but `final permanent = error.isPermanent || (error.category == ChatErrorCategory.unknown && attempts >= _maxAutomaticSendAttempts);` (offline/unavailable/rateLimited never become permanent automatically; backoff already caps at 64 s). Optionally reset `attempts` to 0 on the first successful network call so a long outage does not leave a 64 s delay afterward.
- Test: `sendTextMessage` throws `SocketException` for 7 consecutive calls; call `retryMessage`/flush after each; assert status is always `queued`, never `failed`, and outbox `state != failedPermanent`; then succeed → `sent`.

### RC-3 — One `_retryTimer`, armed only on failure for the latest item; `flushOutbox` skips not-yet-due items without rescheduling
- Covers: 01 H-2.
- Verdict: CONFIRMED.
- Corrected severity: High standalone (a clock bubble with no Retry/Remove — SCR:3537-3555 and `message_bubble.dart:388-391, 1996-1999` gate both on `isFailed`); drops to Medium once RC-1 lands (any reconnect/event flushes it).
- Evidence: CS:2253-2259 `_retryTimer?.cancel()` then re-arm for the current item only; CS:1826-1829 `continue` on future `nextAttemptAt`, nothing arms a timer; after the loop (CS:1836-1845) only `_flushRequestedWhileBusy` re-runs. Scenario: A due at +6 s, B due at +1.5 s; timer fires at 1.5 s, B sends, A skipped, no failure → no timer → A stranded until next failure/eviction.
- Minimal fix: in `flushOutbox` after the loop compute `earliest = min(nextAttemptAt)` over items that are not permanent/in-flight and still in the future; `_armRetryTimer(earliest)`; in `_handleSendFailure` call `_armRetryTimer(min(existingDeadline, newDeadline))` instead of cancel-and-replace (track `_retryDeadline`). UI: allow Retry/Remove on `isQueued` rows too.
- Test (`fakeAsync`): outbox with A(nextAttemptAt +6 s) and B(+1 s), repo healthy; `flushOutbox()` at t=1 s → `sendCallCount == 1` (B); `elapse(5 s)` → `sendCallCount == 2` (A) with no further `_handleSendFailure`.

### RC-4 — A throw inside the `on PostgrestException` 23505 branch escapes `_attemptSend`
- Covers: 01 H-3.
- Verdict: CONFIRMED.
- Corrected severity: High (bubble stuck at clock while partner already has the message; `isSending` stays true; unhandled async error; when reached via `flushOutbox` the loop aborts for the rest of the queue). Partially self-heals after RC-1 (the outbox row is at `sending`, which `flushOutbox` does not skip, so any later flush retries → 23505 → reconcile).
- Evidence: CS:2009-2017 `await findMessageByClientId(...)` inside the catch clause; REPO:327-341 is a plain select with no try/catch; Dart does not route an exception thrown in a `catch` clause to a sibling `catch` of the same `try`. `finally` (CS:2076) only clears `_inFlightClientIds`; outbox row stays `PendingSendState.sending` (written CS:1859-1863); no `_handleSendFailure`, no timer, state unchanged.
- Minimal fix: extract `_reconcileDuplicate(user, pending, durablePending)`; call it inside `try { ... } catch (e) { await _handleSendFailure(user.id, durablePending, ChatError.from(e)); }`. Equivalent: wrap the whole body in an outer `try/catch` that funnels to `_handleSendFailure` and keep the `on PostgrestException` nested inside.
- Test: harness `sendTextMessage` throws `PostgrestException(code:'23505')`, `findMessageByClientId` throws `SocketException` → `await sendMessage('x')` completes without error; status `queued`; `isSending == false`; outbox row `queued` with `nextAttemptAt != null`.

### RC-5 — The realtime handler is a serial, unguarded, metadata-first refetch chain that also self-amplifies through `conversationsRefreshProvider`
- Covers: 02 H-1, 02 H-2.
- Verdict: CONFIRMED (request counts are derived from code, not measured; the shape and the amplification are certain).
- Corrected severity: High. The latency half (H-2) is the one the owner will feel immediately: a bubble is gated behind `getConversations()` = relationships + users + last-message + `count_unread_messages` RPC + avatar signed URL (REPO:56, 80, 89, 90, 111) before `_catchUpFromCursor` runs, and if any of those throws the whole Timer callback dies (CS:513 has no try/catch) and the new message is not shown until the next event.
- Evidence for amplification: CS:529 bumps `conversationsRefreshProvider`; the same controller listens to it (CS:298-300) → second `_refreshConversation()`; `ConversationsNotifier.build()` watches it (CS:144) → `getConversations()` (CS:165); the `ref.onDispose` registered inside `_subscribeToInbox` (CS:208-212) runs on recompute in Riverpod 2.6 (onDispose fires on rebuild, and the notifier instance persists so `_servedCache` stays true) → `_subscribedIds = null` → resubscribe → `removeChannel`/new `inbox:` channel (REPO:716-719, 710-715) → `subscribed` → `_refreshInBackground` (CS:224) → `getConversations()` again. The inbox stream itself is undebounced (CS:204-206). Server side (scratch DB): `enqueue_message_downstream_work` does `UPDATE public.relationships SET message_count = ...+1` per insert → a `relationships` UPDATE event on both channels per message; `delete_message` is an UPDATE (so edits/deletes do arrive — good), safety/analysis workers UPDATE `messages` too.
- Minimal fix (ordered by payoff):
  1. Handler: `try { await _catchUpFromCursor(); await loadMessages(silent: true); } finally { ... }` first, then `_refreshConversation()`, `_markPartnerMessagesDelivered()`, `_refreshPinnedMessages()` each in its own try/catch; drop the bump at CS:529 (the inbox stream already refreshes the list); keep bumps only for identity edits.
  2. `ConversationsNotifier`: register one `ref.onDispose` in `build()` (not inside `_subscribeToInbox`), guard with `_subscribedIds`; debounce `_refreshInBackground` 300 ms trailing.
  3. REPO: a real `getConversation(id)` (one relationship select + partner row; skip last-message/unread when called from the chat).
  4. Later: use `PostgresChangePayload.newRecord` to merge the INSERT directly; move `message_count` off `relationships`.
- Test: harness `getConversationsCalls` counter — one `repo.emitRealtime()` with the chat open must produce ≤ 1 `getConversations` and exactly 1 `getMessages`; with `getConversations` throwing, a message added to the fake repo before `emitRealtime()` must still appear in `state.messages`.

### RC-6 — `_isViewActive` is never cleared when another route is pushed over the chat (the `deactivate()` comment is wrong)
- Covers: 02 H-4.
- Verdict: CONFIRMED.
- Corrected severity: High. Compounding effect found: the server's push worker, seeing presence "active in chat", **suppresses the push and stamps `delivered_at`** (`supabase/functions/process-chat-notification-outbox/index.ts:221-233`), and the client's stale `_isViewActive` then runs `markAsReadDebounced()` on every event (CS:528, 2300-2345) → partner sees Read, recipient got no push, while playing a game.
- Evidence: SCR:177-193 relies on `State.deactivate` firing on push; Flutter only calls `deactivate` when the element is removed from the tree, and a route under an opaque `MaterialPage` with `maintainState: true` stays mounted (offstage in the Overlay). `_syncViewActive()` (SCR:221-227, uses `ModalRoute.isCurrent` correctly) is only called from first frame (SCR:174), lifecycle (SCR:215) and the two hand-wrapped pushes `_openPulse`/`_openInsights` (SCR:1241-1257). Every other push is bare: SCR:870, 918, 958, 3462, 3490, 4273-4371 (all games). Presence heartbeat keeps running while `_isViewActive` (CS:465-471).
- Minimal fix: add a `RouteObserver<ModalRoute<void>>` to the GoRouter (`observers:` — none exist today) and make `_ChatScreenState` `RouteAware`: `didPushNext → notifier.setViewActive(false)`, `didPopNext → _syncViewActive()`. Fallback with zero routing changes: a `Future<T?> _pushFromChat<T>(Future<T?> Function() push)` helper used by every `context.pushNamed` in SCR, doing what `_openPulse` does. Keep `deactivate()` as backstop.
- Test (widget): pump `ChatScreen` with harness, `setViewActive` becomes true after first frame; `Navigator.push` a dummy route; `repo.emitRealtime()`; pump 1 s; expect `repo.markConversationReadCalls` unchanged and presence set to null.

### RC-7 — Filtered DELETE events are dropped under `REPLICA IDENTITY DEFAULT`
- Covers: 02 M-1; the realtime leg of 03 H-1.
- Verdict: CONFIRMED (schema + subscription + Supabase/walrus semantics; not reproduced against live Realtime).
- Corrected severity: Medium (stale until the next event; adds are live).
- Evidence: scratch DB `relreplident = 'd'` for `messages`, `message_pins`, `message_reactions`, `relationships`; all three subscriptions filter `relationship_id=eq.<id>` (REPO:563-606, inbox REPO:672-702). Unpin is a DELETE (REPO:1139-1144); `remove_reaction` is `DELETE FROM public.message_reactions`. Under DEFAULT identity a DELETE's old record carries only the PK, walrus's `is_visible_through_filters` inner-joins filter columns to the record's columns → no row → `bool_and` = NULL → not visible → dropped. Compensation that does exist: every other event re-runs `_refreshPinnedMessages()` and re-hydrates reactions for the newest 50 (REPO:918-975 reactions query), so it is "stale until anything else happens", not "never". User message deletion is soft (`delete_message` → `UPDATE ... deleted_at = now()`), so ordinary deletes propagate fine; only hard deletes (`delete_chat_import`, cascades, ops wipes) are invisible — handled by RC-8.
- Minimal fix: migration `ALTER TABLE public.message_pins REPLICA IDENTITY FULL; ALTER TABLE public.message_reactions REPLICA IDENTITY FULL;` (tiny tables, negligible WAL). Leave `messages` DEFAULT and let RC-8 reconcile. SQL contract test: `SELECT relreplident FROM pg_class WHERE relname IN ('message_pins','message_reactions')` → `'f'`.

### RC-8 — The in-memory/cached list is only ever merged into, never reconciled against the server, and UPDATE pickup is limited to the newest 50 rows
- Covers: 03 H-1 (ghosts), 03 H-2, 02 M-3.
- Verdict: CONFIRMED.
- Corrected severity: High for the manual test (the owner's "wipe messages before testing" leaves permanent ghosts on both phones until sign-out; new messages render under them). Stale receipts/reactions/edits beyond row 50: Medium-High (every active couple exceeds 50 messages/day).
- Evidence: `_mergeMessages` CS:2395-2475 seeds `byId` from `state.messages` and only overlays; `loadMessages` CS:541-566 writes the merged list back to the cache, so stale rows are re-persisted on every sync; `_catchUpFromCursor` CS:588-625 + `getMessagesAfter` REPO:213-260 are strictly forward on `(sort_at, id)` (an edit/reaction/receipt does not move `sort_at`); `_appendOlderMessages` CS:2477-2485 keeps the existing (stale) row for known ids; cache cap 200 (`chat_cache_service.dart:11`). Purge only on relationship gone/archived (CS:482-499) or sign-out. Realtime cannot rescue hard deletes (RC-7).
- Minimal fix:
  1. `_reconcileWindow(List<Message> fresh, {ChatMessageCursor? before})`: drop every canonical (non-`_local_`) row whose `sortAt` lies inside the window the fetch covered (`>= fresh.last.sortAt` for the first page; between `before` and `older.last.sortAt` for a page; the whole canonical set when `fresh.isEmpty` on the first page) and whose id is not in `fresh`; use it in `loadMessages` and `loadMoreMessages`, then `writeMessages`. Keep `_local_` rows.
  2. Change the channel callbacks from `(_) => events.add(null)` to carry `payload.newRecord['id']`/`old_record` PK for `messages`/`message_reactions`; in the handler collect ids within the 250 ms debounce and call a new `repository.getMessagesByIds(ids)` (one `in` select + `_hydrateMessages`) → `_mergeMessages`. This fixes 02 M-3 and 03 H-2 regardless of row position.
- Tests: (1) seed cache with ids {1,2,3}; harness `getMessages` returns {1,2}; after `loadMessages()` → `state.messages.ids == {1,2}` and `cache.readMessages` == {1,2}. (2) 60 canonical rows loaded; mutate row 55 in the fake repo (reaction added); emit an UPDATE event carrying id 55; expect `state.messages` row 55 to carry the reaction.

### RC-9 — Cache initialisation is unguarded in `main()`
- Covers: 03 H-3.
- Verdict: CONFIRMED as a gap; likelihood unknown (no corruption path observed).
- Corrected severity: High by effect (app never starts), Low probability → treat as High because the fix is 15 lines.
- Evidence: `lib/main.dart:45-46` `await chatCache.init()` before `runApp`; `chat_cache_service.dart:39-47` guards only the cipher; `chat_cache_backend_io.dart:29-70` opens the file, `PRAGMA journal_mode = WAL`, 4 `CREATE TABLE`s with no try/catch; `ChatCacheCipher.create()` (`chat_cache_cipher.dart:43-61`) awaits `storage.read` with no timeout, although `main.dart:86-93` already applies a 3 s keystore timeout for the safety lock. Runtime variant: `_init` CS:349-356 awaits `readMessages`/`readOutbox` unguarded; a throw there leaves `isLoading: true` for the controller lifetime.
- Minimal fix: `ChatCacheService.init()`: `try { await _backend.init(); } on Object { delete sqlite{,-wal,-shm}; retry once; on second failure swap `_backend` for the stub backend }`; `ChatCacheCipher.create().timeout(3 s)`; in `_init` wrap the two cache reads → `[]`.
- Test: `ChatCacheService.forTesting(backend: ThrowingBackend())` → `init()` completes; `readMessages` returns `[]`; `putOutbox` does not throw.

### RC-10 — Restoring a saved draft fires the typing broadcast
- Covers: 03 M-5.
- Verdict: CONFIRMED.
- Corrected severity: Medium (partner sees "typing…" on every open of a chat with a draft; also re-encrypts/re-writes the draft).
- Evidence: SCR:168 `addListener(_onDraftChanged)` → SCR:170 `_restoreDraft`; plain-draft branch SCR:327-331 assigns `_controller.value` with the listener attached (only the `initialDraft` branch removes it, SCR:318-323) → `_onDraftChanged` SCR:229-235 → `onComposingChanged(true)` → `typing_controller.dart:43-49` sends immediately (`_sendTyping(true)`, no debounce on the first call).
- Minimal fix: in `_restoreDraft` wrap the plain assignment in `removeListener/addListener` exactly like the `given` branch.
- Test: seed `cache.writeDraft('u','rel','hey')`, pump `ChatScreen`, settle → expect harness `sendTyping` not called (add a `typingCalls` list next to `markDeliveredCalls` at `chat_test_harness.dart:111`).

### RC-11 — Jump-to-message uses a non-convergent extent guess and does not page back for quotes/pins
- Covers: 05 H-1.
- Verdict: CONFIRMED.
- Corrected severity: High (reply quotes, pinned banner, Starred/Search/Media "go to" all route through it).
- Evidence: SCR:605-660. `averageExtent = viewportDimension / _messageKeys.length` (SCR:638-640) — `_messageKeys` holds a key for every row *ever built* that is still in `state.messages` (pruned only by membership, SCR:3258-3262), so the denominator grows with scrolling while the numerator is one viewport; one `animateTo`, one 50 ms wait, one retry, then silent return. `index == -1` returns silently (SCR:634) — quote taps (SCR:1417 `onJumpToParent: _jumpToMessage`), pinned banner (SCR:1392-1394) and the Info/Media sub-screen returns (SCR:3462-3500 → `onJumpToParent`) never page back; only `initialJumpToMessageId` uses `_jumpToMessageAcrossPages` (SCR:664-688), and even that hands off to the same estimate. Existing `chat_screen_initial_jump_test.dart` only covers targets within ~a page.
- Minimal fix: (a) make `_jumpToMessage` delegate to `_jumpToMessageAcrossPages` when `index == -1 && state.hasMore`; (b) replace the estimate with an anchored iteration: find the built row with the index nearest the target (`_rowKeys` → `RenderBox.localToGlobal`), compute `delta = (targetIndex - anchorIndex) * meanExtentOfBuiltRows`, `jumpTo(clamp(anchorOffset + delta))`, pump a frame, repeat ≤ 12 times until `_messageKeys[target].currentContext != null`, then `ensureVisible` + flash; (c) a brief "Loading older messages…" overlay while paging.
- Test (widget): 300 rows alternating 1-line and 8-line texts; fling to the top; tap a quote whose parent is row 250 → expect `find.text('message 250')` hit-testable and highlighted within 2 s of pumps.

### RC-12 — `starredMessagesProvider` is a plain `FutureProvider` and is never invalidated
- Covers: 05 H-3.
- Verdict: CONFIRMED.
- Corrected severity: Medium (stuck for the session, but a secondary screen; not a core-flow stuck state).
- Evidence: `starred_messages_screen.dart:8-11` `FutureProvider` (not autoDispose); `grep -rn starredMessagesProvider lib` → only the screen's `ref.watch`; `starMessage`/`unstarMessage` CS:1606-1620 touch `state.starredMessageIds` only; no pull-to-refresh.
- Minimal fix: `FutureProvider.autoDispose`, plus `ref.invalidate(starredMessagesProvider)` at the end of `starMessage`/`unstarMessage`.
- Test: `ProviderContainer` with harness; read provider once; `controller.starMessage('m2')`; read again → `getStarredMessages` called twice and result contains `m2`.

### RC-13 — No "new messages"/scroll-to-bottom affordance; arrivals while scrolled up
- Covers: 02 M-5, 05 M-1.
- Verdict: PARTLY. Missing pill/divider/auto-scroll: CONFIRMED (SCR:1230-1239 `_scrollToLatest` only after own sends at SCR:733, 893, 949, 959, 1011, 1129, 1161; no pill widget anywhere; `ListView.builder(reverse: true)` SCR:3298-3312 with no `findChildIndexCallback`/`center`). The content *jump* on arrival is NOT verified (needs a widget/device test; plausible for a reverse `SliverList` when `pixels > 0`).
- Corrected severity: Medium.
- Minimal fix: track `_isAwayFromBottom = pixels > 1.5 * viewport` in the existing `NotificationListener` (SCR:3275); count partner arrivals since leaving the bottom (reuse `MessageArrivalTracker`); floating pill → `_scrollToLatest()`; if the jump is confirmed, add `findChildIndexCallback` keyed on `clientMessageId` or move to `CustomScrollView(center:)`.
- Test (widget): 200 rows; scroll to `pixels = 2000`; add a partner row at index 0 via harness + `emitRealtime()`; expect pill visible with "1"; and (jump check) expect the previously top-visible row's `localToGlobal` unchanged within 1 px.

### RC-14 — "Delivered" is only stamped by a foregrounded client (or server-side when the push is suppressed)
- Covers: 02 M-2.
- Verdict: CONFIRMED, with one correction: the server **does** stamp `delivered_at` in the suppressed-because-actively-viewing branch (`process-chat-notification-outbox/index.ts:221-233`); the normal push path deliberately does not (index.ts:255-264). Client stamps only from the open chat (CS:2282-2298) and from the conversations list fetch (`markRelationshipDelivered`, CS:129-140, 168, 227). OneSignal wiring has only click/foreground listeners (`onesignal_service.dart:41, 73`), neither calls an RPC.
- Corrected severity: Medium.
- Minimal fix: in `addForegroundWillDisplayListener` and `addClickListener` call `mark_relivery…` → `mark_relationship_delivered(relationship_id)` from `additionalData`; iOS background delivery needs an NSE (out of app code).
- Test: unit-test the OneSignal handler with a fake payload → `markRelationshipDelivered('rel')` called once.

### RC-15 — New sends bypass the FIFO outbox order
- Covers: 01 M-3.
- Verdict: CONFIRMED.
- Corrected severity: Medium (sender and partner see different orders; sender's own order flips on restart because `presentationSortAt` is not in `Message.toJson` — `message.dart` has it only as a field/ctor/copyWith, never serialised).
- Evidence: `sendMessage` CS:727 → `_attemptSend(pending)` directly; `_inFlightClientIds` prevents double-send but not reordering; `flushOutbox` is the only FIFO path (CS:1816-1838, backend `ORDER BY created_at ASC`).
- Minimal fix: in `sendMessage`/media sends, `if (_isFlushing || await _hasOlderQueued(relationshipId)) { await putOutbox(pending.queued); unawaited(flushOutbox()); return; }` else attempt directly.
- Test: A fails with `SocketException` (queued); repo healthy; `sendMessage('B')` → expect repo's recorded send order `[A, B]` (A retried by the flush before B) or at least that B is enqueued behind A.

### RC-16 — Over-limit paste is silently discarded
- Covers: 01 M-1.
- Verdict: CONFIRMED.
- Corrected severity: Medium (text loss without feedback; rare input).
- Evidence: SCR:719 `_controller.clear()` runs before `sendMessage`; `sendMessage` CS:687 returns silently when `!Message.isValidContent(content)` (`message.dart:13, 585-588`, 10,000 runes); no `maxLength`/`inputFormatters` in `chat_text_field.dart` or SCR (grep empty).
- Minimal fix: `_sendDraftText`: `if (!Message.isValidContent(trimmed)) { show SnackBar/inline "Message is too long (max 10,000 characters)"; return; }` before clearing; add `LengthLimitingTextInputFormatter(Message.maxContentRunes)` to the composer.
- Test (widget): enter 10,001 chars; tap send; expect composer text unchanged and the error visible; `repo.sendCallCount == 0`.

## Refuted / downgraded

- 03 M-6 timing — downgraded detail, not verdict: the fifth failure lands after ~15-30 s (windows 1-2, 2-4, 4-8, 8-16 s), not "60-120 s". Same root cause as 01 H-1 (RC-2).
- 05 H-3 (Starred never refreshes) — confirmed but downgraded High → Medium: secondary screen, no data loss, restart heals.
- 02 M-2 ("delivered only on foreground") — partly corrected: the server does stamp delivered when it suppresses the push for an actively-viewing recipient (index.ts:221-233); the gap is only the push-delivered-but-app-not-opened case. Severity stays Medium.
- 02 M-5 / 05 M-1 content jump — not refuted, but unverified; only the missing affordance is confirmed. Keep Medium.
- 02 H-1 request counts — the "~30 requests per event" arithmetic is plausible but derived; the amplification chain (self-listen on the bump, inbox channel teardown on recompute, undebounced inbox stream, per-insert `relationships` UPDATE) is confirmed in code/DB. Severity High stands on H-2's latency/fragility even if the exact numbers are lower.
- 01 H-3 — confirmed, but note the partial self-heal: the outbox row is left at `sending`, which `flushOutbox` does not skip, so once RC-1 adds reconnect flushes the message recovers on the next event; `isSending` still sticks and the error is still unhandled, so the fix is still required.
- 01 H-2 — confirmed; practical severity drops to Medium once RC-1's reconnect/connectivity flushes exist, because any later flush picks the stranded item up.
- Nothing in the verified set was fully refuted. No existing test covers any confirmed item, so none of them is protected against regression today.

## Priority for the pre-test fix pass (by user effect, smallest diff first)
1. RC-1 (three ~5-line changes) + RC-2 (one-line condition) — makes offline sends actually send.
2. RC-5 step 1 (reorder + guard the handler, drop the bump) — makes incoming messages fast and not droppable.
3. RC-6 (`_pushFromChat` helper or RouteObserver) — stops false Read + suppressed pushes during games.
4. RC-8 step 1 (`_reconcileWindow`) — removes ghosts before the owner wipes the table; RC-7 migration alongside.
5. RC-4, RC-3, RC-10, RC-16, RC-12 — each ≤ 20 lines.
6. RC-11, RC-13, RC-9, RC-14, RC-15 — larger; schedule after the first device pass.
