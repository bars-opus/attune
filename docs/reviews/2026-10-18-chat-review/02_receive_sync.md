# 02 — Receiving & Sync review

Scope: realtime subscription lifecycle, INSERT/UPDATE/DELETE handling, reconnect/gap-fill, initial load + pagination, ordering, read/delivered receipts (Spec 1a split), typing, presence, unread counts/badges, conversation-list liveness. Read-only; code traced in `lib/features/chat/**`, scratch DB `attune_spec3a`, and the resolved packages `supabase_flutter 2.14.1` / `realtime_client 2.7.3`.

## Summary

The correctness skeleton is solid: one shared channel per relationship, a subscribe-status callback that gap-fills on every (re)subscribe, forward keyset catch-up that pages until the gap is exhausted, merge-by-id-then-clientMessageId, keyset pagination on an indexed `(relationship_id, sort_at, id)`, and read receipts gated on foreground + current route + first frame. I found no path that loses or duplicates a message once the network is up.

What is **not** at WhatsApp level is the *shape* of the receive path. Realtime is used purely as an invalidation ping, and every ping fans out into three independent full refetches (chat handler, conversations-list inbox stream, and a `conversationsRefreshProvider` bump that rebuilds the list notifier *and* tears down/recreates the inbox channel). Each incoming message produces ≥ 6 realtime events per device (INSERT, `relationships.message_count` UPDATE from the insert trigger, safety/analysis/thumbnail worker UPDATEs, `delivered_at` UPDATE, `read_receipt_at` UPDATE), so a 20-message burst turns into hundreds of HTTP requests on *both* phones, and the new bubble is not shown until ~5 sequential unrelated requests finish. Two stuck-state bugs: a cold open while offline aborts `_init` before the outbox flush (queued messages never auto-send that session), and `deactivate()` does not fire when another route is pushed, so read receipts are written while the user is in a game, the media gallery or message info. Pin/reaction *removals* never arrive live because the tables have `REPLICA IDENTITY DEFAULT` and the subscriptions are filtered.

Counts: Critical 0 · High 4 · Medium 7 · Low 6.

## Findings

### H-1: Every incoming message fans out into ~30+ HTTP requests per device (×6 events per message)

- Severity: High (jank, battery, API rate-limit exposure, and seconds-long receive latency on real networks; a 20-message burst is hundreds of requests on each phone)
- Confidence: Confirmed (traced; request counts are derived from code, not measured)
- Evidence:
  - Per-chat handler runs on *every* event after a 250 ms debounce: `lib/features/chat/presentation/state/chat_state.dart:507-531` → `_refreshConversation()` (514) → `_catchUpFromCursor()` (519) → `loadMessages()` (520) → `_markPartnerMessagesDelivered()` (521) → `_refreshPinnedMessages()` (525) → `conversationsRefreshProvider++` (529).
  - `_refreshConversation` → `repository.getConversation()` → `getConversations()` which is **4–5 sequential requests** per relationship: `lib/features/chat/data/repositories/supabase_chat_repository.dart:54-138` (relationships 56, users 80, last message 89, `count_unread_messages` RPC 90, avatar signed URL 111).
  - The bump at 529 is also listened to by the *same* controller: `chat_state.dart:298-300` → `_refreshConversation()` again (another 4–5 requests).
  - The bump rebuilds `ConversationsNotifier.build()` (`chat_state.dart:144` watches it) → `getConversations()` again (165). Rebuild runs the `ref.onDispose` registered in `_subscribeToInbox` (208-212), which cancels the inbox stream → `removeChannel` (`supabase_chat_repository.dart:717-719`), and after the fetch resubscribes (167) → new `inbox:` channel → `subscribed` status emits an event (710-715) → `_refreshInBackground` → `getConversations()` **again** (224). The existing test `test/features/chat/inbox_realtime_test.dart:94` only proves no churn on inbox *events*, not on bumps.
  - The inbox stream itself has **no debounce**: `chat_state.dart:204-206` → one `getConversations()` per raw event.
  - Events per message, each a separate WAL row and therefore a separate realtime event on both devices and on both channels (chat + inbox both subscribe to `messages` and `relationships` for the same id, `supabase_chat_repository.dart:563-584, 672-702`):
    1. `messages` INSERT.
    2. `relationships` UPDATE — the insert trigger `enqueue_message_downstream_work` does `UPDATE public.relationships SET message_count = COALESCE(message_count,0)+1` (trigger `messages_enqueue_downstream_work`, scratch DB). Both channels subscribe to `relationships` UPDATE for the id.
    3. `messages` UPDATE from `process-chat-safety-outbox` (`supabase/functions/process-chat-safety-outbox/index.ts:353,366`).
    4. `messages` UPDATE from `analyse-message` (`index.ts:373`); images also `process-chat-media` (`index.ts:44-45`).
    5. `messages` UPDATE from `mark_delivered` / `mark_relationship_delivered` (per row).
    6. `messages` UPDATE from `mark_conversation_read` when receipts are on (per row).
  - Rough per-event cost while the chat is open: handler chain ≈ 9 requests + bump cascade (list rebuild 5 + inbox resubscribe 5 + controller listen 5) + inbox stream 5 ≈ **~30 requests per event**, so ~150–180 per received message, and the sender pays the same on its own INSERT + receipts.
- Failure scenario: B is in the chat; A sends 20 messages in a minute. B's phone issues on the order of 1,000+ requests, the inbox channel is torn down and rejoined dozens of times, and on a 3G-class link the handler chains queue behind each other so bubbles trickle in seconds late. Supabase per-IP rate limiting or realtime join throttling becomes plausible during manual testing.
- WhatsApp/iMessage expectation: an incoming message costs one push/socket frame and zero extra round trips; receipts are a single tiny write.
- Fix (minimal, in order of payoff):
  1. Stop the self-amplification: in the handler (`chat_state.dart:529`) do **not** bump `conversationsRefreshProvider`; the inbox stream already refreshes the list. Keep the bump only for user-initiated changes (name/avatar edits). Likewise drop the bump after send (`:2012`) and after read (`:2328`) or replace it with a targeted `_refreshInBackground` call on the list notifier that does not rebuild.
  2. In `ConversationsNotifier`, subscribe once outside the rebuild path (don't register `ref.onDispose` inside `_subscribeToInbox`; use a single `onDispose` in `build` guarded by `_subscribedIds`), and debounce `_refreshInBackground` (250–500 ms, trailing).
  3. Split `getConversation(relationshipId)` from `getConversations()`: one query for the relationship + partner, no `_fetchLastMessage`/`count_unread` when called from the chat handler (the chat already has the messages).
  4. Server: remove the per-insert `UPDATE relationships SET message_count` from `enqueue_message_downstream_work` (count on read or move to a non-published table), and consider narrowing the chat channel's `relationships` handler to the columns that matter (or a dedicated `relationship_chat_signals` table). Worker UPDATEs (safety/analysis) should ideally write to side tables, not `messages`, since every one of them re-renders the chat on both phones.

### H-2: New message rendering is gated behind ~5 unrelated sequential requests, and one failure drops the whole gap-fill

- Severity: High (receive latency is the single most-felt chat metric; and a transient failure leaves the message missing until the next event)
- Confidence: Confirmed
- Evidence: handler order `chat_state.dart:514-520` — `await _refreshConversation()` (4–5 sequential requests, `supabase_chat_repository.dart:54-138`) runs **before** `_catchUpFromCursor()` and `loadMessages()`. `_refreshConversation` (`:478-500`) and `getConversation` have no try/catch; the handler closure (`:513`) has none either, so an exception there aborts the Timer callback and skips catch-up, loadMessages, delivered marking and pins for that event. Same in `_init`: `chat_state.dart:373,378` — `await conversationRefresh` rethrows and aborts `_init` (see H-3).
- Failure scenario: (a) Normal network, 150 ms RTT: event → 250 ms debounce → ~5 × 150 ms metadata → catch-up → loadMessages → bubble appears ~1.5 s after the socket frame; on 400 ms RTT it is 3–4 s. (b) A's message arrives while B's connection flaps: `getConversations()` throws, the handler dies, the bubble never shows until another event happens (the partner sends again, or a worker UPDATE lands).
- WhatsApp/iMessage expectation: the bubble appears within ~100–300 ms of the socket frame.
- Fix: in `_subscribeToRealtime`'s handler run `_catchUpFromCursor()` first (it alone restores new rows), then `loadMessages(silent: true)`, and run `_refreshConversation()`/pins **after** and each inside its own try/catch (`ChatLog.e` and continue). Better still, use the INSERT payload (`PostgresChangePayload.newRecord`) to insert the row immediately via `_mergeMessages([Message.fromRow(...)])` and let the fetch reconcile reactions, since `_messageColumns` are all client-selectable.

### H-3: Opening a chat while offline aborts `_init` before the outbox flush; queued messages never auto-send after reconnect

- Severity: High (stuck state / persistence failure in the send→sync hand-off)
- Confidence: Confirmed (by code path; not run on device)
- Evidence: `chat_state.dart:373` creates `_refreshConversation()`; `loadMessages` catches its own error (`:567-581`), but `:378 await conversationRefresh` rethrows the network error, so `:383-403` never run: baseline seed, `_refreshPinnedMessages`, `_refreshStarredMessageIds`, `_markPartnerMessagesDelivered`, and **`flushOutbox()` (:403)**. `flushOutbox` has no other trigger: not called from the realtime handler (`:513-530`), not from the `subscribed` reconnect event, not from `chatConnectivityProvider` (only used for the "Offline" label, `chat_screen.dart:1316`), and `grep flushOutbox lib` shows no caller outside `chat_state.dart`. `_retryTimer` only exists after an attempt *fails* (`:2253-2259`), so restored `queued` items from a previous session (`_restorePendingMessages`, `:2550-2590`) never get an attempt.
- Failure scenario: A types two messages in a tunnel (queued, clock icon), kills the app, reopens it in the tunnel (warm cache paints, `_init` throws on `getConversations`), then gets signal back. Realtime reconnects and *incoming* messages appear, but A's two queued messages sit with the clock icon indefinitely; they only go out if A leaves the chat for > 5 min (controller eviction, `chat_state.dart:246-257`) and comes back, or restarts the app online.
- WhatsApp/iMessage expectation: queued messages send automatically the moment connectivity returns.
- Fix: in `_init` wrap `await conversationRefresh` in try/catch (log, keep going) so `flushOutbox()` always runs; call `unawaited(flushOutbox())` at the end of the realtime handler (a `subscribed` status after reconnect is exactly "network is back"); and listen to `chatConnectivityProvider` false→true in the controller to call `flushOutbox()` + `_catchUpFromCursor()`.

### H-4: `_isViewActive` stays true while another route is on top — read receipts and presence written for a chat nobody is looking at

- Severity: High (receipt accuracy is user-visible — "Read" ticks on messages the partner never saw; presence heartbeat suppresses pushes while the user is elsewhere in the app)
- Confidence: Confirmed (Flutter semantics + code; the comment claiming otherwise is wrong)
- Evidence: `chat_screen.dart:177-193` relies on `deactivate()` firing "on both a pop and a push of another route over this one". `State.deactivate` only fires when the element is removed from the tree; a route pushed on top keeps the previous route mounted (`maintainState: true`), so it does not fire. `_syncViewActive()` (`:221-227`) is only invoked on first frame (174), app lifecycle changes (215), and the two hand-wrapped navigations `_openPulse`/`_openInsights` (1241-1257). All other pushes leave `_isViewActive == true`: image caption/trim/streak camera (`:870, 918, 958`), message-info/jump sub-screens (`:3462, 3490`), and every game screen (`:4273-4371`). While true, each realtime event calls `markAsReadDebounced()` (`chat_state.dart:528`) → `mark_conversation_read`, and the 20 s presence heartbeat keeps running (`:465-471`) so the server believes the user is "Active in this chat" (push suppression, Spec 9.2).
- Failure scenario: B opens Love Map from the chat and plays for 10 minutes. A sends "are you there?" — A's tick goes to Read within a second and A's header shows "Active in this chat"; B never saw the message and also got no push for it.
- WhatsApp/iMessage expectation: a message is marked read only when the conversation view itself is visible.
- Fix: subscribe the screen to a `RouteObserver` (`RouteAware.didPushNext` → `setViewActive(false)`, `didPopNext` → `_syncViewActive()`), or wrap every `context.pushNamed` in `_ChatScreenState` the way `_openPulse` does. Keep `deactivate()` as a backstop.

### M-1: Partner's unpin and reaction removal never arrive live (filtered DELETE events are dropped with `REPLICA IDENTITY DEFAULT`)

- Severity: Medium (stale pin banner / reaction pill until some other event or re-entry)
- Confidence: Likely (Supabase docs: "You can only filter Delete events … if the table has the replica identity set to full"; schema verified)
- Evidence: scratch DB `pg_class.relreplident = 'd'` for `message_pins` and `message_reactions`; both subscriptions are filtered `relationship_id=eq.<id>` (`supabase_chat_repository.dart:585-606`). Unpin is a DELETE (`:1139-1144`); `remove_reaction` is `DELETE FROM public.message_reactions` (scratch DB). The pin/reaction *adds* are INSERT/UPSERT and do arrive.
- Failure scenario: A unpins a message or removes a ❤️. B's banner/pill stays until a message, receipt or worker UPDATE happens to fire the handler, which refetches pins/top-50 (and for reactions only if the message is in the newest 50, see M-3).
- WhatsApp/iMessage expectation: reaction/pin changes are reflected within a second.
- Fix: migration `ALTER TABLE public.message_pins REPLICA IDENTITY FULL; ALTER TABLE public.message_reactions REPLICA IDENTITY FULL;` (tiny tables). Add a SQL contract test asserting `relreplident = 'f'` for both.

### M-2: "Delivered" only happens when the recipient foregrounds the app; no delivery ack from the push path

- Severity: Medium (sender sees a single tick for hours although the partner's phone received the push)
- Confidence: Confirmed
- Evidence: `mark_delivered` is called only from the open chat (`chat_state.dart:2282-2298`) and `mark_relationship_delivered` only from the conversations list fetch (`:129-140`, `:168`, `:227`). No notification-side caller: `grep markDelivered|mark_delivered lib` finds nothing outside chat state/data; OneSignal wiring has only click/foreground listeners (`lib/core/notifications/services/onesignal_service.dart:41,73`). The server deliberately stopped stamping `delivered_at` on push enqueue (comment `chat_state.dart:120-128`).
- Failure scenario: A sends at 09:00; B's phone shows the notification immediately but B doesn't open the app until 13:00. A sees one grey tick for four hours and wonders if it went through.
- WhatsApp/iMessage expectation: double grey tick as soon as the device has the message (background), blue on read.
- Fix: cheapest honest signal — in the OneSignal foreground-will-display listener and in the click listener call `mark_relationship_delivered(relationship_id)` from the payload; on iOS add a Notification Service Extension (or OneSignal's) that calls the RPC with the stored session; or revert to stamping `delivered_at` on *successful push provider acceptance* (not enqueue) in `process-chat-notification-outbox`.

### M-3: UPDATEs to rows outside the newest 50 are never applied in-session

- Severity: Medium (stale ticks/reactions on older messages the user is actually looking at)
- Confidence: Confirmed
- Evidence: the only UPDATE pickup is `loadMessages(silent: true)` → newest `messagePageSize` (50) rows, `chat_state.dart:520, 547-550`; `_catchUpFromCursor` is forward-only by `(sort_at,id)` (`:588-625`) so an edited/reacted/received-receipt row with an old `sort_at` is never refetched. `_mergeMessages` keeps older rows as-is (`:2395-2475`).
- Failure scenario: B was offline; A sent 70 messages; B comes back and reads all → A's handler refetches the top 50 → the 20 oldest of that burst keep showing "delivered" until A reopens the chat. Also: A scrolls back a week and reacts to an old photo; B, viewing the same spot, sees nothing (and with M-1, un-reacts never show).
- WhatsApp/iMessage expectation: every visible row reflects the latest state.
- Fix: use the UPDATE payload (`newRecord`) to patch the matching id in state regardless of position (reactions table events carry `message_id`; refetch just that message), or add a `getMessagesByIds` refresh for loaded rows older than the top page when an UPDATE event arrives.

### M-4: No connectivity-driven resync; a silent network switch leaves missed messages invisible for up to ~35–45 s

- Severity: Medium
- Confidence: Likely
- Evidence: gap-fill is triggered only by channel `subscribed` status (`supabase_chat_repository.dart:636-640`) which, after a dead socket, waits for `realtime_client` to notice (heartbeat 25 s, `constants.dart:6`, + stepped reconnect backoff) then rejoin. `chatConnectivityProvider` (`chat_experience_providers.dart:7-15`) feeds only the "Offline" label. App background→foreground *is* handled by `supabase_flutter` (`supabase.dart:268-306`: disconnect on pause, `connect()` + `forceRejoin()` on resume → `subscribed` → handler), so the gap is the no-lifecycle-change case (Wi-Fi→cellular, elevator, airplane toggle while screen on).
- Failure scenario: B walks out of Wi-Fi range with the chat open; A's next three messages arrive 30–45 s later in one lump although B's phone had data within 2 s.
- WhatsApp/iMessage expectation: resync within 1–3 s of connectivity returning.
- Fix: `ref.listen(chatConnectivityProvider)` in `ChatController` → on false→true call `_catchUpFromCursor()` + `loadMessages(silent: true)` + `flushOutbox()`, and `Supabase.instance.client.realtime.connect()` if `!isConnected`.

### M-5: Message arriving while scrolled up — no "new messages" affordance, and a probable content jump

- Severity: Medium
- Confidence: Possible (device check needed for the jump; the missing pill is Confirmed)
- Evidence: `ListView.builder(reverse: true, …)` at `chat_screen.dart:3298-3300`, no `findChildIndexCallback`, no `center` key; rows keyed by `GlobalKey` (`:3323-3350`). `_scrollToLatest` (`:1230-1239`) is called only for the user's own sends (`:733, 893, 949, 959, 1011, 1129, 1161`), never for arrivals, and there is no "↓ N new messages" pill anywhere in the screen (grep). In a reverse `SliverList` an insertion at index 0 re-bases layout offsets, so when `pixels > 0` the visible content shifts by the new bubble's height.
- Failure scenario: B is reading something from yesterday; A sends a long message — B's viewport shifts and B has no indicator that something new arrived at the bottom (haptic/sound only fire if the view is active, `chat_state.dart:643-648`).
- WhatsApp/iMessage expectation: no jump; a "↓ 1 new message" pill appears; tapping scrolls down.
- Fix: track `pixels > ~200` in the scroll listener, count arrivals via `MessageArrivalTracker`, show a floating pill that calls `_scrollToLatest()`; for the jump use the two-sliver `CustomScrollView(center: key)` pattern (new messages in the sliver above the center, history below) or compensate with `position.correctPixels(pixels + insertedExtent)`.

### M-6: Two devices / one user with receipts off: the other device's unread badge is not updated by a read

- Severity: Medium (by design of Spec 1a, but a visible desync for the owner's own two-device test)
- Confidence: Confirmed
- Evidence: with `seen_receipts_effective() = false`, `mark_conversation_read` writes only `message_reads` + `message_read_marks`, neither published (`supabase/migrations/20261017130200_read_marks_watermark.sql`, comments). The reading device bumps its own list (`chat_state.dart:2328`); the other device gets no event, so its `count_unread_messages` is not refetched until some other event.
- Failure scenario: same account on phone + tablet; read on the phone; tablet's list keeps "3 unread" until the next message/worker UPDATE or a pull-to-refresh.
- WhatsApp/iMessage expectation: linked devices clear the badge immediately.
- Fix: broadcast a tiny per-user "reads changed" event (Realtime Broadcast on `inbox:<uid>`, no DB publication) from the reading device, or put `message_read_marks` in the publication with RLS limited to `reader_id = auth.uid()` (it only carries a timestamp).

### M-7: No unread badge on the Chat tab and no app-icon badge

- Severity: Medium (polish, but it is the first thing a WhatsApp user notices)
- Confidence: Likely (app code confirmed; OneSignal dashboard badge setting not verifiable here)
- Evidence: `HomeTab(id: 'chat', …)` is constructed without `badgeCount` (`lib/home/home_screen.dart:383-395`); `badgeCount` is only rendered in `home_widget.dart:252-254`. No `badge` key anywhere in `supabase/functions` push payloads; no `FlutterAppBadger`/badge plugin in `lib`.
- Failure scenario: a user on the Opinions tab gets no hint that 5 messages arrived; the app icon never shows a count.
- WhatsApp/iMessage expectation: tab and icon badges track the unread total.
- Fix: derive `badgeCount` for the chat tab from `conversationsProvider` (`sum(unreadCount)`), and set `ios_badgeType: 'Increase'`/`ios_badgeCount` in the OneSignal payload built by `send-notification` (clear it on `mark_conversation_read` via a silent push, or on next foreground).

### L-1: `getMessagesAfter(after: null)` pages the *entire* history oldest-first

- Severity: Low (latent; only reached if the catch-up runs before any canonical row is in state)
- Confidence: Confirmed (code), trigger Possible
- Evidence: `supabase_chat_repository.dart:226-233` orders ascending with no upper bound and `:246-253` keeps paging while `rows.length == limit`; the doc comment (`chat_repository.dart:15-18`) promises "newest limit rows". Caller `_catchUpFromCursor` passes `after: null` when `state.messages` has no non-`_local_` row (`chat_state.dart:595-601`). Normally `loadMessages` (one request) wins the race against the `subscribed`-event handler (`_refreshConversation` first), so the path is rarely hit; a reaction `inFilter` over thousands of ids would then fail and the whole catch-up is swallowed (`:622`).
- Fix: when `after == null`, return early (let `loadMessages` own the first page), or fetch newest-`limit` descending and reverse.

### L-2: Cached timestamps are serialized as local time without offset

- Severity: Low
- Confidence: Confirmed
- Evidence: `Message.toJson` writes `createdAt.toIso8601String()` / `sortAt…` of a `.toLocal()` DateTime (`message.dart:401-402, 209, 215`) → no `Z`; `fromJson` parses as local (`:440-444`). The catch-up/pagination cursors are built from cached `sortAt` (`chat_state.dart:599, 662-665`) then `.toUtc()` (`supabase_chat_repository.dart:202, 239`).
- Failure scenario: device time zone changes (travel, DST) between cache write and next cold open → every cached bubble's time and date chip is off by the delta until the server refresh merges; cursor is off by the same delta (extra or, in the forward direction, fewer rows fetched by `_catchUpFromCursor`; `loadMessages` top-50 still corrects).
- Fix: serialize with `toUtc().toIso8601String()` and `.toLocal()` on read.

### L-3: Device clock skew keeps the user's own message out of order for the session

- Severity: Low
- Confidence: Confirmed
- Evidence: optimistic rows use `DateTime.now()` (`chat_state.dart:694, 711`); `_replaceOptimistic` keeps the local slot (`:2487-2517`) and `_mergeMessages` carries `presentationSortAt` forward for every non-game row (`:2411-2417`), so server order is never applied in-session; only a cold open re-sorts by cached `sortAt`.
- Failure scenario: phone clock 90 s fast; A sends "ok", B replies 10 s later — on A's screen B's reply renders *above* A's "ok" until A reopens the chat.
- Fix: after acknowledgement, if `|serverCreatedAt − localCreatedAt| > a few seconds`, adopt the server `sortAt` as `presentationSortAt` (visible move is better than wrong order), or re-sort when a partner row lands between.

### L-4: `hasMore` is recomputed from the top page on every silent refresh

- Severity: Low
- Confidence: Confirmed
- Evidence: `chat_state.dart:556-557` sets `hasMore: messages.length >= pageSize` on every `loadMessages`, including realtime refreshes after the user has already paged to the beginning (`loadMoreMessages` set it false at `:673`). Next scroll to the top issues one extra empty page request (`:3276-3281`).
- Fix: only set `hasMore` when `silent == false` (initial load), or `hasMore: state.hasMore || first load`.

### L-5: Account switch leaves the previous user's chat channel joined

- Severity: Low (privacy hygiene; events are RLS-filtered server-side)
- Confidence: Confirmed
- Evidence: `_handleAccountChange` cancels the Dart subscription but does not `releaseChannel` (`chat_state.dart:2625-2649`); the controller is kept alive up to 5 min (`:246-257`) with the `chat:<rel>` channel still joined under the old relationship filter. `supabase_flutter` re-auths the socket with the new JWT, so the new user's socket is now subscribed to the old user's relationship topic (server RLS stops row delivery, but the join remains).
- Fix: call `await _repository.releaseChannel(relationshipId)` in `_handleAccountChange`.

### L-6: Typing/presence edge: typing broadcast has no app-background guard

- Severity: Low
- Confidence: Confirmed
- Evidence: `TypingController` (`typing_controller.dart`) stops on inactivity (5 s) and the receiver auto-expires after 5 s, so nothing sticks; but backgrounding mid-typing does not send `typing:false` (only `dispose` does, `:117-118`), leaving the partner's indicator for up to 5 s. Cosmetic.
- Fix: in `_ChatScreenState.didChangeAppLifecycleState`, call `typingController.onSent()`-style stop when leaving `resumed`.

## Done well (keep these intact when fixing)

- One shared `RealtimeChannel` per relationship for postgres_changes + typing broadcast, lazily created and released on controller dispose (`supabase_chat_repository.dart:548-654, 822-835`); `Conversation ==` keyed on `relationshipId` prevents duplicate controllers (`conversation.dart`).
- Subscribe-status callback triggers a refetch on every `subscribed`, including after reconnect (`:636-640`); `supabase_flutter 2.14.1` disconnects on pause and `connect()` + `forceRejoin()` on resume, so background→foreground gap-fills without app code.
- Forward keyset catch-up `(sort_at, id)` that pages until fewer than `limit` remain (`getMessagesAfter`), backed by `messages_relationship_sort_idx (relationship_id, sort_at DESC, id DESC)`.
- Merge by canonical id, then dedupe `_local_` rows by `clientMessageId`; incoming server row wins (reactions/edits/deletes survive); ephemeral-expiry local-file sweep (`_mergeMessages`).
- Newest-first ordering by `(presentationSortAt, id)` matching the server; keyset pagination for older pages, never offset.
- Read receipts only when foreground + current route + first frame rendered (`setViewActive`, `_syncViewActive`), inactive/paused lifecycle clears presence and cancels the read debounce; `_markedReadIds` avoids re-calling `mark_conversation_read` while receipts are off (Spec 1a).
- Receipt RPCs update only null timestamps and check `status='active'`, so delivered/read UPDATE events cannot ping-pong forever.
- Spec 1a split is clean: `message_reads`/`message_read_marks` unpublished and ungranted; `read_at` not client-selectable; `read_receipt_at` written only when both partners opt in.
- Typing: 2 s throttle, 5 s inactivity stop, 5 s receiver expiry, self-echo ignored.
- Presence: 20 s heartbeat vs 45 s window, stopped on inactive/dispose; `partner_is_active_in_chat` is membership-checked and boolean-only (no last-seen leak); poll is autoDispose.
- Conversations list: cache-then-refresh, `valueOrNull` so background refreshes never flash; inbox stream keyed on the sorted id set so inbox *events* don't resubscribe.
- Preview text handles deleted/media/streak privately (`conversation_preview.dart`).

## Not verified

- Request counts in H-1 are derived from code, not measured against the live project (no remote access per brief); the pathological numbers assume all workers and receipts fire, which they do by default.
- Riverpod `ref.onDispose`-runs-on-recompute (H-1 inbox-channel churn) is from Riverpod's documented behaviour, not a test in this repo; a unit test bumping `conversationsRefreshProvider` and counting `repo.inboxSubscriptions` would confirm it in 10 lines (harness already has the counter).
- The reverse-`ListView` content jump (M-5) needs a device check; the absence of a new-messages pill is certain.
- Realtime's dropping of filtered DELETE events under `REPLICA IDENTITY DEFAULT` (M-1) is per Supabase docs; not reproduced against the live realtime server.
- OneSignal dashboard badge settings and iOS NSE presence (M-2, M-7) are outside the repo.
- Screen-lock behaviour relies on `AppLifecycleState.inactive/paused` being delivered before the lock (standard on iOS/Android); not device-tested.
- Game-session and story realtime channels were not reviewed except where they share the chat channel.
